// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {LifecycleBase} from "test/lifecycle/Lifecycle.t.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus, ConsensusReport, Reputation} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";

/// @title QualitySeparation
/// @notice Category 1: Verifies that the protocol creates clear economic and reputational
///         divergence between good-quality and bad-quality contributors over multiple rounds.
contract QualitySeparation is LifecycleBase {
    bytes32 internal pid;
    uint256 internal constant LARGE_FUND = 200_000e18;
    uint256 internal constant LARGE_QTY = 20;

    function setUp() public override {
        super.setUp();
        token.mint(originator, LARGE_FUND);
        vm.startPrank(originator);
        token.approve(address(engine), type(uint256).max);
        vm.stopPrank();
        pid = _pid("quality-sep");
        _setupProject(pid, LARGE_FUND, LARGE_QTY);
    }

    /// @notice Over 8 rounds, a consistently good contributor should outperform a consistently
    ///         bad one in reputation, successful action count, and accumulated rewards.
    function test_goodContributorOutperformsBadContributor() public {
        uint256 rounds = 8;

        for (uint256 i; i < rounds; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
            uint256 idx = indices[0];

            _validate(validator1, pid, idx, 8500, VALIDATOR_STAKE);
            _validate(validator2, pid, idx, 8500, VALIDATOR_STAKE);
            _validate(validator3, pid, idx, 8500, VALIDATOR_STAKE);
            engine.computeConsensus(pid, idx);

            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(pid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator2);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator3);
            engine.settleValidator(pid, idx, nonce);
            engine.releaseContributorReward(pid, idx);
        }

        for (uint256 i; i < rounds; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor2, pid, 1);
            uint256 idx = indices[0];

            _validate(validator1, pid, idx, 3000, VALIDATOR_STAKE);
            _validate(validator2, pid, idx, 3000, VALIDATOR_STAKE);
            _validate(validator3, pid, idx, 3000, VALIDATOR_STAKE);
            engine.computeConsensus(pid, idx);

            // Settle validators before recycling
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(pid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator2);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator3);
            engine.settleValidator(pid, idx, nonce);
        }

        Reputation memory repGood = engine.getReputation(contributor1, SKILL_ID);
        Reputation memory repBad = engine.getReputation(contributor2, SKILL_ID);

        console2.log("--- Quality Separation Results ---");
        console2.log("  Good contributor rep:", repGood.score, "| actions:", repGood.totalActions);
        console2.log("  Bad  contributor rep:", repBad.score, "| actions:", repBad.totalActions);

        assertGt(repGood.score, repBad.score, "good contributor should have higher reputation");
        assertEq(repGood.successfulActions, rounds, "good contributor: all successful");
        assertEq(repBad.successfulActions, 0, "bad contributor: zero successful");

        uint256 rewardsGood = engine.getPendingRewards(contributor1, address(token));
        uint256 rewardsBad = engine.getPendingRewards(contributor2, address(token));

        console2.log("  Good contributor rewards:", rewardsGood / 1e18, "SAPIEN");
        console2.log("  Bad  contributor rewards:", rewardsBad / 1e18, "SAPIEN");

        assertGt(rewardsGood, 0, "good contributor should have pending rewards");
        assertEq(rewardsBad, 0, "bad contributor should have zero rewards");

        uint256 repGap = repGood.score - repBad.score;
        console2.log("  Reputation gap:", repGap);
        assertGt(repGap, 200, "reputation gap should be significant (>200 points)");
    }

    /// @notice A contributor who starts with rejections but then improves should see
    ///         their reputation recover — but not fully erase the penalty history.
    function test_contributorRecoversReputationAfterRejections() public {
        uint256 rejectRounds = 3;
        uint256 acceptRounds = 5;

        // Phase 1: Rejections
        for (uint256 i; i < rejectRounds; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
            uint256 idx = indices[0];
            _validate(validator1, pid, idx, 3000, VALIDATOR_STAKE);
            _validate(validator2, pid, idx, 3000, VALIDATOR_STAKE);
            _validate(validator3, pid, idx, 3000, VALIDATOR_STAKE);
            engine.computeConsensus(pid, idx);

            // Settle validators before recycling
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(pid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator2);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator3);
            engine.settleValidator(pid, idx, nonce);
        }

        Reputation memory repAfterRejects = engine.getReputation(contributor1, SKILL_ID);
        uint256 nadir = repAfterRejects.score;
        assertLt(nadir, C.DEFAULT_REPUTATION, "reputation should drop below default after rejections");

        console2.log("--- Redemption Arc ---");
        console2.log("  After", rejectRounds, "rejections - rep:", nadir);

        // Phase 2: Acceptances (redemption)
        for (uint256 i; i < acceptRounds; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
            uint256 idx = indices[0];
            _validate(validator1, pid, idx, 8500, VALIDATOR_STAKE);
            _validate(validator2, pid, idx, 8500, VALIDATOR_STAKE);
            _validate(validator3, pid, idx, 8500, VALIDATOR_STAKE);
            engine.computeConsensus(pid, idx);
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(pid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator2);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator3);
            engine.settleValidator(pid, idx, nonce);
            engine.releaseContributorReward(pid, idx);
        }

        Reputation memory repAfterRedemption = engine.getReputation(contributor1, SKILL_ID);
        uint256 recovered = repAfterRedemption.score;

        console2.log("  After", acceptRounds, "acceptances - rep:", recovered);
        console2.log("  Recovery:", recovered - nadir, "points");

        assertGt(recovered, nadir, "reputation should recover after acceptances");
        assertEq(repAfterRedemption.successfulActions, acceptRounds);
        assertEq(repAfterRedemption.totalActions, rejectRounds + acceptRounds);
    }

    /// @notice Two accepted contributions with different quality levels should produce
    ///         different reputation bonuses: excellent (9500) vs mediocre (7100).
    function test_higherQualityScoreYieldsHigherReputationBonus() public {
        bytes32 pidBonus = _pid("quality-bonus");
        _setupProject(pidBonus, FUND_AMOUNT, 5);

        // Contributor 1: excellent quality (9500)
        (, uint256[] memory indicesA) = _claimAndSubmit(contributor1, pidBonus, 1);
        uint256 idxA = indicesA[0];
        _validate(validator1, pidBonus, idxA, 9500, VALIDATOR_STAKE);
        _validate(validator2, pidBonus, idxA, 9500, VALIDATOR_STAKE);
        _validate(validator3, pidBonus, idxA, 9500, VALIDATOR_STAKE);
        engine.computeConsensus(pidBonus, idxA);

        // Contributor 2: mediocre quality (7100)
        (, uint256[] memory indicesB) = _claimAndSubmit(contributor2, pidBonus, 1);
        uint256 idxB = indicesB[0];
        _validate(validator1, pidBonus, idxB, 7100, VALIDATOR_STAKE);
        _validate(validator2, pidBonus, idxB, 7100, VALIDATOR_STAKE);
        _validate(validator3, pidBonus, idxB, 7100, VALIDATOR_STAKE);
        engine.computeConsensus(pidBonus, idxB);

        Reputation memory repExcellent = engine.getReputation(contributor1, SKILL_ID);
        Reputation memory repMediocre = engine.getReputation(contributor2, SKILL_ID);

        console2.log("--- Quality Bonus Differentiation ---");
        console2.log("  Excellent (9500) contributor rep:", repExcellent.score);
        console2.log("  Mediocre  (7100) contributor rep:", repMediocre.score);

        assertGt(repExcellent.score, repMediocre.score, "higher quality should yield higher reputation");
        assertGt(repExcellent.score, C.DEFAULT_REPUTATION, "excellent should be above default");
        assertGt(repMediocre.score, C.DEFAULT_REPUTATION, "mediocre should still be above default");

        uint256 excellentBonus = (9500 * 20) / C.BPS; // 19
        uint256 mediocreBonus = (7100 * 20) / C.BPS; // 14
        uint256 expectedGap = excellentBonus - mediocreBonus; // 5
        uint256 actualGap = repExcellent.score - repMediocre.score;
        assertEq(actualGap, expectedGap, "gap should equal difference in quality bonuses");
    }
}
