// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ContributionStatus} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title SEC-H-01 FIX VERIFICATION: completeProject blocked while pipeline active
/// @notice Verifies that completeProject reverts with ProjectHasActivePipeline when
///         contributions are in-flight, preventing escrow drain.
contract SEC_H_01_PrematureCompletion is BaseTest {
    function test_cannotCompleteWithInFlightContributions() public {
        bytes32 projectId = _createAndFundProject();

        // Contributor submits — pipeline is now active
        _claimAndContribute(contributor1, projectId, 1);

        // FIX VERIFIED: completeProject reverts because pendingContributions > 0
        vm.prank(originator);
        vm.expectRevert(ISapienCore.ProjectHasActivePipeline.selector);
        engine.completeProject(projectId);
    }

    function test_canCompleteAfterAllContributionsFinalized() public {
        bytes32 projectId = _createAndFundProject();

        // Contributor submits and validators accept
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        _reveal(validator1, projectId, idx, 8000);
        _reveal(validator2, projectId, idx, 8000);
        _reveal(validator3, projectId, idx, 8000);
        engine.computeConsensus(projectId, idx);

        // Wait for challenge period and release contributor reward
        vm.warp(block.timestamp + C.DEFAULT_CHALLENGE_PERIOD + 1);
        engine.releaseContributorReward(projectId, idx);

        // Now pendingContributions is 0, so completion succeeds
        vm.prank(originator);
        engine.completeProject(projectId);

        assertEq(uint8(engine.getProject(projectId).status), uint8(3), "project should be Completed");
    }

    function test_rejectedContributionsDecrementPipeline() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        // Validators reject
        _claimAndCommit(validator1, projectId, idx, 3000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, idx, 3000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, idx, 3000, VALIDATOR_STAKE);
        _reveal(validator1, projectId, idx, 3000);
        _reveal(validator2, projectId, idx, 3000);
        _reveal(validator3, projectId, idx, 3000);
        engine.computeConsensus(projectId, idx);

        // Rejection decrements pendingContributions, so completeProject succeeds
        vm.prank(originator);
        engine.completeProject(projectId);

        assertEq(uint8(engine.getProject(projectId).status), uint8(3), "project should be Completed");
    }

    function test_escrowSafeAfterProperCompletion() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        _reveal(validator1, projectId, idx, 8000);
        _reveal(validator2, projectId, idx, 8000);
        _reveal(validator3, projectId, idx, 8000);
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
