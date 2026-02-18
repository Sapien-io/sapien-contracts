// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Constants as C} from "src/Constants.sol";
import {IQualityEngine} from "src/interfaces/IQualityEngine.sol";
import {ReputationLib} from "src/libraries/ReputationLib.sol";
import {
    EngineStorage,
    Project,
    ProjectStatus,
    Contribution,
    ContributionStatus,
    ConsensusReport,
    ValidatorCommit,
    ValidatorConsensusResult,
    Dispute,
    DisputeStatus
} from "src/Types.sol";

/// @title FinalizationLib
/// @notice Deployed library for validator settlement and reward release operations.
/// @dev Called via DELEGATECALL from QualityEngine; operates on the caller's ERC-7201 storage.
library FinalizationLib {
    using SafeERC20 for IERC20;

    // keccak256(abi.encode(uint256(keccak256("sapien.storage.QualityEngine")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0x93ae96f70dc96ca851a79b6bf630e034298e11be62b3174b3a3408302fc00900
        }
    }

    /// @notice Settle a validator's outcome for a consensus round.
    /// @param nonce The submission nonce the validator participated in (RISK-006)
    function settleValidator(bytes32 projectId, uint256 index, uint256 nonce) public {
        _settleValidatorFor(projectId, index, nonce, msg.sender);
    }

    /// @notice Permissionless force-settle after FORCE_SETTLE_DELAY (SEC-H-02).
    function forceSettleValidator(bytes32 projectId, uint256 index, uint256 nonce, address validator) public {
        EngineStorage storage $ = _getStorage();
        ConsensusReport storage report = $.consensusReports[projectId][index][nonce];
        if (!report.computed) revert IQualityEngine.ConsensusNotReady(0, 1);

        // Enforce timeout: must wait FORCE_SETTLE_DELAY after the consensus report's nonce was computed.
        // We use the contribution's challengeEndsAt as a proxy for when consensus was computed,
        // but for safety we check the commit timestamp of the validator instead.
        ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][validator];
        if (vc.revealedAt == 0) revert IQualityEngine.NotCommitted();
        if (block.timestamp <= uint256(vc.revealedAt) + C.FORCE_SETTLE_DELAY) {
            revert IQualityEngine.ForceSettleTooEarly();
        }

        _settleValidatorFor(projectId, index, nonce, validator);
    }

    /// @dev Shared settlement logic for both self-settle and force-settle.
    function _settleValidatorFor(bytes32 projectId, uint256 index, uint256 nonce, address validator) internal {
        EngineStorage storage $ = _getStorage();

        ConsensusReport storage report = $.consensusReports[projectId][index][nonce];
        if (!report.computed) revert IQualityEngine.ConsensusNotReady(0, 1);

        uint128 committedStake;
        {
            ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][validator];

            if (vc.settled) revert IQualityEngine.AlreadySettled();
            if (vc.revealedAt == 0) revert IQualityEngine.NotCommitted();

            vc.settled = true;
            committedStake = vc.stakedAmount;
        }

        Project storage proj = $.projects[projectId];
        ValidatorConsensusResult storage vcr = $.validatorConsensus[projectId][index][nonce][validator];
        bool outlier = vcr.isOutlier;

        if (outlier) {
            uint256 slashAmt = uint256(vcr.slashAmount);
            if (slashAmt > 0 && committedStake > 0) {
                uint256 actualSlash = slashAmt > committedStake ? committedStake : slashAmt;
                $.vault.slashValidator(validator, actualSlash);
                uint256 remaining = committedStake - actualSlash;
                if (remaining > 0) {
                    $.vault.releaseCommit(validator, remaining);
                }
            } else if (committedStake > 0) {
                $.vault.releaseCommit(validator, committedStake);
            }
            ReputationLib.update(validator, C.VALIDATOR_ROLE_KEY, false, 0);
        } else {
            if (committedStake > 0) {
                $.vault.releaseCommit(validator, committedStake);
            }

            Contribution storage contrib = $.contributions[projectId][index];
            if (contrib.status == ContributionStatus.Accepted) {
                uint256 weight = uint256(vcr.weight);
                uint256 totalAccWeight = uint256(report.totalAccurateWeight);

                if (totalAccWeight > 0 && weight > 0) {
                    uint256 reward = (proj.totalRewards * uint256(proj.validatorRewardBps) * weight)
                        / (C.BPS * proj.totalQuantity * totalAccWeight);

                    $.pendingRewards[validator][proj.rewardToken] += reward;
                    $.projectEscrow[projectId][proj.rewardToken] -= reward;
                }
            }
            ReputationLib.update(validator, C.VALIDATOR_ROLE_KEY, true, 0);
        }

        emit IQualityEngine.ValidatorSettled(projectId, index, validator, outlier);
    }

    /// @notice Release a contributor's reward after the challenge period.
    function releaseContributorReward(bytes32 projectId, uint256 index) public {
        EngineStorage storage $ = _getStorage();
        Contribution storage contrib = $.contributions[projectId][index];

        if (contrib.status != ContributionStatus.Accepted) revert IQualityEngine.ContributionNotAccepted();
        if (block.timestamp < contrib.challengeEndsAt) revert IQualityEngine.ChallengeNotElapsed();
        if (contrib.rewardReleased) revert IQualityEngine.RewardAlreadyReleased();

        // SEC-C-01: look up dispute at the current contribution's nonce
        uint256 nonce = contrib.consensusNonce;
        Dispute storage dispute = $.disputes[projectId][index][nonce];
        if (dispute.status == DisputeStatus.Open) revert IQualityEngine.DisputeInProgress();
        if (dispute.status == DisputeStatus.Upheld) revert IQualityEngine.DisputeInProgress();

        contrib.rewardReleased = true;

        Project storage proj = $.projects[projectId];
        address token = proj.rewardToken;

        uint256 contributorShare = (contrib.rewardRate * (C.BPS - uint256(proj.validatorRewardBps))) / C.BPS;
        uint256 reward = contributorShare;

        address adapter = $.contributionAdapter[contrib.claimId];
        if (adapter != address(0) && $.contributionFeeBps > 0) {
            uint256 fee = (reward * $.contributionFeeBps) / C.BPS;
            $.pendingRewards[adapter][token] += fee;
            reward -= fee;
            emit IQualityEngine.ContributionAdapterFeePaid(projectId, index, adapter, fee);
        }

        $.pendingRewards[contrib.contributor][token] += reward;
        $.projectEscrow[projectId][token] -= contributorShare;

        // SEC-H-01: decrement pending contributions counter
        $.pendingContributions[projectId]--;

        emit IQualityEngine.ContributorRewardReleased(projectId, index, contrib.contributor, reward);
    }

    /// @notice Claim accumulated rewards for a token.
    function claimReward(address token) public {
        EngineStorage storage $ = _getStorage();
        uint256 amount = $.pendingRewards[msg.sender][token];
        if (amount == 0) revert IQualityEngine.NoRewardToClaim();

        if ($.minClaimAmount > 0 && amount < $.minClaimAmount) {
            revert IQualityEngine.ClaimAmountTooSmall(amount, $.minClaimAmount);
        }

        if ($.claimCooldown > 0) {
            uint64 lastClaim = $.lastClaimTime[msg.sender];
            if (lastClaim > 0 && block.timestamp < lastClaim + $.claimCooldown) {
                revert IQualityEngine.ClaimCooldownActive(block.timestamp, lastClaim + $.claimCooldown);
            }
            $.lastClaimTime[msg.sender] = uint64(block.timestamp);
        }

        $.pendingRewards[msg.sender][token] = 0;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit IQualityEngine.RewardClaimed(msg.sender, token, amount);
    }

    /// @notice Cancel an expired validation commitment and slash the ghost validator.
    function cancelExpiredCommitment(bytes32 projectId, uint256 index, address validator) public {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.submissionNonce[projectId][index];

        ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][validator];
        if (vc.commitTimestamp == 0) revert IQualityEngine.NotCommitted();
        if (vc.revealedAt != 0) revert IQualityEngine.AlreadyRevealed();

        if (block.timestamp <= uint256(vc.commitTimestamp) + C.COMMIT_DEADLINE + C.REVEAL_DEADLINE) {
            revert IQualityEngine.ClaimDeadlineNotPassed();
        }

        uint128 committedStake = vc.stakedAmount;
        if (committedStake > 0) {
            $.vault.slashValidator(validator, committedStake);
        }

        delete $.validatorCommits[projectId][index][nonce][validator];
        $.validationCounters[projectId][index][nonce].claimCount--;

        ReputationLib.update(validator, C.VALIDATOR_ROLE_KEY, false, 0);
    }

    /// @notice Mark a project as Completed.
    function completeProject(bytes32 projectId) public {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];
        if (proj.originator != msg.sender) revert IQualityEngine.NotProjectOriginator();
        if (proj.status != ProjectStatus.Active && proj.status != ProjectStatus.Funded) {
            revert IQualityEngine.ProjectNotActive();
        }

        // SEC-H-01: prevent completion while contributions are in the pipeline
        if ($.pendingContributions[projectId] > 0) revert IQualityEngine.ProjectHasActivePipeline();

        proj.status = ProjectStatus.Completed;
        proj.completedAt = uint64(block.timestamp);

        uint256 originatorStake = $.originatorLockedStake[projectId];
        if (originatorStake > 0) {
            $.vault.unlockContributor(proj.originator, originatorStake);
            $.originatorLockedStake[projectId] = 0;
        }

        emit IQualityEngine.ProjectCompleted(projectId);
    }

    /// @notice Refund remaining escrow to the originator after the completion grace period.
    function refundEscrow(bytes32 projectId) public {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];
        if (proj.originator != msg.sender) revert IQualityEngine.NotProjectOriginator();
        if (proj.status != ProjectStatus.Completed) revert IQualityEngine.ProjectNotCompleted();
        if (block.timestamp < uint256(proj.completedAt) + C.PROJECT_COMPLETION_DELAY) {
            revert IQualityEngine.ChallengeNotElapsed();
        }

        address token = proj.rewardToken;
        uint256 remaining = $.projectEscrow[projectId][token];
        if (remaining == 0) revert IQualityEngine.ZeroAmount();

        $.projectEscrow[projectId][token] = 0;
        IERC20(token).safeTransfer(proj.originator, remaining);

        emit IQualityEngine.EscrowRefunded(projectId, remaining);
    }
}
