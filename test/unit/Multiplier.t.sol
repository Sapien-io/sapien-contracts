// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Multiplier} from "src/Multiplier.sol";
import {Constants as Const} from "src/utils/Constants.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";

// Test helper contract to expose internal functions
contract MultiplierTestHelper {
    function getAmountTierFactor(uint256 amount) external pure returns (uint256) {
        return Multiplier.getAmountTierFactor(amount);
    }
}

contract MultiplierTest is Test {
    MultiplierTestHelper public helper;

    // Test constants
    uint256 public constant TOKEN_DECIMALS = 10 ** 18;
    uint256 public constant MINIMUM_STAKE = 250 * TOKEN_DECIMALS;

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
        helper = new MultiplierTestHelper();
    }

    // =============================================================================
    // BASIC FUNCTIONALITY TESTS
    // =============================================================================

    function test_Multiplier_CalculateMultiplier_ExactDiscretePeriods() public pure {
        uint256 amount = MINIMUM_STAKE;

        // Test exact discrete periods with minimum stake (250 tokens = Tier 0)
        assertEq(Multiplier.calculateMultiplier(amount, LOCK_30_DAYS), 10500); // 1.05x (1.05x + 0.00x tier bonus)
        assertEq(Multiplier.calculateMultiplier(amount, LOCK_90_DAYS), 11000); // 1.10x (1.10x + 0.00x tier bonus)
        assertEq(Multiplier.calculateMultiplier(amount, LOCK_180_DAYS), 12500); // 1.25x (1.25x + 0.00x tier bonus)
        assertEq(Multiplier.calculateMultiplier(amount, LOCK_365_DAYS), 15000); // 1.50x (1.50x + 0.00x tier bonus)
    }

    function test_Multiplier_CalculateMultiplier_AmountTiers() public pure {
        uint256 lockup = LOCK_365_DAYS; // Use max duration to see full tier effect

        // Test all amount tiers
        assertEq(Multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, lockup), 15900); // 1K: 1.59x (Tier 1)
        assertEq(Multiplier.calculateMultiplier(1500 * TOKEN_DECIMALS, lockup), 15900); // 1K-2.5K: 1.59x
        assertEq(Multiplier.calculateMultiplier(3000 * TOKEN_DECIMALS, lockup), 16800); // 2.5K-5K: 1.68x
        assertEq(Multiplier.calculateMultiplier(6000 * TOKEN_DECIMALS, lockup), 17700); // 5K-7.5K: 1.77x
        assertEq(Multiplier.calculateMultiplier(8000 * TOKEN_DECIMALS, lockup), 18600); // 7.5K-10K: 1.86x
        assertEq(Multiplier.calculateMultiplier(15000 * TOKEN_DECIMALS, lockup), 19500); // 10K+: 1.95x
    }

    function test_Multiplier_CalculateMultiplier_Matrix() public pure {
        // Test the complete multiplier matrix as documented in the contract

        // 30 days row
        assertEq(Multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, LOCK_30_DAYS), 11400); // 1.14x (with tier bonus)
        assertEq(Multiplier.calculateMultiplier(1500 * TOKEN_DECIMALS, LOCK_30_DAYS), 11400); // 1.14x
        assertEq(Multiplier.calculateMultiplier(3000 * TOKEN_DECIMALS, LOCK_30_DAYS), 12300); // 1.23x
        assertEq(Multiplier.calculateMultiplier(6000 * TOKEN_DECIMALS, LOCK_30_DAYS), 13200); // 1.32x
        assertEq(Multiplier.calculateMultiplier(8000 * TOKEN_DECIMALS, LOCK_30_DAYS), 14100); // 1.41x
        assertEq(Multiplier.calculateMultiplier(15000 * TOKEN_DECIMALS, LOCK_30_DAYS), 15000); // 1.50x

        // 90 days row
        assertEq(Multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, LOCK_90_DAYS), 11900); // 1.19x (with tier bonus)
        assertEq(Multiplier.calculateMultiplier(1500 * TOKEN_DECIMALS, LOCK_90_DAYS), 11900); // 1.19x
        assertEq(Multiplier.calculateMultiplier(3000 * TOKEN_DECIMALS, LOCK_90_DAYS), 12800); // 1.28x
        assertEq(Multiplier.calculateMultiplier(6000 * TOKEN_DECIMALS, LOCK_90_DAYS), 13700); // 1.37x
        assertEq(Multiplier.calculateMultiplier(8000 * TOKEN_DECIMALS, LOCK_90_DAYS), 14600); // 1.46x
        assertEq(Multiplier.calculateMultiplier(15000 * TOKEN_DECIMALS, LOCK_90_DAYS), 15500); // 1.55x

        // 180 days row
        assertEq(Multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, LOCK_180_DAYS), 13400); // 1.34x (with tier bonus)
        assertEq(Multiplier.calculateMultiplier(1500 * TOKEN_DECIMALS, LOCK_180_DAYS), 13400); // 1.34x
        assertEq(Multiplier.calculateMultiplier(3000 * TOKEN_DECIMALS, LOCK_180_DAYS), 14300); // 1.43x
        assertEq(Multiplier.calculateMultiplier(6000 * TOKEN_DECIMALS, LOCK_180_DAYS), 15200); // 1.52x
        assertEq(Multiplier.calculateMultiplier(8000 * TOKEN_DECIMALS, LOCK_180_DAYS), 16100); // 1.61x
        assertEq(Multiplier.calculateMultiplier(15000 * TOKEN_DECIMALS, LOCK_180_DAYS), 17000); // 1.70x

        // 365 days row (already tested above)
    }

    // =============================================================================
    // INTERPOLATION TESTS
    // =============================================================================

    function test_Multiplier_DurationMultiplier_InterpolationBetween30And90Days() public pure {
        uint256 amount = MINIMUM_STAKE; // Use minimum to isolate duration effect

        // Test interpolation at 60 days (midpoint between 30 and 90)
        uint256 expected = 10500 + ((60 days - 30 days) * (11000 - 10500)) / (90 days - 30 days);
        assertEq(Multiplier.calculateMultiplier(amount, 60 days), expected);

        // Test at 45 days (1/4 between 30 and 90)
        expected = 10500 + ((45 days - 30 days) * (11000 - 10500)) / (90 days - 30 days);
        assertEq(Multiplier.calculateMultiplier(amount, 45 days), expected);
    }

    function test_Multiplier_DurationMultiplier_InterpolationBetween90And180Days() public pure {
        uint256 amount = MINIMUM_STAKE;

        // Test interpolation at 135 days (midpoint between 90 and 180)
        uint256 expected = 11000 + ((135 days - 90 days) * (12500 - 11000)) / (180 days - 90 days);
        assertEq(Multiplier.calculateMultiplier(amount, 135 days), expected);
    }

    function test_Multiplier_DurationMultiplier_InterpolationBetween180And365Days() public pure {
        uint256 amount = MINIMUM_STAKE;

        // Test interpolation at 272.5 days (midpoint between 180 and 365)
        uint256 midpoint = 180 days + (365 days - 180 days) / 2;
        uint256 expected = 12500 + ((midpoint - 180 days) * (15000 - 12500)) / (365 days - 180 days);
        assertEq(Multiplier.calculateMultiplier(amount, midpoint), expected);
    }

    // =============================================================================
    // EDGE CASES AND VALIDATION TESTS
    // =============================================================================

    function test_Multiplier_CalculateMultiplier_InvalidLockupPeriods() public {
        uint256 amount = MINIMUM_STAKE;

        // Test below minimum lockup
        vm.expectRevert(ISapienVault.InvalidLockupPeriod.selector);
        Multiplier.calculateMultiplier(amount, LOCK_30_DAYS - 1);

        // Test above maximum lockup
        vm.expectRevert(ISapienVault.InvalidLockupPeriod.selector);
        Multiplier.calculateMultiplier(amount, LOCK_365_DAYS + 1);

        // Test zero lockup
        vm.expectRevert(ISapienVault.InvalidLockupPeriod.selector);
        Multiplier.calculateMultiplier(amount, 0);
    }

    function test_Multiplier_CalculateMultiplier_InvalidAmounts() public {
        uint256 lockup = LOCK_30_DAYS;

        // Test below minimum stake
        vm.expectRevert(ISapienVault.MinimumStakeAmountRequired.selector);
        Multiplier.calculateMultiplier(MINIMUM_STAKE - 1, lockup);

        // Test zero amount
        vm.expectRevert(ISapienVault.MinimumStakeAmountRequired.selector);
        Multiplier.calculateMultiplier(0, lockup);
    }

    function test_Multiplier_CalculateMultiplier_BoundaryAmounts() public pure {
        uint256 lockup = LOCK_365_DAYS;

        // Test exact tier boundaries
        assertEq(Multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, lockup), 15900); // 1K = Tier 1
        assertEq(Multiplier.calculateMultiplier(1001 * TOKEN_DECIMALS, lockup), 15900); // Just above 1K, still T1
        assertEq(Multiplier.calculateMultiplier(2500 * TOKEN_DECIMALS, lockup), 16800); // Exact T2
        assertEq(Multiplier.calculateMultiplier(5000 * TOKEN_DECIMALS, lockup), 17700); // Exact T3
        assertEq(Multiplier.calculateMultiplier(7500 * TOKEN_DECIMALS, lockup), 18600); // Exact T4
        assertEq(Multiplier.calculateMultiplier(10000 * TOKEN_DECIMALS, lockup), 19500); // Exact T5

        // Test just below tier boundaries (but above minimum stake)
        assertEq(Multiplier.calculateMultiplier(2499 * TOKEN_DECIMALS, lockup), 15900); // Just below T2
        assertEq(Multiplier.calculateMultiplier(4999 * TOKEN_DECIMALS, lockup), 16800); // Just below T3
        assertEq(Multiplier.calculateMultiplier(7499 * TOKEN_DECIMALS, lockup), 17700); // Just below T4
        assertEq(Multiplier.calculateMultiplier(9999 * TOKEN_DECIMALS, lockup), 18600); // Just below T5
    }

    function test_Multiplier_CalculateMultiplier_LargeAmounts() public pure {
        uint256 lockup = LOCK_365_DAYS;

        // Test very large amounts (should cap at max tier)
        assertEq(Multiplier.calculateMultiplier(100000 * TOKEN_DECIMALS, lockup), 19500); // 1.95x
        assertEq(Multiplier.calculateMultiplier(1000000 * TOKEN_DECIMALS, lockup), 19500); // 1.95x
    }

    // =============================================================================
    // INTERNAL FUNCTION TESTS (via public interface)
    // =============================================================================

    function test_Multiplier_GetAmountTierFactor_AllTiers() public pure {
        // We can test this indirectly through calculateMultiplier with fixed duration
        uint256 baseDuration = LOCK_30_DAYS; // 1.05x base
        uint256 baseMult = 10500;

        // Tier 1: 1K tokens (gets 20% bonus)
        uint256 result = Multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 900); // +0.09x tier bonus

        // Tier 1: 1K-2.5K tokens (20% bonus = 0.09x)
        result = Multiplier.calculateMultiplier(1500 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 900); // +0.09x

        // Tier 2: 2.5K-5K tokens (40% bonus = 0.18x)
        result = Multiplier.calculateMultiplier(3000 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 1800); // +0.18x

        // Tier 3: 5K-7.5K tokens (60% bonus = 0.27x)
        result = Multiplier.calculateMultiplier(6000 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 2700); // +0.27x

        // Tier 4: 7.5K-10K tokens (80% bonus = 0.36x)
        result = Multiplier.calculateMultiplier(8000 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 3600); // +0.36x

        // Tier 5: 10K+ tokens (100% bonus = 0.45x)
        result = Multiplier.calculateMultiplier(15000 * TOKEN_DECIMALS, baseDuration);
        assertEq(result, baseMult + 4500); // +0.45x
    }

    // =============================================================================
    // FUZZ TESTS
    // =============================================================================

    function testFuzz_Multiplier_CalculateMultiplier_ValidInputs(uint256 amount, uint256 lockup) public pure {
        // Bound inputs to valid ranges
        amount = bound(amount, MINIMUM_STAKE, 1000000 * TOKEN_DECIMALS);
        lockup = bound(lockup, LOCK_30_DAYS, LOCK_365_DAYS);

        uint256 result = Multiplier.calculateMultiplier(amount, lockup);

        // Should always return a positive result for valid inputs
        assertGt(result, 0);

        // Should be within expected bounds (1.05x to 1.95x)
        assertGe(result, 10500); // Minimum multiplier
        assertLe(result, 19500); // Maximum multiplier
    }

    function testFuzz_Multiplier_CalculateMultiplier_InvalidInputs(uint256 amount, uint256 lockup) public {
        // Test invalid amounts
        if (amount < MINIMUM_STAKE) {
            vm.expectRevert(ISapienVault.MinimumStakeAmountRequired.selector);
            Multiplier.calculateMultiplier(amount, LOCK_30_DAYS);
        }

        // Test invalid lockups
        if (lockup < LOCK_30_DAYS || lockup > LOCK_365_DAYS) {
            vm.expectRevert(ISapienVault.InvalidLockupPeriod.selector);
            Multiplier.calculateMultiplier(MINIMUM_STAKE, lockup);
        }
    }

    // =============================================================================
    // INTEGRATION TESTS
    // =============================================================================

    function test_Multiplier_CalculateMultiplier_MonotonicIncrease() public pure {
        // Test that multiplier increases with both amount and duration

        // Fixed duration, increasing amounts
        uint256 lockup = LOCK_180_DAYS;
        uint256 mult1 = Multiplier.calculateMultiplier(1000 * TOKEN_DECIMALS, lockup);
        uint256 mult2 = Multiplier.calculateMultiplier(5000 * TOKEN_DECIMALS, lockup);
        uint256 mult3 = Multiplier.calculateMultiplier(10000 * TOKEN_DECIMALS, lockup);

        assertLt(mult1, mult2);
        assertLt(mult2, mult3);

        // Fixed amount, increasing durations
        uint256 amount = 5000 * TOKEN_DECIMALS;
        mult1 = Multiplier.calculateMultiplier(amount, LOCK_30_DAYS);
        mult2 = Multiplier.calculateMultiplier(amount, LOCK_180_DAYS);
        mult3 = Multiplier.calculateMultiplier(amount, LOCK_365_DAYS);

        assertLt(mult1, mult2);
        assertLt(mult2, mult3);
    }

    function test_Multiplier_CalculateMultiplier_ConsistentWithMatrix() public pure {
        // Verify that our implementation matches the documented matrix exactly

        TestCase[] memory testCases = new TestCase[](24);

        // Fill in all matrix values (6 tiers × 4 durations)
        testCases[0] = TestCase(1000 * TOKEN_DECIMALS, LOCK_30_DAYS, 11400); // 1.14x with tier bonus
        testCases[1] = TestCase(1500 * TOKEN_DECIMALS, LOCK_30_DAYS, 11400); // Same tier as 1000
        testCases[2] = TestCase(3000 * TOKEN_DECIMALS, LOCK_30_DAYS, 12300);
        testCases[3] = TestCase(6000 * TOKEN_DECIMALS, LOCK_30_DAYS, 13200);
        testCases[4] = TestCase(8000 * TOKEN_DECIMALS, LOCK_30_DAYS, 14100);
        testCases[5] = TestCase(15000 * TOKEN_DECIMALS, LOCK_30_DAYS, 15000);

        testCases[6] = TestCase(1000 * TOKEN_DECIMALS, LOCK_90_DAYS, 11900); // 1.19x with tier bonus
        testCases[7] = TestCase(1500 * TOKEN_DECIMALS, LOCK_90_DAYS, 11900); // Same tier as 1000
        testCases[8] = TestCase(3000 * TOKEN_DECIMALS, LOCK_90_DAYS, 12800);
        testCases[9] = TestCase(6000 * TOKEN_DECIMALS, LOCK_90_DAYS, 13700);
        testCases[10] = TestCase(8000 * TOKEN_DECIMALS, LOCK_90_DAYS, 14600);
        testCases[11] = TestCase(15000 * TOKEN_DECIMALS, LOCK_90_DAYS, 15500);

        testCases[12] = TestCase(1000 * TOKEN_DECIMALS, LOCK_180_DAYS, 13400); // 1.34x with tier bonus
        testCases[13] = TestCase(1500 * TOKEN_DECIMALS, LOCK_180_DAYS, 13400); // Same tier as 1000
        testCases[14] = TestCase(3000 * TOKEN_DECIMALS, LOCK_180_DAYS, 14300);
        testCases[15] = TestCase(6000 * TOKEN_DECIMALS, LOCK_180_DAYS, 15200);
        testCases[16] = TestCase(8000 * TOKEN_DECIMALS, LOCK_180_DAYS, 16100);
        testCases[17] = TestCase(15000 * TOKEN_DECIMALS, LOCK_180_DAYS, 17000);

        testCases[18] = TestCase(1000 * TOKEN_DECIMALS, LOCK_365_DAYS, 15900); // 1.59x with tier bonus
        testCases[19] = TestCase(1500 * TOKEN_DECIMALS, LOCK_365_DAYS, 15900); // Same tier as 1000
        testCases[20] = TestCase(3000 * TOKEN_DECIMALS, LOCK_365_DAYS, 16800);
        testCases[21] = TestCase(6000 * TOKEN_DECIMALS, LOCK_365_DAYS, 17700);
        testCases[22] = TestCase(8000 * TOKEN_DECIMALS, LOCK_365_DAYS, 18600);
        testCases[23] = TestCase(15000 * TOKEN_DECIMALS, LOCK_365_DAYS, 19500);

        for (uint256 i = 0; i < testCases.length; i++) {
            uint256 result = Multiplier.calculateMultiplier(testCases[i].amount, testCases[i].duration);
            assertEq(
                result,
                testCases[i].expectedMultiplier,
                string(abi.encodePacked("Test case ", vm.toString(i), " failed"))
            );
        }
    }

    // =============================================================================
    // SPECIFIC TIER FACTOR TESTS
    // =============================================================================

    function test_Multiplier_GetAmountTierFactor_OneToken() public {
        // Test that 1 token returns tier factor 0 (Tier 0)
        // Since getAmountTierFactor is internal, we test indirectly through calculateMultiplier

        uint256 oneToken = 1 * TOKEN_DECIMALS; // 1 token = 1e18 wei
        uint256 lockup = LOCK_30_DAYS; // Use minimum lockup for simplicity

        // This should revert because amount < MINIMUM_STAKE_AMOUNT
        vm.expectRevert(ISapienVault.MinimumStakeAmountRequired.selector);
        Multiplier.calculateMultiplier(oneToken, lockup);

        // Test 249 tokens (below 250 threshold) - this should also revert from calculateMultiplier
        uint256 tokens249 = 249 * TOKEN_DECIMALS;
        vm.expectRevert(ISapienVault.MinimumStakeAmountRequired.selector);
        Multiplier.calculateMultiplier(tokens249, lockup);

        // Test exactly 250 tokens (at threshold) - should get Tier 0 treatment
        uint256 tokens250 = 250 * TOKEN_DECIMALS;
        uint256 result = Multiplier.calculateMultiplier(tokens250, lockup);
        assertGt(result, 0, "250 tokens should return positive multiplier");

        // The 250 token result should be base (10500) + tier 0 bonus (0) = 10500
        assertEq(result, 10500, "250 tokens should get Tier 0 multiplier (1.05x)");
    }

    function test_Multiplier_GetAmountTierFactor_DirectCall() public view {
        // Test the getAmountTierFactor function directly using our helper contract

        // Test 1 token - should return 0 (Tier 0)
        uint256 oneToken = 1 * TOKEN_DECIMALS;
        uint256 tierFactor = helper.getAmountTierFactor(oneToken);
        assertEq(tierFactor, 0, "1 token should return tier factor 0");

        // Test 999 tokens - should return 0 (Tier 0)
        uint256 tokens999 = 999 * TOKEN_DECIMALS;
        tierFactor = helper.getAmountTierFactor(tokens999);
        assertEq(tierFactor, 0, "999 tokens should return tier factor 0");

        // Test 1000 tokens - should return 2000 (Tier 1, 20%)
        uint256 tokens1000 = 1000 * TOKEN_DECIMALS;
        tierFactor = helper.getAmountTierFactor(tokens1000);
        assertEq(tierFactor, 2000, "1000 tokens should return tier factor 2000 (20%)");

        // Test 2500 tokens - should return 4000 (Tier 2, 40%)
        uint256 tokens2500 = 2500 * TOKEN_DECIMALS;
        tierFactor = helper.getAmountTierFactor(tokens2500);
        assertEq(tierFactor, 4000, "2500 tokens should return tier factor 4000 (40%)");
    }
}
