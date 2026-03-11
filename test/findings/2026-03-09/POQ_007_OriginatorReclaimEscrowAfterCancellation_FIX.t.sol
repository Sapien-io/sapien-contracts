// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ProjectStatus, ContributionStatus, Contribution} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title POQ-7 FIX VERIFIED: Contributor Rewards Protected During Project Cancellation
/// @notice This test verifies that after cancellation via upholdOriginatorReport() or removeProject(),
///         contributors with Accepted work now have their rewards pre-distributed to pendingRewards
///         before the project status is set to Cancelled, preventing the originator from stealing them.
contract POQ_007_OriginatorReclaimEscrowAfterCancellation_FIX is BaseTest {
    /// @notice Test that demonstrates the fix when project is cancelled via removeProject
    function test_removeProject_ContributorRewardsProtected() public {
        // Setup: Create project with accepted contribution
        bytes32 projectId = _setupProjectWithAcceptedContribution();

        // Store initial balances
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        uint256 contributorPendingBefore = engine.getPendingRewards(contributor1, address(token));

        assertGt(escrowBefore, 0, "project should have funded escrow");

        // Originator gets project removed (by admin/operator)
        vm.prank(admin);
        engine.removeProject(projectId);

        assertEq(
            uint256(engine.getProject(projectId).status),
            uint256(ProjectStatus.Cancelled),
            "project should be cancelled"
        );

        // After fix: Contributor's rewards should be in pendingRewards
        uint256 contributorPendingAfter = engine.getPendingRewards(contributor1, address(token));
        assertGt(contributorPendingAfter, contributorPendingBefore, "contributor should have pending rewards");

        // Escrow should be reduced by the amount distributed
        uint256 escrowAfter = engine.getProjectEscrow(projectId, address(token));
        assertLt(escrowAfter, escrowBefore, "escrow should be reduced");

        // Contributor can claim their reward
        vm.prank(contributor1);
        engine.claimReward(address(token));

        assertEq(engine.getPendingRewards(contributor1, address(token)), 0, "pending rewards should be claimed");
        assertGt(token.balanceOf(contributor1), 0, "contributor should have received tokens");

        // Wait 30 days and originator can only refund remaining escrow (not contributor's portion)
        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);

        uint256 originatorBalBefore = token.balanceOf(originator);
        if (escrowAfter > 0) {
            vm.prank(originator);
            engine.refundEscrow(projectId);

            uint256 originatorBalAfter = token.balanceOf(originator);
            assertEq(
                originatorBalAfter - originatorBalBefore, escrowAfter, "originator should only get remaining escrow"
            );
        }

        assertEq(engine.getProjectEscrow(projectId, address(token)), 0, "escrow should be fully drained");
    }

    /// @notice Test that demonstrates the fix when project is cancelled via upholdOriginatorReport
    function test_upholdOriginatorReport_ContributorRewardsProtected() public {
        // Setup: Create project with accepted contribution
        bytes32 projectId = _setupProjectWithAcceptedContribution();

        // Store initial balances
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        uint256 contributorPendingBefore = engine.getPendingRewards(contributor1, address(token));

        assertGt(escrowBefore, 0, "project should have funded escrow");

        // Someone reports the originator for misconduct
        vm.prank(contributor2);
        engine.reportOriginator(projectId, keccak256("originator-misconduct"));

        // Report is upheld
        vm.prank(admin);
        engine.resolveOriginatorReport(projectId, true);

        assertEq(
            uint256(engine.getProject(projectId).status),
            uint256(ProjectStatus.Cancelled),
            "project should be cancelled"
        );

        // After fix: Contributor's rewards should be in pendingRewards
        uint256 contributorPendingAfter = engine.getPendingRewards(contributor1, address(token));
        assertGt(contributorPendingAfter, contributorPendingBefore, "contributor should have pending rewards");

        // Escrow should be reduced by the amount distributed
        uint256 escrowAfter = engine.getProjectEscrow(projectId, address(token));
        assertLt(escrowAfter, escrowBefore, "escrow should be reduced");

        // Contributor can claim their reward
        vm.prank(contributor1);
        engine.claimReward(address(token));

        assertEq(engine.getPendingRewards(contributor1, address(token)), 0, "pending rewards should be claimed");
        assertGt(token.balanceOf(contributor1), 0, "contributor should have received tokens");

        // Wait 30 days and originator can only refund remaining escrow
        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);

        uint256 originatorBalBefore = token.balanceOf(originator);
        if (escrowAfter > 0) {
            vm.prank(originator);
            engine.refundEscrow(projectId);

            uint256 originatorBalAfter = token.balanceOf(originator);
            assertEq(
                originatorBalAfter - originatorBalBefore, escrowAfter, "originator should only get remaining escrow"
            );
        }

        assertEq(engine.getProjectEscrow(projectId, address(token)), 0, "escrow should be fully drained");
    }

    /// @notice Helper to create a project with an accepted contribution
    function _setupProjectWithAcceptedContribution() internal returns (bytes32) {
        bytes32 projectId = _createAndFundProject();

        // Contributor claims a slot and submits work
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, address(0));
        bytes32 submissionHash = keccak256("work-hash");
        engine.contribute(claimId, indices[0], submissionHash, "");
        vm.stopPrank();

        uint256 index = indices[0];

        // Validators claim, commit and reveal high scores (consensus threshold is 70%, scores are 90%)
        uint256 score = 9000; // 90% quality

        // Validator 1
        _commitAndReveal(validator1, projectId, index, score, VALIDATOR_STAKE);

        // Validator 2
        _commitAndReveal(validator2, projectId, index, score, VALIDATOR_STAKE);

        // Validator 3
        _commitAndReveal(validator3, projectId, index, score, VALIDATOR_STAKE);

        // Compute consensus
        vm.warp(block.timestamp + 1);
        vm.prank(validator1);
        engine.computeConsensus(projectId, index);

        // Verify contribution is now Accepted
        Contribution memory contrib = engine.getContribution(projectId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted), "contribution should be accepted");

        return projectId;
    }
}
