// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

interface Vm {
    function assume(bool) external;
}

contract SqrtStakeConsensusVerify {
    /**
     * @notice Babylonian method sqrt - matches ConsensusLib.sqrt
     */
    function sqrt(uint256 x) public pure returns (uint256 y) {
        if (x == 0) return 0;
        uint256 z = (x + 1) / 2;
        y = x;
        while (z < y) {
            y = z;
            z = (x / z + z) / 2;
        }
        return y;
    }

    /**
     * @notice Calculate weight for SqrtStakeConsensus: weight = sqrt(stakeAmount)
     * @dev SqrtStakeConsensus uses pure sqrt weighting (no reputation factor)
     */
    function calculateWeight(uint256 stakeAmount) public pure returns (uint256) {
        return sqrt(stakeAmount);
    }
}

contract SqrtStakeConsensusFormalTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    SqrtStakeConsensusVerify ssc = new SqrtStakeConsensusVerify();

    /**
     * @notice Verify weight formula: weight == sqrt(stakeAmount)
     */
    function check_Weight_Equals_SqrtStake(uint256 stake) public {
        vm.assume(stake > 0 && stake < 1e30);

        uint256 weight = ssc.calculateWeight(stake);
        uint256 expected = ssc.sqrt(stake);

        if (weight != expected) revert("IncorrectWeightFormula");
    }

    /**
     * @notice Verify weight monotonicity: increasing stake => non-decreasing weight
     */
    function check_Weight_Monotonicity(uint256 stake1, uint256 stake2) public {
        vm.assume(stake1 > 0 && stake1 < 1e30);
        vm.assume(stake2 >= stake1 && stake2 < 1e30);

        uint256 weight1 = ssc.calculateWeight(stake1);
        uint256 weight2 = ssc.calculateWeight(stake2);

        if (weight2 < weight1) revert("MonotonicityViolated");
    }

    /**
     * @notice Verify sqrt integer bounds: sqrt(x)^2 <= x < (sqrt(x)+1)^2
     */
    function check_Sqrt_Bounds(uint256 x) public {
        vm.assume(x > 0 && x < 1e30);

        uint256 y = ssc.sqrt(x);

        if (y * y > x) revert("SqrtTooLarge");
        if ((y + 1) * (y + 1) <= x) revert("SqrtTooSmall");
    }
}
