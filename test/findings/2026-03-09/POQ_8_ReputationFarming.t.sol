// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Project, ProjectStatus} from "src/Types.sol";

/// @title POQ-8 FIX VERIFICATION: Reputation Farming Prevention
/// @notice Verifies fixes for reputation farming via self-contained cycles
/// @dev Tests demonstrate that all three attack vectors are now blocked
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
        token.approve(address(engine), type(uint256).max);
        vm.stopPrank();

        // Setup sybil accounts
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

    /// @notice POQ-8 FIX #1: Minimum 3 validators enforced
    function test_POQ_8_FIX_MinValidationsEnforced() public {
        bytes32 projectId = keccak256("attack-project-1");

        vm.startPrank(attacker);

        // Cannot create project with < 3 validators
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
        );
        engine.createProject(projectId, "", _getProjectConfig(1));

        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
        );
        engine.createProject(projectId, "", _getProjectConfig(2));

        // Can create with 3 validators
        engine.createProject(projectId, "", _getProjectConfig(3));

        vm.stopPrank();
    }

    /// @notice POQ-8 FIX #2: Cannot complete project with zero accepted contributions
    function test_POQ_8_FIX_ZeroContributionBlocked() public {
        bytes32 projectId = keccak256("attack-project-2");

        vm.startPrank(attacker);

        engine.createProject(projectId, "", _getProjectConfig(3));
        engine.fundProject(projectId, FUND_AMOUNT, 1, address(0));

        // Cannot complete without accepted contributions
        vm.expectRevert(ISapienCore.NoAcceptedContributions.selector);
        engine.completeProject(projectId);

        vm.stopPrank();
    }

    /// @notice POQ-8 FIX #3: Originator cannot validate own project
    function test_POQ_8_FIX_OriginatorSelfValidationBlocked() public {
        bytes32 projectId = keccak256("self-validate-project");

        // Originator creates and funds project
        vm.startPrank(attacker);
        engine.createProject(projectId, "", _getProjectConfig(3));
        engine.fundProject(projectId, FUND_AMOUNT, 1, address(0));
        vm.stopPrank();

        // Sybil contributes
        vm.prank(sybil1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, address(0));

        vm.prank(sybil1);
        engine.contribute(claimId, indices[0], keccak256("work"), "cid");

        // Originator cannot claim to validate their own project
        vm.prank(attacker);
        vm.expectRevert(ISapienCore.OriginatorCannotValidate.selector);
        engine.claimToValidate(projectId, 1);
    }

    /// @notice Helper to create project config
    function _getProjectConfig(uint256 numValidations) internal view returns (Project memory) {
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
}
