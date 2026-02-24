// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ValidationClaimStatus} from "src/Types.sol";

/// @title FIX VERIFIED — PoC-002: Commit Blocked After Validation Claim Expiry
/// @notice Confirms that a validator cannot commit/reveal after their validation
///         claim has expired — the "last look" window is eliminated.
contract POC_002_LateCommitAfterValidationClaimExpiry is BaseTest {
    function test_validatorCanCommitAfterValidationClaimIsExpired() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        uint256[] memory indices = new uint256[](1);
        indices[0] = idx;

        // Validator3 reserves the slot but does not commit yet.
        vm.prank(validator3);
        uint256 v3ClaimId = engine.claimToValidate(projectId, indices);

        // Honest validators reveal first.
        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        assertEq(engine.getRevealCount(projectId, idx), 2, "honest reveals should be visible");

        // Validation claim expires and is cancelled.
        vm.warp(block.timestamp + C.VALIDATION_CLAIM_DEADLINE + 1);
        engine.cancelExpiredValidationClaim(v3ClaimId);
        assertEq(
            uint256(engine.getValidationClaim(v3ClaimId).status),
            uint256(ValidationClaimStatus.Expired),
            "validation claim should be expired"
        );

        // After fix: the ValidatorCommit slot is deleted when the claim is cancelled,
        // so the stale reservation can no longer be used to commit.
        uint256 lateScore = 1000;
        bytes32 salt = keccak256(abi.encodePacked("late-commit", validator3, idx));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(lateScore), salt));

        vm.startPrank(validator3);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.expectRevert();
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        assertEq(engine.getRevealCount(projectId, idx), 2, "late commit+reveal is blocked");
    }
}
