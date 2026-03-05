// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
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

library FinalizationLib {
    using SafeERC20 for IERC20;

    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0xb21037e32bd67da4126ec23c3d75228183c819f055709f5aa59aa33cc3fd2b00
        }
    }

    function settleValidator(bytes32 projectId, uint256 index, uint256 nonce) public {
        _settleValidatorFor(projectId, index, nonce, msg.sender);
    }

    function forceSettleValidator(bytes32 projectId, uint256 index, uint256 nonce, address validator) public {
        EngineStorage storage $ = _getStorage();
        ConsensusReport storage report = $.consensusReports[projectId][index][nonce];
        if (!report.computed) revert ISapienCore.ConsensusNotReady(0, 1);

        ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][validator];
        if (vc.revealedAt == 0) revert ISapienCore.NotCommitted();
        if (block.timestamp <= uint256(vc.revealedAt) + $.forceSettleDelay) {
            revert ISapienCore.ForceSettleTooEarly();
        }

        _settleValidatorFor(projectId, index, nonce, validator);
    }

    function releaseValidatorOnCancelledProject(bytes32 projectId, uint256 index, uint256 nonce, address validator)
        public
    {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];
        if (proj.status != ProjectStatus.Cancelled) revert ISapienCore.ProjectNotCancelled();

        ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][validator];
        if (vc.settled) revert ISapienCore.AlreadySettled();
        if (vc.stakedAmount == 0) revert ISapienCore.NotCommitted();

        vc.settled = true;
        uint256 stake = vc.stakedAmount;
        if (stake > 0) {
            $.vault.releaseCommit(validator, stake);
        }

        emit ISapienCore.ValidatorSettled(projectId, index, validator, false);
    }

    function _settleValidatorFor(bytes32 projectId, uint256 index, uint256 nonce, address validator) internal {
        EngineStorage storage $ = _getStorage();

        Project storage proj = $.projects[projectId];
        if (proj.status == ProjectStatus.Cancelled) revert ISapienCore.ProjectNotActive();

        ConsensusReport storage report = $.consensusReports[projectId][index][nonce];
        if (!report.computed) revert ISapienCore.ConsensusNotReady(0, 1);

        uint256 committedStake;
        address validationAdapter;
        {
            ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][validator];

            if (vc.settled) revert ISapienCore.AlreadySettled();
            if (vc.revealedAt == 0) revert ISapienCore.NotCommitted();

            vc.settled = true;
            committedStake = vc.stakedAmount;
            validationAdapter = vc.adapter;
        }

        Contribution storage contrib = $.contributions[projectId][index];
        ValidatorConsensusResult storage vcr = $.validatorConsensus[projectId][index][nonce][validator];
        bool outlier = vcr.isOutlier;

        if (outlier) {
            uint256 slashAmt = vcr.slashAmount;
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
            ReputationLib.update(validator, proj.requiredSkill, false, 0);
        } else {
            if (committedStake > 0) {
                $.vault.releaseCommit(validator, committedStake);
            }

            if (contrib.status == ContributionStatus.Accepted) {
                Dispute storage dispute = $.disputes[projectId][index][nonce];

                if (dispute.status == DisputeStatus.Open) revert ISapienCore.DisputeInProgress();

                if (dispute.status != DisputeStatus.Upheld) {
                    if (block.timestamp < contrib.challengeEndsAt) revert ISapienCore.ChallengeNotElapsed();

                    uint256 weight = vcr.weight;
                    uint256 totalAccWeight = report.totalAccurateWeight;

                    if (totalAccWeight > 0 && weight > 0) {
                        uint256 validatorShare = Math.mulDiv(
                            proj.totalRewards * proj.validatorRewardBps * weight,
                            1,
                            C.BPS * uint256(proj.totalQuantity) * totalAccWeight
                        );

                        uint256 availableEscrow = $.projectEscrow[projectId][proj.rewardToken];
                        uint256 actualValidatorShare =
                            validatorShare > availableEscrow ? availableEscrow : validatorShare;
                        uint256 reward = actualValidatorShare;

                        if (validationAdapter != address(0) && $.validationFeeBps > 0) {
                            uint256 fee = (actualValidatorShare * $.validationFeeBps) / C.BPS;
                            $.pendingRewards[validationAdapter][proj.rewardToken] += fee;
                            reward -= fee;
                            emit ISapienCore.ValidationAdapterFeePaid(projectId, index, validationAdapter, fee);
                        }

                        $.pendingRewards[validator][proj.rewardToken] += reward;
                        $.projectEscrow[projectId][proj.rewardToken] -= actualValidatorShare;
                    }
                }
            }
            ReputationLib.update(validator, proj.requiredSkill, true, 0);
        }

        emit ISapienCore.ValidatorSettled(projectId, index, validator, outlier);
    }

    function releaseContributorReward(bytes32 projectId, uint256 index) public {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];

        if (proj.status == ProjectStatus.Cancelled) revert ISapienCore.ProjectNotActive();

        Contribution storage contrib = $.contributions[projectId][index];

        if (contrib.status != ContributionStatus.Accepted) revert ISapienCore.ContributionNotAccepted();
        if (block.timestamp < contrib.challengeEndsAt) revert ISapienCore.ChallengeNotElapsed();
        if (contrib.rewardReleased) revert ISapienCore.RewardAlreadyReleased();

        uint256 nonce = contrib.consensusNonce;
        Dispute storage dispute = $.disputes[projectId][index][nonce];
        if (dispute.status == DisputeStatus.Open) revert ISapienCore.DisputeInProgress();
        if (dispute.status == DisputeStatus.Upheld) revert ISapienCore.DisputeInProgress();

        contrib.rewardReleased = true;

        address token = proj.rewardToken;

        uint256 contributorShare = Math.mulDiv(contrib.rewardRate, C.BPS - uint256(proj.validatorRewardBps), C.BPS);

        uint256 availableEscrow = $.projectEscrow[projectId][token];
        uint256 actualContributorShare = contributorShare > availableEscrow ? availableEscrow : contributorShare;
        uint256 reward = actualContributorShare;

        address adapter = $.contributionAdapter[contrib.claimId];
        if (adapter != address(0) && $.contributionFeeBps > 0) {
            uint256 fee = Math.mulDiv(actualContributorShare, $.contributionFeeBps, C.BPS);
            $.pendingRewards[adapter][token] += fee;
            reward -= fee;
            emit ISapienCore.ContributionAdapterFeePaid(projectId, index, adapter, fee);
        }

        $.pendingRewards[contrib.contributor][token] += reward;
        $.projectEscrow[projectId][token] -= actualContributorShare;

        $.pendingContributions[projectId]--;

        emit ISapienCore.ContributorRewardReleased(projectId, index, contrib.contributor, reward);
    }

    function claimReward(address token) public {
        EngineStorage storage $ = _getStorage();
        uint256 amount = $.pendingRewards[msg.sender][token];
        if (amount == 0) revert ISapienCore.NoRewardToClaim();

        if ($.minClaimAmount > 0 && amount < $.minClaimAmount) {
            revert ISapienCore.ClaimAmountTooSmall(amount, $.minClaimAmount);
        }

        if ($.claimCooldown > 0) {
            uint256 lastClaim = $.lastClaimTime[msg.sender];
            if (lastClaim > 0 && block.timestamp < lastClaim + $.claimCooldown) {
                revert ISapienCore.ClaimCooldownActive(block.timestamp, lastClaim + $.claimCooldown);
            }
            $.lastClaimTime[msg.sender] = block.timestamp;
        }

        $.pendingRewards[msg.sender][token] = 0;
        IERC20(token).safeTransfer(msg.sender, amount);

        emit ISapienCore.RewardClaimed(msg.sender, token, amount);
    }

    function cancelExpiredCommitment(bytes32 projectId, uint256 index, address validator) public {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.submissionNonce[projectId][index];

        ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][validator];
        if (vc.commitTimestamp == 0) revert ISapienCore.NotCommitted();
        if (vc.revealedAt != 0) revert ISapienCore.AlreadyRevealed();

        if (block.timestamp <= uint256(vc.commitTimestamp) + $.commitDeadline + $.revealDeadline) {
            revert ISapienCore.ClaimDeadlineNotPassed();
        }

        uint256 committedStake = vc.stakedAmount;
        if (committedStake > 0) {
            $.vault.slashValidator(validator, committedStake);
        }

        delete $.validatorCommits[projectId][index][nonce][validator];

        if ($.validationCounters[projectId][index][nonce].claimCount > 0) {
            $.validationCounters[projectId][index][nonce].claimCount--;
        }
        if ($.validationCounters[projectId][index][nonce].commitCount > 0) {
            $.validationCounters[projectId][index][nonce].commitCount--;
        }

        ReputationLib.update(validator, $.projects[projectId].requiredSkill, false, 0);

        emit ISapienCore.ValidatorCommitmentExpired(projectId, index, validator);
    }

    function completeProject(bytes32 projectId) public {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];
        if (proj.originator != msg.sender) revert ISapienCore.NotProjectOriginator();
        if (proj.status != ProjectStatus.Active && proj.status != ProjectStatus.Funded) {
            revert ISapienCore.ProjectNotActive();
        }

        if ($.pendingContributions[projectId] > 0) revert ISapienCore.ProjectHasActivePipeline();

        proj.status = ProjectStatus.Completed;
        proj.completedAt = uint48(block.timestamp);

        uint256 originatorStake = $.originatorLockedStake[projectId];
        if (originatorStake > 0) {
            $.vault.unlockContributor(proj.originator, originatorStake);
            $.originatorLockedStake[projectId] = 0;
        }

        emit ISapienCore.ProjectCompleted(projectId);
    }

    function refundEscrow(bytes32 projectId) public {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];
        if (proj.originator != msg.sender) revert ISapienCore.NotProjectOriginator();
        if (proj.status == ProjectStatus.Completed) {
            if (block.timestamp < uint256(proj.completedAt) + C.PROJECT_COMPLETION_DELAY) {
                revert ISapienCore.ChallengeNotElapsed();
            }
        } else if (proj.status == ProjectStatus.Cancelled) {
            if (block.timestamp < uint256(proj.cancelledAt) + C.PROJECT_COMPLETION_DELAY) {
                revert ISapienCore.ChallengeNotElapsed();
            }
        } else {
            revert ISapienCore.ProjectNotCompleted();
        }

        address token = proj.rewardToken;
        uint256 remaining = $.projectEscrow[projectId][token];
        if (remaining == 0) revert ISapienCore.ZeroAmount();

        $.projectEscrow[projectId][token] = 0;
        IERC20(token).safeTransfer(proj.originator, remaining);

        emit ISapienCore.EscrowRefunded(projectId, remaining);
    }
}
