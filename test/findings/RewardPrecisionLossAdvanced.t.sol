// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title RewardPrecisionLossAdvancedTest
 * @notice Test demonstrating Issue #4: Reward Calculation Precision Loss on Small Projects
 *
 * VULNERABILITY DESCRIPTION:
 * The reward calculation can result in 0 rewards if:
 * totalRewardsAvailable * (10000 - validatorRewardBasisPoints) < 10000 * totalQuantityAvailable
 *
 * Example: 100 tokens with 10% validator reward = 90 reward per contribution.
 * But if there are 100 slots: 100 * 9000 / (10000 * 100) = 900000 / 1000000 = 0
 *
 * ATTACK VECTOR: Economic Manipulation
 *
 * LOCATION: SapienCore.sol lines 775-779 (_calculateContributorReward)
 *
 * SEVERITY: Medium
 */
contract RewardPrecisionLossAdvancedTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("precision-test");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        _setupValidator(validator1, 100 ether);
        _setupValidator(validator2, 100 ether);
        _setupValidator(validator3, 100 ether);
    }

    /**
     * @notice Test: Fix verification - Zero reward per slot is now blocked
     * @dev Issue #4 fix: fundProject enforces MIN_REWARD_PER_SLOT
     */
    function test_ZeroContributorReward_FixVerification() public {
        uint256 rewardAmount = 100; // 100 wei - too small
        uint256 quantity = 100;
        uint256 validatorBps = 1000; // 10% validator reward

        uint256 minRewardPerSlot = core.MIN_REWARD_PER_SLOT();
        console.log("=== Fix Verification: Minimum Reward Per Slot ===");
        console.log("Minimum reward per slot:", minRewardPerSlot);

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "precision-test", 0, 0, 1, validatorBps, "");
        rewardToken.approve(address(core), rewardAmount);

        // Try to fund with too-small reward - should revert
        vm.expectRevert(); // RewardPerSlotTooLow
        core.fundProject(PROJECT_ID, rewardAmount, quantity);
        vm.stopPrank();

        console.log("FIX VERIFIED: Funding with too-small rewards blocked");
        console.log("Contributors protected from zero-reward projects");
    }

    /**
     * @notice Test: Calculate the minimum reward to avoid precision loss
     * @dev Find the threshold where precision loss stops occurring
     */
    function test_MinimumRewardToAvoidPrecisionLoss() public pure {
        uint256 quantity = 100;
        uint256 validatorBps = 1000; // 10%

        // For reward > 0, we need:
        // rewardAmount * (10000 - validatorBps) >= 10000 * quantity
        // rewardAmount >= (10000 * quantity) / (10000 - validatorBps)
        // rewardAmount >= (10000 * 100) / 9000
        // rewardAmount >= 1000000 / 9000
        // rewardAmount >= 112 (rounded up)

        uint256 minReward = (10000 * quantity + (10000 - validatorBps) - 1) / (10000 - validatorBps);
        console.log("=== Minimum Reward Calculation ===");
        console.log("Slots:", quantity);
        console.log("Validator BPS:", validatorBps);
        console.log("Minimum reward to avoid precision loss:", minReward);

        // Verify
        uint256 rewardPerSlot = (minReward * (10000 - validatorBps)) / (10000 * quantity);
        console.log("Reward per slot at minimum:", rewardPerSlot);

        assertGt(rewardPerSlot, 0, "Should have non-zero reward at minimum threshold");
    }

    /**
     * @notice Test: Fix verification - Inadequate funding is blocked at creation
     * @dev Issue #4 fix: Small reward/large quantity combinations rejected
     */
    function test_E2E_PrecisionLossInFinalization_FixVerification() public {
        uint256 rewardAmount = 1000; // Small reward
        uint256 quantity = 1000; // Many slots - would cause precision loss

        uint256 minRewardPerSlot = core.MIN_REWARD_PER_SLOT();
        console.log("=== Fix Verification: E2E Precision Loss Prevention ===");
        console.log("Attempting: 1000 tokens / 1000 slots = 1 token per slot");
        console.log("Minimum required per slot:", minRewardPerSlot);

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "precision-test", 0, 0, 2, 1000, "");
        rewardToken.approve(address(core), rewardAmount);

        // Try to fund with inadequate reward per slot - should revert
        vm.expectRevert(); // RewardPerSlotTooLow
        core.fundProject(PROJECT_ID, rewardAmount, quantity);
        vm.stopPrank();

        console.log("FIX VERIFIED: Funding with inadequate rewards blocked");
        console.log("Contributors protected from projects that would pay nothing");
    }

    /**
     * @notice Test: Accumulated precision loss over many contributions
     * @dev Each contribution loses a small amount, total loss is significant
     */
    function test_AccumulatedPrecisionLoss() public pure {
        uint256 totalRewards = 1 ether;
        uint256 quantity = 3;
        uint256 validatorBps = 2000; // 20%

        // Calculate per-contribution reward
        uint256 rewardPerContrib = (totalRewards * (10000 - validatorBps)) / (10000 * quantity);
        uint256 totalDistributed = rewardPerContrib * quantity;
        uint256 intendedTotal = (totalRewards * (10000 - validatorBps)) / 10000;

        console.log("=== Accumulated Precision Loss ===");
        console.log("Total rewards:", totalRewards);
        console.log("Slots:", quantity);
        console.log("Validator BPS:", validatorBps);
        console.log("Intended contributor share (80%):", intendedTotal);
        console.log("Per-contribution reward:", rewardPerContrib);
        console.log("Total actually distributed:", totalDistributed);
        console.log("Precision loss (wei):", intendedTotal - totalDistributed);
        console.log("Precision loss (%):", ((intendedTotal - totalDistributed) * 10000) / intendedTotal);

        assertLt(totalDistributed, intendedTotal, "Some rewards lost to precision");
    }

    /**
     * @notice Test: Document recommended mitigations
     */
    function test_DocumentMitigations() public pure {
        console.log("=== Recommended Mitigations ===");
        console.log("");
        console.log("1. Add minimum reward check:");
        console.log("   if (rewardPerContrib == 0) revert RewardTooSmall();");
        console.log("");
        console.log("2. Scale up calculation:");
        console.log("   uint256 scaled = (totalRewards * 1e18 * (10000 - bps)) / (10000 * quantity);");
        console.log("   uint256 reward = scaled / 1e18;");
        console.log("");
        console.log("3. Require minimum reward per slot at project creation:");
        console.log("   uint256 minRewardPerSlot = rewardAmount / quantity;");
        console.log("   if (minRewardPerSlot < MIN_REWARD_THRESHOLD) revert RewardTooSmall();");
        console.log("");
        console.log("4. Track and distribute remainder:");
        console.log("   uint256 remainder = totalDistributed % quantity;");
        console.log("   // Distribute remainder to last contributor or treasury");
    }

    // Helper to validate a contribution with all validators
    function _validateContribution(bytes32 projectId, uint256 contribIndex, uint256 score) internal {
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");
        uint256 stake = 100 ether;

        vm.startPrank(validator1);
        uint256 v1Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v1Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt1)));
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v2Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt2)));
        vm.stopPrank();

        vm.startPrank(validator3);
        uint256 v3Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v3Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt3)));
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        vm.prank(validator1);
        oracle.revealValidation(projectId, contribIndex, score, salt1);
        vm.prank(validator2);
        oracle.revealValidation(projectId, contribIndex, score, salt2);
        vm.prank(validator3);
        oracle.revealValidation(projectId, contribIndex, score, salt3);
    }

    function _setupValidator(address v, uint256 amount) internal {
        _setupUser(v, amount);
        vm.startPrank(admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();
        vm.prank(v);
        oracle.setValidatorCapacity(amount);
    }
}
