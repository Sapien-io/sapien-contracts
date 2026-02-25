// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {LifecycleBase} from "test/lifecycle/Lifecycle.t.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus, ConsensusReport, Reputation} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";

/// @title ValidatorAlignment
/// @notice Category 2: Verifies that the protocol's incentive mechanisms correctly reward
///         honest validators and punish dishonest/outlier ones, including Sybil resistance.
contract ValidatorAlignment is LifecycleBase {
    address public validator4;
    address public validator5;
    address public sybil1;
    address public sybil2;

    function setUp() public override {
        super.setUp();

        validator4 = makeAddr("val4-align");
        validator5 = makeAddr("val5-align");
        sybil1 = makeAddr("sybil1");
        sybil2 = makeAddr("sybil2");

        address[2] memory extras = [validator4, validator5];
        for (uint256 i; i < extras.length; ++i) {
            token.mint(extras[i], STAKE_AMOUNT * 20);
            vm.startPrank(extras[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 10, extras[i]);
            vm.stopPrank();
        }

        token.mint(originator, 500_000e18);
        vm.startPrank(originator);
        token.approve(address(engine), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice With 5 validators, 4 scoring 8500 and 1 scoring 2000, the outlier should be
    ///         detected, slashed, and excluded from rewards. Contribution still accepted.
    function test_outlierValidatorDetectedAndSlashed() public {
        bytes32 pid = _pid("outlier-detect");
        Project memory config = _defaultConfig();
        config.numberOfValidations = 5;
        _setupProjectWithConfig(pid, 50_000e18, 5, config);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        _validate(validator1, pid, idx, 8500, VALIDATOR_STAKE);
        _validate(validator2, pid, idx, 8500, VALIDATOR_STAKE);
        _validate(validator3, pid, idx, 8500, VALIDATOR_STAKE);
        _validate(validator4, pid, idx, 8500, VALIDATOR_STAKE);
        _validate(validator5, pid, idx, 2000, VALIDATOR_STAKE); // outlier

        uint256 outlierSharesBefore = vault.balanceOf(validator5);

        engine.computeConsensus(pid, idx);

        ConsensusReport memory r = engine.getConsensusReport(pid, idx);
        assertGe(r.weightedAverage, 7000, "weighted avg should still be above threshold");

        Contribution memory c = engine.getContribution(pid, idx);
        assertEq(uint256(c.status), uint256(ContributionStatus.Accepted), "should be accepted");

        assertTrue(engine.isValidatorOutlier(pid, idx, validator5), "v5 should be outlier");
        assertFalse(engine.isValidatorOutlier(pid, idx, validator1), "v1 should not be outlier");
        assertFalse(engine.isValidatorOutlier(pid, idx, validator2), "v2 should not be outlier");
        assertFalse(engine.isValidatorOutlier(pid, idx, validator3), "v3 should not be outlier");
        assertFalse(engine.isValidatorOutlier(pid, idx, validator4), "v4 should not be outlier");

        _warpPastChallengePeriod();
        uint256 nonce = c.consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pid, idx, nonce);
        vm.prank(validator2);
        engine.settleValidator(pid, idx, nonce);
        vm.prank(validator3);
        engine.settleValidator(pid, idx, nonce);
        vm.prank(validator4);
        engine.settleValidator(pid, idx, nonce);
        vm.prank(validator5);
        engine.settleValidator(pid, idx, nonce);

        // Outlier slashed
        assertLt(vault.balanceOf(validator5), outlierSharesBefore, "outlier should be slashed");

        // Accurate validators rewarded
        assertGt(engine.getPendingRewards(validator1, address(token)), 0, "v1 should have rewards");
        assertGt(engine.getPendingRewards(validator2, address(token)), 0, "v2 should have rewards");

        // Outlier reputation decreased
        Reputation memory repOutlier = engine.getReputation(validator5, SKILL_ID);
        assertLt(repOutlier.score, C.DEFAULT_REPUTATION, "outlier rep should decrease");

        // Accurate validator reputation increased
        Reputation memory repAccurate = engine.getReputation(validator1, SKILL_ID);
        assertGt(repAccurate.score, C.DEFAULT_REPUTATION, "accurate validator rep should increase");

        console2.log("--- Outlier Detection ---");
        console2.log("  Weighted avg:", r.weightedAverage);
        console2.log("  Outlier (v5) rep:", repOutlier.score);
        console2.log("  Accurate (v1) rep:", repAccurate.score);
        console2.log("  Outlier slashed:", (outlierSharesBefore - vault.balanceOf(validator5)) / 1e18, "shares");
    }

    /// @notice 1 honest high-stake validator (500e18) vs 2 low-stake sybils (1e18).
    ///         Stake weighting should make the honest validator dominate consensus,
    ///         accepting the contribution despite 2/3 validators scoring low.
    function test_highStakeHonestValidatorResistsSybilAttack() public {
        bytes32 pid = _pid("sybil-resist");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        uint256 highStake = 500e18;
        uint256 lowStake = 1e18;

        _validate(validator1, pid, idx, 8500, highStake); // honest
        _validate(sybil1, pid, idx, 1000, lowStake); // sybil
        _validate(sybil2, pid, idx, 1000, lowStake); // sybil

        engine.computeConsensus(pid, idx);

        Contribution memory c = engine.getContribution(pid, idx);
        assertEq(uint256(c.status), uint256(ContributionStatus.Accepted), "honest high-stake should override sybils");

        ConsensusReport memory r = engine.getConsensusReport(pid, idx);
        assertGe(r.weightedAverage, 7000, "weighted avg should be above threshold");

        assertTrue(engine.isValidatorOutlier(pid, idx, sybil1), "sybil1 should be outlier");
        assertTrue(engine.isValidatorOutlier(pid, idx, sybil2), "sybil2 should be outlier");
        assertFalse(engine.isValidatorOutlier(pid, idx, validator1), "honest validator not outlier");

        // Settle: honest validator gets all rewards, sybils slashed
        _warpPastChallengePeriod();
        uint256 nonce = c.consensusNonce;

        uint256 sybil1SharesBefore = vault.balanceOf(sybil1);
        uint256 sybil2SharesBefore = vault.balanceOf(sybil2);

        vm.prank(validator1);
        engine.settleValidator(pid, idx, nonce);
        vm.prank(sybil1);
        engine.settleValidator(pid, idx, nonce);
        vm.prank(sybil2);
        engine.settleValidator(pid, idx, nonce);

        assertGt(engine.getPendingRewards(validator1, address(token)), 0, "honest validator rewarded");
        assertLe(vault.balanceOf(sybil1), sybil1SharesBefore, "sybil1 slashed");
        assertLe(vault.balanceOf(sybil2), sybil2SharesBefore, "sybil2 slashed");

        console2.log("--- Sybil Resistance ---");
        console2.log("  Weighted avg:", r.weightedAverage);
        console2.log("  Honest validator rewards:", engine.getPendingRewards(validator1, address(token)) / 1e18);
    }

    /// @notice 3 validators scoring 7200, 6800, 7000 (split opinion). With equal stakes,
    ///         the average is exactly 7000 → accepted. No outliers.
    function test_splitOpinionResolvesAtThreshold() public {
        bytes32 pid = _pid("split-opinion");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        _validate(validator1, pid, idx, 7200, VALIDATOR_STAKE);
        _validate(validator2, pid, idx, 6800, VALIDATOR_STAKE);
        _validate(validator3, pid, idx, 7000, VALIDATOR_STAKE);

        engine.computeConsensus(pid, idx);

        ConsensusReport memory r = engine.getConsensusReport(pid, idx);
        assertEq(r.weightedAverage, 7000, "avg of 7200+6800+7000 should be 7000");

        Contribution memory c = engine.getContribution(pid, idx);
        assertEq(uint256(c.status), uint256(ContributionStatus.Accepted), "should accept at threshold");

        assertFalse(engine.isValidatorOutlier(pid, idx, validator1));
        assertFalse(engine.isValidatorOutlier(pid, idx, validator2));
        assertFalse(engine.isValidatorOutlier(pid, idx, validator3));
    }

    /// @notice Over 5 rounds with 5 validators (4 honest, 1 dishonest), the dishonest
    ///         validator should earn zero rewards while honest validators accumulate.
    function test_dishonestValidatorEarnsNothingOverTime() public {
        bytes32 pid = _pid("honest-vs-dishonest");
        Project memory config = _defaultConfig();
        config.numberOfValidations = 5;
        _setupProjectWithConfig(pid, 100_000e18, 10, config);

        uint256 rounds = 5;
        uint256 v1RewardsBefore = engine.getPendingRewards(validator1, address(token));

        for (uint256 i; i < rounds; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
            uint256 idx = indices[0];

            // 4 honest validators score accurately
            _validate(validator1, pid, idx, 8500, VALIDATOR_STAKE);
            _validate(validator2, pid, idx, 8500, VALIDATOR_STAKE);
            _validate(validator3, pid, idx, 8500, VALIDATOR_STAKE);
            _validate(validator4, pid, idx, 8500, VALIDATOR_STAKE);
            // 1 dishonest validator scores wildly wrong
            _validate(validator5, pid, idx, 2000, VALIDATOR_STAKE);

            engine.computeConsensus(pid, idx);

            assertTrue(engine.isValidatorOutlier(pid, idx, validator5), "dishonest should be outlier each round");

            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(pid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator2);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator3);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator4);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator5);
            engine.settleValidator(pid, idx, nonce);
            engine.releaseContributorReward(pid, idx);
        }

        uint256 v1RewardsAfter = engine.getPendingRewards(validator1, address(token));
        uint256 v5Rewards = engine.getPendingRewards(validator5, address(token));
        uint256 honestEarnings = v1RewardsAfter - v1RewardsBefore;

        Reputation memory repHonest = engine.getReputation(validator1, SKILL_ID);
        Reputation memory repDishonest = engine.getReputation(validator5, SKILL_ID);

        console2.log("--- Honest vs Dishonest (5 rounds) ---");
        console2.log("  Honest (v1) rewards:", honestEarnings / 1e18, "SAPIEN");
        console2.log("  Dishonest (v5) rewards:", v5Rewards / 1e18, "SAPIEN");
        console2.log("  Honest (v1) rep:", repHonest.score);
        console2.log("  Dishonest (v5) rep:", repDishonest.score);

        assertGt(honestEarnings, 0, "honest validator should have earned rewards");
        assertEq(v5Rewards, 0, "dishonest validator should have zero rewards");
        assertGt(repHonest.score, repDishonest.score, "honest should have higher reputation");
        assertLt(repDishonest.score, C.DEFAULT_REPUTATION, "dishonest rep should be below default");
    }
}
