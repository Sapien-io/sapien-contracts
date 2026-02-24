// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";

/// @title RISK-010 VERIFIED: No Stake Age Requirement for Validation
/// @notice Tokens deposited in the same block can immediately participate in consensus.
///         No minimum holding period prevents instant deposit-and-validate patterns,
///         undermining the skin-in-the-game guarantee.
contract RISK_010_FlashLoanConsensus is BaseTest {
    function test_sameBlockDepositAndValidation() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        address newValidator = makeAddr("instant-validator");
        uint256 score = 8000;
        bytes32 salt = keccak256(abi.encodePacked("salt", newValidator, idx));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));

        // All in one block: mint → deposit → lock → claim → commit → reveal
        token.mint(newValidator, VALIDATOR_STAKE * 3);
        vm.startPrank(newValidator);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(VALIDATOR_STAKE * 2, newValidator);

        uint256[] memory valIdx = new uint256[](1);
        valIdx[0] = idx;
        engine.claimToValidate(projectId, valIdx);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));
        engine.revealValidation(projectId, idx, score, salt);
        vm.stopPrank();

        assertEq(engine.getRevealCount(projectId, idx), 1, "instant validator counted in consensus");
    }

    function test_sameBlockInfluencesConsensusOutcome() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        // 2 honest validators accept
        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);

        // Instant validator deposits and votes to reject — all in one block
        address instantVal = makeAddr("instant-validator");
        uint256 rejectScore = 1000;
        bytes32 salt = keccak256(abi.encodePacked("salt", instantVal, idx));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(rejectScore), salt));

        token.mint(instantVal, VALIDATOR_STAKE * 3);
        vm.startPrank(instantVal);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(VALIDATOR_STAKE * 2, instantVal);

        uint256[] memory valIdx = new uint256[](1);
        valIdx[0] = idx;
        engine.claimToValidate(projectId, valIdx);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));
        engine.revealValidation(projectId, idx, rejectScore, salt);
        vm.stopPrank();

        // Consensus includes the instant validator's vote
        assertEq(engine.getRevealCount(projectId, idx), 3, "instant validator included");
    }
}
