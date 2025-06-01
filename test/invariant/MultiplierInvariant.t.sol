// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {StdInvariant} from "lib/forge-std/src/StdInvariant.sol";
import {Multiplier} from "src/Multiplier.sol";
import {Constants as Const} from "src/utils/Constants.sol";

/**
 * @title MultiplierInvariant
 * @notice Invariant tests for the Multiplier contract
 * @dev Tests mathematical properties that should always hold true
 */
contract MultiplierInvariant is StdInvariant, Test {
    Multiplier public multiplier;
    MultiplierHandler public handler;

    function setUp() public {
        multiplier = new Multiplier();
        handler = new MultiplierHandler(multiplier);
        
        // Set the handler as the target for invariant testing
        targetContract(address(handler));
    }

    // =============================================================================
    // INVARIANT TESTS
    // =============================================================================

    /**
     * @notice Monotonicity invariant for amounts
     * @dev Higher amounts should always result in equal or higher multipliers
     */
    function invariant_MonotonicityByAmount() public view {
        uint256 amount1 = handler.getAmount1();
        uint256 amount2 = handler.getAmount2();
        uint256 lockup = handler.getCurrentLockup();
        
        // Skip if either amount is invalid
        if (amount1 < Const.MINIMUM_STAKE_AMOUNT || amount2 < Const.MINIMUM_STAKE_AMOUNT) {
            return;
        }
        
        // Skip if lockup is invalid
        if (lockup < Const.LOCKUP_30_DAYS || lockup > Const.LOCKUP_365_DAYS) {
            return;
        }
        
        uint256 mult1 = multiplier.calculateMultiplier(amount1, lockup);
        uint256 mult2 = multiplier.calculateMultiplier(amount2, lockup);
        
        // If amount1 <= amount2, then mult1 <= mult2
        if (amount1 <= amount2) {
            assertLe(mult1, mult2, "Higher amounts should have equal or higher multipliers");
        }
    }

    /**
     * @notice Monotonicity invariant for lockup periods
     * @dev Longer lockup periods should always result in equal or higher multipliers
     */
    function invariant_MonotonicityByLockup() public view {
        uint256 amount = handler.getCurrentAmount();
        uint256 lockup1 = handler.getLockup1();
        uint256 lockup2 = handler.getLockup2();
        
        // Skip if amount is invalid
        if (amount < Const.MINIMUM_STAKE_AMOUNT) {
            return;
        }
        
        // Skip if either lockup is invalid
        if (lockup1 < Const.LOCKUP_30_DAYS || lockup1 > Const.LOCKUP_365_DAYS ||
            lockup2 < Const.LOCKUP_30_DAYS || lockup2 > Const.LOCKUP_365_DAYS) {
            return;
        }
        
        uint256 mult1 = multiplier.calculateMultiplier(amount, lockup1);
        uint256 mult2 = multiplier.calculateMultiplier(amount, lockup2);
        
        // If lockup1 <= lockup2, then mult1 <= mult2
        if (lockup1 <= lockup2) {
            assertLe(mult1, mult2, "Longer lockup periods should have equal or higher multipliers");
        }
    }

    /**
     * @notice Boundary invariant for multiplier values
     * @dev Valid multipliers should always be within expected bounds
     */
    function invariant_MultiplierBounds() public view {
        uint256 amount = handler.getCurrentAmount();
        uint256 lockup = handler.getCurrentLockup();
        
        uint256 mult = multiplier.calculateMultiplier(amount, lockup);
        
        if (amount >= Const.MINIMUM_STAKE_AMOUNT && 
            lockup >= Const.LOCKUP_30_DAYS && 
            lockup <= Const.LOCKUP_365_DAYS) {
            // Valid inputs should produce multipliers in expected range
            assertGe(mult, Const.MIN_MULTIPLIER, "Valid multiplier should be >= MIN_MULTIPLIER (1.05x)");
            assertLe(mult, 19500, "Valid multiplier should be <= 19500 (1.95x max)"); // Max possible: 1.50x + 0.45x
        } else {
            // Invalid inputs should return 0
            assertEq(mult, 0, "Invalid inputs should return 0 multiplier");
        }
    }

    /**
     * @notice Consistency invariant
     * @dev Same inputs should always produce same outputs
     */
    function invariant_Consistency() public view {
        uint256 amount = handler.getCurrentAmount();
        uint256 lockup = handler.getCurrentLockup();
        
        uint256 mult1 = multiplier.calculateMultiplier(amount, lockup);
        uint256 mult2 = multiplier.calculateMultiplier(amount, lockup);
        
        assertEq(mult1, mult2, "Same inputs should always produce same outputs");
    }

    /**
     * @notice Tier boundary invariant
     * @dev Multipliers should increase exactly at tier boundaries
     */
    function invariant_TierBoundaries() public view {
        uint256 lockup = Const.LOCKUP_365_DAYS; // Use max lockup to see full tier effect
        
        // Test key tier boundaries (based on actual tier logic)
        // Tier 0 (≤1000) vs Tier 1 (1001-2499): boundary is 1000 to 1001
        uint256 mult1000 = multiplier.calculateMultiplier(1000 * Const.TOKEN_DECIMALS, lockup);
        uint256 mult1001 = multiplier.calculateMultiplier(1001 * Const.TOKEN_DECIMALS, lockup);
        
        // Tier 1 (1001-2499) vs Tier 2 (2500-4999): boundary is 2499 to 2500
        uint256 mult2499 = multiplier.calculateMultiplier(2499 * Const.TOKEN_DECIMALS, lockup);
        uint256 mult2500 = multiplier.calculateMultiplier(2500 * Const.TOKEN_DECIMALS, lockup);
        
        // At tier boundaries, multiplier should increase
        if (mult1000 > 0 && mult1001 > 0) {
            assertLt(mult1000, mult1001, "Multiplier should increase when crossing from 1000 to 1001 tokens");
        }
        
        if (mult2499 > 0 && mult2500 > 0) {
            assertLt(mult2499, mult2500, "Multiplier should increase when crossing from 2499 to 2500 tokens");
        }
    }

    /**
     * @notice Interpolation continuity invariant
     * @dev Linear interpolation should produce continuous results
     */
    function invariant_InterpolationContinuity() public view {
        uint256 amount = handler.getCurrentAmount();
        
        // Skip if amount is invalid
        if (amount < Const.MINIMUM_STAKE_AMOUNT) {
            return;
        }
        
        // Test continuity between interpolation ranges
        uint256 mult89Days = multiplier.calculateMultiplier(amount, 89 days);
        uint256 mult90Days = multiplier.calculateMultiplier(amount, 90 days);
        uint256 mult91Days = multiplier.calculateMultiplier(amount, 91 days);
        
        if (mult89Days > 0 && mult90Days > 0 && mult91Days > 0) {
            // The change should be gradual and consistent
            uint256 diff1 = mult90Days - mult89Days;
            uint256 diff2 = mult91Days - mult90Days;
            
            // Allow for rounding differences but should be similar
            assertApproxEqAbs(diff1, diff2, 10, "Interpolation should be approximately linear");
        }
    }

    /**
     * @notice Amount tier consistency invariant
     * @dev Within the same tier, only duration should affect multiplier
     */
    function invariant_TierConsistency() public view {
        uint256 lockup = handler.getCurrentLockup();
        
        // Skip if lockup is invalid
        if (lockup < Const.LOCKUP_30_DAYS || lockup > Const.LOCKUP_365_DAYS) {
            return;
        }
        
        // Test two amounts in the same tier (e.g., 1200 and 1800 both in tier 1)
        uint256 mult1200 = multiplier.calculateMultiplier(1200 * Const.TOKEN_DECIMALS, lockup);
        uint256 mult1800 = multiplier.calculateMultiplier(1800 * Const.TOKEN_DECIMALS, lockup);
        
        if (mult1200 > 0 && mult1800 > 0) {
            assertEq(mult1200, mult1800, "Amounts in same tier should have same multiplier");
        }
    }

    /**
     * @notice Maximum multiplier invariant
     * @dev The highest possible multiplier should be achieved with max amount and max lockup
     */
    function invariant_MaximumMultiplier() public view {
        uint256 maxAmount = 100000 * Const.TOKEN_DECIMALS; // Well above highest tier
        uint256 maxLockup = Const.LOCKUP_365_DAYS;
        
        uint256 maxMult = multiplier.calculateMultiplier(maxAmount, maxLockup);
        
        // Should be 1.95x (19500 basis points)
        assertEq(maxMult, 19500, "Maximum multiplier should be 1.95x (19500 basis points)");
    }

    /**
     * @notice Minimum multiplier invariant  
     * @dev The lowest possible multiplier should be achieved with min amount and min lockup
     */
    function invariant_MinimumMultiplier() public view {
        uint256 minAmount = Const.MINIMUM_STAKE_AMOUNT;
        uint256 minLockup = Const.LOCKUP_30_DAYS;
        
        uint256 minMult = multiplier.calculateMultiplier(minAmount, minLockup);
        
        // Should be 1.05x (10500 basis points)
        assertEq(minMult, 10500, "Minimum multiplier should be 1.05x (10500 basis points)");
    }
}

/**
 * @title MultiplierHandler
 * @notice Handler contract for invariant testing
 * @dev Provides controlled random inputs for invariant tests
 */
contract MultiplierHandler is Test {
    Multiplier public multiplier;
    
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

    constructor(Multiplier _multiplier) {
        multiplier = _multiplier;
    }

    /**
     * @notice Set amount for testing
     */
    function setAmount(uint256 amount) public {
        currentAmount = bound(amount, 0, 1000000 * Const.TOKEN_DECIMALS);
        totalCalculations++;
        
        uint256 result = multiplier.calculateMultiplier(currentAmount, Const.LOCKUP_30_DAYS);
        if (result > 0) {
            validCalculations++;
        } else {
            invalidCalculations++;
        }
    }

    /**
     * @notice Set lockup period for testing
     */
    function setLockup(uint256 lockup) public {
        currentLockup = bound(lockup, 0, 400 days);
        totalCalculations++;
        
        uint256 result = multiplier.calculateMultiplier(Const.MINIMUM_STAKE_AMOUNT, currentLockup);
        if (result > 0) {
            validCalculations++;
        } else {
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
        uint256 result = multiplier.calculateMultiplier(amount, lockup);
        
        if (result > 0) {
            validCalculations++;
        } else {
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
} 