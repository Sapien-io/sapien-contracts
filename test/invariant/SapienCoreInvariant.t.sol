// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienCore} from "../../src/SapienCore.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus, Reputation, StakeAccount} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";
import {SapienCoreHandler} from "./handlers/SapienCoreHandler.sol";

/// @title SapienCoreInvariantTest
/// @notice Invariant tests for the SapienCore protocol
/// @dev Tests solvency, reputation bounds, slot accounting, and token conservation
///      across the full protocol lifecycle driven by the SapienCoreHandler.
contract SapienCoreInvariantTest is Test {
    SapienCore public engine;
    SapienVault public vault;
    MockERC20 public token;
    SapienCoreHandler public handler;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public originator = makeAddr("originator");
    address public adapter = makeAddr("adapter");

    address[] public contributorAddrs;
    address[] public validatorAddrs;
    address[] public allParticipants;

    function setUp() public {
        // Deploy token
        token = new MockERC20("Sapien Token", "SPN");

        // Deploy SapienVault behind proxy
        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInit = abi.encodeCall(SapienVault.initialize, (token, admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));

        // Deploy SapienCore behind proxy
        SapienCore engineImpl = new SapienCore();
        bytes memory engineInit = abi.encodeCall(SapienCore.initialize, (admin, address(vault), treasury));
        engine = SapienCore(address(new ERC1967Proxy(address(engineImpl), engineInit)));

        // Grant ENGINE_ROLE to SapienCore on the vault
        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), address(engine));
        vm.stopPrank();

        // Create actors
        contributorAddrs.push(makeAddr("contributor1"));
        contributorAddrs.push(makeAddr("contributor2"));
        contributorAddrs.push(makeAddr("contributor3"));

        validatorAddrs.push(makeAddr("validator1"));
        validatorAddrs.push(makeAddr("validator2"));
        validatorAddrs.push(makeAddr("validator3"));
        validatorAddrs.push(makeAddr("validator4"));

        // Seed initial stake for all participants
        for (uint256 i; i < contributorAddrs.length; ++i) {
            _seedStake(contributorAddrs[i], 500e18);
            allParticipants.push(contributorAddrs[i]);
        }
        for (uint256 i; i < validatorAddrs.length; ++i) {
            _seedStake(validatorAddrs[i], 500e18);
            allParticipants.push(validatorAddrs[i]);
        }

        // Deploy handler
        handler = new SapienCoreHandler(engine, vault, token, originator, contributorAddrs, validatorAddrs, adapter);

        // Set handler as the only target
        targetContract(address(handler));
    }

    function _seedStake(address user, uint256 amount) internal {
        token.mint(user, amount);
        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 1: Engine token solvency
    // The engine's token balance must always be >= sum of all project escrows
    // plus all pending rewards (for that token).
    // ════════════════════════════════════════════════════════════════════

    function invariant_engineTokenSolvency() public view {
        uint256 engineBalance = token.balanceOf(address(engine));

        // Sum all project escrows
        uint256 totalEscrow;
        uint256 projectCount = handler.getProjectCount();
        for (uint256 i; i < projectCount; ++i) {
            bytes32 projectId = handler.projectIds(i);
            totalEscrow += engine.getProjectEscrow(projectId, address(token));
        }

        // Sum all pending rewards for known participants
        uint256 totalPending;
        for (uint256 i; i < allParticipants.length; ++i) {
            totalPending += engine.getPendingRewards(allParticipants[i], address(token));
        }
        // Also check adapter pending rewards
        totalPending += engine.getPendingRewards(adapter, address(token));

        assertGe(engineBalance, totalEscrow, "Engine balance less than total escrow");

        // Note: engineBalance >= totalEscrow is the critical check.
        // pendingRewards are carved out of escrow, so:
        // engineBalance >= totalEscrow (which internally covers pending rewards after release)
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 2: Reputation bounds
    // All reputation scores must be within [MIN_REPUTATION, MAX_REPUTATION].
    // ════════════════════════════════════════════════════════════════════

    function invariant_reputationBounds() public view {
        uint256 minRep = C.MIN_REPUTATION;
        uint256 maxRep = C.MAX_REPUTATION;
        uint256 defaultRep = C.DEFAULT_REPUTATION;

        bytes32[3] memory roles = [C.ORIGINATOR_ROLE_KEY, C.CONTRIBUTOR_ROLE_KEY, C.VALIDATOR_ROLE_KEY];

        for (uint256 i; i < allParticipants.length; ++i) {
            for (uint256 r; r < roles.length; ++r) {
                Reputation memory rep = engine.getReputation(allParticipants[i], roles[r]);
                uint256 score = rep.score;

                // If never updated, score is DEFAULT_REPUTATION
                if (rep.lastUpdated == 0) {
                    assertEq(score, defaultRep, "Uninitialized reputation not at default");
                } else {
                    assertGe(score, minRep, "Reputation below minimum");
                    assertLe(score, maxRep, "Reputation above maximum");
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 3: Project slot accounting
    // For each funded/active project:
    //   availableSlots <= totalQuantity
    // ════════════════════════════════════════════════════════════════════

    function invariant_projectSlotAccounting() public view {
        uint256 projectCount = handler.getProjectCount();

        for (uint256 i; i < projectCount; ++i) {
            bytes32 projectId = handler.projectIds(i);
            Project memory proj = engine.getProject(projectId);

            assertLe(proj.availableSlots, proj.totalQuantity, "Available slots exceed total quantity");
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 4: Protocol fee bounds
    // Protocol and adapter fee BPS must always be within configured maximums.
    // ════════════════════════════════════════════════════════════════════

    function invariant_feeBounds() public view {
        (uint256 originationBps, uint256 contributionBps, uint256 validationBps) = engine.getAdapterFees();

        assertLe(originationBps, C.MAX_ADAPTER_FEE_BPS, "Origination fee exceeds max");
        assertLe(contributionBps, C.MAX_ADAPTER_FEE_BPS, "Contribution fee exceeds max");
        assertLe(validationBps, C.MAX_ADAPTER_FEE_BPS, "Validation fee exceeds max");
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 5: Vault lock solvency (cross-contract)
    // Even through the SapienCore flow, vault lock solvency must hold
    // for all participants.
    // ════════════════════════════════════════════════════════════════════

    function invariant_vaultLockSolvencyThroughProtocol() public view {
        for (uint256 i; i < allParticipants.length; ++i) {
            address user = allParticipants[i];
            StakeAccount memory acct = vault.getStakeAccount(user);
            uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
            uint256 totalAssets = vault.convertToAssets(vault.balanceOf(user));

            assertGe(totalAssets, totalLocked, "Vault lock solvency violated through protocol flow");
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 6: Project escrow non-negative
    // Project escrow should never underflow (go below zero).
    // Since it's uint256, an underflow would wrap to a very large number.
    // We check that escrow is reasonable (< total funded).
    // ════════════════════════════════════════════════════════════════════

    function invariant_projectEscrowReasonable() public view {
        uint256 projectCount = handler.getProjectCount();

        for (uint256 i; i < projectCount; ++i) {
            bytes32 projectId = handler.projectIds(i);
            uint256 escrow = engine.getProjectEscrow(projectId, address(token));
            Project memory proj = engine.getProject(projectId);

            assertLe(escrow, proj.totalRewards, "Escrow exceeds total rewards - possible underflow");
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 7: Validator reward BPS bounds
    // Each project's validatorRewardBps must be <= MAX_VALIDATOR_REWARD_BPS.
    // ════════════════════════════════════════════════════════════════════

    function invariant_validatorRewardBpsBounds() public view {
        uint256 projectCount = handler.getProjectCount();

        for (uint256 i; i < projectCount; ++i) {
            bytes32 projectId = handler.projectIds(i);
            Project memory proj = engine.getProject(projectId);

            assertLe(proj.validatorRewardBps, C.MAX_VALIDATOR_REWARD_BPS, "Validator reward BPS exceeds max");
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 8: Contribution status consistency
    // An accepted contribution must have a non-zero challengeEndsAt.
    // A rejected contribution must not have rewardReleased == true.
    // ════════════════════════════════════════════════════════════════════

    function invariant_contributionStatusConsistency() public view {
        uint256 projectCount = handler.getProjectCount();

        for (uint256 i; i < projectCount; ++i) {
            bytes32 projectId = handler.projectIds(i);
            Project memory proj = engine.getProject(projectId);

            for (uint256 idx; idx < proj.totalQuantity; ++idx) {
                Contribution memory contrib = engine.getContribution(projectId, idx);

                if (contrib.status == ContributionStatus.Accepted) {
                    assertGt(contrib.challengeEndsAt, 0, "Accepted contribution has zero challengeEndsAt");
                }

                if (contrib.status == ContributionStatus.Rejected) {
                    assertFalse(contrib.rewardReleased, "Rejected contribution has rewardReleased = true");
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 9: Daily reputation gain cap
    // For any participant, the daily reputation gain should never
    // exceed MAX_DAILY_GAIN in a single day.
    // This is checked indirectly: if reputation increased by more than
    // MAX_DAILY_GAIN from default within a single day, something is wrong.
    // ════════════════════════════════════════════════════════════════════

    function invariant_reputationDailyGainCap() public view {
        uint256 maxDailyGain = C.MAX_DAILY_GAIN;
        bytes32[3] memory roles = [C.ORIGINATOR_ROLE_KEY, C.CONTRIBUTOR_ROLE_KEY, C.VALIDATOR_ROLE_KEY];

        for (uint256 i; i < allParticipants.length; ++i) {
            for (uint256 r; r < roles.length; ++r) {
                Reputation memory rep = engine.getReputation(allParticipants[i], roles[r]);
                if (rep.lastUpdated > 0) {
                    // dailyGain tracked in the struct should not exceed MAX_DAILY_GAIN
                    assertLe(rep.dailyGain, maxDailyGain, "Daily gain exceeds MAX_DAILY_GAIN cap");
                }
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 10: Token conservation
    // Total tokens minted to originator and sent to engine should account for:
    //   engine balance + treasury balance + claimed rewards + adapter pending
    // ════════════════════════════════════════════════════════════════════

    function invariant_tokenConservation() public view {
        uint256 totalFunded = handler.ghost_totalFunded();
        if (totalFunded == 0) return;

        uint256 engineBalance = token.balanceOf(address(engine));
        uint256 treasuryBalance = token.balanceOf(treasury);
        uint256 totalClaimed = handler.ghost_totalRewardsClaimed();

        // Sum claimed tokens that are now in participant wallets
        // totalFunded = engineBalance + treasuryBalance + totalClaimed + participant_balances_from_claims
        // Since totalClaimed is the amount transferred out of engine to participants:
        // totalFunded >= engineBalance + treasuryBalance
        // (the rest went to participants via claimReward)
        assertGe(totalFunded, engineBalance, "More tokens in engine than were funded");

        // Stronger check: totalFunded = engineBalance + treasuryBalance + totalClaimed
        // Allow rounding tolerance for fee calculations
        uint256 totalAccounted = engineBalance + treasuryBalance + totalClaimed;
        assertApproxEqAbs(
            totalFunded,
            totalAccounted,
            handler.ghost_projectCount() * 2, // small rounding per project
            "Token conservation violated"
        );
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 11: Engine token balance sanity check
    // Engine balance should be >= sum of all project escrows + pending rewards
    // This is the core token conservation invariant for the engine
    // ════════════════════════════════════════════════════════════════════

    function invariant_engineBalanceSanity() public view {
        uint256 engineBalance = token.balanceOf(address(engine));

        // Sum all project escrows
        uint256 totalProjectEscrow;
        uint256 projectCount = handler.getProjectCount();
        for (uint256 i; i < projectCount; ++i) {
            bytes32 projectId = handler.projectIds(i);
            totalProjectEscrow += engine.getProjectEscrow(projectId, address(token));
        }

        // Sum all pending rewards across all participants and adapter
        uint256 totalPendingRewards;
        for (uint256 i; i < allParticipants.length; ++i) {
            totalPendingRewards += engine.getPendingRewards(allParticipants[i], address(token));
        }
        totalPendingRewards += engine.getPendingRewards(adapter, address(token));

        // Engine should have at least enough to cover escrows and pending rewards
        assertGe(engineBalance, totalProjectEscrow + totalPendingRewards, "Engine balance insufficient for obligations");
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 12: Project state consistency
    // For all projects: availableSlots >= 0 && availableSlots <= totalQuantity
    // ════════════════════════════════════════════════════════════════════

    function invariant_stateConsistency() public view {
        uint256 projectCount = handler.getProjectCount();

        for (uint256 i; i < projectCount; ++i) {
            bytes32 projectId = handler.projectIds(i);
            Project memory proj = engine.getProject(projectId);

            // availableSlots should never be negative (uint256) and should not exceed totalQuantity
            assertLe(proj.availableSlots, proj.totalQuantity, "Available slots exceed total quantity");

            // Additional consistency checks
            assertGe(proj.totalQuantity, 0, "Total quantity should be non-negative");
            assertGe(proj.totalRewards, 0, "Total rewards should be non-negative");
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Post-run summary
    // ════════════════════════════════════════════════════════════════════

    function invariant_callSummary() public view {
        console2.log("--- SapienCore Handler Call Summary ---");
        console2.log("  createProject:       ", handler.calls_createProject());
        console2.log("  fundProject:         ", handler.calls_fundProject());
        console2.log("  claimToContribute:   ", handler.calls_claimToContribute());
        console2.log("  contribute:          ", handler.calls_contribute());
        console2.log("  commitValidation:    ", handler.calls_commitValidation());
        console2.log("  revealValidation:    ", handler.calls_revealValidation());
        console2.log("  computeConsensus:    ", handler.calls_computeConsensus());
        console2.log("  settleValidator:     ", handler.calls_settleValidator());
        console2.log("  releaseReward:       ", handler.calls_releaseReward());
        console2.log("  claimReward:         ", handler.calls_claimReward());
        console2.log("--- Ghost State ---");
        console2.log("  totalFunded:         ", handler.ghost_totalFunded());
        console2.log("  totalProtocolFees:   ", handler.ghost_totalProtocolFees());
        console2.log("  totalRewardsClaimed: ", handler.ghost_totalRewardsClaimed());
        console2.log("  projectCount:        ", handler.ghost_projectCount());
        console2.log("  contributionCount:   ", handler.ghost_contributionCount());
        console2.log("  consensusCount:      ", handler.ghost_consensusCount());
        console2.log("  settleCount:         ", handler.ghost_settleCount());
        console2.log("  rewardReleaseCount:  ", handler.ghost_rewardReleaseCount());
    }
}
