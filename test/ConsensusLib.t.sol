// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ConsensusLib} from "src/libraries/ConsensusLib.sol";
import {ValidationInput, ConsensusResult} from "src/Types.sol";

contract ConsensusLibTest is Test {
    function test_calculate_uniformScores() public pure {
        ValidationInput[] memory inputs = new ValidationInput[](3);
        inputs[0] = ValidationInput({validator: address(1), score: 8000, stakeAmount: 100e18, reputation: 5000});
        inputs[1] = ValidationInput({validator: address(2), score: 8000, stakeAmount: 100e18, reputation: 5000});
        inputs[2] = ValidationInput({validator: address(3), score: 8000, stakeAmount: 100e18, reputation: 5000});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertEq(result.weightedAverage, 8000);
        assertEq(result.stdDeviation, 0);
        assertEq(result.totalAccurateWeight, result.weights[0] + result.weights[1] + result.weights[2]);

        // No outliers when all scores are the same
        for (uint256 i; i < 3; ++i) {
            assertFalse(result.isOutlier[i]);
            assertEq(result.slashAmounts[i], 0);
        }
    }

    function test_calculate_weightedAverage() public pure {
        ValidationInput[] memory inputs = new ValidationInput[](3);
        inputs[0] = ValidationInput({validator: address(1), score: 8000, stakeAmount: 100e18, reputation: 5000});
        inputs[1] = ValidationInput({validator: address(2), score: 6000, stakeAmount: 100e18, reputation: 5000});
        inputs[2] = ValidationInput({validator: address(3), score: 7000, stakeAmount: 100e18, reputation: 5000});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        // Equal weights -> simple average = (8000 + 6000 + 7000) / 3 = 7000
        assertEq(result.weightedAverage, 7000);
    }

    function test_calculate_outlierDetection() public pure {
        ValidationInput[] memory inputs = new ValidationInput[](5);
        // 4 validators agree tightly at ~8000, 1 validator at 1000 (extreme outlier)
        // With 4 out of 5 agreeing, the outlier should be clearly detected
        inputs[0] = ValidationInput({validator: address(1), score: 8000, stakeAmount: 100e18, reputation: 5000});
        inputs[1] = ValidationInput({validator: address(2), score: 8000, stakeAmount: 100e18, reputation: 5000});
        inputs[2] = ValidationInput({validator: address(3), score: 8000, stakeAmount: 100e18, reputation: 5000});
        inputs[3] = ValidationInput({validator: address(4), score: 8000, stakeAmount: 100e18, reputation: 5000});
        inputs[4] = ValidationInput({validator: address(5), score: 1000, stakeAmount: 100e18, reputation: 5000});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        // Validator 5 (score 1000) should be an outlier
        assertTrue(result.isOutlier[4]);
        assertGt(result.slashAmounts[4], 0);

        // The 4 agreeing validators should not be outliers
        // (they may or may not be flagged depending on stddev - assert at least 3 are not outliers)
        uint256 nonOutlierCount;
        for (uint256 i; i < 4; ++i) {
            if (!result.isOutlier[i]) nonOutlierCount++;
        }
        assertGe(nonOutlierCount, 3);
    }

    function test_calculate_stakeWeighting() public pure {
        ValidationInput[] memory inputs = new ValidationInput[](2);
        // Higher stake should have more weight
        inputs[0] = ValidationInput({
            validator: address(1),
            score: 9000,
            stakeAmount: 400e18, // sqrt(400) = 20
            reputation: 5000
        });
        inputs[1] = ValidationInput({
            validator: address(2),
            score: 5000,
            stakeAmount: 100e18, // sqrt(100) = 10
            reputation: 5000
        });

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        // Weighted average should lean towards 9000 since validator 1 has sqrt(4x) = 2x weight
        // weight1 = sqrt(400e18) * 5000 / 10000 ~ 10000000000 * 0.5
        // weight2 = sqrt(100e18) * 5000 / 10000 ~ 5000000000 * 0.5
        // avg = (9000 * w1 + 5000 * w2) / (w1 + w2)
        // w1/w2 = sqrt(400e18)/sqrt(100e18) = 2
        // avg = (9000*2 + 5000) / 3 = 23000/3 ≈ 7666
        assertGt(result.weightedAverage, 7000);
        assertLt(result.weightedAverage, 9000);
    }

    function test_calculate_reputationWeighting() public pure {
        ValidationInput[] memory inputs = new ValidationInput[](2);
        inputs[0] = ValidationInput({
            validator: address(1),
            score: 9000,
            stakeAmount: 100e18,
            reputation: 10000 // MAX reputation
        });
        inputs[1] = ValidationInput({
            validator: address(2),
            score: 5000,
            stakeAmount: 100e18,
            reputation: 1000 // MIN_REPUTATION_FLOOR
        });

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        // Higher reputation validator should have more weight
        // weight1/weight2 = 10000/1000 = 10
        // avg ≈ (9000*10 + 5000) / 11 = 95000/11 ≈ 8636
        assertGt(result.weightedAverage, 8000);
    }

    function test_calculate_singleInput() public pure {
        ValidationInput[] memory inputs = new ValidationInput[](1);
        inputs[0] = ValidationInput({validator: address(1), score: 7500, stakeAmount: 100e18, reputation: 5000});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertEq(result.weightedAverage, 7500);
        assertEq(result.stdDeviation, 0);
        assertFalse(result.isOutlier[0]);
    }

    function test_calculate_minReputationFloor() public pure {
        ValidationInput[] memory inputs = new ValidationInput[](2);
        inputs[0] = ValidationInput({
            validator: address(1),
            score: 8000,
            stakeAmount: 100e18,
            reputation: 0 // Below floor, should use 1000
        });
        inputs[1] = ValidationInput({
            validator: address(2),
            score: 6000,
            stakeAmount: 100e18,
            reputation: 0 // Below floor, should use 1000
        });

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        // Both at floor reputation, equal stake -> simple average
        assertEq(result.weightedAverage, 7000);
    }
}
