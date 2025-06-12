// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/**
 * @title Multiplier - Sapien AI Staking Multiplier Calculator
 * @notice Handles all multiplier calculations for the Sapien staking system
 * @dev Multiplier Calculation Formula:
 *
 * Final Multiplier = Duration Base Multiplier + Amount Tier Bonus
 *
 * Duration Base Multipliers:
 * - 30 days:  1.05x (10500 basis points)
 * - 90 days:  1.10x (11000 basis points)
 * - 180 days: 1.25x (12500 basis points)
 * - 365 days: 1.50x (15000 basis points)
 *
 * Amount Tier Bonuses (0% to 45% of base range):
 * - Tier 1 (1K-2.5K):   +20% of 0.45x = +0.09x
 * - Tier 2 (2.5K-5K):   +40% of 0.45x = +0.18x
 * - Tier 3 (5K-7.5K):   +60% of 0.45x = +0.27x
 * - Tier 4 (7.5K-10K):  +80% of 0.45x = +0.36x
 * - Tier 5 (10K+):      +100% of 0.45x = +0.45x
 *
 * Example Multiplier Matrix (calculated values):
 * ┌─────────────┬──────┬─────────┬─────────┬─────────┬──────────┬──────┐
 * │ Time Period │ ≤1K  │ 1K-2.5K │ 2.5K-5K │ 5K-7.5K │ 7.5K-10K │ 10K+ │
 * ├─────────────┼──────┼─────────┼─────────┼─────────┼──────────┼──────┤
 * │ 30 days     │ 1.05x│ 1.14x   │ 1.23x   │ 1.32x   │ 1.41x    │ 1.50x│
 * │ 90 days     │ 1.10x│ 1.19x   │ 1.28x   │ 1.37x   │ 1.46x    │ 1.55x│
 * │ 180 days    │ 1.25x│ 1.34x   │ 1.43x   │ 1.52x   │ 1.61x    │ 1.70x│
 * │ 365 days    │ 1.50x│ 1.59x   │ 1.68x   │ 1.77x   │ 1.86x    │ 1.95x│
 * └─────────────┴──────┴─────────┴─────────┴─────────┴──────────┴──────┘
 */
import {Constants as Const} from "src/utils/Constants.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";

library Multiplier {
    // -------------------------------------------------------------
    // Core Multiplier Functions
    // -------------------------------------------------------------

    function calculateMultiplier(uint256 amount, uint256 lockUpPeriod) internal pure returns (uint256) {
        // Validate inputs and revert with specific errors
        if (lockUpPeriod < Const.LOCKUP_30_DAYS || lockUpPeriod > Const.LOCKUP_365_DAYS) {
            revert ISapienVault.InvalidLockupPeriod();
        }
        if (amount < Const.MINIMUM_STAKE_AMOUNT) {
            revert ISapienVault.MinimumStakeAmountRequired();
        }

        // Get base duration multiplier using existing discrete values
        uint256 durationMultiplier = getDurationMultiplier(lockUpPeriod);

        // Get amount tier factor (0 to 10000 basis points)
        uint256 amountTierFactor = getAmountTierFactor(amount);

        // Combine duration and amount factors
        // Formula: base_duration_multiplier + (amount_tier_factor * additional_multiplier_range / BASIS_POINTS)
        // This adds up to 4500 basis points (0.45x) based on amount tier
        uint256 additionalMultiplier =
            (amountTierFactor * (Const.MAX_MULTIPLIER - Const.MIN_MULTIPLIER)) / Const.BASIS_POINTS;

        return durationMultiplier + additionalMultiplier;
    }

    /**
     * @notice Get duration-based multiplier using existing discrete values
     * @param lockUpPeriod The lock-up period in seconds
     * @return multiplier The base multiplier for the duration
     */
    function getDurationMultiplier(uint256 lockUpPeriod) internal pure returns (uint256 multiplier) {
        // Check for exact discrete periods first
        if (lockUpPeriod == Const.LOCKUP_30_DAYS) {
            return Const.MIN_MULTIPLIER; // 10500 (1.05x)
        } else if (lockUpPeriod == Const.LOCKUP_90_DAYS) {
            return Const.MULTIPLIER_90_DAYS; // 11000 (1.10x)
        } else if (lockUpPeriod == Const.LOCKUP_180_DAYS) {
            return Const.MULTIPLIER_180_DAYS; // 12500 (1.25x)
        } else if (lockUpPeriod == Const.LOCKUP_365_DAYS) {
            return Const.MAX_MULTIPLIER; // 15000 (1.50x)
        }

        // For non-discrete periods, use linear interpolation between known points
        if (lockUpPeriod < Const.LOCKUP_90_DAYS) {
            // Interpolate between 30 and 90 days
            return interpolate(
                lockUpPeriod, Const.LOCKUP_30_DAYS, Const.LOCKUP_90_DAYS, Const.MIN_MULTIPLIER, Const.MULTIPLIER_90_DAYS
            );
        } else if (lockUpPeriod < Const.LOCKUP_180_DAYS) {
            // Interpolate between 90 and 180 days
            return interpolate(
                lockUpPeriod,
                Const.LOCKUP_90_DAYS,
                Const.LOCKUP_180_DAYS,
                Const.MULTIPLIER_90_DAYS,
                Const.MULTIPLIER_180_DAYS
            );
        } else {
            // Interpolate between 180 and 365 days
            return interpolate(
                lockUpPeriod,
                Const.LOCKUP_180_DAYS,
                Const.LOCKUP_365_DAYS,
                Const.MULTIPLIER_180_DAYS,
                Const.MAX_MULTIPLIER
            );
        }
    }

    /**
     * @notice Get amount tier factor based on stake amount
     * @param amount The staked amount
     * @return factor The tier factor (0 to 10000 basis points)
     */
    function getAmountTierFactor(uint256 amount) internal pure returns (uint256 factor) {
        uint256 tierAmount = amount / Const.TOKEN_DECIMALS;

        if (tierAmount < Const.TIER_1_THRESHOLD) {
            return 0; // Tier 0: 0% (up to 999 tokens) Unreachable due to MINIMUM_STAKE_AMOUNT = 1000
        } else if (tierAmount < Const.TIER_2_THRESHOLD) {
            return 2000; // Tier 1: 20% (1000-2499 tokens)
        } else if (tierAmount < Const.TIER_3_THRESHOLD) {
            return 4000; // Tier 2: 40% (2500-4999 tokens)
        } else if (tierAmount < Const.TIER_4_THRESHOLD) {
            return 6000; // Tier 3: 60% (5000-7499 tokens)
        } else if (tierAmount < Const.TIER_5_THRESHOLD) {
            return 8000; // Tier 4: 80% (7500-9999 tokens)
        } else {
            return 10000; // Tier 5: 100% (10000+ tokens)
        }
    }

    /**
     * @notice Linear interpolation helper function
     * @param x The input value
     * @param x1 The lower bound input
     * @param x2 The upper bound input
     * @param y1 The lower bound output
     * @param y2 The upper bound output
     * @return The interpolated value
     */
    function interpolate(uint256 x, uint256 x1, uint256 x2, uint256 y1, uint256 y2) internal pure returns (uint256) {
        // Required validation: x2 must be greater than x1
        require(x2 > x1, "Multiplier: x2 must be greater than x1");

        // Optional validations for additional safety
        require(y2 >= y1, "Multiplier: y2 must be greater than or equal to y1");
        require(x >= x1 && x <= x2, "Multiplier: x must be between x1 and x2 (inclusive)");

        return y1 + ((x - x1) * (y2 - y1)) / (x2 - x1);
    }
}
