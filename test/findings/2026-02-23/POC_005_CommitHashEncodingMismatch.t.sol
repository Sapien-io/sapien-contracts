// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title FIX VERIFIED — PoC-005: Commit Hash Encoding Aligned with Interface Docs
/// @notice Confirms that `uint256` score in `abi.encodePacked(score, salt)` is the
///         canonical format and reveals successfully; `uint16` (2-byte) packing fails.
contract POC_005_CommitHashEncodingMismatch is BaseTest {
    function test_uint256PackedCommitHashSucceedsReveal() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        uint256 score = 8000;
        bytes32 salt = keccak256(abi.encodePacked("doc-style", validator1, idx));
        bytes32 documentedCommitHash = keccak256(abi.encodePacked(score, salt)); // 32-byte score packing

        vm.startPrank(validator1);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, documentedCommitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        _claimAndCommit(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, idx, 8000, VALIDATOR_STAKE);

        // After fix: uint256-encoded commit hash is the canonical format.
        vm.prank(validator1);
        engine.revealValidation(projectId, idx, score, salt);

        assertEq(engine.getRevealCount(projectId, idx), 1, "uint256 encoding reveals successfully");
    }

    function test_uint16PackedCommitHashFailsReveal() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        uint16 score = 8000;
        bytes32 salt = keccak256(abi.encodePacked("impl-style", validator1, idx));
        bytes32 implCommitHash = keccak256(abi.encodePacked(score, salt)); // 2-byte score packing

        vm.startPrank(validator1);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, implCommitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        _claimAndCommit(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, idx, 8000, VALIDATOR_STAKE);

        // After fix: uint16 (2-byte) packing does not match reveal verification.
        vm.prank(validator1);
        vm.expectRevert(ISapienCore.InvalidReveal.selector);
        engine.revealValidation(projectId, idx, score, salt);
    }
}
