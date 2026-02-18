// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Constants as C} from "src/Constants.sol";
import {IQualityEngine} from "src/interfaces/IQualityEngine.sol";
import {ReputationLib} from "src/libraries/ReputationLib.sol";
import {EngineStorage, Project, ProjectStatus, IndexRange} from "src/Types.sol";

/// @title OriginationLib
/// @notice Deployed library for project creation and funding operations.
/// @dev Called via DELEGATECALL from QualityEngine; operates on the caller's ERC-7201 storage.
library OriginationLib {
    using SafeERC20 for IERC20;

    // keccak256(abi.encode(uint256(keccak256("sapien.storage.QualityEngine")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0x93ae96f70dc96ca851a79b6bf630e034298e11be62b3174b3a3408302fc00900
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Project Management
    // ════════════════════════════════════════════════════════════════════

    /// @notice Create a new project with the given configuration.
    function createProject(bytes32 projectId, Project calldata config) public {
        EngineStorage storage $ = _getStorage();
        if ($.projects[projectId].originator != address(0)) {
            revert IQualityEngine.InvalidProjectConfig("project already exists");
        }
        // SEC-L-01: reject mismatched originator instead of silently overwriting
        if (config.originator != address(0) && config.originator != msg.sender) {
            revert IQualityEngine.InvalidProjectConfig("originator must be msg.sender or zero");
        }
        if (config.rewardToken == address(0)) revert IQualityEngine.ZeroAddress();
        if (config.consensusThreshold == 0 || config.consensusThreshold > uint16(C.BPS)) {
            revert IQualityEngine.InvalidProjectConfig("consensusThreshold out of range");
        }
        if (config.validatorRewardBps > uint16(C.MAX_VALIDATOR_REWARD_BPS)) {
            revert IQualityEngine.InvalidProjectConfig("validatorRewardBps too high");
        }
        if (config.numberOfValidations == 0 || config.numberOfValidations > C.MAX_NUMBER_OF_VALIDATIONS) {
            revert IQualityEngine.InvalidProjectConfig("numberOfValidations out of range");
        }

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

        emit IQualityEngine.ProjectCreated(projectId, msg.sender);
    }

    /// @notice Fund a project with reward tokens and allocate contribution slots.
    function fundProject(bytes32 projectId, uint256 amount, uint256 quantity, address adapter) public {
        if (amount == 0) revert IQualityEngine.ZeroAmount();
        if (quantity == 0) revert IQualityEngine.InvalidProjectConfig("quantity must be > 0");

        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];
        if (proj.originator != msg.sender) revert IQualityEngine.NotProjectOriginator();
        if (proj.status != ProjectStatus.Created && proj.status != ProjectStatus.Funded) {
            revert IQualityEngine.InvalidProjectConfig("project not in fundable state");
        }

        address token = proj.rewardToken;

        { // Lock originator stake if required
            uint256 originatorStakeReq = $.originatorStakeRequirement;
            if (originatorStakeReq > 0) {
                uint256 stakeNeeded = originatorStakeReq * quantity;
                $.vault.lockContributor(msg.sender, stakeNeeded);
                $.originatorLockedStake[projectId] += stakeNeeded;
            }
        }

        uint256 remaining;
        { // M-02: Measure actual received to handle fee-on-transfer tokens
            uint256 balBefore = IERC20(token).balanceOf(address(this));
            IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
            uint256 received = IERC20(token).balanceOf(address(this)) - balBefore;

            // Deduct protocol fee (based on actual received, not requested amount)
            uint256 protocolFee = (received * $.protocolFeeBps) / C.BPS;
            if (protocolFee > 0) {
                IERC20(token).safeTransfer($.treasury, protocolFee);
            }
            remaining = received - protocolFee;
        }

        { // Deduct origination adapter fee
            if (adapter != address(0) && $.originationFeeBps > 0) {
                uint256 originationFee = (remaining * $.originationFeeBps) / C.BPS;
                $.pendingRewards[adapter][token] += originationFee;
                $.originationAdapter[projectId] = adapter;
                remaining -= originationFee;
                emit IQualityEngine.OriginationFeePaid(projectId, adapter, originationFee);
            }
        }

        // Credit project escrow
        $.projectEscrow[projectId][token] += remaining;
        proj.totalRewards += remaining;
        proj.totalQuantity += quantity;
        proj.availableSlots += quantity;
        proj.status = ProjectStatus.Funded;

        { // Extend range for sequential index allocation — O(1) instead of O(n)
            uint256 existingTotal = proj.totalQuantity - quantity;
            IndexRange storage range = $.indexRange[projectId];
            if (range.count == 0) {
                range.start = uint128(existingTotal);
            }
            range.count += uint128(quantity);
        }

        emit IQualityEngine.ProjectFunded(projectId, remaining, quantity);
    }
}
