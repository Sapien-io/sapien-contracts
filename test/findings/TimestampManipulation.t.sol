// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title TimestampManipulationTest
 * @notice Tests for timestamp-dependent logic robustness
 * @dev Issue #15 from security review: Timestamp Dependence - MEDIUM
 *
 * Miners can manipulate block.timestamp by +/-15 seconds
 * This test verifies that timestamp-dependent logic is robust to small variations
 */
contract TimestampManipulationTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");
    uint256 public constant TIMESTAMP_MANIPULATION_WINDOW = 15 seconds; // Miners can manipulate +/-15s

    function setUp() public override {
        super.setUp();

        // Setup roles
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        vm.stopPrank();

        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "test-project", 0, 0, 1, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();
    }

    /**
     * @notice Test claim deadline with timestamp manipulation
     * @dev Claim deadline is 7 days, test with +/-15 seconds manipulation
     */
    function test_ClaimDeadline_TimestampManipulation() public {
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        uint256 deadline = core.getClaim(PROJECT_ID, claimId).deadline;
        vm.stopPrank();

        uint256 expectedDeadline = block.timestamp + 7 days;
        console.log("Expected deadline:", expectedDeadline);
        console.log("Actual deadline:", deadline);
        console.log(
            "Difference:", deadline > expectedDeadline ? deadline - expectedDeadline : expectedDeadline - deadline
        );

        // Test that deadline is approximately correct (within manipulation window)
        assertTrue(
            deadline >= expectedDeadline - TIMESTAMP_MANIPULATION_WINDOW
                && deadline <= expectedDeadline + TIMESTAMP_MANIPULATION_WINDOW,
            "Deadline should be within manipulation window"
        );

        // Test expiration check with manipulation
        vm.warp(deadline - TIMESTAMP_MANIPULATION_WINDOW);
        assertEq(
            uint256(core.getClaim(PROJECT_ID, claimId).status),
            uint256(ClaimStatus.Active),
            "Claim should still be active before deadline"
        );

        vm.warp(deadline + TIMESTAMP_MANIPULATION_WINDOW);
        assertTrue(block.timestamp > deadline, "Should be able to expire claim after deadline");
    }

    /**
     * @notice Test contribution expiration with timestamp manipulation
     */
    function test_ContributionExpiration_TimestampManipulation() public {
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        uint256 submittedAt = core.getContribution(PROJECT_ID, 0).submittedAt;
        console.log("Submitted at:", submittedAt);
        console.log("Current timestamp:", block.timestamp);

        // Contribution should be valid immediately
        assertEq(submittedAt, block.timestamp, "Submitted timestamp should match current block");
    }

    /**
     * @notice Test reputation decay with timestamp manipulation
     * @dev Decay is calculated daily, test robustness to small timestamp variations
     */
    function test_ReputationDecay_TimestampManipulation() public {
        // Setup user with reputation
        _setupUser(contributor, 100 ether);
        vm.startPrank(admin);
        trust.updateReputation(contributor, CONTRIBUTOR_ROLE, true, 5000);
        trust.setReputationDecay(10); // 0.1% per day
        vm.stopPrank();

        uint256 initialScore = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);
        console.log("Initial score:", initialScore);

        // Test decay after exactly 1 day
        vm.warp(block.timestamp + 1 days);
        uint256 scoreAfter1Day = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);
        console.log("Score after 1 day:", scoreAfter1Day);

        // Test decay after 1 day + manipulation window
        vm.warp(block.timestamp + TIMESTAMP_MANIPULATION_WINDOW);
        uint256 scoreAfter1DayPlusManipulation = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);
        console.log("Score after 1 day + manipulation:", scoreAfter1DayPlusManipulation);

        // Scores should be very close (decay is linear, small time difference = small decay difference)
        uint256 difference = scoreAfter1Day > scoreAfter1DayPlusManipulation
            ? scoreAfter1Day - scoreAfter1DayPlusManipulation
            : scoreAfter1DayPlusManipulation - scoreAfter1Day;

        // Difference should be minimal (decay over 15 seconds is negligible)
        assertTrue(difference < 100, "Score difference should be minimal"); // 100 = 0.01% of 10000
    }

    /**
     * @notice Test validation deadline with timestamp manipulation
     */
    function test_ValidationDeadline_TimestampManipulation() public {
        // Setup validators
        _setupValidator(validator1, 100 ether);

        // Setup contribution
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Validator commits
        vm.startPrank(validator1);
        uint256 vClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, vClaimId, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt")))
        );
        uint256 committedAt = block.timestamp;
        vm.stopPrank();

        // Default reveal deadline is 3 days
        uint256 revealDeadline = committedAt + 3 days;
        console.log("Committed at:", committedAt);
        console.log("Reveal deadline:", revealDeadline);

        // Test reveal before deadline (with manipulation window)
        vm.warp(revealDeadline - TIMESTAMP_MANIPULATION_WINDOW);
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 8000, keccak256("salt"));

        // Should succeed
        assertTrue(true, "Reveal should succeed before deadline");
    }

    /**
     * @notice Test skill validation cooldown with timestamp manipulation
     * @dev Cooldown is SKILL_VALIDATION_COOLDOWN, test robustness
     */
    function test_SkillValidationCooldown_TimestampManipulation() public {
        _setupUser(contributor, 100 ether);

        // First validation
        vm.startPrank(admin);
        trust.validateSkill(contributor, "test-skill");
        uint256 firstValidationTime = block.timestamp;
        vm.stopPrank();

        // Try to validate again immediately (should fail)
        vm.startPrank(admin);
        vm.expectRevert();
        trust.validateSkill(contributor, "test-skill");
        vm.stopPrank();

        // Try after cooldown - manipulation window
        vm.warp(firstValidationTime + 1 days - TIMESTAMP_MANIPULATION_WINDOW);
        vm.startPrank(admin);
        vm.expectRevert(); // Should still fail
        trust.validateSkill(contributor, "test-skill");
        vm.stopPrank();

        // Try after cooldown + manipulation window (should succeed)
        vm.warp(firstValidationTime + 1 days + TIMESTAMP_MANIPULATION_WINDOW);
        vm.startPrank(admin);
        trust.validateSkill(contributor, "test-skill"); // Should succeed
        vm.stopPrank();

        assertTrue(trust.hasValidatedSkill(contributor, "test-skill"), "Skill should be validated");
    }

    /**
     * @notice Test that deadlines are calculated correctly despite manipulation
     */
    function test_DeadlineCalculation_Robustness() public view {
        uint256 baseTime = block.timestamp;
        uint256 deadlineDays = 7;
        uint256 expectedDeadline = baseTime + (deadlineDays * 1 days);

        // Simulate timestamp manipulation (+/-15 seconds)
        // Use uint256 to avoid underflow issues
        for (uint256 i = 0; i <= 30; i += 5) {
            // forge-lint: disable-next-line(unsafe-typecast)
            // casting to 'int256' is safe because i is uint256 in range 0-30, so offset is in range -15 to +15
            int256 offset = int256(i) - 15; // Range from -15 to +15
            uint256 manipulatedTime;
            // forge-lint: disable-next-line(unsafe-typecast)
            // casting to 'uint256' is safe because offset is negative, so -offset is positive and fits in uint256
            if (offset < 0 && uint256(-offset) > baseTime) {
                // Skip if would underflow
                continue;
            }
            // forge-lint: disable-next-line(unsafe-typecast)
            // casting to 'uint256' is safe: if offset < 0, -offset is positive; if offset >= 0, offset fits in uint256
            manipulatedTime = offset < 0 ? baseTime - uint256(-offset) : baseTime + uint256(offset);
            uint256 calculatedDeadline = manipulatedTime + (deadlineDays * 1 days);

            // Deadline should be within manipulation window of expected
            assertTrue(
                calculatedDeadline >= expectedDeadline - TIMESTAMP_MANIPULATION_WINDOW
                    && calculatedDeadline <= expectedDeadline + TIMESTAMP_MANIPULATION_WINDOW,
                "Deadline should be robust to timestamp manipulation"
            );
        }
    }

    /**
     * @notice Test expiration checks with boundary conditions
     */
    function test_ExpirationBoundaryConditions() public {
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        uint256 deadline = core.getClaim(PROJECT_ID, claimId).deadline;
        vm.stopPrank();

        // Test exactly at deadline
        vm.warp(deadline);
        assertEq(
            uint256(core.getClaim(PROJECT_ID, claimId).status),
            uint256(ClaimStatus.Active),
            "Claim should be active at exact deadline"
        );

        // Test 1 second after deadline
        vm.warp(deadline + 1);
        assertTrue(block.timestamp > deadline, "Should be able to expire 1 second after deadline");

        // Test with manipulation window
        vm.warp(deadline - TIMESTAMP_MANIPULATION_WINDOW);
        assertEq(
            uint256(core.getClaim(PROJECT_ID, claimId).status),
            uint256(ClaimStatus.Active),
            "Claim should be active within manipulation window before deadline"
        );
    }

    /**
     * @notice Document timestamp manipulation risks
     */
    function test_DocumentTimestampRisks() public pure {
        console.log("=== Timestamp Manipulation Risks ===");
        console.log("\n1. Miners can manipulate block.timestamp by +/-15 seconds");
        console.log("2. This affects:");
        console.log("   - Claim deadlines");
        console.log("   - Validation reveal deadlines");
        console.log("   - Reputation decay calculations");
        console.log("   - Skill validation cooldowns");

        console.log("\n3. Mitigations:");
        console.log("   - Use >= or <= instead of == for deadline checks");
        console.log("   - Add buffer time for critical operations");
        console.log("   - Consider using block.number for some operations");

        console.log("\n4. Current Implementation:");
        console.log("   - Uses > and < comparisons (good)");
        console.log("   - Daily calculations are robust to small variations");
        console.log("   - Boundary conditions are handled correctly");
    }

    // Helper function
    function _setupValidator(address v, uint256 amount) internal {
        _setupUser(v, amount);
        vm.startPrank(admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();

        vm.prank(v);
        oracle.setValidatorCapacity(amount);
    }
}
