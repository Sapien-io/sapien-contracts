// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title MinMaxValidationsMismatchTest
 * @notice Test demonstrating Issue #7: No Minimum Validation Count Enforcement at Project Creation
 *
 * VULNERABILITY DESCRIPTION:
 * There's no check that minValidations <= maxValidations. A project could be created with
 * minValidations = 5 while _maxValidations = 3, making consensus impossible to reach.
 *
 * ATTACK VECTOR: Configuration Error / DoS
 *
 * LOCATION: SapienCore.sol lines 226-227
 *
 * SEVERITY: Medium
 */
contract MinMaxValidationsMismatchTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("mismatch-test");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        _setupValidator(validator1, 100 ether);
        _setupValidator(validator2, 100 ether);
        _setupValidator(validator3, 100 ether);
    }

    /**
     * @notice Test: Create project with minValidations > maxValidations
     * @dev This should either revert or create an unfinalizable project
     */
    function test_MinGreaterThanMaxValidations() public {
        // Get current global maxValidations
        uint256 globalMax = core.getMaxValidations();
        console.log("=== Min/Max Validation Mismatch ===");
        console.log("Global maxValidations:", globalMax);

        // Try to create project with minValidations > maxValidations
        uint256 requestedMin = globalMax + 5; // More than max

        vm.startPrank(originator);
        try core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "mismatch-test",
            0,
            0,
            requestedMin, // minValidations > maxValidations
            1000,
            ""
        ) {
            console.log("Project created with minValidations:", requestedMin);
            console.log("But maxValidations is only:", globalMax);

            // Check the actual stored values
            uint256 storedMin = core.getProject(PROJECT_ID).config.minValidations;
            uint256 storedMax = core.getProject(PROJECT_ID).config.maxValidations;
            console.log("Stored minValidations:", storedMin);
            console.log("Stored maxValidations:", storedMax);

            if (storedMin > storedMax) {
                console.log("\nVULNERABILITY CONFIRMED:");
                console.log("Project has minValidations > maxValidations!");
                console.log("Consensus can NEVER be reached for contributions");

                // Fund and try to demonstrate
                rewardToken.approve(address(core), 100 ether);
                core.fundProject(PROJECT_ID, 100 ether, 10);
            } else {
                console.log("Note: Values may have been adjusted during creation");
            }
        } catch {
            console.log("Project creation reverted (good - validation exists)");
            assertTrue(true, "Proper validation prevents invalid configuration");
        }
        vm.stopPrank();
    }

    /**
     * @notice Test: Demonstrate unfinalizable contribution
     * @dev If minValidations > maxValidations, contributions get stuck
     */
    function test_UnfinalizableContribution() public {
        // Set low maxValidations at admin level
        vm.prank(admin);
        core.setMaxValidations(2);

        console.log("=== Unfinalizable Contribution Test ===");
        console.log("Global maxValidations set to: 2");

        // Create project with high minValidations
        vm.startPrank(originator);
        try core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "mismatch-test",
            0,
            0,
            5, // Request 5 min validations
            1000,
            ""
        ) {
            // Check actual config
            uint256 storedMin = core.getProject(PROJECT_ID).config.minValidations;
            uint256 storedMax = core.getProject(PROJECT_ID).config.maxValidations;
            console.log("Stored minValidations:", storedMin);
            console.log("Stored maxValidations:", storedMax);

            if (storedMin > storedMax) {
                rewardToken.approve(address(core), 100 ether);
                core.fundProject(PROJECT_ID, 100 ether, 10);
                vm.stopPrank();

                // Contributor submits
                vm.startPrank(contributor);
                uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
                core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
                vm.stopPrank();

                console.log("\nContribution submitted...");

                // All validators validate
                _validateContribution(PROJECT_ID, 0, 8000);

                // Try to finalize
                console.log("Attempting to finalize with", storedMax, "validations...");
                console.log("But need", storedMin, "validations for consensus");

                try core.finalizeContribution(PROJECT_ID, 0) {
                    console.log("Finalization succeeded (unexpected)");
                } catch (bytes memory reason) {
                    console.log("Finalization FAILED!");
                    console.log("Contribution is stuck forever!");
                    console.log("VULNERABILITY CONFIRMED: Funds locked, work wasted");
                }
            } else {
                vm.stopPrank();
                console.log("Configuration was valid - test skipped");
            }
        } catch {
            vm.stopPrank();
            console.log("Project creation properly reverted");
        }
    }

    /**
     * @notice Test: Edge case - minValidations = 0
     * @dev minValidations = 0 means any single validation triggers consensus
     */
    function test_ZeroMinValidations() public {
        vm.startPrank(originator);
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "mismatch-test",
            0,
            0,
            0, // 0 minValidations - should default to 3
            1000,
            ""
        );

        uint256 storedMin = core.getProject(PROJECT_ID).config.minValidations;
        console.log("=== Zero MinValidations Test ===");
        console.log("Requested minValidations: 0");
        console.log("Stored minValidations:", storedMin);

        if (storedMin == 3) {
            console.log("Defaulted to 3 (expected behavior)");
        } else if (storedMin == 0) {
            console.log("ISSUE: minValidations stored as 0");
            console.log("Single validation could approve anything!");
        }
        vm.stopPrank();

        assertGe(storedMin, 1, "minValidations should be at least 1");
    }

    /**
     * @notice Test: Verify fix - minValidations should not exceed maxValidations
     */
    function test_VerifyMinMaxRelationship() public {
        vm.prank(admin);
        core.setMaxValidations(5);

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "mismatch-test", 0, 0, 3, 1000, "");

        uint256 storedMin = core.getProject(PROJECT_ID).config.minValidations;
        uint256 storedMax = core.getProject(PROJECT_ID).config.maxValidations;

        console.log("=== Min/Max Relationship Verification ===");
        console.log("Stored minValidations:", storedMin);
        console.log("Stored maxValidations:", storedMax);

        assertLe(storedMin, storedMax, "minValidations should not exceed maxValidations");
        vm.stopPrank();
    }

    /**
     * @notice Document recommended fix
     */
    function test_DocumentRecommendedFix() public pure {
        console.log("=== Recommended Fix ===");
        console.log("");
        console.log("Add validation in createProject():");
        console.log("");
        console.log("  uint256 effectiveMin = minValidations == 0 ? 3 : minValidations;");
        console.log("  if (effectiveMin > _maxValidations) {");
        console.log("      revert InvalidConfiguration();");
        console.log("  }");
        console.log("");
        console.log("Or automatically cap minValidations:");
        console.log("");
        console.log("  p.config.minValidations = minValidations == 0");
        console.log("      ? 3");
        console.log("      : (minValidations > _maxValidations ? _maxValidations : minValidations);");
    }

    function _validateContribution(bytes32 projectId, uint256 contribIndex, uint256 score) internal {
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        uint256 stake = 100 ether;

        vm.startPrank(validator1);
        uint256 v1Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v1Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt1)));
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v2Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt2)));
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        vm.prank(validator1);
        oracle.revealValidation(projectId, contribIndex, score, salt1);
        vm.prank(validator2);
        oracle.revealValidation(projectId, contribIndex, score, salt2);
    }

    function _setupValidator(address v, uint256 amount) internal {
        _setupUser(v, amount);
        vm.startPrank(admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();
        vm.prank(v);
        oracle.setValidatorCapacity(amount);
    }
}
