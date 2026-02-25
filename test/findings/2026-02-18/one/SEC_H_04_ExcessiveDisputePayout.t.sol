// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ContributionStatus, ProjectStatus, Project} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";

/// @title SEC-H-04 FIX VERIFICATION: Overturned rejection payout capped to rewardRate
/// @notice Verifies that upholding a dispute on a rejected contribution now deducts at most
///         rewardRate from escrow (contributor gets rewardRate - challengerReward, challenger
///         gets the rest), keeping within the per-index budget.
contract SEC_H_04_ExcessiveDisputePayout is BaseTest {
    address public challenger = makeAddr("challenger");

    function setUp() public override {
        super.setUp();
        vm.startPrank(admin);
        engine.setProtocolFee(0);
        engine.setOriginationFee(0);
        vm.stopPrank();

        token.mint(challenger, STAKE_AMOUNT * 10);
        vm.startPrank(challenger);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 5, challenger);
        vm.stopPrank();
    }

    function test_overturnedRejectionCappedToRewardRate() public {
        bytes32 projectId = keccak256("payout-test");
        vm.startPrank(originator);
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
        engine.createProject(projectId, "", config);

        uint256 fundAmount = 5000e18;
        token.approve(address(engine), fundAmount);
        engine.fundProject(projectId, fundAmount, 5, address(0));
        vm.stopPrank();

        uint256 totalEscrow = engine.getProjectEscrow(projectId, address(token));
        assertEq(totalEscrow, fundAmount, "full amount in escrow (no fees)");

        uint256 rewardRate = fundAmount / 5; // 1000e18 per slot

        // Contribution rejected by validators
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 3000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        uint256 escrowAfterConsensus = engine.getProjectEscrow(projectId, address(token));

        // Challenger disputes the rejection
        vm.prank(challenger);
        engine.openDispute(projectId, idx, keccak256("overturn"), "evidenceCid");

        // Operator upholds the dispute
        vm.prank(admin);
        engine.resolveDispute(projectId, idx, true);

        uint256 escrowAfterUphold = engine.getProjectEscrow(projectId, address(token));
        uint256 deducted = escrowAfterConsensus - escrowAfterUphold;

        // FIX VERIFIED: Total deducted is exactly rewardRate (not 120%)
        // Challenger gets 20% of rewardRate from the single budget
        // Contributor gets the remaining 80%
        assertEq(deducted, rewardRate, "total deduction capped to rewardRate");

        // Remaining escrow: 5000 - 1000 = 4000, enough for 4 remaining slots
        uint256 remainingBudgetNeeded = rewardRate * 4;
        assertEq(escrowAfterUphold, remainingBudgetNeeded, "escrow sufficient for remaining slots");
    }

    function test_multipleOverturnsDoNotDrainEscrow() public {
        bytes32 projectId = keccak256("multi-overturn");
        vm.startPrank(originator);
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
        engine.createProject(projectId, "", config);

        uint256 fundAmount = 3000e18;
        token.approve(address(engine), fundAmount);
        engine.fundProject(projectId, fundAmount, 3, address(0));
        vm.stopPrank();

        // FIX VERIFIED: Each overturn only costs rewardRate (1000), not 1200.
        // Three overturns cost 3000 total, exactly matching the escrow.
        _rejectAndOverturn(projectId, 0);
        uint256 escrow1 = engine.getProjectEscrow(projectId, address(token));
        assertEq(escrow1, 2000e18, "3000 - 1000 = 2000");

        _rejectAndOverturn(projectId, 1);
        uint256 escrow2 = engine.getProjectEscrow(projectId, address(token));
        assertEq(escrow2, 1000e18, "2000 - 1000 = 1000");

        _rejectAndOverturn(projectId, 2);
        uint256 escrow3 = engine.getProjectEscrow(projectId, address(token));
        assertEq(escrow3, 0, "1000 - 1000 = 0, all escrow cleanly distributed");
    }

    function _rejectAndOverturn(bytes32 projectId, uint256 contribNum) internal {
        (, uint256[] memory indices) = _claimAndContribute(contribNum == 0 ? contributor1 : contributor2, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 3000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        vm.prank(challenger);
        engine.openDispute(projectId, idx, keccak256(abi.encode("overturn", contribNum)), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(projectId, idx, true);

        // Settle validators to free in-flight stake
        uint256 nonce = contribNum;
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, nonce);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, nonce);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, nonce);
    }
}
