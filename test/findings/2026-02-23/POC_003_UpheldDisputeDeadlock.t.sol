// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {DisputeStatus} from "src/Types.sol";

/// @title FIX VERIFIED — PoC-003: Upheld Dispute No Longer Deadlocks Project Completion
/// @notice Confirms that an upheld dispute on an accepted contribution properly
///         resolves pipeline accounting, allowing project completion.
contract POC_003_UpheldDisputeDeadlock is BaseTest {
    function test_upheldDisputeOnAcceptedContributionBlocksProjectCompletion() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        vm.prank(contributor2);
        engine.openDispute(projectId, idx, keccak256("accepted-dispute"), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(projectId, idx, true);
        assertEq(uint256(engine.getDispute(projectId, idx).status), uint256(DisputeStatus.Upheld), "dispute upheld");

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // After fix: dispute resolution decrements pendingContributions so the
        // project can be completed without being blocked by the overturned contribution.
        vm.prank(originator);
        engine.completeProject(projectId);
    }
}
