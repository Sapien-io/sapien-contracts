// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IConsensusAlgorithm} from "../interface/IConsensusAlgorithm.sol";
import {ConsensusLib} from "../libraries/ConsensusLib.sol";

/**
 * @title CappedLinearConsensus
 * @notice Stake x Reputation weighted consensus with iterative 30% cap per validator
 * @dev Weight = min(stake * reputation / 10000, 30% of total weight)
 *      The cap is applied iteratively via ConsensusLib.applyCap to ensure no single
 *      validator exceeds 30% of the final total weight.
 *      This provides Sybil resistance by:
 *      1. New validators (rep=5000) have less influence than established ones
 *      2. Attackers can't instantly dominate consensus with fresh accounts
 *      3. 30% iterative cap prevents whale dominance
 * Security Grade: A- (prevents whale dominance + Sybil resistance)
 */
contract CappedLinearConsensus is IConsensusAlgorithm {
    /// @notice Maximum weight percentage per validator (30%)
    uint256 public constant MAX_WEIGHT_BPS = 3000; // 30%

    function calculateConsensus(ValidationInput[] calldata validations)
        external
        pure
        returns (ConsensusResult memory result)
    {
        if (validations.length == 0) revert NoValidations();

        uint256 len = validations.length;

        // Allocate arrays
        uint256[] memory scores = new uint256[](len);
        uint256[] memory weights = new uint256[](len);

        // Single pass: validate inputs and calculate base weights
        uint256 totalWeight = 0;
        for (uint256 i = 0; i < len; i++) {
            if (validations[i].score > 10000) {
                revert InvalidScore(validations[i].score);
            }
            if (validations[i].stakeAmount == 0) {
                revert InvalidStakeAmount();
            }

            scores[i] = validations[i].score;

            // Calculate base weight = stake * effective_reputation / 10000
            uint256 baseWeight = ConsensusLib.calculateBaseWeight(validations[i].stakeAmount, validations[i].reputation);

            // Ensure baseWeight > 0 to prevent zero-weight validators (handles rounding edge cases)
            if (baseWeight == 0) revert InvalidStakeAmount();

            weights[i] = baseWeight;
            totalWeight += baseWeight;
        }

        if (totalWeight == 0) revert InvalidStakeAmount();

        // Apply iterative cap - properly limits any single validator to MAX_WEIGHT_BPS
        ConsensusLib.applyCap(weights, MAX_WEIGHT_BPS);

        // Verify total weight after capping is still > 0 to prevent division by zero
        uint256 totalCappedWeight = 0;
        for (uint256 i = 0; i < weights.length; i++) {
            totalCappedWeight += weights[i];
        }
        if (totalCappedWeight == 0) revert InvalidStakeAmount();

        // Calculate weighted average with capped weights
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

    function getName() external pure returns (string memory) {
        return "CappedLinear";
    }

    function getSecurityGrade() external pure returns (string memory) {
        return "A-";
    }

    function getDescription() external pure returns (string memory) {
        return "Stake x Reputation weighted with iterative 30% cap. Weight = min(stake * rep, 30% of total). Provides Sybil resistance and prevents whale dominance.";
    }
}
