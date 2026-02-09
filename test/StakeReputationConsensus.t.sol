// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {CappedLinearConsensus} from "../src/consensus/CappedLinearConsensus.sol";
import {LinearStakeConsensus} from "../src/consensus/LinearStakeConsensus.sol";
import {IConsensusAlgorithm} from "../src/interface/IConsensusAlgorithm.sol";

/**
 * @title StakeReputationConsensusTest
 * @notice Comprehensive tests for stake × reputation weighted consensus
 * @dev Tests verify that:
 *      1. Reputation affects validator weight in consensus
 *      2. High-rep validators have more influence than low-rep
 *      3. Sybil attacks are mitigated (new accounts have less power)
 *      4. 30% cap still applies after reputation weighting
 *      5. Minimum reputation floor prevents zero-weight validators
 */
contract StakeReputationConsensusTest is Test {
    CappedLinearConsensus public consensus;

    uint256 constant DEFAULT_REP = 5000;
    uint256 constant HIGH_REP = 8000;
    uint256 constant LOW_REP = 3000;
    uint256 constant MAX_REP = 10000;
    uint256 constant MIN_REP_FLOOR = 1000;

    function setUp() public {
        consensus = new CappedLinearConsensus();
    }

    // ============================================
    // TEST: Basic Functionality
    // ============================================

    function test_BasicConsensusWithEqualReputation() public view {
        // Two validators with equal stake and reputation
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);

        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1), score: 8000, stakeAmount: 100 ether, reputation: DEFAULT_REP
        });

        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2), score: 6000, stakeAmount: 100 ether, reputation: DEFAULT_REP
        });

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // With equal stake and rep, should be simple average
        assertEq(result.weightedAverage, 7000, "Should be average of 8000 and 6000");
    }

    function test_HighReputationHasMoreWeight() public view {
        // High rep validator vs low rep validator, same stake
        // Use 5 validators to avoid 2-validator cap convergence to equality
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](5);

        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 10000, // Votes YES
            stakeAmount: 100 ether,
            reputation: HIGH_REP // 8000
        });

        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2),
            score: 0, // Votes NO
            stakeAmount: 100 ether,
            reputation: LOW_REP // 3000
        });

        // Add 3 neutral validators to dilute below cap threshold
        for (uint256 i = 2; i < 5; i++) {
            inputs[i] = IConsensusAlgorithm.ValidationInput({
                validator: address(uint160(i + 1)), score: 5000, stakeAmount: 100 ether, reputation: DEFAULT_REP
            });
        }

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        console.log("High rep vs Low rep consensus:", result.weightedAverage);
        console.log("Weight 1 (high rep):", result.validatorWeights[0]);
        console.log("Weight 2 (low rep):", result.validatorWeights[1]);

        // High rep should still have more weight than low rep
        assertTrue(result.validatorWeights[0] > result.validatorWeights[1], "High rep should have more weight");

        // High rep should pull consensus above 50% (toward their vote)
        assertTrue(result.weightedAverage > 5000, "High rep should have more influence");
    }

    // ============================================
    // TEST: Sybil Attack Resistance
    // ============================================

    function test_SybilAttackMitigated_NewAccountsLessWeight() public view {
        // Scenario: 1 established validator vs 5 new Sybil accounts
        // The 30% cap limits any single validator, including the established one
        // But established validator should still have meaningful influence

        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](6);

        // Established validator votes YES (good contribution)
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 10000,
            stakeAmount: 400 ether,
            reputation: HIGH_REP // 8000
        });

        // 5 Sybil accounts vote NO (attack)
        for (uint256 i = 1; i < 6; i++) {
            inputs[i] = IConsensusAlgorithm.ValidationInput({
                // forge-lint: disable-next-line(unsafe-typecast)
                // casting to 'uint160' is safe because i+1 is in range 2-6, which fits in uint160
                validator: address(uint160(i + 1)),
                score: 0,
                stakeAmount: 100 ether,
                reputation: DEFAULT_REP // 5000 (new account)
            });
        }

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        console.log("Sybil attack scenario consensus:", result.weightedAverage);
        console.log("Established validator weight:", result.validatorWeights[0]);
        console.log("Sybil 1 weight:", result.validatorWeights[1]);

        // Key insight: established validator has HIGHER weight per account than Sybils
        // Even though capped, they get more influence per unit of stake+rep
        assertTrue(
            result.validatorWeights[0] > result.validatorWeights[1],
            "Established validator should have more weight than single Sybil"
        );

        // The attack still works somewhat because there are 5 Sybils
        // But each Sybil has less weight than they would with stake-only consensus
        // Consensus should be between 0 (sybil score) and 10000 (honest score)
        assertTrue(result.weightedAverage > 0, "Should not be complete rejection");
        assertTrue(result.weightedAverage < 10000, "Should not be complete acceptance");

        // In pure stake-weighted: established=400, sybil=500 → sybils win (44% vs 56%)
        // With reputation: established=320, sybil=250 → established wins (56% vs 44%)
        // But with 30% cap applied... it's more complex
        // The important thing is each sybil has less weight than their stake would suggest
    }

    function test_SybilAttackWithMoreStake_StillMitigated() public view {
        // Sybils have MORE total stake but lower reputation
        // Established: 200 stake, 9000 rep
        // Sybils: 800 total stake (8 × 100), 5000 rep each

        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](9);

        // Established validator votes YES
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 10000,
            stakeAmount: 200 ether,
            reputation: 9000 // Very high rep
        });

        // 8 Sybil accounts vote NO
        for (uint256 i = 1; i < 9; i++) {
            inputs[i] = IConsensusAlgorithm.ValidationInput({
                // forge-lint: disable-next-line(unsafe-typecast)
                // casting to 'uint160' is safe because i+1 is in range 2-9, which fits in uint160
                validator: address(uint160(i + 1)),
                score: 0,
                stakeAmount: 100 ether,
                reputation: DEFAULT_REP
            });
        }

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // Established weight = 200 * 9000 / 10000 = 180
        // Each Sybil weight = 100 * 5000 / 10000 = 50
        // Total Sybil weight = 8 * 50 = 400
        // Total weight = 180 + 400 = 580
        // Note: 30% cap may apply to Sybils if their collective weight > 30% each

        console.log("Heavy Sybil attack consensus:", result.weightedAverage);

        // Even with 4x stake, Sybils should not completely dominate
        // The high-rep established validator should have meaningful influence
        assertTrue(result.weightedAverage > 2500, "High-rep validator should have influence");
    }

    function test_PureSybilAttack_NoEstablishedValidators() public view {
        // Worst case: All validators are Sybils with default reputation
        // This tests the baseline - even Sybils need reputation to dominate

        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](3);

        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 2000, // Attack score
            stakeAmount: 100 ether,
            reputation: DEFAULT_REP
        });

        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2), score: 2000, stakeAmount: 100 ether, reputation: DEFAULT_REP
        });

        inputs[2] = IConsensusAlgorithm.ValidationInput({
            validator: address(3), score: 2000, stakeAmount: 100 ether, reputation: DEFAULT_REP
        });

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // All agree on 2000, so consensus should be 2000
        assertEq(result.weightedAverage, 2000, "Unanimous low score");

        // This shows the attack works when ALL validators are Sybils
        // But this requires building up reputation over time or having no honest validators
    }

    // ============================================
    // TEST: Reputation Influence Scaling
    // ============================================

    function test_MaxReputationDoubleInfluence() public view {
        // Test that reputation scales weight correctly (before capping)
        // Use more validators to avoid capping distorting the test
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](4);

        // Max rep validator
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 10000,
            stakeAmount: 100 ether,
            reputation: MAX_REP // 10000
        });

        // Default rep validator
        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2),
            score: 0,
            stakeAmount: 100 ether,
            reputation: DEFAULT_REP // 5000
        });

        // Two more default rep validators to dilute weights below cap
        inputs[2] = IConsensusAlgorithm.ValidationInput({
            validator: address(3), score: 5000, stakeAmount: 100 ether, reputation: DEFAULT_REP
        });

        inputs[3] = IConsensusAlgorithm.ValidationInput({
            validator: address(4), score: 5000, stakeAmount: 100 ether, reputation: DEFAULT_REP
        });

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        console.log("Max rep weight:", result.validatorWeights[0]);
        console.log("Default rep weight:", result.validatorWeights[1]);
        console.log("Consensus:", result.weightedAverage);

        // Max rep should have higher weight than default rep (same stake)
        assertTrue(result.validatorWeights[0] > result.validatorWeights[1], "Max rep should have more weight");

        // Consensus should be pulled toward max rep's vote (10000)
        assertTrue(result.weightedAverage > 5000, "Max rep should pull consensus up");
    }

    function test_MinReputationFloor() public view {
        // Very low reputation should be floored at 1000 (10%)
        // Use 5 validators to avoid 2-validator cap convergence distorting weights
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](5);

        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 10000,
            stakeAmount: 100 ether,
            reputation: 500 // Below floor, should be treated as 1000
        });

        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2), score: 0, stakeAmount: 100 ether, reputation: MAX_REP
        });

        // Add 3 default validators to avoid extreme capping
        for (uint256 i = 2; i < 5; i++) {
            inputs[i] = IConsensusAlgorithm.ValidationInput({
                validator: address(uint160(i + 1)), score: 5000, stakeAmount: 100 ether, reputation: DEFAULT_REP
            });
        }

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        console.log("Min rep floor test:", result.weightedAverage);
        console.log("Floored weight:", result.validatorWeights[0]);
        console.log("Max rep weight:", result.validatorWeights[1]);

        // Floored validator should have lower weight than max-rep validator
        assertTrue(result.validatorWeights[0] > 0, "Should have non-zero weight");
        assertTrue(
            result.validatorWeights[0] < result.validatorWeights[1], "Floored rep should have less weight than max rep"
        );
    }

    // ============================================
    // TEST: Cap Still Applies
    // ============================================

    function test_CapAppliesAfterReputationWeight() public view {
        // One validator with massive stake×rep should still be capped at 30%
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);

        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 10000,
            stakeAmount: 1000 ether,
            reputation: MAX_REP // 10000 - whale with max rep
        });

        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2), score: 0, stakeAmount: 100 ether, reputation: DEFAULT_REP
        });

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // Uncapped weight1 = 1000 * 10000 / 10000 = 1000
        // Uncapped weight2 = 100 * 5000 / 10000 = 50
        // Total = 1050
        // Weight1 is 95% of total, so should be capped at 30%

        console.log("Cap test consensus:", result.weightedAverage);
        console.log("Whale weight (should be capped):", result.validatorWeights[0]);
        console.log("Small weight:", result.validatorWeights[1]);

        // Whale should be capped - consensus shouldn't be 10000
        assertTrue(result.weightedAverage < 9000, "Whale should be capped");
    }

    // ============================================
    // TEST: Binary Voting Scenarios
    // ============================================

    function test_BinaryVoting_HighRepWins() public view {
        // Binary vote: 2 high-rep YES vs 3 low-rep NO
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](5);

        // 2 high-rep validators vote YES
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1), score: 10000, stakeAmount: 100 ether, reputation: HIGH_REP
        });
        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2), score: 10000, stakeAmount: 100 ether, reputation: HIGH_REP
        });

        // 3 low-rep validators vote NO
        inputs[2] = IConsensusAlgorithm.ValidationInput({
            validator: address(3), score: 0, stakeAmount: 100 ether, reputation: LOW_REP
        });
        inputs[3] = IConsensusAlgorithm.ValidationInput({
            validator: address(4), score: 0, stakeAmount: 100 ether, reputation: LOW_REP
        });
        inputs[4] = IConsensusAlgorithm.ValidationInput({
            validator: address(5), score: 0, stakeAmount: 100 ether, reputation: LOW_REP
        });

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // High rep weight: 2 × (100 × 8000 / 10000) = 2 × 80 = 160
        // Low rep weight: 3 × (100 × 3000 / 10000) = 3 × 30 = 90
        // Total = 250
        // Weighted avg = (10000 × 160 + 0 × 90) / 250 = 1600000 / 250 = 6400

        console.log("Binary high-rep wins:", result.weightedAverage);

        // High-rep minority should win despite being outnumbered
        assertTrue(result.weightedAverage > 5000, "High-rep should win");
    }

    function test_BinaryVoting_TwoValidatorsCappedEqual() public view {
        // When only 2 validators exist, both exceed 30% cap and get equalized
        // This demonstrates the anti-whale protection working aggressively
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);

        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 10000,
            stakeAmount: 100 ether,
            reputation: HIGH_REP // 8000
        });

        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2),
            score: 0,
            stakeAmount: 300 ether, // 3x stake
            reputation: LOW_REP // 3000
        });

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // Base weights:
        // Weight1 = 100 × 8000 / 10000 = 80
        // Weight2 = 300 × 3000 / 10000 = 90
        // Total = 170
        // Weight1 % = 47% > 30% → CAPPED
        // Weight2 % = 53% > 30% → CAPPED
        // Both capped to 30% of total = equal weights!

        console.log("Two validators capped:", result.weightedAverage);
        console.log("High rep weight:", result.validatorWeights[0]);
        console.log("Low rep weight:", result.validatorWeights[1]);

        // Both validators get capped to the same weight
        assertEq(result.validatorWeights[0], result.validatorWeights[1], "Both capped to same weight");

        // With equal weights, consensus is exactly 50-50
        assertEq(result.weightedAverage, 5000, "Equal weights = 50-50 consensus");
    }

    // ============================================
    // TEST: Edge Cases
    // ============================================

    function test_ZeroReputation_FloorsToMinimum() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](1);

        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 5000,
            stakeAmount: 100 ether,
            reputation: 0 // Zero rep should floor to 1000
        });

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // Should not revert, should use floored reputation
        assertEq(result.weightedAverage, 5000, "Single validator score");
        assertTrue(result.validatorWeights[0] > 0, "Should have non-zero weight");
    }

    function test_SingleValidator() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](1);

        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1), score: 7500, stakeAmount: 100 ether, reputation: HIGH_REP
        });

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        assertEq(result.weightedAverage, 7500, "Single validator determines consensus");
    }

    function test_AllValidatorsAgree() public view {
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](3);

        for (uint256 i = 0; i < 3; i++) {
            inputs[i] = IConsensusAlgorithm.ValidationInput({
                // forge-lint: disable-next-line(unsafe-typecast)
                // casting to 'uint160' is safe because i+1 is in range 1-3, which fits in uint160
                validator: address(uint160(i + 1)),
                score: 8000,
                stakeAmount: 100 ether,
                reputation: DEFAULT_REP
            });
        }

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        assertEq(result.weightedAverage, 8000, "Unanimous consensus");
        assertEq(result.validatorsToSlash.length, 0, "No outliers when unanimous");
    }

    // ============================================
    // TEST: Algorithm Metadata
    // ============================================

    function test_AlgorithmMetadata() public view {
        assertEq(consensus.getName(), "CappedLinear");
        assertEq(consensus.getSecurityGrade(), "A-");
        assertTrue(bytes(consensus.getDescription()).length > 0);
    }

    // ============================================
    // TEST: Comparison with Stake-Only Consensus
    // ============================================

    function test_CompareWithLinearStake_SybilScenario() public {
        // Compare stake-only vs stake×reputation in a Sybil attack scenario
        LinearStakeConsensus linearConsensus = new LinearStakeConsensus();

        // Scenario: 1 established validator vs 3 Sybils
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](4);

        // Established validator: high reputation, moderate stake
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 10000, // Votes YES
            stakeAmount: 100 ether,
            reputation: 8500 // High rep from good history
        });

        // 3 Sybil accounts: default reputation, same stake each
        for (uint256 i = 1; i < 4; i++) {
            inputs[i] = IConsensusAlgorithm.ValidationInput({
                // forge-lint: disable-next-line(unsafe-typecast)
                // casting to 'uint160' is safe because i+1 is in range 2-4, which fits in uint160
                validator: address(uint160(i + 1)),
                score: 0, // Vote NO (attack)
                stakeAmount: 100 ether,
                reputation: DEFAULT_REP // New accounts
            });
        }

        // Calculate with stake-only (LinearStake)
        IConsensusAlgorithm.ConsensusResult memory linearResult = linearConsensus.calculateConsensus(inputs);

        // Calculate with stake×reputation (CappedLinear)
        IConsensusAlgorithm.ConsensusResult memory cappedResult = consensus.calculateConsensus(inputs);

        console.log("=== Sybil Attack Comparison ===");
        console.log("Linear (stake-only) consensus:", linearResult.weightedAverage);
        console.log("CappedLinear (stake*rep) consensus:", cappedResult.weightedAverage);

        // In stake-only: established=100, sybils=300 → 25% vs 75% → sybils win (consensus ≈ 2500)
        // In stake×rep: established=85, sybils=150 → 36% vs 64% → better for established

        // Both should show Sybils winning, but stake×rep gives established validator more influence
        assertTrue(cappedResult.weightedAverage >= linearResult.weightedAverage, "Stake*rep should favor established");

        // Verify established validator has better relative weight in stake×rep
        uint256 establishedLinearWeight = linearResult.validatorWeights[0];
        uint256 sybilLinearWeight = linearResult.validatorWeights[1];
        uint256 establishedCappedWeight = cappedResult.validatorWeights[0];
        uint256 sybilCappedWeight = cappedResult.validatorWeights[1];

        // Ratio improvement: established/sybil ratio should be higher in stake×rep
        uint256 linearRatio = (establishedLinearWeight * 10000) / sybilLinearWeight;
        uint256 cappedRatio = (establishedCappedWeight * 10000) / sybilCappedWeight;

        console.log("Linear ratio (established/sybil):", linearRatio);
        console.log("Capped ratio (established/sybil):", cappedRatio);

        assertTrue(cappedRatio >= linearRatio, "Established validator should have better ratio in stake*rep");
    }

    function test_ReputationBreaksTheTie() public {
        // When stake is equal, reputation should break the tie
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](4);

        // 2 high-rep validators vote YES
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1), score: 10000, stakeAmount: 100 ether, reputation: 9000
        });
        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2), score: 10000, stakeAmount: 100 ether, reputation: 8000
        });

        // 2 low-rep validators vote NO
        inputs[2] = IConsensusAlgorithm.ValidationInput({
            validator: address(3), score: 0, stakeAmount: 100 ether, reputation: 4000
        });
        inputs[3] = IConsensusAlgorithm.ValidationInput({
            validator: address(4), score: 0, stakeAmount: 100 ether, reputation: 3000
        });

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        console.log("Reputation tie-breaker:", result.weightedAverage);

        // High-rep side: 90 + 80 = 170 base weight (but may be capped at 30%)
        // Low-rep side: 40 + 30 = 70 base weight
        // Total base = 240, each high-rep validator is 37.5%/33.3% - both capped
        // After capping, consensus is pulled down but still favors high-rep

        assertTrue(result.weightedAverage > 6000, "High reputation validators should win");
    }

    // ============================================
    // FUZZ TESTS
    // ============================================

    function testFuzz_ConsensusWithVariableReputation(uint256 rep1, uint256 rep2, uint256 score1, uint256 score2)
        public
        view
    {
        // Bound inputs to valid ranges
        rep1 = bound(rep1, 0, 10000);
        rep2 = bound(rep2, 0, 10000);
        score1 = bound(score1, 0, 10000);
        score2 = bound(score2, 0, 10000);

        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);

        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1), score: score1, stakeAmount: 100 ether, reputation: rep1
        });

        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2), score: score2, stakeAmount: 100 ether, reputation: rep2
        });

        // Should not revert
        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // Result should be within valid range
        assertTrue(result.weightedAverage <= 10000, "Consensus should not exceed max");

        // Both weights should be positive (due to floor)
        assertTrue(result.validatorWeights[0] > 0, "Weight 1 should be positive");
        assertTrue(result.validatorWeights[1] > 0, "Weight 2 should be positive");
    }

    function testFuzz_ConsensusWithVariableStake(uint256 stake1, uint256 stake2) public view {
        // Bound to reasonable stake values (10 wei minimum to ensure weight > 0 after rounding)
        // With min reputation floor of 1000: weight = stake * 1000 / 10000 = stake / 10
        // For weight >= 1, we need stake >= 10
        stake1 = bound(stake1, 10, 1_000_000 ether);
        stake2 = bound(stake2, 10, 1_000_000 ether);

        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](2);

        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1), score: 10000, stakeAmount: stake1, reputation: 8000
        });

        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: address(2), score: 0, stakeAmount: stake2, reputation: 5000
        });

        // Should not revert
        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // Result should be within valid range
        assertTrue(result.weightedAverage <= 10000, "Consensus should not exceed max");
    }

    function testFuzz_ManyValidators(uint8 validatorCount) public view {
        // Bound to reasonable validator count
        validatorCount = uint8(bound(validatorCount, 2, 50));

        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](validatorCount);

        for (uint256 i = 0; i < validatorCount; i++) {
            inputs[i] = IConsensusAlgorithm.ValidationInput({
                // forge-lint: disable-next-line(unsafe-typecast)
                // casting to 'uint160' is safe because i+1 is in range 1-validatorCount, which fits in uint160
                validator: address(uint160(i + 1)),
                score: uint256(keccak256(abi.encode(i))) % 10001, // Random score 0-10000
                stakeAmount: 100 ether,
                reputation: 5000
            });
        }

        // Should not revert
        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // Result should be within valid range
        assertTrue(result.weightedAverage <= 10000, "Consensus should not exceed max");
    }

    function test_MassiveSybilAttackMitigated() public {
        // Extreme scenario: 1 established validator vs 10 Sybils
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](11);

        // Established validator with high reputation
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: address(1),
            score: 10000,
            stakeAmount: 500 ether, // Higher stake
            reputation: 9500 // Very high reputation
        });

        // 10 Sybil accounts with default reputation
        for (uint256 i = 1; i < 11; i++) {
            inputs[i] = IConsensusAlgorithm.ValidationInput({
                // forge-lint: disable-next-line(unsafe-typecast)
                // casting to 'uint160' is safe because i+1 is in range 2-11, which fits in uint160
                validator: address(uint160(i + 1)),
                score: 0,
                stakeAmount: 100 ether, // Same stake each
                reputation: DEFAULT_REP
            });
        }

        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        console.log("Massive Sybil attack consensus:", result.weightedAverage);
        console.log("Established weight:", result.validatorWeights[0]);
        console.log("Sybil 1 weight:", result.validatorWeights[1]);

        // Established: 500 × 9500 / 10000 = 475 base weight (but capped at 30%)
        // Each Sybil: 100 × 5000 / 10000 = 50 weight
        // Total Sybil: 10 × 50 = 500 weight
        // Established gets capped at 30% of total (~292.5)
        // Consensus is lower due to capping, but still significant

        // Key insight: despite 10 Sybils, established validator still gets meaningful influence
        // With iterative 30% cap, established validator is limited to 30% influence
        // Consensus = 30% * 10000 + 70% * 0 ≈ 3000
        assertTrue(result.weightedAverage > 2500, "Established validator should have strong influence");

        // Verify each Sybil has less weight than they would with stake-only
        uint256 sybilTotalStake = 1000 ether; // 10 × 100
        uint256 sybilTotalWeight = 0;
        for (uint256 i = 1; i < 11; i++) {
            sybilTotalWeight += result.validatorWeights[i];
        }

        // Sybil total weight should be less than their total stake (due to reputation discount)
        assertTrue(sybilTotalWeight < sybilTotalStake, "Sybils should have reduced weight");
    }
}
