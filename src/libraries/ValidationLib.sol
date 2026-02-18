// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Constants as C} from "src/Constants.sol";
import {IQualityEngine} from "src/interfaces/IQualityEngine.sol";
import {ConsensusLib} from "src/libraries/ConsensusLib.sol";
import {ReputationLib} from "src/libraries/ReputationLib.sol";
import {
    EngineStorage,
    Project,
    Contribution,
    ContributionStatus,
    SubmissionStatus,
    ValidatorCommit,
    ValidatorConsensusResult,
    ConsensusReport,
    ValidationInput,
    ConsensusResult,
    ValidationCounters
} from "src/Types.sol";

/// @title ValidationLib
/// @notice Deployed library for validation commit-reveal and consensus operations.
/// @dev Called via DELEGATECALL from QualityEngine; operates on the caller's ERC-7201 storage.
library ValidationLib {
    // keccak256(abi.encode(uint256(keccak256("sapien.storage.QualityEngine")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0x93ae96f70dc96ca851a79b6bf630e034298e11be62b3174b3a3408302fc00900
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Validator Capacity
    // ════════════════════════════════════════════════════════════════════

    /// @notice Lock validator capacity stake.
    function setValidatorCapacity(uint256 amount) public {
        _getStorage().vault.lockValidatorCapacity(msg.sender, amount);
    }

    /// @notice Reduce committed validator capacity and unlock stake.
    function reduceValidatorCapacity(uint256 amount) public {
        _getStorage().vault.unlockValidatorCapacity(msg.sender, amount);
    }

    // ════════════════════════════════════════════════════════════════════
    // Validation (Commit-Reveal)
    // ════════════════════════════════════════════════════════════════════

    /// @notice Commit a validation score hash for a pending contribution.
    function commitValidation(bytes32 projectId, uint256 index, bytes32 commitHash, uint128 stakeAmount) public {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];
        Contribution storage contrib = $.contributions[projectId][index];

        // Verify contribution exists and is pending
        if (contrib.status != ContributionStatus.Pending) revert IQualityEngine.IndexNotSubmitted();
        if (contrib.contributor == msg.sender) revert IQualityEngine.CannotValidateOwnContribution();

        // Check reputation gate
        if (proj.minValidatorReputation > 0) {
            bytes32 skill = proj.requiredSkill;
            uint256 rep = ReputationLib.getScore(msg.sender, skill != bytes32(0) ? skill : C.VALIDATOR_ROLE_KEY);
            if (rep < proj.minValidatorReputation) {
                revert IQualityEngine.InsufficientReputation(uint256(proj.minValidatorReputation), rep);
            }
        }

        uint256 nonce = $.submissionNonce[projectId][index];

        // C-03: Reject bytes32(0) commit hash to prevent DoS via duplicate-commit bypass
        if (commitHash == bytes32(0)) revert IQualityEngine.InvalidCommitHash();

        // Verify not already committed for this nonce
        ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][msg.sender];
        if (vc.commitHash != bytes32(0)) revert IQualityEngine.AlreadyCommitted();

        // Verify we haven't exceeded the required number of validations
        ValidationCounters storage counters = $.validationCounters[projectId][index][nonce];
        uint256 claimCount = uint256(counters.claimCount);
        if (claimCount >= proj.numberOfValidations) {
            revert IQualityEngine.ConsensusNotReady(claimCount, uint256(proj.numberOfValidations));
        }

        // H-05: Enforce minimum validation stake (max of global and per-project)
        // RISK-007: Reject zero-stake — zero-stake validators get weight=1 in ConsensusLib
        if (stakeAmount == 0) revert IQualityEngine.InsufficientStake(1, 0);
        {
            uint256 minStake = proj.minValidationStake;
            uint256 globalMin = $.minValidationStake;
            if (globalMin > minStake) minStake = globalMin;
            if (stakeAmount < minStake) revert IQualityEngine.InsufficientStake(minStake, stakeAmount);
        }

        // Lock stake from validator capacity to in-flight
        if (stakeAmount > 0) {
            $.vault.commitStake(msg.sender, stakeAmount);
        }

        // Store commit (single struct write replaces 5 separate mapping writes)
        vc.commitHash = commitHash;
        vc.commitTimestamp = uint64(block.timestamp);
        vc.stakedAmount = stakeAmount;
        vc.claimed = true;
        counters.claimCount++;

        emit IQualityEngine.ValidationCommitted(projectId, index, msg.sender);
    }

    /// @notice Reveal a previously committed validation score.
    function revealValidation(bytes32 projectId, uint256 index, uint16 score, bytes32 salt) public {
        if (score > 10_000) revert IQualityEngine.InvalidScore();

        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.submissionNonce[projectId][index];

        // Verify commit exists (single mapping lookup)
        ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][msg.sender];
        if (vc.commitHash == bytes32(0)) revert IQualityEngine.NotCommitted();

        // Verify not already revealed
        if (vc.revealedAt != 0) revert IQualityEngine.AlreadyRevealed();

        // Verify commit hash: keccak256(abi.encodePacked(score, salt))
        bytes32 expectedHash;
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, shl(240, score))
            mstore(add(ptr, 2), salt)
            expectedHash := keccak256(ptr, 34)
        }
        if (vc.commitHash != expectedHash) revert IQualityEngine.InvalidReveal();

        // Store reveal into same struct (stake stays in-flight until settlement)
        vc.score = score;
        vc.revealedAt = uint64(block.timestamp);

        // Track validator in revealed list
        $.revealedValidators[projectId][index][nonce].push(msg.sender);
        $.validationCounters[projectId][index][nonce].revealCount++;

        emit IQualityEngine.ValidationRevealed(projectId, index, msg.sender, score);
    }

    // ════════════════════════════════════════════════════════════════════
    // Consensus Computation
    // ════════════════════════════════════════════════════════════════════

    /// @notice Compute consensus for a contribution's validations.
    function computeConsensus(bytes32 projectId, uint256 index) public {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];
        uint256 nonce = $.submissionNonce[projectId][index];

        // Verify not already computed (RISK-006: report keyed by nonce)
        ConsensusReport storage report = $.consensusReports[projectId][index][nonce];
        if (report.computed) revert IQualityEngine.ConsensusAlreadyComputed();

        // Verify sufficient reveals
        uint256 reveals_ = uint256($.validationCounters[projectId][index][nonce].revealCount);
        if (reveals_ < proj.numberOfValidations) {
            revert IQualityEngine.ConsensusNotReady(reveals_, uint256(proj.numberOfValidations));
        }

        // Compute consensus via extracted helper (reduces stack depth)
        ConsensusResult memory result = _buildAndCompute($, projectId, index, nonce, proj.requiredSkill);

        // Store consensus report (RISK-006: keyed by nonce)
        report.weightedAverage = uint128(result.weightedAverage);
        report.stdDeviation = uint128(result.stdDeviation);
        report.totalAccurateWeight = uint128(result.totalAccurateWeight);
        report.nonce = uint64(nonce);

        // Store per-validator results (RISK-006: keyed by nonce)
        for (uint256 i; i < result.validators.length; ++i) {
            address v = result.validators[i];
            ValidatorConsensusResult storage vcr = $.validatorConsensus[projectId][index][nonce][v];
            vcr.isOutlier = result.isOutlier[i];
            vcr.slashAmount = uint120(result.slashAmounts[i]);
            vcr.weight = uint120(result.weights[i]);
        }

        // Determine contribution outcome
        Contribution storage contrib = $.contributions[projectId][index];
        contrib.consensusNonce = uint64(nonce); // RISK-006: store for dispute/release lookups
        ContributionStatus newStatus;

        if (result.weightedAverage >= proj.consensusThreshold) {
            // Accepted — mark computed only on acceptance (saves SSTORE on rejection path)
            report.computed = true;
            newStatus = ContributionStatus.Accepted;
            contrib.status = ContributionStatus.Accepted;
            contrib.challengeEndsAt = uint64(block.timestamp + C.CHALLENGE_PERIOD);
            $.indexStates[projectId][index].status = SubmissionStatus.Accepted;

            // Reputation boost for contributor (base + quality bonus up to +20)
            uint256 qualityBonus = (result.weightedAverage * 20) / C.BPS;
            ReputationLib.update(contrib.contributor, C.CONTRIBUTOR_ROLE_KEY, true, qualityBonus);

            // Unlock contributor stake for this index
            uint256 minStake = proj.minStakeToClaim;
            if (minStake > 0) {
                $.vault.unlockContributor(contrib.contributor, minStake);
            }
        } else {
            // Rejected — set computed=true so validators can settle (RISK-003 fix)
            report.computed = true;
            newStatus = ContributionStatus.Rejected;
            contrib.status = ContributionStatus.Rejected;
            contrib.challengeEndsAt = uint64(block.timestamp + C.CHALLENGE_PERIOD);
            $.indexStates[projectId][index].status = SubmissionStatus.Empty;

            // Increment nonce to invalidate stale data
            $.submissionNonce[projectId][index]++;

            // Push index to return stack
            uint256 rsTop = $.returnStackTop[projectId];
            $.returnStack[projectId][rsTop] = index;
            $.returnStackTop[projectId] = rsTop + 1;
            proj.availableSlots++;

            // Reputation penalty for contributor
            ReputationLib.update(contrib.contributor, C.CONTRIBUTOR_ROLE_KEY, false, 0);

            // Slash contributor stake for this index
            uint256 minStake = proj.minStakeToClaim;
            if (minStake > 0) {
                $.vault.slashContributor(contrib.contributor, minStake);
            }
        }

        emit IQualityEngine.ConsensusReached(projectId, index, result.weightedAverage, newStatus);
    }

    // ════════════════════════════════════════════════════════════════════
    // Internal Helpers
    // ════════════════════════════════════════════════════════════════════

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

        bytes32 roleKey = requiredSkill;
        if (roleKey == bytes32(0)) roleKey = C.VALIDATOR_ROLE_KEY;
        uint256 cachedDecayBps = uint256($.decayRateBps);

        for (uint256 i; i < n; ++i) {
            address validator = validators[i];
            ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][validator];
            uint256 rep = ReputationLib.getScoreCached(validator, roleKey, cachedDecayBps);
            inputs[i] =
                ValidationInput({validator: validator, score: vc.score, stakeAmount: vc.stakedAmount, reputation: rep});
        }

        return ConsensusLib.calculate(inputs);
    }
}
