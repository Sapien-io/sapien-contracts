// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    Contribution,
    ContributionStatus,
    ConsensusReport
} from "src/Types.sol";

/// @title SepoliaForkLifecycleTest
/// @notice Complete lifecycle test against deployed Base Sepolia contracts.
///         Skips automatically when chain ID is not 84532 (Base Sepolia).
///
///         Usage:
///           1. Start anvil fork:  anvil --fork-url $BASE_SEPOLIA_RPC_URL
///           2. Run test:          forge test --match-contract SepoliaForkLifecycleTest --rpc-url http://localhost:8545
contract SepoliaForkLifecycleTest is Test {
    uint256 constant BASE_SEPOLIA_CHAIN_ID = 84532;

    // ── Deployed addresses (deployments/base-sepolia.json) ───────────────
    address constant SAPIEN_CORE = 0xDFFEc0D8F9DF05bf3DecbdFefD650779D6481077;
    address constant SAPIEN_VAULT = 0xf0E3C676b277Ce31C2E72Cd473684FA4C8866029;
    address constant SAPIEN_TOKEN = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6;
    address constant ADMIN = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;

    SapienCore engine = SapienCore(SAPIEN_CORE);
    SapienVault vault = SapienVault(SAPIEN_VAULT);
    IERC20 token = IERC20(SAPIEN_TOKEN);

    // ── Test actors ──────────────────────────────────────────────────────
    address originator;
    address contributor1;
    address validator1;
    address validator2;
    address validator3;
    address adapter;

    // ── Test constants ───────────────────────────────────────────────────
    bytes32 constant SKILL_ID = keccak256("DATA_ANNOTATION");
    uint256 constant FUND_AMOUNT = 10_000e18;
    uint256 constant QUANTITY = 5;
    uint256 constant STAKE_AMOUNT = 100e18;
    uint256 constant VALIDATOR_STAKE = 50e18;

    function setUp() public {
        vm.skip(block.chainid != BASE_SEPOLIA_CHAIN_ID);

        originator = makeAddr("fork-originator");
        contributor1 = makeAddr("fork-contributor1");
        validator1 = makeAddr("fork-validator1");
        validator2 = makeAddr("fork-validator2");
        validator3 = makeAddr("fork-validator3");
        adapter = makeAddr("fork-adapter");

        if (!engine.isSkillRegistered(SKILL_ID)) {
            vm.prank(ADMIN);
            engine.registerSkill("DATA_ANNOTATION");
        }

        _fundAndStake(originator, FUND_AMOUNT * 2);
        _fundAndStake(contributor1, STAKE_AMOUNT * 10);
        _fundAndStake(validator1, STAKE_AMOUNT * 10);
        _fundAndStake(validator2, STAKE_AMOUNT * 10);
        _fundAndStake(validator3, STAKE_AMOUNT * 10);
    }

    // ═════════════════════════════════════════════════════════════════════
    // Complete Lifecycle Test
    // ═════════════════════════════════════════════════════════════════════

    /// @notice Full lifecycle: create → fund → claim → contribute → validate →
    ///         consensus → settle → release reward → claim reward
    function test_fullLifecycleOnFork() public {
        bytes32 projectId = keccak256(abi.encodePacked("fork-lifecycle-", block.timestamp));

        // ── Phase 1: Create & Fund ───────────────────────────────────────
        vm.startPrank(originator);

        engine.createProject(projectId, "ipfs://fork-test-metadata", _projectConfig());

        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(projectId, FUND_AMOUNT, QUANTITY, adapter);

        vm.stopPrank();

        Project memory proj = engine.getProject(projectId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Funded), "project should be Funded");
        assertEq(proj.totalQuantity, QUANTITY);
        assertEq(proj.availableSlots, QUANTITY);
        assertGt(proj.totalRewards, 0, "project should have rewards after fee");

        // ── Phase 2: Claim & Contribute ──────────────────────────────────
        _ensureStake(contributor1, STAKE_AMOUNT * 2);

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, adapter);
        uint256 index = indices[0];

        bytes32 submissionHash = keccak256("fork-test-submission-data");
        engine.contribute(claimId, index, submissionHash, "ipfs://fork-submission");
        vm.stopPrank();

        proj = engine.getProject(projectId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Active), "project should be Active");

        Contribution memory contrib = engine.getContribution(projectId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Pending));
        assertEq(contrib.contributor, contributor1);
        assertGt(contrib.rewardRate, 0, "contribution should have a reward rate");

        Claim memory claim = engine.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(ClaimStatus.Completed));

        // ── Phase 3: Validation (3x commit-reveal) ──────────────────────
        _commitAndReveal(validator1, projectId, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, index, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, index, 7500, VALIDATOR_STAKE);

        assertEq(engine.getRevealCount(projectId, index), 3, "all 3 validators should have revealed");

        // ── Phase 4: Compute Consensus ───────────────────────────────────
        engine.computeConsensus(projectId, index);

        ConsensusReport memory report = engine.getConsensusReport(projectId, index);
        assertTrue(report.computed, "consensus should be computed");
        assertGe(report.weightedAverage, 7000, "weighted avg should meet threshold");

        contrib = engine.getContribution(projectId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted), "contribution should be accepted");
        assertGt(contrib.challengeEndsAt, 0, "challenge period should be set");

        // ── Phase 5: Settle Validators ───────────────────────────────────
        vm.warp(block.timestamp + engine.challengePeriod() + 1);

        uint256 nonce = contrib.consensusNonce;

        vm.prank(validator1);
        engine.settleValidator(projectId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projectId, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(projectId, index, nonce);

        assertTrue(engine.isValidatorSettled(projectId, index, nonce, validator1));
        assertTrue(engine.isValidatorSettled(projectId, index, nonce, validator2));
        assertTrue(engine.isValidatorSettled(projectId, index, nonce, validator3));

        uint256 totalValRewards = engine.getPendingRewards(validator1, SAPIEN_TOKEN)
            + engine.getPendingRewards(validator2, SAPIEN_TOKEN) + engine.getPendingRewards(validator3, SAPIEN_TOKEN);
        assertGt(totalValRewards, 0, "validators should have earned rewards");

        // ── Phase 6: Release Contributor Reward ──────────────────────────
        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projectId, index);

        uint256 contribReward = engine.getPendingRewards(contributor1, SAPIEN_TOKEN);
        assertGt(contribReward, 0, "contributor should have pending reward");

        // ── Phase 7: Claim All Rewards ───────────────────────────────────
        uint256 balBefore = token.balanceOf(contributor1);
        vm.prank(contributor1);
        engine.claimReward(SAPIEN_TOKEN);
        assertGt(token.balanceOf(contributor1), balBefore, "contributor balance should increase");

        balBefore = token.balanceOf(validator1);
        vm.prank(validator1);
        engine.claimReward(SAPIEN_TOKEN);
        assertGt(token.balanceOf(validator1), balBefore, "validator1 balance should increase");

        balBefore = token.balanceOf(validator2);
        vm.prank(validator2);
        engine.claimReward(SAPIEN_TOKEN);
        assertGt(token.balanceOf(validator2), balBefore, "validator2 balance should increase");

        balBefore = token.balanceOf(validator3);
        vm.prank(validator3);
        engine.claimReward(SAPIEN_TOKEN);
        assertGt(token.balanceOf(validator3), balBefore, "validator3 balance should increase");

        uint256 adapterPending = engine.getPendingRewards(adapter, SAPIEN_TOKEN);
        assertGt(adapterPending, 0, "adapter should have pending fees");
        balBefore = token.balanceOf(adapter);
        vm.prank(adapter);
        engine.claimReward(SAPIEN_TOKEN);
        assertEq(token.balanceOf(adapter) - balBefore, adapterPending, "adapter should receive exact pending amount");
    }

    // ═════════════════════════════════════════════════════════════════════
    // Internal Helpers
    // ═════════════════════════════════════════════════════════════════════

    function _projectConfig() internal pure returns (Project memory) {
        return Project({
            originator: address(0),
            rewardToken: SAPIEN_TOKEN,
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
    }

    function _fundAndStake(address user, uint256 amount) internal {
        deal(SAPIEN_TOKEN, user, amount);
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(amount / 2, user);
        vm.stopPrank();
    }

    function _ensureStake(address user, uint256 needed) internal {
        uint256 available = vault.availableBalance(user);
        if (available >= needed) return;

        uint256 deficit = needed - available + 1e18;
        deal(SAPIEN_TOKEN, user, token.balanceOf(user) + deficit);
        vm.startPrank(user);
        token.approve(address(vault), deficit);
        vault.deposit(deficit, user);
        vm.stopPrank();
    }

    function _commitAndReveal(address val, bytes32 projectId, uint256 index, uint256 score, uint256 stakeAmt)
        internal
    {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, index));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(val, stakeAmt * 2);

        vm.startPrank(val);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projectId, index, commitHash, stakeAmt, address(0));
        engine.revealValidation(projectId, index, score, salt);
        vm.stopPrank();
    }
}
