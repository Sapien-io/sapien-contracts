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
        uint256[] memory valIdx = new uint256[](1);
        valIdx[0] = idx;
        engine.claimToValidate(projectId, valIdx);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, ghostHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // Honest validators commit and reveal — scores now visible on-chain
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);

        assertEq(engine.getRevealCount(projectId, idx), 2, "only 2 reveals, ghost withheld");

        // Ghost cannot be cancelled yet — deadline hasn't elapsed
        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.cancelExpiredCommitment(projectId, idx, validator1);

        // Advance past commit deadline — still can't cancel (need full window)
        vm.warp(block.timestamp + engine.commitDeadline());
        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.cancelExpiredCommitment(projectId, idx, validator1);

        // Ghost has observed scores and can still strategically reveal or abandon
        // Full window must elapse before cancellation is possible
        vm.warp(block.timestamp + engine.revealDeadline() + 1);
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
        uint256[] memory valIdx = new uint256[](1);
        valIdx[0] = idx;
        engine.claimToValidate(projectId, valIdx);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, ghostHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);

        // Ghost sees scores, waits almost until deadline, then reveals
        vm.warp(block.timestamp + engine.commitDeadline() + engine.revealDeadline() - 1);

        vm.prank(validator1);
        engine.revealValidation(projectId, idx, ghostScore, ghostSalt);

        assertEq(engine.getRevealCount(projectId, idx), 3, "ghost revealed just before deadline");
    }
}
