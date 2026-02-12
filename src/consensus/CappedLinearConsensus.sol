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
 * @author Sapien Team
 */
contract CappedLinearConsensus is IConsensusAlgorithm {
    /// @notice Maximum weight percentage per validator (30%)
    uint256 public constant MAX_WEIGHT_BPS = 3000; // 30%

    /**
     * @notice Calculate consensus for a set of validations
     * @param validations Array of validation inputs
     * @return result The consensus result including weighted average and outliers
     */
    function calculateConsensus(ValidationInput[] calldata validations)
        external
        pure
        returns (ConsensusResult memory result)
    {
        if (validations.length == 0) revert NoValidations();

        (uint256[] memory scores, uint256[] memory weights, uint256 totalWeight) = _prepareWeights(validations);
        if (totalWeight == 0) revert InvalidStakeAmount();

        // Apply iterative cap - properly limits any single validator to MAX_WEIGHT_BPS
        ConsensusLib.applyCap(weights, MAX_WEIGHT_BPS);

        // Verify total weight after capping is still > 0 to prevent division by zero
        uint256 totalCappedWeight = 0;
        for (uint256 i = 0; i < weights.length; ++i) {
            totalCappedWeight += weights[i];
        }
        if (totalCappedWeight == 0) revert InvalidStakeAmount();

        // Calculate weighted average and outliers
        result.weightedAverage = ConsensusLib.calculateWeightedAverage(scores, weights);
        result.stdDev = ConsensusLib.calculateStandardDeviation(scores, weights, result.weightedAverage);
        (result.validatorsToSlash, result.slashAmounts) =
            ConsensusLib.identifyOutliers(validations, result.weightedAverage, result.stdDev);
        result.validatorWeights = weights;

        return result;
    }

    /**
     * @notice Prepare base weights and scores from validations
     * @param validations Array of validation inputs
     * @return scores Array of scores
     * @return weights Array of base weights
     * @return totalWeight Total base weight
     */
    function _prepareWeights(ValidationInput[] calldata validations)
        internal
        pure
        returns (uint256[] memory scores, uint256[] memory weights, uint256 totalWeight)
    {
        uint256 len = validations.length;
        scores = new uint256[](len);
        weights = new uint256[](len);

        for (uint256 i = 0; i < len; ++i) {
            if (validations[i].score > 10000) revert InvalidScore(validations[i].score);
            if (validations[i].stakeAmount == 0) revert InvalidStakeAmount();

            scores[i] = validations[i].score;
            weights[i] = ConsensusLib.calculateBaseWeight(validations[i].stakeAmount, validations[i].reputation);
            if (weights[i] == 0) revert InvalidStakeAmount();
            totalWeight += weights[i];
        }
    }

    /**
     * @notice Get the name of the consensus algorithm
     * @return The name string
     */
    function getName() external pure returns (string memory) {
        return "CappedLinear";
    }

    /**
     * @notice Get the security grade of the algorithm
     * @return The security grade string
     */
    function getSecurityGrade() external pure returns (string memory) {
        return "A-";
    }

    /**
     * @notice Get the description of the algorithm
     * @return The description string
     */
    function getDescription() external pure returns (string memory) {
        return "Stake x Reputation weighted with iterative 30% cap. Weight = min(stake * rep, 30% of total). Provides Sybil resistance and prevents whale dominance.";
    }
}
