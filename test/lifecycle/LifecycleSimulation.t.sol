// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {LifecycleBase} from "test/lifecycle/Lifecycle.t.sol";
import {
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    Contribution,
    ContributionStatus,
    ConsensusReport,
    Reputation,
    StakeAccount
} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";

/// @title LifecycleSimulation
/// @notice Full protocol lifecycle simulation: 10 projects, multi-round contributions
///         and validations, with aggregated protocol statistics printed live.
contract LifecycleSimulation is LifecycleBase {
    // ═══════════════════════════════════════════════════════════════════
    // Extra actors for the simulation
    // ═══════════════════════════════════════════════════════════════════

    address public contributor3;
    address public contributor4;
    address public validator4;
    address public validator5;

    address public adapter2;
    address public adapter3;

    // ═══════════════════════════════════════════════════════════════════
    // Aggregated stats structs
    // ═══════════════════════════════════════════════════════════════════

    struct ProjectStats {
        bytes32 projectId;
        uint256 fundAmount;
        uint256 quantity;
        uint256 consensusThreshold;
        uint256 validatorRewardBps;
        uint256 numberOfValidations;
        uint256 totalRewards;
        uint256 accepted;
        uint256 rejected;
        uint256 escrowStart;
        uint256 escrowEnd;
        ProjectStatus finalStatus;
    }

    struct ConsensusStats {
        uint256 totalConsensusRuns;
        uint256 totalAccepted;
        uint256 totalRejected;
        uint256 sumWeightedAverage;
        uint256 sumStdDeviation;
        uint256 outlierCount;
    }

    struct RewardStats {
        uint256 totalContributorRewards;
        uint256 totalValidatorRewards;
        uint256 totalAdapterFees;
        uint256 totalProtocolFees;
        uint256 totalContributorClaimed;
        uint256 totalValidatorClaimed;
        uint256 totalAdapterClaimed;
    }

    struct FundsFlowStats {
        uint256 totalFunded;
        uint256 totalEscrowStart;
        uint256 totalEscrowEnd;
        uint256 totalRefunded;
        uint256 totalSlashed;
    }

    ProjectStats[10] internal projectStats;
    ConsensusStats internal consensus;
    RewardStats internal rewards;
    FundsFlowStats internal fundsFlow;

    // Track pending reward snapshots per actor
    mapping(address => uint256) internal lastPendingSnapshot;

    // ═══════════════════════════════════════════════════════════════════
    // Setup
    // ═══════════════════════════════════════════════════════════════════

    function setUp() public override {
        super.setUp();

        contributor3 = makeAddr("contributor3");
        contributor4 = makeAddr("contributor4");
        validator4 = makeAddr("validator4");
        validator5 = makeAddr("validator5");
        adapter2 = makeAddr("adapter2");
        adapter3 = makeAddr("adapter3");

        address[4] memory extraActors = [contributor3, contributor4, validator4, validator5];
        for (uint256 i; i < extraActors.length; ++i) {
            token.mint(extraActors[i], STAKE_AMOUNT * 50);
            vm.startPrank(extraActors[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 25, extraActors[i]);
            vm.stopPrank();
        }

        // Ensure baseline actors have plenty of stake
        address[7] memory baseActors =
            [contributor1, contributor2, validator1, validator2, validator3, challenger, reporter];
        for (uint256 i; i < baseActors.length; ++i) {
            token.mint(baseActors[i], STAKE_AMOUNT * 50);
            vm.startPrank(baseActors[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 20, baseActors[i]);
            vm.stopPrank();
        }

        // Give originator plenty of tokens for 10 projects
        token.mint(originator, 1_000_000e18);
        vm.startPrank(originator);
        token.approve(address(engine), type(uint256).max);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════
    // Main simulation test
    // ═══════════════════════════════════════════════════════════════════

    function test_lifecycleSimulation_10Projects() public {
        console2.log("");
        console2.log("============================================================");
        console2.log("  SAPIEN PROTOCOL LIFECYCLE SIMULATION");
        console2.log("  10 Projects | Multi-round contributions & validations");
        console2.log("============================================================");
        console2.log("");

        uint256 treasuryStart = token.balanceOf(treasury);

        // ── Project configurations ──────────────────────────────────
        // Varying fund amounts, quantities, thresholds, validator reward %
        uint256[10] memory fundAmounts = [
            uint256(50_000e18),
            uint256(20_000e18),
            uint256(100_000e18),
            uint256(10_000e18),
            uint256(75_000e18),
            uint256(30_000e18),
            uint256(15_000e18),
            uint256(40_000e18),
            uint256(60_000e18),
            uint256(25_000e18)
        ];

        uint256[10] memory quantities = [
            uint256(5),
            uint256(3),
            uint256(8),
            uint256(2),
            uint256(6),
            uint256(4),
            uint256(3),
            uint256(5),
            uint256(7),
            uint256(4)
        ];

        uint256[10] memory thresholds = [
            uint256(7000),
            uint256(6000),
            uint256(8000),
            uint256(5000),
            uint256(7500),
            uint256(6500),
            uint256(7000),
            uint256(7000),
            uint256(6000),
            uint256(7500)
        ];

        uint256[10] memory valRewardBps = [
            uint256(2000),
            uint256(1500),
            uint256(2500),
            uint256(1000),
            uint256(2000),
            uint256(1800),
            uint256(2200),
            uint256(2000),
            uint256(1500),
            uint256(2500)
        ];

        // ── Phase 1: Create and fund all projects ───────────────────
        console2.log("--- PHASE 1: Creating and funding 10 projects ---");
        console2.log("");

        for (uint256 p; p < 10; ++p) {
            bytes32 pid = _simPid(p);
            projectStats[p].projectId = pid;
            projectStats[p].fundAmount = fundAmounts[p];
            projectStats[p].quantity = quantities[p];
            projectStats[p].consensusThreshold = thresholds[p];
            projectStats[p].validatorRewardBps = valRewardBps[p];
            projectStats[p].numberOfValidations = 3;

            Project memory config = _defaultConfig();
            config.consensusThreshold = thresholds[p];
            config.validatorRewardBps = valRewardBps[p];

            vm.startPrank(originator);
            engine.createProject(pid, "", config);
            engine.fundProject(pid, fundAmounts[p], quantities[p], _adapterFor(p));
            vm.stopPrank();

            Project memory proj = engine.getProject(pid);
            projectStats[p].totalRewards = proj.totalRewards;
            projectStats[p].escrowStart = engine.getProjectEscrow(pid, address(token));

            fundsFlow.totalFunded += fundAmounts[p];
            fundsFlow.totalEscrowStart += projectStats[p].escrowStart;

            console2.log("  Project", p);
            console2.log("    Fund:", fundAmounts[p] / 1e18, "SAPIEN");
            console2.log("    Qty:", quantities[p], "| Threshold:", thresholds[p]);
            console2.log("    Escrow:", projectStats[p].escrowStart / 1e18, "SAPIEN");
        }

        rewards.totalProtocolFees = token.balanceOf(treasury) - treasuryStart;
        console2.log("");
        console2.log("  Total protocol fees to treasury:", rewards.totalProtocolFees / 1e18, "SAPIEN");
        console2.log("");

        // ── Phase 2: Contributions and validations per project ──────
        console2.log("--- PHASE 2: Contributions, validations & consensus ---");
        console2.log("");

        // P0: 5 slots — 3 accepted, 2 rejected
        _runProjectRounds(0, 3, 2);

        // P1: 3 slots — all accepted
        _runProjectRounds(1, 3, 0);

        // P2: 8 slots — 5 accepted, 3 rejected
        _runProjectRounds(2, 5, 3);

        // P3: 2 slots — 1 accepted, 1 rejected
        _runProjectRounds(3, 1, 1);

        // P4: 6 slots — 4 accepted, 2 rejected
        _runProjectRounds(4, 4, 2);

        // P5: 4 slots — all accepted
        _runProjectRounds(5, 4, 0);

        // P6: 3 slots — 2 accepted, 1 rejected
        _runProjectRounds(6, 2, 1);

        // P7: 5 slots — 3 accepted, 2 rejected
        _runProjectRounds(7, 3, 2);

        // P8: 7 slots — all accepted
        _runProjectRounds(8, 7, 0);

        // P9: 4 slots — 2 accepted, 2 rejected
        _runProjectRounds(9, 2, 2);

        // ── Phase 3: Complete projects and collect final stats ───────
        console2.log("--- PHASE 3: Project completion & escrow refunds ---");
        console2.log("");

        for (uint256 p; p < 10; ++p) {
            bytes32 pid = projectStats[p].projectId;
            Project memory proj = engine.getProject(pid);

            if (proj.status == ProjectStatus.Active || proj.status == ProjectStatus.Funded) {
                vm.prank(originator);
                engine.completeProject(pid);
            }

            proj = engine.getProject(pid);
            projectStats[p].finalStatus = proj.status;
            projectStats[p].escrowEnd = engine.getProjectEscrow(pid, address(token));
            fundsFlow.totalEscrowEnd += projectStats[p].escrowEnd;

            if (proj.status == ProjectStatus.Completed && projectStats[p].escrowEnd > 0) {
                vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);
                uint256 balBefore = token.balanceOf(originator);
                vm.prank(originator);
                engine.refundEscrow(pid);
                uint256 refunded = token.balanceOf(originator) - balBefore;
                fundsFlow.totalRefunded += refunded;

                console2.log("  Project %d - Refunded: %d SAPIEN", p, refunded / 1e18);
            } else {
                console2.log("  Project %d - No refund (escrow: %d SAPIEN)", p, projectStats[p].escrowEnd / 1e18);
            }
        }

        // ── Phase 4: Claim all rewards ──────────────────────────────
        console2.log("");
        console2.log("--- PHASE 4: Claiming all rewards ---");
        console2.log("");

        rewards.totalContributorClaimed += _claimAllRewards(contributor1, "contributor1");
        rewards.totalContributorClaimed += _claimAllRewards(contributor2, "contributor2");
        rewards.totalContributorClaimed += _claimAllRewards(contributor3, "contributor3");
        rewards.totalContributorClaimed += _claimAllRewards(contributor4, "contributor4");

        rewards.totalValidatorClaimed += _claimAllRewards(validator1, "validator1");
        rewards.totalValidatorClaimed += _claimAllRewards(validator2, "validator2");
        rewards.totalValidatorClaimed += _claimAllRewards(validator3, "validator3");
        rewards.totalValidatorClaimed += _claimAllRewards(validator4, "validator4");
        rewards.totalValidatorClaimed += _claimAllRewards(validator5, "validator5");

        rewards.totalAdapterClaimed += _claimAllRewards(adapter, "adapter (origination)");
        rewards.totalAdapterClaimed += _claimAllRewards(adapter2, "adapter2 (contribution)");
        rewards.totalAdapterClaimed += _claimAllRewards(adapter3, "adapter3 (contribution)");

        // ── Phase 5: Print comprehensive stats ──────────────────────
        _printFinalReport();

        // ── Assertions ──────────────────────────────────────────────
        assertEq(consensus.totalConsensusRuns, consensus.totalAccepted + consensus.totalRejected);
        assertGt(rewards.totalContributorClaimed, 0, "contributors should have claimed rewards");
        assertGt(rewards.totalValidatorClaimed, 0, "validators should have claimed rewards");
        assertGt(rewards.totalProtocolFees, 0, "protocol fees collected");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Project round runner
    // ═══════════════════════════════════════════════════════════════════

    function _runProjectRounds(uint256 projectIdx, uint256 acceptCount, uint256 rejectCount) internal {
        bytes32 pid = projectStats[projectIdx].projectId;

        console2.log("  Project", projectIdx);
        console2.log("    Target: accept", acceptCount, "/ reject", rejectCount);

        // Process accepted contributions
        for (uint256 r; r < acceptCount; ++r) {
            address contrib = _contributorFor(r);
            _ensureStake(contrib, STAKE_AMOUNT * 5);

            (, uint256[] memory indices) = _claimAndSubmit(contrib, pid, 1);
            uint256 index = indices[0];

            // 3 validators with high scores
            address[3] memory vals = _validatorSet(r);
            uint256[3] memory scores = _highScores(r, projectStats[projectIdx].consensusThreshold);

            for (uint256 v; v < 3; ++v) {
                _ensureStake(vals[v], VALIDATOR_STAKE * 4);
                _validate(vals[v], pid, index, scores[v], VALIDATOR_STAKE);
            }

            engine.computeConsensus(pid, index);

            ConsensusReport memory report = engine.getConsensusReport(pid, index);
            Contribution memory contrib_ = engine.getContribution(pid, index);

            consensus.totalConsensusRuns++;
            consensus.sumWeightedAverage += report.weightedAverage;
            consensus.sumStdDeviation += report.stdDeviation;

            if (contrib_.status == ContributionStatus.Accepted) {
                consensus.totalAccepted++;
                projectStats[projectIdx].accepted++;

                // Settle validators
                _warpPastChallengePeriod();
                uint256 nonce = contrib_.consensusNonce;
                for (uint256 v; v < 3; ++v) {
                    uint256 vRewardBefore = engine.getPendingRewards(vals[v], address(token));
                    vm.prank(vals[v]);
                    engine.settleValidator(pid, index, nonce);
                    rewards.totalValidatorRewards += engine.getPendingRewards(vals[v], address(token)) - vRewardBefore;
                }

                // Check for outliers
                for (uint256 v; v < 3; ++v) {
                    if (engine.isValidatorOutlier(pid, index, vals[v])) {
                        consensus.outlierCount++;
                    }
                }

                // Release contributor reward
                vm.warp(block.timestamp + 2 days);
                uint256 contribRewardBefore = engine.getPendingRewards(contrib, address(token));
                engine.releaseContributorReward(pid, index);
                rewards.totalContributorRewards += engine.getPendingRewards(contrib, address(token))
                - contribRewardBefore;
            }
        }

        // Process rejected contributions
        for (uint256 r; r < rejectCount; ++r) {
            address contrib = _contributorFor(acceptCount + r);
            _ensureStake(contrib, STAKE_AMOUNT * 5);

            (, uint256[] memory indices) = _claimAndSubmit(contrib, pid, 1);
            uint256 index = indices[0];

            uint256 sharesBefore = vault.balanceOf(contrib);

            // 3 validators with low scores
            address[3] memory vals = _validatorSet(acceptCount + r);
            uint256[3] memory scores = _lowScores(acceptCount + r, projectStats[projectIdx].consensusThreshold);

            for (uint256 v; v < 3; ++v) {
                _ensureStake(vals[v], VALIDATOR_STAKE * 4);
                _validate(vals[v], pid, index, scores[v], VALIDATOR_STAKE);
            }

            engine.computeConsensus(pid, index);

            ConsensusReport memory report = engine.getConsensusReport(pid, index);
            consensus.totalConsensusRuns++;
            consensus.sumWeightedAverage += report.weightedAverage;
            consensus.sumStdDeviation += report.stdDeviation;
            consensus.totalRejected++;
            projectStats[projectIdx].rejected++;

            // Settle validators before recycling
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(pid, index).consensusNonce;
            for (uint256 v; v < 3; ++v) {
                vm.prank(vals[v]);
                engine.settleValidator(pid, index, nonce);
            }

            uint256 sharesAfter = vault.balanceOf(contrib);
            if (sharesBefore > sharesAfter) {
                fundsFlow.totalSlashed += sharesBefore - sharesAfter;
            }
        }

        console2.log(
            "    Done: accepted", projectStats[projectIdx].accepted, "/ rejected", projectStats[projectIdx].rejected
        );
        console2.log("");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Final report
    // ═══════════════════════════════════════════════════════════════════

    function _printFinalReport() internal view {
        console2.log("");
        console2.log("============================================================");
        console2.log("  SIMULATION RESULTS");
        console2.log("============================================================");
        console2.log("");

        // ── Per-project summary ─────────────────────────────────────
        console2.log("--- PROJECT SUMMARY ---");
        for (uint256 p; p < 10; ++p) {
            console2.log("");
            console2.log("  Project", p);
            console2.log("    Funded:      ", projectStats[p].fundAmount / 1e18, "SAPIEN");
            console2.log("    Slots:       ", projectStats[p].quantity);
            console2.log("    Threshold:   ", projectStats[p].consensusThreshold, "bps");
            console2.log("    Val Reward:  ", projectStats[p].validatorRewardBps, "bps");
            console2.log("    Accepted:    ", projectStats[p].accepted);
            console2.log("    Rejected:    ", projectStats[p].rejected);
            console2.log("    Escrow start:", projectStats[p].escrowStart / 1e18, "SAPIEN");
            console2.log("    Escrow end:  ", projectStats[p].escrowEnd / 1e18, "SAPIEN");
            console2.log("    Status:      ", _statusLabel(projectStats[p].finalStatus));
        }

        // ── Consensus statistics ────────────────────────────────────
        console2.log("");
        console2.log("--- CONSENSUS STATISTICS ---");
        console2.log("  Total consensus runs:    ", consensus.totalConsensusRuns);
        console2.log("  Total accepted:          ", consensus.totalAccepted);
        console2.log("  Total rejected:          ", consensus.totalRejected);
        if (consensus.totalConsensusRuns > 0) {
            console2.log("  Avg weighted score (bps):", consensus.sumWeightedAverage / consensus.totalConsensusRuns);
            console2.log("  Avg std deviation (bps): ", consensus.sumStdDeviation / consensus.totalConsensusRuns);
        }
        console2.log("  Outlier validators:      ", consensus.outlierCount);
        if (consensus.totalConsensusRuns > 0) {
            console2.log(
                "  Acceptance rate:         ", (consensus.totalAccepted * 10000) / consensus.totalConsensusRuns, "bps"
            );
        }

        // ── Reward statistics ───────────────────────────────────────
        console2.log("");
        console2.log("--- REWARD STATISTICS ---");
        console2.log("  Contributor rewards accrued:", rewards.totalContributorRewards / 1e18, "SAPIEN");
        console2.log("  Validator rewards accrued:  ", rewards.totalValidatorRewards / 1e18, "SAPIEN");
        console2.log("  Protocol fees (treasury):  ", rewards.totalProtocolFees / 1e18, "SAPIEN");
        console2.log("  Contributor claimed:       ", rewards.totalContributorClaimed / 1e18, "SAPIEN");
        console2.log("  Validator claimed:         ", rewards.totalValidatorClaimed / 1e18, "SAPIEN");
        console2.log("  Adapter claimed:           ", rewards.totalAdapterClaimed / 1e18, "SAPIEN");

        // ── Funds flow ──────────────────────────────────────────────
        console2.log("");
        console2.log("--- FLOW OF FUNDS ---");
        console2.log("  Total funded:          ", fundsFlow.totalFunded / 1e18, "SAPIEN");
        console2.log("  Total escrow (start):  ", fundsFlow.totalEscrowStart / 1e18, "SAPIEN");
        console2.log("  Total escrow (end):    ", fundsFlow.totalEscrowEnd / 1e18, "SAPIEN");
        console2.log("  Total refunded:        ", fundsFlow.totalRefunded / 1e18, "SAPIEN");
        console2.log("  Total slashed (shares):", fundsFlow.totalSlashed / 1e18);

        // ── Adapter fee breakdown ───────────────────────────────────
        console2.log("");
        console2.log("--- ADAPTER FEE BREAKDOWN ---");
        console2.log(
            "  adapter  (origination):", engine.getPendingRewards(adapter, address(token)) / 1e18, "SAPIEN remaining"
        );
        console2.log(
            "  adapter2 (alt):        ", engine.getPendingRewards(adapter2, address(token)) / 1e18, "SAPIEN remaining"
        );
        console2.log(
            "  adapter3 (alt):        ", engine.getPendingRewards(adapter3, address(token)) / 1e18, "SAPIEN remaining"
        );

        // ── Reputation snapshot ─────────────────────────────────────
        console2.log("");
        console2.log("--- REPUTATION SNAPSHOT ---");
        _printReputation(originator, "originator", C.ORIGINATOR_ROLE_KEY);
        _printReputation(contributor1, "contributor1", SKILL_ID);
        _printReputation(contributor2, "contributor2", SKILL_ID);
        _printReputation(contributor3, "contributor3", SKILL_ID);
        _printReputation(contributor4, "contributor4", SKILL_ID);
        _printReputation(validator1, "validator1", SKILL_ID);
        _printReputation(validator2, "validator2", SKILL_ID);
        _printReputation(validator3, "validator3", SKILL_ID);
        _printReputation(validator4, "validator4", SKILL_ID);
        _printReputation(validator5, "validator5", SKILL_ID);

        // ── Vault state ─────────────────────────────────────────────
        console2.log("");
        console2.log("--- VAULT STATE ---");
        console2.log("  Total vault assets:", vault.totalAssets() / 1e18, "SAPIEN");
        console2.log("  Total vault shares:", vault.totalSupply() / 1e18);

        // ── Token conservation check ────────────────────────────────
        console2.log("");
        console2.log("--- TOKEN CONSERVATION ---");
        uint256 engineBal = token.balanceOf(address(engine));
        console2.log("  Engine balance:    ", engineBal / 1e18, "SAPIEN");
        console2.log("  Treasury balance:  ", token.balanceOf(treasury) / 1e18, "SAPIEN");

        console2.log("");
        console2.log("============================================================");
        console2.log("  SIMULATION COMPLETE");
        console2.log("============================================================");
    }

    // ═══════════════════════════════════════════════════════════════════
    // Helpers
    // ═══════════════════════════════════════════════════════════════════

    function _simPid(uint256 idx) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("simulation-project-", idx));
    }

    function _contributorFor(uint256 roundIdx) internal view returns (address) {
        uint256 mod = roundIdx % 4;
        if (mod == 0) return contributor1;
        if (mod == 1) return contributor2;
        if (mod == 2) return contributor3;
        return contributor4;
    }

    function _validatorSet(uint256 roundIdx) internal view returns (address[3] memory) {
        uint256 mod = roundIdx % 3;
        if (mod == 0) return [validator1, validator2, validator3];
        if (mod == 1) return [validator2, validator3, validator4];
        return [validator3, validator4, validator5];
    }

    function _adapterFor(uint256 projectIdx) internal view returns (address) {
        uint256 mod = projectIdx % 3;
        if (mod == 0) return adapter;
        if (mod == 1) return adapter2;
        return adapter3;
    }

    function _highScores(uint256 seed, uint256 threshold) internal pure returns (uint256[3] memory) {
        uint256 base = threshold + 500;
        if (base > 9500) base = 9500;
        return [base + (seed * 37) % 500, base + (seed * 53) % 400, base + (seed * 71) % 600];
    }

    function _lowScores(uint256 seed, uint256 threshold) internal pure returns (uint256[3] memory) {
        uint256 base = threshold > 3000 ? threshold - 3000 : 1000;
        return [base + (seed * 41) % 500, base + (seed * 67) % 400, base + (seed * 29) % 300];
    }

    function _claimAllRewards(address user, string memory label) internal returns (uint256 claimed) {
        claimed = engine.getPendingRewards(user, address(token));
        if (claimed > 0) {
            uint256 balBefore = token.balanceOf(user);
            vm.prank(user);
            engine.claimReward(address(token));
            uint256 actual = token.balanceOf(user) - balBefore;
            console2.log("    %s claimed: %d SAPIEN", label, actual / 1e18);
            return actual;
        }
        return 0;
    }

    function _printReputation(address user, string memory label, bytes32 roleKey) internal view {
        Reputation memory rep = engine.getReputation(user, roleKey);
        console2.log("  ", label, "- score:", rep.score);
        console2.log("      actions:", rep.totalActions, "| successful:", rep.successfulActions);
    }

    function _statusLabel(ProjectStatus status) internal pure returns (string memory) {
        if (status == ProjectStatus.Created) return "Created";
        if (status == ProjectStatus.Funded) return "Funded";
        if (status == ProjectStatus.Active) return "Active";
        if (status == ProjectStatus.Completed) return "Completed";
        if (status == ProjectStatus.Cancelled) return "Cancelled";
        return "Unknown";
    }
}
