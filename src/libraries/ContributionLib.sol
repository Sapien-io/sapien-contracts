// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Constants as C} from "src/Constants.sol";
import {IQualityEngine} from "src/interfaces/IQualityEngine.sol";
import {ReputationLib} from "src/libraries/ReputationLib.sol";
import {
    EngineStorage,
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    IndexState,
    SubmissionStatus,
    Contribution,
    ContributionStatus,
    IndexRange,
    OriginatorReportStatus
} from "src/Types.sol";

/// @title ContributionLib
/// @notice Deployed library for claim and contribution operations.
/// @dev Called via DELEGATECALL from QualityEngine; operates on the caller's ERC-7201 storage.
library ContributionLib {
    // keccak256(abi.encode(uint256(keccak256("sapien.storage.QualityEngine")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0x93ae96f70dc96ca851a79b6bf630e034298e11be62b3174b3a3408302fc00900
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Claim & Contribute
    // ════════════════════════════════════════════════════════════════════

    /// @notice Claim indices for contribution and lock contributor stake.
    function claimToContribute(bytes32 projectId, uint256 quantity, address adapter)
        public
        returns (uint256 claimId, uint256[] memory indices)
    {
        if (quantity == 0) revert IQualityEngine.ZeroAmount();
        if (quantity > C.MAX_CLAIM_QUANTITY) {
            revert IQualityEngine.ClaimQuantityTooHigh(quantity, C.MAX_CLAIM_QUANTITY);
        }

        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];

        if (proj.status != ProjectStatus.Funded && proj.status != ProjectStatus.Active) {
            revert IQualityEngine.ProjectNotActive();
        }
        if (proj.originator == msg.sender) revert IQualityEngine.OriginatorCannotContribute();
        if (proj.availableSlots < quantity) revert IQualityEngine.NoSlotsAvailable();

        // Block claims if an originator report is active
        if ($.originatorReports[projectId].status == OriginatorReportStatus.Open) {
            revert IQualityEngine.DisputeInProgress();
        }

        { // Lock contributor stake
            uint256 stakeRequired = proj.minStakeToClaim * quantity;
            if (stakeRequired > 0) {
                $.vault.lockContributor(msg.sender, stakeRequired);
            }
        }

        // Pop indices: first from return stack (fragmented), then from range
        indices = new uint256[](quantity);
        {
            uint256 filled;
            // 1. Pop from return stack
            uint256 rsTop = $.returnStackTop[projectId];
            while (filled < quantity && rsTop > 0) {
                rsTop--;
                indices[filled] = $.returnStack[projectId][rsTop];
                filled++;
            }
            $.returnStackTop[projectId] = rsTop;

            // 2. Pop from range (O(1) arithmetic)
            if (filled < quantity) {
                uint256 remaining = quantity - filled;
                IndexRange storage range = $.indexRange[projectId];
                uint256 rStart = uint256(range.start);
                uint256 rCount = uint256(range.count);
                for (uint256 i; i < remaining; ++i) {
                    indices[filled + i] = rStart + rCount - remaining + i;
                }
                range.count = uint128(rCount - remaining);
            }
        }

        proj.availableSlots -= quantity;

        { // Create claim
            claimId = $.nextClaimId++;
            Claim storage claim = $.claims[claimId];
            claim.claimant = msg.sender;
            claim.projectId = projectId;
            claim.deadline = uint64(block.timestamp + C.CLAIM_DEADLINE);
            claim.totalCount = uint8(quantity);
            claim.status = ClaimStatus.Active;

            if (adapter != address(0)) {
                $.contributionAdapter[claimId] = adapter;
            }
        }

        { // Mark index states as reserved
            uint64 claimId64 = uint64(claimId);
            for (uint256 i; i < quantity; ++i) {
                IndexState storage idx = $.indexStates[projectId][indices[i]];
                idx.reservedBy = msg.sender;
                idx.claimId = claimId64;
                idx.status = SubmissionStatus.Reserved;
            }
        }

        // Activate project on first claim
        if (proj.status == ProjectStatus.Funded) {
            proj.status = ProjectStatus.Active;
            proj.activatedAt = uint64(block.timestamp);
        }

        emit IQualityEngine.ClaimCreated(claimId, projectId, msg.sender, indices);
    }

    /// @notice Submit a contribution for a claimed index.
    function contribute(uint256 claimId, uint256 index, bytes32 submissionHash) public {
        EngineStorage storage $ = _getStorage();
        Claim storage claim = $.claims[claimId];

        if (claim.claimant != msg.sender) revert IQualityEngine.NotClaimOwner();
        if (claim.status != ClaimStatus.Active) revert IQualityEngine.ClaimDeadlinePassed();
        if (block.timestamp > claim.deadline) revert IQualityEngine.ClaimDeadlinePassed();

        bytes32 projectId = claim.projectId;

        // SEC-M-03: reject contributions to cancelled/completed projects
        Project storage proj = $.projects[projectId];
        if (proj.status != ProjectStatus.Active && proj.status != ProjectStatus.Funded) {
            revert IQualityEngine.ProjectNotActive();
        }

        // Verify index belongs to this claim
        IndexState storage idx = $.indexStates[projectId][index];
        if (idx.claimId != uint64(claimId)) revert IQualityEngine.IndexNotInClaim();
        if (idx.status != SubmissionStatus.Reserved) revert IQualityEngine.IndexNotReserved();

        // Snapshot reward rate: totalRewards / totalQuantity
        uint256 rewardRate = proj.totalRewards / proj.totalQuantity;

        // Store contribution — SEC-C-01: explicitly reset ALL fields to prevent stale state
        // from a previous nonce poisoning the recycled index
        Contribution storage contrib = $.contributions[projectId][index];
        contrib.contributor = msg.sender;
        contrib.submissionHash = submissionHash;
        contrib.rewardRate = rewardRate;
        contrib.submittedAt = uint64(block.timestamp);
        contrib.status = ContributionStatus.Pending;
        contrib.claimId = uint64(claimId);
        contrib.challengeEndsAt = 0;
        contrib.rewardReleased = false;
        contrib.consensusNonce = 0;

        // Update index state (no report reset needed — RISK-006: reports keyed by nonce)
        idx.status = SubmissionStatus.Submitted;

        // SEC-H-01: track in-flight contributions
        $.pendingContributions[projectId]++;

        // Increment submitted count
        claim.submittedCount++;
        if (claim.submittedCount == claim.totalCount) {
            claim.status = ClaimStatus.Completed;
        }

        emit IQualityEngine.ContributionSubmitted(projectId, index, msg.sender, submissionHash);
    }

    /// @notice Expire an overdue claim, return unsubmitted indices, and slash contributor.
    function expireClaim(uint256 claimId, uint256[] calldata indices) public {
        EngineStorage storage $ = _getStorage();
        Claim storage claim = $.claims[claimId];

        if (claim.status != ClaimStatus.Active) revert IQualityEngine.ClaimDeadlineNotPassed();
        if (block.timestamp <= claim.deadline) revert IQualityEngine.ClaimDeadlineNotPassed();

        bytes32 projectId = claim.projectId;
        Project storage proj = $.projects[projectId];
        uint256 unsubmitted;

        // Verify caller-provided indices belong to this claim via IndexState.claimId
        uint64 claimId64 = uint64(claimId);
        uint256 len = indices.length;
        if (len != uint256(claim.totalCount)) revert IQualityEngine.InvalidIndex();

        // Cache returnStackTop to avoid repeated SLOAD/SSTORE per iteration
        uint256 rsTop = $.returnStackTop[projectId];

        for (uint256 i; i < len; ++i) {
            uint256 idx = indices[i];
            IndexState storage idxState = $.indexStates[projectId][idx];
            if (idxState.claimId != claimId64) revert IQualityEngine.IndexNotInClaim();

            if (idxState.status == SubmissionStatus.Reserved) {
                // Push to return stack (only the mapping write per iter)
                $.returnStack[projectId][rsTop] = idx;
                rsTop++;

                // Clear index state
                delete $.indexStates[projectId][idx];
                unsubmitted++;
            }
            // Submitted indices stay in pipeline
        }

        // Write batched updates once (saves (n-1) SSTOREs each)
        $.returnStackTop[projectId] = rsTop;
        proj.availableSlots += unsubmitted;

        // Batch slash + unlock in a single vault call
        uint256 slashAmount = unsubmitted > 0 ? proj.minStakeToClaim * unsubmitted : 0;
        uint256 unlockAmount = uint256(claim.submittedCount) * proj.minStakeToClaim;
        if (slashAmount > 0 || unlockAmount > 0) {
            $.vault.slashAndUnlockContributor(claim.claimant, slashAmount, unlockAmount);
        }

        claim.status = ClaimStatus.Expired;

        // Reputation penalty for incomplete claims
        if (unsubmitted > 0) {
            ReputationLib.update(claim.claimant, C.CONTRIBUTOR_ROLE_KEY, false, 0);
        }

        emit IQualityEngine.ClaimExpired(claimId, unsubmitted);
    }
}
