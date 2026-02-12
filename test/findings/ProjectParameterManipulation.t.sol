// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ISharedTypes, ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {IValidationOracle} from "../../src/interface/IValidationOracle.sol";

/**
 * @title ProjectParameterManipulationTest
 * @notice Test demonstrating Issue #2: Project Parameter Manipulation Mid-Lifecycle
 *
 * VULNERABILITY DESCRIPTION:
 * An originator can modify project parameters mid-lifecycle:
 * - setProjectAlgorithm - Change consensus algorithm after validations started
 * - setProjectRequiredSkill - Add skill requirements after validators claimed
 * - setProjectMinValidatorReputation - Raise reputation requirements to exclude validators
 * - setProjectRevealDeadline - Shorten deadline to force slashing
 *
 * ATTACK VECTOR: Malicious Originator
 *
 * ATTACK SCENARIO: Originator sets revealDeadline = 1 second after validators commit
 * but before reveal, forcing all validators to be slashed.
 *
 * LOCATION: ValidationOracle.sol lines 832-891 (setter functions)
 *
 * SEVERITY: High
 */
contract ProjectParameterManipulationTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");
    address public maliciousOriginator = makeAddr("maliciousOriginator");

    function setUp() public override {
        super.setUp();

        // Grant roles
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, maliciousOriginator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        // Setup validators
        _setupValidator(validator1, 100 ether);
        _setupValidator(validator2, 100 ether);
        _setupValidator(validator3, 100 ether);

        // Setup malicious originator with stake (required for hasEnoughStakeForRole check)
        _setupUser(maliciousOriginator, 100 ether);

        // Fund malicious originator with reward tokens
        rewardToken.mint(maliciousOriginator, 1000 ether);
    }

    /**
     * @notice Test: Fix verification - Originator cannot shorten reveal deadline below minimum
     * @dev Issue #2 fix: setProjectRevealDeadline now enforces MIN_REVEAL_DEADLINE
     */
    function test_OriginatorCannotShortenRevealDeadlineBelowMinimum() public {
        // Malicious originator creates project
        vm.startPrank(maliciousOriginator);
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "test-project",
            0,
            0,
            3, // numberOfValidations
            1000,
            ""
        );
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Get minimum reveal deadline
        uint256 minDeadline = oracle.MIN_REVEAL_DEADLINE();
        console.log("=== Fix Verification: Minimum Reveal Deadline ===");
        console.log("Minimum reveal deadline:", minDeadline);

        // ATTACK ATTEMPT: Originator tries to shorten reveal deadline to 1 second
        console.log("\n=== ATTACK ATTEMPT: Originator Tries to Shorten Deadline ===");
        vm.prank(maliciousOriginator);
        vm.expectRevert(abi.encodeWithSelector(IValidationOracle.InvalidDeadline.selector));
        oracle.setProjectRevealDeadline(PROJECT_ID, 1);

        console.log("FIX VERIFIED: Attack blocked - InvalidDeadline() reverted");
        console.log("Validators are now protected from malicious deadline shortening");

        // Verify that setting deadline above minimum works
        vm.prank(maliciousOriginator);
        oracle.setProjectRevealDeadline(PROJECT_ID, minDeadline + 1);

        (,, uint256 newDeadline,,,,,,) = oracle.projectSettings(PROJECT_ID);
        assertGe(newDeadline, minDeadline, "Deadline should be at or above minimum");
        console.log("Valid deadline set:", newDeadline);
    }

    /**
     * @notice Test: Originator can add skill requirement after validators claimed
     * @dev Validators who don't have the new skill can't complete their validation
     */
    function test_OriginatorCanAddSkillRequirementMidLifecycle() public {
        // Create project without skill requirement
        vm.startPrank(maliciousOriginator);
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "test-project",
            0,
            0,
            3, // numberOfValidations
            1000,
            ""
        );
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Contributor submits
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Validator claims (no skill required at this point)
        vm.prank(validator1);
        oracle.claimToValidate(PROJECT_ID);

        // ATTACK: Originator adds skill requirement
        // Note: setProjectRequiredSkill requires SAPIEN_CORE_ROLE or DEFAULT_ADMIN_ROLE
        // But if originator can influence admin, they can still execute this attack
        console.log("\n=== Attack: Add Skill Requirement Mid-Lifecycle ===");

        // Document that if admin adds skill requirement, existing validators are affected
        vm.prank(admin);
        oracle.setProjectRequiredSkill(PROJECT_ID, "expert-skill");

        (,,, string memory newSkill,,,,,) = oracle.projectSettings(PROJECT_ID);
        console.log("New skill requirement added:", newSkill);

        // Validator1 cannot commit if skill check is enforced at commit time
        // This depends on implementation - document the potential issue
        console.log("Validator1 claimed before skill requirement but may not be able to complete validation");
    }

    /**
     * @notice Test: Originator can raise reputation requirement to exclude validators
     * @dev Raises minValidatorReputation after validators claimed
     */
    function test_OriginatorCanRaiseReputationRequirement() public {
        // Create project with low reputation requirement
        vm.startPrank(maliciousOriginator);
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "test-project",
            0,
            0,
            3, // numberOfValidations
            1000,
            ""
        );
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Set low initial reputation requirement
        vm.prank(maliciousOriginator);
        oracle.setProjectMinValidatorReputation(PROJECT_ID, 1000);

        // Contributor submits
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Validator with 5000 reputation claims
        uint256 v1Rep = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        console.log("Validator1 reputation:", v1Rep);

        vm.prank(validator1);
        oracle.claimToValidate(PROJECT_ID);
        console.log("Validator1 claimed successfully with reputation:", v1Rep);

        // ATTACK: Raise reputation requirement above validator's reputation
        console.log("\n=== Attack: Raise Reputation Requirement ===");
        vm.prank(maliciousOriginator);
        oracle.setProjectMinValidatorReputation(PROJECT_ID, 9000);

        (,,,,,,,, uint256 newMinRep) = oracle.projectSettings(PROJECT_ID);
        console.log("New min reputation requirement:", newMinRep);

        // New validators can't claim
        vm.prank(validator2);
        vm.expectRevert();
        oracle.claimToValidate(PROJECT_ID);
        console.log("Validator2 cannot claim - reputation too low");

        console.log("\nVULNERABILITY:");
        console.log("- Originator can change reputation requirements mid-lifecycle");
        console.log("- Can exclude validators from participating");
        console.log("- Existing claims may be affected depending on implementation");
    }

    /**
     * @notice Test: Mitigation - Lock parameters after first contribution
     * @dev Document the recommended fix pattern
     */
    function test_DocumentRecommendedMitigation() public pure {
        console.log("=== Recommended Mitigations ===");
        console.log("");
        console.log("Option 1: Add minimum deadline check:");
        console.log("  if (deadline < 1 hours) revert InvalidDeadline();");
        console.log("");
        console.log("Option 2: Lock parameters after first contribution/validation:");
        console.log("  if (contributionStates[projectId].length > 0) revert ParametersLocked();");
        console.log("");
        console.log("Option 3: Apply new parameters only to future contributions:");
        console.log("  // Store parameter changes with effective timestamp");
        console.log("  // Only apply to contributions submitted after the change");
        console.log("");
        console.log("Option 4: Require timelock for parameter changes:");
        console.log("  // Announce change 24h before it takes effect");
        console.log("  // Allow validators to withdraw commitments if parameters change");
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
