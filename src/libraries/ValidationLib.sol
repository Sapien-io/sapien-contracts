// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {ConsensusLib} from "src/libraries/ConsensusLib.sol";
import {ReputationLib} from "src/libraries/ReputationLib.sol";
import {
    EngineStorage,
    Project,
    ProjectStatus,
    Contribution,
    ContributionStatus,
    ValidatorCommit,
    ValidatorConsensusResult,
    ConsensusReport,
    ValidationInput,
    ConsensusResult,
    ValidationCounters,
    ValidationClaim,
    ValidationClaimStatus
} from "src/Types.sol";

/// @title ValidationLib
/// @notice Deployed library for validation commit-reveal and consensus operations.
/// @dev Called via DELEGATECALL from SapienCore; operates on the caller's ERC-7201 storage.
library ValidationLib {
    // keccak256(abi.encode(uint256(keccak256("sapien.storage.SapienCore")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0xb21037e32bd67da4126ec23c3d75228183c819f055709f5aa59aa33cc3fd2b00
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Validator Capacity (renamed from set/reduce to lock/unlock)
    // ════════════════════════════════════════════════════════════════════

    function lockValidatorCapacity(uint256 amount) public {
        _getStorage().vault.lockValidatorCapacity(msg.sender, amount);
    }

    function unlockValidatorCapacity(uint256 amount) public {
        _getStorage().vault.unlockValidatorCapacity(msg.sender, amount);
    }

    // ════════════════════════════════════════════════════════════════════
    // Validation Claims
    // ════════════════════════════════════════════════════════════════════

    function claimToValidate(bytes32 projectId, uint256 quantity) public returns (uint256 claimId) {
        if (quantity == 0) revert ISapienCore.ZeroAmount();

        (uint256[] memory eligible, uint256 assignCount) = _selectEligibleTargets(projectId, quantity);

        EngineStorage storage $ = _getStorage();

        uint256[] memory assigned = new uint256[](assignCount);
        for (uint256 i; i < assignCount; ++i) {
            uint256 idx = eligible[i];
            uint256 nonce = $.submissionNonce[projectId][idx];
            ValidatorCommit storage vc = $.validatorCommits[projectId][idx][nonce][msg.sender];
            vc.claimed = true;
            $.validationCounters[projectId][idx][nonce].claimCount++;
            assigned[i] = idx;
        }

        claimId = $.nextValidationClaimId++;

        for (uint256 k; k < assignCount; ++k) {
            uint256 nonce = $.submissionNonce[projectId][assigned[k]];
            $.validatorCommits[projectId][assigned[k]][nonce][msg.sender].validationClaimId = claimId;
        }
        ValidationClaim storage vclaim = $.validationClaims[claimId];
        vclaim.validator = msg.sender;
        vclaim.projectId = projectId;
        vclaim.indices = assigned;
        vclaim.deadline = block.timestamp + C.VALIDATION_CLAIM_DEADLINE;
        vclaim.totalCount = assignCount;
        vclaim.status = ValidationClaimStatus.Active;

        emit ISapienCore.ValidationClaimCreated(claimId, projectId, msg.sender, assigned);
    }

    function _selectEligibleTargets(bytes32 projectId, uint256 quantity)
        private
        view
        returns (uint256[] memory eligible, uint256 assignCount)
    {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];

        // POQ-8 FIX: Prevent originator from validating their own project
        if (msg.sender == proj.originator) {
            revert ISapienCore.OriginatorCannotValidate();
        }
        // POQ-4: Block validation claims on non-active projects
        if (proj.status != ProjectStatus.Active && proj.status != ProjectStatus.Funded) {
            revert ISapienCore.ProjectNotActive();
        }

        if (proj.minValidatorReputation > 0) {
            uint256 rep = ReputationLib.getScore(msg.sender, proj.requiredSkill);
            if (rep < proj.minValidatorReputation) {
                revert ISapienCore.InsufficientReputation(uint256(proj.minValidatorReputation), rep);
            }
        }

        uint256 eligibleCount;
        {
            uint256[] storage pending = $.pendingIndices[projectId];
            uint256 pendingLen = pending.length;
            eligible = new uint256[](pendingLen);
            for (uint256 i; i < pendingLen; ++i) {
                uint256 idx = pending[i];
                Contribution storage contrib = $.contributions[projectId][idx];
                if (contrib.contributor == msg.sender) continue;
                uint256 nonce = $.submissionNonce[projectId][idx];
                if ($.validatorCommits[projectId][idx][nonce][msg.sender].claimed) continue;
                if ($.validationCounters[projectId][idx][nonce].claimCount >= proj.numberOfValidations) continue;
                eligible[eligibleCount++] = idx;
            }
        }
        if (eligibleCount == 0) revert ISapienCore.NoEligibleContributions();

        assignCount = quantity < eligibleCount ? quantity : eligibleCount;

        // Fisher-Yates partial shuffle — only shuffle first `assignCount` positions.
        // prevrandao is Beacon-Chain RANDAO; a proposer can bias it by at most 1 bit
        // (forfeiting their slot reward), which is economically irrational for
        // validator-assignment manipulation. Commit-reveal + staking provide the
        // real anti-collusion guarantees.
        uint256 seed = uint256(keccak256(abi.encodePacked(block.prevrandao, projectId, msg.sender, block.timestamp)));
        for (uint256 i; i < assignCount; ++i) {
            // slither-disable-next-line weak-prng
            uint256 j = i + (seed % (eligibleCount - i));
            (eligible[i], eligible[j]) = (eligible[j], eligible[i]);
            seed = uint256(keccak256(abi.encodePacked(seed)));
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Validation (Commit-Reveal)
    // ════════════════════════════════════════════════════════════════════

    function commitValidation(
        bytes32 projectId,
        uint256 index,
        bytes32 commitHash,
        uint256 stakeAmount,
        address adapter
    ) public {
        EngineStorage storage $ = _getStorage();

        // POQ-4: Block commits on cancelled/completed projects
        {
            ProjectStatus status = $.projects[projectId].status;
            if (status == ProjectStatus.Cancelled || status == ProjectStatus.Completed) {
                revert ISapienCore.ProjectNotActive();
            }
        }

        uint256 nonce = $.submissionNonce[projectId][index];

        if (commitHash == bytes32(0)) revert ISapienCore.InvalidCommitHash();

        ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][msg.sender];
        if (!vc.claimed) revert ISapienCore.ValidationNotClaimed();
        if (vc.commitHash != bytes32(0)) revert ISapienCore.AlreadyCommitted();
        uint256 vcClaimId = vc.validationClaimId;
        if (vcClaimId == 0) revert ISapienCore.ValidationNotClaimed();

        ValidationClaim storage vclaim = $.validationClaims[vcClaimId];
        if (vclaim.status != ValidationClaimStatus.Active) revert ISapienCore.ClaimDeadlinePassed();
        if (block.timestamp > vclaim.deadline) revert ISapienCore.ClaimDeadlinePassed();

        if (stakeAmount == 0) revert ISapienCore.InsufficientStake(1, 0);
        {
            Project storage proj = $.projects[projectId];
            uint256 minStake = proj.minValidationStake;
            uint256 globalMin = $.minValidationStake;
            if (globalMin > minStake) minStake = globalMin;
            if (stakeAmount < minStake) revert ISapienCore.InsufficientStake(minStake, stakeAmount);
        }

        $.vault.commitStake(msg.sender, stakeAmount);

        vc.commitHash = commitHash;
        vc.commitTimestamp = block.timestamp;
        vc.stakedAmount = stakeAmount;
        vc.adapter = adapter;

        {
            vclaim.committedCount++;
            if (vclaim.committedCount == vclaim.totalCount) {
                vclaim.status = ValidationClaimStatus.Fulfilled;
            }
        }

        emit ISapienCore.ValidationCommitted(projectId, index, msg.sender);
    }

    function batchCommitValidations(
        bytes32 projectId,
        uint256[] calldata indices,
        bytes32[] calldata commitHashes,
        uint256[] calldata stakeAmounts,
        address adapter
    ) public {
        uint256 len = indices.length;
        if (len == 0) revert ISapienCore.ZeroAmount();
        if (len != commitHashes.length || len != stakeAmounts.length) revert ISapienCore.InvalidIndex();

        for (uint256 i; i < len; ++i) {
            commitValidation(projectId, indices[i], commitHashes[i], stakeAmounts[i], adapter);
        }
    }

    function revealValidation(bytes32 projectId, uint256 index, uint256 score, bytes32 salt) public {
        if (score > 10_000) revert ISapienCore.InvalidScore();

        EngineStorage storage $ = _getStorage();

        // POQ-4: Block reveals on cancelled/completed projects
        {
            ProjectStatus status = $.projects[projectId].status;
            if (status == ProjectStatus.Cancelled || status == ProjectStatus.Completed) {
                revert ISapienCore.ProjectNotActive();
            }
        }

        uint256 nonce = $.submissionNonce[projectId][index];

        ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][msg.sender];
        if (vc.commitHash == bytes32(0)) revert ISapienCore.NotCommitted();

        if (vc.revealedAt != 0) revert ISapienCore.AlreadyRevealed();

        // Enforce commit phase completion before allowing reveals
        if (block.timestamp < vc.commitTimestamp + $.commitDeadline) {
            revert ISapienCore.CommitPhaseActive();
        }

        if (block.timestamp > vc.commitTimestamp + $.commitDeadline + $.revealDeadline) {
            revert ISapienCore.RevealWindowClosed();
        }

        // Canonical format: keccak256(abi.encodePacked(uint256 score, bytes32 salt))
        bytes32 expectedHash = keccak256(abi.encodePacked(score, salt));
        if (vc.commitHash != expectedHash) revert ISapienCore.InvalidReveal();

        vc.score = score;
        vc.revealedAt = block.timestamp;

        $.revealedValidators[projectId][index][nonce].push(msg.sender);
        $.validationCounters[projectId][index][nonce].revealCount++;

        emit ISapienCore.ValidationRevealed(projectId, index, msg.sender, score);
    }

    function batchRevealValidations(
        bytes32 projectId,
        uint256[] calldata indices,
        uint256[] calldata scores,
        bytes32[] calldata salts
    ) public {
        uint256 len = indices.length;
        if (len == 0) revert ISapienCore.ZeroAmount();
        if (len != scores.length || len != salts.length) revert ISapienCore.InvalidIndex();

        for (uint256 i; i < len; ++i) {
            revealValidation(projectId, indices[i], scores[i], salts[i]);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Cancel Expired Validation Claim
    // ════════════════════════════════════════════════════════════════════

    function cancelExpiredValidationClaim(uint256 claimId) public {
        EngineStorage storage $ = _getStorage();
        ValidationClaim storage vclaim = $.validationClaims[claimId];

        if (vclaim.status != ValidationClaimStatus.Active) revert ISapienCore.ClaimDeadlineNotPassed();
        if (block.timestamp <= vclaim.deadline) revert ISapienCore.ClaimDeadlineNotPassed();

        uint256 released = 0;
        {
            address validator = vclaim.validator;
            bytes32 projectId = vclaim.projectId;
            uint256 len = vclaim.indices.length;

            for (uint256 i; i < len; ++i) {
                uint256 idx = vclaim.indices[i];
                uint256 nonce = $.submissionNonce[projectId][idx];

                ValidatorCommit storage vc = $.validatorCommits[projectId][idx][nonce][validator];

                // Only release reservations that still belong to this claim and were never committed.
                if (vc.validationClaimId == claimId && vc.commitHash == bytes32(0)) {
                    delete $.validatorCommits[projectId][idx][nonce][validator];

                    ValidationCounters storage counters = $.validationCounters[projectId][idx][nonce];
                    if (counters.claimCount > 0) {
                        counters.claimCount--;
                    }
                    released++;
                }
            }
        }

        vclaim.status = ValidationClaimStatus.Expired;

        if (released > 0) {
            ReputationLib.update(vclaim.validator, $.projects[vclaim.projectId].requiredSkill, false, 0);
        }

        emit ISapienCore.ValidationClaimExpired(claimId, released);
    }

    // ════════════════════════════════════════════════════════════════════
    // Consensus Computation
    // ════════════════════════════════════════════════════════════════════

    function computeConsensus(bytes32 projectId, uint256 index) public {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];

        if (proj.status == ProjectStatus.Cancelled) revert ISapienCore.ProjectNotActive();

        uint256 nonce = $.submissionNonce[projectId][index];

        ConsensusReport storage report = $.consensusReports[projectId][index][nonce];
        if (report.computed) revert ISapienCore.ConsensusAlreadyComputed();

        uint256 reveals_ = $.validationCounters[projectId][index][nonce].revealCount;
        if (reveals_ < proj.numberOfValidations) {
            revert ISapienCore.ConsensusNotReady(reveals_, proj.numberOfValidations);
        }

        ConsensusResult memory result = _buildAndCompute($, projectId, index, nonce, proj.requiredSkill);

        report.weightedAverage = result.weightedAverage;
        report.stdDeviation = result.stdDeviation;
        report.totalAccurateWeight = result.totalAccurateWeight;
        report.nonce = nonce;
        report.wasAccepted = (result.weightedAverage >= proj.consensusThreshold);
        report.unsettledValidators = result.validators.length;

        for (uint256 i; i < result.validators.length; ++i) {
            address v = result.validators[i];
            ValidatorConsensusResult storage vcr = $.validatorConsensus[projectId][index][nonce][v];
            vcr.isOutlier = result.isOutlier[i];
            vcr.slashAmount = result.slashAmounts[i];
            vcr.weight = result.weights[i];
        }

        Contribution storage contrib = $.contributions[projectId][index];
        contrib.consensusNonce = nonce;
        _removePendingIndex($, projectId, index);
        ContributionStatus newStatus;

        uint256 challengePeriod_ = $.challengePeriod;

        if (result.weightedAverage >= proj.consensusThreshold) {
            report.computed = true;
            newStatus = ContributionStatus.Accepted;
            contrib.status = ContributionStatus.Accepted;
            contrib.challengeEndsAt = block.timestamp + challengePeriod_;

            // POQ-8 FIX: Track accepted contributions
            proj.acceptedContributions++;

            // POQ-15 FIX: Reserve contributor liability at consensus time
            uint256 contributorShare = Math.mulDiv(contrib.rewardRate, C.BPS - proj.validatorRewardBps, C.BPS);
            $.contributorLiability[projectId][index] = contributorShare;
            $.unsettledContributorRewards[projectId]++;

            uint256 qualityBonus = (result.weightedAverage * 20) / C.BPS;
            ReputationLib.update(contrib.contributor, proj.requiredSkill, true, qualityBonus);

            uint256 minStake = proj.minStakeToClaim;
            if (minStake > 0) {
                $.vault.unlockContributor(contrib.contributor, minStake);
            }
        } else {
            report.computed = true;
            newStatus = ContributionStatus.Rejected;
            contrib.status = ContributionStatus.Rejected;
            contrib.challengeEndsAt = block.timestamp + challengePeriod_;

            $.pendingContributions[projectId]--;

            $.submissionNonce[projectId][index]++;

            uint256 rsTop = $.returnStackTop[projectId];
            $.returnStack[projectId][rsTop] = index;
            $.returnStackTop[projectId] = rsTop + 1;
            proj.availableSlots++;

            ReputationLib.update(contrib.contributor, proj.requiredSkill, false, 0);

            uint256 minStake = proj.minStakeToClaim;
            if (minStake > 0) {
                $.vault.slashContributor(contrib.contributor, minStake);
            }
        }

        emit ISapienCore.ConsensusReached(projectId, index, result.weightedAverage, newStatus);
    }

    // ════════════════════════════════════════════════════════════════════
    // Internal Helpers
    // ════════════════════════════════════════════════════════════════════

    function _removePendingIndex(EngineStorage storage $, bytes32 projectId, uint256 idx) internal {
        uint256 pos = $.pendingIndexPos[projectId][idx];
        if (pos == 0) return;
        pos--;
        uint256[] storage arr = $.pendingIndices[projectId];
        uint256 last = arr[arr.length - 1];
        arr[pos] = last;
        $.pendingIndexPos[projectId][last] = pos + 1;
        arr.pop();
        delete $.pendingIndexPos[projectId][idx];
    }

    function _buildAndCompute(
        EngineStorage storage $,
        bytes32 projectId,
        uint256 index,
        uint256 nonce,
        bytes32 requiredSkill
    ) internal view returns (ConsensusResult memory) {
        address[] storage validators = $.revealedValidators[projectId][index][nonce];
        uint256 n = validators.length;
        ValidationInput[] memory inputs = new ValidationInput[](n);

        uint256 cachedDecayBps = $.decayRateBps;

        for (uint256 i; i < n; ++i) {
            address validator = validators[i];
            ValidatorCommit storage vc_ = $.validatorCommits[projectId][index][nonce][validator];
            uint256 rep = ReputationLib.getScoreCached(validator, requiredSkill, cachedDecayBps);
            inputs[i] = ValidationInput({
                validator: validator, score: vc_.score, stakeAmount: vc_.stakedAmount, reputation: rep
            });
        }

        return ConsensusLib.calculate(inputs);
    }
}
