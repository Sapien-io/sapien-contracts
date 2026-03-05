// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
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

library DisputeLib {
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0xb21037e32bd67da4126ec23c3d75228183c819f055709f5aa59aa33cc3fd2b00
        }
    }

    function openDispute(bytes32 projectId, uint256 index, bytes32 evidenceHash, string calldata evidenceCid) public {
        if (evidenceHash == bytes32(0)) revert ISapienCore.InvalidEvidenceHash();

        EngineStorage storage $ = _getStorage();
        Contribution storage contrib = $.contributions[projectId][index];

        uint256 nonce = contrib.consensusNonce;
        if (!$.consensusReports[projectId][index][nonce].computed && contrib.status != ContributionStatus.Rejected) {
            revert ISapienCore.ConsensusNotComputed();
        }

        if (contrib.challengeEndsAt == 0) revert ISapienCore.ConsensusNotComputed();
        if (block.timestamp > contrib.challengeEndsAt) revert ISapienCore.DisputeWindowClosed();

        Dispute storage dispute = $.disputes[projectId][index][nonce];

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
        dispute.openedAt = uint48(block.timestamp);
        dispute.status = DisputeStatus.Open;
        dispute.bondAmount = bondAmount;
        dispute.evidenceHash = evidenceHash;

        if (contrib.status == ContributionStatus.Accepted) {
            contrib.challengeEndsAt = uint48(block.timestamp + C.DISPUTE_RESOLUTION_DEADLINE);
        }

        emit ISapienCore.DisputeOpened(projectId, index, msg.sender, bondAmount, evidenceCid);
    }

    function upholdDispute(bytes32 projectId, uint256 index, uint256 nonce) public {
        EngineStorage storage $ = _getStorage();
        Dispute storage dispute = $.disputes[projectId][index][nonce];
        Contribution storage contrib = $.contributions[projectId][index];
        Project storage proj = $.projects[projectId];
        address rewardToken = proj.rewardToken;

        dispute.status = DisputeStatus.Upheld;
        dispute.resolvedAt = uint40(block.timestamp);
        $.vault.unlockContributor(dispute.challenger, dispute.bondAmount);

        emit ISapienCore.DisputeResolved(projectId, index, true);

        if (contrib.status == ContributionStatus.Accepted) {
            uint256 challengerReward = (contrib.rewardRate * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;
            if (challengerReward > 0 && $.projectEscrow[projectId][rewardToken] >= challengerReward) {
                $.pendingRewards[dispute.challenger][rewardToken] += challengerReward;
                $.projectEscrow[projectId][rewardToken] -= challengerReward;
            }
            ReputationLib.update(contrib.contributor, proj.requiredSkill, false, 0);

            if ($.pendingContributions[projectId] > 0) {
                $.pendingContributions[projectId]--;
            }
        } else if (contrib.status == ContributionStatus.Rejected) {
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

    function rejectDispute(bytes32 projectId, uint256 index, uint256 nonce) public {
        EngineStorage storage $ = _getStorage();
        Dispute storage dispute = $.disputes[projectId][index][nonce];
        Contribution storage contrib = $.contributions[projectId][index];

        dispute.status = DisputeStatus.Rejected;
        dispute.resolvedAt = uint40(block.timestamp);
        $.vault.slashContributor(dispute.challenger, dispute.bondAmount);

        if (contrib.status == ContributionStatus.Accepted) {
            contrib.challengeEndsAt = uint48(block.timestamp);
        }

        emit ISapienCore.DisputeResolved(projectId, index, false);
    }

    function reportOriginator(bytes32 projectId, bytes32 evidenceHash) public {
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
        report.reportedAt = uint48(block.timestamp);
        report.status = OriginatorReportStatus.Open;
        report.bondAmount = bondAmount;
        report.evidenceHash = evidenceHash;

        emit ISapienCore.OriginatorReported(projectId, msg.sender, bondAmount);
    }

    function upholdOriginatorReport(bytes32 projectId, bool includeReporterReward) public {
        EngineStorage storage $ = _getStorage();
        OriginatorReport storage report = $.originatorReports[projectId];
        Project storage proj = $.projects[projectId];

        report.status = OriginatorReportStatus.Upheld;
        report.resolvedAt = uint40(block.timestamp);
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
        proj.cancelledAt = uint48(block.timestamp);
        emit ISapienCore.ProjectCancelled(projectId);
    }

    function rejectOriginatorReport(bytes32 projectId) public {
        EngineStorage storage $ = _getStorage();
        OriginatorReport storage report = $.originatorReports[projectId];

        report.status = OriginatorReportStatus.Rejected;
        report.resolvedAt = uint40(block.timestamp);
        $.vault.slashContributor(report.reporter, report.bondAmount);

        emit ISapienCore.OriginatorReportResolved(projectId, false);
    }
}
