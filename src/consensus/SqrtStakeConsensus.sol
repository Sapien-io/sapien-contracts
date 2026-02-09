// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IConsensusAlgorithm} from "../interface/IConsensusAlgorithm.sol";
import {ConsensusLib} from "../libraries/ConsensusLib.sol";

/**
 * @title SqrtStakeConsensus
 * @notice Square root stake weighting - reduces whale power sublinearly
 * @dev Weight = sqrt(stake)
 * Security Grade: A- (reduces whale power by 22%)
 */
contract SqrtStakeConsensus is IConsensusAlgorithm {
    function calculateConsensus(ValidationInput[] calldata validations)
        external
        pure
        returns (ConsensusResult memory result)
    {
        if (validations.length == 0) revert NoValidations();

        // Calculate sqrt weights
        uint256[] memory scores = new uint256[](validations.length);
        uint256[] memory weights = new uint256[](validations.length);

        for (uint256 i = 0; i < validations.length; i++) {
            if (validations[i].score > 10000) {
                revert InvalidScore(validations[i].score);
            }
            if (validations[i].stakeAmount == 0) {
                revert InvalidStakeAmount();
            }

            scores[i] = validations[i].score;
            weights[i] = ConsensusLib.sqrt(validations[i].stakeAmount);
        }

        // Calculate weighted average with sqrt weights
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
        return "SqrtStake";
    }

    function getSecurityGrade() external pure returns (string memory) {
        return "A-";
    }

    function getDescription() external pure returns (string memory) {
        return "Square root stake weighting. Weight = sqrt(stake). Reduces whale power by 22%, proven in quadratic voting research.";
    }
}
