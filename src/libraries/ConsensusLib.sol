// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IConsensusAlgorithm} from "../interface/IConsensusAlgorithm.sol";

/**
 * @title ConsensusLib
 * @notice Shared utilities for consensus algorithm implementations
 * @dev Provides common calculations used across multiple algorithms
 */
library ConsensusLib {
    // ============================================
    // ERRORS
    // ============================================

    error NoValidations();
    error DivisionByZero();
    error LengthMismatch();

    // ============================================
    // CORE CALCULATIONS
    // ============================================

    /**
     * @notice Calculate weighted average from scores and weights
     * @param scores Array of validation scores
     * @param weights Array of validator weights
     * @return Weighted average score
     */
    function calculateWeightedAverage(uint256[] memory scores, uint256[] memory weights)
        internal
        pure
        returns (uint256)
    {
        uint256 len = scores.length;
        if (len != weights.length) revert LengthMismatch();
        if (len == 0) revert NoValidations();

        uint256 totalWeightedScore = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < len;) {
            totalWeightedScore += scores[i] * weights[i];
            totalWeight += weights[i];
            unchecked {
                ++i;
            }
        }

        if (totalWeight == 0) revert DivisionByZero();

        return totalWeightedScore / totalWeight;
    }

    /**
     * @notice Calculate standard deviation from scores and weights
     * @param scores Array of validation scores
     * @param weights Array of validator weights
     * @param mean The weighted mean
     * @return Standard deviation
     */
    function calculateStandardDeviation(uint256[] memory scores, uint256[] memory weights, uint256 mean)
        internal
        pure
        returns (uint256)
    {
        uint256 len = scores.length;
        if (len != weights.length) revert LengthMismatch();
        if (len == 0) return 0;

        uint256 sumWeightedSquaredDiff = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < len;) {
            uint256 score = scores[i];
            uint256 weight = weights[i];

            // Calculate (score - mean)²
            uint256 diff = score > mean ? score - mean : mean - score;
            uint256 squaredDiff = diff * diff;

            // Weight by stake
            sumWeightedSquaredDiff += squaredDiff * weight;
            totalWeight += weight;
            unchecked {
                ++i;
            }
        }

        if (totalWeight == 0) return 0;

        // Weighted variance
        uint256 variance = sumWeightedSquaredDiff / totalWeight;

        // Standard deviation = sqrt(variance)
        return sqrt(variance);
    }

    /**
     * @notice Identify outliers and calculate slash amounts
     * @param validations Array of validation inputs
     * @param mean Weighted average score
     * @param stdDev Standard deviation
     * @return validatorsToSlash Array of validator addresses to slash
     * @return slashAmounts Corresponding slash amounts
     */
    function identifyOutliers(IConsensusAlgorithm.ValidationInput[] memory validations, uint256 mean, uint256 stdDev)
        internal
        pure
        returns (address[] memory validatorsToSlash, uint256[] memory slashAmounts)
    {
        uint256 outlierCount = _countOutliers(validations, mean, stdDev);

        validatorsToSlash = new address[](outlierCount);
        slashAmounts = new uint256[](outlierCount);

        _fillOutlierArrays(validations, mean, stdDev, validatorsToSlash, slashAmounts);
    }

    /**
     * @dev Count the number of outliers in validations
     * @param validations Array of validation inputs
     * @param mean Weighted average score
     * @param stdDev Standard deviation
     * @return count Number of outliers found
     */
    function _countOutliers(IConsensusAlgorithm.ValidationInput[] memory validations, uint256 mean, uint256 stdDev)
        internal
        pure
        returns (uint256 count)
    {
        uint256 absoluteThreshold = 1500;
        for (uint256 i = 0; i < validations.length; i++) {
            uint256 deviation = validations[i].score > mean ? validations[i].score - mean : mean - validations[i].score;
            if (deviation > absoluteThreshold || (stdDev > 0 && deviation > 2 * stdDev)) {
                count++;
            }
        }
    }

    /**
     * @dev Fill arrays with outlier validator addresses and their slash amounts
     * @param validations Array of validation inputs
     * @param mean Weighted average score
     * @param stdDev Standard deviation
     * @param validatorsToSlash Array to fill with outlier validator addresses
     * @param slashAmounts Array to fill with corresponding slash amounts
     */
    function _fillOutlierArrays(
        IConsensusAlgorithm.ValidationInput[] memory validations,
        uint256 mean,
        uint256 stdDev,
        address[] memory validatorsToSlash,
        uint256[] memory slashAmounts
    ) internal pure {
        uint256 absoluteThreshold = 1500;
        uint256 index = 0;
        for (uint256 i = 0; i < validations.length; i++) {
            uint256 score = validations[i].score;
            uint256 deviation = score > mean ? score - mean : mean - score;

            if (deviation > absoluteThreshold || (stdDev > 0 && deviation > 2 * stdDev)) {
                validatorsToSlash[index] = validations[i].validator;
                uint256 effectiveStdDev = _calculateEffectiveStdDev(deviation, stdDev);
                slashAmounts[index] = calculateSlashAmount(validations[i].stakeAmount, deviation, effectiveStdDev);
                index++;
            }
        }
    }

    /**
     * @dev Calculate effective standard deviation for slash calculation
     * @param deviation Absolute deviation from mean
     * @param stdDev Standard deviation
     * @return Effective standard deviation adjusted for deviation severity
     */
    function _calculateEffectiveStdDev(uint256 deviation, uint256 stdDev) internal pure returns (uint256) {
        if (deviation > 5000) {
            uint256 eff = deviation / 6;
            return eff < 600 ? 600 : eff;
        } else if (deviation > 3300) {
            uint256 eff = deviation / 4;
            return eff < 700 ? 700 : eff;
        } else if (stdDev > 2000) {
            uint256 eff = deviation / 3;
            return eff < 800 ? 800 : eff;
        } else if (stdDev < 500) {
            return 500;
        }
        return stdDev;
    }

    /**
     * @notice Calculate slash amount based on deviation severity
     * @param stakeAmount Amount staked by validator
     * @param deviation Absolute deviation from mean
     * @param stdDev Standard deviation
     * @return Slash amount
     */
    function calculateSlashAmount(uint256 stakeAmount, uint256 deviation, uint256 stdDev)
        internal
        pure
        returns (uint256)
    {
        if (stdDev == 0) return 0;

        // Calculate how many standard deviations away
        // Multiply by 100 for precision: 200 = 2σ, 300 = 3σ, etc.
        uint256 sigmaMultiple = (deviation * 100) / stdDev;

        // Determine slash percentage based on severity
        uint256 slashPercentage;

        if (sigmaMultiple >= 500) {
            slashPercentage = 10000; // 100% - extreme outlier (5σ+)
        } else if (sigmaMultiple >= 400) {
            slashPercentage = 7500; // 75% - very extreme (4σ-5σ)
        } else if (sigmaMultiple >= 300) {
            slashPercentage = 5000; // 50% - significant (3σ-4σ)
        } else if (sigmaMultiple >= 200) {
            slashPercentage = 2500; // 25% - moderate (2σ-3σ)
        } else if (sigmaMultiple >= 150) {
            slashPercentage = 1000; // 10% - mild outlier (1.5σ-2σ)
        } else {
            return 0; // Less than 1.5σ, no slash
        }

        // Calculate slash amount
        return (stakeAmount * slashPercentage) / 10000;
    }

    /**
     * @notice Calculate square root using Babylonian method
     * @param x The number to find square root of
     * @return y The square root of x
     */
    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;

        // Start with an initial guess
        uint256 z = (x + 1) / 2;
        y = x;

        // Iterate until convergence
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }

        return y;
    }

    // ============================================
    // WEIGHT CALCULATION
    // ============================================

    /// @notice Minimum reputation floor to prevent zero-weight validators (10% of max)
    uint256 public constant MIN_REPUTATION_FLOOR = 1000;

    /**
     * @notice Calculate base weight for a validator using stake × reputation
     * @dev This is the core weight calculation used by consensus algorithms and reward distribution
     *      Applies reputation floor to prevent zero-weight validators
     * @param stakeAmount Amount staked by validator
     * @param reputation Validator's reputation score (0-10000)
     * @return weight = stake × effective_reputation / 10000
     */
    function calculateBaseWeight(uint256 stakeAmount, uint256 reputation) internal pure returns (uint256) {
        // Apply reputation floor to prevent zero-weight validators
        uint256 effectiveRep = reputation < MIN_REPUTATION_FLOOR ? MIN_REPUTATION_FLOOR : reputation;

        // Weight = stake × reputation / 10000
        // This normalizes reputation (0-10000) to a multiplier (0-1)
        // Example: 100 stake × 5000 rep = 50 weight
        // Example: 100 stake × 10000 rep = 100 weight
        return (stakeAmount * effectiveRep) / 10000;
    }

    // ============================================
    // WEIGHT CAPPING
    // ============================================

    /// @notice Maximum number of capping iterations to prevent unbounded loops
    uint256 internal constant MAX_CAP_ITERATIONS = 10;

    /**
     * @notice Apply a per-validator weight cap using iterative redistribution
     * @dev Iteratively clamps any validator whose weight exceeds `maxBps` of total weight.
     *      When a validator is capped, their excess weight is effectively removed, which
     *      changes the total and may cause a previously-under-cap validator to now exceed
     *      the threshold. The algorithm iterates until no validator exceeds the cap or
     *      MAX_CAP_ITERATIONS is reached.
     *
     *      Algorithm:
     *      1. Compute totalWeight from current weights
     *      2. For each weight > totalWeight * maxBps / 10000, clamp it
     *      3. Recompute totalWeight and repeat if any weight was clamped
     *
     * @param weights Array of validator weights (modified in place)
     * @param maxBps Maximum weight as basis points of total (e.g. 3000 = 30%)
     */
    function applyCap(uint256[] memory weights, uint256 maxBps) internal pure {
        uint256 len = weights.length;
        if (len <= 1) return; // No capping needed for single validator

        for (uint256 iter = 0; iter < MAX_CAP_ITERATIONS; iter++) {
            // Compute current total
            uint256 totalWeight = 0;
            for (uint256 i = 0; i < len; i++) {
                totalWeight += weights[i];
            }
            if (totalWeight == 0) return;

            // Find and clamp overweight validators
            bool changed = false;
            for (uint256 i = 0; i < len; i++) {
                uint256 maxAllowed = (totalWeight * maxBps) / 10000;
                if (weights[i] > maxAllowed) {
                    weights[i] = maxAllowed > 0 ? maxAllowed : 1;
                    changed = true;
                }
            }

            // If no weights were clamped, we've converged
            if (!changed) return;
        }
    }
}
