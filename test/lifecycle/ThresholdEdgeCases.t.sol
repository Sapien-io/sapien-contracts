// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {LifecycleBase} from "test/lifecycle/Lifecycle.t.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus, ConsensusReport, Reputation} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";

/// @title ThresholdEdgeCases
/// @notice Category 5: Tests that the consensus threshold correctly classifies contributions
///         at boundary values, and that stake weighting shifts outcomes as expected.
contract ThresholdEdgeCases is LifecycleBase {
    bytes32 internal pid;

    function setUp() public override {
        super.setUp();
        pid = _pid("threshold-edge");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
    }

    /// @notice All validators score exactly the threshold → accepted (>=)
    function test_exactThresholdScoreAccepts() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, pid, idx, 7000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx, 7000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx, 7000, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx, 7000);
        _reveal(validator2, pid, idx, 7000);
        _reveal(validator3, pid, idx, 7000);

        engine.computeConsensus(pid, idx);

        ConsensusReport memory r = engine.getConsensusReport(pid, idx);
        assertEq(r.weightedAverage, 7000, "weighted avg should be exactly 7000");

        Contribution memory c = engine.getContribution(pid, idx);
        assertEq(uint256(c.status), uint256(ContributionStatus.Accepted), "should accept at threshold");
    }

    /// @notice All validators score 1 below threshold → rejected
    function test_justBelowThresholdRejects() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, pid, idx, 6999, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx, 6999, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx, 6999, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx, 6999);
        _reveal(validator2, pid, idx, 6999);
        _reveal(validator3, pid, idx, 6999);

        engine.computeConsensus(pid, idx);

        ConsensusReport memory r = engine.getConsensusReport(pid, idx);
        assertEq(r.weightedAverage, 6999, "weighted avg should be 6999");

        Contribution memory c = engine.getContribution(pid, idx);
        assertEq(uint256(c.status), uint256(ContributionStatus.Rejected), "should reject below threshold");
    }

    /// @notice All validators score 1 above threshold → accepted
    function test_justAboveThresholdAccepts() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, pid, idx, 7001, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx, 7001, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx, 7001, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx, 7001);
        _reveal(validator2, pid, idx, 7001);
        _reveal(validator3, pid, idx, 7001);

        engine.computeConsensus(pid, idx);

        Contribution memory c = engine.getContribution(pid, idx);
        assertEq(uint256(c.status), uint256(ContributionStatus.Accepted), "should accept above threshold");
    }

    /// @notice Unanimous maximum score → accepted with high quality bonus
    function test_unanimousMaxScoreAccepts() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, pid, idx, 10_000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx, 10_000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx, 10_000, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx, 10_000);
        _reveal(validator2, pid, idx, 10_000);
        _reveal(validator3, pid, idx, 10_000);

        engine.computeConsensus(pid, idx);

        ConsensusReport memory r = engine.getConsensusReport(pid, idx);
        assertEq(r.weightedAverage, 10_000, "weighted avg should be 10000");
        assertEq(r.stdDeviation, 0, "std deviation should be 0 for unanimous");

        Contribution memory c = engine.getContribution(pid, idx);
        assertEq(uint256(c.status), uint256(ContributionStatus.Accepted));

        Reputation memory rep = engine.getReputation(contributor1, SKILL_ID);
        uint256 expectedBonus = (10_000 * 20) / C.BPS; // = 20
        uint256 expectedGain = C.SUCCESS_INCREASE + expectedBonus; // 10 + 20 = 30
        assertEq(rep.score, C.DEFAULT_REPUTATION + expectedGain, "max quality bonus applied");
    }

    /// @notice 1 high-stake honest validator (score 8000) vs 2 low-stake adversaries (score 4000).
    ///         Stake weighting should pull consensus above threshold despite 2/3 validators
    ///         scoring below it. Without stake weighting, avg would be 5333 → rejected.
    function test_stakeWeightShiftsConsensusOutcome() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        uint256 highStake = 500e18;
        uint256 lowStake = 1e18;

        _claimAndCommit(validator1, pid, idx, 8000, highStake);
        _claimAndCommit(validator2, pid, idx, 4000, lowStake);
        _claimAndCommit(validator3, pid, idx, 4000, lowStake);
        _reveal(validator1, pid, idx, 8000);
        _reveal(validator2, pid, idx, 4000);
        _reveal(validator3, pid, idx, 4000);

        engine.computeConsensus(pid, idx);

        uint256 unweightedAvg = (uint256(8000) + 4000 + 4000) / 3; // 5333
        assertLt(unweightedAvg, 7000, "unweighted avg should be below threshold");

        ConsensusReport memory r = engine.getConsensusReport(pid, idx);
        assertGe(r.weightedAverage, 7000, "stake-weighted avg should be above threshold");

        Contribution memory c = engine.getContribution(pid, idx);
        assertEq(
            uint256(c.status),
            uint256(ContributionStatus.Accepted),
            "high-stake honest validator should pull consensus above threshold"
        );

        // Low-stake validators should be outliers (far from weighted mean)
        assertTrue(engine.isValidatorOutlier(pid, idx, validator2), "low-stake adversary should be outlier");
        assertTrue(engine.isValidatorOutlier(pid, idx, validator3), "low-stake adversary should be outlier");
        assertFalse(engine.isValidatorOutlier(pid, idx, validator1), "high-stake honest should not be outlier");
    }

    /// @notice Scores that average exactly to threshold via mixed values.
    ///         7200 + 6800 + 7000 = 21000, 21000/3 = 7000 → accepted.
    function test_mixedScoresAveragingToThreshold() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, pid, idx, 7200, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx, 6800, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx, 7000, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx, 7200);
        _reveal(validator2, pid, idx, 6800);
        _reveal(validator3, pid, idx, 7000);

        engine.computeConsensus(pid, idx);

        ConsensusReport memory r = engine.getConsensusReport(pid, idx);
        assertEq(r.weightedAverage, 7000, "mixed scores should average to threshold");
        assertGt(r.stdDeviation, 0, "should have nonzero std deviation");

        Contribution memory c = engine.getContribution(pid, idx);
        assertEq(uint256(c.status), uint256(ContributionStatus.Accepted), "should accept at threshold");

        assertFalse(engine.isValidatorOutlier(pid, idx, validator1), "v1 not outlier");
        assertFalse(engine.isValidatorOutlier(pid, idx, validator2), "v2 not outlier");
        assertFalse(engine.isValidatorOutlier(pid, idx, validator3), "v3 not outlier");
    }
}
