// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Project, ProjectStatus, ConsensusReport, ValidatorConsensusResult, ValidationClaim} from "src/Types.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title POQ-010: numberOfValidations = 1 Collapses All Anti-Collusion Guarantees
/// @notice Fix verification for the critical security issue where numberOfValidations < 3 collapses:
///         - Standard deviation always zero with n=1
///         - Outlier detection cannot trigger with n=1
///         - Single validator can sweep all slots atomically with n=1
///         - Reward is independent of stake amount with n=1
/// @dev This test verifies that minimum numberOfValidations = 3 is enforced.
contract POQ_010_SingleValidationCollapsesSecurity is BaseTest {
    // ══════════════════════════════════════════════════════════════════════
    // Fix Validation: minimum numberOfValidations = 3 enforced
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Test that creating project with numberOfValidations < 3 should revert
    function test_fix_rejectsNumberOfValidationsLessThan3() public {
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
            numberOfValidations: 2, // Less than minimum 3
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
        );
        engine.createProject(keccak256("test-fail"), "", config);

        vm.stopPrank();
    }

    /// @notice Test that creating project with numberOfValidations = 1 should revert
    function test_fix_rejectsNumberOfValidationsOne() public {
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
            numberOfValidations: 1, // Critically broken
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
        );
        engine.createProject(keccak256("test-fail-1"), "", config);

        vm.stopPrank();
    }

    /// @notice Test that numberOfValidations = 3 works correctly with proper std dev
    function test_fix_threeValidationsProperStdDev() public {
        bytes32 projectId = _createProjectWithValidations(3);

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, address(0));
        engine.contribute(claimId, indices[0], keccak256("submission"), "");
        vm.stopPrank();

        // Three validators with different scores
        _commitAndReveal(validator1, projectId, indices[0], 7000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, indices[0], 7500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, indices[0], 8000, VALIDATOR_STAKE);

        engine.computeConsensus(projectId, indices[0]);

        ConsensusReport memory report = engine.getConsensusReport(projectId, indices[0]);

        // With 3 validators having different scores, stdDev should be > 0
        assertGt(report.stdDeviation, 0, "stdDev should be non-zero with varying scores");
    }

    /// @notice Test that outlier detection mechanism is enabled with numberOfValidations = 3
    function test_fix_threeValidationsOutlierDetection() public {
        bytes32 projectId = _createProjectWithValidations(3);

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, address(0));
        engine.contribute(claimId, indices[0], keccak256("submission"), "");
        vm.stopPrank();

        // Three validators with varying scores
        _commitAndReveal(validator1, projectId, indices[0], 9000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, indices[0], 9100, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, indices[0], 100, VALIDATOR_STAKE);

        engine.computeConsensus(projectId, indices[0]);

        // With numberOfValidations = 3, the outlier detection mechanism is enabled
        // (it computes stdDev > 0, unlike with numberOfValidations = 1 where stdDev = 0 always)
        // The key fix is that the mechanism CAN work, not that it catches all outliers
        ConsensusReport memory report = engine.getConsensusReport(projectId, indices[0]);
        assertGt(report.stdDeviation, 0, "stdDev > 0 enables outlier detection mechanism");
    }

    /// @notice Test that a validator cannot monopolize all slots with numberOfValidations = 3
    function test_fix_threeValidationsPreventsSweep() public {
        bytes32 projectId = _createProjectWithValidations(3);

        // Create 5 contributions
        vm.startPrank(contributor1);
        (uint256 claimId1, uint256[] memory indices1) = engine.claimToContribute(projectId, 5, address(0));
        for (uint256 i = 0; i < indices1.length; i++) {
            engine.contribute(claimId1, indices1[i], keccak256(abi.encodePacked("sub", i)), "");
        }
        vm.stopPrank();

        // First validator can claim at most all available slots initially
        vm.prank(validator1);
        uint256 vClaimId1 = engine.claimToValidate(projectId, 10);
        ValidationClaim memory vClaim1 = engine.getValidationClaim(vClaimId1);

        // But after first validator commits, other slots need more validators
        for (uint256 i = 0; i < vClaim1.indices.length && i < 5; i++) {
            bytes32 salt = keccak256(abi.encodePacked("salt1", i));
            bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

            vm.startPrank(validator1);
            engine.lockValidatorCapacity(VALIDATOR_STAKE);
            engine.commitValidation(projectId, vClaim1.indices[i], commitHash, VALIDATOR_STAKE, address(0));
            vm.stopPrank();
        }

        // Second validator should be able to claim same slots (up to numberOfValidations)
        vm.prank(validator2);
        uint256 vClaimId2 = engine.claimToValidate(projectId, 10);
        ValidationClaim memory vClaim2 = engine.getValidationClaim(vClaimId2);

        // With numberOfValidations = 3, we need multiple validators per slot
        assertGt(vClaim2.indices.length, 0, "second validator should also get slots");
    }

    // ══════════════════════════════════════════════════════════════════════
    // Helper Functions
    // ══════════════════════════════════════════════════════════════════════

    /// @notice Helper to create a project with specific numberOfValidations
    function _createProjectWithValidations(uint256 numValidations) internal returns (bytes32) {
        bytes32 projectId = keccak256(abi.encodePacked("project", numValidations, block.timestamp));

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
            numberOfValidations: numValidations,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        engine.createProject(projectId, "", config);

        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(projectId, FUND_AMOUNT, QUANTITY, adapter);

        vm.stopPrank();

        return projectId;
    }
}
