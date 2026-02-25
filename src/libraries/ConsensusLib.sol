// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {ValidationInput, ConsensusResult} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ConsensusLib
/// @notice Library for stake-weighted consensus computation with outlier detection
/// @dev Implements weighted average, standard deviation, outlier detection, and tiered slash computation.
///      Uses sqrt(stake) * effectiveRep for weight calculation per the spec.
library ConsensusLib {
    using Math for uint256;

    uint256 internal constant MIN_REPUTATION_FLOOR = 100;
    uint256 internal constant PRECISION = 1e18;

    // Tiered slash thresholds (in units of stddev * PRECISION)
    // 1.5σ = 15e17, 2σ = 2e18, 3σ = 3e18, 5σ = 5e18
    uint256 internal constant TIER_1_THRESHOLD = 15e17; // 1.5σ
    uint256 internal constant TIER_2_THRESHOLD = 2e18; // 2σ
    uint256 internal constant TIER_3_THRESHOLD = 3e18; // 3σ
    uint256 internal constant TIER_4_THRESHOLD = 5e18; // 5σ

    // Tiered slash percentages (basis points of staked amount)
    uint256 internal constant TIER_1_SLASH_BPS = 1000; // 10%
    uint256 internal constant TIER_2_SLASH_BPS = 2500; // 25%
    uint256 internal constant TIER_3_SLASH_BPS = 5000; // 50%
    uint256 internal constant TIER_4_SLASH_BPS = 10000; // 100%

    /// @notice Calculate consensus from validation inputs
    /// @param inputs Array of validator scores, stakes, and reputations
    /// @return result Full consensus result
    function calculate(ValidationInput[] memory inputs) public pure returns (ConsensusResult memory result) {
        uint256 n = inputs.length;
        if (n == 0) revert ISapienCore.ConsensusNotReady(0, 1);

        // ── Pass 1: Compute weights + weighted sum (merged from 2 loops) ──
        uint256[] memory weights = new uint256[](n);
        uint256 totalWeight = 0;
        uint256 weightedAverage = 0;
        {
            uint256 weightedSum = 0;
            for (uint256 i; i < n; ++i) {
                ValidationInput memory inp = inputs[i];
                uint256 effectiveRep = inp.reputation < MIN_REPUTATION_FLOOR ? MIN_REPUTATION_FLOOR : inp.reputation;
                uint256 sqrtStake = Math.sqrt(inp.stakeAmount);
                uint256 w = sqrtStake * effectiveRep;
                if (w == 0) w = 1;
                weights[i] = w;
                totalWeight += w;
                // Accumulate score * w to avoid overflow in score * w * PRECISION
                weightedSum += inp.score * w;
            }
            // Apply PRECISION after division to prevent overflow
            weightedAverage = Math.mulDiv(weightedSum, PRECISION, totalWeight);
        }

        // ── Pass 2: Variance ──
        uint256 stdDev = 0;
        address[] memory validators = new address[](n);
        {
            uint256 varianceSum = 0;
            for (uint256 i; i < n; ++i) {
                ValidationInput memory inp = inputs[i];
                uint256 scorePrecision = inp.score * PRECISION;
                uint256 diff = scorePrecision > weightedAverage
                    ? scorePrecision - weightedAverage
                    : weightedAverage - scorePrecision;
                // Safe multiplication to prevent overflow: weights[i] * diff * diff
                uint256 wi = weights[i];
                uint256 diffSquared = diff * diff;
                uint256 weightedVariance = wi * diffSquared;
                if (diffSquared != 0 && weightedVariance / diffSquared != wi) {
                    weightedVariance = type(uint256).max / 4;
                }
                varianceSum += weightedVariance;
                validators[i] = inp.validator;
            }
            stdDev = Math.sqrt(varianceSum / totalWeight);
        }

        // ── Outlier classification + result assembly ──
        result = _classifyAndAssemble(inputs, weights, validators, n, weightedAverage, stdDev);
    }

    /// @dev Classify outliers and assemble the ConsensusResult (extracted for stack depth)
    function _classifyAndAssemble(
        ValidationInput[] memory inputs,
        uint256[] memory weights,
        address[] memory validators,
        uint256 n,
        uint256 weightedAverage,
        uint256 stdDev
    ) private pure returns (ConsensusResult memory) {
        bool[] memory isOutlier = new bool[](n);
        uint256[] memory slashAmounts = new uint256[](n);
        uint256 totalAccurateWeight = 0;

        for (uint256 i; i < n; ++i) {
            uint256 scorePrecision = inputs[i].score * PRECISION;
            uint256 deviation =
                scorePrecision > weightedAverage ? scorePrecision - weightedAverage : weightedAverage - scorePrecision;

            if (stdDev > 0 && deviation > (stdDev * TIER_1_THRESHOLD) / PRECISION) {
                isOutlier[i] = true;
                slashAmounts[i] = _computeSlash(deviation, stdDev, inputs[i].stakeAmount);
            } else {
                totalAccurateWeight += weights[i];
            }
        }

        return ConsensusResult({
            weightedAverage: weightedAverage / PRECISION,
            stdDeviation: stdDev,
            validators: validators,
            isOutlier: isOutlier,
            slashAmounts: slashAmounts,
            weights: weights,
            totalAccurateWeight: totalAccurateWeight
        });
    }

    /// @dev Compute tiered slash amount based on deviation from mean
    function _computeSlash(uint256 deviation, uint256 stdDev, uint256 stakeAmount) private pure returns (uint256) {
        // deviation and stdDev are both in PRECISION units
        // deviationSigma = deviation * PRECISION / stdDev (in PRECISION units)
        uint256 deviationSigma = (deviation * PRECISION) / stdDev;

        uint256 slashBps;
        if (deviationSigma >= TIER_4_THRESHOLD) {
            slashBps = TIER_4_SLASH_BPS;
        } else if (deviationSigma >= TIER_3_THRESHOLD) {
            slashBps = TIER_3_SLASH_BPS;
        } else if (deviationSigma >= TIER_2_THRESHOLD) {
            slashBps = TIER_2_SLASH_BPS;
        } else {
            slashBps = TIER_1_SLASH_BPS;
        }

        return (stakeAmount * slashBps) / C.BPS;
    }
}
