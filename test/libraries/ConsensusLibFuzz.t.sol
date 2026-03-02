// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ConsensusLib} from "src/libraries/ConsensusLib.sol";
import {ValidationInput, ConsensusResult} from "src/Types.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title ConsensusLibFuzz
/// @notice Fuzz tests attempting to break the ConsensusLib with edge cases
contract ConsensusLibFuzz is Test {
    uint256 constant PRECISION = 1e18;
    uint256 constant MIN_REPUTATION_FLOOR = 1_000;

    function test_calculate_revertsOnEmptyInputs() public {
        ValidationInput[] memory inputs = new ValidationInput[](0);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusNotReady.selector, 0, 1));
        ConsensusLib.calculate(inputs);
    }

    function testFuzz_calculate_singleValidator(
        address validator,
        uint256 score,
        uint256 stakeAmount,
        uint256 reputation
    ) public pure {
        score = bound(score, 0, 10_000);
        stakeAmount = bound(stakeAmount, 1, type(uint128).max);
        reputation = bound(reputation, 0, type(uint128).max);

        ValidationInput[] memory inputs = new ValidationInput[](1);
        inputs[0] =
            ValidationInput({validator: validator, score: score, stakeAmount: stakeAmount, reputation: reputation});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertEq(result.weightedAverage, score, "Single validator should have exact score as weighted average");
        assertEq(result.stdDeviation, 0, "Single validator should have zero stddev");
        assertEq(result.validators.length, 1);
        assertEq(result.validators[0], validator);
        assertFalse(result.isOutlier[0], "Single validator cannot be outlier");
        assertEq(result.slashAmounts[0], 0, "No slash for non-outlier");
    }

    function testFuzz_calculate_twoValidatorsSameScore(
        address validator1,
        address validator2,
        uint256 score,
        uint256 stake1,
        uint256 stake2,
        uint256 rep1,
        uint256 rep2
    ) public {
        vm.assume(validator1 != validator2);
        score = bound(score, 0, 10_000);
        stake1 = bound(stake1, 1, type(uint64).max);
        stake2 = bound(stake2, 1, type(uint64).max);
        rep1 = bound(rep1, 1, type(uint64).max);
        rep2 = bound(rep2, 1, type(uint64).max);

        ValidationInput[] memory inputs = new ValidationInput[](2);
        inputs[0] = ValidationInput({validator: validator1, score: score, stakeAmount: stake1, reputation: rep1});
        inputs[1] = ValidationInput({validator: validator2, score: score, stakeAmount: stake2, reputation: rep2});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertEq(result.weightedAverage, score, "Same scores should produce exact weighted average");
        assertEq(result.stdDeviation, 0, "Same scores should have zero stddev");
        assertFalse(result.isOutlier[0], "No outliers when all scores are same");
        assertFalse(result.isOutlier[1], "No outliers when all scores are same");
    }

    function testFuzz_calculate_extremeScoreDifference(
        uint256 lowScore,
        uint256 highScore,
        uint256 stake1,
        uint256 stake2
    ) public pure {
        lowScore = bound(lowScore, 0, 1000);
        highScore = bound(highScore, 9000, 10_000);
        stake1 = bound(stake1, 1e18, 100e18);
        stake2 = bound(stake2, 1e18, 100e18);

        ValidationInput[] memory inputs = new ValidationInput[](2);
        inputs[0] = ValidationInput({validator: address(1), score: lowScore, stakeAmount: stake1, reputation: 5000});
        inputs[1] = ValidationInput({validator: address(2), score: highScore, stakeAmount: stake2, reputation: 5000});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertTrue(
            result.weightedAverage >= lowScore && result.weightedAverage <= highScore,
            "Weighted average should be between scores"
        );
        assertTrue(result.stdDeviation > 0, "Different scores should have non-zero stddev");
    }

    function testFuzz_calculate_zeroStakeHandled(uint256 score, uint256 reputation) public pure {
        score = bound(score, 0, 10_000);
        reputation = bound(reputation, 0, type(uint64).max);

        ValidationInput[] memory inputs = new ValidationInput[](1);
        inputs[0] = ValidationInput({validator: address(1), score: score, stakeAmount: 0, reputation: reputation});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertEq(result.weightedAverage, score);
        assertGt(result.weights[0], 0, "Weight should be at least 1 even with zero stake");
    }

    function testFuzz_calculate_zeroReputationUsesFloor(uint256 score, uint256 stakeAmount) public pure {
        score = bound(score, 0, 10_000);
        stakeAmount = bound(stakeAmount, 1, type(uint64).max);

        ValidationInput[] memory inputs = new ValidationInput[](1);
        inputs[0] = ValidationInput({validator: address(1), score: score, stakeAmount: stakeAmount, reputation: 0});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertEq(result.weightedAverage, score);
        assertTrue(result.weights[0] > 0, "Zero reputation should still produce positive weight");
    }

    function testFuzz_calculate_manyValidatorsNoOverflow(uint8 numValidators, uint256 baseSeed) public pure {
        numValidators = uint8(bound(numValidators, 1, 50));

        ValidationInput[] memory inputs = new ValidationInput[](numValidators);

        for (uint256 i; i < numValidators; ++i) {
            uint256 seed = uint256(keccak256(abi.encodePacked(baseSeed, i)));
            inputs[i] = ValidationInput({
                validator: address(uint160(seed)),
                score: (seed % 10_001),
                stakeAmount: ((seed >> 32) % 1e20) + 1,
                reputation: ((seed >> 64) % 10_000) + 1
            });
        }

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertTrue(result.weightedAverage <= 10_000, "Weighted average cannot exceed max score");
        assertEq(result.validators.length, numValidators);
        assertEq(result.isOutlier.length, numValidators);
        assertEq(result.slashAmounts.length, numValidators);
        assertEq(result.weights.length, numValidators);
    }

    function testFuzz_calculate_outlierDetection(uint256 consensusScore, uint256 outlierScore, uint256 stake)
        public
        pure
    {
        consensusScore = bound(consensusScore, 5000, 8000);
        stake = bound(stake, 1e18, 100e18);

        outlierScore = bound(outlierScore, 0, 1000);
        if (consensusScore > 7000) {
            outlierScore = 10_000 - (consensusScore - 5000);
        }

        ValidationInput[] memory inputs = new ValidationInput[](4);

        for (uint256 i; i < 3; ++i) {
            inputs[i] = ValidationInput({
                validator: address(uint160(i + 1)), score: consensusScore, stakeAmount: stake, reputation: 5000
            });
        }
        inputs[3] = ValidationInput({
            validator: address(uint160(100)), score: outlierScore, stakeAmount: stake, reputation: 5000
        });

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        if (result.stdDeviation > 0) {
            uint256 diff = consensusScore > outlierScore ? consensusScore - outlierScore : outlierScore - consensusScore;

            if (diff > 1000) {
                assertTrue(result.isOutlier[3], "Large deviation should be detected as outlier");
                assertTrue(result.slashAmounts[3] > 0, "Outliers should have non-zero slash");
            }
        }
    }

    function testFuzz_calculate_tieredSlashing(uint256 outlierDeviation, uint256 stake) public pure {
        stake = bound(stake, 1e18, 100e18);
        outlierDeviation = bound(outlierDeviation, 2000, 10_000);

        uint256 consensusScore = 5000;
        uint256 outlierScore = consensusScore > outlierDeviation ? consensusScore - outlierDeviation : 0;

        ValidationInput[] memory inputs = new ValidationInput[](10);

        for (uint256 i; i < 9; ++i) {
            inputs[i] = ValidationInput({
                validator: address(uint160(i + 1)), score: consensusScore, stakeAmount: stake, reputation: 5000
            });
        }
        inputs[9] = ValidationInput({
            validator: address(uint160(100)), score: outlierScore, stakeAmount: stake, reputation: 5000
        });

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        if (result.isOutlier[9]) {
            uint256 slashAmt = result.slashAmounts[9];
            assertTrue(slashAmt <= stake, "Slash cannot exceed staked amount");

            assertTrue(
                slashAmt == (stake * 1000) / 10_000 || slashAmt == (stake * 2500) / 10_000
                    || slashAmt == (stake * 5000) / 10_000 || slashAmt == stake,
                "Slash should be one of the tiered amounts"
            );
        }
    }

    function testFuzz_calculate_maxStakeNoOverflow(uint256 score) public pure {
        score = bound(score, 0, 10_000);

        ValidationInput[] memory inputs = new ValidationInput[](2);
        inputs[0] = ValidationInput({
            validator: address(1), score: score, stakeAmount: type(uint128).max, reputation: type(uint64).max
        });
        inputs[1] = ValidationInput({
            validator: address(2), score: score, stakeAmount: type(uint128).max, reputation: type(uint64).max
        });

        ConsensusResult memory result = ConsensusLib.calculate(inputs);
        assertEq(result.weightedAverage, score);
    }

    function testFuzz_calculate_consistentWeightOrdering(uint256 stake1, uint256 stake2, uint256 rep1, uint256 rep2)
        public
        pure
    {
        stake1 = bound(stake1, 1e18, 1000e18);
        stake2 = bound(stake2, 1e18, 1000e18);
        rep1 = bound(rep1, MIN_REPUTATION_FLOOR, 10_000);
        rep2 = bound(rep2, MIN_REPUTATION_FLOOR, 10_000);

        ValidationInput[] memory inputs = new ValidationInput[](2);
        inputs[0] = ValidationInput({validator: address(1), score: 5000, stakeAmount: stake1, reputation: rep1});
        inputs[1] = ValidationInput({validator: address(2), score: 5000, stakeAmount: stake2, reputation: rep2});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertGt(result.weights[0], 0);
        assertGt(result.weights[1], 0);
    }

    function testFuzz_calculate_accurateWeightTracking(uint8 numOutliers, uint8 numAccurate) public pure {
        numOutliers = uint8(bound(numOutliers, 0, 5));
        numAccurate = uint8(bound(numAccurate, 3, 20));

        uint256 total = uint256(numOutliers) + uint256(numAccurate);
        ValidationInput[] memory inputs = new ValidationInput[](total);

        for (uint256 i; i < numAccurate; ++i) {
            inputs[i] = ValidationInput({
                validator: address(uint160(i + 1)), score: 5000, stakeAmount: 10e18, reputation: 5000
            });
        }

        for (uint256 i; i < numOutliers; ++i) {
            inputs[numAccurate + i] = ValidationInput({
                validator: address(uint160(numAccurate + i + 100)), score: 100, stakeAmount: 10e18, reputation: 5000
            });
        }

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        uint256 computedAccurateWeight = 0;
        for (uint256 i; i < total; ++i) {
            if (!result.isOutlier[i]) {
                computedAccurateWeight += result.weights[i];
            }
        }

        assertEq(result.totalAccurateWeight, computedAccurateWeight, "totalAccurateWeight mismatch");
    }

    function testFuzz_calculate_allOutliersExceptOne(uint8 numValidators, uint256 goodScore) public pure {
        numValidators = uint8(bound(numValidators, 2, 20));
        goodScore = bound(goodScore, 4000, 6000);

        ValidationInput[] memory inputs = new ValidationInput[](numValidators);

        inputs[0] = ValidationInput({validator: address(1), score: goodScore, stakeAmount: 100e18, reputation: 10_000});

        for (uint256 i = 1; i < numValidators; ++i) {
            inputs[i] = ValidationInput({
                validator: address(uint160(i + 1)),
                score: (i % 2 == 0) ? 0 : 10_000,
                stakeAmount: 1e18,
                reputation: 1000
            });
        }

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertTrue(result.totalAccurateWeight > 0, "Should have at least one accurate validator");
    }

    function testFuzz_calculate_deterministicResults(
        address[3] memory validators,
        uint256[3] memory scores,
        uint256[3] memory stakes,
        uint256[3] memory reps
    ) public pure {
        ValidationInput[] memory inputs1 = new ValidationInput[](3);
        ValidationInput[] memory inputs2 = new ValidationInput[](3);

        for (uint256 i; i < 3; ++i) {
            scores[i] = bound(scores[i], 0, 10_000);
            stakes[i] = bound(stakes[i], 1, type(uint64).max);
            reps[i] = bound(reps[i], 1, type(uint64).max);

            inputs1[i] = ValidationInput({
                validator: validators[i], score: scores[i], stakeAmount: stakes[i], reputation: reps[i]
            });
            inputs2[i] = ValidationInput({
                validator: validators[i], score: scores[i], stakeAmount: stakes[i], reputation: reps[i]
            });
        }

        ConsensusResult memory result1 = ConsensusLib.calculate(inputs1);
        ConsensusResult memory result2 = ConsensusLib.calculate(inputs2);

        assertEq(result1.weightedAverage, result2.weightedAverage, "Results should be deterministic");
        assertEq(result1.stdDeviation, result2.stdDeviation, "StdDev should be deterministic");
        for (uint256 i; i < 3; ++i) {
            assertEq(result1.isOutlier[i], result2.isOutlier[i], "Outlier status should be deterministic");
            assertEq(result1.slashAmounts[i], result2.slashAmounts[i], "Slash amounts should be deterministic");
        }
    }

    function testFuzz_calculate_extremeReputationValues(uint256 score) public pure {
        score = bound(score, 0, 10_000);

        ValidationInput[] memory inputs = new ValidationInput[](2);
        inputs[0] = ValidationInput({validator: address(1), score: score, stakeAmount: 1e18, reputation: 1});
        inputs[1] =
            ValidationInput({validator: address(2), score: score, stakeAmount: 1e18, reputation: type(uint128).max});

        ConsensusResult memory result = ConsensusLib.calculate(inputs);

        assertEq(result.weightedAverage, score, "Same scores should produce exact average");
        assertTrue(result.weights[1] > result.weights[0], "Higher reputation should have higher weight");
    }
}
