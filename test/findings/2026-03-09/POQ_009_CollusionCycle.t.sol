// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Reputation, Contribution} from "src/Types.sol";

/// @title POQ-9: Profitable Self-Dispute Collusion Cycle Extracts Escrow at Zero Net Cost
/// @notice Demonstrates that N Sybil validators can submit identical scores (zero std dev),
///         open a dispute, escalate it after 7 days to auto-uphold, receive bond + 20% reward,
///         and all validators get stake returned + positive reputation despite overturned consensus.
contract POQ_009_CollusionCycle is BaseTest {
    address public disputer;

    function setUp() public override {
        super.setUp();
        disputer = makeAddr("disputer");
        token.mint(disputer, STAKE_AMOUNT * 10);
        vm.startPrank(disputer);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 5, disputer);
        vm.stopPrank();
    }

    /// @notice POQ-9 FIX VERIFICATION: Demonstrates the fix works
    /// After fix:
    /// 1. Escalate dispute requires operator role
    /// 2. Validators with overturned consensus receive negative reputation
    function test_POQ_9_collusionCycle_fixVerification() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        // Step 1: N Sybil validators submit identical scores (zero std dev → no outlier slashing)
        uint256 identicalScore = 8000;
        _commitAndReveal(validator1, projectId, idx, identicalScore, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, identicalScore, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, identicalScore, VALIDATOR_STAKE);

        engine.computeConsensus(projectId, idx);

        // Capture validator reputation before dispute
        Reputation memory val1RepBefore = engine.getReputation(validator1, SKILL_ID);
        Reputation memory val2RepBefore = engine.getReputation(validator2, SKILL_ID);
        Reputation memory val3RepBefore = engine.getReputation(validator3, SKILL_ID);

        // Step 2: Sybil disputer opens a dispute
        vm.warp(block.timestamp + 1);
        bytes32 evidenceHash = keccak256("fake evidence");
        vm.prank(disputer);
        engine.openDispute(projectId, idx, evidenceHash, "ipfs://evidence");

        uint256 disputerBalanceBefore = vault.availableBalance(disputer);
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));

        // Step 3: Wait 7 days and escalate dispute (now requires operator role - POQ-9 fix)
        vm.warp(block.timestamp + C.DISPUTE_RESOLUTION_DEADLINE + 1);
        vm.prank(admin);
        engine.escalateDispute(projectId, idx, 0);

        uint256 disputerBalanceAfter = vault.availableBalance(disputer);
        uint256 escrowAfter = engine.getProjectEscrow(projectId, address(token));

        // Step 4: Verify disputer received bond back + 20% reward
        Contribution memory contribution = engine.getContribution(projectId, idx);
        uint256 expectedReward = (contribution.rewardRate * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;

        assertGt(disputerBalanceAfter, disputerBalanceBefore, "Disputer should gain funds");
        assertEq(escrowBefore - escrowAfter, expectedReward, "Escrow should decrease by challenger reward");

        // Step 5: Settle validators - FIX: they receive negative reputation due to upheld dispute
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        Reputation memory val1RepAfter = engine.getReputation(validator1, SKILL_ID);
        assertLt(val1RepAfter.score, val1RepBefore.score, "FIX: Validator should lose reputation for upheld dispute");

        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        Reputation memory val2RepAfter = engine.getReputation(validator2, SKILL_ID);
        assertLt(val2RepAfter.score, val2RepBefore.score, "FIX: Validator2 should lose reputation for upheld dispute");

        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);
        Reputation memory val3RepAfter = engine.getReputation(validator3, SKILL_ID);
        assertLt(val3RepAfter.score, val3RepBefore.score, "FIX: Validator3 should lose reputation for upheld dispute");
    }

    /// @notice POQ-9 FIX VERIFICATION: Validators with overturned consensus receive negative reputation
    function test_POQ_9_collusionCycle_fix_validatorsGetNegativeReputation() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        // Validators submit identical scores
        uint256 identicalScore = 8000;
        _commitAndReveal(validator1, projectId, idx, identicalScore, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, identicalScore, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, identicalScore, VALIDATOR_STAKE);

        engine.computeConsensus(projectId, idx);

        // Capture validator reputation before dispute
        Reputation memory val1RepBefore = engine.getReputation(validator1, SKILL_ID);

        // Open dispute
        vm.warp(block.timestamp + 1);
        bytes32 evidenceHash = keccak256("fake evidence");
        vm.prank(disputer);
        engine.openDispute(projectId, idx, evidenceHash, "ipfs://evidence");

        // Escalate dispute (requires operator role - POQ-9 fix)
        vm.warp(block.timestamp + C.DISPUTE_RESOLUTION_DEADLINE + 1);
        vm.prank(admin);
        engine.escalateDispute(projectId, idx, 0);

        // Settle validator
        vm.warp(block.timestamp + 1);
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);

        // FIX VERIFIED: Validator receives negative reputation for overturned consensus
        Reputation memory val1RepAfter = engine.getReputation(validator1, SKILL_ID);
        assertLt(val1RepAfter.score, val1RepBefore.score, "FIX: Validator should lose reputation for upheld dispute");
    }

    /// @notice POQ-9 FIX VERIFICATION: Escalate dispute requires operator role
    function test_POQ_9_collusionCycle_fix_escalateRequiresOperator() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        // Validators submit
        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);

        engine.computeConsensus(projectId, idx);

        // Open dispute
        vm.warp(block.timestamp + 1);
        bytes32 evidenceHash = keccak256("fake evidence");
        vm.prank(disputer);
        engine.openDispute(projectId, idx, evidenceHash, "ipfs://evidence");

        // Wait 7 days
        vm.warp(block.timestamp + C.DISPUTE_RESOLUTION_DEADLINE + 1);

        // FIX VERIFIED: Permissionless escalation should revert
        vm.expectRevert();
        engine.escalateDispute(projectId, idx, 0);

        // Only operator can escalate
        vm.prank(admin);
        engine.escalateDispute(projectId, idx, 0);
    }

    /// @notice Verify that after fix, only operator/multi-sig can uphold disputes
    function test_POQ_9_collusionCycle_fix_operatorCanResolveDispute() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        // Validators submit
        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);

        engine.computeConsensus(projectId, idx);

        // Open dispute
        vm.warp(block.timestamp + 1);
        bytes32 evidenceHash = keccak256("fake evidence");
        vm.prank(disputer);
        engine.openDispute(projectId, idx, evidenceHash, "ipfs://evidence");

        // Capture validator reputation before resolution
        Reputation memory val1RepBefore = engine.getReputation(validator1, SKILL_ID);

        // Operator resolves dispute as upheld
        vm.prank(admin);
        engine.resolveDispute(projectId, idx, 0, true);

        // Settle validator
        vm.warp(block.timestamp + 1);
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);

        // Verify negative reputation
        Reputation memory val1RepAfter = engine.getReputation(validator1, SKILL_ID);
        assertLt(val1RepAfter.score, val1RepBefore.score, "Validator should lose reputation when dispute upheld");
    }
}
