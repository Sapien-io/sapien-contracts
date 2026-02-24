// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Dispute, DisputeStatus, ContributionStatus, Contribution} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title SEC-C-01 FIX VERIFICATION: Nonce-keyed disputes prevent cross-nonce poisoning
/// @notice Verifies that disputes are now keyed by (projectId, index, nonce), so a dispute
///         from nonce 0 cannot block reward release for a new contribution at nonce 1.
contract SEC_C_01_DisputeIndexPoisoning is BaseTest {
    address public attacker = makeAddr("attacker");

    function setUp() public override {
        super.setUp();
        token.mint(attacker, STAKE_AMOUNT * 10);
        vm.startPrank(attacker);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 5, attacker);
        vm.stopPrank();
    }

    function test_nonceKeyedDisputeDoesNotBlockNewContributor() public {
        bytes32 projectId = _createAndFundProject();

        // --- Round 1: contributor1 claims index, gets rejected ---
        (, uint256[] memory indices1) = _claimAndContribute(contributor1, projectId, 1);
        uint256 targetIndex = indices1[0];

        _commitAndReveal(validator1, projectId, targetIndex, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, targetIndex, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, targetIndex, 3000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, targetIndex);

        Contribution memory contrib = engine.getContribution(projectId, targetIndex);
        assertEq(uint8(contrib.status), uint8(ContributionStatus.Rejected), "should be rejected");

        // --- Attacker opens dispute on the rejected contribution (nonce 0) ---
        vm.prank(attacker);
        engine.openDispute(projectId, targetIndex, keccak256("evidence"), "evidenceCid");

        // Settle round 1 validators
        vm.prank(validator1);
        engine.settleValidator(projectId, targetIndex, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, targetIndex, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, targetIndex, 0);

        // --- Round 2: contributor2 reclaims the same index, gets accepted ---
        (, uint256[] memory indices2) = _claimAndContribute(contributor2, projectId, 1);
        uint256 recycledIndex = indices2[0];
        assertEq(recycledIndex, targetIndex, "should reclaim the same index from return stack");

        _commitAndReveal(validator1, projectId, recycledIndex, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, recycledIndex, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, recycledIndex, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, recycledIndex);

        contrib = engine.getContribution(projectId, recycledIndex);
        assertEq(uint8(contrib.status), uint8(ContributionStatus.Accepted), "should be accepted");

        // --- Wait for challenge period to pass ---
        vm.warp(block.timestamp + C.DEFAULT_CHALLENGE_PERIOD + 1);

        // FIX VERIFIED: releaseContributorReward succeeds because the dispute
        // from nonce 0 is now isolated and doesn't affect nonce 1.
        engine.releaseContributorReward(projectId, recycledIndex);

        contrib = engine.getContribution(projectId, recycledIndex);
        assertTrue(contrib.rewardReleased, "reward should be released");
    }

    function test_upheldDisputeDoesNotPoisonRecycledIndex() public {
        bytes32 projectId = _createAndFundProject();

        // Round 1: contributor1 rejected
        (, uint256[] memory indices1) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices1[0];

        _commitAndReveal(validator1, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 3000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // Attacker disputes, operator upholds it
        vm.prank(attacker);
        engine.openDispute(projectId, idx, keccak256("evidence"), "evidenceCid");
        vm.prank(admin);
        engine.resolveDispute(projectId, idx, true);

        Dispute memory d = engine.getDispute(projectId, idx);
        assertEq(uint8(d.status), uint8(DisputeStatus.Upheld), "dispute upheld");

        // Settle round 1 validators
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // Round 2: contributor2 claims same index, gets accepted
        (, uint256[] memory indices2) = _claimAndContribute(contributor2, projectId, 1);
        assertEq(indices2[0], idx, "same index recycled");

        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        vm.warp(block.timestamp + C.DEFAULT_CHALLENGE_PERIOD + 1);

        // FIX VERIFIED: contribute() resets rewardReleased and challengeEndsAt,
        // and disputes are nonce-scoped, so recycled index works correctly.
        engine.releaseContributorReward(projectId, idx);

        Contribution memory contrib = engine.getContribution(projectId, idx);
        assertTrue(contrib.rewardReleased, "reward released on recycled index");
    }

    function test_disputeFromOldNonceDoesNotAppearInGetDispute() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 3000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        vm.prank(attacker);
        engine.openDispute(projectId, idx, keccak256("evidence"), "evidenceCid");

        // Before recycling, getDispute returns the open dispute (at nonce 0)
        Dispute memory d1 = engine.getDispute(projectId, idx);
        assertEq(uint8(d1.status), uint8(DisputeStatus.Open), "dispute visible before recycling");

        // Settle and recycle
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        (, uint256[] memory indices2) = _claimAndContribute(contributor2, projectId, 1);
        assertEq(indices2[0], idx, "recycled");

        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // After recycling, getDispute returns the new nonce's dispute (None)
        Dispute memory d2 = engine.getDispute(projectId, idx);
        assertEq(uint8(d2.status), uint8(DisputeStatus.None), "new nonce has no dispute");
    }
}
