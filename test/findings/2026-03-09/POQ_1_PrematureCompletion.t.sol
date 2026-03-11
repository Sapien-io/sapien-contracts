// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title POQ-1 FIX VERIFICATION: completeProject blocked while pipeline active
/// @notice Verifies that completeProject reverts with ProjectHasActivePipeline when
///         contributions are in-flight, preventing escrow drain.
contract POQ_1_PrematureCompletion is BaseTest {
    function test_POQ_1_cannotCompleteWithActiveReservedClaim() public {
        bytes32 projectId = _createAndFundProject();

        // Contributor reserves a slot but has not submitted yet.
        vm.prank(contributor1);
        engine.claimToContribute(projectId, 1, adapter);

        vm.prank(originator);
        vm.expectRevert(ISapienCore.ProjectHasActivePipeline.selector);
        engine.completeProject(projectId);
    }

    function test_POQ_1_cannotCompleteWithInFlightContributions() public {
        bytes32 projectId = _createAndFundProject();

        // Contributor submits — pipeline is now active
        _claimAndContribute(contributor1, projectId, 1);

        // FIX VERIFIED: completeProject reverts because pendingContributions > 0
        vm.prank(originator);
        vm.expectRevert(ISapienCore.ProjectHasActivePipeline.selector);
        engine.completeProject(projectId);
    }

    function test_POQ_1_canCompleteAfterAllContributionsFinalized() public {
        bytes32 projectId = _createAndFundProject();

        // Contributor submits and validators accept
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // Wait for challenge period and release contributor reward
        vm.warp(block.timestamp + C.DEFAULT_CHALLENGE_PERIOD + 1);
        engine.releaseContributorReward(projectId, idx);

        // Now pendingContributions is 0, so completion succeeds
        vm.prank(originator);
        engine.completeProject(projectId);

        assertEq(uint8(engine.getProject(projectId).status), uint8(3), "project should be Completed");
    }

    function test_POQ_1_rejectedContributionsDecrementPipeline() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        // Validators reject
        _commitAndReveal(validator1, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 3000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // Rejection decrements pendingContributions, so completeProject succeeds
        vm.prank(originator);
        engine.completeProject(projectId);

        assertEq(uint8(engine.getProject(projectId).status), uint8(3), "project should be Completed");
    }

    function test_POQ_1_escrowSafeAfterProperCompletion() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        vm.warp(block.timestamp + C.DEFAULT_CHALLENGE_PERIOD + 1);
        engine.releaseContributorReward(projectId, idx);

        // Settle validators before completion
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // Complete and refund
        vm.prank(originator);
        engine.completeProject(projectId);

        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);
        vm.prank(originator);
        engine.refundEscrow(projectId);

        uint256 escrowAfter = engine.getProjectEscrow(projectId, address(token));
        assertEq(escrowAfter, 0, "escrow properly drained after all settlements");
    }
}
