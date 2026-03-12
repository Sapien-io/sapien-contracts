// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {BaseTest} from "../../BaseTest.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus, ValidationClaim} from "src/Types.sol";

/// @title POQ-12: Fix Verification Tests
/// @notice Tests to verify that the paginated processing fixes work correctly
contract POQ_012_UnboundedLoopsGasDoS_FIXED is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    /// @notice Test that removeProject now works with pagination for large projects
    function test_removeProject_PaginationWorks() public {
        uint256 largeQuantity = 200;
        uint256 largeAmount = 200_000e18;

        token.mint(originator, largeAmount * 2);

        bytes32 projectId = keccak256("paginated-project");

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

        // Have contributors claim all slots
        address[] memory contributors = new address[](4);
        for (uint256 i = 0; i < 4; i++) {
            contributors[i] = makeAddr(string(abi.encodePacked("contributor_pag", i)));
            token.mint(contributors[i], STAKE_AMOUNT * 100);
            vm.startPrank(contributors[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 50, contributors[i]);
            vm.stopPrank();
        }

        for (uint256 i = 0; i < 4; i++) {
            vm.startPrank(contributors[i]);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 20, adapter);

            for (uint256 j = 0; j < indices.length; j++) {
                bytes32 hash = keccak256(abi.encodePacked("submission", indices[j]));
                engine.contribute(claimId, indices[j], hash, "");
            }
            vm.stopPrank();
        }

        // Remove project in batches
        vm.startPrank(admin);

        // First batch (50 items)
        (bool complete1, uint256 processed1) = engine.removeProject(projectId, 50);
        assertFalse(complete1, "Should not be complete after first batch");

        // Second batch (50 items)
        (bool complete2, uint256 processed2) = engine.removeProject(projectId, 50);
        assertFalse(complete2, "Should not be complete after second batch");

        // Third batch (50 items)
        (bool complete3, uint256 processed3) = engine.removeProject(projectId, 50);
        assertFalse(complete3, "Should not be complete after third batch");

        // Fourth batch (remaining 50 items)
        (bool complete4, uint256 processed4) = engine.removeProject(projectId, 50);
        assertTrue(complete4, "Should be complete after fourth batch");

        vm.stopPrank();

        // Verify project is now cancelled
        Project memory proj = engine.getProject(projectId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Cancelled), "Project should be cancelled");
    }

    /// @notice Test that removeProject handles default batch size correctly
    function test_removeProject_DefaultBatchSize() public {
        uint256 quantity = 60;
        uint256 amount = 60_000e18;

        bytes32 projectId = _setupProjectWithContributions(quantity, amount);

        vm.startPrank(admin);

        // First call with default batch size (50)
        (bool complete1, uint256 processed1) = engine.removeProject(projectId, 0);
        assertFalse(complete1, "Should not be complete with 60 total");
        assertEq(processed1, 50, "Should process default batch");

        // Second call to finish
        (bool complete2, uint256 processed2) = engine.removeProject(projectId, 0);
        assertTrue(complete2, "Should be complete");
        assertEq(processed2, 10, "Should process remaining 10");

        vm.stopPrank();
    }

    /// @notice Test that removeProject enforces max batch size
    function test_removeProject_MaxBatchSizeEnforced() public {
        uint256 quantity = 150;
        uint256 amount = 150_000e18;

        bytes32 projectId = _setupProjectWithContributions(quantity, amount);

        vm.startPrank(admin);

        // Try to use batch size larger than max (100)
        (bool complete, uint256 processed) = engine.removeProject(projectId, 200);
        assertFalse(complete, "Should not be complete");
        assertLe(processed, 100, "Should cap at max batch size");

        vm.stopPrank();
    }

    /// @notice Test that claimToValidate handles large pending arrays
    function test_claimToValidate_HandlesLargePendingArray() public {
        uint256 quantity = 600;
        uint256 amount = 600_000e18;

        bytes32 projectId = _setupProjectWithSubmissions(quantity, amount);

        // Validator should be able to claim even with 600 pending
        _ensureStake(validator1, VALIDATOR_STAKE * 10);

        vm.prank(validator1);
        uint256 claimId = engine.claimToValidate(projectId, 10);

        assertGt(claimId, 0, "Should successfully claim validations");

        ValidationClaim memory vclaim = engine.getValidationClaim(claimId);
        assertGt(vclaim.totalCount, 0, "Should have assigned some validations");
        assertLe(vclaim.totalCount, 10, "Should not exceed requested quantity");
    }

    /// @notice Test removeProject gas usage stays reasonable with pagination
    function test_removeProject_GasUsageReasonable() public {
        uint256 quantity = 100;
        uint256 amount = 100_000e18;

        bytes32 projectId = _setupProjectWithContributions(quantity, amount);

        vm.startPrank(admin);

        uint256 gasBefore = gasleft();
        engine.removeProject(projectId, 50);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for removeProject() with batch size 50:", gasUsed);

        // Should be under 5M gas for 50 items
        assertLt(gasUsed, 5_000_000, "Gas should be reasonable");

        vm.stopPrank();
    }

    /// @notice Test claimToValidate gas usage stays reasonable
    function test_claimToValidate_GasUsageReasonable() public {
        uint256 quantity = 500;
        uint256 amount = 500_000e18;

        bytes32 projectId = _setupProjectWithSubmissions(quantity, amount);

        _ensureStake(validator1, VALIDATOR_STAKE * 10);

        vm.prank(validator1);
        uint256 gasBefore = gasleft();
        engine.claimToValidate(projectId, 5);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for claimToValidate() with 500 pending:", gasUsed);

        // Should be under 10M gas even with 500 pending (capped at 500 iterations)
        assertLt(gasUsed, 10_000_000, "Gas should be reasonable");
    }

    function _setupProjectWithContributions(uint256 quantity, uint256 amount) internal returns (bytes32 projectId) {
        projectId = keccak256(abi.encodePacked("test-project", block.timestamp));

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
        uint256 contributorsNeeded = (quantity + 19) / 20;
        for (uint256 i = 0; i < contributorsNeeded; i++) {
            address contrib = makeAddr(string(abi.encodePacked("setup_c", i)));
            token.mint(contrib, STAKE_AMOUNT * 100);
            vm.startPrank(contrib);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 50, contrib);

            uint256 claimAmount = (i == contributorsNeeded - 1) ? (quantity % 20 == 0 ? 20 : quantity % 20) : 20;
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, claimAmount, adapter);

            for (uint256 j = 0; j < indices.length; j++) {
                bytes32 hash = keccak256(abi.encodePacked("submission", indices[j]));
                engine.contribute(claimId, indices[j], hash, "");
            }
            vm.stopPrank();
        }

        return projectId;
    }

    function _setupProjectWithSubmissions(uint256 quantity, uint256 amount) internal returns (bytes32 projectId) {
        return _setupProjectWithContributions(quantity, amount);
    }
}
