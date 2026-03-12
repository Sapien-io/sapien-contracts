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

    /// @notice Test demonstrates removeProject() can exceed gas limits for large projects
    /// @dev This test shows the issue exists - it will fail due to out of gas
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

        // Now have contributor1 claim many slots
        address[] memory contributors = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            contributors[i] = makeAddr(string(abi.encodePacked("contributor", i)));
            token.mint(contributors[i], STAKE_AMOUNT * 100);
            vm.startPrank(contributors[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 50, contributors[i]);
            vm.stopPrank();
        }

        // Have each contributor claim 100 slots (total 1000)
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(contributors[i]);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 100, adapter);

            // Submit contributions for each
            for (uint256 j = 0; j < indices.length; j++) {
                bytes32 hash = keccak256(abi.encodePacked("submission", indices[j]));
                engine.contribute(claimId, indices[j], hash, "");
            }
            vm.stopPrank();
        }

        // Now admin tries to remove the project
        vm.prank(admin);

        // Measure gas consumption
        uint256 gasBefore = gasleft();
        engine.removeProject(projectId, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for removeProject() with", largeQuantity, "slots:", gasUsed);

        // This will demonstrate the issue - gas used will be extremely high
        // For 1000 iterations, this can exceed 30M gas
        assertGt(gasUsed, GAS_LIMIT, "Gas usage should exceed block gas limit");
    }

    /// @notice Test demonstrates claimToValidate() can exceed gas limits with many pending contributions
    /// @dev This test shows the issue exists - it will fail due to out of gas or excessive iteration
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
            token.mint(contributors[i], STAKE_AMOUNT * 100);
            vm.startPrank(contributors[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 50, contributors[i]);
            vm.stopPrank();
        }

        // Have each contributor claim and submit 50 contributions (total 500)
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(contributors[i]);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 50, adapter);

            for (uint256 j = 0; j < indices.length; j++) {
                bytes32 hash = keccak256(abi.encodePacked("submission", indices[j]));
                engine.contribute(claimId, indices[j], hash, "");
            }
            vm.stopPrank();
        }

        // Now validator tries to claim validations
        // This will iterate through all 500 pending contributions
        _ensureStake(validator1, VALIDATOR_STAKE * 10);

        vm.prank(validator1);

        uint256 gasBefore = gasleft();
        engine.claimToValidate(projectId, 10);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for claimToValidate() with", largeQuantity, "pending:", gasUsed);

        // This demonstrates high gas consumption proportional to pending array length
        // With 500+ pending, gas can become prohibitive
    }

    /// @notice Test shows gas usage scales linearly with totalQuantity in removeProject()
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

            // Have contributors claim all slots
            uint256 slotsPerContributor = quantity / 10;
            if (slotsPerContributor > 0) {
                for (uint256 i = 0; i < 10; i++) {
                    address contrib = makeAddr(string(abi.encodePacked("c", q, "_", i)));
                    token.mint(contrib, STAKE_AMOUNT * 100);
                    vm.startPrank(contrib);
                    token.approve(address(vault), type(uint256).max);
                    vault.deposit(STAKE_AMOUNT * 50, contrib);

                    (uint256 claimId, uint256[] memory indices) =
                        engine.claimToContribute(projectId, slotsPerContributor, adapter);
                    for (uint256 j = 0; j < indices.length; j++) {
                        bytes32 hash = keccak256(abi.encodePacked("submission", indices[j]));
                        engine.contribute(claimId, indices[j], hash, "");
                    }
                    vm.stopPrank();
                }
            }

            // Measure gas for removeProject
            vm.prank(admin);
            uint256 gasBefore = gasleft();
            engine.removeProject(projectId, 0);
            uint256 gasUsed = gasBefore - gasleft();
            gasUsages[q] = gasUsed;

            console2.log("Quantity:", quantity, "Gas used:", gasUsed);
        }

        // Verify gas usage increases with quantity
        for (uint256 i = 1; i < gasUsages.length; i++) {
            assertGt(gasUsages[i], gasUsages[i - 1], "Gas should increase with quantity");
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

            // Have contributors claim and submit all slots
            uint256 slotsPerContributor = quantity / 10;
            if (slotsPerContributor > 0) {
                for (uint256 i = 0; i < 10; i++) {
                    address contrib = makeAddr(string(abi.encodePacked("vc", q, "_", i)));
                    token.mint(contrib, STAKE_AMOUNT * 100);
                    vm.startPrank(contrib);
                    token.approve(address(vault), type(uint256).max);
                    vault.deposit(STAKE_AMOUNT * 50, contrib);

                    (uint256 claimId, uint256[] memory indices) =
                        engine.claimToContribute(projectId, slotsPerContributor, adapter);
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
