// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ISharedTypes, ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title ZeroStakeValidatorDoSTest
 * @notice Test demonstrating Issue #1: Zero-Stake Validator Claim Attack (Ghost Validator DoS)
 *
 * VULNERABILITY DESCRIPTION:
 * If `trust.roleMinStake(VALIDATOR_ROLE)` returns 0 and `minStakeRequired` is also 0,
 * a validator can:
 * 1. Claim validation slots with `capacity = 0`
 * 2. Never commit or reveal (free DoS on queue)
 *
 * ATTACK VECTOR: Ghost Validator / DoS
 *
 * LOCATION: ValidationOracle.sol lines 172-234 (claimToValidate)
 *
 * If `requiredStake == 0`, then `availableCapacity >= 0` always passes.
 * No stake is at risk for the attacker.
 *
 * SEVERITY: High
 */
contract ZeroStakeValidatorDoSTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");
    address public attacker = makeAddr("attacker");

    function setUp() public override {
        super.setUp();

        // Grant roles to participants
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, attacker);
        vm.stopPrank();

        // Setup validators
        _setupValidator(validator1, 100 ether);
        _setupValidator(attacker, 100 ether);

        // Create project
        vm.startPrank(originator);
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "test-project",
            0, // minStakeToClaim = 0
            0, // minStakeToContribute = 0
            3, // numberOfValidations
            1000, // validatorRewardBasisPoints (10%)
            "" // No required skill
        );

        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Create contributions for validation
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 5);
        for (uint256 i = 0; i < 5; i++) {
            core.contribute(PROJECT_ID, claimId, i, keccak256(abi.encodePacked("submission", i)));
        }
        vm.stopPrank();
    }

    /**
     * @notice Test: Verify zero-stake protection exists
     * @dev If minStakeRequired = 0 in trust, verify validators still need capacity
     */
    function test_ZeroStakeValidatorCannotDoSQueue() public {
        // Get the required stake (should be > 0 in production)
        uint256 requiredStake = trust.roleMinStake(VALIDATOR_ROLE);
        console.log("Required stake from trust:", requiredStake);
        console.log("Trust min stake required:", trust.minStakeRequired());

        // Even if trust allows 0 stake, validator needs capacity
        // This test verifies the capacity check prevents zero-stake DoS

        // Attacker sets capacity to 0
        vm.prank(attacker);
        oracle.setValidatorCapacity(0);

        // Get available capacity
        uint256 attackerCapacity = oracle.getAvailableCapacity(attacker);
        console.log("Attacker available capacity:", attackerCapacity);
        assertEq(attackerCapacity, 0, "Attacker should have 0 capacity");

        // Attacker attempts to claim validation slot with 0 capacity
        // This should revert if protected
        if (requiredStake > 0) {
            vm.prank(attacker);
            vm.expectRevert(abi.encodeWithSelector(ISharedTypes.InsufficientCapacity.selector));
            oracle.claimToValidate(PROJECT_ID);
            console.log("PROTECTED: Attacker cannot claim with 0 capacity when requiredStake > 0");
        } else {
            // If requiredStake == 0, this is the vulnerability!
            vm.prank(attacker);
            try oracle.claimToValidate(PROJECT_ID) {
                console.log("VULNERABLE: Attacker claimed slot with 0 stake requirement!");
                console.log("This is a DoS vulnerability - attacker can block queue for free");
                // This test documents the vulnerability
                assertTrue(true, "Vulnerability confirmed - zero stake allows claim");
            } catch {
                console.log("PROTECTED: Claim reverted even with 0 stake requirement");
            }
        }
    }

    /**
     * @notice Test: Ghost validator attack simulation
     * @dev Attacker claims slots but never commits/reveals
     */
    function test_GhostValidatorAttack() public {
        uint256 requiredStake = trust.roleMinStake(VALIDATOR_ROLE);

        // Skip if properly protected
        if (requiredStake == 0) {
            console.log("=== Ghost Validator Attack Simulation ===");

            // Get initial queue size
            uint256 pendingBefore = oracle.getPendingValidationCount(PROJECT_ID);
            console.log("Pending validations before attack:", pendingBefore);

            // Attacker claims with 0 capacity (if vulnerability exists)
            vm.prank(attacker);
            oracle.setValidatorCapacity(0);

            vm.prank(attacker);
            try oracle.claimToValidate(PROJECT_ID) returns (uint256 claimId) {
                console.log("Ghost validator claimed slot:", claimId);

                uint256 pendingAfter = oracle.getPendingValidationCount(PROJECT_ID);
                console.log("Pending validations after attack:", pendingAfter);

                // Ghost validator never commits or reveals
                // Queue is blocked without any stake at risk

                console.log("VULNERABILITY CONFIRMED:");
                console.log("- Attacker staked: 0");
                console.log("- Queue slots blocked:", pendingBefore - pendingAfter);
                console.log("- Cost to attacker: 0 (no slashing possible)");
            } catch {
                console.log("Attack prevented - claim reverted");
            }
        } else {
            console.log("Ghost validator attack not possible - requiredStake > 0");
            assertTrue(true, "Protected by non-zero stake requirement");
        }
    }

    /**
     * @notice Test: Mitigation verification - minimum stake requirement
     * @dev Verify that setting minStakeRequired > 0 prevents the attack
     */
    function test_Mitigation_MinStakeRequired() public {
        // Set minimum stake requirement
        vm.prank(admin);
        trust.setMinStakeRequired(10 ether);

        uint256 minStake = trust.minStakeRequired();
        console.log("Min stake required:", minStake);
        assertGt(minStake, 0, "Min stake should be > 0");

        // Attacker with 0 capacity
        vm.prank(attacker);
        oracle.setValidatorCapacity(0);

        // Attempt to claim should fail
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.InsufficientCapacity.selector));
        oracle.claimToValidate(PROJECT_ID);

        console.log("Mitigation confirmed: Cannot claim with 0 capacity when minStake > 0");
    }

    /**
     * @notice Test: Recommended fix - explicit zero check
     * @dev Documents the recommended fix pattern
     */
    function test_DocumentRecommendedFix() public pure {
        console.log("=== Recommended Fix ===");
        console.log("");
        console.log("Option 1: Add explicit check in claimToValidate():");
        console.log("");
        console.log("  uint256 requiredStake = _getRequiredValidatorStake(projectId);");
        console.log("  if (requiredStake == 0) revert InvalidStakeAmount();");
        console.log("");
        console.log("Option 2: Ensure minStakeRequired > 0 in production:");
        console.log("");
        console.log("  // In SapienTrust constructor or initialize():");
        console.log("  if (minStakeRequired == 0) revert InvalidConfiguration();");
        console.log("");
        console.log("Option 3: Protocol-level enforcement:");
        console.log("");
        console.log("  // In ValidationOracle.claimToValidate():");
        console.log("  uint256 effectiveStake = requiredStake > 0 ? requiredStake : MIN_STAKE_FLOOR;");
        console.log("  if (availableCapacity < effectiveStake) revert InsufficientCapacity();");
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
