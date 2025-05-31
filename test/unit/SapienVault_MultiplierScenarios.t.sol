// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

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

    // Multiplier constants (in basis points)
    uint256 public constant BASE_MULTIPLIER = 10000; // 1.00x
    uint256 public constant MIN_MULTIPLIER = 10500;  // 1.05x at 30 days
    uint256 public constant MULTIPLIER_90_DAYS = 11000;  // 1.10x at 90 days
    uint256 public constant MULTIPLIER_180_DAYS = 12500; // 1.25x at 180 days
    uint256 public constant MAX_MULTIPLIER = 15000;      // 1.50x at 365 days

    function setUp() public {
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData =
            abi.encodeWithSelector(SapienVault.initialize.selector, address(sapienToken), admin, treasury);
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
        uint256 stakeAmount = MINIMUM_STAKE * 10;

        // Test 30-day lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        (,,,,, uint256 multiplier30,, ) = sapienVault.getUserStakingSummary(alice);
        assertEq(multiplier30, MIN_MULTIPLIER, "30-day multiplier should be 1.05x");

        // Test 90-day lockup
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_90_DAYS);
        vm.stopPrank();

        (,,,,, uint256 multiplier90,, ) = sapienVault.getUserStakingSummary(bob);
        assertEq(multiplier90, MULTIPLIER_90_DAYS, "90-day multiplier should be 1.10x");

        // Test 180-day lockup
        vm.startPrank(charlie);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_180_DAYS);
        vm.stopPrank();

        (,,,,, uint256 multiplier180,, ) = sapienVault.getUserStakingSummary(charlie);
        assertEq(multiplier180, MULTIPLIER_180_DAYS, "180-day multiplier should be 1.25x");

        // Test 365-day lockup
        vm.startPrank(dave);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 multiplier365,, ) = sapienVault.getUserStakingSummary(dave);
        assertEq(multiplier365, MAX_MULTIPLIER, "365-day multiplier should be 1.50x");
    }

    // =============================================================================
    // SCENARIO 2: AMOUNT INCREASE - MULTIPLIER PRESERVATION
    // Test that increasing stake amount preserves multiplier when lockup doesn't change
    // =============================================================================

    function test_Multiplier_Scenario_AmountIncrease_PreservesMultiplier() public {
        uint256 initialStake = MINIMUM_STAKE * 5;
        uint256 additionalStake = MINIMUM_STAKE * 3;

        // Alice stakes with 180-day lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), initialStake);
        sapienVault.stake(initialStake, LOCK_180_DAYS);
        vm.stopPrank();

        (,,,,, uint256 initialMultiplier, uint256 initialLockup, ) = sapienVault.getUserStakingSummary(alice);
        assertEq(initialMultiplier, MULTIPLIER_180_DAYS);
        assertEq(initialLockup, LOCK_180_DAYS);

        // Alice increases amount after 30 days
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), additionalStake);
        sapienVault.increaseAmount(additionalStake);
        vm.stopPrank();

        (uint256 totalStaked,,,, , uint256 newMultiplier, uint256 newLockup, ) = sapienVault.getUserStakingSummary(alice);
        
        // Verify amount increased
        assertEq(totalStaked, initialStake + additionalStake);
        // Verify multiplier stayed the same (lockup period didn't change)
        assertEq(newMultiplier, MULTIPLIER_180_DAYS);
        // Verify lockup period stayed the same
        assertEq(newLockup, LOCK_180_DAYS);
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

        (,,,,, uint256 initialMultiplier, uint256 initialLockup, ) = sapienVault.getUserStakingSummary(alice);
        assertEq(initialMultiplier, MIN_MULTIPLIER);
        assertEq(initialLockup, LOCK_30_DAYS);

        // After 10 days, Alice extends lockup by 60 days (total would be 80 days remaining)
        vm.warp(block.timestamp + 10 days);

        vm.startPrank(alice);
        sapienVault.increaseLockup(60 days);
        vm.stopPrank();

        (,,,,, uint256 newMultiplier, uint256 newLockup, ) = sapienVault.getUserStakingSummary(alice);
        
        // With 80 days lockup, multiplier should be between 30-day and 90-day multipliers
        assertGt(newMultiplier, MIN_MULTIPLIER, "Multiplier should improve from 30-day base");
        assertLt(newMultiplier, MULTIPLIER_90_DAYS, "Multiplier should be less than 90-day multiplier");
        assertEq(newLockup, 80 days, "Lockup should be 80 days (20 remaining + 60 added)");

        // Test extending to 180+ days
        vm.startPrank(alice);
        sapienVault.increaseLockup(120 days); // Should get to around 200 days total
        vm.stopPrank();

        (,,,,, uint256 finalMultiplier,,) = sapienVault.getUserStakingSummary(alice);
        
        // Should now be between 180-day and 365-day multipliers
        assertGt(finalMultiplier, MULTIPLIER_180_DAYS, "Multiplier should be better than 180-day");
        assertLt(finalMultiplier, MAX_MULTIPLIER, "Multiplier should be less than max");
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

        (,,,,, uint256 firstMultiplier,, ) = sapienVault.getUserStakingSummary(alice);
        assertEq(firstMultiplier, MIN_MULTIPLIER);

        // Alice adds larger stake with longer lockup
        uint256 secondStake = MINIMUM_STAKE * 8; // 4x larger
        
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), secondStake);
        sapienVault.stake(secondStake, LOCK_365_DAYS);
        vm.stopPrank();

        (uint256 totalStaked,,,, , uint256 combinedMultiplier, uint256 combinedLockup, ) = sapienVault.getUserStakingSummary(alice);
        
        assertEq(totalStaked, firstStake + secondStake);
        
        // Combined multiplier should be weighted toward the larger stake with longer lockup
        // Calculation: (2000 * 30days + 8000 * 365days) / 10000 = (60000 + 2920000) / 10000 = 298 days
        // This should give a multiplier between 180-day and 365-day multipliers, closer to 365-day
        assertGt(combinedMultiplier, MULTIPLIER_180_DAYS, "Combined multiplier should be better than 180-day");
        assertLt(combinedMultiplier, MAX_MULTIPLIER, "Combined multiplier should be less than max");
        
        // The weighted lockup should be approximately 298 days
        uint256 expectedWeightedLockup = (firstStake * LOCK_30_DAYS + secondStake * LOCK_365_DAYS) / (firstStake + secondStake);
        assertApproxEqAbs(combinedLockup, expectedWeightedLockup, 1 days, "Weighted lockup calculation should be correct");
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

        (,,,,, uint256 phase1Multiplier,, ) = sapienVault.getUserStakingSummary(alice);
        assertEq(phase1Multiplier, MIN_MULTIPLIER, "Phase 1: Should have base 30-day multiplier");

        // Phase 2: Increase amount (multiplier should stay same)
        vm.warp(block.timestamp + 10 days);
        
        uint256 additionalStake1 = MINIMUM_STAKE * 5;
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), additionalStake1);
        sapienVault.increaseAmount(additionalStake1);
        vm.stopPrank();

        (uint256 phase2Amount,,,, , uint256 phase2Multiplier,, ) = sapienVault.getUserStakingSummary(alice);
        assertEq(phase2Amount, initialStake + additionalStake1);
        assertEq(phase2Multiplier, MIN_MULTIPLIER, "Phase 2: Multiplier should remain same after amount increase");

        // Phase 3: Extend lockup (multiplier should improve)
        vm.startPrank(alice);
        sapienVault.increaseLockup(120 days); // Extend significantly
        vm.stopPrank();

        uint256 phase3Mult;
        {
            (uint256 amount,,,, , uint256 mult, uint256 lockup, ) = sapienVault.getUserStakingSummary(alice);
            assertEq(amount, initialStake + additionalStake1);
            assertGt(mult, MIN_MULTIPLIER); // Better multiplier
            assertGt(lockup, LOCK_30_DAYS); // Should be extended
            
            phase3Mult = mult;
        }

        // Phase 4: Add more stake with even longer lockup
        uint256 additionalStake2 = MINIMUM_STAKE * 10;
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), additionalStake2);
        sapienVault.stake(additionalStake2, LOCK_365_DAYS);
        vm.stopPrank();

        (uint256 finalAmount,,,, , uint256 finalMultiplier, uint256 finalLockup, ) = sapienVault.getUserStakingSummary(alice);
        
        assertEq(finalAmount, initialStake + additionalStake1 + additionalStake2);
        assertGt(finalMultiplier, phase3Mult, "Phase 4: Final multiplier should be highest");
        assertGt(finalLockup, LOCK_30_DAYS, "Phase 4: Final lockup should be longest");
        
        // Since we added a large amount with 365-day lockup, the weighted average should be much higher
        assertGt(finalMultiplier, MULTIPLIER_180_DAYS, "Final multiplier should exceed 180-day multiplier");
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

        (,,,,, uint256 cappedMultiplier, uint256 cappedLockup, ) = sapienVault.getUserStakingSummary(alice);
        assertEq(cappedMultiplier, MAX_MULTIPLIER, "Multiplier should be capped at maximum");
        assertEq(cappedLockup, LOCK_365_DAYS, "Lockup should be capped at 365 days");

        // Edge Case 2: Precision in weighted calculations
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        
        // Add small amount with different lockup to test precision
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE); // Use minimum stake instead of 1 token
        sapienVault.stake(MINIMUM_STAKE, LOCK_365_DAYS);
        vm.stopPrank();

        (uint256 totalStaked,,,, , uint256 precisionMultiplier,, ) = sapienVault.getUserStakingSummary(bob);
        assertEq(totalStaked, MINIMUM_STAKE * 2);
        // Multiplier should be weighted average: (1000 * 30days + 1000 * 365days) / 2000 = 197.5 days
        // This should give a multiplier between 180-day and 365-day multipliers
        assertGt(precisionMultiplier, MULTIPLIER_180_DAYS, "Should be better than 180-day multiplier");
        assertLt(precisionMultiplier, MAX_MULTIPLIER, "Should be less than max multiplier");
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

        (,,,,, uint256 initialMultiplier,, ) = sapienVault.getUserStakingSummary(alice);
        assertEq(initialMultiplier, MAX_MULTIPLIER);

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
        (uint256 remainingStake,,,, , uint256 remainingMultiplier,, ) = sapienVault.getUserStakingSummary(alice);
        assertEq(remainingStake, largeStake - unstakeAmount);
        assertEq(remainingMultiplier, MAX_MULTIPLIER, "Remaining stake should keep same multiplier");

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
        (uint256 bobRemainingStake,,,, , uint256 bobRemainingMultiplier,, ) = sapienVault.getUserStakingSummary(bob);
        assertEq(bobRemainingStake, largeStake - instantUnstakeAmount);
        assertEq(bobRemainingMultiplier, MAX_MULTIPLIER, "Remaining stake should keep same multiplier after instant unstake");
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

        (,,,,, uint256 equalWeightMultiplier, uint256 equalWeightLockup, ) = sapienVault.getUserStakingSummary(alice);
        
        // Should be approximately halfway between 30-day and 365-day
        uint256 expectedLockup = (LOCK_30_DAYS + LOCK_365_DAYS) / 2; // ~197.5 days
        assertApproxEqAbs(equalWeightLockup, expectedLockup, 1 days, "Equal weight lockup should be average");
        
        // Multiplier should be between 180-day and 365-day (closer to middle)
        assertGt(equalWeightMultiplier, MULTIPLIER_180_DAYS);
        assertLt(equalWeightMultiplier, MAX_MULTIPLIER);

        // Scenario B: Different amounts, same lockup ratios but opposite
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 10);
        sapienVault.stake(MINIMUM_STAKE * 9, LOCK_30_DAYS);
        sapienVault.stake(MINIMUM_STAKE * 1, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 heavyShortMultiplier,, ) = sapienVault.getUserStakingSummary(bob);
        
        // Should be much closer to 30-day multiplier
        assertLt(heavyShortMultiplier, equalWeightMultiplier, "Heavy short-term stake should have lower multiplier");
        assertGt(heavyShortMultiplier, MIN_MULTIPLIER, "Should be slightly better than pure 30-day");

        // Scenario C: Opposite ratio
        vm.startPrank(charlie);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 10);
        sapienVault.stake(MINIMUM_STAKE * 1, LOCK_30_DAYS);
        sapienVault.stake(MINIMUM_STAKE * 9, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 heavyLongMultiplier,, ) = sapienVault.getUserStakingSummary(charlie);
        
        // Should be much closer to 365-day multiplier
        assertGt(heavyLongMultiplier, equalWeightMultiplier, "Heavy long-term stake should have higher multiplier");
        assertLt(heavyLongMultiplier, MAX_MULTIPLIER, "Should be slightly less than pure 365-day");
    }

    // =============================================================================
    // SCENARIO 9: INTERPOLATION VALIDATION
    // Test that multipliers follow proper interpolation between lockup periods
    // =============================================================================

    function test_Multiplier_Scenario_InterpolationValidation() public {
        // Test interpolation between 30 and 90 days
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        sapienVault.increaseLockup(30 days); // Should result in 60 days total
        vm.stopPrank();

        (,,,,, uint256 multiplier60Days, uint256 lockup60Days, ) = sapienVault.getUserStakingSummary(alice);
        assertEq(lockup60Days, 60 days, "Should have 60-day lockup");
        
        // 60 days should be halfway between 30-day (10500) and 90-day (11000) multipliers
        // Expected: 10500 + ((11000 - 10500) * (60-30) / (90-30)) = 10500 + (500 * 30 / 60) = 10500 + 250 = 10750
        uint256 expectedMultiplier = MIN_MULTIPLIER + ((MULTIPLIER_90_DAYS - MIN_MULTIPLIER) * (60 days - LOCK_30_DAYS) / (LOCK_90_DAYS - LOCK_30_DAYS));
        assertEq(multiplier60Days, expectedMultiplier, "60-day multiplier should be interpolated correctly");

        // Test interpolation between 180 and 365 days
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2);
        sapienVault.stake(MINIMUM_STAKE, LOCK_180_DAYS);
        sapienVault.increaseLockup(92 days); // Should result in 272 days total (180 + 92)
        vm.stopPrank();

        (,,,,, uint256 multiplier272Days, uint256 lockup272Days, ) = sapienVault.getUserStakingSummary(bob);
        assertEq(lockup272Days, 272 days, "Should have 272-day lockup");
        
        // 272 days should be interpolated between 180-day (12500) and 365-day (15000)
        uint256 expectedMultiplier272 = MULTIPLIER_180_DAYS + ((MAX_MULTIPLIER - MULTIPLIER_180_DAYS) * (272 days - LOCK_180_DAYS) / (LOCK_365_DAYS - LOCK_180_DAYS));
        assertEq(multiplier272Days, expectedMultiplier272, "272-day multiplier should be interpolated correctly");
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
        assertEq(initialMultiplier, MAX_MULTIPLIER);
        assertEq(timeUntilUnlock1, LOCK_365_DAYS);

        // Wait 100 days and add more stake
        vm.warp(block.timestamp + 100 days);
        
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.increaseAmount(stakeAmount);
        vm.stopPrank();

        // Multiplier should stay the same but weighted start time should change
        (,,,,, uint256 multiplierAfterIncrease,, uint256 timeUntilUnlock2) = sapienVault.getUserStakingSummary(alice);
        assertEq(multiplierAfterIncrease, MAX_MULTIPLIER, "Multiplier should remain the same");
        
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

        (,,,,, uint256 bobMultiplier, uint256 bobLockup, ) = sapienVault.getUserStakingSummary(bob);
        
        // Bob's effective lockup should be weighted: (existing 365 days + new 90 days) / 2
        // The contract uses the full lockup periods for weighting, not remaining time
        // Weighted lockup: (5000 * 365 + 5000 * 90) / 10000 = 227.5 days
        uint256 expectedWeightedLockup = (stakeAmount * LOCK_365_DAYS + stakeAmount * LOCK_90_DAYS) / (stakeAmount * 2);
        assertApproxEqAbs(bobLockup, expectedWeightedLockup, 1 days, "Weighted lockup should be average of full lockup periods");
        
        // Multiplier should be between 180-day and 365-day multipliers
        assertGt(bobMultiplier, MULTIPLIER_180_DAYS, "Should be better than 180-day multiplier");
        assertLt(bobMultiplier, MAX_MULTIPLIER, "Should be less than max multiplier");
    }

    // =============================================================================
    // SCENARIO 11: EXTREME RATIO TESTING
    // Test multipliers with extreme ratios between different stakes
    // =============================================================================

    function test_Multiplier_Scenario_ExtremeRatios() public {
        // Test 1: Tiny long-term stake with large short-term stake
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 101);
        sapienVault.stake(MINIMUM_STAKE * 100, LOCK_30_DAYS);  // 99%
        sapienVault.stake(MINIMUM_STAKE * 1, LOCK_365_DAYS);   // 1%
        vm.stopPrank();

        (,,,,, uint256 aliceMultiplier,, ) = sapienVault.getUserStakingSummary(alice);
        
        // Should be very close to 30-day multiplier with tiny improvement
        assertGt(aliceMultiplier, MIN_MULTIPLIER, "Should be slightly better than pure 30-day");
        assertLt(aliceMultiplier, MIN_MULTIPLIER + 100, "Should be very close to 30-day multiplier");

        // Test 2: Large long-term stake with tiny short-term stake
        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 101);
        sapienVault.stake(MINIMUM_STAKE * 1, LOCK_30_DAYS);    // 1%
        sapienVault.stake(MINIMUM_STAKE * 100, LOCK_365_DAYS); // 99%
        vm.stopPrank();

        (,,,,, uint256 bobMultiplier,, ) = sapienVault.getUserStakingSummary(bob);
        
        // Should be very close to 365-day multiplier with tiny degradation
        assertLt(bobMultiplier, MAX_MULTIPLIER, "Should be slightly less than pure 365-day");
        assertGt(bobMultiplier, MAX_MULTIPLIER - 100, "Should be very close to 365-day multiplier");

        // Verify the extreme difference
        assertGt(bobMultiplier - aliceMultiplier, 4000, "Difference should be substantial (>40% multiplier difference)");
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

        (,,,,, multipliers[step], lockups[step], ) = sapienVault.getUserStakingSummary(alice);
        assertEq(multipliers[step], MIN_MULTIPLIER);
        step++;

        // Step 1: Double the stake
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2);
        sapienVault.increaseAmount(MINIMUM_STAKE * 2);
        vm.stopPrank();

        (,,,,, multipliers[step], lockups[step], ) = sapienVault.getUserStakingSummary(alice);
        assertEq(multipliers[step], multipliers[step-1], "Multiplier should remain same after amount increase");
        step++;

        // Step 2: Extend lockup to 90 days
        vm.warp(block.timestamp + 15 days);
        vm.startPrank(alice);
        sapienVault.increaseLockup(75 days); // 15 days remaining + 75 days = 90 days
        vm.stopPrank();

        (,,,,, multipliers[step], lockups[step], ) = sapienVault.getUserStakingSummary(alice);
        assertGt(multipliers[step], multipliers[step-1], "Multiplier should improve after lockup extension");
        assertEq(lockups[step], 90 days);
        step++;

        // Step 3: Add stake with longer lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 4);
        sapienVault.stake(MINIMUM_STAKE * 4, LOCK_180_DAYS);
        vm.stopPrank();

        (,,,,, multipliers[step], lockups[step], ) = sapienVault.getUserStakingSummary(alice);
        assertGt(multipliers[step], multipliers[step-1], "Multiplier should improve after adding longer lockup stake");
        assertGt(lockups[step], 90 days, "Lockup should be weighted higher");
        step++;

        // Step 4: Add even more with max lockup
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 8);
        sapienVault.stake(MINIMUM_STAKE * 8, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, multipliers[step], lockups[step], ) = sapienVault.getUserStakingSummary(alice);
        assertGt(multipliers[step], multipliers[step-1], "Multiplier should improve significantly");
        assertGt(lockups[step], LOCK_180_DAYS, "Lockup should be weighted much higher");

        // Verify the progression
        assertGt(multipliers[4], MULTIPLIER_180_DAYS, "Final multiplier should exceed 180-day base");
        assertLt(multipliers[4], MAX_MULTIPLIER, "Final multiplier should be less than max");
        
        // Verify monotonic improvement in multipliers
        for (uint256 i = 1; i < 5; i++) {
            if (i == 1) continue; // Skip step 1 (amount increase, multiplier stays same)
            assertGt(multipliers[i], multipliers[i-1], "Multipliers should generally improve");
        }
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _approxEqual(uint256 a, uint256 b, uint256 tolerance) internal pure returns (bool) {
        return a > b ? (a - b) <= tolerance : (b - a) <= tolerance;
    }

    function _printMultiplierInfo(address user, string memory label) internal view {
        (uint256 totalStaked,,,, , uint256 multiplier, uint256 lockup, uint256 timeUntilUnlock) = 
            sapienVault.getUserStakingSummary(user);
        
        console.log("=== %s ===", label);
        console.log("Total Staked: %e", totalStaked);
        console.log("Multiplier: %d (%.2f%%)", multiplier, (multiplier * 100) / 10000);
        console.log("Lockup: %d days", lockup / 1 days);
        console.log("Time Until Unlock: %d days", timeUntilUnlock / 1 days);
        console.log("");
    }
} 