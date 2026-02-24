// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ProjectStatus} from "src/Types.sol";

/// @title Fix Expectations (2026-02-23)
/// @notice Expected-behavior tests for the findings in
///         `test/findings/2026-02-23/security-functionality-review.md`.
/// @dev These tests are designed for TDD and are expected to fail
///      until the corresponding fixes are implemented.
contract FIX_2026_02_23_ExpectedBehavior is BaseTest {
    function testFIX_expiredValidationClaimsReleaseSlots() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        uint256[] memory indices = new uint256[](1);
        indices[0] = idx;

        vm.prank(validator1);
        uint256 c1 = engine.claimToValidate(projectId, indices);
        vm.prank(validator2);
        uint256 c2 = engine.claimToValidate(projectId, indices);
        vm.prank(validator3);
        uint256 c3 = engine.claimToValidate(projectId, indices);

        vm.warp(block.timestamp + C.VALIDATION_CLAIM_DEADLINE + 1);
        engine.cancelExpiredValidationClaim(c1);
        engine.cancelExpiredValidationClaim(c2);
        engine.cancelExpiredValidationClaim(c3);

        // Expected after fix: all expired reservations are fully released.
        address validator4 = makeAddr("validator4");
        vm.prank(validator4);
        engine.claimToValidate(projectId, indices);
    }

    function testFIX_cannotCommitAfterValidationClaimExpiry() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        uint256[] memory indices = new uint256[](1);
        indices[0] = idx;

        vm.prank(validator3);
        uint256 claimId = engine.claimToValidate(projectId, indices);

        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);

        vm.warp(block.timestamp + C.VALIDATION_CLAIM_DEADLINE + 1);
        engine.cancelExpiredValidationClaim(claimId);

        // Expected after fix: stale/expired validation claim cannot be committed.
        uint256 score = 1000;
        bytes32 salt = keccak256(abi.encodePacked("expired-claim", validator3, idx));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));

        vm.startPrank(validator3);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.expectRevert();
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();
    }

    function testFIX_upheldDisputeOnAcceptedContributionDoesNotDeadlockCompletion() public {
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

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // Expected after fix: upheld disputes still transition contribution
        // lifecycle to a terminal state, allowing project completion.
        vm.prank(originator);
        engine.completeProject(projectId);
        assertEq(uint256(engine.getProject(projectId).status), uint256(ProjectStatus.Completed));
    }

    function testFIX_cancelledFundedProjectCanRefundEscrow() public {
        bytes32 projectId = _createAndFundProject();
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        assertGt(escrowBefore, 0, "funded project should have escrow");

        vm.prank(admin);
        engine.removeProject(projectId);
        assertEq(uint256(engine.getProject(projectId).status), uint256(ProjectStatus.Cancelled));

        // Expected after fix: cancellation path provides an escrow exit.
        vm.prank(originator);
        engine.refundEscrow(projectId);
        assertEq(engine.getProjectEscrow(projectId, address(token)), 0, "escrow should be drained");
    }

    function testFIX_uint256PackedCommitHashRevealsSuccessfully() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        uint256 score = 8000;
        bytes32 salt = keccak256(abi.encodePacked("docs-encoding", validator1, idx));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt)); // 32-byte score packing

        vm.startPrank(validator1);
        uint256[] memory indices = new uint256[](1);
        indices[0] = idx;
        engine.claimToValidate(projectId, indices);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));

        // Expected after fix: hash validation aligns with interface guidance.
        engine.revealValidation(projectId, idx, score, salt);
        vm.stopPrank();
    }
}
