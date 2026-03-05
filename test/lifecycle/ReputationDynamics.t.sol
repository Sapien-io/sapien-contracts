// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {LifecycleBase} from "test/lifecycle/Lifecycle.t.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {
    Project,
    ProjectStatus,
    Contribution,
    ContributionStatus,
    ConsensusReport,
    Reputation,
    ValidationClaim,
    ValidationClaimStatus
} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";

/// @title ReputationDynamics
/// @notice Category 4: Verifies that the reputation system correctly tracks performance
///         over many rounds, that decay behaves as expected, and that reputation gates
///         effectively filter participants.
contract ReputationDynamics is LifecycleBase {
    address public validator4;
    address public validatorBad;

    function setUp() public override {
        super.setUp();

        validator4 = makeAddr("val4-rep");
        validatorBad = makeAddr("valBad-rep");

        address[2] memory extras = [validator4, validatorBad];
        for (uint256 i; i < extras.length; ++i) {
            token.mint(extras[i], STAKE_AMOUNT * 30);
            vm.startPrank(extras[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 15, extras[i]);
            vm.stopPrank();
        }

        token.mint(originator, 1_000_000e18);
        vm.startPrank(originator);
        token.approve(address(engine), type(uint256).max);
        vm.stopPrank();
    }

    /// @notice Over 10 rounds, a consistently accurate validator's reputation should diverge
    ///         from a consistently inaccurate (outlier) validator's reputation.
    function test_reputationDivergesForAccurateVsOutlierValidators() public {
        bytes32 pid = _pid("rep-diverge");
        Project memory config = _defaultConfig();
        config.numberOfValidations = 5;
        _setupProjectWithConfig(pid, 200_000e18, 15, config);

        uint256 rounds = 10;

        for (uint256 i; i < rounds; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
            uint256 idx = indices[0];

            // 4 accurate validators
            _claimAndCommit(validator1, pid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator2, pid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator3, pid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator4, pid, idx, 8500, VALIDATOR_STAKE);
            // 1 consistently inaccurate validator
            _claimAndCommit(validatorBad, pid, idx, 2000, VALIDATOR_STAKE);
            _reveal(validator1, pid, idx, 8500);
            _reveal(validator2, pid, idx, 8500);
            _reveal(validator3, pid, idx, 8500);
            _reveal(validator4, pid, idx, 8500);
            _reveal(validatorBad, pid, idx, 2000);

            engine.computeConsensus(pid, idx);

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
            vm.prank(validatorBad);
            engine.settleValidator(pid, idx, nonce);
            engine.releaseContributorReward(pid, idx);
        }

        Reputation memory repAccurate = engine.getReputation(validator1, SKILL_ID);
        Reputation memory repBad = engine.getReputation(validatorBad, SKILL_ID);

        console2.log("--- Reputation Divergence (10 rounds) ---");
        console2.log("  Accurate (v1) rep:", repAccurate.score, "| success:", repAccurate.successfulActions);
        console2.log("  Outlier  (bad) rep:", repBad.score, "| success:", repBad.successfulActions);

        assertGt(repAccurate.score, repBad.score, "accurate validator should have higher rep");
        assertEq(repAccurate.successfulActions, rounds, "accurate: all successful");
        assertEq(repBad.successfulActions, 0, "outlier: zero successful");

        uint256 gap = repAccurate.score - repBad.score;
        console2.log("  Reputation gap:", gap);
        assertGt(gap, 300, "reputation gap should be significant after 10 rounds");
    }

    /// @notice A validator whose reputation degrades (via outlier slashing) should
    ///         be blocked from gated projects, while a fresh validator is allowed.
    function test_reputationGateBlocksDegradedValidators() public {
        bytes32 degradePid = _pid("rep-degrade");
        Project memory config5 = _defaultConfig();
        config5.numberOfValidations = 5;
        _setupProjectWithConfig(degradePid, 100_000e18, 5, config5);

        // Degrade validatorBad's reputation via 3 outlier rounds
        for (uint256 i; i < 3; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, degradePid, 1);
            uint256 idx = indices[0];

            _claimAndCommit(validator1, degradePid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator2, degradePid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator3, degradePid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator4, degradePid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validatorBad, degradePid, idx, 2000, VALIDATOR_STAKE);
            _reveal(validator1, degradePid, idx, 8500);
            _reveal(validator2, degradePid, idx, 8500);
            _reveal(validator3, degradePid, idx, 8500);
            _reveal(validator4, degradePid, idx, 8500);
            _reveal(validatorBad, degradePid, idx, 2000);

            engine.computeConsensus(degradePid, idx);
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(degradePid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(degradePid, idx, nonce);
            vm.prank(validatorBad);
            engine.settleValidator(degradePid, idx, nonce);
        }

        Reputation memory repDegraded = engine.getReputation(validatorBad, SKILL_ID);
        console2.log("--- Reputation Gate ---");
        console2.log("  Degraded validator rep:", repDegraded.score);
        assertLt(repDegraded.score, C.DEFAULT_REPUTATION, "should be below default after outlier penalties");

        // Use decayed score from getScore for the gate (since claimToValidate uses lazy-decayed score)
        uint256 degradedScore = repDegraded.score;

        // Create gated project requiring reputation above current degraded level
        uint256 gate = degradedScore + 1;
        bytes32 gatedPid = _pid("rep-gated");
        Project memory gatedConfig = _defaultConfig();
        gatedConfig.minValidatorReputation = uint16(gate);
        _setupProjectWithConfig(gatedPid, FUND_AMOUNT, 5, gatedConfig);

        _claimAndSubmit(contributor1, gatedPid, 1);

        // Degraded validator should be blocked
        _ensureStake(validatorBad, VALIDATOR_STAKE * 4);
        vm.prank(validatorBad);
        vm.expectRevert();
        engine.claimToValidate(gatedPid, 1);

        // Fresh validator (default rep 5000) should pass the gate
        if (gate <= C.DEFAULT_REPUTATION) {
            _ensureStake(validator1, VALIDATOR_STAKE * 4);
            vm.prank(validator1);
            engine.claimToValidate(gatedPid, 1);
            console2.log("  Fresh validator (rep 5000): allowed through gate at", gate);
        }

        console2.log("  Degraded validator: blocked at gate", gate);
    }

    /// @notice Verify that inactivity causes reputation to decay, and that the decay amount
    ///         is consistent with the configured decay rate (0.1% per day).
    function test_inactivityDecayReducesReputation() public {
        bytes32 pid = _pid("decay-test");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Initialize validator1's reputation with one successful action
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];
        _claimAndCommit(validator1, pid, idx, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx, 8500, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx, 8500);
        _reveal(validator2, pid, idx, 8500);
        _reveal(validator3, pid, idx, 8500);
        engine.computeConsensus(pid, idx);
        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(pid, idx).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pid, idx, nonce);

        Reputation memory repBefore = engine.getReputation(validator1, SKILL_ID);
        uint256 scoreBefore = repBefore.score;
        console2.log("--- Inactivity Decay ---");
        console2.log("  Score before inactivity:", scoreBefore);

        // Warp 20 days with no activity
        vm.warp(block.timestamp + 20 days);

        // Trigger another reputation update so decay is persisted
        (, uint256[] memory indices2) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx2 = indices2[0];
        _claimAndCommit(validator1, pid, idx2, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx2, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx2, 8500, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx2, 8500);
        _reveal(validator2, pid, idx2, 8500);
        _reveal(validator3, pid, idx2, 8500);
        engine.computeConsensus(pid, idx2);
        _warpPastChallengePeriod();
        uint256 nonce2 = engine.getContribution(pid, idx2).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pid, idx2, nonce2);

        Reputation memory repAfter = engine.getReputation(validator1, SKILL_ID);
        uint256 scoreAfter = repAfter.score;
        console2.log("  Score after 20-day gap + 1 action:", scoreAfter);

        // The total gap includes 20 explicit days + ~1 day from _warpPastChallengePeriod
        uint256 totalDays = (block.timestamp - repBefore.lastUpdated) / 1 days;
        uint256 expectedDecay = (scoreBefore * 10 * totalDays) / C.BPS;
        uint256 expectedScore = scoreBefore - expectedDecay + C.SUCCESS_INCREASE;

        console2.log("  Total days elapsed:", totalDays);
        console2.log("  Expected decay:", expectedDecay);
        console2.log("  Expected score:", expectedScore);

        assertLt(scoreAfter, scoreBefore, "score should decrease despite one success after long inactivity");
        assertApproxEqAbs(scoreAfter, expectedScore, 1, "score should match decay + gain formula");
    }
}
