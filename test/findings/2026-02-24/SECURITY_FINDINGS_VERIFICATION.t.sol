// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {stdError} from "forge-std/StdError.sol";
import {Vm} from "forge-std/Vm.sol";
import {
    Project,
    ProjectStatus,
    Contribution,
    ContributionStatus,
    DisputeStatus,
    OriginatorReportStatus,
    Reputation,
    StakeAccount
} from "src/Types.sol";

/// @title Security Findings Verification — 2026-02-24
/// @notice PoC tests for all findings in test/findings/2026-02-24/SECURITY_AUDIT_REPORT.md
contract SecurityFindings_2026_02_24 is BaseTest {
    // ════════════════════════════════════════════════════════════════════
    // Helpers
    // ════════════════════════════════════════════════════════════════════

    function _createSimpleProject(bytes32 pid, uint256 amount, uint256 qty) internal returns (bytes32) {
        vm.startPrank(originator);

        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: 0,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            acceptedContributions: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        engine.createProject(pid, "", config);
        token.approve(address(engine), amount);
        engine.fundProject(pid, amount, qty, address(0));

        vm.stopPrank();
        return pid;
    }

    function _claimAndContributeSimple(address user, bytes32 pid, uint256 qty)
        internal
        returns (uint256 claimId, uint256[] memory indices)
    {
        vm.startPrank(user);
        (claimId, indices) = engine.claimToContribute(pid, qty, address(0));
        for (uint256 i; i < indices.length; ++i) {
            engine.contribute(claimId, indices[i], keccak256(abi.encodePacked("sub", indices[i])), "");
        }
        vm.stopPrank();
    }

    function _commitAndRevealSimple(address val, bytes32 pid, uint256 index, uint256 score, uint256 stakeAmt) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(val, stakeAmt * 2);

        vm.startPrank(val);

        engine.claimToValidate(pid, 1);
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(pid, index, commitHash, stakeAmt, address(0));

        vm.stopPrank();

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(val);
        engine.revealValidation(pid, index, score, salt);
    }

    // ════════════════════════════════════════════════════════════════════
    // SEC-C-01 FIX: settleValidator enforces challenge period
    // ════════════════════════════════════════════════════════════════════

    /// @notice FIX: Validators cannot settle during the challenge period.
    ///         Settlement reverts with ChallengeNotElapsed until the window closes.
    ///         After a dispute is upheld, validators recover stake but receive no reward.
    function test_SEC_C_01_settleValidatorDuringChallengePeriod() public {
        bytes32 pid = _createSimpleProject(keccak256("c01"), 1_000e18, 1);
        (, uint256[] memory indices) = _claimAndContributeSimple(contributor1, pid, 1);
        uint256 idx = indices[0];

        _commitAndRevealSimple(validator1, pid, idx, 8000, VALIDATOR_STAKE);
        _commitAndRevealSimple(validator2, pid, idx, 8000, VALIDATOR_STAKE);
        _commitAndRevealSimple(validator3, pid, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(pid, idx);

        Contribution memory contrib = engine.getContribution(pid, idx);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted));
        assertGt(contrib.challengeEndsAt, block.timestamp, "challenge period should be active");

        // FIX: Settlement during challenge period now reverts
        vm.prank(validator1);
        vm.expectRevert(ISapienCore.ChallengeNotElapsed.selector);
        engine.settleValidator(pid, idx, 0);

        // Open and uphold a dispute during the challenge window
        _ensureStake(contributor2, 200e18);
        vm.prank(contributor2);
        engine.openDispute(pid, idx, keccak256("evidence"), "cid");

        vm.prank(admin);
        engine.resolveDispute(pid, idx, 0, true);

        assertEq(uint256(engine.getDispute(pid, idx).status), uint256(DisputeStatus.Upheld));

        // After upheld dispute: validator can settle to recover stake but gets no reward
        uint256 inFlightBefore = vault.getStakeAccount(validator1).inFlight;
        assertGt(inFlightBefore, 0, "validator has in-flight (committed) stake");

        vm.prank(validator1);
        engine.settleValidator(pid, idx, 0);

        uint256 inFlightAfter = vault.getStakeAccount(validator1).inFlight;
        assertEq(inFlightAfter, 0, "validator stake released after upheld dispute");
        assertEq(engine.getPendingRewards(validator1, address(token)), 0, "no reward paid after upheld dispute");
    }

    // ════════════════════════════════════════════════════════════════════
    // SEC-H-01 FIX: Escrow cap prevents accounting debt
    // ════════════════════════════════════════════════════════════════════

    /// @notice FIX: When escrow is drained by dispute compensation and a recycled
    ///         slot is later accepted, validator settlement no longer reverts.
    ///         Validators receive proportionally reduced rewards instead.
    function test_SEC_H_01_escrowInsolvencyViaDisputeRejectionRecycle() public {
        bytes32 pid = _createSimpleProject(keccak256("h01"), 1_000e18, 1);

        // Step 1: Contribution submitted and rejected by consensus (low scores)
        (, uint256[] memory indices) = _claimAndContributeSimple(contributor1, pid, 1);
        uint256 idx = indices[0];

        _commitAndRevealSimple(validator1, pid, idx, 5000, VALIDATOR_STAKE);
        _commitAndRevealSimple(validator2, pid, idx, 5000, VALIDATOR_STAKE);
        _commitAndRevealSimple(validator3, pid, idx, 5000, VALIDATOR_STAKE);
        engine.computeConsensus(pid, idx);

        assertEq(uint256(engine.getContribution(pid, idx).status), uint256(ContributionStatus.Rejected));

        // Step 2: Open and uphold dispute on the rejected contribution — drains escrow
        _ensureStake(contributor2, 200e18);
        vm.prank(contributor2);
        engine.openDispute(pid, idx, keccak256("rejection-dispute"), "cid");

        vm.prank(admin);
        engine.resolveDispute(pid, idx, 0, true);

        assertEq(engine.getProjectEscrow(pid, address(token)), 0, "escrow fully drained by dispute");

        // Step 3: Settle nonce-0 validators — rejected contribution, no rewards, no revert
        vm.prank(validator1);
        engine.settleValidator(pid, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(pid, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(pid, idx, 0);

        // Step 4: New contributor claims recycled slot, submits, gets accepted
        (, uint256[] memory newIndices) = _claimAndContributeSimple(contributor2, pid, 1);
        assertEq(newIndices[0], idx, "should reclaim the same index");

        _commitAndRevealSimple(validator1, pid, idx, 8000, VALIDATOR_STAKE);
        _commitAndRevealSimple(validator2, pid, idx, 8000, VALIDATOR_STAKE);
        _commitAndRevealSimple(validator3, pid, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(pid, idx);
        assertEq(uint256(engine.getContribution(pid, idx).status), uint256(ContributionStatus.Accepted));

        // Step 5: FIX — settlement succeeds even with 0 escrow; validator gets 0 reward (no revert)
        _warpPastChallengePeriod();
        vm.prank(validator1);
        engine.settleValidator(pid, idx, 1);

        assertEq(engine.getPendingRewards(validator1, address(token)), 0, "reward is 0 when escrow is empty");
    }

    // ════════════════════════════════════════════════════════════════════
    // SEC-H-02 FIX: Claim expiry succeeds when recycled indices are skipped
    // ════════════════════════════════════════════════════════════════════

    /// @notice FIX: When index A is recycled after rejection, expireClaim skips it
    ///         and still processes index B (Reserved), unlocking the contributor's stake.
    function test_SEC_H_02_claimExpiryBlockedByRejectedRecycle() public {
        bytes32 pid = _createAndFundProject(keccak256("h02"), 2_000e18, 2);

        // Contributor1 claims 2 slots
        vm.prank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(pid, 2, address(0));
        uint256 idxA = indices[0];
        uint256 idxB = indices[1];

        // Submit only index A
        vm.prank(contributor1);
        engine.contribute(claimId, idxA, keccak256("submission-a"), "");

        // Validate index A with low scores → rejected, slot recycled
        _commitAndReveal(validator1, pid, idxA, 5000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, pid, idxA, 5000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, pid, idxA, 5000, VALIDATOR_STAKE);
        engine.computeConsensus(pid, idxA);
        assertEq(uint256(engine.getContribution(pid, idxA).status), uint256(ContributionStatus.Rejected));

        // Settle validators before recycling
        vm.warp(block.timestamp + engine.challengePeriod() + 1);
        vm.prank(validator1);
        engine.settleValidator(pid, idxA, 0);
        vm.prank(validator2);
        engine.settleValidator(pid, idxA, 0);
        vm.prank(validator3);
        engine.settleValidator(pid, idxA, 0);

        // New contributor claims the recycled slot A — index A's claimId is now different
        vm.prank(contributor2);
        engine.claimToContribute(pid, 1, address(0));

        // Warp past contributor1's claim deadline
        vm.warp(block.timestamp + engine.claimDeadline() + 1);

        uint256 lockBefore = vault.getStakeAccount(contributor1).contributorLock;
        assertGt(lockBefore, 0, "contributor stake locked for unsubmitted slot B");

        // FIX: expireClaim now skips the recycled index A and processes B
        uint256[] memory expireIndices = new uint256[](2);
        expireIndices[0] = idxA;
        expireIndices[1] = idxB;

        engine.expireClaim(claimId, expireIndices);

        // Contributor1's stake for index B is now unlocked (slashed for unsubmitted)
        uint256 lockAfter = vault.getStakeAccount(contributor1).contributorLock;
        assertLt(lockAfter, lockBefore, "contributor stake reduced after successful expiry");
    }

    // ════════════════════════════════════════════════════════════════════
    // SEC-H-03 FIX: Cancelled project escrow refund has a delay
    // ════════════════════════════════════════════════════════════════════

    /// @notice FIX: After project cancellation, refundEscrow requires the same 30-day
    ///         delay as completed projects, giving participants time to settle first.
    function test_SEC_H_03_immediateEscrowDrainAfterCancellation() public {
        bytes32 pid = _createSimpleProject(keccak256("h03"), 1_000e18, 1);

        (, uint256[] memory indices) = _claimAndContributeSimple(contributor1, pid, 1);
        uint256 idx = indices[0];

        _commitAndRevealSimple(validator1, pid, idx, 8000, VALIDATOR_STAKE);
        _commitAndRevealSimple(validator2, pid, idx, 8000, VALIDATOR_STAKE);
        _commitAndRevealSimple(validator3, pid, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(pid, idx);
        assertEq(uint256(engine.getContribution(pid, idx).status), uint256(ContributionStatus.Accepted));

        // Cancel the project via originator report
        _ensureStake(contributor2, 200e18);
        vm.prank(contributor2);
        engine.reportOriginator(pid, keccak256("misconduct"));

        vm.prank(admin);
        engine.resolveOriginatorReport(pid, true);
        assertEq(uint256(engine.getProject(pid).status), uint256(ProjectStatus.Cancelled));

        // FIX: Immediate refundEscrow now reverts — delay required
        vm.prank(originator);
        vm.expectRevert(ISapienCore.ChallengeNotElapsed.selector);
        engine.refundEscrow(pid);

        // POQ-4: Validators CAN settle during the delay window (stake released, no rewards)
        _warpPastChallengePeriod();
        uint256 inFlightBefore = vault.getStakeAccount(validator1).inFlight;
        assertGt(inFlightBefore, 0, "validator has in-flight stake before settlement");

        vm.prank(validator1);
        engine.settleValidator(pid, idx, 0);

        assertEq(vault.getStakeAccount(validator1).inFlight, 0, "validator stake released after settlement");
        assertEq(engine.getPendingRewards(validator1, address(token)), 0, "no reward on cancelled project");
    }

    // ════════════════════════════════════════════════════════════════════
    // SEC-M-01 FIX: removeProject unlocks participant stakes
    // ════════════════════════════════════════════════════════════════════

    /// @notice FIX: When an operator removes an active project, contributor stakes
    ///         are unlocked for all in-flight (Reserved or Pending) contributions.
    function test_SEC_M_01_removeProjectStrandsParticipantStakes() public {
        bytes32 pid = _createAndFundProject(keccak256("m01"), 1_000e18, 1);

        // Contributor claims and submits — stake locked
        _claimAndContribute(contributor1, pid, 1);
        uint256 lockBefore = vault.getStakeAccount(contributor1).contributorLock;
        assertEq(lockBefore, STAKE_AMOUNT, "stake should be locked for submitted contribution");

        // Operator removes the project
        vm.prank(admin);
        engine.removeProject(pid);
        assertEq(uint256(engine.getProject(pid).status), uint256(ProjectStatus.Cancelled));

        // FIX: Contributor's stake is now unlocked by the wind-down logic
        uint256 lockAfter = vault.getStakeAccount(contributor1).contributorLock;
        assertEq(lockAfter, 0, "contributor stake unlocked after project removal");
    }

    // ════════════════════════════════════════════════════════════════════
    // SEC-M-02 FIX: Minimum bounds enforced on admin-configurable deadlines
    // ════════════════════════════════════════════════════════════════════

    /// @notice FIX: Setting challengePeriod to 0 (or any value below MIN_CHALLENGE_PERIOD)
    ///         now reverts with DeadlineTooShort.
    function test_SEC_M_02_zeroChallengePeriodDisablesDisputes() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.DeadlineTooShort.selector, 0, C.MIN_CHALLENGE_PERIOD));
        engine.setChallengePeriod(0);

        // Confirm the period was not changed
        assertEq(engine.challengePeriod(), C.DEFAULT_CHALLENGE_PERIOD, "challenge period unchanged");

        // Setting to MIN is accepted
        vm.prank(admin);
        engine.setChallengePeriod(C.MIN_CHALLENGE_PERIOD);
        assertEq(engine.challengePeriod(), C.MIN_CHALLENGE_PERIOD);
    }

    // ════════════════════════════════════════════════════════════════════
    // SEC-M-03 / POQ-4: Settlement on cancelled projects releases stake without rewards
    // ════════════════════════════════════════════════════════════════════

    /// @notice POQ-4 supersedes SEC-M-03: Settlement on cancelled projects now succeeds
    ///         but only releases the validator's committed stake — no rewards are paid.
    function test_SEC_M_03_settlementProceedsOnCancelledProject() public {
        bytes32 pid = _createSimpleProject(keccak256("m03"), 1_000e18, 1);
        (, uint256[] memory indices) = _claimAndContributeSimple(contributor1, pid, 1);
        uint256 idx = indices[0];

        _commitAndRevealSimple(validator1, pid, idx, 8000, VALIDATOR_STAKE);
        _commitAndRevealSimple(validator2, pid, idx, 8000, VALIDATOR_STAKE);
        _commitAndRevealSimple(validator3, pid, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(pid, idx);

        // Cancel the project
        vm.prank(admin);
        engine.removeProject(pid);
        assertEq(uint256(engine.getProject(pid).status), uint256(ProjectStatus.Cancelled));

        // POQ-4: Settlement succeeds — stake is released, no rewards paid
        uint256 inFlightBefore = vault.getStakeAccount(validator1).inFlight;
        assertGt(inFlightBefore, 0, "validator has in-flight stake");

        vm.prank(validator1);
        engine.settleValidator(pid, idx, 0);

        assertTrue(engine.isValidatorSettled(pid, idx, 0, validator1), "validator should be settled");
        assertEq(vault.getStakeAccount(validator1).inFlight, 0, "in-flight stake released");
        assertEq(engine.getPendingRewards(validator1, address(token)), 0, "no reward on cancelled project");
    }

    // ════════════════════════════════════════════════════════════════════
    // SEC-L-01 FIX: Single ProjectCancelled event on escalation
    // ════════════════════════════════════════════════════════════════════

    /// @notice FIX: escalateOriginatorReport now emits ProjectCancelled exactly once.
    function test_SEC_L_01_duplicateProjectCancelledEvent() public {
        bytes32 pid = _createSimpleProject(keccak256("l01"), 1_000e18, 1);

        _ensureStake(contributor2, 200e18);
        vm.prank(contributor2);
        engine.reportOriginator(pid, keccak256("evidence"));

        vm.warp(block.timestamp + C.DISPUTE_RESOLUTION_DEADLINE + 1);

        vm.recordLogs();
        engine.escalateOriginatorReport(pid);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 cancelledTopic = ISapienCore.ProjectCancelled.selector;
        uint256 cancelCount;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length > 0 && logs[i].topics[0] == cancelledTopic) {
                cancelCount++;
            }
        }

        assertEq(cancelCount, 1, "ProjectCancelled emitted exactly once after fix");
    }

    // ════════════════════════════════════════════════════════════════════
    // SEC-L-02 FIX: Reputation event oldScore reflects post-decay value
    // ════════════════════════════════════════════════════════════════════

    /// @notice FIX: ReputationUpdated now emits the post-decay score as oldScore,
    ///         so the event accurately reflects the change caused by the action alone.
    function test_SEC_L_02_reputationOldScoreInaccurate() public {
        // First project creation initialises originator reputation
        _createSimpleProject(keccak256("l02-a"), 1_000e18, 1);

        // Stored score is now DEFAULT_REPUTATION (5000) + SUCCESS_INCREASE (10) = 5010
        Reputation memory rep = engine.getReputation(originator, C.ORIGINATOR_ROLE_KEY);
        uint256 storedScore = rep.score;
        assertEq(storedScore, C.DEFAULT_REPUTATION + C.SUCCESS_INCREASE, "initial stored score");

        // Wait 10 days for significant decay to accumulate
        vm.warp(block.timestamp + 10 days);

        // Compute the expected decayed score
        uint256 decayRateBps = engine.decayRateBps();
        uint256 daysSince = 10;
        uint256 decayAmount = (storedScore * decayRateBps * daysSince) / C.BPS;
        uint256 expectedDecayedScore =
            storedScore > decayAmount + C.MIN_REPUTATION ? storedScore - decayAmount : C.MIN_REPUTATION;

        // Create another project → triggers reputation update with success=true
        vm.recordLogs();
        _createSimpleProject(keccak256("l02-b"), 1_000e18, 1);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bytes32 repTopic = ISapienCore.ReputationUpdated.selector;
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics.length > 1 && logs[i].topics[0] == repTopic) {
                address eventUser = address(uint160(uint256(logs[i].topics[1])));
                if (eventUser == originator) {
                    (uint256 oldScore, uint256 newScore) = abi.decode(logs[i].data, (uint256, uint256));
                    // FIX: oldScore is now the post-decay value, not the stored pre-decay value
                    assertEq(oldScore, expectedDecayedScore, "oldScore reflects post-decay value");
                    assertGt(newScore, oldScore, "newScore reflects the success increase on top of decayed base");
                    found = true;
                    break;
                }
            }
        }
        assertTrue(found, "ReputationUpdated event should have been emitted");
    }
}
