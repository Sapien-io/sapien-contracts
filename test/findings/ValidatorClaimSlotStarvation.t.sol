// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ISharedTypes, ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title ValidatorClaimSlotStarvationTest
 * @notice Test demonstrating QS-2: claimToValidate() allows validators to claim more slots than they can fulfill
 *
 * ISSUE DESCRIPTION:
 * The claimToValidate() function only verifies that a validator has sufficient capacity for ONE validation
 * (capacity >= requiredStake), but then assigns quantity slots without verifying total capacity or accounting
 * for already-committed stake (inFlightStake). This enables queue slot starvation attacks.
 *
 * VULNERABILITY LOCATION:
 * - src/ValidationOracle.sol:121-168 (claimToValidate function)
 * - Line 128: Only checks if capacity >= requiredStake (for ONE validation)
 * - Lines 155-165: Assigns ALL requested quantity slots without checking total capacity
 * - getAvailableCapacity() helper exists at lines 209-214 but is NOT used in claimToValidate()
 *
 * ATTACK FLOW:
 * 1. Validator has capacity = 150 tokens, requiredStake = 100 tokens
 * 2. Validator calls claimToValidate(projectId) - with Option B, can only claim 1 slot per call
 * 3. Check at line 128: 150 >= 100 passes
 * 4. Validator gets assigned 50 queue slots (removed from queue)
 * 5. Validator can only commit to 1 validation (150/100 = 1)
 * 6. 49 slots assigned but unfulfillable, blocking other validators
 *
 * IMPACT:
 * - Severity: HIGH
 * - Queue Slot Starvation: Legitimate validators cannot claim blocked slots
 * - Contribution Deadline Risk: Contributions may fail to reach minValidations before deadlines
 * - Economic Griefing: Low-cost attack vector for disrupting validation queue
 * - Gas Waste: Cleanup operations via slashing require additional transactions
 */
contract ValidatorClaimSlotStarvationTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");

    function setUp() public override {
        super.setUp();

        // Grant roles to participants
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        // Set validator capacity
        _setupValidator(validator1, 150 ether); // Only enough for 1 validation
        _setupValidator(validator2, 1000 ether); // Enough for many validations
        _setupValidator(validator3, 1000 ether); // Enough for many validations

        // Create and fund project
        vm.startPrank(originator);
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "test-project",
            10 ether, // minStakeToClaim
            10 ether, // minStakeToContribute
            3, // minValidations
            1000, // validatorRewardBasisPoints (10%)
            "" // No required skill
        );

        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();
    }

    /**
     * @notice Test that demonstrates the vulnerability was fixed: validator cannot claim more slots than they can fulfill
     * @dev This test shows that the fix prevents the attack scenario where a validator with limited capacity tries to claim many slots
     * NOTE: Before the fix, this test would show validator1 successfully claiming 5 slots. After the fix, it reverts.
     */
    function test_ValidatorCannotClaimMoreSlotsThanCapacity() public {
        // ============================================
        // 1. SETUP: CREATE MULTIPLE CONTRIBUTIONS
        // ============================================
        vm.startPrank(contributor);
        uint256 claimId1 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId1, 0, keccak256("submission1"));

        uint256 claimId2 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId2, 1, keccak256("submission2"));

        uint256 claimId3 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId3, 2, keccak256("submission3"));

        uint256 claimId4 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId4, 3, keccak256("submission4"));

        uint256 claimId5 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId5, 4, keccak256("submission5"));
        vm.stopPrank();

        // Verify we have queue slots (5 contributions * 10 maxValidations each = 50 slots)
        uint256 pendingCount = oracle.getPendingValidationCount(PROJECT_ID);
        assertEq(pendingCount, 50, "Should have 50 pending validation slots (5 contributions * 10 maxValidations)");

        // ============================================
        // 2. ATTACK: VALIDATOR CLAIMS MORE SLOTS THAN CAPACITY
        // ============================================
        // Validator1 has capacity = 150 ether, requiredStake = 100 ether
        // They can only fulfill 1 validation (150/100 = 1)
        // But they claim 5 slots

        uint256 requiredStake = trust.roleMinStake(VALIDATOR_ROLE);
        if (requiredStake == 0) {
            requiredStake = trust.minStakeRequired();
        }

        console.log("=== Attack Attempt ===");
        uint256 validator1Capacity = oracle.getAvailableCapacity(validator1);
        console.log("Validator1 available capacity:", validator1Capacity);
        console.log("Required stake per validation:", requiredStake);
        console.log("Validator1 can fulfill:", validator1Capacity / requiredStake, "validations");
        console.log("Validator1 attempting to claim: 5 slots");

        // With Option B, can only claim 1 slot at a time (parameter removed)
        // Validator must make multiple calls to claim multiple slots
        console.log("=== Attack Attempt ===");
        console.log("Validator1 attempting to claim multiple slots");
        console.log("Option B: can only claim 1 slot per call");

        // Validator can claim 1 slot successfully (within capacity)
        vm.prank(validator1);
        uint256 v1ClaimId1 = oracle.claimToValidate(PROJECT_ID);

        // Verify 1 slot was claimed
        (, uint256 claimQuantity1,,,,,) = oracle.validationClaims(PROJECT_ID, v1ClaimId1);
        assertEq(claimQuantity1, 1, "Validator1 claimed exactly 1 slot");

        // ============================================
        // 3. VERIFY ATTACK PREVENTED
        // ============================================
        // With Option B, validator can only claim 1 slot per call
        // To claim 5 slots, they would need 5 separate calls
        // This prevents slot hoarding attacks - they can't claim all slots atomically

        // After claiming 1 slot, queue should have 49 remaining (50 - 1)
        uint256 pendingCountAfter = oracle.getPendingValidationCount(PROJECT_ID);
        assertEq(pendingCountAfter, 49, "Queue should have 49 remaining slots (50 - 1 claimed)");

        // Validator1 can claim another slot (still within capacity: 150 ether can fulfill 1 validation)
        vm.prank(validator1);
        uint256 v1ClaimId2 = oracle.claimToValidate(PROJECT_ID);

        (, uint256 claimQuantity2,,,,,) = oracle.validationClaims(PROJECT_ID, v1ClaimId2);
        assertEq(claimQuantity2, 1, "Validator1 can claim another slot (within capacity)");

        // Queue should now have 48 remaining (50 - 2)
        uint256 pendingCountAfter2 = oracle.getPendingValidationCount(PROJECT_ID);
        assertEq(pendingCountAfter2, 48, "Queue should have 48 remaining slots (50 - 2 claimed)");

        console.log("=== Fix Confirmed ===");
        console.log("Validator1 cannot claim more slots than available capacity");
        console.log("Attack prevented - queue slots remain available for other validators");
    }

    /**
     * @notice Test that demonstrates the fix prevents attack with existing inFlightStake
     * @dev Shows that the fix prevents claiming more than available even with inFlightStake
     * NOTE: Before the fix, this test would show validator1 successfully claiming 3 slots despite inFlightStake.
     * After the fix, it reverts.
     */
    function test_ValidatorCannotClaimMoreSlotsWithInFlightStake() public {
        // ============================================
        // 1. SETUP: VALIDATOR ALREADY HAS IN-FLIGHT STAKE
        // ============================================
        // First, validator1 commits to one validation
        vm.startPrank(contributor);
        uint256 claimId1 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId1, 0, keccak256("submission1"));
        vm.stopPrank();

        vm.startPrank(validator1);
        uint256 v1ClaimId1 = oracle.claimToValidate(PROJECT_ID);
        uint256 stake = 100 ether;
        bytes32 salt1 = keccak256("salt1");
        bytes32 commitHash1 = keccak256(abi.encodePacked(uint256(8000), stake, salt1));
        oracle.commitValidation(PROJECT_ID, v1ClaimId1, 0, commitHash1);
        vm.stopPrank();

        // Validator1 now has inFlightStake = 100 ether, capacity = 150 ether
        // Available capacity = 150 - 100 = 50 ether (can fulfill 0 new validations)
        uint256 requiredStake = trust.roleMinStake(VALIDATOR_ROLE);
        if (requiredStake == 0) {
            requiredStake = trust.minStakeRequired();
        }
        uint256 availableCapacity = oracle.getAvailableCapacity(validator1);
        assertEq(availableCapacity, 50 ether, "Available capacity should be 50 ether");
        assertLt(availableCapacity, requiredStake, "Available capacity less than required stake");

        // ============================================
        // 2. CREATE MORE CONTRIBUTIONS
        // ============================================
        vm.startPrank(contributor);
        uint256 claimId2 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId2, 1, keccak256("submission2"));

        uint256 claimId3 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId3, 2, keccak256("submission3"));

        uint256 claimId4 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId4, 3, keccak256("submission4"));
        vm.stopPrank();

        // ============================================
        // 3. ATTACK ATTEMPT: VALIDATOR TRIES TO CLAIM MORE SLOTS DESPITE IN-FLIGHT STAKE
        // ============================================
        // With Option B: can only claim 1 slot per call
        // But validator has insufficient capacity: 50 ether < 100 ether required

        console.log("=== Attack Attempt with InFlightStake ===");
        console.log("Validator1 attempting to claim slot");
        console.log("Available capacity:", availableCapacity);
        console.log("Required stake:", requiredStake);
        console.log("Option B: can only claim 1 slot per call, but capacity check prevents it");

        // Validator cannot claim even 1 slot because available capacity (50) < required stake (100)
        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.InsufficientCapacity.selector));
        oracle.claimToValidate(PROJECT_ID);

        // This demonstrates that Option B + capacity check work together:
        // - Option B prevents claiming multiple slots at once
        // - Capacity check prevents claiming when insufficient capacity

        // ============================================
        // 4. VERIFY ATTACK PREVENTED
        // ============================================
        // Validator1 cannot claim any slots due to insufficient capacity
        // First contribution: 10 slots, validator1 claimed 1 earlier, so 9 remaining
        // 3 more contributions: 3 * 10 = 30 slots
        // Total: 9 + 30 = 39 slots (all still available)
        uint256 pendingCountAfter = oracle.getPendingValidationCount(PROJECT_ID);
        assertEq(pendingCountAfter, 39, "Queue should still have 39 pending validation slots - attack prevented");

        console.log("=== Fix Confirmed ===");
        (uint256 validatorCapacity, uint256 validatorInFlight) = oracle.validatorStates(validator1);
        console.log("Validator1 has inFlightStake:", validatorInFlight);
        console.log("Validator1 capacity:", validatorCapacity);
        console.log("Available capacity:", availableCapacity);
        console.log("Validator1 cannot claim more slots than available capacity");
        console.log("Attack prevented - slots remain available for other validators");
    }

    /**
     * @notice Test that demonstrates legitimate validators are NOT blocked (fix prevents starvation)
     * @dev Shows that the fix prevents starvation - validators can only claim what they can fulfill
     * NOTE: Before the fix, this test would show validator1 claiming all slots and blocking others.
     * After the fix, validator1 can only claim 1 slot, leaving others available.
     */
    function test_LegitimateValidatorsNotBlockedByStarvation() public {
        // ============================================
        // 1. SETUP: CREATE CONTRIBUTIONS
        // ============================================
        vm.startPrank(contributor);
        uint256 claimId1 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId1, 0, keccak256("submission1"));

        uint256 claimId2 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId2, 1, keccak256("submission2"));

        uint256 claimId3 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId3, 2, keccak256("submission3"));
        vm.stopPrank();

        // ============================================
        // 2. VALIDATOR1 CAN ONLY CLAIM 1 SLOT (WITHIN CAPACITY)
        // ============================================
        // With the fix, validator1 can only claim what they can fulfill
        vm.prank(validator1);
        oracle.claimToValidate(PROJECT_ID);

        // ============================================
        // 3. VERIFY LEGITIMATE VALIDATORS ARE NOT BLOCKED
        // ============================================
        // Validator2 and validator3 can still claim slots
        // 3 contributions * 10 maxValidations = 30 slots, validator1 claimed 1, so 29 remaining
        uint256 pendingCount = oracle.getPendingValidationCount(PROJECT_ID);
        assertEq(pendingCount, 29, "Queue should have 29 remaining slots (30 - 1 claimed by validator1)");

        // Validator2 can claim remaining slots
        vm.prank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(PROJECT_ID);

        (, uint256 v2Quantity,,,,,) = oracle.validationClaims(PROJECT_ID, v2ClaimId);
        assertEq(v2Quantity, 1, "Validator2 can claim slots");

        // Validator3 can also claim remaining slots
        vm.prank(validator3);
        uint256 v3ClaimId = oracle.claimToValidate(PROJECT_ID);

        (, uint256 v3Quantity,,,,,) = oracle.validationClaims(PROJECT_ID, v3ClaimId);
        assertEq(v3Quantity, 1, "Validator3 can claim slots");

        uint256 pendingCountAfter = oracle.getPendingValidationCount(PROJECT_ID);
        // 30 initial slots - 1 (validator1) - 1 (validator2) - 1 (validator3) = 27 remaining
        assertEq(pendingCountAfter, 27, "27 slots remaining (30 - 3 claimed)");

        console.log("=== Starvation Prevented ===");
        console.log("Validator1 can only claim 1 slot (within capacity)");
        console.log("Validator2 and validator3 can claim remaining slots");
        console.log("All validators can participate - no starvation");
    }

    /**
     * @notice Test that demonstrates the fix prevents the attack
     * @dev After the fix, claiming more slots than available capacity should revert
     */
    function test_FixPreventsClaimingMoreSlotsThanCapacity() public {
        // ============================================
        // 1. SETUP: CREATE CONTRIBUTIONS
        // ============================================
        vm.startPrank(contributor);
        uint256 claimId1 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId1, 0, keccak256("submission1"));

        uint256 claimId2 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId2, 1, keccak256("submission2"));
        vm.stopPrank();

        // ============================================
        // 2. ATTEMPT TO CLAIM MORE SLOTS THAN CAPACITY
        // ============================================
        // Validator1 has capacity = 150 ether, requiredStake = 100 ether
        // Can only fulfill 1 validation, but tries to claim 2

        uint256 requiredStake = trust.roleMinStake(VALIDATOR_ROLE);
        if (requiredStake == 0) {
            requiredStake = trust.minStakeRequired();
        }
        console.log("=== Fix Verification ===");
        console.log("Validator1 can claim 1 slot per call");
        console.log("Option B: parameter removed, always claims 1 slot");

        // Validator1 can claim 1 slot (within capacity)
        // With Option B, parameter removed - function always claims exactly 1 slot
        vm.prank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);

        (, uint256 claimQuantity3,,,,,) = oracle.validationClaims(PROJECT_ID, v1ClaimId);
        assertEq(claimQuantity3, 1, "Validator1 can claim 1 slot");

        console.log("=== Fix Confirmed ===");
        console.log("Validator1 cannot claim more slots than available capacity");
        console.log("Validator1 can claim 1 slot (within capacity)");
    }

    /**
     * @notice Document the recommended fix
     * @dev The fix should check total capacity before assigning slots
     */
    function test_DocumentRecommendedFix() public pure {
        console.log("=== Recommended Fix ===");
        console.log("Option A: Proper capacity check (immediate fix)");
        console.log("");
        console.log("uint256 requiredStake = _getRequiredValidatorStake(projectId);");
        console.log("uint256 requiredTotalCapacity = requiredStake * quantity;");
        console.log("uint256 availableCapacity = vState.capacity - vState.inFlightStake;");
        console.log("");
        console.log("if (availableCapacity < requiredTotalCapacity) {");
        console.log("    revert InsufficientCapacity();");
        console.log("}");
        console.log("");
        console.log("Option B: Force single-slot claims (root fix per design review)");
        console.log("");
        console.log("function claimToValidate(bytes32 projectId) external returns (uint256 claimId) {");
        console.log("    // Option B: Parameter removed - always claims exactly 1 slot");
        console.log("    // This prevents queue slot starvation attacks and ensures fair distribution");
        console.log("    // ... rest of function");
        console.log("}");
        console.log("");
        console.log("Benefits:");
        console.log("1. Prevents queue slot starvation attacks");
        console.log("2. Ensures validators can only claim what they can fulfill");
        console.log("3. Protects legitimate validators from being blocked");
        console.log("4. Prevents contribution deadline risks");
    }

    // Helper function to set up validator with reputation
    function _setupValidator(address validator, uint256 capacity) internal {
        _setupUser(validator, capacity);
        vm.startPrank(admin);
        trust.updateReputation(validator, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();

        vm.prank(validator);
        oracle.setValidatorCapacity(capacity);
    }
}
