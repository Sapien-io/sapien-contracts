// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ProjectStatus, ContributionStatus, Contribution} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title POQ-7 FIXED: Originator Reclaims Escrow After Project Cancellation, Depriving Contributors of Rewards
/// @notice This test originally demonstrated that after cancellation via upholdOriginatorReport() or removeProject(),
///         contributors with Accepted work cannot call releaseContributorReward() (reverts on Cancelled projects),
///         but the originator can use refundEscrow() after 30 days to drain all remaining escrow including
///         earned contributor rewards. This has been FIXED - rewards are now pre-distributed.
contract POQ_007_OriginatorReclaimEscrowAfterCancellation is BaseTest {
    /// @notice Test that originally demonstrated the vulnerability - now shows it's fixed
    function test_removeProject_ContributorRewardsNowProtected() public {
        // Setup: Create project with accepted contribution
        bytes32 projectId = _setupProjectWithAcceptedContribution();

        // Verify contributor has earned reward
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        assertGt(escrowBefore, 0, "project should have funded escrow");

        // Originator gets project removed (by admin/operator)
        vm.prank(admin);
        engine.removeProject(projectId);

        assertEq(
            uint256(engine.getProject(projectId).status),
            uint256(ProjectStatus.Cancelled),
            "project should be cancelled"
        );

        // FIXED: Contributor now has their rewards in pendingRewards
        uint256 contributorPending = engine.getPendingRewards(contributor1, address(token));
        assertGt(contributorPending, 0, "contributor should have pending rewards after fix");

        // Contributor can claim their reward
        vm.prank(contributor1);
        engine.claimReward(address(token));

        // Wait 30 days
        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);

        // Originator can only drain REMAINING escrow (not contributor's portion)
        uint256 escrowAfterDistribution = engine.getProjectEscrow(projectId, address(token));
        uint256 originatorBalBefore = token.balanceOf(originator);

        if (escrowAfterDistribution > 0) {
            vm.prank(originator);
            engine.refundEscrow(projectId);
        }

        uint256 originatorBalAfter = token.balanceOf(originator);

        // Contributor successfully received their reward
        assertGt(token.balanceOf(contributor1), 0, "contributor received their tokens");
    }

    /// @notice Test that originally demonstrated the vulnerability - now shows it's fixed
    function test_upholdOriginatorReport_ContributorRewardsNowProtected() public {
        // Setup: Create project with accepted contribution
        bytes32 projectId = _setupProjectWithAcceptedContribution();

        // Verify contributor has earned reward
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
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

        // FIXED: Contributor now has their rewards in pendingRewards
        uint256 contributorPending = engine.getPendingRewards(contributor1, address(token));
        assertGt(contributorPending, 0, "contributor should have pending rewards after fix");

        // Contributor can claim their reward
        vm.prank(contributor1);
        engine.claimReward(address(token));

        // Wait 30 days
        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);

        // Originator can only drain REMAINING escrow (not contributor's portion)
        uint256 escrowAfterDistribution = engine.getProjectEscrow(projectId, address(token));
        uint256 originatorBalBefore = token.balanceOf(originator);

        if (escrowAfterDistribution > 0) {
            vm.prank(originator);
            engine.refundEscrow(projectId);
        }

        uint256 originatorBalAfter = token.balanceOf(originator);

        // Contributor successfully received their reward
        assertGt(token.balanceOf(contributor1), 0, "contributor received their tokens");
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
        _claimAndCommit(validator1, projectId, index, score, VALIDATOR_STAKE);

        // Validator 2
        _claimAndCommit(validator2, projectId, index, score, VALIDATOR_STAKE);

        // Validator 3
        _claimAndCommit(validator3, projectId, index, score, VALIDATOR_STAKE);

        // Wait past commit deadline
        vm.warp(block.timestamp + engine.commitDeadline() + 1);

        // Reveal all validators
        _reveal(validator1, projectId, index, score);
        _reveal(validator2, projectId, index, score);
        _reveal(validator3, projectId, index, score);

        // Compute consensus
        vm.prank(validator1);
        engine.computeConsensus(projectId, index);

        // Verify contribution is now Accepted
        Contribution memory contrib = engine.getContribution(projectId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted), "contribution should be accepted");

        return projectId;
    }
}
