// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Contribution, Dispute, DisputeStatus} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title SEC-H-03 FIX VERIFICATION: Dispute reopening blocked after rejection
/// @notice Verifies that only one dispute can be opened per (projectId, index, nonce).
///         After a dispute is rejected, no new dispute can be opened for the same nonce,
///         preventing the infinite grief loop.
contract SEC_H_03_DisputeGriefLoop is BaseTest {
    address public attacker1 = makeAddr("attacker1");
    address public attacker2 = makeAddr("attacker2");

    function setUp() public override {
        super.setUp();
        address[2] memory attackers = [attacker1, attacker2];
        for (uint256 i; i < attackers.length; ++i) {
            token.mint(attackers[i], STAKE_AMOUNT * 10);
            vm.startPrank(attackers[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 5, attackers[i]);
            vm.stopPrank();
        }
    }

    function test_cannotReopenDisputeAfterRejection() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // attacker1 opens dispute
        vm.prank(attacker1);
        engine.openDispute(projectId, idx, keccak256("grief-1"), "evidenceCid");

        // Operator rejects dispute
        vm.prank(admin);
        engine.resolveDispute(projectId, idx, false);

        Dispute memory d = engine.getDispute(projectId, idx);
        assertEq(uint8(d.status), uint8(DisputeStatus.Rejected), "dispute rejected");

        // FIX VERIFIED: attacker2 cannot open a new dispute on the same nonce
        vm.prank(attacker2);
        vm.expectRevert(ISapienCore.DisputeAlreadyClosed.selector);
        engine.openDispute(projectId, idx, keccak256("grief-2"), "evidenceCid");
    }

    function test_cannotReopenDisputeAfterUphold() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        vm.prank(attacker1);
        engine.openDispute(projectId, idx, keccak256("dispute-1"), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(projectId, idx, true);

        // FIX VERIFIED: cannot reopen after uphold either
        vm.prank(attacker2);
        vm.expectRevert(ISapienCore.DisputeAlreadyClosed.selector);
        engine.openDispute(projectId, idx, keccak256("dispute-2"), "evidenceCid");
    }

    function test_rewardBlockedDuringGriefLoop() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // Warp to just before original challenge ends
        vm.warp(block.timestamp + C.DEFAULT_CHALLENGE_PERIOD - 1);

        // Attacker opens dispute — extends deadline
        vm.prank(attacker1);
        engine.openDispute(projectId, idx, keccak256("block-reward"), "evidenceCid");

        vm.warp(block.timestamp + C.DEFAULT_CHALLENGE_PERIOD + 1);

        // Reward still blocked by the open dispute (ChallengeNotElapsed because
        // the dispute extended the challenge window)
        vm.expectRevert(ISapienCore.ChallengeNotElapsed.selector);
        engine.releaseContributorReward(projectId, idx);

        // But once the dispute is resolved and challenge period passes, reward releases
        vm.prank(admin);
        engine.resolveDispute(projectId, idx, false);

        Contribution memory contrib = engine.getContribution(projectId, idx);
        // After rejection, challengeEndsAt is snapped to block.timestamp
        vm.warp(block.timestamp + 1);
        engine.releaseContributorReward(projectId, idx);
    }
}
