// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IConsensusAlgorithm} from "../interface/IConsensusAlgorithm.sol";
import {ConsensusLib} from "../libraries/ConsensusLib.sol";

/**
 * @title LinearStakeConsensus
 * @notice Current system - linear stake-weighted consensus
 * @dev Weight = stake (vulnerable to whale attacks with >50% stake)
 * Security Grade: C+ (vulnerable to whale manipulation)
 */
contract LinearStakeConsensus is IConsensusAlgorithm {
    /**
     * @notice Calculate consensus from validator inputs using linear stake weighting
     * @dev Weight = stake amount. Vulnerable to whale manipulation with >50% stake.
     * @param validations Array of validator inputs with scores and stakes
     * @return result Consensus calculation result with weighted average, std dev, and outliers
     */
    function calculateConsensus(ValidationInput[] calldata validations)
        external
        pure
        returns (ConsensusResult memory result)
    {
        if (validations.length == 0) revert NoValidations();

        // Extract scores and use stakes as weights
        uint256[] memory scores = new uint256[](validations.length);
        uint256[] memory weights = new uint256[](validations.length);

        for (uint256 i = 0; i < validations.length; i++) {
            scores[i] = validations[i].score;
            weights[i] = validations[i].stakeAmount;

            if (validations[i].score > 10000) {
                revert InvalidScore(validations[i].score);
            }
            if (validations[i].stakeAmount == 0) {
                revert InvalidStakeAmount();
            }
        }

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

    function getName() external pure returns (string memory) {
        return "LinearStake";
    }

    function getSecurityGrade() external pure returns (string memory) {
        return "C+";
    }

    function getDescription() external pure returns (string memory) {
        return "Linear stake-weighted consensus. Weight = stake. Vulnerable to whale attacks (>50% stake).";
    }
}
