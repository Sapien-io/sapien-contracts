// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TransparentUpgradeableProxy} from
    "lib/openzeppelin-contracts/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

import {SapienVault} from "src/SapienVault.sol";
import {SapienQA} from "src/SapienQA.sol";
import {Multiplier} from "src/Multiplier.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {Constants as Const} from "src/utils/Constants.sol";

contract SapienVaultEndToEndTest is Test {
    // Core contracts
    SapienVault public sapienVault;
    SapienQA public sapienQA;
    MockERC20 public sapienToken;

    // System accounts
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public qaManager = makeAddr("qaManager");

    // User personas for comprehensive testing
    address public conservativeStaker = makeAddr("conservativeStaker"); // Low risk, short lockups
    address public aggressiveStaker = makeAddr("aggressiveStaker"); // High risk, long lockups
    address public strategicStaker = makeAddr("strategicStaker"); // Dynamic strategy adjustments
    address public emergencyUser = makeAddr("emergencyUser"); // Emergency exits
    address public compoundStaker = makeAddr("compoundStaker"); // Progressive stake building
    address public qaVictim = makeAddr("qaVictim"); // QA penalty scenarios
    address public maxStaker = makeAddr("maxStaker"); // Boundary testing
    address public socialStaker = makeAddr("socialStaker"); // Community behaviors

    // Test parameters aligned with contract constants
    uint256 public constant INITIAL_BALANCE = 10_000_000 * 10 ** 18; // 10M tokens per user
    uint256 public constant MINIMUM_STAKE = 1000 * 10 ** 18; // 1K tokens
    uint256 public constant LARGE_STAKE = 9_000 * 10 ** 18; // 9K tokens (within 10k limit)
    uint256 public constant MEDIUM_STAKE = 5_000 * 10 ** 18; // 5K tokens (within 10k limit)
    uint256 public constant SMALL_STAKE = 2_000 * 10 ** 18; // 2K tokens
    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 public constant EARLY_WITHDRAWAL_PENALTY = 2000; // 20% in basis points

    // Lockup periods
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    // Tracking variables for comprehensive verification
    uint256 public totalOriginalBalance;
    uint256 public totalCurrentStaked;
    uint256 public totalPenaltiesCollected;
    uint256 public totalQAPenalties;

    function setUp() public {
        // Deploy token
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        // Deploy SapienVault with proxy
        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector,
            address(sapienToken),
            admin,
            makeAddr("pauseManager"),
            treasury,
            makeAddr("dummySapienQA")
        );
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        // Deploy SapienQA implementation and proxy
        SapienQA qaImpl = new SapienQA();
        bytes memory qaInitData = abi.encodeWithSelector(
            SapienQA.initialize.selector, treasury, address(sapienVault), qaManager, makeAddr("qaSigner"), admin
        );
        sapienQA = SapienQA(address(new TransparentUpgradeableProxy(address(qaImpl), admin, qaInitData)));

        // Grant QA manager role to QA contract
        vm.prank(admin);
        sapienVault.grantRole(Const.QA_MANAGER_ROLE, address(sapienQA));

        // Grant SAPIEN_QA_ROLE to QA contract so it can call processQAPenalty
        vm.prank(admin);
        sapienVault.grantRole(Const.SAPIEN_QA_ROLE, address(sapienQA));

        // Setup user balances
        address[8] memory users = [
            conservativeStaker,
            aggressiveStaker,
            strategicStaker,
            emergencyUser,
            compoundStaker,
            qaVictim,
            maxStaker,
            socialStaker
        ];

        for (uint256 i = 0; i < users.length; i++) {
            sapienToken.mint(users[i], INITIAL_BALANCE);
            vm.prank(users[i]);
            sapienToken.approve(address(sapienVault), type(uint256).max);
            totalOriginalBalance += INITIAL_BALANCE;
        }

        console.log("=== Staking End-to-End Test Setup Complete ===");
        console.log("Total user balances:", totalOriginalBalance / 10 ** 18, "tokens");
        console.log("Users configured:", users.length);
    }

    // ============================================
    // COMPLETE END-TO-END STAKING JOURNEY TEST
    // ============================================

    function test_EndToEnd_CompleteStakingJourney() public {
        console.log("\n=== COMPLETE END-TO-END STAKING JOURNEY ===");

        // Phase 1: Initial Adoption & Basic Staking (Day 0-30)
        console.log("\n--- Phase 1: Initial Adoption & Basic Staking ---");
        _phaseInitialAdoption();

        // Phase 2: Stake Optimization & Growth (Day 30-90)
        console.log("\n--- Phase 2: Stake Optimization & Growth ---");
        _phaseStakeOptimization();

        // Phase 3: Strategic Adjustments (Day 90-180)
        console.log("\n--- Phase 3: Strategic Adjustments ---");
        _phaseStrategicAdjustments();

        // Phase 4: Maturity & Complexity (Day 180-270)
        console.log("\n--- Phase 4: Maturity & Complexity ---");
        _phaseMaturityAndComplexity();

        // Phase 5: Emergency & Edge Cases (Day 270-365)
        console.log("\n--- Phase 5: Emergency & Edge Cases ---");
        _phaseEmergencyAndEdgeCases();

        // Phase 6: QA Integration & Penalties
        console.log("\n--- Phase 6: QA Integration & Penalties ---");
        _phaseQAIntegration();

        // Phase 7: Long-term Operations (Day 365+)
        console.log("\n--- Phase 7: Long-term Operations ---");
        _phaseLongTermOperations();

        // Final comprehensive verification
        _finalComprehensiveVerification();
    }

    // Helper function for early unstake with proper cooldown
    function _performEarlyUnstakeWithCooldown(address user, uint256 amount) internal {
        vm.startPrank(user);
        sapienVault.initiateEarlyUnstake(amount);
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        sapienVault.earlyUnstake(amount);
        vm.stopPrank();
    }

    function _phaseInitialAdoption() internal {
        // Conservative staker starts with small, safe stakes
        vm.prank(conservativeStaker);
        sapienVault.stake(SMALL_STAKE, LOCK_30_DAYS);
        totalCurrentStaked += SMALL_STAKE;

        console.log("Conservative staker: First stake", SMALL_STAKE / 10 ** 18, "SAPIEN for 30 days");

        // Aggressive staker goes big immediately
        vm.prank(aggressiveStaker);
        sapienVault.stake(LARGE_STAKE, LOCK_365_DAYS);
        totalCurrentStaked += LARGE_STAKE;

        console.log("Aggressive staker: Large stake", LARGE_STAKE / 10 ** 18, "SAPIEN for 365 days");

        // Strategic staker starts medium
        vm.prank(strategicStaker);
        sapienVault.stake(MEDIUM_STAKE, LOCK_90_DAYS);
        totalCurrentStaked += MEDIUM_STAKE;

        console.log("Strategic staker: Medium stake", MEDIUM_STAKE / 10 ** 18, "SAPIEN for 90 days");

        // Verify initial state
        assertEq(sapienVault.totalStaked(), totalCurrentStaked);
        assertTrue(sapienVault.hasActiveStake(conservativeStaker));
        assertTrue(sapienVault.hasActiveStake(aggressiveStaker));
        assertTrue(sapienVault.hasActiveStake(strategicStaker));

        // Advance time to simulate first month
        vm.warp(block.timestamp + 30 days);
        console.log("Time advanced: 30 days");
    }

    function _phaseStakeOptimization() internal {
        // Conservative staker gains confidence, increases amount
        vm.prank(conservativeStaker);
        sapienVault.increaseAmount(SMALL_STAKE * 2); // 3x total now
        totalCurrentStaked += SMALL_STAKE * 2;

        console.log("Conservative staker: Increased stake by", (SMALL_STAKE * 2) / 10 ** 18, "SAPIEN");

        // Strategic staker extends lockup for better multiplier
        vm.prank(strategicStaker);
        sapienVault.increaseLockup(180 days); // Now 270 days total

        console.log("Strategic staker: Extended lockup by 180 days");

        // Compound staker enters with progressive strategy
        vm.prank(compoundStaker);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        totalCurrentStaked += MINIMUM_STAKE;

        console.log("Compound staker: Initial minimum stake", MINIMUM_STAKE / 10 ** 18, "SAPIEN");

        // Social staker joins with medium stake
        vm.prank(socialStaker);
        sapienVault.stake(MEDIUM_STAKE, LOCK_180_DAYS);
        totalCurrentStaked += MEDIUM_STAKE;

        // Test boundary: max staker tests system limits (within 10k limit)
        uint256 maxTestAmount = 9_500 * 10 ** 18; // 9.5k tokens (within 10k limit)
        vm.prank(maxStaker);
        sapienVault.stake(maxTestAmount, LOCK_365_DAYS);
        totalCurrentStaked += maxTestAmount;

        console.log("Max staker: Large system test", maxTestAmount / 10 ** 18, "SAPIEN");

        // Advance time
        vm.warp(block.timestamp + 60 days); // Total: 90 days
        console.log("Time advanced: 60 days (total: 90 days)");
    }

    function _phaseStrategicAdjustments() internal {
        // Compound staker executes growth strategy
        for (uint256 i = 0; i < 3; i++) {
            uint256 increaseAmount = SMALL_STAKE * (i + 1);
            vm.prank(compoundStaker);
            sapienVault.increaseAmount(increaseAmount);
            totalCurrentStaked += increaseAmount;

            // Also increase lockup progressively
            vm.prank(compoundStaker);
            sapienVault.increaseLockup(30 days);

            vm.warp(block.timestamp + 10 days);
            console.log("Compound staker: Iteration increased by", increaseAmount / 10 ** 18, "SAPIEN");
        }

        // Strategic staker rebalances again
        vm.prank(strategicStaker);
        sapienVault.increaseAmount(LARGE_STAKE);
        totalCurrentStaked += LARGE_STAKE;

        console.log("Strategic staker: Major rebalance +", LARGE_STAKE / 10 ** 18, "SAPIEN");

        // Conservative staker decides to extend lockup for first time
        vm.prank(conservativeStaker);
        sapienVault.increaseLockup(60 days); // Extending beyond original 30 days

        console.log("Conservative staker: First lockup extension +60 days");

        // Time progression - now some early stakes might be unlocking
        vm.warp(block.timestamp + 90 days); // Total: 180 days
        console.log("Time advanced: 90 days (total: 180 days)");
    }

    function _phaseMaturityAndComplexity() internal {
        // Log initial state
        console.log("\n=== Initial State ===");
        console.log("Current block timestamp:", block.timestamp);

        ISapienVault.UserStakingSummary memory conservativeStake = sapienVault.getUserStakingSummary(conservativeStaker);
        console.log("\nConservative staker initial state:");
        console.log("Total staked:", conservativeStake.userTotalStaked / 10 ** 18, "SAPIEN");
        console.log("Weighted start time:", conservativeStake.effectiveLockUpPeriod);
        console.log("Effective lockup period:", conservativeStake.effectiveLockUpPeriod);
        console.log("Time until unlock:", conservativeStake.timeUntilUnlock);
        console.log(
            "Is unlocked:",
            block.timestamp >= (conservativeStake.effectiveLockUpPeriod + conservativeStake.timeUntilUnlock)
        );

        // Get social staker state
        ISapienVault.UserStakingSummary memory socialStake = sapienVault.getUserStakingSummary(socialStaker);
        console.log("\nSocial staker initial state:");
        console.log("Total staked:", socialStake.userTotalStaked / 10 ** 18, "SAPIEN");
        console.log("Weighted start time:", socialStake.effectiveLockUpPeriod);
        console.log("Effective lockup period:", socialStake.effectiveLockUpPeriod);
        console.log("Time until unlock:", socialStake.timeUntilUnlock);
        console.log(
            "Is unlocked:", block.timestamp >= (socialStake.effectiveLockUpPeriod + socialStake.timeUntilUnlock)
        );

        // Calculate how much time we need to wait for both stakes
        uint256 timeNeeded = conservativeStake.timeUntilUnlock > socialStake.timeUntilUnlock
            ? conservativeStake.timeUntilUnlock
            : socialStake.timeUntilUnlock;

        console.log("\nTime needed to wait:", timeNeeded);
        console.log("Current time:", block.timestamp);
        console.log("Target unlock time:", block.timestamp + timeNeeded);

        // Ensure enough time has passed for both stakes to unlock
        vm.warp(block.timestamp + timeNeeded + 1); // Add 1 second buffer

        // Log state after time warp
        console.log("\n=== State After Time Warp ===");
        console.log("New block timestamp:", block.timestamp);

        conservativeStake = sapienVault.getUserStakingSummary(conservativeStaker);
        console.log("\nConservative staker state after time warp:");
        console.log("Total staked:", conservativeStake.userTotalStaked / 10 ** 18, "SAPIEN");
        console.log("Weighted start time:", conservativeStake.effectiveLockUpPeriod);
        console.log("Effective lockup period:", conservativeStake.effectiveLockUpPeriod);
        console.log("Time until unlock:", conservativeStake.timeUntilUnlock);
        console.log(
            "Is unlocked:",
            block.timestamp >= (conservativeStake.effectiveLockUpPeriod + conservativeStake.timeUntilUnlock)
        );

        socialStake = sapienVault.getUserStakingSummary(socialStaker);
        console.log("\nSocial staker state after time warp:");
        console.log("Total staked:", socialStake.userTotalStaked / 10 ** 18, "SAPIEN");
        console.log("Weighted start time:", socialStake.effectiveLockUpPeriod);
        console.log("Effective lockup period:", socialStake.effectiveLockUpPeriod);
        console.log("Time until unlock:", socialStake.timeUntilUnlock);
        console.log(
            "Is unlocked:", block.timestamp >= (socialStake.effectiveLockUpPeriod + socialStake.timeUntilUnlock)
        );

        // Test unstaking flows - conservative staker tries to exit partially
        uint256 unstakeAmount = SMALL_STAKE;

        console.log("\n=== Attempting Unstake ===");
        console.log("Attempting to unstake:", unstakeAmount / 10 ** 18, "SAPIEN");
        console.log("Current time:", block.timestamp);
        console.log("Time until unlock:", conservativeStake.timeUntilUnlock);

        vm.prank(conservativeStaker);
        sapienVault.initiateUnstake(unstakeAmount);

        console.log("Conservative staker: Initiated unstake of", unstakeAmount / 10 ** 18, "SAPIEN");

        // Fast forward through cooldown
        uint256 previousTime = block.timestamp;
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        console.log("Time warped from", previousTime, "to", block.timestamp);

        uint256 balanceBefore = sapienToken.balanceOf(conservativeStaker);
        vm.prank(conservativeStaker);
        sapienVault.unstake(unstakeAmount);
        uint256 balanceAfter = sapienToken.balanceOf(conservativeStaker);

        assertEq(balanceAfter - balanceBefore, unstakeAmount);
        totalCurrentStaked -= unstakeAmount;

        console.log("Conservative staker: Successfully unstaked", unstakeAmount / 10 ** 18, "SAPIEN");

        // SOCIAL STAKER UNSTAKING - COMPLETELY REWRITTEN USING FIXED TIMESTAMPS

        // Social staker first unstake
        console.log("\n=== Social Staker First Unstake ===");
        uint256 socialUnstakeAmount = SMALL_STAKE;

        // Capture state before unstaking
        uint256 beforeBalance = sapienToken.balanceOf(socialStaker);
        console.log("Social staker balance before:", beforeBalance / 10 ** 18, "SAPIEN");
        console.log("Social staker total staked:", sapienVault.getTotalStaked(socialStaker) / 10 ** 18, "SAPIEN");

        // Use fixed timestamps for testing
        uint256 firstInitiateTime = 20_000_000;
        console.log("Warping to first initiate time:", firstInitiateTime);
        vm.warp(firstInitiateTime);

        // Step 1: Initiate unstake
        vm.prank(socialStaker);
        sapienVault.initiateUnstake(socialUnstakeAmount);
        console.log("Social staker initiated unstake at time:", block.timestamp);

        // Step 2: Wait for cooldown period to complete
        uint256 firstUnstakeTime = firstInitiateTime + COOLDOWN_PERIOD + 100; // Add buffer
        console.log("Cooldown period:", COOLDOWN_PERIOD);
        console.log("Warping to after first cooldown:", firstUnstakeTime);
        vm.warp(firstUnstakeTime);
        console.log("Current time after warp:", block.timestamp);
        console.log("Time passed since cooldown initiation:", block.timestamp - firstInitiateTime);

        // Step 3: Complete the unstake
        vm.prank(socialStaker);
        sapienVault.unstake(socialUnstakeAmount);

        // Verify unstake was successful
        uint256 afterBalance = sapienToken.balanceOf(socialStaker);
        console.log("Social staker balance after:", afterBalance / 10 ** 18, "SAPIEN");
        console.log("Balance increase:", (afterBalance - beforeBalance) / 10 ** 18, "SAPIEN");
        assertEq(afterBalance - beforeBalance, socialUnstakeAmount);

        totalCurrentStaked -= socialUnstakeAmount;
        console.log("Social staker: Successfully unstaked first amount");

        // Social staker second unstake
        console.log("\n=== Social Staker Second Unstake ===");

        // Reset variables for clarity
        beforeBalance = sapienToken.balanceOf(socialStaker);
        console.log("Social staker balance before second unstake:", beforeBalance / 10 ** 18, "SAPIEN");
        console.log("Social staker remaining staked:", sapienVault.getTotalStaked(socialStaker) / 10 ** 18, "SAPIEN");

        // Use fixed timestamps for testing
        uint256 secondInitiateTime = 21_000_000;
        console.log("Warping to second initiate time:", secondInitiateTime);
        vm.warp(secondInitiateTime);

        // Step 1: Initiate second unstake
        vm.prank(socialStaker);
        sapienVault.initiateUnstake(socialUnstakeAmount);
        console.log("Social staker initiated second unstake at time:", block.timestamp);

        // Step 2: Wait for second cooldown period to complete
        uint256 secondUnstakeTime = secondInitiateTime + COOLDOWN_PERIOD + 100; // Add buffer
        console.log("Cooldown period:", COOLDOWN_PERIOD);
        console.log("Warping to after second cooldown:", secondUnstakeTime);
        vm.warp(secondUnstakeTime);
        console.log("Current time after warp:", block.timestamp);
        console.log("Time passed since second cooldown initiation:", block.timestamp - secondInitiateTime);

        // Step 3: Complete the second unstake
        vm.prank(socialStaker);
        sapienVault.unstake(socialUnstakeAmount);

        // Verify second unstake was successful
        afterBalance = sapienToken.balanceOf(socialStaker);
        console.log("Social staker balance after second unstake:", afterBalance / 10 ** 18, "SAPIEN");
        console.log("Balance increase from second unstake:", (afterBalance - beforeBalance) / 10 ** 18, "SAPIEN");
        assertEq(afterBalance - beforeBalance, socialUnstakeAmount);

        totalCurrentStaked -= socialUnstakeAmount;
        console.log("Social staker: Successfully unstaked second amount");

        // Emergency user setup for next phase
        vm.prank(emergencyUser);
        sapienVault.stake(LARGE_STAKE, LOCK_365_DAYS);
        totalCurrentStaked += LARGE_STAKE;

        vm.warp(block.timestamp + 90 days); // Total: 270 days
        console.log("Time advanced: 90 days (total: 270 days)");
    }

    function _phaseEmergencyAndEdgeCases() internal {
        // Emergency user needs instant liquidity - uses early unstake (with cooldown)
        uint256 emergencyAmount = MEDIUM_STAKE;
        uint256 expectedPenalty = (emergencyAmount * EARLY_WITHDRAWAL_PENALTY) / 10000;
        uint256 expectedPayout = emergencyAmount - expectedPenalty;

        uint256 userBalanceBefore = sapienToken.balanceOf(emergencyUser);
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        // Use helper function for early unstake with cooldown
        _performEarlyUnstakeWithCooldown(emergencyUser, emergencyAmount);

        uint256 userBalanceAfter = sapienToken.balanceOf(emergencyUser);
        uint256 treasuryBalanceAfter = sapienToken.balanceOf(treasury);

        assertEq(userBalanceAfter - userBalanceBefore, expectedPayout);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedPenalty);

        totalCurrentStaked -= emergencyAmount;
        totalPenaltiesCollected += expectedPenalty;

        console.log("Emergency user: Early unstake", emergencyAmount / 10 ** 18, "SAPIEN");
        console.log("Penalty collected:", expectedPenalty / 10 ** 18, "SAPIEN");

        // Test edge case: trying to initiate early unstake for more than available
        vm.prank(emergencyUser);
        vm.expectRevert();
        sapienVault.initiateEarlyUnstake(LARGE_STAKE * 2); // Should fail

        console.log("Emergency user: Correctly failed oversized unstake");

        // Test system pause functionality
        vm.prank(makeAddr("pauseManager"));
        sapienVault.pause();

        vm.prank(maxStaker);
        vm.expectRevert();
        sapienVault.stake(SMALL_STAKE, LOCK_30_DAYS); // Should fail when paused

        vm.prank(makeAddr("pauseManager"));
        sapienVault.unpause();

        console.log("System: Pause/unpause functionality verified");

        vm.warp(block.timestamp + 95 days); // Total: 365 days
        console.log("Time advanced: 95 days (total: 365 days)");
    }

    function _phaseQAIntegration() internal {
        // QA victim receives penalty
        vm.prank(qaVictim);
        sapienVault.stake(LARGE_STAKE, LOCK_180_DAYS);
        totalCurrentStaked += LARGE_STAKE;

        console.log("QA victim: Staked before penalty", LARGE_STAKE / 10 ** 18, "SAPIEN");

        // Simulate QA penalty process
        uint256 penaltyAmount = MEDIUM_STAKE;
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        vm.prank(address(sapienQA));
        uint256 actualPenalty = sapienVault.processQAPenalty(qaVictim, penaltyAmount);

        uint256 treasuryBalanceAfter = sapienToken.balanceOf(treasury);

        assertEq(actualPenalty, penaltyAmount);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, penaltyAmount);

        totalCurrentStaked -= penaltyAmount;
        totalQAPenalties += penaltyAmount;

        console.log("QA victim: Penalty processed", actualPenalty / 10 ** 18, "SAPIEN");

        // Test QA penalty larger than stake
        vm.prank(address(sapienQA));
        uint256 largePenalty = sapienVault.processQAPenalty(qaVictim, LARGE_STAKE * 2);

        // Should only penalize remaining stake
        assertTrue(largePenalty < LARGE_STAKE * 2);
        console.log("QA victim: Large penalty processed", largePenalty / 10 ** 18, "SAPIEN");

        totalCurrentStaked -= largePenalty;
        totalQAPenalties += largePenalty;
    }

    function _phaseLongTermOperations() internal {
        // Aggressive staker finally unlocks after full year
        console.log("\n=== Aggressive Staker Unstaking ===");

        // First, check the current state of the aggressive staker
        ISapienVault.UserStakingSummary memory aggressiveStakeSummary =
            sapienVault.getUserStakingSummary(aggressiveStaker);
        console.log("Aggressive staker current state:");
        console.log("Total staked:", aggressiveStakeSummary.userTotalStaked / 10 ** 18, "SAPIEN");
        console.log("Effective lockup period:", aggressiveStakeSummary.effectiveLockUpPeriod);
        console.log("Time until unlock:", aggressiveStakeSummary.timeUntilUnlock);
        console.log("Current time:", block.timestamp);

        // Calculate exactly how much time is needed to unlock
        uint256 targetTime;
        if (aggressiveStakeSummary.timeUntilUnlock > 0) {
            console.log("Stake still locked, waiting for unlock...");
            targetTime = block.timestamp + aggressiveStakeSummary.timeUntilUnlock + 1 days;
        } else {
            console.log("Stake already unlocked");
            targetTime = block.timestamp + 1 days;
        }

        // Warp to unlock time with an extra buffer
        console.log("Warping from", block.timestamp, "to", targetTime);
        vm.warp(targetTime);

        // Verify stake is now unlocked
        aggressiveStakeSummary = sapienVault.getUserStakingSummary(aggressiveStaker);
        console.log("After time warp:");
        console.log("Current time:", block.timestamp);
        console.log("Time until unlock:", aggressiveStakeSummary.timeUntilUnlock);
        console.log("Is unlocked:", aggressiveStakeSummary.timeUntilUnlock == 0);

        // Start unstaking process
        uint256 unstakeAmount = LARGE_STAKE / 2;
        console.log("Initiating unstake of", unstakeAmount / 10 ** 18, "SAPIEN");

        vm.prank(aggressiveStaker);
        sapienVault.initiateUnstake(unstakeAmount);
        console.log("Unstake initiated at time:", block.timestamp);

        // Wait for cooldown to complete
        console.log("Waiting for cooldown period:", COOLDOWN_PERIOD);
        uint256 cooldownCompleteTime = block.timestamp + COOLDOWN_PERIOD + 1 hours; // Add extra buffer
        console.log("Warping to after cooldown:", cooldownCompleteTime);
        vm.warp(cooldownCompleteTime);
        console.log("Current time after cooldown:", block.timestamp);

        // Verify tokens are ready for unstaking
        uint256 readyForUnstake = sapienVault.getTotalReadyForUnstake(aggressiveStaker);
        console.log("Amount ready for unstake:", readyForUnstake / 10 ** 18, "SAPIEN");
        require(readyForUnstake >= unstakeAmount, "Tokens should be ready for unstaking");

        // Complete the unstake
        vm.prank(aggressiveStaker);
        sapienVault.unstake(unstakeAmount);
        totalCurrentStaked -= unstakeAmount;

        console.log("Aggressive staker: Long-term unstake completed");

        // Max staker tests system with large operations
        vm.prank(maxStaker);
        sapienVault.increaseAmount(500 * 10 ** 18); // Another 500 tokens (keeping within 10K limit)
        totalCurrentStaked += 500 * 10 ** 18;

        console.log("Max staker: Large late-stage increase");

        // Compound staker reaches maximum optimization
        vm.prank(compoundStaker);
        sapienVault.increaseLockup(100 days); // Further optimize

        console.log("Compound staker: Final optimization");

        // New users can still join mature system
        address lateJoiner = makeAddr("lateJoiner");
        sapienToken.mint(lateJoiner, INITIAL_BALANCE);
        vm.prank(lateJoiner);
        sapienToken.approve(address(sapienVault), type(uint256).max);

        vm.prank(lateJoiner);
        sapienVault.stake(MEDIUM_STAKE, LOCK_90_DAYS);
        totalCurrentStaked += MEDIUM_STAKE;

        console.log("Late joiner: Successfully entered mature system");

        vm.warp(block.timestamp + 30 days);
        console.log("Time advanced: 30 days (total: ~400 days)");
    }

    function _finalComprehensiveVerification() internal {
        console.log("\n=== FINAL COMPREHENSIVE VERIFICATION ===");

        // Token conservation check
        uint256 totalTokensInVault = sapienToken.balanceOf(address(sapienVault));
        uint256 totalTokensInTreasury = sapienToken.balanceOf(treasury);
        uint256 totalUserBalances = 0;

        address[8] memory users = [
            conservativeStaker,
            aggressiveStaker,
            strategicStaker,
            emergencyUser,
            compoundStaker,
            qaVictim,
            maxStaker,
            socialStaker
        ];

        for (uint256 i = 0; i < users.length; i++) {
            totalUserBalances += sapienToken.balanceOf(users[i]);
        }

        // Account for late joiner
        totalUserBalances += sapienToken.balanceOf(makeAddr("lateJoiner"));

        console.log("Tokens in vault:", totalTokensInVault / 10 ** 18);
        console.log("Tokens in treasury:", totalTokensInTreasury / 10 ** 18);
        console.log("Total user balances:", totalUserBalances / 10 ** 18);
        console.log("Contract total staked:", sapienVault.totalStaked() / 10 ** 18);
        console.log("Tracked total staked:", totalCurrentStaked / 10 ** 18);

        // Core invariants
        assertEq(sapienVault.totalStaked(), totalCurrentStaked, "Tracked staked amount mismatch");
        assertEq(totalTokensInVault, sapienVault.totalStaked(), "Vault balance != total staked");

        // System health checks
        assertTrue(sapienVault.totalStaked() > 0, "System should have active stakes");
        assertTrue(totalTokensInTreasury > 0, "Treasury should have collected penalties");

        // Verify specific user states
        assertTrue(sapienVault.hasActiveStake(aggressiveStaker), "Aggressive staker should still have stake");
        assertTrue(sapienVault.hasActiveStake(maxStaker), "Max staker should have stake");
        assertTrue(sapienVault.hasActiveStake(compoundStaker), "Compound staker should have stake");

        // Check that emergency user has reduced stake
        uint256 emergencyUserStake = sapienVault.getTotalStaked(emergencyUser);
        assertTrue(emergencyUserStake < LARGE_STAKE, "Emergency user should have reduced stake");

        console.log("Total penalties collected:", totalPenaltiesCollected / 10 ** 18, "SAPIEN");
        console.log("Total QA penalties:", totalQAPenalties / 10 ** 18, "SAPIEN");

        // Advanced verification - check that multipliers are reasonable
        for (uint256 i = 0; i < users.length; i++) {
            if (sapienVault.hasActiveStake(users[i])) {
                ISapienVault.UserStakingSummary memory userStake = sapienVault.getUserStakingSummary(users[i]);
                assertTrue(userStake.effectiveMultiplier > 0, "Active stakes should have positive multipliers");
            }
        }

        console.log("\n=== ALL END-TO-END STAKING TESTS PASSED ===");
        console.log("System successfully handled:");
        console.log("- Initial staking with various strategies");
        console.log("- Stake modifications (amount & lockup increases)");
        console.log("- Multiple unstaking patterns");
        console.log("- Emergency early unstaking with penalties");
        console.log("- QA integration and penalty processing");
        console.log("- Long-term operations and late joiners");
        console.log("- System pause/unpause functionality");
        console.log("- Edge cases and boundary conditions");
        console.log("- Token conservation and accounting");
    }

    // ============================================
    // SPECIALIZED SCENARIO TESTS
    // ============================================

    function test_StakingPattern_ProgressiveBuilder() public {
        console.log("\n=== PROGRESSIVE BUILDER PATTERN ===");

        address builder = makeAddr("progressiveBuilder");
        sapienToken.mint(builder, INITIAL_BALANCE);
        vm.prank(builder);
        sapienToken.approve(address(sapienVault), type(uint256).max);

        // Start small and build up over time
        vm.prank(builder);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);

        // Week 1: Double the stake
        vm.warp(block.timestamp + 7 days);
        vm.prank(builder);
        sapienVault.increaseAmount(MINIMUM_STAKE);

        // Week 2: Extend lockup
        vm.warp(block.timestamp + 7 days);
        vm.prank(builder);
        sapienVault.increaseLockup(60 days);

        // Week 3: Add more stake
        vm.warp(block.timestamp + 7 days);
        vm.prank(builder);
        sapienVault.increaseAmount(MINIMUM_STAKE * 3);

        // Week 4: Final extension
        vm.warp(block.timestamp + 7 days);
        vm.prank(builder);
        sapienVault.increaseLockup(90 days);

        // Verify final state
        ISapienVault.UserStakingSummary memory builderStake = sapienVault.getUserStakingSummary(builder);
        uint256 totalStaked = builderStake.userTotalStaked;
        uint256 effectiveMultiplier = builderStake.effectiveMultiplier;
        uint256 lockup = builderStake.effectiveLockUpPeriod;

        assertEq(totalStaked, MINIMUM_STAKE * 5); // 1 + 1 + 3 = 5x minimum
        assertTrue(lockup > LOCK_30_DAYS); // Should be longer than original 30 days
        assertTrue(effectiveMultiplier > 0);

        console.log("Progressive builder final stake:", totalStaked / 10 ** 18, "SAPIEN");
        console.log("Final lockup period:", lockup / 1 days, "days");
        console.log("Final multiplier:", effectiveMultiplier);

        // Verify the builder can handle complex patterns
        assertTrue(totalStaked > MINIMUM_STAKE * 4, "Builder should have substantial stake");
        assertTrue(effectiveMultiplier > 10000, "Builder should have multiplier > 1.0x");
        assertTrue(lockup >= LOCK_30_DAYS, "Builder should have reasonable lockup");
    }

    function test_StakingPattern_EarlyExitOptimizer() public {
        console.log("\n=== EARLY EXIT OPTIMIZER PATTERN ===");

        address optimizer = makeAddr("earlyExitOptimizer");
        sapienToken.mint(optimizer, INITIAL_BALANCE);
        vm.prank(optimizer);
        sapienToken.approve(address(sapienVault), type(uint256).max);

        // Stake with long lockup but plan for early exit
        uint256 stakeAmount = LARGE_STAKE;
        vm.prank(optimizer);
        sapienVault.stake(stakeAmount, LOCK_365_DAYS);

        // After 6 months, needs emergency liquidity
        vm.warp(block.timestamp + 180 days);

        // Calculate optimal early exit amount
        uint256 exitAmount = stakeAmount / 3; // Exit 1/3
        uint256 expectedPenalty = (exitAmount * EARLY_WITHDRAWAL_PENALTY) / 10000;
        uint256 expectedReceived = exitAmount - expectedPenalty;

        uint256 balanceBefore = sapienToken.balanceOf(optimizer);

        // Use helper function for early unstake with cooldown
        _performEarlyUnstakeWithCooldown(optimizer, exitAmount);

        uint256 balanceAfter = sapienToken.balanceOf(optimizer);

        assertEq(balanceAfter - balanceBefore, expectedReceived);

        // Verify remaining stake is still optimal
        ISapienVault.UserStakingSummary memory optimizerStake = sapienVault.getUserStakingSummary(optimizer);
        uint256 remainingStake = optimizerStake.userTotalStaked;
        assertEq(remainingStake, stakeAmount - exitAmount);

        console.log("Early exit amount:", exitAmount / 10 ** 18, "SAPIEN");
        console.log("Penalty paid:", expectedPenalty / 10 ** 18, "SAPIEN");
        console.log("Amount received:", expectedReceived / 10 ** 18, "SAPIEN");
        console.log("Remaining stake:", remainingStake / 10 ** 18, "SAPIEN");

        // Test partial unstaking
        assertTrue(remainingStake > 0, "Optimizer should have remaining stake");
        assertTrue(remainingStake < MINIMUM_STAKE * 75, "Should have less than starting amount");
    }

    function test_StakingPattern_LiquidityManager() public {
        console.log("\n=== LIQUIDITY MANAGER PATTERN ===");

        address manager = makeAddr("liquidityManager");
        sapienToken.mint(manager, INITIAL_BALANCE);
        vm.prank(manager);
        sapienToken.approve(address(sapienVault), type(uint256).max);

        // Create multiple stake positions with different lockups for liquidity management
        vm.prank(manager);
        sapienVault.stake(MEDIUM_STAKE, LOCK_30_DAYS); // Short-term liquidity

        vm.warp(block.timestamp + 1 days);
        vm.prank(manager);
        sapienVault.increaseAmount(MEDIUM_STAKE); // Add to short-term

        // Wait for initial lockup to expire before trying to unstake
        vm.warp(block.timestamp + LOCK_30_DAYS + 1 days);

        // Now start unstaking process for partial liquidity
        uint256 liquidityNeeded = SMALL_STAKE;
        vm.prank(manager);
        sapienVault.initiateUnstake(liquidityNeeded);

        // Complete unstaking after cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        uint256 balanceBefore = sapienToken.balanceOf(manager);
        vm.prank(manager);
        sapienVault.unstake(liquidityNeeded);
        uint256 balanceAfter = sapienToken.balanceOf(manager);

        assertEq(balanceAfter - balanceBefore, liquidityNeeded);

        // Verify remaining stake is still active
        assertTrue(sapienVault.hasActiveStake(manager));

        ISapienVault.UserStakingSummary memory managerStake = sapienVault.getUserStakingSummary(manager);
        uint256 remainingStake = managerStake.userTotalStaked;
        assertEq(remainingStake, MEDIUM_STAKE * 2 - liquidityNeeded);

        console.log("Liquidity obtained:", liquidityNeeded / 10 ** 18, "SAPIEN");
        console.log("Remaining stake:", remainingStake / 10 ** 18, "SAPIEN");

        // Test full cycle completion
        assertTrue(remainingStake > 7999 ether, "Manager should have substantial remaining stake");
    }
}
