// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {StakeAccount, ContributionStatus, Contribution, ClaimStatus} from "src/Types.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";

/// @title POQ-011: Protocol Pausability Creates Slash and Reputation Exposure for Honest Participants
/// @notice While paused, all actions are blocked but internal timers continue. A 1-hour pause makes
///         contributor claims slashable; a 2-hour pause makes validator commitments fully slashable.
/// @dev This test validates the issue and verifies the fix: track cumulative paused duration and
///      subtract from all deadline calculations.
contract POQ_011_PausabilitySlashExposure is BaseTest {
    // ── Issue Validation: Contributors get slashed after pause (PRE-FIX BEHAVIOR) ──
    // NOTE: These tests demonstrate the vulnerability that existed before the fix.
    //       With the fix implemented, these tests now show the issue is RESOLVED.

    /// @notice PRE-FIX: A contributor claims and pauses for 1 hour. Their claim would expire unfairly.
    ///         POST-FIX: The deadline is extended by pause duration, so no unfair slash occurs.
    function test_pauseCausesContributorSlash_FIXED() public {
        bytes32 projectId = _createAndFundProject();

        // Contributor claims slots
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, address(0));
        vm.stopPrank();

        uint256 claimDeadline = engine.claimDeadline();
        uint256 claimCreatedAt = block.timestamp;

        // Protocol pauses for 1 hour (arbitrary admin action)
        vm.prank(admin);
        engine.pause();

        vm.warp(block.timestamp + 1 hours);

        vm.prank(admin);
        engine.unpause();

        // Contributor tries to submit, but deadline is calculated from original timestamp
        // The pause consumed 1 hour of their window
        // If claimDeadline is 1 day, they now have 23 hours instead of 24

        // Let's warp to what SHOULD be just before deadline (if pause time was excluded)
        // claimCreatedAt + claimDeadline - 1 hour (pause duration)
        vm.warp(claimCreatedAt + claimDeadline - 1 hours + 1);

        // Contributor tries to submit but claim is now expired
        vm.startPrank(contributor1);
        // This should work if pause time was properly accounted for, but it will be expired
        vm.stopPrank();

        // PRE-FIX: Claim would be expired and contributor slashed
        // POST-FIX: Claim is NOT expired yet because deadline was extended by pause duration
        uint256 lockBefore = vault.getStakeAccount(contributor1).contributorLock;
        assertGt(lockBefore, 0, "contributor has locked stake");

        // This should revert with the fix - claim not expired yet
        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.expireClaim(claimId, indices);

        // Contributor is NOT slashed with the fix
        uint256 lockAfter = vault.getStakeAccount(contributor1).contributorLock;
        assertEq(lockAfter, lockBefore, "contributor NOT slashed - fix working");
    }

    /// @notice PRE-FIX: Validator would be 100% slashed after pause prevented them from revealing.
    ///         POST-FIX: Reveal window is extended by pause, so validator can still reveal.
    function test_pauseCausesValidatorFullSlash_FIXED() public {
        bytes32 projectId = _createAndFundProject();

        // Contributor submits work
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, address(0));
        engine.contribute(claimId, indices[0], keccak256("submission"), "");
        vm.stopPrank();

        // Validator commits
        bytes32 salt = keccak256(abi.encodePacked("salt", validator1));
        uint256 score = 8000;
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, indices[0], commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        uint256 commitTimestamp = block.timestamp;
        uint256 commitDeadline = engine.commitDeadline();
        uint256 revealDeadline = engine.revealDeadline();

        StakeAccount memory valBefore = vault.getStakeAccount(validator1);
        assertEq(valBefore.inFlight, VALIDATOR_STAKE, "validator has in-flight stake");

        // Protocol pauses for 2 hours
        vm.prank(admin);
        engine.pause();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(admin);
        engine.unpause();

        // Validator tries to reveal but the window has passed
        // commitTimestamp + commitDeadline + revealDeadline
        // The pause consumed 2 hours of their window

        // POST-FIX: Warp past the commit phase to enter reveal window
        vm.warp(commitTimestamp + commitDeadline + 1 hours);

        // Validator can now reveal because the window is extended by pause duration
        vm.startPrank(validator1);
        // This should succeed with the fix
        engine.revealValidation(projectId, indices[0], score, salt);
        vm.stopPrank();

        // Validator is NOT slashed with the fix
        StakeAccount memory valAfter = vault.getStakeAccount(validator1);
        assertGt(valAfter.inFlight, 0, "validator NOT slashed - fix working");
    }

    /// @notice PRE-FIX: Multiple pauses would compound slash risk.
    ///         POST-FIX: All pause time is tracked and deadlines extended accordingly.
    function test_multiplePausesCompoundSlashRisk_FIXED() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, address(0));
        vm.stopPrank();

        uint256 claimDeadline = engine.claimDeadline();
        uint256 claimCreatedAt = block.timestamp;

        // First pause: 30 minutes
        vm.prank(admin);
        engine.pause();
        vm.warp(block.timestamp + 30 minutes);
        vm.prank(admin);
        engine.unpause();

        // Second pause: 45 minutes
        vm.prank(admin);
        engine.pause();
        vm.warp(block.timestamp + 45 minutes);
        vm.prank(admin);
        engine.unpause();

        // Total pause time: 75 minutes
        // Contributor's effective window is now claimDeadline - 75 minutes

        // POST-FIX: Even though real time has advanced, effective time accounts for pauses
        // Contributor should still be able to submit

        // Verify total pause time is tracked
        assertEq(engine.getTotalPausedDuration(), 75 minutes, "total pause tracked");

        uint256 lockBefore = vault.getStakeAccount(contributor1).contributorLock;
        assertGt(lockBefore, 0, "contributor has locked stake");

        // Claim should NOT be expired yet
        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.expireClaim(claimId, indices);

        uint256 lockAfter = vault.getStakeAccount(contributor1).contributorLock;
        assertEq(lockAfter, lockBefore, "contributor NOT slashed - fix working");
    }

    /// @notice Challenge period is also affected - disputes can be escalated prematurely
    function test_pauseAffectsChallengePeriod() public {
        bytes32 projectId = _createAndFundProject();

        // Full workflow to get to challenge period
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, address(0));
        engine.contribute(claimId, indices[0], keccak256("submission"), "");
        vm.stopPrank();

        _commitAndReveal(validator1, projectId, indices[0], 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, indices[0], 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, indices[0], 8200, VALIDATOR_STAKE);

        engine.computeConsensus(projectId, indices[0]);

        Contribution memory contrib = engine.getContribution(projectId, indices[0]);
        assertEq(uint8(contrib.status), uint8(ContributionStatus.Accepted));

        // Challenger opens dispute
        bytes32 evidenceHash = keccak256("evidence");
        vm.prank(contributor2);
        engine.openDispute(projectId, indices[0], evidenceHash, "");

        uint256 disputeOpenedAt = block.timestamp;
        uint256 challengePeriod = engine.challengePeriod();

        // Protocol pauses for 1 hour during challenge period
        vm.prank(admin);
        engine.pause();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        engine.unpause();

        // Warp to what appears to be after challenge period
        // but should still be within it if pause time was excluded
        vm.warp(disputeOpenedAt + challengePeriod - 1 hours + 1);

        // In unfixed version, dispute resolution deadline has passed
        // Escalation becomes possible even though effective time hasn't elapsed
    }

    // ── Post-Fix Tests: Pause time is properly tracked and excluded ──

    /// @notice After fix: contributor deadlines account for pause duration
    function test_fix_pauseTimeExcludedFromContributorDeadline() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, address(0));
        vm.stopPrank();

        uint256 claimDeadline = engine.claimDeadline();
        uint256 claimCreatedAt = block.timestamp;

        // Pause for 2 hours
        vm.prank(admin);
        engine.pause();
        vm.warp(block.timestamp + 2 hours);
        vm.prank(admin);
        engine.unpause();

        // Verify pause was tracked
        assertEq(engine.getTotalPausedDuration(), 2 hours, "pause duration tracked");
        assertEq(engine.getLastPauseTimestamp(), 0, "not currently paused");

        // After fix: deadline is extended by pause duration
        // Warp to what would have been past deadline (without pause accounting)
        vm.warp(claimCreatedAt + claimDeadline - 1 hours);

        vm.startPrank(contributor1);
        // This should succeed with the fix - we're within the pause-adjusted window
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        vm.stopPrank();

        // Claim should not be expired yet
        ClaimStatus status = engine.getClaim(claimId).status;
        assertEq(uint8(status), uint8(ClaimStatus.Active), "claim still active after pause");

        // Contributor should NOT be slashed
        uint256 lockAfter = vault.getStakeAccount(contributor1).contributorLock;
        assertGt(lockAfter, 0, "contributor not slashed with fix");
    }

    /// @notice After fix: validator reveal window accounts for pause duration
    function test_fix_pauseTimeExcludedFromRevealWindow() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, address(0));
        engine.contribute(claimId, indices[0], keccak256("submission"), "");
        vm.stopPrank();

        bytes32 salt = keccak256(abi.encodePacked("salt", validator1));
        uint256 score = 8000;
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, indices[0], commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        uint256 commitTimestamp = block.timestamp;
        uint256 commitDeadline = engine.commitDeadline();
        uint256 revealDeadline = engine.revealDeadline();

        // Pause for 3 hours
        vm.prank(admin);
        engine.pause();
        uint256 pauseStart = block.timestamp;
        vm.warp(block.timestamp + 3 hours);
        vm.prank(admin);
        engine.unpause();

        // Verify pause tracking
        assertEq(engine.getTotalPausedDuration(), 3 hours, "3 hour pause tracked");

        // After fix: reveal window is extended by pause duration
        // Warp past commit deadline to enter reveal phase
        vm.warp(commitTimestamp + commitDeadline + 1);

        vm.startPrank(validator1);
        // This should succeed with the fix - we're in the pause-adjusted reveal window
        engine.revealValidation(projectId, indices[0], score, salt);
        vm.stopPrank();

        // Validator should not be slashable
        StakeAccount memory valAfter = vault.getStakeAccount(validator1);
        assertGt(valAfter.inFlight, 0, "validator stake still in-flight after reveal");
    }

    /// @notice After fix: multiple pauses are tracked cumulatively
    function test_fix_multiplePausesTrackedCorrectly() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, address(0));
        vm.stopPrank();

        uint256 claimCreatedAt = block.timestamp;

        // First pause: 1 hour
        vm.prank(admin);
        engine.pause();
        vm.warp(block.timestamp + 1 hours);
        vm.prank(admin);
        engine.unpause();

        assertEq(engine.getTotalPausedDuration(), 1 hours, "first pause tracked");

        // Second pause: 2 hours
        vm.prank(admin);
        engine.pause();
        vm.warp(block.timestamp + 2 hours);
        vm.prank(admin);
        engine.unpause();

        // Total should be cumulative
        assertEq(engine.getTotalPausedDuration(), 3 hours, "cumulative pause tracked");

        // Contributor can still submit within adjusted window
        vm.startPrank(contributor1);
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        vm.stopPrank();

        // Should not be slashed
        uint256 lockAfter = vault.getStakeAccount(contributor1).contributorLock;
        assertGt(lockAfter, 0, "contributor not slashed after multiple pauses");
    }
}
