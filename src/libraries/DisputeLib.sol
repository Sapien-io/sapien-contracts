// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {ReputationLib} from "src/libraries/ReputationLib.sol";
import {PauseAwareLib} from "src/libraries/PauseAwareLib.sol";
import {
    EngineStorage,
    Project,
    ProjectStatus,
    Contribution,
    ContributionStatus,
    Dispute,
    DisputeStatus,
    OriginatorReport,
    OriginatorReportStatus
} from "src/Types.sol";

/// @title DisputeLib
/// @notice Deployed library for dispute and originator report operations.
/// @dev Called via DELEGATECALL from SapienCore; operates on the caller's ERC-7201 storage.
///      Uses ReputationLib (also via DELEGATECALL) for reputation updates.
library DisputeLib {
    // keccak256(abi.encode(uint256(keccak256("sapien.storage.SapienCore")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0xb21037e32bd67da4126ec23c3d75228183c819f055709f5aa59aa33cc3fd2b00
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Disputes — Consensus Outcome Challenges
    // ════════════════════════════════════════════════════════════════════

    /// @notice Open a dispute on a consensus outcome during the challenge period.
    function openDispute(bytes32 projectId, uint256 index, bytes32 evidenceHash, string calldata evidenceCid) public {
        // SEC-L-03: Require non-empty evidence hash
        if (evidenceHash == bytes32(0)) revert ISapienCore.InvalidEvidenceHash();

        EngineStorage storage $ = _getStorage();
        Contribution storage contrib = $.contributions[projectId][index];

        uint256 nonce = contrib.consensusNonce;
        if (!$.consensusReports[projectId][index][nonce].computed && contrib.status != ContributionStatus.Rejected) {
            revert ISapienCore.ConsensusNotComputed();
        }

        if (contrib.challengeEndsAt == 0) revert ISapienCore.ConsensusNotComputed();
        if (PauseAwareLib.isAfterDeadline($, contrib.challengeEndsAt)) revert ISapienCore.DisputeWindowClosed();

        // SEC-C-01: disputes keyed by nonce to prevent cross-nonce poisoning
        Dispute storage dispute = $.disputes[projectId][index][nonce];

        // SEC-H-03: only one dispute per (projectId, index, nonce) — block reopening
        if (dispute.status == DisputeStatus.Open) revert ISapienCore.DisputeAlreadyOpen();
        if (dispute.status == DisputeStatus.Rejected || dispute.status == DisputeStatus.Upheld) {
            revert ISapienCore.DisputeAlreadyClosed();
        }

        if (contrib.status == ContributionStatus.Accepted && contrib.contributor == msg.sender) {
            revert ISapienCore.CannotDisputeOwnContribution();
        }

        uint256 bondAmount = (contrib.rewardRate * $.disputeBondBps) / C.BPS;
        if (bondAmount == 0) bondAmount = 1;
        $.vault.lockContributor(msg.sender, bondAmount);

        dispute.challenger = msg.sender;
        dispute.openedAt = block.timestamp;
        dispute.status = DisputeStatus.Open;
        dispute.bondAmount = bondAmount;
        dispute.evidenceHash = evidenceHash;

        if (contrib.status == ContributionStatus.Accepted) {
            contrib.challengeEndsAt = block.timestamp + C.DISPUTE_RESOLUTION_DEADLINE;
        }

        emit ISapienCore.DisputeOpened(projectId, index, msg.sender, bondAmount, evidenceCid);
    }

    /// @notice Execute the "upheld" path for a dispute (used by both resolve and escalate).
    function upholdDispute(bytes32 projectId, uint256 index, uint256 nonce) public {
        EngineStorage storage $ = _getStorage();
        Dispute storage dispute = $.disputes[projectId][index][nonce];
        Contribution storage contrib = $.contributions[projectId][index];
        Project storage proj = $.projects[projectId];
        address rewardToken = proj.rewardToken;

        dispute.status = DisputeStatus.Upheld;
        dispute.resolvedAt = block.timestamp;
        $.vault.unlockContributor(dispute.challenger, dispute.bondAmount);

        emit ISapienCore.DisputeResolved(projectId, index, true);

        if (contrib.status == ContributionStatus.Accepted) {
            uint256 challengerReward = (contrib.rewardRate * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;
            if (challengerReward > 0 && $.projectEscrow[projectId][rewardToken] >= challengerReward) {
                $.pendingRewards[dispute.challenger][rewardToken] += challengerReward;
                $.projectEscrow[projectId][rewardToken] -= challengerReward;
            }
            ReputationLib.update(contrib.contributor, proj.requiredSkill, false, 0);

            // Mark this accepted contribution as lifecycle-complete from the pipeline
            // perspective so upheld disputes do not deadlock project completion.
            if ($.pendingContributions[projectId] > 0) {
                $.pendingContributions[projectId]--;
            }
        } else if (contrib.status == ContributionStatus.Rejected) {
            // SEC-H-04: Cap total payout to rewardRate (contributor + challenger share a single budget)
            uint256 maxPayout = contrib.rewardRate;
            uint256 challengerReward = (maxPayout * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;
            uint256 compensation = maxPayout - challengerReward;

            if (compensation > 0 && $.projectEscrow[projectId][rewardToken] >= compensation) {
                $.pendingRewards[contrib.contributor][rewardToken] += compensation;
                $.projectEscrow[projectId][rewardToken] -= compensation;
                contrib.rewardReleased = true;
            }
            ReputationLib.update(contrib.contributor, proj.requiredSkill, true, 0);

            if (challengerReward > 0 && $.projectEscrow[projectId][rewardToken] >= challengerReward) {
                $.pendingRewards[dispute.challenger][rewardToken] += challengerReward;
                $.projectEscrow[projectId][rewardToken] -= challengerReward;
            }
        }
    }

    /// @notice Execute the "rejected" path for a dispute.
    function rejectDispute(bytes32 projectId, uint256 index, uint256 nonce) public {
        EngineStorage storage $ = _getStorage();
        Dispute storage dispute = $.disputes[projectId][index][nonce];
        Contribution storage contrib = $.contributions[projectId][index];

        dispute.status = DisputeStatus.Rejected;
        dispute.resolvedAt = block.timestamp;
        $.vault.slashContributor(dispute.challenger, dispute.bondAmount);

        if (contrib.status == ContributionStatus.Accepted) {
            contrib.challengeEndsAt = block.timestamp;
        }

        emit ISapienCore.DisputeResolved(projectId, index, false);
    }

    // ════════════════════════════════════════════════════════════════════
    // Originator Accountability
    // ════════════════════════════════════════════════════════════════════

    /// @notice Report an originator for misconduct.
    function reportOriginator(bytes32 projectId, bytes32 evidenceHash) public {
        // SEC-L-03: Require non-empty evidence hash
        if (evidenceHash == bytes32(0)) revert ISapienCore.InvalidEvidenceHash();

        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];

        if (proj.originator == address(0)) revert ISapienCore.ProjectNotFound();
        if (proj.status != ProjectStatus.Active && proj.status != ProjectStatus.Funded) {
            revert ISapienCore.ProjectNotCancellable();
        }

        if (proj.originator == msg.sender) revert ISapienCore.NotProjectOriginator();

        OriginatorReport storage report = $.originatorReports[projectId];
        if (report.status == OriginatorReportStatus.Open) revert ISapienCore.OriginatorReportAlreadyOpen();

        uint256 bondAmount = (proj.totalRewards * $.originatorReportBondBps) / C.BPS;
        if (bondAmount == 0) bondAmount = 1;
        $.vault.lockContributor(msg.sender, bondAmount);

        report.reporter = msg.sender;
        report.reportedAt = block.timestamp;
        report.status = OriginatorReportStatus.Open;
        report.bondAmount = bondAmount;
        report.evidenceHash = evidenceHash;

        emit ISapienCore.OriginatorReported(projectId, msg.sender, bondAmount);
    }

    /// @notice Execute the "upheld" path for an originator report.
    /// @param includeReporterReward If true, give reporter a reward from escrow (used by resolve, not escalate)
    function upholdOriginatorReport(bytes32 projectId, bool includeReporterReward) public {
        EngineStorage storage $ = _getStorage();
        OriginatorReport storage report = $.originatorReports[projectId];
        Project storage proj = $.projects[projectId];

        report.status = OriginatorReportStatus.Upheld;
        report.resolvedAt = block.timestamp;
        $.vault.unlockContributor(report.reporter, report.bondAmount);

        uint256 originatorStake = $.originatorLockedStake[projectId];
        if (originatorStake > 0) {
            $.vault.slashContributor(proj.originator, originatorStake);
            $.originatorLockedStake[projectId] = 0;

            if (includeReporterReward) {
                uint256 reporterReward = (originatorStake * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;
                address rewardToken = proj.rewardToken;
                if (reporterReward > 0 && $.projectEscrow[projectId][rewardToken] >= reporterReward) {
                    $.pendingRewards[report.reporter][rewardToken] += reporterReward;
                    $.projectEscrow[projectId][rewardToken] -= reporterReward;
                }
            }
        }

        ReputationLib.update(proj.originator, C.ORIGINATOR_ROLE_KEY, false, 0);
        proj.status = ProjectStatus.Cancelled;
        proj.cancelledAt = block.timestamp;
        emit ISapienCore.ProjectCancelled(projectId);
    }

    /// @notice Execute the "rejected" path for an originator report.
    function rejectOriginatorReport(bytes32 projectId) public {
        EngineStorage storage $ = _getStorage();
        OriginatorReport storage report = $.originatorReports[projectId];

        report.status = OriginatorReportStatus.Rejected;
        report.resolvedAt = block.timestamp;
        $.vault.slashContributor(report.reporter, report.bondAmount);

        emit ISapienCore.OriginatorReportResolved(projectId, false);
    }
}
