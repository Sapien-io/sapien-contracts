// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Multiplier} from "src/Multiplier.sol";
import {Constants as Const} from "src/utils/Constants.sol";

contract MultiplierTest is Test {
    Multiplier public multiplier;

    // Test constants
    uint256 public constant TOKEN_DECIMALS = 10 ** 18;
    uint256 public constant MINIMUM_STAKE = 1000 * TOKEN_DECIMALS;

    // Duration constants
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    // Expected base duration multipliers
    uint256 public constant MULTIPLIER_30_DAYS = 10500; // 1.05x
    uint256 public constant MULTIPLIER_90_DAYS = 11000; // 1.10x
    uint256 public constant MULTIPLIER_180_DAYS = 12500; // 1.25x
    uint256 public constant MULTIPLIER_365_DAYS = 15000; // 1.50x

    // Amount tiers (in tokens)
    uint256 public constant TIER_1K = 1000 * TOKEN_DECIMALS;
    uint256 public constant TIER_2_5K = 2500 * TOKEN_DECIMALS;
    uint256 public constant TIER_5K = 5000 * TOKEN_DECIMALS;
    uint256 public constant TIER_7_5K = 7500 * TOKEN_DECIMALS;
    uint256 public constant TIER_10K = 10000 * TOKEN_DECIMALS;

    // Test struct for matrix validation
    struct TestCase {
        uint256 amount;
        uint256 duration;
        uint256 expectedMultiplier;
    }

    function setUp() public {
        multiplier = new Multiplier();
    }

    // =============================================================================
    // BASIC FUNCTIONALITY TESTS
    // =============================================================================

    function test_CalculateMultiplier_ExactDiscretePeriods() public view {
        uint256 amount = MINIMUM_STAKE;

        // Test exact discrete periods with minimum stake
        assertEq(multiplier.calculateMultiplier(amount, LOCK_30_DAYS), 10500); // 1.05x
        assertEq(multiplier.calculateMultiplier(amount, LOCK_90_DAYS), 11000); // 1.10x
        assertEq(multiplier.calculateMultiplier(amount, LOCK_180_DAYS), 12500); // 1.25x
        assertEq(multiplier.calculateMultiplier(amount, LOCK_365_DAYS), 15000); // 1.50x
    }

    function test_CalculateMultiplier_AmountTiers() public view {
        uint256 lockup = LOCK_365_DAYS; // Use max duration to see full tier effect

        // Test all amount tiers
        assertEq(multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, lockup), 15000); // ≤1K: 1.50x
        assertEq(multiplier.calculateMultiplier(1500 * TOKEN_DECIMALS, lockup), 15900); // 1K-2.5K: 1.59x
        assertEq(multiplier.calculateMultiplier(3000 * TOKEN_DECIMALS, lockup), 16800); // 2.5K-5K: 1.68x
        assertEq(multiplier.calculateMultiplier(6000 * TOKEN_DECIMALS, lockup), 17700); // 5K-7.5K: 1.77x
        assertEq(multiplier.calculateMultiplier(8000 * TOKEN_DECIMALS, lockup), 18600); // 7.5K-10K: 1.86x
        assertEq(multiplier.calculateMultiplier(15000 * TOKEN_DECIMALS, lockup), 19500); // 10K+: 1.95x
    }

    function test_CalculateMultiplier_Matrix() public view {
        // Test the complete multiplier matrix as documented in the contract

        // 30 days row
        assertEq(multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, LOCK_30_DAYS), 10500); // 1.05x
        assertEq(multiplier.calculateMultiplier(1500 * TOKEN_DECIMALS, LOCK_30_DAYS), 11400); // 1.14x
        assertEq(multiplier.calculateMultiplier(3000 * TOKEN_DECIMALS, LOCK_30_DAYS), 12300); // 1.23x
        assertEq(multiplier.calculateMultiplier(6000 * TOKEN_DECIMALS, LOCK_30_DAYS), 13200); // 1.32x
        assertEq(multiplier.calculateMultiplier(8000 * TOKEN_DECIMALS, LOCK_30_DAYS), 14100); // 1.41x
        assertEq(multiplier.calculateMultiplier(15000 * TOKEN_DECIMALS, LOCK_30_DAYS), 15000); // 1.50x

        // 90 days row
        assertEq(multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, LOCK_90_DAYS), 11000); // 1.10x
        assertEq(multiplier.calculateMultiplier(1500 * TOKEN_DECIMALS, LOCK_90_DAYS), 11900); // 1.19x
        assertEq(multiplier.calculateMultiplier(3000 * TOKEN_DECIMALS, LOCK_90_DAYS), 12800); // 1.28x
        assertEq(multiplier.calculateMultiplier(6000 * TOKEN_DECIMALS, LOCK_90_DAYS), 13700); // 1.37x
        assertEq(multiplier.calculateMultiplier(8000 * TOKEN_DECIMALS, LOCK_90_DAYS), 14600); // 1.46x
        assertEq(multiplier.calculateMultiplier(15000 * TOKEN_DECIMALS, LOCK_90_DAYS), 15500); // 1.55x

        // 180 days row
        assertEq(multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, LOCK_180_DAYS), 12500); // 1.25x
        assertEq(multiplier.calculateMultiplier(1500 * TOKEN_DECIMALS, LOCK_180_DAYS), 13400); // 1.34x
        assertEq(multiplier.calculateMultiplier(3000 * TOKEN_DECIMALS, LOCK_180_DAYS), 14300); // 1.43x
        assertEq(multiplier.calculateMultiplier(6000 * TOKEN_DECIMALS, LOCK_180_DAYS), 15200); // 1.52x
        assertEq(multiplier.calculateMultiplier(8000 * TOKEN_DECIMALS, LOCK_180_DAYS), 16100); // 1.61x
        assertEq(multiplier.calculateMultiplier(15000 * TOKEN_DECIMALS, LOCK_180_DAYS), 17000); // 1.70x

        // 365 days row (already tested above)
    }

    // =============================================================================
    // INTERPOLATION TESTS
    // =============================================================================

    function test_DurationMultiplier_InterpolationBetween30And90Days() public view {
        uint256 amount = MINIMUM_STAKE; // Use minimum to isolate duration effect

        // Test interpolation at 60 days (midpoint between 30 and 90)
        uint256 expected = 10500 + ((60 days - 30 days) * (11000 - 10500)) / (90 days - 30 days);
        assertEq(multiplier.calculateMultiplier(amount, 60 days), expected);

        // Test at 45 days (1/4 between 30 and 90)
        expected = 10500 + ((45 days - 30 days) * (11000 - 10500)) / (90 days - 30 days);
        assertEq(multiplier.calculateMultiplier(amount, 45 days), expected);
    }

    function test_DurationMultiplier_InterpolationBetween90And180Days() public view {
        uint256 amount = MINIMUM_STAKE;

        // Test interpolation at 135 days (midpoint between 90 and 180)
        uint256 expected = 11000 + ((135 days - 90 days) * (12500 - 11000)) / (180 days - 90 days);
        assertEq(multiplier.calculateMultiplier(amount, 135 days), expected);
    }

    function test_DurationMultiplier_InterpolationBetween180And365Days() public view {
        uint256 amount = MINIMUM_STAKE;

        // Test interpolation at 272.5 days (midpoint between 180 and 365)
        uint256 midpoint = 180 days + (365 days - 180 days) / 2;
        uint256 expected = 12500 + ((midpoint - 180 days) * (15000 - 12500)) / (365 days - 180 days);
        assertEq(multiplier.calculateMultiplier(amount, midpoint), expected);
    }

    // =============================================================================
    // EDGE CASES AND VALIDATION TESTS
    // =============================================================================

    function test_CalculateMultiplier_InvalidLockupPeriods() public view {
        uint256 amount = MINIMUM_STAKE;

        // Test below minimum lockup
        assertEq(multiplier.calculateMultiplier(amount, LOCK_30_DAYS - 1), 0);

        // Test above maximum lockup
        assertEq(multiplier.calculateMultiplier(amount, LOCK_365_DAYS + 1), 0);

        // Test zero lockup
        assertEq(multiplier.calculateMultiplier(amount, 0), 0);
    }

    function test_CalculateMultiplier_InvalidAmounts() public view {
        uint256 lockup = LOCK_30_DAYS;

        // Test below minimum stake
        assertEq(multiplier.calculateMultiplier(MINIMUM_STAKE - 1, lockup), 0);

        // Test zero amount
        assertEq(multiplier.calculateMultiplier(0, lockup), 0);
    }

    function test_CalculateMultiplier_BoundaryAmounts() public view {
        uint256 lockup = LOCK_365_DAYS;

        // Test exact tier boundaries
        assertEq(multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, lockup), 15000); // Exact T0 (≤1K)
        assertEq(multiplier.calculateMultiplier(1001 * TOKEN_DECIMALS, lockup), 15900); // Just above T0 -> T1
        assertEq(multiplier.calculateMultiplier(2500 * TOKEN_DECIMALS, lockup), 16800); // Exact T2
        assertEq(multiplier.calculateMultiplier(5000 * TOKEN_DECIMALS, lockup), 17700); // Exact T3
        assertEq(multiplier.calculateMultiplier(7500 * TOKEN_DECIMALS, lockup), 18600); // Exact T4
        assertEq(multiplier.calculateMultiplier(10000 * TOKEN_DECIMALS, lockup), 19500); // Exact T5

        // Test just below tier boundaries (but above minimum stake)
        assertEq(multiplier.calculateMultiplier(2499 * TOKEN_DECIMALS, lockup), 15900); // Just below T2
        assertEq(multiplier.calculateMultiplier(4999 * TOKEN_DECIMALS, lockup), 16800); // Just below T3
        assertEq(multiplier.calculateMultiplier(7499 * TOKEN_DECIMALS, lockup), 17700); // Just below T4
        assertEq(multiplier.calculateMultiplier(9999 * TOKEN_DECIMALS, lockup), 18600); // Just below T5
    }

    function test_CalculateMultiplier_LargeAmounts() public view {
        uint256 lockup = LOCK_365_DAYS;

        // Test very large amounts (should cap at max tier)
        assertEq(multiplier.calculateMultiplier(100000 * TOKEN_DECIMALS, lockup), 19500); // 1.95x
        assertEq(multiplier.calculateMultiplier(1000000 * TOKEN_DECIMALS, lockup), 19500); // 1.95x
    }

    // =============================================================================
    // INTERNAL FUNCTION TESTS (via public interface)
    // =============================================================================

    function test_GetAmountTierFactor_AllTiers() public view {
        // We can test this indirectly through calculateMultiplier with fixed duration
        uint256 baseDuration = LOCK_30_DAYS; // 1.05x base
        uint256 baseMult = 10500;

        // Tier 0: ≤1K tokens
        uint256 result = multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult); // No bonus

        // Tier 1: 1K-2.5K tokens (20% bonus = 0.09x)
        result = multiplier.calculateMultiplier(1500 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 900); // +0.09x

        // Tier 2: 2.5K-5K tokens (40% bonus = 0.18x)
        result = multiplier.calculateMultiplier(3000 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 1800); // +0.18x

        // Tier 3: 5K-7.5K tokens (60% bonus = 0.27x)
        result = multiplier.calculateMultiplier(6000 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 2700); // +0.27x

        // Tier 4: 7.5K-10K tokens (80% bonus = 0.36x)
        result = multiplier.calculateMultiplier(8000 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 3600); // +0.36x

        // Tier 5: 10K+ tokens (100% bonus = 0.45x)
        result = multiplier.calculateMultiplier(15000 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 4500); // +0.45x
    }

    function test_IsValidLockupPeriod() public view {
        // Test valid lockup periods
        assertTrue(multiplier.isValidLockupPeriod(LOCK_30_DAYS));
        assertTrue(multiplier.isValidLockupPeriod(LOCK_90_DAYS));
        assertTrue(multiplier.isValidLockupPeriod(LOCK_180_DAYS));
        assertTrue(multiplier.isValidLockupPeriod(LOCK_365_DAYS));

        // Test invalid lockup periods
        assertFalse(multiplier.isValidLockupPeriod(LOCK_30_DAYS - 1)); // Just below minimum
        assertFalse(multiplier.isValidLockupPeriod(LOCK_365_DAYS + 1)); // Just above maximum
        assertFalse(multiplier.isValidLockupPeriod(0)); // Zero duration
        assertFalse(multiplier.isValidLockupPeriod(type(uint256).max)); // Max uint256
    }

    // =============================================================================
    // FUZZ TESTS
    // =============================================================================

    function testFuzz_CalculateMultiplier_ValidInputs(uint256 amount, uint256 lockup) public view {
        // Bound inputs to valid ranges
        amount = bound(amount, MINIMUM_STAKE, 1000000 * TOKEN_DECIMALS);
        lockup = bound(lockup, LOCK_30_DAYS, LOCK_365_DAYS);

        uint256 result = multiplier.calculateMultiplier(amount, lockup);

        // Should always return a positive result for valid inputs
        assertGt(result, 0);

        // Should be within expected bounds (1.05x to 1.95x)
        assertGe(result, 10500); // Minimum multiplier
        assertLe(result, 19500); // Maximum multiplier
    }

    function testFuzz_CalculateMultiplier_InvalidInputs(uint256 amount, uint256 lockup) public view {
        // Test invalid amounts
        if (amount < MINIMUM_STAKE) {
            assertEq(multiplier.calculateMultiplier(amount, LOCK_30_DAYS), 0);
        }

        // Test invalid lockups
        if (lockup < LOCK_30_DAYS || lockup > LOCK_365_DAYS) {
            assertEq(multiplier.calculateMultiplier(MINIMUM_STAKE, lockup), 0);
        }
    }

    // =============================================================================
    // INTEGRATION TESTS
    // =============================================================================

    function test_CalculateMultiplier_MonotonicIncrease() public view {
        // Test that multiplier increases with both amount and duration

        // Fixed duration, increasing amounts
        uint256 lockup = LOCK_180_DAYS;
        uint256 mult1 = multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, lockup);
        uint256 mult2 = multiplier.calculateMultiplier(5000 * TOKEN_DECIMALS, lockup);
        uint256 mult3 = multiplier.calculateMultiplier(10000 * TOKEN_DECIMALS, lockup);

        assertLt(mult1, mult2);
        assertLt(mult2, mult3);

        // Fixed amount, increasing durations
        uint256 amount = 5000 * TOKEN_DECIMALS;
        mult1 = multiplier.calculateMultiplier(amount, LOCK_30_DAYS);
        mult2 = multiplier.calculateMultiplier(amount, LOCK_180_DAYS);
        mult3 = multiplier.calculateMultiplier(amount, LOCK_365_DAYS);

        assertLt(mult1, mult2);
        assertLt(mult2, mult3);
    }

    function test_CalculateMultiplier_ConsistentWithMatrix() public view {
        // Verify that our implementation matches the documented matrix exactly

        TestCase[] memory testCases = new TestCase[](24);

        // Fill in all matrix values (6 tiers × 4 durations)
        testCases[0] = TestCase(1000 * TOKEN_DECIMALS, LOCK_30_DAYS, 10500);
        testCases[1] = TestCase(1500 * TOKEN_DECIMALS, LOCK_30_DAYS, 11400);
        testCases[2] = TestCase(3000 * TOKEN_DECIMALS, LOCK_30_DAYS, 12300);
        testCases[3] = TestCase(6000 * TOKEN_DECIMALS, LOCK_30_DAYS, 13200);
        testCases[4] = TestCase(8000 * TOKEN_DECIMALS, LOCK_30_DAYS, 14100);
        testCases[5] = TestCase(15000 * TOKEN_DECIMALS, LOCK_30_DAYS, 15000);

        testCases[6] = TestCase(1000 * TOKEN_DECIMALS, LOCK_90_DAYS, 11000);
        testCases[7] = TestCase(1500 * TOKEN_DECIMALS, LOCK_90_DAYS, 11900);
        testCases[8] = TestCase(3000 * TOKEN_DECIMALS, LOCK_90_DAYS, 12800);
        testCases[9] = TestCase(6000 * TOKEN_DECIMALS, LOCK_90_DAYS, 13700);
        testCases[10] = TestCase(8000 * TOKEN_DECIMALS, LOCK_90_DAYS, 14600);
        testCases[11] = TestCase(15000 * TOKEN_DECIMALS, LOCK_90_DAYS, 15500);

        testCases[12] = TestCase(1000 * TOKEN_DECIMALS, LOCK_180_DAYS, 12500);
        testCases[13] = TestCase(1500 * TOKEN_DECIMALS, LOCK_180_DAYS, 13400);
        testCases[14] = TestCase(3000 * TOKEN_DECIMALS, LOCK_180_DAYS, 14300);
        testCases[15] = TestCase(6000 * TOKEN_DECIMALS, LOCK_180_DAYS, 15200);
        testCases[16] = TestCase(8000 * TOKEN_DECIMALS, LOCK_180_DAYS, 16100);
        testCases[17] = TestCase(15000 * TOKEN_DECIMALS, LOCK_180_DAYS, 17000);

        testCases[18] = TestCase(1000 * TOKEN_DECIMALS, LOCK_365_DAYS, 15000);
        testCases[19] = TestCase(1500 * TOKEN_DECIMALS, LOCK_365_DAYS, 15900);
        testCases[20] = TestCase(3000 * TOKEN_DECIMALS, LOCK_365_DAYS, 16800);
        testCases[21] = TestCase(6000 * TOKEN_DECIMALS, LOCK_365_DAYS, 17700);
        testCases[22] = TestCase(8000 * TOKEN_DECIMALS, LOCK_365_DAYS, 18600);
        testCases[23] = TestCase(15000 * TOKEN_DECIMALS, LOCK_365_DAYS, 19500);

        for (uint256 i = 0; i < testCases.length; i++) {
            uint256 result = multiplier.calculateMultiplier(testCases[i].amount, testCases[i].duration);
            assertEq(
                result,
                testCases[i].expectedMultiplier,
                string(abi.encodePacked("Test case ", vm.toString(i), " failed"))
            );
        }
    }
}
