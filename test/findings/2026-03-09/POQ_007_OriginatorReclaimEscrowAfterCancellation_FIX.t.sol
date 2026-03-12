// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ProjectStatus, ContributionStatus, Contribution} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title POQ-7 FIX VERIFIED: Contributor Rewards Protected During Project Cancellation
/// @notice Verifies that after cancellation, contributors can settle rewards via paginated
///         batch settlement or individual releaseContributorReward(), while the originator
///         can only refund remaining escrow after 30 days.
contract POQ_007_OriginatorReclaimEscrowAfterCancellation_FIX is BaseTest {
    /// @notice Test that removeProject sets Cancelled and batch settlement distributes rewards
    function test_removeProject_ContributorRewardsProtected() public {
        (bytes32 projectId,) = _setupProjectWithAcceptedContribution();

        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        uint256 contributorPendingBefore = engine.getPendingRewards(contributor1, address(token));

        assertGt(escrowBefore, 0, "project should have funded escrow");

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        assertEq(
            uint256(engine.getProject(projectId).status),
            uint256(ProjectStatus.Cancelled),
            "project should be cancelled"
        );

        _warpPastChallengePeriod();

        engine.settleContributorRewards(projectId, 100);

        uint256 contributorPendingAfter = engine.getPendingRewards(contributor1, address(token));
        assertGt(contributorPendingAfter, contributorPendingBefore, "contributor should have pending rewards");

        uint256 escrowAfter = engine.getProjectEscrow(projectId, address(token));
        assertLt(escrowAfter, escrowBefore, "escrow should be reduced");

        vm.prank(contributor1);
        engine.claimReward(address(token));

        assertEq(engine.getPendingRewards(contributor1, address(token)), 0, "pending rewards should be claimed");
        assertGt(token.balanceOf(contributor1), 0, "contributor should have received tokens");

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

    /// @notice Test that upholdOriginatorReport sets Cancelled and batch settlement distributes rewards
    function test_upholdOriginatorReport_ContributorRewardsProtected() public {
        (bytes32 projectId,) = _setupProjectWithAcceptedContribution();

        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        uint256 contributorPendingBefore = engine.getPendingRewards(contributor1, address(token));

        assertGt(escrowBefore, 0, "project should have funded escrow");

        vm.prank(contributor2);
        engine.reportOriginator(projectId, keccak256("originator-misconduct"));

        vm.prank(admin);
        engine.resolveOriginatorReport(projectId, true);

        assertEq(
            uint256(engine.getProject(projectId).status),
            uint256(ProjectStatus.Cancelled),
            "project should be cancelled"
        );

        _warpPastChallengePeriod();

        engine.settleContributorRewards(projectId, 100);

        uint256 contributorPendingAfter = engine.getPendingRewards(contributor1, address(token));
        assertGt(contributorPendingAfter, contributorPendingBefore, "contributor should have pending rewards");

        uint256 escrowAfter = engine.getProjectEscrow(projectId, address(token));
        assertLt(escrowAfter, escrowBefore, "escrow should be reduced");

        vm.prank(contributor1);
        engine.claimReward(address(token));

        assertEq(engine.getPendingRewards(contributor1, address(token)), 0, "pending rewards should be claimed");
        assertGt(token.balanceOf(contributor1), 0, "contributor should have received tokens");

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

    /// @notice Test individual releaseContributorReward works on cancelled projects
    function test_releaseContributorReward_worksOnCancelledProject() public {
        (bytes32 projectId, uint256 index) = _setupProjectWithAcceptedContribution();

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        assertEq(
            uint256(engine.getProject(projectId).status),
            uint256(ProjectStatus.Cancelled),
            "project should be cancelled"
        );

        _warpPastChallengePeriod();

        uint256 pendingBefore = engine.getPendingRewards(contributor1, address(token));
        engine.releaseContributorReward(projectId, index);
        uint256 pendingAfter = engine.getPendingRewards(contributor1, address(token));

        assertGt(pendingAfter, pendingBefore, "contributor reward should be released on cancelled project");
    }

    /// @notice Test paginated settlement processes batches correctly with cursor advancement
    function test_paginatedSettlement_cursorAdvancement() public {
        (bytes32 projectId,) = _setupProjectWithAcceptedContribution();

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        _warpPastChallengePeriod();

        uint256 totalQuantity = engine.getProject(projectId).totalQuantity;

        assertEq(engine.getSettlementCursor(projectId), 0, "cursor should start at 0");

        // Settle first 5 of 10 total indices
        engine.settleContributorRewards(projectId, 5);
        assertEq(engine.getSettlementCursor(projectId), 5, "cursor should advance to 5");

        // Settle remaining 5
        engine.settleContributorRewards(projectId, 100);
        assertEq(engine.getSettlementCursor(projectId), totalQuantity, "cursor should reach end");

        // Further calls should revert
        vm.expectRevert(ISapienCore.SettlementAlreadyComplete.selector);
        engine.settleContributorRewards(projectId, 1);
    }

    /// @notice Test that settlement respects challenge finality
    function test_settlement_respectsChallengeFinality() public {
        (bytes32 projectId,) = _setupProjectWithAcceptedContribution();

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        // Don't warp past challenge period
        uint256 processed = engine.settleContributorRewards(projectId, 100);
        uint256 contributorPending = engine.getPendingRewards(contributor1, address(token));

        assertEq(processed, 0, "should not process unfinalised contributions");
        assertEq(contributorPending, 0, "no rewards should be distributed before challenge expires");
    }

    /// @notice Test that non-cancelled project can't use settleContributorRewards
    function test_settleContributorRewards_revertsOnActiveProject() public {
        (bytes32 projectId,) = _setupProjectWithAcceptedContribution();

        vm.expectRevert(ISapienCore.ProjectNotCancellable.selector);
        engine.settleContributorRewards(projectId, 100);
    }

    /// @notice Test emitted event from batch settlement
    function test_settleContributorRewards_emitsEvent() public {
        (bytes32 projectId, uint256 index) = _setupProjectWithAcceptedContribution();

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        _warpPastChallengePeriod();

        vm.expectEmit(true, false, false, false);
        emit ISapienCore.ContributorRewardsSettled(projectId, 0, 0);
        engine.settleContributorRewards(projectId, 100);
    }

    /// @notice Helper to create a project with a single accepted contribution
    function _setupProjectWithAcceptedContribution() internal returns (bytes32, uint256) {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, address(0));
        bytes32 submissionHash = keccak256("work-hash");
        engine.contribute(claimId, indices[0], submissionHash, "");
        vm.stopPrank();

        uint256 index = indices[0];
        uint256 score = 9000;

        _commitAndReveal(validator1, projectId, index, score, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, index, score, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, index, score, VALIDATOR_STAKE);

        vm.warp(block.timestamp + 1);
        vm.prank(validator1);
        engine.computeConsensus(projectId, index);

        Contribution memory contrib = engine.getContribution(projectId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted), "contribution should be accepted");

        return (projectId, index);
    }
}
