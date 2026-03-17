// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Project, ProjectStatus} from "src/Types.sol";

/// @title POQ-8: Reputation System Can Be Systematically Farmed via Self-Contained Cycles
/// @notice Tests demonstrating how reputation can be farmed through:
///         Path 1: Creating, funding, and completing projects with zero contributions
///         Path 2: Sybil cycles with minimal validations and worthless tokens
contract POQ_8_ReputationFarming is BaseTest {
    address public attacker = makeAddr("attacker");
    address public sybil1 = makeAddr("sybil1");
    address public sybil2 = makeAddr("sybil2");

    function setUp() public override {
        super.setUp();

        // Setup attacker balances
        token.mint(attacker, FUND_AMOUNT * 10);
        vm.startPrank(attacker);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 10, attacker);
        vm.stopPrank();

        // Setup sybil accounts with sufficient funds for funding projects
        address[2] memory sybils = [sybil1, sybil2];
        for (uint256 i = 0; i < sybils.length; i++) {
            token.mint(sybils[i], FUND_AMOUNT * 10);
            vm.startPrank(sybils[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 10, sybils[i]);
            token.approve(address(engine), type(uint256).max);
            vm.stopPrank();
        }
    }

    /// @notice POQ-8 FIX VERIFIED: Path 1 - Cannot create project with < 3 validators
    /// @dev After fix, projects with numberOfValidations < 3 are rejected
    function test_POQ_8_FIX_Path1_MinValidationsEnforced() public {
        bytes32 projectId = keccak256("attack-project-1");

        vm.startPrank(attacker);

        // FIX VERIFIED: Cannot create project with only 1 validator
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
        );
        engine.createProject(projectId, "", _getProjectConfig(attacker, 1));

        vm.stopPrank();
    }

    /// @notice POQ-8 FIX VERIFIED: Path 1 - Cannot complete project with zero accepted contributions
    /// @dev After fix, projects must have at least one accepted contribution to be completed
    function test_POQ_8_FIX_Path1_ZeroContributionBlocked() public {
        bytes32 projectId = keccak256("attack-project-1");

        vm.startPrank(attacker);

        // Create project with minimum 3 validators (now enforced)
        engine.createProject(projectId, "", _getProjectConfig(attacker, 3));

        // Fund the project
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(projectId, FUND_AMOUNT, 1, address(0));

        // FIX VERIFIED: Cannot complete project with zero accepted contributions
        vm.expectRevert(ISapienCore.NoAcceptedContributions.selector);
        engine.completeProject(projectId);

        vm.stopPrank();
    }

    /// @notice POQ-8 FIX VERIFIED: Path 1 - Repeated farming blocked
    /// @dev After fix, cannot create projects with < 3 validators or complete without accepted contributions
    function test_POQ_8_FIX_Path1_RepeatedFarmingBlocked() public {
        vm.startPrank(attacker);
        token.approve(address(engine), FUND_AMOUNT * 5);

        // FIX VERIFIED: All attempts to create projects with 1 validator fail
        for (uint256 i = 0; i < 5; i++) {
            bytes32 projectId = keccak256(abi.encodePacked("attack-project", i));
            vm.expectRevert(
                abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
            );
            engine.createProject(projectId, "", _getProjectConfig(attacker, 1));
        }

        vm.stopPrank();
    }

    /// @notice POQ-8 FIX VERIFIED: Path 2 - Minimal validation farming blocked
    /// @dev After fix, cannot create projects with numberOfValidations < 3
    function test_POQ_8_FIX_Path2_MinimalValidationBlocked() public {
        bytes32 projectId = keccak256("sybil-project");

        vm.startPrank(sybil1);

        // FIX VERIFIED: Cannot create project with numberOfValidations = 1
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
        );
        engine.createProject(projectId, "", _getProjectConfigMinValidations(sybil1));

        vm.stopPrank();
    }

    /// @notice POQ-8 FIX VERIFIED: Path 2 - Originator cannot validate own project
    /// @dev After fix, originator is prevented from claiming to validate their own project
    function test_POQ_8_FIX_Path2_OriginatorSelfValidationBlocked() public {
        bytes32 projectId = keccak256("self-validate-project");

        // Originator creates and funds project with minimum 3 validators
        vm.startPrank(attacker);
        engine.createProject(projectId, "", _getProjectConfig(attacker, 3));
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(projectId, FUND_AMOUNT, 1, address(0));
        vm.stopPrank();

        // Sybil contributes
        vm.prank(sybil1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, address(0));

        vm.prank(sybil1);
        engine.contribute(claimId, indices[0], keccak256("work"), "cid");

        // FIX VERIFIED: Originator cannot claim to validate their own project
        vm.prank(attacker);
        vm.expectRevert(ISapienCore.OriginatorCannotValidate.selector);
        engine.claimToValidate(projectId, 1);
    }

    /// @notice Helper to create project config with attacker as originator
    function _getProjectConfig(address orig, uint256 numValidations) internal view returns (Project memory) {
        return Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: numValidations,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            acceptedContributions: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
    }

    /// @notice Helper for minimal validation project config
    function _getProjectConfigMinValidations(address orig) internal view returns (Project memory) {
        return _getProjectConfig(orig, 1); // Minimum allowed
    }
}
