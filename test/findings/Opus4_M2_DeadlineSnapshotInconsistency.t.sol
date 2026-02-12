// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {IValidationOracle} from "../../src/interface/IValidationOracle.sol";
import {ISharedTypes} from "../../src/interface/ISharedTypes.sol";

/**
 * @title Opus4_M2_DeadlineSnapshotInconsistency
 * @notice Opus 4.6 Security Review - M-2 FIX VERIFICATION
 *
 * ORIGINAL FINDING:
 * cancelExpiredCommitment, _isCommitExpired, _checkConsensusReady, and
 * _appendExpiredSlashes all used the CURRENT project revealDeadline instead
 * of the per-commit snapshot (revealDeadlineSnapshot).
 *
 * FIX APPLIED:
 * _isCommitExpired now reads commit.revealDeadlineSnapshot (falling back to
 * the passed fallbackDeadline for legacy commits). cancelExpiredCommitment
 * also uses the per-commit snapshot directly.
 *
 * LOCATION: ValidationOracle.sol
 * SEVERITY: Medium (now fixed)
 */
contract Opus4_M2_DeadlineSnapshotInconsistency is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("opus4-m2-test");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        _setupValidator(validator1, 200 ether);
        _setupValidator(validator2, 200 ether);
        _setupValidator(validator3, 200 ether);

        // Use numberOfValidations=3 so all 3 validators can claim queue slots
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "opus4-m2-test", 0, 0, 3, 1000, "");
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();
    }

    /**
     * @notice FIX VERIFIED: cancelExpiredCommitment now uses snapshot deadline
     * @dev After originator shortens deadline, cancelExpiredCommitment correctly
     *      uses the per-commit snapshot. The cancel should FAIL because the commit
     *      is still within its snapshot window.
     */
    function test_M2_Fix_CancelExpiredCommitmentUsesSnapshot() public {
        console.log("=== M-2 FIX: cancelExpiredCommitment Uses Snapshot ===");

        // Submit contribution
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("work"));
        vm.stopPrank();

        // Validator commits (snapshot = 3 days)
        uint256 score = 8000;
        uint256 stake = 100 ether;
        bytes32 salt = keccak256("salt-m2");
        bytes32 commitHash = keccak256(abi.encodePacked(score, stake, salt));

        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(PROJECT_ID, v1ClaimId, 0, commitHash);
        vm.stopPrank();

        uint256 commitTime = block.timestamp;
        console.log("Validator committed at:", commitTime);

        // Verify snapshot stored correctly
        ISharedTypes.ValidationCommit[] memory commits = oracle.getValidationCommits(PROJECT_ID, 0);
        assertEq(commits[0].revealDeadlineSnapshot, 3 days, "Snapshot should be 3 days");

        // Originator shortens deadline to 1 hour
        vm.prank(originator);
        oracle.setProjectRevealDeadline(PROJECT_ID, 1 hours);
        console.log("Originator shortened deadline to 1 hour");

        // Warp 2 hours - past new deadline, but within snapshot
        vm.warp(commitTime + 2 hours);

        // FIX: cancelExpiredCommitment now FAILS because it uses the snapshot (3 days)
        vm.expectRevert(IValidationOracle.NoUnrevealedCommit.selector);
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);
        console.log("cancelExpiredCommitment correctly REVERTED (uses 3-day snapshot)");

        // Validator can still reveal
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, score, salt);
        console.log("Validator reveal SUCCEEDED within snapshot window");

        console.log("FIX VERIFIED: Snapshot used consistently across all expiry checks.");
    }

    /**
     * @notice cancelExpiredCommitment still works after the SNAPSHOT deadline passes
     * @dev Ensures the cancel mechanism still functions correctly for truly expired commits.
     */
    function test_M2_Fix_CancelStillWorksAfterSnapshotExpiry() public {
        console.log("=== M-2 FIX: Cancel Works After Snapshot Expiry ===");

        // Submit contribution
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("work2"));
        vm.stopPrank();

        // Validator commits (snapshot = 3 days)
        uint256 score = 8000;
        uint256 stake = 100 ether;
        bytes32 salt = keccak256("salt-m2-expiry");
        bytes32 commitHash = keccak256(abi.encodePacked(score, stake, salt));

        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(PROJECT_ID, v1ClaimId, 0, commitHash);
        vm.stopPrank();

        uint256 commitTime = block.timestamp;

        // Warp past snapshot deadline (3 days + 1 second)
        vm.warp(commitTime + 3 days + 1);

        uint256 stakeBefore = vault.getStake(validator1);
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);
        uint256 stakeAfter = vault.getStake(validator1);

        assertGt(stakeBefore - stakeAfter, 0, "Validator should be slashed after snapshot expiry");
        console.log("Cancel SUCCEEDED after snapshot deadline (3 days) passed");
        console.log("Slashed:", (stakeBefore - stakeAfter) / 1e18, "tokens");
    }

    /**
     * @notice Snapshot protects V3's ability to reveal after deadline is shortened
     * @dev With the fix, shortening the deadline does NOT prevent validators from revealing
     *      within their original snapshot window. V3 can still reveal past the new deadline
     *      because their commit's revealDeadlineSnapshot is the original 3 days.
     */
    function test_M2_Fix_ConsensusReadinessUsesSnapshot() public {
        console.log("=== M-2 FIX: Snapshot Protects Reveal Window ===");

        // Submit contribution
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("work3"));
        vm.stopPrank();

        // 3 validators commit (all get snapshot = 3 days)
        uint256 score = 8000;
        uint256 stake = 100 ether;

        bytes32 salt1 = keccak256("salt-v1-consensus");
        bytes32 commitHash1 = keccak256(abi.encodePacked(score, stake, salt1));
        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(PROJECT_ID, v1ClaimId, 0, commitHash1);
        vm.stopPrank();

        bytes32 salt2 = keccak256("salt-v2-consensus");
        bytes32 commitHash2 = keccak256(abi.encodePacked(score, stake, salt2));
        vm.startPrank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(PROJECT_ID, v2ClaimId, 0, commitHash2);
        vm.stopPrank();

        bytes32 salt3 = keccak256("salt-v3-consensus");
        bytes32 commitHash3 = keccak256(abi.encodePacked(score, stake, salt3));
        vm.startPrank(validator3);
        uint256 v3ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(PROJECT_ID, v3ClaimId, 0, commitHash3);
        vm.stopPrank();

        uint256 commitTime = block.timestamp;

        // Reveal v1 and v2 early
        vm.warp(commitTime + 1 hours);
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, score, salt1);
        vm.prank(validator2);
        oracle.revealValidation(PROJECT_ID, 0, score, salt2);

        // Originator shortens deadline to 1 hour
        vm.prank(originator);
        oracle.setProjectRevealDeadline(PROJECT_ID, 1 hours);

        // Warp to 2 hours after commit - past new deadline, within snapshot
        vm.warp(commitTime + 2 hours);

        // Only 2 of 3 reveals so far - consensus NOT ready (need numberOfValidations=3)
        ISharedTypes.ConsensusReport memory report = oracle.getConsensus(PROJECT_ID, 0);
        assertFalse(report.isReady, "Consensus should NOT be ready (only 2 of 3 reveals)");
        console.log("Consensus NOT ready at T+2h (only 2 of 3 reveals)");

        // FIX VERIFICATION: V3 can STILL reveal because snapshot is 3 days (not the shortened 1 hour)
        // Without the M-2 fix, this would revert because the system would use the new 1-hour deadline
        vm.prank(validator3);
        oracle.revealValidation(PROJECT_ID, 0, score, salt3);
        console.log("V3 reveal SUCCEEDED at T+2h (within 3-day snapshot, past 1h new deadline)");

        // Now all 3 have revealed - consensus is ready
        report = oracle.getConsensus(PROJECT_ID, 0);
        assertTrue(report.isReady, "Consensus should be ready after all 3 reveals");
        assertEq(report.validatorCount, 3, "All 3 validators counted");
        console.log("Consensus ready after V3 revealed within snapshot window");

        console.log("FIX VERIFIED: Snapshot protects reveal window against retroactive deadline shortening.");
    }

    // ============================================
    // HELPERS
    // ============================================

    function _setupValidator(address v, uint256 capacity) internal {
        vm.startPrank(admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();
        vm.prank(v);
        oracle.setValidatorCapacity(capacity);
    }
}
