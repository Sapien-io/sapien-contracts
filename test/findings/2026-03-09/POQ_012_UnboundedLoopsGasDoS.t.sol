// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {BaseTest} from "../../BaseTest.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus} from "src/Types.sol";

/// @title POQ-12: Unbounded Loops in removeProject() and claimToValidate() Create Gas-Based Liveness DoS
/// @notice Tests to validate the unbounded loop gas issue exists
contract POQ_012_UnboundedLoopsGasDoS is BaseTest {
    uint256 constant GAS_LIMIT = 30_000_000;

    function setUp() public override {
        super.setUp();
    }

    /// @notice Test demonstrates removeProject() no longer exceeds gas limits due to pagination
    /// @dev With the fix, this processes in batches and stays under gas limits
    function test_removeProject_ExceedsGasLimit_WithLargeQuantity() public {
        uint256 largeQuantity = 1000;
        uint256 largeAmount = 1_000_000e18;

        token.mint(originator, largeAmount * 2);

        bytes32 projectId = keccak256("large-project");

        vm.startPrank(originator);

        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        engine.createProject(projectId, "", config);
        token.approve(address(engine), largeAmount);
        engine.fundProject(projectId, largeAmount, largeQuantity, adapter);

        vm.stopPrank();

        // Now have contributors claim many slots
        address[] memory contributors = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            contributors[i] = makeAddr(string(abi.encodePacked("contributor", i)));
            token.mint(contributors[i], STAKE_AMOUNT * 200);
            vm.startPrank(contributors[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 150, contributors[i]);
            vm.stopPrank();
        }

        // Have each contributor claim slots in batches of 20 (max allowed)
        // Need 50 claims total to get 1000 slots (50 * 20 = 1000)
        for (uint256 i = 0; i < 50; i++) {
            address contrib = contributors[i % 10];
            vm.startPrank(contrib);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 20, adapter);

            // Submit contributions for each
            for (uint256 j = 0; j < indices.length; j++) {
                bytes32 hash = keccak256(abi.encodePacked("submission", indices[j]));
                engine.contribute(claimId, indices[j], hash, "");
            }
            vm.stopPrank();
        }

        // Now admin tries to remove the project
        vm.prank(admin);

        // Measure gas consumption for first batch
        uint256 gasBefore = gasleft();
        (bool complete,) = engine.removeProject(projectId, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for removeProject() first batch (default 50):", gasUsed);

        // With the fix, gas usage should be reasonable (under 1M gas)
        // Not the 30M+ it would have been without pagination
        assertLt(gasUsed, 1_000_000, "Gas usage should be capped by pagination");
        assertFalse(complete, "Should not be complete after first batch");
    }

    /// @notice Test demonstrates claimToValidate() no longer exceeds gas limits due to iteration cap
    /// @dev With the fix, iterations are capped at 500 max
    function test_claimToValidate_ExceedsGasLimit_WithManyPending() public {
        uint256 largeQuantity = 500;
        uint256 largeAmount = 500_000e18;

        token.mint(originator, largeAmount * 2);

        bytes32 projectId = keccak256("large-validation-project");

        vm.startPrank(originator);

        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        engine.createProject(projectId, "", config);
        token.approve(address(engine), largeAmount);
        engine.fundProject(projectId, largeAmount, largeQuantity, adapter);

        vm.stopPrank();

        // Create many contributors and have them all submit
        address[] memory contributors = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            contributors[i] = makeAddr(string(abi.encodePacked("contributor_val", i)));
            token.mint(contributors[i], STAKE_AMOUNT * 200);
            vm.startPrank(contributors[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 150, contributors[i]);
            vm.stopPrank();
        }

        // Have contributors claim and submit in batches of 20 (max allowed)
        // Need 25 claims total to get 500 slots (25 * 20 = 500)
        for (uint256 i = 0; i < 25; i++) {
            address contrib = contributors[i % 10];
            vm.startPrank(contrib);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 20, adapter);

            for (uint256 j = 0; j < indices.length; j++) {
                bytes32 hash = keccak256(abi.encodePacked("submission", indices[j]));
                engine.contribute(claimId, indices[j], hash, "");
            }
            vm.stopPrank();
        }

        // Now validator tries to claim validations
        // With the fix, iterations are capped at 500 max
        _ensureStake(validator1, VALIDATOR_STAKE * 10);

        vm.prank(validator1);

        uint256 gasBefore = gasleft();
        engine.claimToValidate(projectId, 10);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for claimToValidate() with", largeQuantity, "pending:", gasUsed);

        // With the fix, gas consumption is capped due to 500-iteration limit
        // Should be reasonable even with 500 pending
        assertLt(gasUsed, 10_000_000, "Gas usage should be capped by iteration limit");
    }

    /// @notice Test shows gas usage is now capped due to pagination fix
    function test_removeProject_GasScalesLinearly() public {
        uint256[] memory quantities = new uint256[](5);
        quantities[0] = 10;
        quantities[1] = 50;
        quantities[2] = 100;
        quantities[3] = 200;
        quantities[4] = 500;

        uint256[] memory gasUsages = new uint256[](5);

        for (uint256 q = 0; q < quantities.length; q++) {
            uint256 quantity = quantities[q];
            uint256 amount = quantity * 1000e18;

            bytes32 projectId = keccak256(abi.encodePacked("project", q));
            token.mint(originator, amount * 2);

            vm.startPrank(originator);
            Project memory config = Project({
                originator: address(0),
                rewardToken: address(token),
                totalRewards: 0,
                totalQuantity: 0,
                availableSlots: 0,
                consensusThreshold: 7000,
                minStakeToClaim: STAKE_AMOUNT,
                validatorRewardBps: 2000,
                numberOfValidations: 3,
                requiredSkill: SKILL_ID,
                minValidatorReputation: 0,
                minValidationStake: 0,
                status: ProjectStatus.Created,
                activatedAt: 0,
                completedAt: 0,
                cancelledAt: 0
            });

            engine.createProject(projectId, "", config);
            token.approve(address(engine), amount);
            engine.fundProject(projectId, amount, quantity, adapter);
            vm.stopPrank();

            // Have contributors claim all slots in batches of max 20
            if (quantity > 0) {
                uint256 numClaims = (quantity + 19) / 20; // Round up
                for (uint256 i = 0; i < numClaims; i++) {
                    address contrib = makeAddr(string(abi.encodePacked("c", q, "_", i)));
                    token.mint(contrib, STAKE_AMOUNT * 100);
                    vm.startPrank(contrib);
                    token.approve(address(vault), type(uint256).max);
                    vault.deposit(STAKE_AMOUNT * 50, contrib);

                    uint256 claimSize = (i == numClaims - 1 && quantity % 20 != 0) ? quantity % 20 : 20;
                    if (claimSize > quantity - (i * 20)) claimSize = quantity - (i * 20);

                    (uint256 claimId, uint256[] memory indices) =
                        engine.claimToContribute(projectId, claimSize, adapter);
                    for (uint256 j = 0; j < indices.length; j++) {
                        bytes32 hash = keccak256(abi.encodePacked("submission", indices[j]));
                        engine.contribute(claimId, indices[j], hash, "");
                    }
                    vm.stopPrank();
                }
            }

            // Measure gas for removeProject (with default batch size of 50)
            vm.prank(admin);
            uint256 gasBefore = gasleft();
            engine.removeProject(projectId, 0);
            uint256 gasUsed = gasBefore - gasleft();
            gasUsages[q] = gasUsed;

            console2.log("Quantity:", quantity, "Gas used:", gasUsed);
        }

        // With pagination fix, gas usage should be capped and NOT scale linearly
        // For quantities > 50, gas should remain roughly constant (batch size of 50)
        // This demonstrates the fix is working
        for (uint256 i = 2; i < gasUsages.length; i++) {
            // Gas for 100, 200, 500 should be similar (all use batch size 50)
            assertLt(gasUsages[i], gasUsages[1] * 2, "Gas should be capped due to pagination, not scale with quantity");
        }
    }

    /// @notice Test shows gas usage scales linearly with pendingIndices length in claimToValidate()
    function test_claimToValidate_GasScalesLinearly() public {
        uint256[] memory quantities = new uint256[](4);
        quantities[0] = 10;
        quantities[1] = 50;
        quantities[2] = 100;
        quantities[3] = 200;

        uint256[] memory gasUsages = new uint256[](4);

        for (uint256 q = 0; q < quantities.length; q++) {
            uint256 quantity = quantities[q];
            uint256 amount = quantity * 1000e18;

            bytes32 projectId = keccak256(abi.encodePacked("val_project", q));
            token.mint(originator, amount * 2);

            vm.startPrank(originator);
            Project memory config = Project({
                originator: address(0),
                rewardToken: address(token),
                totalRewards: 0,
                totalQuantity: 0,
                availableSlots: 0,
                consensusThreshold: 7000,
                minStakeToClaim: STAKE_AMOUNT,
                validatorRewardBps: 2000,
                numberOfValidations: 3,
                requiredSkill: SKILL_ID,
                minValidatorReputation: 0,
                minValidationStake: 0,
                status: ProjectStatus.Created,
                activatedAt: 0,
                completedAt: 0,
                cancelledAt: 0
            });

            engine.createProject(projectId, "", config);
            token.approve(address(engine), amount);
            engine.fundProject(projectId, amount, quantity, adapter);
            vm.stopPrank();

            // Have contributors claim and submit all slots in batches of max 20
            if (quantity > 0) {
                uint256 numClaims = (quantity + 19) / 20; // Round up
                for (uint256 i = 0; i < numClaims; i++) {
                    address contrib = makeAddr(string(abi.encodePacked("vc", q, "_", i)));
                    token.mint(contrib, STAKE_AMOUNT * 100);
                    vm.startPrank(contrib);
                    token.approve(address(vault), type(uint256).max);
                    vault.deposit(STAKE_AMOUNT * 50, contrib);

                    uint256 claimSize = (i == numClaims - 1 && quantity % 20 != 0) ? quantity % 20 : 20;
                    if (claimSize > quantity - (i * 20)) claimSize = quantity - (i * 20);

                    (uint256 claimId, uint256[] memory indices) =
                        engine.claimToContribute(projectId, claimSize, adapter);
                    for (uint256 j = 0; j < indices.length; j++) {
                        bytes32 hash = keccak256(abi.encodePacked("submission", indices[j]));
                        engine.contribute(claimId, indices[j], hash, "");
                    }
                    vm.stopPrank();
                }
            }

            // Create unique validator for each test
            address val = makeAddr(string(abi.encodePacked("val", q)));
            token.mint(val, STAKE_AMOUNT * 100);
            vm.startPrank(val);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 50, val);
            vm.stopPrank();

            // Measure gas for claimToValidate
            vm.prank(val);
            uint256 gasBefore = gasleft();
            engine.claimToValidate(projectId, 5);
            uint256 gasUsed = gasBefore - gasleft();
            gasUsages[q] = gasUsed;

            console2.log("Pending:", quantity, "Gas used:", gasUsed);
        }

        // Verify gas usage increases with pending count
        for (uint256 i = 1; i < gasUsages.length; i++) {
            assertGt(gasUsages[i], gasUsages[i - 1], "Gas should increase with pending count");
        }
    }
}
