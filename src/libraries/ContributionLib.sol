// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {ReputationLib} from "src/libraries/ReputationLib.sol";
import {
    EngineStorage,
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    Contribution,
    ContributionStatus,
    IndexRange,
    OriginatorReportStatus
} from "src/Types.sol";

library ContributionLib {
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0xb21037e32bd67da4126ec23c3d75228183c819f055709f5aa59aa33cc3fd2b00
        }
    }

    function claimToContribute(bytes32 projectId, uint256 quantity, address adapter)
        public
        returns (uint256 claimId, uint256[] memory indices)
    {
        if (quantity == 0) revert ISapienCore.ZeroAmount();
        if (quantity > C.MAX_CLAIM_QUANTITY) {
            revert ISapienCore.ClaimQuantityTooHigh(quantity, C.MAX_CLAIM_QUANTITY);
        }

        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];

        if (proj.status != ProjectStatus.Funded && proj.status != ProjectStatus.Active) {
            revert ISapienCore.ProjectNotActive();
        }
        if (proj.originator == msg.sender) revert ISapienCore.OriginatorCannotContribute();
        if (proj.availableSlots < quantity) revert ISapienCore.NoSlotsAvailable();

        if ($.originatorReports[projectId].status == OriginatorReportStatus.Open) {
            revert ISapienCore.DisputeInProgress();
        }

        {
            uint256 stakeRequired = proj.minStakeToClaim * quantity;
            if (stakeRequired > 0) {
                $.vault.lockContributor(msg.sender, stakeRequired);
            }
        }

        indices = new uint256[](quantity);
        {
            uint256 filled = 0;
            uint256 rsTop = $.returnStackTop[projectId];
            while (filled < quantity && rsTop > 0) {
                rsTop--;
                indices[filled] = $.returnStack[projectId][rsTop];
                filled++;
            }
            $.returnStackTop[projectId] = rsTop;

            if (filled < quantity) {
                uint256 remaining = quantity - filled;
                IndexRange storage range = $.indexRange[projectId];
                uint256 rStart = range.start;
                uint256 rCount = range.count;
                for (uint256 i; i < remaining; ++i) {
                    indices[filled + i] = rStart + rCount - remaining + i;
                }
                range.count = uint128(rCount - remaining);
            }
        }

        proj.availableSlots -= uint32(quantity);

        {
            claimId = $.nextClaimId++;
            Claim storage claim = $.claims[claimId];
            claim.claimant = msg.sender;
            claim.projectId = projectId;
            claim.deadline = uint48(block.timestamp + $.claimDeadline);
            claim.totalCount = uint16(quantity);
            claim.status = ClaimStatus.Active;

            if (adapter != address(0)) {
                $.contributionAdapter[claimId] = adapter;
            }
        }

        {
            for (uint256 i; i < quantity; ++i) {
                Contribution storage contrib = $.contributions[projectId][indices[i]];
                contrib.contributor = msg.sender;
                contrib.claimId = uint32(claimId);
                contrib.status = ContributionStatus.Reserved;
                contrib.submissionHash = bytes32(0);
            }
        }

        if (proj.status == ProjectStatus.Funded) {
            proj.status = ProjectStatus.Active;
            proj.activatedAt = uint48(block.timestamp);
        }

        emit ISapienCore.ClaimCreated(claimId, projectId, msg.sender, indices);
    }

    function contribute(uint256 claimId, uint256 index, bytes32 submissionHash, string calldata dataCid) public {
        EngineStorage storage $ = _getStorage();
        Claim storage claim = $.claims[claimId];

        if (claim.claimant != msg.sender) revert ISapienCore.NotClaimOwner();
        if (claim.status != ClaimStatus.Active) revert ISapienCore.ClaimDeadlinePassed();
        if (block.timestamp > claim.deadline) revert ISapienCore.ClaimDeadlinePassed();

        bytes32 projectId = claim.projectId;

        Project storage proj = $.projects[projectId];
        if (proj.status != ProjectStatus.Active && proj.status != ProjectStatus.Funded) {
            revert ISapienCore.ProjectNotActive();
        }

        Contribution storage contrib = $.contributions[projectId][index];
        if (contrib.claimId != uint32(claimId)) revert ISapienCore.IndexNotInClaim();
        if (contrib.status != ContributionStatus.Reserved) revert ISapienCore.IndexNotReserved();

        uint256 rewardRate = proj.totalRewards / proj.totalQuantity;

        contrib.submissionHash = submissionHash;
        contrib.rewardRate = rewardRate;
        contrib.submittedAt = uint48(block.timestamp);
        contrib.status = ContributionStatus.Pending;
        contrib.challengeEndsAt = 0;
        contrib.rewardReleased = false;
        contrib.consensusNonce = 0;

        $.pendingContributions[projectId]++;

        $.pendingIndices[projectId].push(index);
        $.pendingIndexPos[projectId][index] = $.pendingIndices[projectId].length; // 1-indexed

        claim.submittedCount++;
        if (claim.submittedCount == claim.totalCount) {
            claim.status = ClaimStatus.Completed;
        }

        emit ISapienCore.ContributionSubmitted(projectId, index, msg.sender, submissionHash, dataCid);
    }

    function batchContribute(
        uint256 claimId,
        uint256[] calldata indices,
        bytes32[] calldata submissionHashes,
        string[] calldata dataCids
    ) public {
        uint256 len = indices.length;
        if (len == 0) revert ISapienCore.ZeroAmount();
        if (len != submissionHashes.length || len != dataCids.length) revert ISapienCore.InvalidIndex();

        for (uint256 i; i < len; ++i) {
            contribute(claimId, indices[i], submissionHashes[i], dataCids[i]);
        }
    }

    function expireClaim(uint256 claimId, uint256[] calldata indices) public {
        EngineStorage storage $ = _getStorage();
        Claim storage claim = $.claims[claimId];

        if (claim.status != ClaimStatus.Active) revert ISapienCore.ClaimDeadlineNotPassed();
        if (block.timestamp <= claim.deadline) revert ISapienCore.ClaimDeadlineNotPassed();

        bytes32 projectId = claim.projectId;
        Project storage proj = $.projects[projectId];
        uint256 unsubmitted = 0;
        uint256 stillInFlight = 0;

        uint256 len = indices.length;
        if (len != claim.totalCount) revert ISapienCore.InvalidIndex();
        uint256 rsTop = $.returnStackTop[projectId];

        for (uint256 i; i < len; ++i) {
            uint256 idx = indices[i];
            Contribution storage contrib = $.contributions[projectId][idx];

            if (contrib.claimId != uint32(claimId)) continue;

            if (contrib.status == ContributionStatus.Reserved) {
                $.returnStack[projectId][rsTop] = idx;
                rsTop++;

                contrib.contributor = address(0);
                contrib.claimId = 0;
                contrib.status = ContributionStatus.Empty;
                unsubmitted++;
            } else if (contrib.status == ContributionStatus.Pending) {
                stillInFlight++;
            }
        }

        $.returnStackTop[projectId] = rsTop;
        proj.availableSlots += uint32(unsubmitted);

        uint256 expectedUnsubmitted = uint256(claim.totalCount) - uint256(claim.submittedCount);
        if (unsubmitted != expectedUnsubmitted) revert ISapienCore.InvalidIndex();

        uint256 slashAmount = unsubmitted > 0 ? proj.minStakeToClaim * unsubmitted : 0;
        uint256 unlockAmount = stillInFlight * proj.minStakeToClaim;
        if (slashAmount > 0 || unlockAmount > 0) {
            $.vault.slashAndUnlockContributor(claim.claimant, slashAmount, unlockAmount);
        }

        claim.status = ClaimStatus.Expired;

        if (unsubmitted > 0) {
            ReputationLib.update(claim.claimant, proj.requiredSkill, false, 0);
        }

        emit ISapienCore.ClaimExpired(claimId, unsubmitted);
    }
}
