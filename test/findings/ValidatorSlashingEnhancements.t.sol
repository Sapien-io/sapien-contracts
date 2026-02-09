// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";

/**
 * @title Validator Slashing Enhancements Test
 * @notice Tests for enhanced validator slashing mechanisms
 * @dev Tests that validators are properly slashed when they don't complete their obligations
 */
contract ValidatorSlashingEnhancementsTest is BaseTest {
    // forge-lint: disable-next-line(mixed-case-variable)
    // PROJECT_ID is a test constant used throughout the test file
    bytes32 public PROJECT_ID;

    function setUp() public override {
        super.setUp();
        PROJECT_ID = keccak256(abi.encodePacked("slashing-test-project"));
        vm.prank(admin);
        oracle.registerProject(PROJECT_ID, 10, 3, "", originator);
    }

    /**
     * @notice Test that validators are slashed when their validation claims expire without commits
     */
    function testValidatorSlashedForExpiredUncommittedClaim() public {
        _setValidatorCapacity(validator1, 1000 ether);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        // Validator claims 1 validation slot
        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);

        // Wait for claim deadline to expire (CLAIM_DURATION = 1 hour)
        vm.warp(block.timestamp + 1 hours + 1);

        // Check stake before slashing
        uint256 stakeBefore = vault.getStake(validator1);

        // Cancel the expired claim
        vm.prank(admin);
        oracle.cancelExpiredValidationClaim(PROJECT_ID, claimId);

        // Check stake after slashing - should be reduced (slashed)
        uint256 stakeAfter = vault.getStake(validator1);
        assertTrue(stakeAfter < stakeBefore, "Validator should be slashed for expired uncommitted claim");

        // Check capacity is reduced
        uint256 availableCapacityAfter = oracle.getAvailableCapacity(validator1);
        assertTrue(availableCapacityAfter < 1000 ether, "Capacity should be reduced after slashing");
    }

    /**
     * @notice Test that fully committed claims don't get slashed when expired
     */
    function testNoSlashingForFullyCompletedClaim() public {
        _setValidatorCapacity(validator1, 1000 ether);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        // Validator claims 1 validation slot
        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);

        // Commit to the validation
        bytes32 salt = keccak256("salt");
        uint256 stakeAmount = 100 ether;
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), stakeAmount, salt));

        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, claimId, 0, commitHash);

        // Wait for claim deadline to expire
        vm.warp(block.timestamp + 1 hours + 1);

        // Check stake before cancellation
        uint256 stakeBefore = vault.getStake(validator1);

        // Cancel the expired claim (even though fully committed)
        // Since the claim is fully committed, it's status is Fulfilled, not Active
        // So cancelExpiredValidationClaim will revert with NoClaimAvailable()
        vm.prank(admin);
        vm.expectRevert(); // NoClaimAvailable() - claim is Fulfilled, not Active
        oracle.cancelExpiredValidationClaim(PROJECT_ID, claimId);

        // Check stake after - should be unchanged (no slashing because cancellation failed)
        uint256 stakeAfter = vault.getStake(validator1);
        assertEq(stakeAfter, stakeBefore, "Fully committed claims should not be slashed");
    }

    /**
     * @notice Test that reveal deadline slashing still works as before
     */
    function testRevealDeadlineSlashingStillWorks() public {
        _setValidatorCapacity(validator1, 1000 ether);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);

        // Commit
        bytes32 salt = keccak256("salt");
        uint256 stakeAmount = 100 ether;
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), stakeAmount, salt));

        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, claimId, 0, commitHash);

        // Check capacity after commit - should be reduced
        uint256 availableCapacityAfterCommit = oracle.getAvailableCapacity(validator1);
        assertTrue(availableCapacityAfterCommit < 1000 ether, "Capacity should be reduced after commit");

        // Wait for reveal deadline to expire (3 days default)
        vm.warp(block.timestamp + 4 days);

        // Check stake before slashing
        uint256 stakeBefore = vault.getStake(validator1);

        // Cancel expired commitment
        vm.prank(admin);
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);

        // Check stake after slashing - should be reduced
        uint256 stakeAfter = vault.getStake(validator1);
        assertTrue(stakeAfter < stakeBefore, "Validator should be slashed for expired commitment");

        // Capacity is reduced by slash amount, but inFlightStake is released
        // Available capacity = (1000 - 100 slash) - 0 inFlight = 900 ether
        uint256 availableCapacityAfterSlash = oracle.getAvailableCapacity(validator1);
        assertEq(availableCapacityAfterSlash, 900 ether, "Capacity should be reduced by slash amount");
    }
}
