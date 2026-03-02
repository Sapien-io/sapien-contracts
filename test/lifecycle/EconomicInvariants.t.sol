// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {LifecycleBase} from "test/lifecycle/Lifecycle.t.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus, ConsensusReport, Reputation} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";

/// @title EconomicInvariants
/// @notice Category 3: Verifies that the protocol remains solvent at every lifecycle step,
///         funds are conserved across mixed outcomes, and escrow drains are bounded.
contract EconomicInvariants is LifecycleBase {
    function setUp() public override {
        super.setUp();
        token.mint(originator, 500_000e18);
        vm.startPrank(originator);
        token.approve(address(engine), type(uint256).max);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _sumPendingRewards() internal view returns (uint256 total) {
        address[7] memory actors = [contributor1, contributor2, validator1, validator2, validator3, adapter, originator];
        for (uint256 i; i < actors.length; ++i) {
            total += engine.getPendingRewards(actors[i], address(token));
        }
    }

    function _assertSolvent(bytes32 projectId, string memory checkpoint) internal view {
        uint256 engineBal = token.balanceOf(address(engine));
        uint256 escrow = engine.getProjectEscrow(projectId, address(token));
        uint256 pending = _sumPendingRewards();
        assertGe(engineBal, escrow + pending, string.concat("insolvent at: ", checkpoint));
    }

    // ═══════════════════════════════════════════════════════════════════
    // Tests
    // ═══════════════════════════════════════════════════════════════════

    /// @notice Check solvency invariant at every major lifecycle step:
    ///         fund → claim → contribute → validate → consensus → settle → release → claim reward.
    function test_engineSolventAtEveryLifecycleStep() public {
        bytes32 pid = _pid("solvent-steps");

        // Step 1: Fund
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
        _assertSolvent(pid, "after fund");

        // Step 2: Claim & Submit
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];
        _assertSolvent(pid, "after claim+submit");

        // Step 3: Validate
        _claimAndCommit(validator1, pid, idx, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx, 8500, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx, 8500);
        _reveal(validator2, pid, idx, 8500);
        _reveal(validator3, pid, idx, 8500);
        _assertSolvent(pid, "after validation");

        // Step 4: Compute consensus
        engine.computeConsensus(pid, idx);
        _assertSolvent(pid, "after consensus");

        // Step 5: Settle validators
        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(pid, idx).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pid, idx, nonce);
        _assertSolvent(pid, "after settle v1");
        vm.prank(validator2);
        engine.settleValidator(pid, idx, nonce);
        _assertSolvent(pid, "after settle v2");
        vm.prank(validator3);
        engine.settleValidator(pid, idx, nonce);
        _assertSolvent(pid, "after settle v3");

        // Step 6: Release contributor reward
        engine.releaseContributorReward(pid, idx);
        _assertSolvent(pid, "after release");

        // Step 7: Claim rewards
        vm.prank(contributor1);
        engine.claimReward(address(token));
        _assertSolvent(pid, "after contributor claim");

        vm.prank(validator1);
        engine.claimReward(address(token));
        _assertSolvent(pid, "after validator claim");

        console2.log("--- Solvency Check ---");
        console2.log("  Engine balance:", token.balanceOf(address(engine)) / 1e18);
        console2.log("  Escrow remaining:", engine.getProjectEscrow(pid, address(token)) / 1e18);
        console2.log("  Pending rewards:", _sumPendingRewards() / 1e18);
    }

    /// @notice Process 3 accepted + 2 rejected contributions and verify the accounting
    ///         equation: funded = treasury + engine_balance + claimed_rewards.
    function test_fundsConservedAcrossMixedOutcomes() public {
        bytes32 pid = _pid("funds-conservation");
        uint256 fundAmt = 50_000e18;

        uint256 treasuryBefore = token.balanceOf(treasury);
        _setupProject(pid, fundAmt, 8);

        // 3 accepted rounds
        for (uint256 i; i < 3; ++i) {
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
            vm.prank(validator2);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator3);
            engine.settleValidator(pid, idx, nonce);
            engine.releaseContributorReward(pid, idx);
        }

        // 2 rejected rounds
        for (uint256 i; i < 2; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor2, pid, 1);
            uint256 idx = indices[0];
            _claimAndCommit(validator1, pid, idx, 3000, VALIDATOR_STAKE);
            _claimAndCommit(validator2, pid, idx, 3000, VALIDATOR_STAKE);
            _claimAndCommit(validator3, pid, idx, 3000, VALIDATOR_STAKE);
            _reveal(validator1, pid, idx, 3000);
            _reveal(validator2, pid, idx, 3000);
            _reveal(validator3, pid, idx, 3000);
            engine.computeConsensus(pid, idx);
        }

        _assertSolvent(pid, "after mixed outcomes");

        // Claim all available rewards
        uint256 totalClaimed;
        address[5] memory claimants = [contributor1, validator1, validator2, validator3, adapter];
        for (uint256 i; i < claimants.length; ++i) {
            uint256 pending = engine.getPendingRewards(claimants[i], address(token));
            if (pending > 0) {
                uint256 balBefore = token.balanceOf(claimants[i]);
                vm.prank(claimants[i]);
                engine.claimReward(address(token));
                totalClaimed += token.balanceOf(claimants[i]) - balBefore;
            }
        }

        uint256 treasuryReceived = token.balanceOf(treasury) - treasuryBefore;
        uint256 engineBalance = token.balanceOf(address(engine));
        uint256 remainingPending = _sumPendingRewards();

        console2.log("--- Funds Conservation ---");
        console2.log("  Funded:", fundAmt / 1e18);
        console2.log("  Treasury received:", treasuryReceived / 1e18);
        console2.log("  Total claimed:", totalClaimed / 1e18);
        console2.log("  Engine balance:", engineBalance / 1e18);
        console2.log("  Remaining pending:", remainingPending / 1e18);

        // Conservation: funded = treasury + claimed + engine_balance
        // (engine_balance covers remaining escrow + remaining pending)
        assertEq(fundAmt, treasuryReceived + totalClaimed + engineBalance, "funds should be fully conserved");
    }

    /// @notice For a single accepted contribution, verify the escrow drain equals exactly
    ///         the contributor share + total validator rewards (= rewardRate).
    function test_escrowDrainEqualsRewardRate() public {
        bytes32 pid = _pid("escrow-drain");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        uint256 escrowBefore = engine.getProjectEscrow(pid, address(token));

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, pid, idx, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx, 8500, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx, 8500);
        _reveal(validator2, pid, idx, 8500);
        _reveal(validator3, pid, idx, 8500);
        engine.computeConsensus(pid, idx);

        // Track individual validator reward increments
        uint256 v1Before = engine.getPendingRewards(validator1, address(token));
        uint256 v2Before = engine.getPendingRewards(validator2, address(token));
        uint256 v3Before = engine.getPendingRewards(validator3, address(token));

        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(pid, idx).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pid, idx, nonce);
        vm.prank(validator2);
        engine.settleValidator(pid, idx, nonce);
        vm.prank(validator3);
        engine.settleValidator(pid, idx, nonce);

        uint256 totalValRewards;
        totalValRewards += engine.getPendingRewards(validator1, address(token)) - v1Before;
        totalValRewards += engine.getPendingRewards(validator2, address(token)) - v2Before;
        totalValRewards += engine.getPendingRewards(validator3, address(token)) - v3Before;

        engine.releaseContributorReward(pid, idx);

        uint256 escrowAfter = engine.getProjectEscrow(pid, address(token));
        uint256 drain = escrowBefore - escrowAfter;

        Contribution memory contrib = engine.getContribution(pid, idx);
        Project memory proj = engine.getProject(pid);
        uint256 contributorShare = (contrib.rewardRate * (C.BPS - proj.validatorRewardBps)) / C.BPS;

        console2.log("--- Escrow Drain Analysis ---");
        console2.log("  Reward rate:", contrib.rewardRate / 1e18);
        console2.log("  Contributor share:", contributorShare / 1e18);
        console2.log("  Total validator rewards:", totalValRewards / 1e18);
        console2.log("  Actual drain:", drain / 1e18);

        assertEq(drain, contributorShare + totalValRewards, "drain should equal contributor + validator shares");

        // Adapter fees are redistributed within the drain, not additional
        uint256 adapterPending = engine.getPendingRewards(adapter, address(token));
        assertGt(adapterPending, 0, "adapter should have received fees");
    }
}
