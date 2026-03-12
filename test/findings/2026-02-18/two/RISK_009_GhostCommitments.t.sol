// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {StakeAccount} from "src/Types.sol";

/// @title RISK-009 VERIFIED: Free Option via Ghost Validator Commitments
/// @notice Validators can commit, observe others' reveals on-chain, then choose whether
///         to reveal. cancelExpiredCommitment only activates after commitDeadline +
///         revealDeadline (2 days default), creating a large free-option window.
contract RISK_009_GhostCommitments is BaseTest {
    function test_ghostValidatorFreeOption() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        // Ghost validator commits but will NOT reveal
        uint256 ghostScore = 8000;
        bytes32 ghostSalt = keccak256(abi.encodePacked("salt", validator1, idx));
        bytes32 ghostHash = keccak256(abi.encodePacked(uint256(ghostScore), ghostSalt));
        _ensureStake(validator1, VALIDATOR_STAKE * 2);

        vm.startPrank(validator1);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, ghostHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        uint256 commitTimestamp = block.timestamp;

        // Honest validators also commit (using manual approach to avoid multiple time warps)
        bytes32 salt2 = keccak256(abi.encodePacked("salt", validator2, idx));
        bytes32 commitHash2 = keccak256(abi.encodePacked(uint256(8000), salt2));
        _ensureStake(validator2, VALIDATOR_STAKE * 2);
        vm.startPrank(validator2);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, commitHash2, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        bytes32 salt3 = keccak256(abi.encodePacked("salt", validator3, idx));
        bytes32 commitHash3 = keccak256(abi.encodePacked(uint256(8000), salt3));
        _ensureStake(validator3, VALIDATOR_STAKE * 2);
        vm.startPrank(validator3);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, commitHash3, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // Warp past commit deadline to allow reveals
        vm.warp(commitTimestamp + engine.commitDeadline());

        // Honest validators reveal — scores now visible on-chain
        vm.prank(validator2);
        engine.revealValidation(projectId, idx, 8000, salt2);
        vm.prank(validator3);
        engine.revealValidation(projectId, idx, 8000, salt3);

        assertEq(engine.getRevealCount(projectId, idx), 2, "only 2 reveals, ghost withheld");

        // Ghost cannot be cancelled yet — deadline hasn't elapsed
        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.cancelExpiredCommitment(projectId, idx, validator1);

        // Full window must elapse before cancellation is possible
        vm.warp(commitTimestamp + engine.commitDeadline() + engine.revealDeadline() + 1);
        engine.cancelExpiredCommitment(projectId, idx, validator1);

        // Ghost is finally slashed, but had a multi-day free look at other scores
    }

    function test_ghostCanRevealLateWithinWindow() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        uint256 ghostScore = 8000;
        bytes32 ghostSalt = keccak256(abi.encodePacked("salt", validator1, idx));
        bytes32 ghostHash = keccak256(abi.encodePacked(uint256(ghostScore), ghostSalt));
        _ensureStake(validator1, VALIDATOR_STAKE * 2);

        vm.startPrank(validator1);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, ghostHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        uint256 commitTimestamp = block.timestamp;

        // Other validators also commit
        bytes32 salt2 = keccak256(abi.encodePacked("salt", validator2, idx));
        bytes32 commitHash2 = keccak256(abi.encodePacked(uint256(8000), salt2));
        _ensureStake(validator2, VALIDATOR_STAKE * 2);
        vm.startPrank(validator2);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, commitHash2, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        bytes32 salt3 = keccak256(abi.encodePacked("salt", validator3, idx));
        bytes32 commitHash3 = keccak256(abi.encodePacked(uint256(8000), salt3));
        _ensureStake(validator3, VALIDATOR_STAKE * 2);
        vm.startPrank(validator3);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, commitHash3, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // Warp past commit deadline to allow reveals
        vm.warp(commitTimestamp + engine.commitDeadline());

        // Honest validators reveal — scores now visible on-chain
        vm.prank(validator2);
        engine.revealValidation(projectId, idx, 8000, salt2);
        vm.prank(validator3);
        engine.revealValidation(projectId, idx, 8000, salt3);

        // Ghost sees scores and reveals later within the window
        // The window is: commitTimestamp + commitDeadline to commitTimestamp + commitDeadline + revealDeadline
        // We're already at commitTimestamp + commitDeadline from the earlier warp
        // So we can reveal immediately or warp a bit more (but not past commitTimestamp + commitDeadline + revealDeadline)
        // Let's warp to 1 hour after reveal phase starts
        vm.warp(block.timestamp + 1 hours);

        vm.prank(validator1);
        engine.revealValidation(projectId, idx, ghostScore, ghostSalt);

        assertEq(engine.getRevealCount(projectId, idx), 3, "ghost revealed within window");
    }
}
