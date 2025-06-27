// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienVault} from "src/SapienVault.sol";
import {Constants as Const} from "src/utils/Constants.sol";


/**
 * @title MultiplierInvariant
 * @notice Invariant tests for the Multiplier library
 * @dev Tests mathematical properties that should always hold true
 */
contract MultiplierInvariantTest is Test {

    SapienVault public sapienVault;

    function setUp() public {
        sapienVault = new SapienVault();
    }

    // =============================================================================
    // MONOTONICITY INVARIANTS
    // =============================================================================

    /// @dev For a fixed lockup period, multiplier should increase monotonically with amount
    function invariant_multiplierMonotonicInAmount() public view {
        // Test with various lockup periods
        uint256[] memory lockups = new uint256[](4);
        lockups[0] = Const.LOCKUP_30_DAYS;
        lockups[1] = Const.LOCKUP_90_DAYS;
        lockups[2] = Const.LOCKUP_180_DAYS;
        lockups[3] = Const.LOCKUP_365_DAYS;

        // Test with different amounts
        uint256 amount1 = 1000 * Const.TOKEN_DECIMALS;
        uint256 amount2 = 2000 * Const.TOKEN_DECIMALS;

        for (uint256 i = 0; i < lockups.length; i++) {
            uint256 lockup = lockups[i];
            uint256 mult1 = sapienVault.calculateMultiplier(amount1, lockup);
            uint256 mult2 = sapienVault.calculateMultiplier(amount2, lockup);

            // Higher amount should give higher or equal multiplier
            assert(mult1 <= mult2);

            // Both multipliers should be within expected bounds
            assert(mult1 >= Const.BASE_MULTIPLIER);
            assert(mult2 >= Const.BASE_MULTIPLIER);
            assert(mult1 <= Const.MAX_MULTIPLIER);
            assert(mult2 <= Const.MAX_MULTIPLIER);
        }
    }

    /// @dev For a fixed amount, multiplier should increase monotonically with lockup period
    function invariant_multiplierMonotonicInTime() public view {
        uint256 amount = 1500 * Const.TOKEN_DECIMALS;

        uint256 lockup1 = Const.LOCKUP_30_DAYS;
        uint256 lockup2 = Const.LOCKUP_365_DAYS;

        uint256 mult1 = sapienVault.calculateMultiplier(amount, lockup1);
        uint256 mult2 = sapienVault.calculateMultiplier(amount, lockup2);

        // Longer lockup should give higher multiplier
        assert(mult1 < mult2);

        // Both multipliers should be within expected bounds
        assert(mult1 >= Const.BASE_MULTIPLIER);
        assert(mult2 >= Const.BASE_MULTIPLIER);
        assert(mult1 <= Const.MAX_MULTIPLIER);
        assert(mult2 <= Const.MAX_MULTIPLIER);
    }

    // =============================================================================
    // BOUNDARY INVARIANTS
    // =============================================================================

    /// @dev Multiplier should always be within valid bounds
    function invariant_multiplierBounds() public view {
        // Test various combinations
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 100 * Const.TOKEN_DECIMALS;
        amounts[1] = 1000 * Const.TOKEN_DECIMALS;
        amounts[2] = 10000 * Const.TOKEN_DECIMALS; // Above max to test clamping

        uint256[] memory lockups = new uint256[](3);
        lockups[0] = Const.LOCKUP_30_DAYS;
        lockups[1] = Const.LOCKUP_180_DAYS;
        lockups[2] = Const.LOCKUP_365_DAYS + 100 days; // Above max to test clamping

        for (uint256 i = 0; i < amounts.length; i++) {
            for (uint256 j = 0; j < lockups.length; j++) {
                uint256 mult = sapienVault.calculateMultiplier(amounts[i], lockups[j]);

                // Must be within bounds
                assert(mult >= Const.BASE_MULTIPLIER);
                assert(mult <= Const.MAX_MULTIPLIER);

                // since sapienVault.calculateMultiplier is a view function
                // it should be deterministic
                uint256 mult2 = sapienVault.calculateMultiplier(amounts[i], lockups[j]);
                assert(mult == mult2);
            }
        }
    }

    // =============================================================================
    // DETERMINISM INVARIANTS
    // =============================================================================

    /// @dev Multiplier function should be deterministic
    function invariant_multiplierDeterministic() public view {
        uint256 amount = 1000 * Const.TOKEN_DECIMALS;
        uint256 lockup = Const.LOCKUP_180_DAYS;

        uint256 mult1 = sapienVault.calculateMultiplier(amount, lockup);
        uint256 mult2 = sapienVault.calculateMultiplier(amount, lockup);

        assert(mult1 == mult2);
    }

    // =============================================================================
    // CLAMPING INVARIANTS
    // =============================================================================

    /// @dev Amount clamping should work correctly at boundaries
    function invariant_amountClamping() public view {
        uint256 lockup = Const.LOCKUP_180_DAYS;

        // Test amounts at and around the maximum
        uint256 mult2000 = sapienVault.calculateMultiplier(2000 * Const.TOKEN_DECIMALS, lockup);
        uint256 mult2250 = sapienVault.calculateMultiplier(2250 * Const.TOKEN_DECIMALS, lockup);
        uint256 mult2500 = sapienVault.calculateMultiplier(2500 * Const.TOKEN_DECIMALS, lockup);

        // Should increase up to the maximum
        assert(mult2000 <= mult2250);
        assert(mult2250 <= mult2500);

        // Test clamping above maximum
        uint256 mult5000 = sapienVault.calculateMultiplier(5000 * Const.TOKEN_DECIMALS, lockup);
        uint256 mult10000 = sapienVault.calculateMultiplier(10000 * Const.TOKEN_DECIMALS, lockup);

        // Should clamp to the same value as the maximum
        assert(mult2500 == mult5000);
        assert(mult2500 == mult10000);
    }

    /// @dev Lockup clamping should work correctly at boundaries
    function invariant_lockupClamping() public view {
        uint256 amount = 1000 * Const.TOKEN_DECIMALS;

        // Test lockups below minimum should clamp to minimum behavior
        // Note: calculateMultiplier doesn't enforce minimum, but let's test what it actually does
        uint256 mult10Days = sapienVault.calculateMultiplier(amount, 10 days);
        uint256 mult20Days = sapienVault.calculateMultiplier(amount, 20 days);
        uint256 mult30Days = sapienVault.calculateMultiplier(amount, Const.LOCKUP_30_DAYS);
        
        // Lower lockup should give lower multiplier (no clamping in calculateMultiplier)
        assert(mult10Days <= mult20Days);
        assert(mult20Days <= mult30Days);

        // Test lockups within valid range should be strictly increasing
        uint256 mult90Days = sapienVault.calculateMultiplier(amount, Const.LOCKUP_90_DAYS);
        uint256 mult180Days = sapienVault.calculateMultiplier(amount, Const.LOCKUP_180_DAYS);
        uint256 mult365Days = sapienVault.calculateMultiplier(amount, Const.LOCKUP_365_DAYS);

        assert(mult30Days < mult90Days);
        assert(mult90Days < mult180Days); 
        assert(mult180Days <= mult365Days);

        // Test clamping above maximum
        uint256 mult500Days = sapienVault.calculateMultiplier(amount, 500 days);
        uint256 mult1000Days = sapienVault.calculateMultiplier(amount, 1000 days);

        // Should clamp to the same value as the maximum
        assert(mult365Days == mult500Days);
        assert(mult365Days == mult1000Days);
    }

    // =============================================================================
    // SPECIFIC VALUE INVARIANTS
    // =============================================================================

    /// @dev Test specific amounts at boundaries
    function invariant_specificAmountBoundaries() public view {
        uint256 lockup = Const.LOCKUP_180_DAYS;

        uint256 mult1200 = sapienVault.calculateMultiplier(1200 * Const.TOKEN_DECIMALS, lockup);
        uint256 mult1800 = sapienVault.calculateMultiplier(1800 * Const.TOKEN_DECIMALS, lockup);

        // Should be monotonic
        assert(mult1200 <= mult1800);

        // Should be within bounds
        assert(mult1200 >= Const.BASE_MULTIPLIER && mult1200 <= Const.MAX_MULTIPLIER);
        assert(mult1800 >= Const.BASE_MULTIPLIER && mult1800 <= Const.MAX_MULTIPLIER);
    }

    /// @dev Maximum multiplier should be achieved at maximum inputs
    function invariant_maxMultiplierAtMaxInputs() public view {
        uint256 maxAmount = Const.MAXIMUM_STAKE_AMOUNT;
        uint256 maxLockup = Const.LOCKUP_365_DAYS;

        uint256 maxMult = sapienVault.calculateMultiplier(maxAmount, maxLockup);
        assert(maxMult == Const.MAX_MULTIPLIER);
    }

    /// @dev Base multiplier should be achieved at minimum inputs  
    function invariant_baseMultiplierAtMinInputs() public view {
        uint256 minAmount = Const.MINIMUM_STAKE_AMOUNT;
        uint256 minLockup = Const.LOCKUP_30_DAYS;

        uint256 minMult = sapienVault.calculateMultiplier(minAmount, minLockup);
        assert(minMult == Const.BASE_MULTIPLIER);
    }

    // =============================================================================
    // EDGE CASE INVARIANTS
    // =============================================================================

    /// @dev Zero amounts should be handled correctly
    function invariant_zeroAmountHandling() public view{
        uint256 lockup = Const.LOCKUP_180_DAYS;
        
        uint256 zeroMult = sapienVault.calculateMultiplier(0, lockup);
        uint256 minMult = sapienVault.calculateMultiplier(Const.MINIMUM_STAKE_AMOUNT, lockup);
        
        // Zero should clamp to minimum behavior
        assert(zeroMult == Const.BASE_MULTIPLIER);
        assert(zeroMult <= minMult);
    }

    /// @dev Extreme values should be clamped properly
    function invariant_extremeValueClamping() public view {
        uint256 extremeAmount = type(uint256).max;
        uint256 extremeLockup = type(uint256).max;
        
        uint256 extremeMult = sapienVault.calculateMultiplier(extremeAmount, extremeLockup);
        assert(extremeMult == Const.MAX_MULTIPLIER);
    }

    function test_SetupWrapper() public view {
        
        // Test that multiplier works correctly
        uint256 mult = sapienVault.calculateMultiplier(1000 * Const.TOKEN_DECIMALS, Const.LOCKUP_90_DAYS);
        assert(mult >= Const.BASE_MULTIPLIER);
        assert(mult <= Const.MAX_MULTIPLIER);
    }
}

/**
 * @title MultiplierHandler
 * @notice Handler contract for invariant testing
 * @dev Provides controlled random inputs for invariant tests
 */
contract MultiplierHandler is Test {
    
    // State variables to track for invariants
    uint256 public currentAmount;
    uint256 public currentLockup;
    uint256 public amount1;
    uint256 public amount2;
    uint256 public lockup1;
    uint256 public lockup2;
    
    // Ghost variables for statistics
    uint256 public totalCalculations;
    uint256 public validCalculations;
    uint256 public invalidCalculations;

    SapienVault public sapienVault;
    
    constructor() {
        sapienVault = new SapienVault();
    }

    /**
     * @notice Set amount for testing
     */
    function setAmount(uint256 amount) public {
        currentAmount = bound(amount, 0, 1000000 * Const.TOKEN_DECIMALS);
        totalCalculations++;
        
        try sapienVault.calculateMultiplier(currentAmount, Const.LOCKUP_30_DAYS) returns (uint256 result) {
            if (result > 0) {
                validCalculations++;
            } else {
                invalidCalculations++;
            }
        } catch {
            invalidCalculations++;
        }
    }

    /**
     * @notice Set lockup period for testing
     */
    function setLockup(uint256 lockup) public {
        currentLockup = bound(lockup, 0, 400 days);
        totalCalculations++;
        
        try sapienVault.calculateMultiplier(Const.MINIMUM_STAKE_AMOUNT, currentLockup) returns (uint256 result) {
            if (result > 0) {
                validCalculations++;
            } else {
                invalidCalculations++;
            }
        } catch {
            invalidCalculations++;
        }
    }

    /**
     * @notice Set two amounts for comparison testing
     */
    function setTwoAmounts(uint256 _amount1, uint256 _amount2) public {
        amount1 = bound(_amount1, 0, 500000 * Const.TOKEN_DECIMALS);
        amount2 = bound(_amount2, 0, 500000 * Const.TOKEN_DECIMALS);
    }

    /**
     * @notice Set two lockup periods for comparison testing
     */
    function setTwoLockups(uint256 _lockup1, uint256 _lockup2) public {
        lockup1 = bound(_lockup1, 0, 400 days);
        lockup2 = bound(_lockup2, 0, 400 days);
    }

    /**
     * @notice Perform a calculation to track statistics
     */
    function performCalculation(uint256 amount, uint256 lockup) public {
        amount = bound(amount, 0, 1000000 * Const.TOKEN_DECIMALS);
        lockup = bound(lockup, 0, 400 days);
        
        totalCalculations++;
        
        try sapienVault.calculateMultiplier(amount, lockup) returns (uint256 result) {
            if (result > 0) {
                validCalculations++;
            } else {
                invalidCalculations++;
            }
        } catch {
            invalidCalculations++;
        }
        
        currentAmount = amount;
        currentLockup = lockup;
    }

    // Getter functions for invariant testing
    function getCurrentAmount() external view returns (uint256) {
        return currentAmount;
    }

    function getCurrentLockup() external view returns (uint256) {
        return currentLockup;
    }

    function getAmount1() external view returns (uint256) {
        return amount1;
    }

    function getAmount2() external view returns (uint256) {
        return amount2;
    }

    function getLockup1() external view returns (uint256) {
        return lockup1;
    }

    function getLockup2() external view returns (uint256) {
        return lockup2;
    }

    // Helper function that implements the same logic as SapienVault's calculateMultiplier
    function calculateMultiplier(uint256 amount, uint256 effectiveLockup) external pure returns (uint256) {
        // Clamp inputs to valid ranges
        uint256 maxTokens = Const.MAXIMUM_STAKE_AMOUNT;

        if (amount > maxTokens) {
            amount = maxTokens;
        }

        if (effectiveLockup > Const.LOCKUP_365_DAYS) {
            effectiveLockup = Const.LOCKUP_365_DAYS;
        }

        // Calculate bonus with single division to minimize precision loss
        uint256 bonus = (effectiveLockup * amount * Const.MAX_BONUS) / (Const.LOCKUP_365_DAYS * maxTokens);

        return Const.BASE_MULTIPLIER + bonus;
    }
} 