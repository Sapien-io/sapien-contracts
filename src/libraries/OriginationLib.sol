// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {ReputationLib} from "src/libraries/ReputationLib.sol";
import {EngineStorage, Project, ProjectStatus, Contribution, ContributionStatus, IndexRange} from "src/Types.sol";

/// @title OriginationLib
/// @notice Deployed library for project creation and funding operations.
/// @dev Called via DELEGATECALL from SapienCore; operates on the caller's ERC-7201 storage.
library OriginationLib {
    using SafeERC20 for IERC20;

    // keccak256(abi.encode(uint256(keccak256("sapien.storage.SapienCore")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0xb21037e32bd67da4126ec23c3d75228183c819f055709f5aa59aa33cc3fd2b00
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Project Management
    // ════════════════════════════════════════════════════════════════════

    function createProject(bytes32 projectId, string calldata metadataCid, Project calldata config) public {
        EngineStorage storage $ = _getStorage();
        if ($.projects[projectId].originator != address(0)) {
            revert ISapienCore.InvalidProjectConfig("project already exists");
        }
        if (config.originator != address(0) && config.originator != msg.sender) {
            revert ISapienCore.InvalidProjectConfig("originator must be msg.sender or zero");
        }
        if (config.rewardToken == address(0)) revert ISapienCore.ZeroAddress();
        if (config.consensusThreshold == 0 || config.consensusThreshold > C.BPS) {
            revert ISapienCore.InvalidProjectConfig("consensusThreshold out of range");
        }
        if (config.validatorRewardBps > C.MAX_VALIDATOR_REWARD_BPS) {
            revert ISapienCore.InvalidProjectConfig("validatorRewardBps too high");
        }
        if (config.numberOfValidations == 0 || config.numberOfValidations > C.MAX_NUMBER_OF_VALIDATIONS) {
            revert ISapienCore.InvalidProjectConfig("numberOfValidations out of range");
        }
        if (config.requiredSkill == bytes32(0)) revert ISapienCore.SkillNotRegistered();
        if (!$.registeredSkills[config.requiredSkill]) revert ISapienCore.SkillNotRegistered();

        Project storage proj = $.projects[projectId];
        proj.originator = msg.sender;
        proj.rewardToken = config.rewardToken;
        proj.consensusThreshold = config.consensusThreshold;
        proj.minStakeToClaim = config.minStakeToClaim;
        proj.validatorRewardBps = config.validatorRewardBps;
        proj.numberOfValidations = config.numberOfValidations;
        proj.requiredSkill = config.requiredSkill;
        proj.minValidatorReputation = config.minValidatorReputation;
        proj.minValidationStake = config.minValidationStake;
        proj.status = ProjectStatus.Created;

        ReputationLib.update(msg.sender, C.ORIGINATOR_ROLE_KEY, true, 0);

        emit ISapienCore.ProjectCreated(projectId, msg.sender, metadataCid);
    }

    function fundProject(bytes32 projectId, uint256 amount, uint256 quantity, address adapter) public {
        if (amount == 0) revert ISapienCore.ZeroAmount();
        if (quantity == 0) revert ISapienCore.InvalidProjectConfig("quantity must be > 0");

        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];
        if (proj.originator != msg.sender) revert ISapienCore.NotProjectOriginator();
        if (proj.status != ProjectStatus.Created && proj.status != ProjectStatus.Funded) {
            revert ISapienCore.InvalidProjectConfig("project not in fundable state");
        }

        address token = proj.rewardToken;

        {
            uint256 originatorStakeReq = $.originatorStakeRequirement;
            if (originatorStakeReq > 0) {
                uint256 stakeNeeded = originatorStakeReq * quantity;
                $.vault.lockContributor(msg.sender, stakeNeeded);
                $.originatorLockedStake[projectId] += stakeNeeded;
            }
        }

        uint256 remaining;
        {
            uint256 balBefore = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            uint256 received = IERC20(token).balanceOf(address(this)) - balBefore;

            uint256 protocolFee = (received * $.protocolFeeBps) / C.BPS;
            if (protocolFee > 0) {
                IERC20(token).safeTransfer($.treasury, protocolFee);
            }
            remaining = received - protocolFee;
        }

        {
            if (adapter != address(0) && $.originationFeeBps > 0) {
                uint256 originationFee = (remaining * $.originationFeeBps) / C.BPS;
                $.pendingRewards[adapter][token] += originationFee;
                $.originationAdapter[projectId] = adapter;
                remaining -= originationFee;
                emit ISapienCore.OriginationFeePaid(projectId, adapter, originationFee);
            }
        }

        $.projectEscrow[projectId][token] += remaining;
        proj.totalRewards += remaining;
        proj.totalQuantity += quantity;
        proj.availableSlots += quantity;
        proj.status = ProjectStatus.Funded;

        {
            uint256 existingTotal = proj.totalQuantity - quantity;
            IndexRange storage range = $.indexRange[projectId];
            if (range.count == 0) {
                range.start = existingTotal;
            }
            range.count += quantity;
        }

        emit ISapienCore.ProjectFunded(projectId, remaining, quantity);
    }

    /// @notice Admin/operator removes a project and slashes the originator for TOS breach.
    /// @dev Processes contributions in batches to avoid gas DoS. Call repeatedly until complete.
    /// @param projectId The project to remove
    /// @param batchSize Maximum number of contributions to process (0 = use default of 50)
    /// @return complete True if all contributions have been processed
    /// @return processed Number of contributions processed in this batch
    function removeProject(bytes32 projectId, uint256 batchSize) public returns (bool complete, uint256 processed) {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];

        if (proj.originator == address(0)) revert ISapienCore.InvalidProjectConfig("project does not exist");
        if (proj.status == ProjectStatus.Cancelled) revert ISapienCore.ProjectNotCancellable();

        // Set default batch size if not specified
        if (batchSize == 0) batchSize = 50;
        // Cap batch size to prevent single-call DoS
        if (batchSize > 100) batchSize = 100;

        // Get or initialize removal cursor
        uint256 cursor = $.removalCursor[projectId];
        uint256 totalQuantity = proj.totalQuantity;
        uint256 stakePerSlot = proj.minStakeToClaim;

        // On first call, slash originator and update reputation
        if (cursor == 0) {
            uint256 originatorStake = $.originatorLockedStake[projectId];
            if (originatorStake > 0) {
                $.vault.slashContributor(proj.originator, originatorStake);
                $.originatorLockedStake[projectId] = 0;
            }
            ReputationLib.update(proj.originator, C.ORIGINATOR_ROLE_KEY, false, 0);
        }

        // Process contributions in batch
        uint256 endIndex = cursor + batchSize;
        if (endIndex > totalQuantity) endIndex = totalQuantity;

        processed = 0;
        for (uint256 i = cursor; i < endIndex; ++i) {
            Contribution storage contrib = $.contributions[projectId][i];
            if (contrib.status == ContributionStatus.Reserved || contrib.status == ContributionStatus.Pending) {
                if (contrib.contributor != address(0) && contrib.claimId != 0) {
                    if (stakePerSlot > 0) {
                        $.vault.unlockContributor(contrib.contributor, stakePerSlot);
                    }
                    contrib.status = ContributionStatus.Empty;
                    contrib.contributor = address(0);
                    contrib.claimId = 0;
                    processed++;
                }
            }
        }

        // Update cursor
        $.removalCursor[projectId] = endIndex;

        // Check if complete
        complete = endIndex >= totalQuantity;

        // If complete, clean up pending indices and mark as cancelled
        if (complete) {
            $.pendingContributions[projectId] = 0;
            {
                uint256[] storage arr = $.pendingIndices[projectId];
                uint256 pLen = arr.length;
                for (uint256 j; j < pLen; ++j) {
                    delete $.pendingIndexPos[projectId][arr[j]];
                }
                delete $.pendingIndices[projectId];
            }

            proj.status = ProjectStatus.Cancelled;
            proj.cancelledAt = block.timestamp;

            // Clean up cursor
            delete $.removalCursor[projectId];

            emit ISapienCore.ProjectRemoved(projectId, msg.sender);
            emit ISapienCore.ProjectCancelled(projectId);
        }

        return (complete, processed);
    }
}
