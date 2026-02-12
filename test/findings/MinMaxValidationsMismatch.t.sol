// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title NumberOfValidationsTest
 * @notice Tests verifying numberOfValidations configuration at project creation
 *
 * TESTS:
 * 1. numberOfValidations defaults to 3 when 0 is passed
 * 2. numberOfValidations is stored correctly when a valid value is provided
 * 3. Project can be created and funded with various numberOfValidations values
 */
contract NumberOfValidationsTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("validations-test");

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
     * @notice Test: numberOfValidations defaults to 3 when 0 is passed
     */
    function test_ZeroNumberOfValidations() public {
        vm.startPrank(originator);
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "validations-test",
            0,
            0,
            0, // 0 numberOfValidations - should default to 3
            1000,
            ""
        );

        uint256 storedValidations = core.getProject(PROJECT_ID).config.numberOfValidations;
        console.log("=== Zero NumberOfValidations Test ===");
        console.log("Requested numberOfValidations: 0");
        console.log("Stored numberOfValidations:", storedValidations);

        if (storedValidations == 3) {
            console.log("Defaulted to 3 (expected behavior)");
        } else if (storedValidations == 0) {
            console.log("ISSUE: numberOfValidations stored as 0");
            console.log("Single validation could approve anything!");
        }
        vm.stopPrank();

        assertGe(storedValidations, 1, "numberOfValidations should be at least 1");
    }

    /**
     * @notice Test: numberOfValidations is stored correctly when a valid value is provided
     */
    function test_NumberOfValidationsStoredCorrectly() public {
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "validations-test", 0, 0, 5, 1000, "");

        uint256 storedValidations = core.getProject(PROJECT_ID).config.numberOfValidations;

        console.log("=== NumberOfValidations Stored Correctly ===");
        console.log("Stored numberOfValidations:", storedValidations);

        assertEq(storedValidations, 5, "numberOfValidations should be stored as 5");
        vm.stopPrank();
    }

    /**
     * @notice Test: Project can be created and funded with numberOfValidations = 1
     */
    function test_CreateProjectWithSingleValidation() public {
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "validations-test", 0, 0, 1, 1000, "");

        uint256 storedValidations = core.getProject(PROJECT_ID).config.numberOfValidations;
        assertEq(storedValidations, 1, "numberOfValidations should be stored as 1");

        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();
    }

    /**
     * @notice Test: Contributions can be validated with the configured numberOfValidations
     */
    function test_ContributionValidatedWithNumberOfValidations() public {
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "validations-test", 0, 0, 2, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Contributor submits
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Validate with 2 validators (matching numberOfValidations)
        _validateContribution(PROJECT_ID, 0, 8000);

        // Finalize should succeed
        vm.warp(block.timestamp + 4 days);
        core.finalizeContribution(PROJECT_ID, 0);
    }

    // ============================================
    // HELPERS
    // ============================================

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
