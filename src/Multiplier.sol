// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Constants as Const} from "src/utils/Constants.sol";
import {IMultiplier} from "src/interfaces/IMultiplier.sol";

/// @title Multiplier - Sapien AI Staking Multiplier Calculator
/// @notice Handles all multiplier calculations for the Sapien staking system
contract Multiplier is IMultiplier {
    
    // -------------------------------------------------------------
    // Core Multiplier Functions
    // -------------------------------------------------------------

    /**
     * @notice Get base multiplier for a specific lock-up period
     * @param lockUpPeriod The lock-up period in seconds
     * @return multiplier The base multiplier for the period
     */
    function getMultiplierForPeriod(uint256 lockUpPeriod) external pure returns (uint256 multiplier) {
        return _getMultiplierForPeriod(lockUpPeriod);
    }

    /**
     * @notice Internal function to get base multiplier for a specific lock-up period
     * @param lockUpPeriod The lock-up period in seconds
     * @return multiplier The base multiplier for the period
     */
    function _getMultiplierForPeriod(uint256 lockUpPeriod) internal pure returns (uint256 multiplier) {
        // Validate lockup period is within bounds
        if (lockUpPeriod < Const.LOCKUP_30_DAYS || lockUpPeriod > Const.LOCKUP_365_DAYS) {
            return 0;
        }

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

        // For non-discrete periods, use linear interpolation
        // Formula: min + (period - minPeriod) * (max - min) / (maxPeriod - minPeriod)
        uint256 numerator = (lockUpPeriod - Const.LOCKUP_30_DAYS) * 
            (Const.MAX_MULTIPLIER - Const.MIN_MULTIPLIER);
        uint256 denominator = Const.LOCKUP_365_DAYS - Const.LOCKUP_30_DAYS;
        
        return Const.MIN_MULTIPLIER + (numerator / denominator);
    }

    /**
     * @notice Calculate linear weighted multiplier that includes both time and amount factors plus global coefficient
     * @param amount The total staked amount
     * @param effectiveLockup The effective lockup period
     * @param totalStaked Total amount staked in the vault
     * @param totalSupply Total supply of tokens
     * @return The calculated final multiplier including global effects
     */
    function calculateLinearWeightedMultiplier(
        uint256 amount, 
        uint256 effectiveLockup,
        uint256 totalStaked,
        uint256 totalSupply
    ) external pure returns (uint256) {
        // Calculate individual multiplier (base + time bonus + amount bonus)
        uint256 individualMultiplier = calculateIndividualMultiplier(amount, effectiveLockup);

        // Calculate global staking coefficient based on network participation
        uint256 globalCoefficient = calculateGlobalCoefficient(totalStaked, totalSupply);

        // Apply global coefficient to individual multiplier
        return (individualMultiplier * globalCoefficient) / 10000;
    }

    /**
     * @notice Calculate individual multiplier based on time and amount factors
     * @param amount The staked amount
     * @param effectiveLockup The effective lockup period
     * @return The individual multiplier before global effects
     */
    function calculateIndividualMultiplier(uint256 amount, uint256 effectiveLockup) public pure returns (uint256) {
        uint256 base = Const.BASE_MULTIPLIER; // 10000 (100%)

        // Time factor: Linear from 0 to 1 based on duration (max 365 days)
        uint256 timeFactor = (effectiveLockup * 10000) / Const.LOCKUP_365_DAYS;
        if (timeFactor > 10000) timeFactor = 10000; // Cap at 1.0

        // Time bonus: 0% to 25% based on duration
        uint256 timeBonus = (timeFactor * 2500) / 10000; // Max 2500 basis points (25%)

        // Amount factor: Logarithmic from 0 to 1 based on stake size
        uint256 amountFactor = calculateAmountFactor(amount);

        // Amount bonus: 0% to 25% based on stake size
        uint256 amountBonus = (amountFactor * 2500) / 10000; // Max 2500 basis points (25%)

        return base + timeBonus + amountBonus;
    }

    /**
     * @notice Approximate log10 function for integer values
     * @param value The input value
     * @return The approximate log10 * 1000 for precision
     */
    function approximateLog10(uint256 value) public pure returns (uint256) {
        if (value <= 1) return 0;
        if (value < 10) return 1000; // log10(1-9) ≈ 0-1
        if (value < 100) return 2000; // log10(10-99) ≈ 1-2
        if (value < 1000) return 3000; // log10(100-999) ≈ 2-3
        if (value < 10000) return 4000; // log10(1000-9999) ≈ 3-4
        if (value < 100000) return 5000; // log10(10000+) ≈ 4+
        return 6000; // Cap for very large values
    }

    /**
     * @notice Calculate global staking coefficient based on network participation
     * @param totalStaked Total amount staked in the vault
     * @param totalSupply Total supply of tokens
     * @return The global coefficient (5000-15000, representing 0.5x to 1.5x)
     */
    function calculateGlobalCoefficient(uint256 totalStaked, uint256 totalSupply) public pure returns (uint256) {
        if (totalSupply == 0) return 10000; // Safety check

        // Calculate staking ratio in basis points (0-10000)
        uint256 stakingRatio = (totalStaked * 10000) / totalSupply;

        return calculateSigmoidCoefficient(stakingRatio);
    }

    /**
     * @notice Calculate sigmoid-based coefficient for optimal staking participation
     * @param stakingRatio The ratio of staked tokens to total supply (in basis points)
     * @return The coefficient (5000-15000, representing 0.5x to 1.5x)
     */
    function calculateSigmoidCoefficient(uint256 stakingRatio) public pure returns (uint256) {
        if (stakingRatio <= 1000) {
            // 0-10% staked: Linear growth from 0.5x to 1.0x
            // Coefficient = 5000 + (stakingRatio * 5000) / 1000
            return 5000 + (stakingRatio * 5000) / 1000;
        } else if (stakingRatio <= 5000) {
            // 10-50% staked: Optimal zone, 1.0x to 1.5x
            // Coefficient = 10000 + ((stakingRatio - 1000) * 5000) / 4000
            return 10000 + ((stakingRatio - 1000) * 5000) / 4000;
        } else {
            // 50%+ staked: Diminishing returns, 1.5x down to 1.0x
            // Coefficient = 15000 - ((stakingRatio - 5000) * 5000) / 5000
            uint256 excess = stakingRatio - 5000;
            if (excess >= 5000) {
                return 10000; // Cap at 1.0x when 100% staked
            }
            return 15000 - (excess * 5000) / 5000;
        }
    }

    /**
     * @notice Get detailed multiplier breakdown for a given amount and duration
     * @param amount The stake amount
     * @param duration The lockup duration
     * @param totalStaked Total amount staked in the vault
     * @param totalSupply Total supply of tokens
     * @return individualMultiplier The multiplier before global effects
     * @return globalCoefficient The current global coefficient
     * @return finalMultiplier The final multiplier after global effects
     * @return stakingRatio Current network staking ratio (basis points)
     */
    function getMultiplierBreakdown(
        uint256 amount, 
        uint256 duration,
        uint256 totalStaked,
        uint256 totalSupply
    ) external pure returns (
        uint256 individualMultiplier, 
        uint256 globalCoefficient, 
        uint256 finalMultiplier, 
        uint256 stakingRatio
    ) {
        individualMultiplier = calculateIndividualMultiplier(amount, duration);
        globalCoefficient = calculateGlobalCoefficient(totalStaked, totalSupply);
        finalMultiplier = (individualMultiplier * globalCoefficient) / 10000;
        stakingRatio = (totalStaked * 10000) / totalSupply;
    }

    /**
     * @notice Validates that a lockup period is supported
     * @param lockUpPeriod The lockup period to validate
     * @return isValid Whether the lockup period is valid
     */
    function isValidLockupPeriod(uint256 lockUpPeriod) external pure returns (bool isValid) {
        return _getMultiplierForPeriod(lockUpPeriod) > 0;
    }

    /**
     * @notice Calculate amount factor using logarithmic scaling
     * @param amount The staked amount
     * @return The amount factor (0 to 10000, representing 0.0 to 1.0)
     */
    function calculateAmountFactor(uint256 amount) public pure returns (uint256) {
        if (amount <= Const.MINIMUM_STAKE_AMOUNT) {
            return 0;
        }

        uint256 minStake = Const.MINIMUM_STAKE_AMOUNT;
        uint256 maxAmount = 10_000_000 * Const.TOKEN_DECIMALS; // 10M tokens cap

        // Prevent overflow and ensure we're within reasonable bounds
        if (amount >= maxAmount) {
            return 10000; // 1.0
        }

        // Logarithmic calculation: log10(amount/minStake) / log10(maxAmount/minStake)
        // Since we can't do floating point math, we use integer approximation

        // Calculate ratio = amount / minStake
        uint256 ratio = amount / minStake;

        // Approximate log10 using lookup table for common values
        uint256 logRatio = approximateLog10(ratio);
        uint256 logMax = approximateLog10(maxAmount / minStake); // log10(10000) = 4.0

        // Return factor as basis points (0-10000)
        return (logRatio * 10000) / logMax;
    }

    function calculateMultiplier(uint256 amount, uint256 effectiveLockup) public pure returns (uint256) {
        // Calculate base multiplier from lockup period (amount_from_duration)
        uint256 baseMultiplier = _getMultiplierForPeriod(effectiveLockup);
        
        // Calculate amount scaling factor: max(1, user_staked_amount / MAX_STAKE_TIER_AMOUNT)
        // Using basis points for precision: multiply by 10000, then divide by 10000 at the end
        uint256 amountScalingFactor = (amount * 10000) / Const.MAX_STAKE_TIER_AMOUNT;
        
        // Ensure minimum scaling factor of 1.0 (10000 basis points)
        if (amountScalingFactor < 10000) {
            amountScalingFactor = 10000;
        }
        
        // Apply formula: multiplier = amount_from_duration * max(1, (user_staked_amount / MAX_STAKE_TIER_AMOUNT))
        return (baseMultiplier * amountScalingFactor) / 10000;
    }
}
