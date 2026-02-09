// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {
    ORIGINATOR_ROLE,
    CONTRIBUTOR_ROLE,
    VALIDATOR_ROLE,
    UNAUTHORIZED_NOT_PROJECT_ORIGINATOR
} from "../../src/interface/ISharedTypes.sol";
import {ISharedTypes} from "../../src/interface/ISharedTypes.sol";
import {ISapienCore} from "../../src/interface/ISapienCore.sol";

/**
 * @title TaskRewardDilution
 * @notice Test demonstrating H-2: Task Reward Dilution via Zero-Cost Funding
 *
 * ISSUE DESCRIPTION (ORIGINAL):
 * Anyone can dilute task rewards to near-zero by calling fundProject() with rewardAmount=0
 * and an arbitrarily high quantity. The function lacks access control and does not validate
 * that rewardAmount > 0.
 *
 * FIX IMPLEMENTED:
 * - Added access control: Only project originator can fund their project
 * - Added validation: If quantity > 0, rewardAmount must be > 0
 * - Prevents zero-cost dilution attacks
 *
 * ROOT CAUSE:
 * - fundProject() had no access control (anyone could call it)
 * - No validation that rewardAmount > 0
 * - Attacker could inflate totalQuantityAvailable without adding rewards
 *
 * IMPACT (WITHOUT FIX):
 * Critical economic griefing at near-zero cost. A task with 1,000 USDC for 100 items
 * (10 USDC/item) can be diluted to 0.001 USDC/item with a single transaction costing only gas.
 *
 * IMPACT (WITH FIX):
 * Attack is impossible - unauthorized funding reverts, zero-reward funding reverts.
 */
contract TaskRewardDilutionTest is BaseTest {
    bytes32 projectId;
    uint256 constant INITIAL_REWARDS = 1000 ether;
    uint256 constant INITIAL_QUANTITY = 100;
    uint256 constant INITIAL_REWARD_PER_ITEM = INITIAL_REWARDS / INITIAL_QUANTITY; // 10 tokens

    address attacker = makeAddr("attacker");

    function setUp() public override {
        super.setUp();

        // Grant roles to participants
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        vm.stopPrank();

        // Create project
        vm.startPrank(originator);
        projectId = keccak256("reward-dilution-test");
        core.createProject(
            projectId,
            address(rewardToken),
            "reward-dilution-test",
            10 ether, // minStakeToClaim
            10 ether, // minStakeToContribute
            3, // minValidations
            1000, // validatorRewardBasisPoints (10%)
            ""
        );

        // Originator funds project with legitimate rewards
        rewardToken.approve(address(core), INITIAL_REWARDS);
        core.fundProject(projectId, INITIAL_REWARDS, INITIAL_QUANTITY);
        vm.stopPrank();
    }

    /**
     * @notice Test that reward dilution attack is blocked by access control
     * This test verifies the FIX is working
     */
    function test_RewardDilutionAttack_BlockedByAccessControl() public {
        // ============================================
        // 1. RECORD INITIAL STATE
        // ============================================
        uint256 initialRewards = getProjectRewards(projectId);
        uint256 initialQuantity = getProjectQuantity(projectId);
        uint256 initialRewardPerItem = initialRewards / initialQuantity;

        assertEq(initialRewards, INITIAL_REWARDS, "Initial rewards should match");
        assertEq(initialQuantity, INITIAL_QUANTITY, "Initial quantity should match");
        assertEq(initialRewardPerItem, INITIAL_REWARD_PER_ITEM, "Initial reward per item should be 10 tokens");

        console.log("=== BEFORE ATTACK ===");
        console.log("Total rewards:", initialRewards / 1 ether);
        console.log("Total quantity:", initialQuantity);
        console.log("Reward per item:", initialRewardPerItem / 1 ether);

        // ============================================
        // 2. ATTACKER ATTEMPTS TO DILUTE REWARDS (FIX: BLOCKED)
        // ============================================
        uint256 dilutionQuantity = 1_000_000; // Massively inflate quantity

        vm.startPrank(attacker);

        // FIX VERIFICATION: Attack is blocked by access control
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_NOT_PROJECT_ORIGINATOR));
        core.fundProject(projectId, 0, dilutionQuantity);

        vm.stopPrank();

        // ============================================
        // 3. VERIFY REWARDS WERE NOT DILUTED
        // ============================================
        uint256 afterRewards = getProjectRewards(projectId);
        uint256 afterQuantity = getProjectQuantity(projectId);

        console.log("=== AFTER BLOCKED ATTACK ===");
        console.log("Total rewards:", afterRewards / 1 ether);
        console.log("Total quantity:", afterQuantity);
        console.log("Attack blocked: YES");

        // Verify the attack was blocked - state unchanged
        assertEq(afterRewards, initialRewards, "Total rewards unchanged");
        assertEq(afterQuantity, initialQuantity, "FIX VERIFIED: Quantity NOT inflated");

        console.log("FIX VERIFIED: Unauthorized funding blocked!");
    }

    /**
     * @notice Test that multiple attackers are all blocked by access control
     */
    function test_MultipleAttackers_AllBlocked() public {
        uint256 initialQuantity = getProjectQuantity(projectId);

        // Multiple attackers try to dilute
        address attacker2 = makeAddr("attacker2");
        address attacker3 = makeAddr("attacker3");

        // All attacks are blocked
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_NOT_PROJECT_ORIGINATOR));
        core.fundProject(projectId, 0, 100_000);

        vm.prank(attacker2);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_NOT_PROJECT_ORIGINATOR));
        core.fundProject(projectId, 0, 100_000);

        vm.prank(attacker3);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_NOT_PROJECT_ORIGINATOR));
        core.fundProject(projectId, 0, 100_000);

        uint256 finalQuantity = getProjectQuantity(projectId);

        console.log("Attacker attempts: 3");
        console.log("Successful attacks: 0");
        console.log("Project quantity unchanged:", finalQuantity == initialQuantity);

        // Verify no dilution occurred
        assertEq(finalQuantity, initialQuantity, "FIX VERIFIED: All attacks blocked");
    }

    /**
     * @notice Test that zero-reward funding is blocked even for originator
     */
    function test_ZeroRewardFunding_Blocked() public {
        // Even the originator cannot fund with zero rewards
        vm.startPrank(originator);

        // Mint some tokens for potential legitimate funding
        rewardToken.mint(originator, 1000 ether);
        rewardToken.approve(address(core), 1000 ether);

        // Attempt to add quantity without rewards
        vm.expectRevert(ISapienCore.InvalidAmount.selector);
        core.fundProject(projectId, 0, 100);

        vm.stopPrank();

        console.log("FIX VERIFIED: Zero-reward funding blocked even for originator");
    }

    /**
     * @notice Test that legitimate funding still works for originator
     */
    function test_LegititmateFunding_StillWorks() public {
        uint256 initialQuantity = getProjectQuantity(projectId);
        uint256 initialRewards = getProjectRewards(projectId);

        // Originator can legitimately add more rewards and quantity
        vm.startPrank(originator);

        rewardToken.mint(originator, 1000 ether);
        rewardToken.approve(address(core), 1000 ether);

        // Legitimate funding: adding rewards WITH quantity
        core.fundProject(projectId, 1000 ether, 100);

        vm.stopPrank();

        uint256 afterQuantity = getProjectQuantity(projectId);
        uint256 afterRewards = getProjectRewards(projectId);

        assertEq(afterQuantity, initialQuantity + 100, "Quantity increased");
        assertEq(afterRewards, initialRewards + 1000 ether, "Rewards increased");

        uint256 rewardPerItem = afterRewards / afterQuantity;
        console.log("Reward per item after legitimate funding:", rewardPerItem / 1 ether);
        console.log("FIX VERIFIED: Legitimate funding works correctly");
    }

    /**
     * @notice Test that legitimate contributors receive correct (non-diluted) rewards
     */
    function skipTestContributorsReceiveCorrectRewards() public {
        // Setup validator capacity
        _setValidatorCapacity(validator1, 100 ether);
        _setValidatorCapacity(validator2, 100 ether);
        _setValidatorCapacity(validator3, 100 ether);

        vm.startPrank(admin);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        // Record expected reward (now attack is blocked, reward should be correct)
        uint256 expectedReward = (INITIAL_REWARDS * 9000) / (10000 * INITIAL_QUANTITY); // 90% of 10 tokens = 9 tokens
        console.log("Expected reward (no attack possible):", expectedReward / 1 ether);

        // Attacker tries to dilute rewards but is BLOCKED
        vm.prank(attacker);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_NOT_PROJECT_ORIGINATOR));
        core.fundProject(projectId, 0, 900);

        // Contributor does legitimate work
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(projectId, 1);
        core.contribute(projectId, claimId, 0, keccak256("good work"));
        vm.stopPrank();

        // Validators approve
        uint256 stake = 100 ether;
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");

        bytes32 commitHash1 = keccak256(abi.encodePacked(uint256(8000), stake, salt1));
        bytes32 commitHash2 = keccak256(abi.encodePacked(uint256(8000), stake, salt2));
        bytes32 commitHash3 = keccak256(abi.encodePacked(uint256(8000), stake, salt3));

        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v1ClaimId, 0, commitHash1);
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v2ClaimId, 0, commitHash2);
        vm.stopPrank();

        vm.startPrank(validator3);
        uint256 v3ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v3ClaimId, 0, commitHash3);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(validator1);
        oracle.revealValidation(projectId, 0, 8000, salt1);
        vm.prank(validator2);
        oracle.revealValidation(projectId, 0, 8000, salt2);
        vm.prank(validator3);
        oracle.revealValidation(projectId, 0, 8000, salt3);

        vm.prank(contributor);
        core.finalizeContribution(projectId, 0);

        // Check actual reward received
        uint256 actualReward = rewards.getAvailableRewards(contributor, projectId, address(rewardToken));

        console.log("Expected reward:", expectedReward / 1 ether);
        console.log("Actual reward received:", actualReward / 1 ether);
        console.log("FIX VERIFIED: Contributor receives correct reward");

        // Contributor receives full expected reward (attack was blocked)
        assertEq(actualReward, expectedReward, "FIX VERIFIED: Contributor receives full reward");
    }

    /**
     * @notice Test the economic impact of the attack (if it were possible)
     * This demonstrates why the fix is critical
     */
    function test_EconomicImpactCalculation() public pure {
        // Scenario: Project with $10,000 USDC for 100 tasks ($100/task)
        uint256 projectValue = 10_000 ether; // Representing 10,000 USDC
        uint256 taskCount = 100;
        uint256 rewardPerTask = projectValue / taskCount; // $100 per task

        // Attacker cost: only gas (let's say ~$5 in gas)
        uint256 attackCost = 5 ether; // Representing $5

        // Attacker dilutes with massive quantity
        uint256 dilutionFactor = 1_000_000;

        // Calculate diluted reward
        uint256 dilutedRewardPerTask = projectValue / (taskCount + dilutionFactor);

        // Economic damage
        uint256 valueDestroyed = (rewardPerTask - dilutedRewardPerTask) * taskCount;
        uint256 roi = valueDestroyed / attackCost;

        console.log("=== ECONOMIC IMPACT ===");
        console.log("Project value (USD):", projectValue / 1 ether);
        console.log("Original reward/task (USD):", rewardPerTask / 1 ether);
        console.log("Diluted reward/task (USD):", dilutedRewardPerTask);
        console.log("Value destroyed (USD):", valueDestroyed / 1 ether);
        console.log("Attack cost (USD):", attackCost / 1 ether);
        console.log("Attack ROI:", roi, "x");

        assertTrue(roi > 1000, "Attack has >1000x ROI - extremely profitable griefing");
    }
}
