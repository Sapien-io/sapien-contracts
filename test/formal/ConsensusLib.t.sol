// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface Vm {
    function assume(bool) external;
}

contract ConsensusLibFormalTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function calculateWeightedAverage(uint256[] memory scores, uint256[] memory weights)
        internal
        pure
        returns (uint256)
    {
        uint256 len = scores.length;
        if (len != weights.length) revert("LengthMismatch");
        if (len == 0) revert("NoValidations");

        uint256 totalWeightedScore = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < len;) {
            totalWeightedScore += scores[i] * weights[i];
            totalWeight += weights[i];
            unchecked {
                ++i;
            }
        }

        if (totalWeight == 0) revert("DivisionByZero");

        return totalWeightedScore / totalWeight;
    }

    function calculateStandardDeviation(uint256[] memory scores, uint256[] memory weights, uint256 mean)
        internal
        pure
        returns (uint256)
    {
        uint256 len = scores.length;
        if (len != weights.length) revert("LengthMismatch");
        if (len == 0) return 0;

        uint256 sumWeightedSquaredDiff = 0;
        uint256 totalWeight = 0;

        for (uint256 i = 0; i < len;) {
            uint256 score = scores[i];
            uint256 weight = weights[i];

            uint256 diff = score > mean ? score - mean : mean - score;
            uint256 squaredDiff = diff * diff;

            sumWeightedSquaredDiff += squaredDiff * weight;
            totalWeight += weight;
            unchecked {
                ++i;
            }
        }

        if (totalWeight == 0) return 0;
        uint256 variance = sumWeightedSquaredDiff / totalWeight;
        return sqrt(variance);
    }

    function sqrt(uint256 x) internal pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    function check_WeightedAverage_Bounds(uint256 s1, uint256 s2, uint256 w1, uint256 w2) public {
        vm.assume(w1 > 0 && w2 > 0);
        vm.assume(s1 <= 10000 && s2 <= 10000);
        vm.assume(w1 < 1e18 && w2 < 1e18);

        uint256[] memory scores = new uint256[](2);
        scores[0] = s1;
        scores[1] = s2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = w1;
        weights[1] = w2;

        uint256 mean = calculateWeightedAverage(scores, weights);

        uint256 minS = s1 < s2 ? s1 : s2;
        uint256 maxS = s1 > s2 ? s1 : s2;

        if (!(mean >= minS)) revert("FailMin");
        if (!(mean <= maxS)) revert("FailMax");
    }

    function check_WeightedAverage_Identity(uint256 s, uint256 w1, uint256 w2) public {
        vm.assume(w1 > 0 && w2 > 0);
        vm.assume(s <= 10000);
        vm.assume(w1 < 1e18 && w2 < 1e18);

        uint256[] memory scores = new uint256[](2);
        scores[0] = s;
        scores[1] = s;

        uint256[] memory weights = new uint256[](2);
        weights[0] = w1;
        weights[1] = w2;

        uint256 mean = calculateWeightedAverage(scores, weights);

        if (mean != s) revert("FailIdentity");
    }

    function check_StandardDeviation_Identity(uint256 s, uint256 w1, uint256 w2) public {
        vm.assume(w1 > 0 && w2 > 0);
        vm.assume(s <= 10000);
        vm.assume(w1 < 1e18 && w2 < 1e18);

        uint256[] memory scores = new uint256[](2);
        scores[0] = s;
        scores[1] = s;

        uint256[] memory weights = new uint256[](2);
        weights[0] = w1;
        weights[1] = w2;

        uint256 mean = calculateWeightedAverage(scores, weights);
        uint256 stdDev = calculateStandardDeviation(scores, weights, mean);

        if (stdDev != 0) revert("FailStdDev0");
    }

    function check_OutlierThreshold(uint256 s1, uint256 s2, uint256 w1, uint256 w2) public {
        vm.assume(w1 > 0 && w2 > 0);
        vm.assume(s1 <= 10000 && s2 <= 10000);
        vm.assume(w1 < 1e18 && w2 < 1e18);

        uint256[] memory scores = new uint256[](2);
        scores[0] = s1;
        scores[1] = s2;

        uint256[] memory weights = new uint256[](2);
        weights[0] = w1;
        weights[1] = w2;

        uint256 mean = calculateWeightedAverage(scores, weights);
        uint256 stdDev = calculateStandardDeviation(scores, weights, mean);

        uint256 deviation1 = s1 > mean ? s1 - mean : mean - s1;

        bool isOutlier = deviation1 > 1500 || (stdDev > 0 && deviation1 > 2 * stdDev);

        if (deviation1 <= 1500 && (stdDev == 0 || deviation1 <= 2 * stdDev)) {
            if (isOutlier) revert("FailFalsePositive");
        } else {
            if (!isOutlier) revert("FailFalseNegative");
        }
    }

    function calculateSlashAmount(uint256 stakeAmount, uint256 deviation, uint256 stdDev)
        internal
        pure
        returns (uint256)
    {
        if (stdDev == 0) return 0;

        uint256 sigmaMultiple = (deviation * 100) / stdDev;
        uint256 slashPercentage;

        if (sigmaMultiple > 499) {
            slashPercentage = 10000; // 100%
        } else if (sigmaMultiple > 399) {
            slashPercentage = 7500; // 75%
        } else if (sigmaMultiple > 299) {
            slashPercentage = 5000; // 50%
        } else if (sigmaMultiple > 199) {
            slashPercentage = 2500; // 25%
        } else if (sigmaMultiple > 149) {
            slashPercentage = 1000; // 10%
        } else {
            return 0;
        }

        return (stakeAmount * slashPercentage) / 10000;
    }

    function check_Slashing_Monotonicity(uint256 stake, uint256 dev1, uint256 dev2, uint256 stdDev) public {
        vm.assume(stdDev > 0);
        vm.assume(dev2 > dev1);
        vm.assume(stake > 0 && stake < 1e30);

        uint256 slash1 = calculateSlashAmount(stake, dev1, stdDev);
        uint256 slash2 = calculateSlashAmount(stake, dev2, stdDev);

        if (!(slash2 >= slash1)) revert("FailMonotonicity");
    }
}
