// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";

/**
 * @title Validator Capacity Underflow Vulnerability Test
 * @notice Tests for Issue #2: Validator capacity underflow risks
 * @dev This vulnerability occurs when inFlightStake is reduced without proper bounds checking,
 *      potentially causing underflow or state inconsistencies.
 *      This test verifies that the fix prevents such issues.
 */
contract ValidatorCapacityUnderflowTest is BaseTest {
    // forge-lint: disable-next-line(mixed-case-variable)
    // PROJECT_ID is a test constant used throughout the test file
    bytes32 public PROJECT_ID;

    function setUp() public override {
        super.setUp();
        PROJECT_ID = keccak256(abi.encodePacked("capacity-vulnerability-project"));
        vm.prank(admin);
        oracle.registerProject(PROJECT_ID, 3, "", originator);
    }

    /**
     * @notice Test that normal validation flow still works with underflow protection
     * @dev Verifies that the underflow checks don't break normal functionality
     */
    function testNormalValidationFlowStillWorks() public {
        _setValidatorCapacity(validator1, 1000 ether);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);

        // Commit with a stake amount
        bytes32 salt = keccak256("salt");
        uint256 stakeAmount = 100 ether;
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), stakeAmount, salt));

        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, claimId, 0, commitHash);

        // Check that capacity was used
        uint256 availableCapacityBefore = oracle.getAvailableCapacity(validator1);
        assertTrue(availableCapacityBefore < 1000 ether);

        // Reveal successfully
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt);

        // Check that capacity was restored
        uint256 availableCapacityAfter = oracle.getAvailableCapacity(validator1);
        assertEq(availableCapacityAfter, 1000 ether);
    }

    /**
     * @notice Test that cancelExpiredCommitment still works with underflow protection
     * @dev Ensures that cancelling expired commitments functions correctly
     */
    function testCancelExpiredCommitmentStillWorks() public {
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

        // Check capacity was used
        uint256 availableCapacityBefore = oracle.getAvailableCapacity(validator1);
        assertTrue(availableCapacityBefore < 1000 ether);

        // Wait for reveal deadline to pass
        vm.warp(block.timestamp + 4 days);

        // Cancel the expired commitment
        vm.prank(admin);
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);

        // Check that inFlightStake was released (capacity is reduced due to slashing)
        // Capacity is reduced by the slash amount (100 ether), so available capacity = 1000 - 100 = 900
        uint256 availableCapacityAfter = oracle.getAvailableCapacity(validator1);
        assertEq(availableCapacityAfter, 900 ether); // Capacity reduced by slash, inFlightStake released
    }

    /**
     * @notice Test the capacity reduction logic in handleValidatorSlash
     * @dev Ensures slashing maintains proper bounds
     */
    function testHandleValidatorSlashCapacityBounds() public {
        _setValidatorCapacity(validator1, 1000 ether);

        // Test normal slash
        vm.prank(admin);
        oracle.handleValidatorSlash(PROJECT_ID, 0, validator1, 200 ether);

        uint256 availableCapacityAfterSlash = oracle.getAvailableCapacity(validator1);
        assertEq(availableCapacityAfterSlash, 800 ether);

        // Test slash amount larger than capacity
        vm.prank(admin);
        oracle.handleValidatorSlash(PROJECT_ID, 0, validator1, 1000 ether);

        uint256 availableCapacityAfterLargeSlash = oracle.getAvailableCapacity(validator1);
        assertEq(availableCapacityAfterLargeSlash, 0); // Should be clamped to 0
    }
}
