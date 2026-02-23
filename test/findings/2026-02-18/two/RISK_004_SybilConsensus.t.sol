// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ConsensusLib} from "src/libraries/ConsensusLib.sol";
import {ValidationInput, ConsensusResult} from "src/Types.sol";

/// @title RISK-004 VERIFIED: Sybil Consensus Manipulation via sqrt Weighting
/// @notice Proves that sqrt(stake) * reputation weighting enables >3x weight amplification
///         when an attacker splits stake across multiple accounts.
contract RISK_004_SybilConsensus is BaseTest {
    function test_sybilWeightAmplification() public pure {
        uint256 totalStake = 10_000e18;
        uint256 reputation = 5000;

        ValidationInput[] memory single = new ValidationInput[](1);
        single[0] =
            ValidationInput({validator: address(0x1), score: 8000, stakeAmount: totalStake, reputation: reputation});
        ConsensusResult memory singleResult = ConsensusLib.calculate(single);
        uint256 singleWeight = singleResult.weights[0];

        uint256 n = 10;
        ValidationInput[] memory sybil = new ValidationInput[](n);
        for (uint256 i; i < n; i++) {
            sybil[i] = ValidationInput({
                validator: address(uint160(100 + i)), score: 8000, stakeAmount: totalStake / n, reputation: reputation
            });
        }
        ConsensusResult memory sybilResult = ConsensusLib.calculate(sybil);
        uint256 totalSybilWeight;
        for (uint256 i; i < n; i++) {
            totalSybilWeight += sybilResult.weights[i];
        }

        // sqrt(N) ≈ 3.16x amplification proves the sybil attack is viable
        assertGt(totalSybilWeight, singleWeight * 3, "sybil splitting yields >3x weight");
    }

    function test_sybilOverridesHonestConsensus() public pure {
        uint256 reputation = 5000;

        // 3 honest validators (high stake, rate quality high)
        // vs 6 sybil accounts (same total stake, rate quality low to reject)
        ValidationInput[] memory inputs = new ValidationInput[](9);
        for (uint256 i; i < 3; i++) {
            inputs[i] = ValidationInput({
                validator: address(uint160(1 + i)), score: 8500, stakeAmount: 5_000e18, reputation: reputation
            });
        }
        for (uint256 i; i < 6; i++) {
            inputs[3 + i] = ValidationInput({
                validator: address(uint160(100 + i)),
                score: 2000,
                stakeAmount: 2_500e18, // 6 * 2500 = 15k == 3 * 5k honest total
                reputation: reputation
            });
        }

        ConsensusResult memory result = ConsensusLib.calculate(inputs);
        uint256 honestWeight;
        uint256 sybilWeight;
        for (uint256 i; i < 3; i++) {
            honestWeight += result.weights[i];
        }
        for (uint256 i; i < 6; i++) {
            sybilWeight += result.weights[3 + i];
        }

        assertGt(sybilWeight, honestWeight, "sybil outweighs honest with equal total stake");
        assertLt(result.weightedAverage, 7000, "sybil pulls consensus below acceptance threshold");
    }
}
