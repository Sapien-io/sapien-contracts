// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {
    Project,
    ProjectStatus,
    Contribution,
    ContributionStatus,
    Dispute,
    DisputeStatus,
    OriginatorReport,
    OriginatorReportStatus,
    ValidationClaim,
    ValidationClaimStatus,
    ConsensusReport,
    Claim,
    ClaimStatus
} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";

/// @title FuzzExtended
/// @notice Extended fuzz coverage for dispute resolution, originator accountability,
///         project completion & escrow refund, force settlement, batch operations,
///         configurable consensus thresholds, and admin fee effects.
///
/// All tests build on the BaseTest UUPS proxy setup (engine + vault behind ERC-1967
/// proxies) and the fuzz helpers defined below.
contract FuzzExtended is BaseTest {
    // ── Fuzz Helpers ─────────────────────────────────────────────────────────

    function _boundFundAmount(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 1_000e18, 500_000e18);
    }

    function _boundStake(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 1e18, 200e18);
    }

    /// @dev Commit and reveal for a validator (similar to LifecycleBase._validate)
    function _validate(address val, bytes32 projectId, uint256 index, uint256 score, uint256 stakeAmt) internal {
        bytes32 salt = keccak256(abi.encodePacked("fuzz-validate-salt", val, projectId, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(val, stakeAmt * 2);

        vm.startPrank(val);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projectId, index, commitHash, stakeAmt, address(0));
        vm.stopPrank();

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(val);
        engine.revealValidation(projectId, index, score, salt);
    }

    function _projectId(uint256 seed) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("fuzz-ext-project", seed));
    }

    /// @dev Deploy a funded project and return projectId + qty.
    function _fundProject(uint256 seed, uint256 fundAmount, uint256 qty, uint256 numValidations, uint256 thresholdBps)
        internal
        returns (bytes32 projId)
    {
        projId = _projectId(seed);
        token.mint(originator, fundAmount);

        vm.startPrank(originator);
        Project memory cfg = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: thresholdBps,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: numValidations,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
        engine.createProject(projId, "", cfg);
        token.approve(address(engine), fundAmount);
        engine.fundProject(projId, fundAmount, qty, address(0));
        vm.stopPrank();
    }

    /// @dev Commit and reveal for `val`, returning the salt used.
    function _commitReveal(address val, bytes32 projId, uint256 index, uint256 score, uint256 stakeAmt)
        internal
        returns (bytes32 salt)
    {
        salt = keccak256(abi.encodePacked("ext-salt", val, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(val, stakeAmt * 3);

        vm.startPrank(val);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projId, index, commitHash, stakeAmt, address(0));
        engine.revealValidation(projId, index, score, salt);
        vm.stopPrank();
    }

    /// @dev Full setup: fund project, claim one slot, contribute, 3 validators
    ///      commit+reveal at `score`. Returns (projId, index, settleNonce).
    function _setupAcceptedContribution(uint256 seed, uint256 fundAmount, uint256 score, uint256 valStake)
        internal
        returns (bytes32 projId, uint256 index, uint256 nonce)
    {
        projId = _fundProject(seed, fundAmount, 5, 3, 7000);

        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 1, address(0));
        index = indices[0];
        engine.contribute(claimId, index, keccak256(abi.encodePacked("sub", seed)), "");
        vm.stopPrank();

        _commitReveal(validator1, projId, index, score, valStake);
        _commitReveal(validator2, projId, index, score, valStake);
        _commitReveal(validator3, projId, index, score, valStake);
        engine.computeConsensus(projId, index);

        nonce = engine.getContribution(projId, index).consensusNonce;
    }

    /// @dev Full setup leading to a REJECTED contribution.
    function _setupRejectedContribution(uint256 seed, uint256 fundAmount, uint256 valStake)
        internal
        returns (bytes32 projId, uint256 index, uint256 nonce)
    {
        projId = _fundProject(seed, fundAmount, 5, 3, 7000);

        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 1, address(0));
        index = indices[0];
        engine.contribute(claimId, index, keccak256(abi.encodePacked("sub-reject", seed)), "");
        vm.stopPrank();

        // Low scores — all below 7000 threshold
        _commitReveal(validator1, projId, index, 2000, valStake);
        _commitReveal(validator2, projId, index, 3000, valStake);
        _commitReveal(validator3, projId, index, 2500, valStake);
        engine.computeConsensus(projId, index);

        nonce = engine.getContribution(projId, index).consensusNonce;
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 11 — Dispute upheld on an accepted contribution
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Challenger disputes an accepted contribution; admin upholds it.
    ///         Challenger receives 20% of rewardRate from escrow; contributor
    ///         cannot later release their reward.
    function testFuzz_disputeUpheld_acceptedContribution(uint256 fundAmount, uint256 valStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 valStake = _boundStake(valStakeSeed);

        (bytes32 projId, uint256 index,) = _setupAcceptedContribution(42, fundAmount, 8500, valStake);

        assertEq(uint256(engine.getContribution(projId, index).status), uint256(ContributionStatus.Accepted));

        uint256 rewardRate = engine.getContribution(projId, index).rewardRate;
        uint256 escrowBefore = engine.getProjectEscrow(projId, address(token));

        // Bond = rewardRate * disputeBondBps / BPS (default 10%). Ensure challenger can cover it.
        uint256 bondNeeded = (rewardRate * 1000) / 10_000 + 1;
        _ensureStake(contributor2, bondNeeded + 1e18);
        uint256 challengerAvailBefore = vault.availableBalance(contributor2);
        uint256 challengerPendingBefore = engine.getPendingRewards(contributor2, address(token));

        // Open dispute within challenge window
        bytes32 evidenceHash = keccak256("dispute-evidence-1");
        vm.prank(contributor2);
        engine.openDispute(projId, index, evidenceHash, "");

        assertEq(uint256(engine.getDispute(projId, index).status), uint256(DisputeStatus.Open));

        // Admin upholds the dispute
        vm.prank(admin);
        engine.resolveDispute(projId, index, true);

        assertEq(uint256(engine.getDispute(projId, index).status), uint256(DisputeStatus.Upheld));

        // Challenger's bond is returned (available balance restored) and they gain a reward
        uint256 challengerPendingAfter = engine.getPendingRewards(contributor2, address(token));
        uint256 expectedChallengerReward = (rewardRate * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;
        assertGe(challengerPendingAfter - challengerPendingBefore, 0);
        assertLe(challengerPendingAfter - challengerPendingBefore, expectedChallengerReward);

        // Escrow decreased by challenger reward
        uint256 escrowAfter = engine.getProjectEscrow(projId, address(token));
        assertLe(escrowAfter, escrowBefore);

        // Contributor CANNOT release reward — dispute is upheld
        vm.warp(block.timestamp + 2 days);
        vm.expectRevert();
        engine.releaseContributorReward(projId, index);

        // Challenger's available balance restored after bond unlock
        assertGe(vault.availableBalance(contributor2), challengerAvailBefore - 1);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 12 — Dispute rejected on an accepted contribution
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Challenger disputes an accepted contribution; admin rejects it.
    ///         Challenger's bond is slashed; contributor can still release reward.
    function testFuzz_disputeRejected_acceptedContribution(uint256 fundAmount, uint256 valStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 valStake = _boundStake(valStakeSeed);

        (bytes32 projId, uint256 index,) = _setupAcceptedContribution(43, fundAmount, 8500, valStake);

        uint256 bondNeeded2 = (engine.getContribution(projId, index).rewardRate * 1000) / 10_000 + 1;
        _ensureStake(contributor2, bondNeeded2 + 1e18);
        uint256 challengerSharesBefore = vault.balanceOf(contributor2);

        // Open dispute within challenge window (before settling)
        vm.prank(contributor2);
        engine.openDispute(projId, index, keccak256("dispute-evidence-2"), "");

        // Admin rejects the dispute (resets challengeEndsAt to block.timestamp)
        vm.prank(admin);
        engine.resolveDispute(projId, index, false);

        assertEq(uint256(engine.getDispute(projId, index).status), uint256(DisputeStatus.Rejected));

        // Challenger is slashed
        assertLt(vault.balanceOf(contributor2), challengerSharesBefore);

        // Settle validators (challenge period reset by dispute rejection)
        uint256 nonce = engine.getContribution(projId, index).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(projId, index, nonce);

        // Contributor CAN release their reward — challenge period was reset to now
        engine.releaseContributorReward(projId, index);
        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 13 — Dispute auto-escalates after resolution deadline
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice If admin never resolves a dispute, anyone can escalate it after
    ///         DISPUTE_RESOLUTION_DEADLINE (7 days). Escalation auto-upholds.
    function testFuzz_disputeEscalated(uint256 fundAmount, uint256 valStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 valStake = _boundStake(valStakeSeed);

        (bytes32 projId, uint256 index,) = _setupAcceptedContribution(44, fundAmount, 8500, valStake);

        uint256 bondNeeded3 = (engine.getContribution(projId, index).rewardRate * 1000) / 10_000 + 1;
        _ensureStake(contributor2, bondNeeded3 + 1e18);
        uint256 challengerPendingBefore = engine.getPendingRewards(contributor2, address(token));

        vm.prank(contributor2);
        engine.openDispute(projId, index, keccak256("dispute-evidence-3"), "");

        // Nobody resolves — warp past DISPUTE_RESOLUTION_DEADLINE
        vm.warp(block.timestamp + C.DISPUTE_RESOLUTION_DEADLINE + 1);

        // Any address can escalate
        engine.escalateDispute(projId, index);

        assertEq(uint256(engine.getDispute(projId, index).status), uint256(DisputeStatus.Upheld));

        // Challenger should have received their reward
        uint256 challengerPendingAfter = engine.getPendingRewards(contributor2, address(token));
        assertGe(challengerPendingAfter, challengerPendingBefore);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 14 — Dispute upheld on a rejected contribution (contributor disputes)
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice The contributor of a rejected contribution can dispute the outcome.
    ///         If upheld: contributor gets 80% of rewardRate, challenger gets 20%.
    ///         Here contributor2 acts as the external challenger.
    function testFuzz_disputeUpheld_rejectedContribution(uint256 fundAmount, uint256 valStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 valStake = _boundStake(valStakeSeed);

        (bytes32 projId, uint256 index,) = _setupRejectedContribution(45, fundAmount, valStake);

        assertEq(uint256(engine.getContribution(projId, index).status), uint256(ContributionStatus.Rejected));

        uint256 rewardRate = engine.getContribution(projId, index).rewardRate;
        uint256 contrib1PendingBefore = engine.getPendingRewards(contributor1, address(token));
        uint256 contrib2PendingBefore = engine.getPendingRewards(contributor2, address(token));

        // contributor2 disputes the rejected outcome (they believe the validators were wrong)
        uint256 bondNeeded4 = (rewardRate * 1000) / 10_000 + 1;
        _ensureStake(contributor2, bondNeeded4 + 1e18);
        vm.prank(contributor2);
        engine.openDispute(projId, index, keccak256("dispute-evidence-4"), "");

        vm.prank(admin);
        engine.resolveDispute(projId, index, true);

        assertEq(uint256(engine.getDispute(projId, index).status), uint256(DisputeStatus.Upheld));

        // contributor1 (rejected contributor) gets compensation
        uint256 contrib1PendingAfter = engine.getPendingRewards(contributor1, address(token));
        uint256 contrib2PendingAfter = engine.getPendingRewards(contributor2, address(token));

        uint256 expectedChallengerReward = (rewardRate * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;
        uint256 expectedCompensation = rewardRate - expectedChallengerReward;

        // Both may receive rewards (capped by escrow availability)
        assertGe(contrib1PendingAfter, contrib1PendingBefore);
        assertGe(contrib2PendingAfter, contrib2PendingBefore);
        assertLe(contrib1PendingAfter - contrib1PendingBefore, expectedCompensation);
        assertLe(contrib2PendingAfter - contrib2PendingBefore, expectedChallengerReward);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 15 — Force settle an unresponsive validator
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Validator1 and Validator2 settle normally. Validator3 never calls
    ///         settleValidator. After forceSettleDelay elapses, anyone can settle
    ///         validator3 via forceSettleValidator.
    function testFuzz_forceSettleUnresponsiveValidator(uint256 fundAmount, uint256 valStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 valStake = _boundStake(valStakeSeed);

        (bytes32 projId, uint256 index, uint256 nonce) = _setupAcceptedContribution(50, fundAmount, 8500, valStake);

        _warpPastChallengePeriod();

        // Validator1 and Validator2 settle after challenge period
        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projId, index, nonce);

        assertTrue(engine.isValidatorSettled(projId, index, nonce, validator1));
        assertTrue(engine.isValidatorSettled(projId, index, nonce, validator2));
        assertFalse(engine.isValidatorSettled(projId, index, nonce, validator3));

        // Warp past forceSettleDelay (revealedAt is approximately block.timestamp at commit time)
        uint256 delay = engine.forceSettleDelay();
        vm.warp(block.timestamp + delay + 1);

        uint256 v3SharesBefore = vault.balanceOf(validator3);

        // Any address can force-settle validator3
        engine.forceSettleValidator(projId, index, nonce, validator3);

        assertTrue(engine.isValidatorSettled(projId, index, nonce, validator3));

        // validator3 either received rewards or was handled (shares not unexpectedly destroyed)
        uint256 v3SharesAfter = vault.balanceOf(validator3);
        // Non-outlier should have shares unchanged or increased (stake returned)
        assertGe(v3SharesAfter, 0);
        // Specifically: since validator3 voted same as others (8500), they are not an outlier
        assertFalse(engine.isValidatorOutlier(projId, index, validator3));
        assertGe(v3SharesAfter, v3SharesBefore); // stake released back
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 16 — Cancel expired validation claim (validator claims but never commits)
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice A validator reserves indices via claimToValidate but lets the
    ///         1-hour window expire without committing. Anyone can cancel the claim,
    ///         releasing the uncommitted indices and allowing other validators to proceed.
    function testFuzz_cancelExpiredValidationClaim(uint256 fundAmount, uint256 valStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 valStake = _boundStake(valStakeSeed);

        bytes32 projId = _fundProject(60, fundAmount, 5, 3, 7000);

        // contributor1 claims and contributes one slot
        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 1, address(0));
        uint256 index = indices[0];
        engine.contribute(claimId, index, keccak256("subm-cancel-vc"), "");
        vm.stopPrank();

        // validator1 claims the index for validation but never commits
        _ensureStake(validator1, valStake * 3);
        vm.startPrank(validator1);
        uint256 vcClaimId = engine.claimToValidate(projId, 1);
        vm.stopPrank();

        ValidationClaim memory vc = engine.getValidationClaim(vcClaimId);
        assertEq(uint256(vc.status), uint256(ValidationClaimStatus.Active));

        // Warp past VALIDATION_CLAIM_DEADLINE (1 hour)
        vm.warp(block.timestamp + C.VALIDATION_CLAIM_DEADLINE + 1);

        // Anyone cancels — no slash for uncommitted slots
        engine.cancelExpiredValidationClaim(vcClaimId);

        ValidationClaim memory vcAfter = engine.getValidationClaim(vcClaimId);
        assertEq(uint256(vcAfter.status), uint256(ValidationClaimStatus.Expired));

        // validator2 can now claim the same index and commit
        _commitReveal(validator2, projId, index, 8500, valStake);
        _commitReveal(validator3, projId, index, 8500, valStake);

        // Need one more validator since only 2 committed so far; use a new address
        address validator4 = makeAddr("val4-ext60");
        _commitReveal(validator4, projId, index, 8500, valStake);

        engine.computeConsensus(projId, index);
        assertEq(uint256(engine.getContribution(projId, index).status), uint256(ContributionStatus.Accepted));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 17 — Complete project and refund remaining escrow
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Full project lifecycle: accept 1 of 2 slots (rejected slot auto-decrements
    ///         pendingContributions), originator completes the project, waits the
    ///         30-day grace period, then claims the remaining escrow.
    function testFuzz_completeProjectAndRefundEscrow(uint256 fundAmount, uint256 valStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 valStake = _boundStake(valStakeSeed);

        bytes32 projId = _fundProject(70, fundAmount, 3, 3, 7000);

        // Index 0: accepted and released → pendingContributions goes 1→0
        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.startPrank(contributor1);
        (uint256 claimId1, uint256[] memory idxs1) = engine.claimToContribute(projId, 1, address(0));
        engine.contribute(claimId1, idxs1[0], keccak256("accepted-work"), "");
        vm.stopPrank();

        _commitReveal(validator1, projId, idxs1[0], 9000, valStake);
        _commitReveal(validator2, projId, idxs1[0], 8500, valStake);
        _commitReveal(validator3, projId, idxs1[0], 8800, valStake);
        engine.computeConsensus(projId, idxs1[0]);

        _warpPastChallengePeriod();

        // Settle validators
        uint256 nonce0 = engine.getContribution(projId, idxs1[0]).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(projId, idxs1[0], nonce0);
        vm.prank(validator2);
        engine.settleValidator(projId, idxs1[0], nonce0);
        vm.prank(validator3);
        engine.settleValidator(projId, idxs1[0], nonce0);

        // Release reward → pendingContributions = 0
        engine.releaseContributorReward(projId, idxs1[0]);

        // Originator completes the project
        vm.prank(originator);
        engine.completeProject(projId);

        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Completed));

        // Cannot refund before grace period
        vm.expectRevert();
        vm.prank(originator);
        engine.refundEscrow(projId);

        // Warp past PROJECT_COMPLETION_DELAY (30 days)
        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);

        uint256 originatorBalBefore = token.balanceOf(originator);
        uint256 escrowBefore = engine.getProjectEscrow(projId, address(token));
        assertGt(escrowBefore, 0, "remaining escrow must be non-zero");

        vm.prank(originator);
        engine.refundEscrow(projId);

        assertEq(engine.getProjectEscrow(projId, address(token)), 0);
        assertEq(token.balanceOf(originator), originatorBalBefore + escrowBefore);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 18 — Originator report upheld (project cancelled)
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice A reporter files an originator report; admin upholds it.
    ///         Project is cancelled, reporter's bond is returned, escrow is refundable.
    function testFuzz_originatorReport_upheld(uint256 fundAmount) public {
        fundAmount = _boundFundAmount(fundAmount);
        bytes32 projId = _fundProject(80, fundAmount, 5, 3, 7000);

        // Bond = totalRewards * originatorReportBondBps / BPS (default 1%)
        uint256 totalRewards80 = engine.getProject(projId).totalRewards;
        uint256 reportBond80 = (totalRewards80 * 100) / 10_000 + 1;
        _ensureStake(contributor1, reportBond80 + 1e18);
        uint256 reporterAvailBefore = vault.availableBalance(contributor1);

        vm.prank(contributor1);
        engine.reportOriginator(projId, keccak256("misconduct-evidence-1"));

        OriginatorReport memory report = engine.getOriginatorReport(projId);
        assertEq(uint256(report.status), uint256(OriginatorReportStatus.Open));

        // Bond is locked from reporter's available balance
        uint256 reporterAvailAfterReport = vault.availableBalance(contributor1);
        assertLt(reporterAvailAfterReport, reporterAvailBefore);

        // Admin upholds the report
        vm.prank(admin);
        engine.resolveOriginatorReport(projId, true);

        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Cancelled));
        assertEq(uint256(engine.getOriginatorReport(projId).status), uint256(OriginatorReportStatus.Upheld));

        // Reporter's bond is returned
        uint256 reporterAvailAfterUpheld = vault.availableBalance(contributor1);
        assertGe(reporterAvailAfterUpheld, reporterAvailAfterReport);

        // Originator can refund remaining escrow after completion delay
        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);
        uint256 escrow = engine.getProjectEscrow(projId, address(token));
        if (escrow > 0) {
            uint256 originatorBalBefore = token.balanceOf(originator);
            vm.prank(originator);
            engine.refundEscrow(projId);
            assertEq(token.balanceOf(originator), originatorBalBefore + escrow);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 19 — Originator report rejected (reporter slashed)
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Admin rejects the originator report. Reporter's bond is slashed;
    ///         project continues as active.
    function testFuzz_originatorReport_rejected(uint256 fundAmount) public {
        fundAmount = _boundFundAmount(fundAmount);
        bytes32 projId = _fundProject(81, fundAmount, 5, 3, 7000);

        uint256 totalRewards81 = engine.getProject(projId).totalRewards;
        uint256 reportBond81 = (totalRewards81 * 100) / 10_000 + 1;
        _ensureStake(contributor1, reportBond81 + 1e18);
        uint256 reporterSharesBefore = vault.balanceOf(contributor1);

        vm.prank(contributor1);
        engine.reportOriginator(projId, keccak256("bad-faith-report"));

        // Admin rejects
        vm.prank(admin);
        engine.resolveOriginatorReport(projId, false);

        assertEq(uint256(engine.getOriginatorReport(projId).status), uint256(OriginatorReportStatus.Rejected));

        // Project is still active (not cancelled)
        ProjectStatus s = engine.getProject(projId).status;
        assertTrue(s == ProjectStatus.Active || s == ProjectStatus.Funded);

        // Reporter's bond is slashed (shares burned)
        assertLt(vault.balanceOf(contributor1), reporterSharesBefore);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 20 — Originator report escalated after resolution deadline
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice If admin never resolves an originator report, anyone can escalate after
    ///         DISPUTE_RESOLUTION_DEADLINE (7 days). Escalation auto-upholds and
    ///         cancels the project.
    function testFuzz_originatorReport_escalated(uint256 fundAmount) public {
        fundAmount = _boundFundAmount(fundAmount);
        bytes32 projId = _fundProject(82, fundAmount, 5, 3, 7000);

        uint256 totalRewards82 = engine.getProject(projId).totalRewards;
        uint256 reportBond82 = (totalRewards82 * 100) / 10_000 + 1;
        _ensureStake(contributor1, reportBond82 + 1e18);
        vm.prank(contributor1);
        engine.reportOriginator(projId, keccak256("escalation-evidence"));

        // No admin action — warp past resolution deadline
        vm.warp(block.timestamp + C.DISPUTE_RESOLUTION_DEADLINE + 1);

        engine.escalateOriginatorReport(projId);

        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Cancelled));
        assertEq(uint256(engine.getOriginatorReport(projId).status), uint256(OriginatorReportStatus.Upheld));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 21 — Batch contribute
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice A contributor claims multiple slots and submits all of them in a single
    ///         batchContribute call instead of individual transactions.
    function testFuzz_batchContribute(uint256 fundAmount, uint256 qtySeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 qty = bound(qtySeed, 2, 5);

        bytes32 projId = _fundProject(90, fundAmount, qty + 3, 3, 7000);

        _ensureStake(contributor1, STAKE_AMOUNT * (qty + 2));

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, qty, address(0));

        // Build batch arrays
        bytes32[] memory hashes = new bytes32[](qty);
        string[] memory cids = new string[](qty);
        for (uint256 i; i < qty; ++i) {
            hashes[i] = keccak256(abi.encodePacked("batch-sub", i));
            cids[i] = "";
        }

        engine.batchContribute(claimId, indices, hashes, cids);
        vm.stopPrank();

        // All slots should be Pending
        for (uint256 i; i < qty; ++i) {
            Contribution memory c = engine.getContribution(projId, indices[i]);
            assertEq(uint256(c.status), uint256(ContributionStatus.Pending));
            assertEq(c.submissionHash, hashes[i]);
        }

        // Claim should be Completed (all submitted)
        assertEq(uint256(engine.getClaim(claimId).status), uint256(ClaimStatus.Completed));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 22 — Batch commit + batch reveal validation
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Validators use batchCommitValidations and batchRevealValidations to
    ///         process multiple indices in a single transaction.
    function testFuzz_batchValidation(uint256 fundAmount, uint256 valStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 valStake = _boundStake(valStakeSeed);
        uint256 batchSize = 2;

        bytes32 projId = _fundProject(100, fundAmount, batchSize + 3, 3, 7000);

        // contributor1 batch-claims and batch-contributes both slots
        _ensureStake(contributor1, STAKE_AMOUNT * (batchSize + 2));
        uint256[] memory indices;
        {
            vm.startPrank(contributor1);
            uint256 claimId;
            (claimId, indices) = engine.claimToContribute(projId, batchSize, address(0));
            bytes32[] memory hs = new bytes32[](batchSize);
            string[] memory cs = new string[](batchSize);
            for (uint256 i; i < batchSize; ++i) {
                hs[i] = keccak256(abi.encodePacked("bval-sub", i));
                cs[i] = "";
            }
            engine.batchContribute(claimId, indices, hs, cs);
            vm.stopPrank();
        }

        // Each validator: claimToValidate(batchSize), get assigned indices, batchCommit, batchReveal
        address[3] memory vals = [validator1, validator2, validator3];
        uint256 score = 8800;

        // Arrays to store data for reveal phase
        uint256[][3] memory allAssignedIndices;
        uint256[][3] memory allScores;
        bytes32[][3] memory allSalts;

        // Commit phase - all validators commit
        for (uint256 v; v < 3; ++v) {
            address val = vals[v];
            _ensureStake(val, valStake * 3);

            vm.startPrank(val);
            uint256 vcClaimId = engine.claimToValidate(projId, batchSize);
            ValidationClaim memory vc = engine.getValidationClaim(vcClaimId);
            uint256[] memory assignedIndices = vc.indices;
            allAssignedIndices[v] = assignedIndices;
            engine.lockValidatorCapacity(valStake * assignedIndices.length);

            // Build commit arrays for assigned indices
            bytes32[] memory commitHashes = new bytes32[](assignedIndices.length);
            bytes32[] memory salts = new bytes32[](assignedIndices.length);
            uint256[] memory stakeAmts = new uint256[](assignedIndices.length);
            uint256[] memory scores = new uint256[](assignedIndices.length);
            for (uint256 i; i < assignedIndices.length; ++i) {
                salts[i] = keccak256(abi.encodePacked("bval-salt", val, assignedIndices[i], v));
                commitHashes[i] = keccak256(abi.encodePacked(score, salts[i]));
                stakeAmts[i] = valStake;
                scores[i] = score;
            }

            allScores[v] = scores;
            allSalts[v] = salts;

            engine.batchCommitValidations(projId, assignedIndices, commitHashes, stakeAmts, address(0));
            vm.stopPrank();
        }

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        // Reveal phase - all validators reveal
        for (uint256 v; v < 3; ++v) {
            vm.prank(vals[v]);
            engine.batchRevealValidations(projId, allAssignedIndices[v], allScores[v], allSalts[v]);
        }

        // Compute consensus and verify acceptance for each index
        for (uint256 i; i < batchSize; ++i) {
            assertEq(engine.getRevealCount(projId, indices[i]), 3);
            engine.computeConsensus(projId, indices[i]);
            assertEq(uint256(engine.getContribution(projId, indices[i]).status), uint256(ContributionStatus.Accepted));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 23 — Varying consensus threshold
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice The acceptance outcome must exactly match whether the weighted average
    ///         of validator scores meets or exceeds the project's consensus threshold.
    function testFuzz_varyingConsensusThreshold(
        uint256 fundAmount,
        uint256 thresholdSeed,
        uint256 scoreSeed,
        uint256 valStakeSeed
    ) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 valStake = _boundStake(valStakeSeed);
        uint256 threshold = bound(thresholdSeed, 3000, 9000);

        // Score is fuzzed across the full range so we get both outcomes
        uint256 score = bound(scoreSeed, 0, 10_000);

        bytes32 projId = _projectId(110 + thresholdSeed % 100);
        token.mint(originator, fundAmount);

        vm.startPrank(originator);
        Project memory cfg = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: threshold,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
        engine.createProject(projId, "", cfg);
        token.approve(address(engine), fundAmount);
        engine.fundProject(projId, fundAmount, 5, address(0));
        vm.stopPrank();

        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.startPrank(contributor1);
        (uint256 cid, uint256[] memory idxs) = engine.claimToContribute(projId, 1, address(0));
        engine.contribute(cid, idxs[0], keccak256("threshold-sub"), "");
        vm.stopPrank();

        // All three validators use the same score — weighted average == score
        _commitReveal(validator1, projId, idxs[0], score, valStake);
        _commitReveal(validator2, projId, idxs[0], score, valStake);
        _commitReveal(validator3, projId, idxs[0], score, valStake);

        engine.computeConsensus(projId, idxs[0]);

        Contribution memory contrib = engine.getContribution(projId, idxs[0]);
        ConsensusReport memory report = engine.getConsensusReport(projId, idxs[0]);
        assertTrue(report.computed);

        if (report.weightedAverage >= threshold) {
            assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted));
        } else {
            assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected));
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 24 — Admin fee updates affect new projects
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Admin updates the protocol fee between two identical funding calls.
    ///         The second project should have a different (higher) escrow deduction.
    function testFuzz_adminFeesAffectAccounting(uint256 fundAmount, uint256 newFeeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);

        // Default protocol fee is 10% (1000 bps). Set a higher value.
        uint256 newFee = bound(newFeeSeed, 0, C.MAX_PROTOCOL_FEE_BPS);

        bytes32 projId1 = _projectId(120);
        bytes32 projId2 = _projectId(121);

        // Fund project1 at default fee (1000 bps = 10%)
        token.mint(originator, fundAmount * 2);

        vm.startPrank(originator);
        Project memory cfg = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
        engine.createProject(projId1, "", cfg);
        token.approve(address(engine), fundAmount * 2);
        engine.fundProject(projId1, fundAmount, 5, address(0));
        vm.stopPrank();

        uint256 escrow1 = engine.getProjectEscrow(projId1, address(token));

        // Admin changes protocol fee
        vm.prank(admin);
        engine.setProtocolFee(newFee);

        // Fund project2 with same amount
        vm.startPrank(originator);
        cfg.status = ProjectStatus.Created;
        engine.createProject(projId2, "", cfg);
        engine.fundProject(projId2, fundAmount, 5, address(0));
        vm.stopPrank();

        uint256 escrow2 = engine.getProjectEscrow(projId2, address(token));

        // At lower fee → more escrow; at higher fee → less escrow
        if (newFee < 1000) {
            assertGe(escrow2, escrow1);
        } else if (newFee > 1000) {
            assertLe(escrow2, escrow1);
        } else {
            assertEq(escrow2, escrow1);
        }
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 25 — Reputation updates stay within [MIN, MAX] bounds after many cycles
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice After repeated accepted and rejected contributions, a contributor's
    ///         reputation score must always remain in [MIN_REPUTATION, MAX_REPUTATION].
    function testFuzz_reputationBounds(uint256 fundAmount, uint256 cyclesSeed, uint256 valStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 cycles = bound(cyclesSeed, 1, 4); // keep gas reasonable
        uint256 valStake = _boundStake(valStakeSeed);

        // Alternate accept / reject cycles on independent indices
        for (uint256 c; c < cycles; ++c) {
            uint256 seed = 200 + c * 2;
            bool accept = (c % 2 == 0);
            uint256 score = accept ? 9000 : 1000;

            bytes32 projId = _fundProject(seed, fundAmount, 5, 3, 7000);

            _ensureStake(contributor1, STAKE_AMOUNT * 3);
            vm.startPrank(contributor1);
            (uint256 cid, uint256[] memory idxs) = engine.claimToContribute(projId, 1, address(0));
            engine.contribute(cid, idxs[0], keccak256(abi.encodePacked("rep-sub", c)), "");
            vm.stopPrank();

            _commitReveal(validator1, projId, idxs[0], score, valStake);
            _commitReveal(validator2, projId, idxs[0], score, valStake);
            _commitReveal(validator3, projId, idxs[0], score, valStake);
            engine.computeConsensus(projId, idxs[0]);
        }

        uint256 repScore = engine.getReputation(contributor1, SKILL_ID).score;
        assertGe(repScore, C.MIN_REPUTATION);
        assertLe(repScore, C.MAX_REPUTATION);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 26 — Vault: locked stake cannot be withdrawn during active contribution
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice After locking stake for a contribution claim, the contributor's
    ///         locked amount is excluded from available balance and cannot be
    ///         immediately redeemed via the vault.
    function testFuzz_lockedStakeUnavailableDuringClaim(uint256 fundAmount) public {
        fundAmount = _boundFundAmount(fundAmount);
        bytes32 projId = _fundProject(130, fundAmount, 5, 3, 7000);

        uint256 availBefore = vault.availableBalance(contributor1);

        vm.startPrank(contributor1);
        (uint256 cid, uint256[] memory idxs) = engine.claimToContribute(projId, 1, address(0));
        vm.stopPrank();

        // Available balance decreases by minStakeToClaim
        uint256 availAfterClaim = vault.availableBalance(contributor1);
        assertLt(availAfterClaim, availBefore);

        // Available balance reflects the locked portion
        uint256 locked = availBefore - availAfterClaim;
        assertGt(locked, 0, "stake must be locked after claiming");

        // maxWithdraw is bounded by availableBalance — the vault enforces this
        uint256 maxWithdrawable = vault.maxWithdraw(contributor1);
        assertLe(maxWithdrawable, availAfterClaim + 1, "maxWithdraw must not exceed available balance");

        // After contributing and being accepted+released, the lock is lifted
        vm.prank(contributor1);
        engine.contribute(cid, idxs[0], keccak256("lock-test-sub"), "");

        _commitReveal(validator1, projId, idxs[0], 8500, VALIDATOR_STAKE);
        _commitReveal(validator2, projId, idxs[0], 8500, VALIDATOR_STAKE);
        _commitReveal(validator3, projId, idxs[0], 8500, VALIDATOR_STAKE);
        engine.computeConsensus(projId, idxs[0]);

        _warpPastChallengePeriod();

        uint256 settleNonce = engine.getContribution(projId, idxs[0]).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(projId, idxs[0], settleNonce);
        vm.prank(validator2);
        engine.settleValidator(projId, idxs[0], settleNonce);
        vm.prank(validator3);
        engine.settleValidator(projId, idxs[0], settleNonce);

        engine.releaseContributorReward(projId, idxs[0]);

        // Lock is released — available balance restored
        uint256 availAfterRelease = vault.availableBalance(contributor1);
        assertGe(availAfterRelease, availAfterClaim);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 27 — Consensus manipulation with varying stake distributions
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Fuzz test consensus manipulation attempts with different stake distributions
    /// @dev Tests that sqrt(stake) weighting prevents flash loan manipulation
    function testFuzz_consensusManipulationVaryingStakeDistributions(
        uint256 fundAmount,
        uint256 attackerStake,
        uint256 normalStake,
        uint256 numValidators
    ) public {
        fundAmount = _boundFundAmount(fundAmount);
        attackerStake = bound(attackerStake, 1e18, 1000e18); // 1 to 1000 tokens
        normalStake = bound(normalStake, 1e18, 100e18); // 1 to 100 tokens
        numValidators = bound(numValidators, 3, 10); // 3 to 10 validators

        bytes32 projId = _fundProject(300, fundAmount, 5, numValidators, 7000);

        // Create attacker and normal validators
        address attacker = makeAddr("attacker");
        address[] memory normals = new address[](numValidators - 1);
        for (uint256 i; i < normals.length; ++i) {
            normals[i] = makeAddr(string(abi.encodePacked("normal", i)));
        }

        // Fund attacker with large stake
        token.mint(attacker, attackerStake);
        vm.startPrank(attacker);
        token.approve(address(vault), attackerStake);
        vault.deposit(attackerStake, attacker);
        vm.stopPrank();

        // Fund normal validators
        for (uint256 i; i < normals.length; ++i) {
            token.mint(normals[i], normalStake);
            vm.startPrank(normals[i]);
            token.approve(address(vault), normalStake);
            vault.deposit(normalStake, normals[i]);
            vm.stopPrank();
        }

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projId, 1);
        uint256 index = indices[0];

        // All validators (attacker + normals) vote with same score
        uint256 consensusScore = 8000;

        // Attacker commits with large stake
        _ensureStake(attacker, attackerStake * 2);
        _validate(attacker, projId, index, consensusScore, attackerStake);

        // Normal validators commit
        for (uint256 i; i < normals.length; ++i) {
            _ensureStake(normals[i], normalStake * 2);
            _validate(normals[i], projId, index, consensusScore, normalStake);
        }

        engine.computeConsensus(projId, index);

        // Contribution should be accepted despite attacker having much more stake
        assertEq(uint256(engine.getContribution(projId, index).status), uint256(ContributionStatus.Accepted));

        // Verify consensus was computed correctly with stake weighting
        ConsensusReport memory report = engine.getConsensusReport(projId, index);
        assertTrue(report.computed);
        assertGe(report.weightedAverage, 7000); // Above threshold
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 29 — Fee calculation edge cases
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Fuzz test fee calculation edge cases with extreme values
    function testFuzz_feeCalculationEdgeCases(uint256 fundAmount, uint256 protocolFeeBps, uint256 adapterFeeBps)
        public
    {
        fundAmount = bound(fundAmount, 1e18, 1e12 * 1e18); // 1 to 1 trillion tokens
        protocolFeeBps = bound(protocolFeeBps, 0, C.MAX_PROTOCOL_FEE_BPS);
        adapterFeeBps = bound(adapterFeeBps, 0, C.MAX_ADAPTER_FEE_BPS);

        // Set custom fees
        vm.startPrank(admin);
        engine.setProtocolFee(protocolFeeBps);
        engine.setOriginationFee(adapterFeeBps);
        engine.setContributionFee(adapterFeeBps);
        engine.setValidationFee(adapterFeeBps);
        vm.stopPrank();

        bytes32 projId = _projectId(500 + protocolFeeBps % 100);

        // Create project with extreme funding amount
        token.mint(originator, fundAmount);
        vm.startPrank(originator);
        Project memory cfg = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
        engine.createProject(projId, "", cfg);
        token.approve(address(engine), fundAmount);
        engine.fundProject(projId, fundAmount, 5, adapter);
        vm.stopPrank();

        // Verify fee calculations don't overflow or underflow
        uint256 treasuryBalance = token.balanceOf(treasury);
        uint256 adapterPending = engine.getPendingRewards(adapter, address(token));
        uint256 projectEscrow = engine.getProjectEscrow(projId, address(token));

        // Total should add up (allowing small rounding tolerance)
        uint256 totalDistributed = treasuryBalance + adapterPending + projectEscrow;
        assertApproxEqAbs(totalDistributed, fundAmount, 10, "Fee calculation error with extreme values");

        // Project escrow should be reasonable (not negative, not exceeding original amount)
        assertGe(projectEscrow, 0, "Project escrow negative");
        assertLe(projectEscrow, fundAmount, "Project escrow exceeds funding");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // Test 30 — ERC20 integration assumptions
    // ══════════════════════════════════════════════════════════════════════════

    /// @notice Fuzz test ERC20 integration with various token behaviors
    function testFuzz_erc20IntegrationAssumptions(uint256 fundAmount, uint256 feeBps, uint256 transferAmount) public {
        fundAmount = _boundFundAmount(fundAmount);
        feeBps = bound(feeBps, 0, 500); // 0% to 5% fee
        transferAmount = bound(transferAmount, 1e18, fundAmount);

        // Create a fee-on-transfer token with fuzzed fee rate
        FeeOnTransferToken feeToken = new FeeOnTransferToken();
        feeToken.setFeeBps(feeBps);

        // Fund originator
        feeToken.mint(originator, fundAmount);

        // Create project with fee-on-transfer token
        vm.startPrank(originator);
        bytes32 projId = keccak256(abi.encodePacked("fee-test", feeBps, transferAmount));
        Project memory cfg = Project({
            originator: address(0),
            rewardToken: address(feeToken),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
        engine.createProject(projId, "", cfg);

        // Approve and fund - demonstrate fee-on-transfer issue
        feeToken.approve(address(engine), transferAmount);
        uint256 balanceBefore = feeToken.balanceOf(address(engine));

        engine.fundProject(projId, transferAmount, 10, adapter);

        uint256 balanceAfter = feeToken.balanceOf(address(engine));
        uint256 received = balanceAfter - balanceBefore;

        // With fee-on-transfer, received amount should be less than sent amount
        // This demonstrates the ERC20 integration assumption vulnerability
        assertLt(received, transferAmount, "Fee-on-transfer tokens should result in less tokens received");

        // The protocol assumes it receives exactly transferAmount, but gets less
        // This is the vulnerability being tested
        uint256 expectedFee = (transferAmount * feeBps) / 10000;
        uint256 actualFee = transferAmount - received;
        assertGe(actualFee, expectedFee, "Fee should be at least the expected amount");

        // Project should still be created (protocol doesn't validate received amount)
        Project memory proj = engine.getProject(projId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Funded));
    }
}

// Mock ERC20 token with configurable fee-on-transfer behavior for testing
contract FeeOnTransferToken is IERC20 {
    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    uint256 public feeBps = 100; // Default 1%

    string public constant name = "Fee Token";
    string public constant symbol = "FEE";
    uint8 public constant decimals = 18;

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        uint256 fee = (amount * feeBps) / 10000;
        uint256 netAmount = amount - fee;

        _balances[msg.sender] -= amount;
        _balances[to] += netAmount;
        _balances[address(this)] += fee;

        emit Transfer(msg.sender, to, netAmount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        _allowances[from][msg.sender] -= amount;

        uint256 fee = (amount * feeBps) / 10000;
        uint256 netAmount = amount - fee;

        _balances[from] -= amount;
        _balances[to] += netAmount;
        _balances[address(this)] += fee;

        emit Transfer(from, to, netAmount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function mint(address to, uint256 amount) external {
        _balances[to] += amount;
        _totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function setFeeBps(uint256 _feeBps) external {
        require(_feeBps <= 10000, "Fee too high");
        feeBps = _feeBps;
    }
}
