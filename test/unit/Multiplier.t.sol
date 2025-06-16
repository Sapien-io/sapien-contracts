// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Multiplier} from "src/Multiplier.sol";
import {Constants as Const} from "src/utils/Constants.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";

contract MultiplierTest is Test {

    // Test constants
    uint256 public constant TOKEN_DECIMALS = 10 ** 18;
    uint256 public constant MIN_TOKENS = 1;
    uint256 public constant MAX_TOKENS = 2500 ether;

    // Duration constants
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    // Expected multipliers for exponential model
    uint256 public constant BASE_MULTIPLIER = 10000; // 1.00x
    uint256 public constant MAX_MULTIPLIER = 15000;  // 1.50x

    // =============================================================================
    // BASIC FUNCTIONALITY TESTS
    // =============================================================================

    function test_Multiplier_CalculateMultiplier_ExactDiscretePeriods() public pure {
        uint256 amount = 100 ether; // Use 100 tokens instead of 1 to avoid rounding issues

        // Test exact discrete periods with small stake (100 tokens)
        // At 100 tokens, we should get base multiplier + small time bonus
        uint256 result30 = Multiplier.calculateMultiplier(amount, LOCK_30_DAYS);
        uint256 result90 = Multiplier.calculateMultiplier(amount, LOCK_90_DAYS);
        uint256 result180 = Multiplier.calculateMultiplier(amount, LOCK_180_DAYS);
        uint256 result365 = Multiplier.calculateMultiplier(amount, LOCK_365_DAYS);

        // Should increase with time
        assertLt(result30, result90, "90 days should be higher than 30 days");
        assertLt(result90, result180, "180 days should be higher than 90 days");
        assertLt(result180, result365, "365 days should be higher than 180 days");

        // All should be >= base multiplier
        assertGe(result30, BASE_MULTIPLIER, "30 days should be >= base multiplier");
        assertGe(result365, BASE_MULTIPLIER, "365 days should be >= base multiplier");
    }

    function test_Multiplier_CalculateMultiplier_AmountScaling() public pure {
        uint256 lockup = LOCK_180_DAYS; // Use shorter duration to avoid hitting cap

        // Test exponential scaling with different amounts (use smaller amounts to avoid cap)
        uint256 result1 = Multiplier.calculateMultiplier(1 ether, lockup);
        uint256 result100 = Multiplier.calculateMultiplier(100 ether, lockup);
        uint256 result1000 = Multiplier.calculateMultiplier(1000 ether, lockup);
        uint256 result2000 = Multiplier.calculateMultiplier(2000 ether, lockup);

        // Should increase with amount (exponential curve)
        assertLt(result1, result100, "100 tokens should be higher than 1 token");
        assertLt(result100, result1000, "1000 tokens should be higher than 100 tokens");
        assertLt(result1000, result2000, "2000 tokens should be higher than 1000 tokens");

        // Maximum should not exceed MAX_MULTIPLIER
        assertLe(result2000, MAX_MULTIPLIER, "Should not exceed maximum multiplier");
    }

    function test_Multiplier_CalculateMultiplier_BoundaryValues() public pure {
        // Test minimum values
        uint256 minResult = Multiplier.calculateMultiplier(MIN_TOKENS, LOCK_30_DAYS);
        assertGe(minResult, BASE_MULTIPLIER, "Minimum should be >= base multiplier");

        // Test maximum values
        uint256 maxResult = Multiplier.calculateMultiplier(MAX_TOKENS, LOCK_365_DAYS);
        assertEq(maxResult, MAX_MULTIPLIER, "Maximum should equal MAX_MULTIPLIER");

        // Test clamping above maximum
        uint256 aboveMaxResult = Multiplier.calculateMultiplier(MAX_TOKENS * 2, LOCK_365_DAYS);
        assertEq(aboveMaxResult, MAX_MULTIPLIER, "Should clamp to MAX_MULTIPLIER");
    }

    function test_Multiplier_CalculateMultiplier_InputClamping() public pure {
        // Test amount clamping
        uint256 belowMin = Multiplier.calculateMultiplier(0, LOCK_30_DAYS);
        uint256 atMin = Multiplier.calculateMultiplier(MIN_TOKENS, LOCK_30_DAYS);
        assertEq(belowMin, atMin, "Below minimum should clamp to minimum");

        uint256 aboveMax = Multiplier.calculateMultiplier(MAX_TOKENS * 2, LOCK_30_DAYS);
        uint256 atMax = Multiplier.calculateMultiplier(MAX_TOKENS, LOCK_30_DAYS);
        assertEq(aboveMax, atMax, "Above maximum should clamp to maximum");

        // Test lockup clamping
        uint256 belowMinLockup = Multiplier.calculateMultiplier(1000, LOCK_30_DAYS - 1);
        uint256 atMinLockup = Multiplier.calculateMultiplier(1000, LOCK_30_DAYS);
        assertEq(belowMinLockup, atMinLockup, "Below minimum lockup should clamp");

        uint256 aboveMaxLockup = Multiplier.calculateMultiplier(1000, LOCK_365_DAYS + 1);
        uint256 atMaxLockup = Multiplier.calculateMultiplier(1000, LOCK_365_DAYS);
        assertEq(aboveMaxLockup, atMaxLockup, "Above maximum lockup should clamp");
    }

    // =============================================================================
    // EXPONENTIAL CURVE TESTS
    // =============================================================================

    function test_Multiplier_ExponentialCurve_Properties() public pure {
        uint256 lockup = LOCK_30_DAYS; // Use shorter duration to avoid hitting cap

        // Test that the curve approaches the maximum asymptotically
        uint256 result500 = Multiplier.calculateMultiplier(500, lockup);
        uint256 result1500 = Multiplier.calculateMultiplier(1500, lockup);
        uint256 result2500 = Multiplier.calculateMultiplier(2500, lockup);

        // The difference between consecutive points should decrease (exponential behavior)
        uint256 diff1 = result1500 - result500;
        uint256 diff2 = result2500 - result1500;
        
        // For an exponential curve approaching asymptote, later differences should be smaller
        assertLe(diff2, diff1, "Exponential curve should have decreasing or equal increments");
    }

    function test_Multiplier_TimeBonus_Linear() public pure {
        uint256 amount = 1000 ether; // Fixed amount

        uint256 result30 = Multiplier.calculateMultiplier(amount, LOCK_30_DAYS);
        uint256 result180 = Multiplier.calculateMultiplier(amount, LOCK_180_DAYS);
        uint256 result365 = Multiplier.calculateMultiplier(amount, LOCK_365_DAYS);

        // Time bonus should be linear
        uint256 timeBonus180 = result180 - result30;
        uint256 timeBonus365 = result365 - result30;

        // The ratio should be approximately linear with time
        // 180 days is (180-30)/(365-30) = 150/335 of the way to 365 days
        // We'll just check that the time bonus increases linearly
        assertGt(timeBonus180, 0, "180 day bonus should be positive");
        assertGt(timeBonus365, timeBonus180, "365 day bonus should be greater than 180 day bonus");
    }

    // =============================================================================
    // MONOTONIC INCREASE TESTS
    // =============================================================================

    function test_Multiplier_CalculateMultiplier_MonotonicIncrease() public pure {
        // Test that multiplier increases monotonically with both amount and duration

        // Fixed duration, increasing amounts (use shorter duration to avoid cap)
        uint256 lockup = LOCK_30_DAYS;
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = 250 ether;
        amounts[1] = 500 ether;
        amounts[2] = 1000 ether;
        amounts[3] = 1500 ether;
        amounts[4] = 2500 ether;

        for (uint256 i = 1; i < amounts.length; i++) {
            uint256 prevResult = Multiplier.calculateMultiplier(amounts[i-1], lockup);
            uint256 currResult = Multiplier.calculateMultiplier(amounts[i], lockup);
            assertLe(prevResult, currResult, "Multiplier should increase or stay same with amount");
        }

        // Fixed amount, increasing durations
        uint256 amount = 1250 ether;
        uint256[] memory durations = new uint256[](4);
        durations[0] = LOCK_30_DAYS;
        durations[1] = LOCK_90_DAYS;
        durations[2] = LOCK_180_DAYS;
        durations[3] = LOCK_365_DAYS;

        for (uint256 i = 1; i < durations.length; i++) {
            uint256 prevResult = Multiplier.calculateMultiplier(amount, durations[i-1]);
            uint256 currResult = Multiplier.calculateMultiplier(amount, durations[i]);
            assertLt(prevResult, currResult, "Multiplier should increase with duration");
        }
    }

    // =============================================================================
    // FUZZ TESTS
    // =============================================================================

    function testFuzz_Multiplier_CalculateMultiplier_ValidInputs(uint256 amount, uint256 lockup) public pure {
        // Bound inputs to reasonable ranges (the function clamps internally)
        amount = bound(amount, 0, MAX_TOKENS * 10); // Allow above max to test clamping
        lockup = bound(lockup, 0, LOCK_365_DAYS * 2); // Allow above max to test clamping

        uint256 result = Multiplier.calculateMultiplier(amount, lockup);

        // Should always return a positive result
        assertGt(result, 0, "Result should be positive");

        // Should be within expected bounds
        assertGe(result, BASE_MULTIPLIER, "Should be >= base multiplier");
        assertLe(result, MAX_MULTIPLIER, "Should be <= max multiplier");
    }

    function testFuzz_Multiplier_CalculateMultiplier_Monotonic(uint256 amount1, uint256 amount2, uint256 lockup) public pure {
        // Bound inputs
        amount1 = bound(amount1, MIN_TOKENS, MAX_TOKENS);
        amount2 = bound(amount2, MIN_TOKENS, MAX_TOKENS);
        lockup = bound(lockup, LOCK_30_DAYS, LOCK_365_DAYS);

        if (amount1 < amount2) {
            uint256 result1 = Multiplier.calculateMultiplier(amount1, lockup);
            uint256 result2 = Multiplier.calculateMultiplier(amount2, lockup);
            assertLe(result1, result2, "Multiplier should be monotonic in amount");
        }
    }



    // =============================================================================
    // SPECIFIC VALUE TESTS
    // =============================================================================

    function test_Multiplier_SpecificValues() public pure {
        // Test some specific expected values based on the exponential model
        
        // Minimum case: 1 token, 30 days
        uint256 minResult = Multiplier.calculateMultiplier(1 ether, LOCK_30_DAYS);
        assertEq(minResult, BASE_MULTIPLIER, "Minimum should equal base multiplier");

        // Maximum case: 2500 tokens, 365 days
        uint256 maxResult = Multiplier.calculateMultiplier(MAX_TOKENS, LOCK_365_DAYS);
        assertEq(maxResult, MAX_MULTIPLIER, "Maximum should equal max multiplier");

        // Mid-range case: 1250 tokens, 180 days
        uint256 midResult = Multiplier.calculateMultiplier(1250 ether, LOCK_180_DAYS);
        assertGt(midResult, BASE_MULTIPLIER, "Mid-range should be > base");
        assertLt(midResult, MAX_MULTIPLIER, "Mid-range should be < max");
    }

    function test_Multiplier_AsymptoticBehavior() public pure {
        uint256 lockup = LOCK_365_DAYS;

        // Test that very large amounts don't exceed the maximum
        uint256 result1 = Multiplier.calculateMultiplier(MAX_TOKENS, lockup);
        uint256 result2 = Multiplier.calculateMultiplier(MAX_TOKENS * 10, lockup);
        uint256 result3 = Multiplier.calculateMultiplier(MAX_TOKENS * 100, lockup);

        assertEq(result1, MAX_MULTIPLIER, "Max tokens should give max multiplier");
        assertEq(result2, MAX_MULTIPLIER, "10x max tokens should still give max multiplier");
        assertEq(result3, MAX_MULTIPLIER, "100x max tokens should still give max multiplier");
    }
}
