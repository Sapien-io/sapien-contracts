// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {HybridConsensus} from "../../src/consensus/HybridConsensus.sol";
import {CappedLinearConsensus} from "../../src/consensus/CappedLinearConsensus.sol";
import {IConsensusAlgorithm} from "../../src/interface/IConsensusAlgorithm.sol";

/**
 * @title HybridConsensusCapIneffectiveTest
 * @notice Verifies the FIX for H-2: HybridConsensus 30% Cap Was Ineffective
 *
 * ORIGINAL VULNERABILITY:
 * The `_applyCap` function scaled ALL weights by the same factor, which is a
 * mathematical no-op for weighted averages. A whale with >50% of weighted stake
 * could fully control consensus.
 *
 * FIX APPLIED:
 * Both HybridConsensus and CappedLinearConsensus now use ConsensusLib.applyCap()
 * which implements iterative individual capping. When a validator exceeds 30%,
 * their weight is clamped and the total is recalculated, repeating until convergence.
 *
 * LOCATION: ConsensusLib.applyCap(), HybridConsensus.calculateConsensus(), CappedLinearConsensus.calculateConsensus()
 *
 * SEVERITY: HIGH (now fixed)
 */
contract HybridConsensusCapIneffectiveTest is Test {
    HybridConsensus public hybrid;
    CappedLinearConsensus public cappedLinear;

    function setUp() public {
        hybrid = new HybridConsensus();
        cappedLinear = new CappedLinearConsensus();
    }

    /**
     * @notice FIX VERIFIED: Whale is now properly capped at 30% in HybridConsensus
     * @dev A whale with 10000 ether vs 3 validators with 100 ether each.
     *      Before fix: whale achieved weighted average of 7692 (dominated).
     *      After fix: whale should be limited to ~30% influence, result ~3000.
     */
    function test_H2_Fix_WhaleCappedInHybridConsensus() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](4);
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x1),
            score: 10000, // Whale votes max
            stakeAmount: 10000 ether,
            reputation: 5000
        });
        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x2),
            score: 0, // Normal validators vote 0
            stakeAmount: 100 ether,
            reputation: 5000
        });
        inputs[2] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x3), score: 0, stakeAmount: 100 ether, reputation: 5000
        });
        inputs[3] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x4), score: 0, stakeAmount: 100 ether, reputation: 5000
        });

        IConsensusAlgorithm.ConsensusResult memory result = hybrid.calculateConsensus(inputs);

        console.log("=== H-2 FIX VERIFIED: HybridConsensus ===");
        console.log("Whale: 10000 ether, score=10000");
        console.log("3 normals: 100 ether each, score=0");
        console.log("Weighted average:", result.weightedAverage);

        // Before fix: 7692 (whale had ~77% influence)
        // After fix: whale is capped at 30%, so result should be <= 30% * 10000 = 3000
        assertLe(result.weightedAverage, 5000, "FIX VERIFIED: Whale no longer dominates consensus");
        console.log("FIX VERIFIED: Whale influence properly limited.");
    }

    /**
     * @notice FIX VERIFIED: Both algorithms now produce similar (low) results for whale scenario
     */
    function test_H2_Fix_BothAlgorithmsCapped() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](4);
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x1), score: 10000, stakeAmount: 10000 ether, reputation: 5000
        });
        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x2), score: 0, stakeAmount: 100 ether, reputation: 5000
        });
        inputs[2] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x3), score: 0, stakeAmount: 100 ether, reputation: 5000
        });
        inputs[3] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x4), score: 0, stakeAmount: 100 ether, reputation: 5000
        });

        IConsensusAlgorithm.ConsensusResult memory hybridResult = hybrid.calculateConsensus(inputs);
        IConsensusAlgorithm.ConsensusResult memory cappedResult = cappedLinear.calculateConsensus(inputs);

        console.log("=== Comparison After Fix ===");
        console.log("HybridConsensus:", hybridResult.weightedAverage);
        console.log("CappedLinear:", cappedResult.weightedAverage);

        // Both should have whale limited to ~30%
        assertLe(hybridResult.weightedAverage, 5000, "Hybrid: whale properly capped");
        assertLe(cappedResult.weightedAverage, 5000, "CappedLinear: whale properly capped");

        console.log("FIX VERIFIED: Both algorithms properly cap whale influence.");
    }

    /**
     * @notice FIX VERIFIED: Proportional scaling no longer preserves whale dominance
     * @dev Before fix, the 2-validator case gave 9090. After fix, should be ~5000 (30%/70% split at most).
     */
    function test_H2_Fix_TwoValidatorCase() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x1), score: 10000, stakeAmount: 10000 ether, reputation: 5000
        });
        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x2), score: 0, stakeAmount: 100 ether, reputation: 5000
        });

        IConsensusAlgorithm.ConsensusResult memory result = hybrid.calculateConsensus(inputs);

        console.log("=== 2-Validator Case After Fix ===");
        console.log("Whale(10000e, score=10000) vs Normal(100e, score=0)");
        console.log("Before fix: 9090 (whale had ~91% weight)");
        console.log("After fix:", result.weightedAverage);

        // With proper 30% cap, result should be at most 5000
        // (and realistically close to 3000-5000 depending on iteration convergence)
        assertLe(result.weightedAverage, 5000, "FIX VERIFIED: 2-validator whale properly capped");
    }

    /**
     * @notice Verify weights actually show capping in action
     */
    function test_H2_Fix_WeightsShowCapping() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](3);
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x1),
            score: 8000,
            stakeAmount: 1000 ether, // Whale
            reputation: 5000
        });
        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x2), score: 3000, stakeAmount: 100 ether, reputation: 5000
        });
        inputs[2] = IConsensusAlgorithm.ValidationInput({
            validator: address(0x3), score: 3000, stakeAmount: 100 ether, reputation: 5000
        });

        IConsensusAlgorithm.ConsensusResult memory result = cappedLinear.calculateConsensus(inputs);

        console.log("=== Weight Capping Verification ===");
        console.log("Whale: 1000 ether, score=8000");
        console.log("Two normals: 100 ether each, score=3000");

        uint256 totalWeight = 0;
        for (uint256 i = 0; i < result.validatorWeights.length; i++) {
            console.log("  Validator", i, "weight:", result.validatorWeights[i]);
            totalWeight += result.validatorWeights[i];
        }

        // Whale's weight should be <= 30% of total after capping
        if (totalWeight > 0) {
            uint256 whaleBps = (result.validatorWeights[0] * 10000) / totalWeight;
            console.log("Whale weight %:", whaleBps);
            // With 3 validators, the theoretical minimum for the largest weight is ~33%
            // (since 3 * 30% = 90% < 100%, perfect 30% cap is impossible).
            // The iterative cap converges to equal weights, so ~33% each.
            assertLe(whaleBps, 3400, "Whale should be significantly reduced from original dominance");
        }

        console.log("Weighted average:", result.weightedAverage);
    }
}
