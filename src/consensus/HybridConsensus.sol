// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IConsensusAlgorithm} from "../interface/IConsensusAlgorithm.sol";
import {ConsensusLib} from "../libraries/ConsensusLib.sol";

/**
 * @title HybridConsensus
 * @notice Combines sqrt stake, reputation weighting, and a hard 30% per-validator cap
 * @dev Weight = min(sqrt(stake) * reputation / 10000, 30% of total weight)
 *      The cap is applied iteratively: after clamping overweight validators, the total
 *      weight decreases, which may cause new validators to exceed the threshold.
 *      The algorithm repeats until convergence (max 10 iterations).
 * Security Grade: A (best overall protection)
 */
contract HybridConsensus is IConsensusAlgorithm {
    /// @notice Maximum weight percentage per validator (30%)
    uint256 public constant MAX_WEIGHT_BPS = 3000; // 30%

    function calculateConsensus(ValidationInput[] calldata validations)
        external
        pure
        returns (ConsensusResult memory result)
    {
        if (validations.length == 0) revert NoValidations();

        (uint256[] memory scores, uint256[] memory weights, uint256 totalWeight) = _calculateInitialWeights(validations);

        if (totalWeight == 0) revert InvalidStakeAmount();

        // Apply iterative cap — properly limits any single validator to MAX_WEIGHT_BPS
        ConsensusLib.applyCap(weights, MAX_WEIGHT_BPS);

        // Calculate weighted average
        result.weightedAverage = ConsensusLib.calculateWeightedAverage(scores, weights);

        // Calculate standard deviation
        result.stdDev = ConsensusLib.calculateStandardDeviation(scores, weights, result.weightedAverage);

        // Identify outliers
        (result.validatorsToSlash, result.slashAmounts) =
            ConsensusLib.identifyOutliers(validations, result.weightedAverage, result.stdDev);

        // Return weights for transparency
        result.validatorWeights = weights;

        return result;
    }

    function _calculateInitialWeights(ValidationInput[] calldata validations)
        internal
        pure
        returns (uint256[] memory scores, uint256[] memory weights, uint256 totalWeight)
    {
        scores = new uint256[](validations.length);
        weights = new uint256[](validations.length);
        totalWeight = 0;

        for (uint256 i = 0; i < validations.length; i++) {
            if (validations[i].score > 10000) revert InvalidScore(validations[i].score);
            if (validations[i].stakeAmount == 0) revert InvalidStakeAmount();
            if (validations[i].reputation > 10000) revert InvalidReputation(validations[i].reputation);

            scores[i] = validations[i].score;
            uint256 sqrtStake = ConsensusLib.sqrt(validations[i].stakeAmount);
            uint256 repWeight = (sqrtStake * validations[i].reputation) / 10000;
            weights[i] = repWeight;
            totalWeight += repWeight;
        }
    }

    function getName() external pure returns (string memory) {
        return "Hybrid";
    }

    function getSecurityGrade() external pure returns (string memory) {
        return "A";
    }

    function getDescription() external pure returns (string memory) {
        return "Hybrid consensus: Weight = min(sqrt(stake) * reputation, 30% cap). Best overall protection combining whale resistance, quality incentives, and hard limits.";
    }
}
