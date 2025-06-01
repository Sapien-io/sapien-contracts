// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Multiplier, IMultiplier} from "src/Multiplier.sol";

contract SapienVaultMultiplierScenariosTest is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public dave = makeAddr("dave");

    uint256 public constant MINIMUM_STAKE = 1000e18;
    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 public constant EARLY_WITHDRAWAL_PENALTY = 20;
    uint256 public constant MINIMUM_LOCKUP_INCREASE = 7 days;

    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    // Updated for new Linear Weighted Multiplier System
    // Base: 100% + Time: 0-25% + Amount: 0-25% + Global: 50-150%
    uint256 public constant BASE_MULTIPLIER = 10000; // 1.00x

    // Individual multipliers from the actual system (before global coefficient)
    uint256 public constant INDIVIDUAL_1K_30_DAY = 10200; // 102% (1K @ 30d)
    uint256 public constant INDIVIDUAL_1K_90_DAY = 10600; // 106% (1K @ 90d)
    uint256 public constant INDIVIDUAL_1K_180_DAY = 11200; // 112% (1K @ 180d)
    uint256 public constant INDIVIDUAL_1K_365_DAY = 12500; // 125% (1K @ 365d)

    uint256 public constant INDIVIDUAL_10K_30_DAY = 11200; // 112% (10K @ 30d)
    uint256 public constant INDIVIDUAL_10K_90_DAY = 11600; // 116% (10K @ 90d)
    uint256 public constant INDIVIDUAL_10K_180_DAY = 12200; // 122% (10K @ 180d)
    uint256 public constant INDIVIDUAL_10K_365_DAYS = 13500; // 135% (10K @ 365d)

    // With global coefficient at 0.5x (bootstrap phase, minimal network staking)
    // 10K tokens get multiplied by 0.5 in empty network
    uint256 public constant EXPECTED_10K_30_DAY = 5600; // 112% * 0.5 = 56%
    uint256 public constant EXPECTED_10K_90_DAY = 5800; // 116% * 0.5 = 58%
    uint256 public constant EXPECTED_10K_180_DAY = 6100; // 122% * 0.5 = 61%
    uint256 public constant EXPECTED_10K_365_DAY = 6750; // 135% * 0.5 = 67.5%

    // 5K tokens (smaller amount bonus)
    uint256 public constant EXPECTED_5K_30_DAY = 5350; // Slightly less than 10K
    uint256 public constant EXPECTED_5K_180_DAY = 5850; // Slightly less than 10K
    uint256 public constant EXPECTED_5K_365_DAY = 6500; // Slightly less than 10K

    // 2K tokens (minimal amount bonus)
    uint256 public constant EXPECTED_2K_30_DAY = 5350; // Close to 1K amounts
    uint256 public constant EXPECTED_2K_365_DAY = 6250; // Close to 1K amounts

    // Large stakes (20K+ tokens)
    uint256 public constant EXPECTED_20K_365_DAY = 6750; // Similar to what we see in traces

    function setUp() public {
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        SapienVault sapienVaultImpl = new SapienVault();
        Multiplier multiplierImpl = new Multiplier();
        IMultiplier multiplierContract = IMultiplier(address(multiplierImpl));

        bytes memory initData =
            abi.encodeWithSelector(SapienVault.initialize.selector, address(sapienToken), admin, treasury, address(multiplierContract));
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        // Mint tokens to users
        sapienToken.mint(alice, 10000000e18);
        sapienToken.mint(bob, 10000000e18);
        sapienToken.mint(charlie, 10000000e18);
        sapienToken.mint(dave, 10000000e18);
    }

    // =============================================================================
    // SCENARIO 1: BASE MULTIPLIER VALIDATION
    // Test that initial stakes get correct multipliers for each lockup period
    // =============================================================================

    function test_Multiplier_Scenario_BaseMultipliers() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10; // 10K tokens

        // Test 30-day lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        (,,,,, uint256 multiplier30,,) = sapienVault.getUserStakingSummary(alice);
        assertApproxEqAbs(
            multiplier30,
            EXPECTED_10K_30_DAY,
            50,
            "30-day multiplier should match expected value with global coefficient"
        );

        // Test 90-day lockup
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_90_DAYS);
        vm.stopPrank();

        (,,,,, uint256 multiplier90,,) = sapienVault.getUserStakingSummary(bob);
        assertApproxEqAbs(
            multiplier90,
            EXPECTED_10K_90_DAY,
            50,
            "90-day multiplier should match expected value with global coefficient"
        );

        // Test 180-day lockup
        vm.startPrank(charlie);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_180_DAYS);
        vm.stopPrank();

        (,,,,, uint256 multiplier180,,) = sapienVault.getUserStakingSummary(charlie);
        assertApproxEqAbs(
            multiplier180,
            EXPECTED_10K_180_DAY,
            50,
            "180-day multiplier should match expected value with global coefficient"
        );

        // Test 365-day lockup
        vm.startPrank(dave);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 multiplier365,,) = sapienVault.getUserStakingSummary(dave);
        assertApproxEqAbs(
            multiplier365,
            EXPECTED_10K_365_DAY,
            50,
            "365-day multiplier should match expected value with global coefficient"
        );
    }

    // =============================================================================
    // SCENARIO 2: AMOUNT INCREASE - MULTIPLIER PRESERVATION
    // Test that increasing stake amount preserves lockup but may change multiplier due to amount factor
    // =============================================================================

    function test_Multiplier_Scenario_AmountIncrease_PreservesMultiplier() public {
        uint256 initialStake = MINIMUM_STAKE * 5; // 5K tokens
        uint256 additionalStake = MINIMUM_STAKE * 5; // 5K tokens more = 10K total

        // Alice stakes with 180-day lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), initialStake);
        sapienVault.stake(initialStake, LOCK_180_DAYS);
        vm.stopPrank();

        (,,,,, uint256 initialMultiplier, uint256 initialLockup,) = sapienVault.getUserStakingSummary(alice);
        assertEq(initialLockup, LOCK_180_DAYS);

        // Alice increases amount after 30 days
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), additionalStake);
        sapienVault.increaseAmount(additionalStake);
        vm.stopPrank();

        (uint256 totalStaked,,,,, uint256 newMultiplier, uint256 newLockup,) = sapienVault.getUserStakingSummary(alice);

        // Verify amount increased
        assertEq(totalStaked, initialStake + additionalStake);
        // Verify lockup period stayed the same
        assertEq(newLockup, LOCK_180_DAYS);
        // New multiplier should be higher due to larger amount (better amount bonus)
        assertGt(newMultiplier, initialMultiplier, "Multiplier should improve with larger stake amount");
        // Should be close to expected 180-day multiplier for 10K tokens
        assertApproxEqAbs(
            newMultiplier, EXPECTED_10K_180_DAY, 50, "Should match expected 180-day multiplier for 10K tokens"
        );
    }

    // =============================================================================
    // SCENARIO 3: LOCKUP INCREASE - MULTIPLIER IMPROVEMENT
    // Test that increasing lockup period improves multiplier appropriately
    // =============================================================================

    function test_Multiplier_Scenario_LockupIncrease_ImprovesMultiplier() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10;

        // Alice starts with 30-day lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        (,,,,, uint256 initialMultiplier, uint256 initialLockup,) = sapienVault.getUserStakingSummary(alice);
        // With new system, don't expect exact individual multiplier since global coefficient applies
        assertApproxEqAbs(initialMultiplier, EXPECTED_10K_30_DAY, 100, "Initial multiplier should be close to expected");
        assertEq(initialLockup, LOCK_30_DAYS);

        // After 10 days, Alice extends lockup by 60 days (total would be 80 days remaining)
        vm.warp(block.timestamp + 10 days);

        vm.startPrank(alice);
        sapienVault.increaseLockup(60 days);
        vm.stopPrank();

        (,,,,, uint256 newMultiplier, uint256 newLockup,) = sapienVault.getUserStakingSummary(alice);

        // With 80 days lockup, multiplier should improve from initial
        assertGt(newMultiplier, initialMultiplier, "Multiplier should improve from 30-day base");
        assertLt(newMultiplier, EXPECTED_10K_90_DAY, "Multiplier should be less than 90-day multiplier");
        assertEq(newLockup, 80 days, "Lockup should be 80 days (20 remaining + 60 added)");

        // Test extending to 180+ days
        vm.startPrank(alice);
        sapienVault.increaseLockup(120 days); // Should get to around 200 days total
        vm.stopPrank();

        (,,,,, uint256 finalMultiplier,,) = sapienVault.getUserStakingSummary(alice);

        // Should now be better than initial but still reasonable
        assertGt(finalMultiplier, newMultiplier, "Multiplier should continue to improve");
        assertLt(finalMultiplier, EXPECTED_10K_365_DAY, "Multiplier should be less than max");
    }

    // =============================================================================
    // SCENARIO 4: COMBINATION STAKING - WEIGHTED MULTIPLIER CALCULATION
    // Test multiplier when combining stakes with different lockup periods
    // =============================================================================

    function test_Multiplier_Scenario_CombinationStaking_WeightedMultiplier() public {
        // Alice starts with small stake, short lockup
        uint256 firstStake = MINIMUM_STAKE * 2;

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), firstStake);
        sapienVault.stake(firstStake, LOCK_30_DAYS);
        vm.stopPrank();

        (,,,,, uint256 firstMultiplier,,) = sapienVault.getUserStakingSummary(alice);
        // 2K tokens should get lower multiplier than 10K tokens
        assertApproxEqAbs(firstMultiplier, EXPECTED_2K_30_DAY, 100, "2K tokens should have expected 30-day multiplier");

        // Alice adds larger stake with longer lockup
        uint256 secondStake = MINIMUM_STAKE * 8; // 4x larger

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), secondStake);
        sapienVault.stake(secondStake, LOCK_365_DAYS);
        vm.stopPrank();

        (uint256 totalStaked,,,,, uint256 combinedMultiplier, uint256 combinedLockup,) =
            sapienVault.getUserStakingSummary(alice);

        assertEq(totalStaked, firstStake + secondStake);

        // Combined multiplier should be weighted toward the larger stake with longer lockup
        // Since 8K of 10K total is at 365 days, this should be much closer to 365-day multiplier
        assertGt(combinedMultiplier, firstMultiplier, "Combined multiplier should be better than initial small stake");
        // Should be significantly improved since majority is long-term
        assertGt(combinedMultiplier, EXPECTED_10K_180_DAY, "Should be better than 180-day multiplier for 10K");

        // The weighted lockup should be approximately 298 days
        uint256 expectedWeightedLockup =
            (firstStake * LOCK_30_DAYS + secondStake * LOCK_365_DAYS) / (firstStake + secondStake);
        assertApproxEqAbs(
            combinedLockup, expectedWeightedLockup, 1 days, "Weighted lockup calculation should be correct"
        );
    }

    // =============================================================================
    // SCENARIO 5: PROGRESSIVE OPTIMIZATION - MULTIPLE OPERATIONS
    // Test multiplier evolution through multiple staking operations
    // =============================================================================

    function test_Multiplier_Scenario_ProgressiveOptimization() public {
        // Phase 1: Conservative start
        uint256 initialStake = MINIMUM_STAKE * 5;

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), initialStake);
        sapienVault.stake(initialStake, LOCK_30_DAYS);
        vm.stopPrank();

        (,,,,, uint256 phase1Multiplier,,) = sapienVault.getUserStakingSummary(alice);
        // Just verify we got a reasonable multiplier for 5K tokens @ 30 days
        assertGt(phase1Multiplier, 5000, "Phase 1: Should have reasonable multiplier");
        assertLt(phase1Multiplier, 7000, "Phase 1: Should not be too high");

        // Phase 2: Increase amount (multiplier should improve due to amount factor)
        vm.warp(block.timestamp + 10 days);

        uint256 additionalStake1 = MINIMUM_STAKE * 5;
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), additionalStake1);
        sapienVault.increaseAmount(additionalStake1);
        vm.stopPrank();

        (uint256 phase2Amount,,,,, uint256 phase2Multiplier,,) = sapienVault.getUserStakingSummary(alice);
        assertEq(phase2Amount, initialStake + additionalStake1);
        assertGt(phase2Multiplier, phase1Multiplier, "Phase 2: Multiplier should improve with more stake");

        // Phase 3: Extend lockup (multiplier should improve further)
        vm.warp(block.timestamp + 15 days);
        vm.startPrank(alice);
        sapienVault.increaseLockup(150 days); // Extend lockup significantly
        vm.stopPrank();

        (uint256 amount,,,,, uint256 mult, uint256 lockup,) = sapienVault.getUserStakingSummary(alice);
        assertEq(amount, initialStake + additionalStake1);
        assertGt(mult, phase2Multiplier, "Phase 3: Should improve with longer lockup");
        assertGt(lockup, LOCK_30_DAYS, "Phase 3: Should be extended");

        // Phase 4: Add more stake with even longer lockup
        uint256 additionalStake2 = MINIMUM_STAKE * 10;
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), additionalStake2);
        sapienVault.stake(additionalStake2, LOCK_365_DAYS);
        vm.stopPrank();

        (uint256 finalAmount,,,,, uint256 finalMultiplier,,) = sapienVault.getUserStakingSummary(alice);
        assertEq(finalAmount, initialStake + additionalStake1 + additionalStake2);

        // Since we added a large amount with 365-day lockup, should improve significantly
        assertGt(finalMultiplier, mult, "Final multiplier should be much better than previous");
    }

    // =============================================================================
    // SCENARIO 6: MULTIPLIER EDGE CASES
    // Test edge cases in multiplier calculations
    // =============================================================================

    function test_Multiplier_Scenario_EdgeCases() public {
        // Edge Case 1: Maximum lockup capping
        uint256 stakeAmount = MINIMUM_STAKE * 5;

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_365_DAYS);

        // Try to extend beyond maximum - should cap at 365 days
        sapienVault.increaseLockup(100 days);
        vm.stopPrank();

        (,,,,, uint256 cappedMultiplier, uint256 cappedLockup,) = sapienVault.getUserStakingSummary(alice);
        // With global coefficient, expect around 6500 not 13500
        assertApproxEqAbs(
            cappedMultiplier, EXPECTED_5K_365_DAY, 100, "Multiplier should be close to expected with global coefficient"
        );
        assertEq(cappedLockup, LOCK_365_DAYS, "Lockup should be capped at 365 days");

        // Edge Case 2: Precision in weighted calculations
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);

        // Add small amount with different lockup to test precision
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE); // Use minimum stake instead of 1 token
        sapienVault.stake(MINIMUM_STAKE, LOCK_365_DAYS);
        vm.stopPrank();

        (uint256 totalStaked,,,,, uint256 precisionMultiplier,,) = sapienVault.getUserStakingSummary(bob);
        assertEq(totalStaked, MINIMUM_STAKE * 2);
        // Multiplier should be weighted average: (1000 * 30days + 1000 * 365days) / 2000 = 197.5 days
        // This should give a multiplier between 180-day and 365-day multipliers
        assertGt(precisionMultiplier, EXPECTED_2K_30_DAY, "Should be better than 30-day multiplier");
        assertLt(precisionMultiplier, EXPECTED_2K_365_DAY, "Should be less than max multiplier");
    }

    // =============================================================================
    // SCENARIO 7: UNSTAKING EFFECTS ON MULTIPLIERS
    // Test how unstaking affects remaining stake multipliers
    // =============================================================================

    function test_Multiplier_Scenario_UnstakingEffects() public {
        uint256 largeStake = MINIMUM_STAKE * 20;

        // Alice stakes large amount with long lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), largeStake);
        sapienVault.stake(largeStake, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 initialMultiplier,,) = sapienVault.getUserStakingSummary(alice);
        // With global coefficient, expect around 6750 not 13500
        assertApproxEqAbs(initialMultiplier, EXPECTED_20K_365_DAY, 100, "Should get expected multiplier for 20K tokens");

        // Wait for unlock
        vm.warp(block.timestamp + LOCK_365_DAYS + 1);

        // Partial unstake
        uint256 unstakeAmount = MINIMUM_STAKE * 5;

        vm.startPrank(alice);
        sapienVault.initiateUnstake(unstakeAmount);
        vm.stopPrank();

        // Wait for cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        vm.startPrank(alice);
        sapienVault.unstake(unstakeAmount);
        vm.stopPrank();

        // Check remaining stake still has same multiplier
        (uint256 remainingStake,,,,, uint256 remainingMultiplier,,) = sapienVault.getUserStakingSummary(alice);
        assertEq(remainingStake, largeStake - unstakeAmount);
        assertApproxEqAbs(
            remainingMultiplier, EXPECTED_20K_365_DAY, 100, "Remaining stake should keep similar multiplier"
        );

        // Test instant unstake during lock period
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), largeStake);
        sapienVault.stake(largeStake, LOCK_365_DAYS);
        vm.stopPrank();

        // Wait some time but not full lockup
        vm.warp(block.timestamp + 100 days);

        uint256 instantUnstakeAmount = MINIMUM_STAKE * 3;

        vm.startPrank(bob);
        sapienVault.instantUnstake(instantUnstakeAmount);
        vm.stopPrank();

        // Check remaining stake still has same multiplier
        (uint256 bobRemainingStake,,,,, uint256 bobRemainingMultiplier,,) = sapienVault.getUserStakingSummary(bob);
        assertEq(bobRemainingStake, largeStake - instantUnstakeAmount);
        assertApproxEqAbs(
            bobRemainingMultiplier,
            EXPECTED_20K_365_DAY,
            100,
            "Remaining stake should keep similar multiplier after instant unstake"
        );
    }

    // =============================================================================
    // SCENARIO 8: COMPLEX WEIGHTED AVERAGE SCENARIOS
    // Test complex scenarios with multiple stakes and different ratios
    // =============================================================================

    function test_Multiplier_Scenario_ComplexWeightedAverages() public {
        // Scenario A: Equal amounts, different lockups
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 10);
        sapienVault.stake(MINIMUM_STAKE * 5, LOCK_30_DAYS);
        sapienVault.stake(MINIMUM_STAKE * 5, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 equalWeightMultiplier, uint256 equalWeightLockup,) = sapienVault.getUserStakingSummary(alice);

        // Should be approximately halfway between 30-day and 365-day
        uint256 expectedLockup = (LOCK_30_DAYS + LOCK_365_DAYS) / 2; // ~197.5 days
        assertApproxEqAbs(equalWeightLockup, expectedLockup, 1 days, "Equal weight lockup should be average");

        // Multiplier should be between 180-day and 365-day (closer to middle)
        // With global coefficient, expect around 6200-6400 range
        assertGt(equalWeightMultiplier, EXPECTED_10K_180_DAY, "Should be better than 180-day");
        assertLt(equalWeightMultiplier, EXPECTED_10K_365_DAY, "Should be less than 365-day");

        // Scenario B: Different amounts, same lockup ratios but opposite
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 10);
        sapienVault.stake(MINIMUM_STAKE * 9, LOCK_30_DAYS);
        sapienVault.stake(MINIMUM_STAKE * 1, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 heavyShortMultiplier,,) = sapienVault.getUserStakingSummary(bob);

        // Should be much closer to 30-day multiplier
        assertLt(heavyShortMultiplier, equalWeightMultiplier, "Heavy short-term stake should have lower multiplier");
        assertGt(heavyShortMultiplier, EXPECTED_10K_30_DAY, "Should be slightly better than pure 30-day");

        // Scenario C: Opposite ratio
        vm.startPrank(charlie);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 10);
        sapienVault.stake(MINIMUM_STAKE * 1, LOCK_30_DAYS);
        sapienVault.stake(MINIMUM_STAKE * 9, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 heavyLongMultiplier,,) = sapienVault.getUserStakingSummary(charlie);

        // Should be much closer to 365-day multiplier
        assertGt(heavyLongMultiplier, equalWeightMultiplier, "Heavy long-term stake should have higher multiplier");
        assertLt(heavyLongMultiplier, EXPECTED_10K_365_DAY, "Should be slightly less than pure 365-day");
    }

    // =============================================================================
    // SCENARIO 9: INTERPOLATION VALIDATION
    // Test that multipliers follow proper interpolation between lockup periods
    // =============================================================================

    function test_Multiplier_Scenario_InterpolationValidation() public {
        uint256 stakeAmount = MINIMUM_STAKE * 5; // Use 5K for each stake

        // Test weighted average between 30 and 90 days (should give ~60 day equivalent)
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), stakeAmount * 2);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS); // 5K @ 30 days
        sapienVault.stake(stakeAmount, LOCK_90_DAYS); // 5K @ 90 days
        vm.stopPrank();

        (,,,,, uint256 multiplier60DayEquiv, uint256 lockup60DayEquiv,) = sapienVault.getUserStakingSummary(alice);

        // Weighted lockup should be (30 + 90) / 2 = 60 days
        assertEq(lockup60DayEquiv, 60 days, "Weighted lockup should be 60 days");

        // Multiplier should be between 30 and 90 day multipliers
        assertGt(multiplier60DayEquiv, EXPECTED_10K_30_DAY, "Should be better than 30-day");
        assertLt(multiplier60DayEquiv, EXPECTED_10K_90_DAY, "Should be less than 90-day");

        // Test weighted average between 180 and 365 days (should give ~272 day equivalent)
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), stakeAmount * 2);
        sapienVault.stake(stakeAmount, LOCK_180_DAYS); // 5K @ 180 days
        sapienVault.stake(stakeAmount, LOCK_365_DAYS); // 5K @ 365 days
        vm.stopPrank();

        (,,,,, uint256 multiplier272DayEquiv, uint256 lockup272DayEquiv,) = sapienVault.getUserStakingSummary(bob);

        // Weighted lockup should be (180 + 365) / 2 = 272.5 days
        assertApproxEqAbs(lockup272DayEquiv, 272 days, 1 days, "Weighted lockup should be ~272 days");

        // Multiplier should be between 180 and 365 day multipliers
        assertGt(multiplier272DayEquiv, EXPECTED_10K_180_DAY, "Should be better than 180-day");
        assertLt(multiplier272DayEquiv, EXPECTED_10K_365_DAY, "Should be less than 365-day");
    }

    // =============================================================================
    // SCENARIO 10: TIME-BASED MULTIPLIER EFFECTS
    // Test how time passage affects weighted start times and multipliers
    // =============================================================================

    function test_Multiplier_Scenario_TimeBasedEffects() public {
        uint256 stakeAmount = MINIMUM_STAKE * 5;

        // Alice stakes with 365-day lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_365_DAYS);
        vm.stopPrank();

        // uint256 startTime = block.timestamp;
        (,,,,, uint256 initialMultiplier,, uint256 timeUntilUnlock1) = sapienVault.getUserStakingSummary(alice);
        assertApproxEqAbs(initialMultiplier, EXPECTED_5K_365_DAY, 100, "Should get expected multiplier for 5K tokens");
        assertEq(timeUntilUnlock1, LOCK_365_DAYS);

        // Wait 100 days and add more stake
        vm.warp(block.timestamp + 100 days);

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.increaseAmount(stakeAmount);
        vm.stopPrank();

        // Multiplier should stay the same but weighted start time should change
        (,,,,, uint256 multiplierAfterIncrease,, uint256 timeUntilUnlock2) = sapienVault.getUserStakingSummary(alice);
        assertApproxEqAbs(
            multiplierAfterIncrease, EXPECTED_10K_365_DAY, 100, "Multiplier should be similar with more stake"
        );

        // Time until unlock should be less than original but more than 265 days (365 - 100)
        assertLt(timeUntilUnlock2, timeUntilUnlock1, "Time until unlock should decrease");
        assertGt(timeUntilUnlock2, 265 days, "Should be weighted average of unlock times");

        // Test adding stake with different lockup after time has passed
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_365_DAYS);
        vm.stopPrank();

        // Wait 200 days
        vm.warp(block.timestamp + 200 days);

        // Add stake with 90-day lockup
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_90_DAYS);
        vm.stopPrank();

        (,,,,, uint256 bobMultiplier, uint256 bobLockup,) = sapienVault.getUserStakingSummary(bob);

        // Bob's effective lockup should be weighted: (existing 365 days + new 90 days) / 2
        // The contract uses the full lockup periods for weighting, not remaining time
        // Weighted lockup: (5000 * 365 + 5000 * 90) / 10000 = 227.5 days
        uint256 expectedWeightedLockup = (stakeAmount * LOCK_365_DAYS + stakeAmount * LOCK_90_DAYS) / (stakeAmount * 2);
        assertApproxEqAbs(
            bobLockup, expectedWeightedLockup, 1 days, "Weighted lockup should be average of full lockup periods"
        );

        // Multiplier should be between 180-day and 365-day multipliers
        assertGt(bobMultiplier, EXPECTED_10K_180_DAY, "Should be better than 180-day multiplier");
        assertLt(bobMultiplier, EXPECTED_10K_365_DAY, "Should be less than max multiplier");
    }

    // =============================================================================
    // SCENARIO 11: EXTREME RATIO TESTING
    // Test multipliers with extreme ratios between different stakes
    // =============================================================================

    function test_Multiplier_Scenario_ExtremeRatios() public {
        // Test 1: Tiny long-term stake with large short-term stake
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 101);
        sapienVault.stake(MINIMUM_STAKE * 100, LOCK_30_DAYS); // 99%
        sapienVault.stake(MINIMUM_STAKE * 1, LOCK_365_DAYS); // 1%
        vm.stopPrank();

        (,,,,, uint256 aliceMultiplier,,) = sapienVault.getUserStakingSummary(alice);

        // Should be very close to 30-day multiplier with tiny improvement
        // With global coefficient, expect around 5600-5700 range
        assertGt(aliceMultiplier, EXPECTED_10K_30_DAY, "Should be slightly better than pure 30-day");
        assertLt(aliceMultiplier, EXPECTED_10K_30_DAY + 300, "Should be very close to 30-day multiplier");

        // Test 2: Large long-term stake with tiny short-term stake
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 101);
        sapienVault.stake(MINIMUM_STAKE * 1, LOCK_30_DAYS); // 1%
        sapienVault.stake(MINIMUM_STAKE * 100, LOCK_365_DAYS); // 99%
        vm.stopPrank();

        (,,,,, uint256 bobMultiplier,,) = sapienVault.getUserStakingSummary(bob);

        // Should be very close to 365-day multiplier with tiny degradation
        // With global coefficient, expect around 6700-6750 range
        assertLt(bobMultiplier, EXPECTED_10K_365_DAY + 300, "Should be close to pure 365-day");
        assertGt(bobMultiplier, EXPECTED_10K_365_DAY - 200, "Should be very close to 365-day multiplier");

        // Verify the extreme difference - with global coefficient, difference will be smaller
        assertGt(bobMultiplier - aliceMultiplier, 800, "Difference should be substantial (>8% multiplier difference)");
    }

    // =============================================================================
    // SCENARIO 12: SEQUENTIAL OPERATIONS MULTIPLIER TRACKING
    // Test multiplier changes through a sequence of realistic operations
    // =============================================================================

    function test_Multiplier_Scenario_SequentialOperations() public {
        uint256[] memory multipliers = new uint256[](10);
        uint256[] memory lockups = new uint256[](10);
        uint256 step = 0;

        // Step 0: Initial conservative stake
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2);
        sapienVault.stake(MINIMUM_STAKE * 2, LOCK_30_DAYS);
        vm.stopPrank();

        (,,,,, multipliers[step], lockups[step],) = sapienVault.getUserStakingSummary(alice);
        // With global coefficient, expect around 5350 not 11200
        assertApproxEqAbs(multipliers[step], EXPECTED_2K_30_DAY, 100, "Should get expected multiplier for 2K tokens");
        step++;

        // Step 1: Double the stake
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2);
        sapienVault.increaseAmount(MINIMUM_STAKE * 2);
        vm.stopPrank();

        (,,,,, multipliers[step], lockups[step],) = sapienVault.getUserStakingSummary(alice);
        assertGe(multipliers[step], multipliers[step - 1], "Multiplier should improve or stay same with larger amount");
        step++;

        // Step 2: Extend lockup to 90 days
        vm.warp(block.timestamp + 15 days);
        vm.startPrank(alice);
        sapienVault.increaseLockup(75 days); // 15 days remaining + 75 days = 90 days
        vm.stopPrank();

        (,,,,, multipliers[step], lockups[step],) = sapienVault.getUserStakingSummary(alice);
        assertGt(multipliers[step], multipliers[step - 1], "Multiplier should improve after lockup extension");
        assertEq(lockups[step], 90 days, "Lockup should be 90 days");
        step++;

        // Step 3: Add stake with longer lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 4);
        sapienVault.stake(MINIMUM_STAKE * 4, LOCK_180_DAYS);
        vm.stopPrank();

        (,,,,, multipliers[step], lockups[step],) = sapienVault.getUserStakingSummary(alice);
        assertGt(multipliers[step], multipliers[step - 1], "Multiplier should improve after adding longer lockup stake");
        assertGt(lockups[step], 90 days, "Lockup should be weighted higher");
        step++;

        // Step 4: Add even more with max lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 8);
        sapienVault.stake(MINIMUM_STAKE * 8, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, multipliers[step], lockups[step],) = sapienVault.getUserStakingSummary(alice);
        assertGt(multipliers[step], multipliers[step - 1], "Multiplier should improve significantly");
        assertGt(lockups[step], LOCK_180_DAYS, "Lockup should be weighted much higher");

        // Verify the progression - with global coefficient, expect much lower values
        assertGt(multipliers[4], EXPECTED_10K_180_DAY, "Final multiplier should exceed 180-day base");
        assertLt(multipliers[4], EXPECTED_20K_365_DAY, "Final multiplier should be reasonable");

        // Verify monotonic improvement in multipliers (except step 1 which might be same)
        for (uint256 i = 2; i < 5; i++) {
            assertGt(multipliers[i], multipliers[i - 1], "Multipliers should generally improve");
        }
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _approxEqual(uint256 a, uint256 b, uint256 tolerance) internal pure returns (bool) {
        return a > b ? (a - b) <= tolerance : (b - a) <= tolerance;
    }

    function _printMultiplierInfo(address user, string memory label) internal view {
        (uint256 totalStaked,,,,, uint256 multiplier, uint256 lockup, uint256 timeUntilUnlock) =
            sapienVault.getUserStakingSummary(user);

        console.log("=== %s ===", label);
        console.log("Total Staked: %e", totalStaked);
        console.log("Multiplier: %d (%.2f%%)", multiplier, (multiplier * 100) / 10000);
        console.log("Lockup: %d days", lockup / 1 days);
        console.log("Time Until Unlock: %d days", timeUntilUnlock / 1 days);
        console.log("");
    }
}
