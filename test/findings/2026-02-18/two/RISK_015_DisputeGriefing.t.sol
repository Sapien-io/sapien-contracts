// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Project, ProjectStatus, Dispute} from "src/Types.sol";

/// @title RISK-015 VERIFIED: Dispute Griefing via Trivial Bond
/// @notice Low-value contributions have near-zero dispute bonds (minimum 1 wei),
///         enabling cheap griefing that delays contributor rewards by up to 7 days.
contract RISK_015_DisputeGriefing is BaseTest {
    function test_oneWeiBondForTinyContributions() public {
        bytes32 pid = keccak256("tiny-project");

        vm.startPrank(originator);
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: 0,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            acceptedContributions: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
        engine.createProject(pid, "", config);
        token.approve(address(engine), 5);
        engine.fundProject(pid, 5, 1, address(0));
        vm.stopPrank();

        // rewardRate ≈ 5 wei after fees
        // disputeBond = rewardRate * disputeBondBps / BPS = 5 * 1000 / 10000 = 0 → min 1 wei

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(pid, 1, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub"), "");
        vm.stopPrank();

        _commitAndReveal(validator1, pid, indices[0], 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, pid, indices[0], 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, pid, indices[0], 8000, VALIDATOR_STAKE);
        engine.computeConsensus(pid, indices[0]);

        // Griefer opens dispute with trivial 1 wei bond
        vm.prank(contributor2);
        engine.openDispute(pid, indices[0], keccak256("grief"), "cid");

        Dispute memory dispute = engine.getDispute(pid, indices[0]);
        assertEq(dispute.bondAmount, 1, "bond is minimum 1 wei - trivial griefing cost");
    }

    function test_griefingDelaysRewardClaim() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // Without dispute, contributor can release reward after challenge period
        // With dispute, reward is blocked until dispute is resolved (up to 7 days)
        vm.prank(contributor2);
        engine.openDispute(projectId, idx, keccak256("grief"), "cid");

        // Even after challenge period, reward is blocked by open dispute
        vm.warp(block.timestamp + engine.challengePeriod() + 1);
        vm.expectRevert();
        engine.releaseContributorReward(projectId, idx);
    }
}
