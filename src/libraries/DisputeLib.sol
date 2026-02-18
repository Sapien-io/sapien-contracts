// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Constants as C} from "src/Constants.sol";
import {IQualityEngine} from "src/interfaces/IQualityEngine.sol";
import {ReputationLib} from "src/libraries/ReputationLib.sol";
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
/// @dev Called via DELEGATECALL from QualityEngine; operates on the caller's ERC-7201 storage.
///      Uses ReputationLib (also via DELEGATECALL) for reputation updates.
library DisputeLib {
    // keccak256(abi.encode(uint256(keccak256("sapien.storage.QualityEngine")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0x93ae96f70dc96ca851a79b6bf630e034298e11be62b3174b3a3408302fc00900
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Disputes — Consensus Outcome Challenges
    // ════════════════════════════════════════════════════════════════════

    /// @notice Open a dispute on a consensus outcome during the challenge period.
    function openDispute(bytes32 projectId, uint256 index, bytes32 evidenceHash) public {
        EngineStorage storage $ = _getStorage();
        Contribution storage contrib = $.contributions[projectId][index];

        uint256 nonce = contrib.consensusNonce;
        if (!$.consensusReports[projectId][index][nonce].computed && contrib.status != ContributionStatus.Rejected) {
            revert IQualityEngine.ConsensusNotComputed();
        }

        if (contrib.challengeEndsAt == 0) revert IQualityEngine.ConsensusNotComputed();
        if (block.timestamp > contrib.challengeEndsAt) revert IQualityEngine.DisputeWindowClosed();

        Dispute storage dispute = $.disputes[projectId][index];
        if (dispute.status == DisputeStatus.Open) revert IQualityEngine.DisputeAlreadyOpen();

        if (contrib.status == ContributionStatus.Accepted && contrib.contributor == msg.sender) {
            revert IQualityEngine.CannotDisputeOwnContribution();
        }

        uint256 bondAmount = (contrib.rewardRate * uint256($.disputeBondBps)) / C.BPS;
        if (bondAmount == 0) bondAmount = 1;
        $.vault.lockContributor(msg.sender, bondAmount);

        dispute.challenger = msg.sender;
        dispute.openedAt = uint64(block.timestamp);
        dispute.status = DisputeStatus.Open;
        dispute.bondAmount = uint128(bondAmount);
        dispute.evidenceHash = evidenceHash;

        if (contrib.status == ContributionStatus.Accepted) {
            contrib.challengeEndsAt = uint64(block.timestamp + C.DISPUTE_RESOLUTION_DEADLINE);
        }

        emit IQualityEngine.DisputeOpened(projectId, index, msg.sender, bondAmount);
    }

    /// @notice Execute the "upheld" path for a dispute (used by both resolve and escalate).
    function upholdDispute(bytes32 projectId, uint256 index) public {
        EngineStorage storage $ = _getStorage();
        Dispute storage dispute = $.disputes[projectId][index];
        Contribution storage contrib = $.contributions[projectId][index];
        Project storage proj = $.projects[projectId];
        address rewardToken = proj.rewardToken;

        dispute.status = DisputeStatus.Upheld;
        dispute.resolvedAt = uint64(block.timestamp);
        $.vault.unlockContributor(dispute.challenger, dispute.bondAmount);

        if (contrib.status == ContributionStatus.Accepted) {
            uint256 challengerReward = (contrib.rewardRate * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;
            if (challengerReward > 0 && $.projectEscrow[projectId][rewardToken] >= challengerReward) {
                $.pendingRewards[dispute.challenger][rewardToken] += challengerReward;
                $.projectEscrow[projectId][rewardToken] -= challengerReward;
            }
            ReputationLib.update(contrib.contributor, C.CONTRIBUTOR_ROLE_KEY, false, 0);
        } else if (contrib.status == ContributionStatus.Rejected) {
            uint256 compensation = contrib.rewardRate;
            if (compensation > 0 && $.projectEscrow[projectId][rewardToken] >= compensation) {
                $.pendingRewards[contrib.contributor][rewardToken] += compensation;
                $.projectEscrow[projectId][rewardToken] -= compensation;
                contrib.rewardReleased = true;
            }
            ReputationLib.update(contrib.contributor, C.CONTRIBUTOR_ROLE_KEY, true, 0);

            uint256 challengerReward = (contrib.rewardRate * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;
            if (challengerReward > 0 && $.projectEscrow[projectId][rewardToken] >= challengerReward) {
                $.pendingRewards[dispute.challenger][rewardToken] += challengerReward;
                $.projectEscrow[projectId][rewardToken] -= challengerReward;
            }
        }
    }

    /// @notice Execute the "rejected" path for a dispute.
    function rejectDispute(bytes32 projectId, uint256 index) public {
        EngineStorage storage $ = _getStorage();
        Dispute storage dispute = $.disputes[projectId][index];
        Contribution storage contrib = $.contributions[projectId][index];

        dispute.status = DisputeStatus.Rejected;
        dispute.resolvedAt = uint64(block.timestamp);
        $.vault.slashContributor(dispute.challenger, dispute.bondAmount);

        if (contrib.status == ContributionStatus.Accepted) {
            contrib.challengeEndsAt = uint64(block.timestamp);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Originator Accountability
    // ════════════════════════════════════════════════════════════════════

    /// @notice Report an originator for misconduct.
    function reportOriginator(bytes32 projectId, bytes32 evidenceHash) public {
        EngineStorage storage $ = _getStorage();
        Project storage proj = $.projects[projectId];

        if (proj.originator == address(0)) revert IQualityEngine.InvalidProjectConfig("project does not exist");
        if (proj.status != ProjectStatus.Active && proj.status != ProjectStatus.Funded) {
            revert IQualityEngine.ProjectNotCancellable();
        }

        if (proj.originator == msg.sender) revert IQualityEngine.NotProjectOriginator();

        OriginatorReport storage report = $.originatorReports[projectId];
        if (report.status == OriginatorReportStatus.Open) revert IQualityEngine.OriginatorReportAlreadyOpen();

        uint256 bondAmount = (proj.totalRewards * uint256($.originatorReportBondBps)) / C.BPS;
        if (bondAmount == 0) bondAmount = 1;
        $.vault.lockContributor(msg.sender, bondAmount);

        report.reporter = msg.sender;
        report.reportedAt = uint64(block.timestamp);
        report.status = OriginatorReportStatus.Open;
        report.bondAmount = uint128(bondAmount);
        report.evidenceHash = evidenceHash;

        emit IQualityEngine.OriginatorReported(projectId, msg.sender, bondAmount);
    }

    /// @notice Execute the "upheld" path for an originator report.
    /// @param includeReporterReward If true, give reporter a reward from escrow (used by resolve, not escalate)
    function upholdOriginatorReport(bytes32 projectId, bool includeReporterReward) public {
        EngineStorage storage $ = _getStorage();
        OriginatorReport storage report = $.originatorReports[projectId];
        Project storage proj = $.projects[projectId];

        report.status = OriginatorReportStatus.Upheld;
        report.resolvedAt = uint64(block.timestamp);
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
        emit IQualityEngine.ProjectCancelled(projectId);
    }

    /// @notice Execute the "rejected" path for an originator report.
    function rejectOriginatorReport(bytes32 projectId) public {
        EngineStorage storage $ = _getStorage();
        OriginatorReport storage report = $.originatorReports[projectId];

        report.status = OriginatorReportStatus.Rejected;
        report.resolvedAt = uint64(block.timestamp);
        $.vault.slashContributor(report.reporter, report.bondAmount);
    }
}
