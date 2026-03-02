// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title SEC-M-04 FIX VERIFICATION: Reveal deadline now enforced
/// @notice Verifies that revealValidation() rejects reveals after the
///         COMMIT_DEADLINE + REVEAL_DEADLINE window has passed.
contract SEC_M_04_NoRevealDeadline is BaseTest {
    function test_lateRevealRejected() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, idx, 8000, VALIDATOR_STAKE);

        // validator3 commits but does NOT reveal yet
        bytes32 salt = keccak256(abi.encodePacked("salt", validator3, idx));
        uint256 score = 8000;
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));
        vm.startPrank(validator3);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(uint256(VALIDATOR_STAKE));
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // All 3 committed — now reveal validator1 and validator2
        _reveal(validator1, projectId, idx, 8000);
        _reveal(validator2, projectId, idx, 8000);

        // Warp past the reveal deadline
        vm.warp(block.timestamp + C.DEFAULT_COMMIT_DEADLINE + C.DEFAULT_REVEAL_DEADLINE + 1);

        // FIX VERIFIED: validator3's late reveal is now rejected
        vm.prank(validator3);
        vm.expectRevert(ISapienCore.RevealWindowClosed.selector);
        engine.revealValidation(projectId, idx, score, salt);
    }

    function test_revealWithinWindowSucceeds() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, idx, 8000, VALIDATOR_STAKE);

        bytes32 salt = keccak256(abi.encodePacked("salt", validator3, idx));
        uint256 score = 8000;
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));
        vm.startPrank(validator3);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(uint256(VALIDATOR_STAKE));
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // All 3 committed — now reveal validator1 and validator2
        _reveal(validator1, projectId, idx, 8000);
        _reveal(validator2, projectId, idx, 8000);

        // Warp to just before deadline
        vm.warp(block.timestamp + C.DEFAULT_COMMIT_DEADLINE + C.DEFAULT_REVEAL_DEADLINE);

        // Reveal within window succeeds
        vm.prank(validator3);
        engine.revealValidation(projectId, idx, score, salt);

        uint256 revealCount = engine.getRevealCount(projectId, idx);
        assertEq(revealCount, 3, "all 3 reveals accepted within window");
    }

    function test_lateRevealCannotFrontRunCancelExpiredCommitment() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, idx, 8000, VALIDATOR_STAKE);

        bytes32 salt = keccak256(abi.encodePacked("salt", validator3, idx));
        uint256 score = 8000;
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));
        vm.startPrank(validator3);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(uint256(VALIDATOR_STAKE));
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // All 3 committed — now reveal validator1 and validator2
        _reveal(validator1, projectId, idx, 8000);
        _reveal(validator2, projectId, idx, 8000);

        // Warp past the cancellation threshold
        vm.warp(block.timestamp + C.DEFAULT_COMMIT_DEADLINE + C.DEFAULT_REVEAL_DEADLINE + 1);

        // FIX VERIFIED: validator3 cannot front-run with a late reveal
        vm.prank(validator3);
        vm.expectRevert(ISapienCore.RevealWindowClosed.selector);
        engine.revealValidation(projectId, idx, score, salt);

        // cancelExpiredCommitment can now safely be called
        engine.cancelExpiredCommitment(projectId, idx, validator3);
    }
}
