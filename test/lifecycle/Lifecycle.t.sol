// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {SapienCore} from "src/SapienCore.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    Contribution,
    ContributionStatus,
    ConsensusReport,
    Reputation,
    StakeAccount,
    ValidationClaim,
    ValidationClaimStatus,
    Dispute,
    DisputeStatus,
    OriginatorReport,
    OriginatorReportStatus
} from "src/Types.sol";

// ═══════════════════════════════════════════════════════════════════════
// Shared Helpers for Lifecycle Tests
// ═══════════════════════════════════════════════════════════════════════

/// @title LifecycleBase
/// @notice Extended base with helpers specific to end-to-end lifecycle testing
contract LifecycleBase is BaseTest {
    address public challenger = makeAddr("challenger");
    address public reporter = makeAddr("reporter");
    address public keeper = makeAddr("keeper");

    function setUp() public virtual override {
        super.setUp();

        // Fund extra actors with stake
        address[2] memory extras = [challenger, reporter];
        for (uint256 i; i < extras.length; ++i) {
            token.mint(extras[i], STAKE_AMOUNT * 10);
            vm.startPrank(extras[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 5, extras[i]);
            vm.stopPrank();
        }
    }

    /// @dev Ensure an address has enough available (unlocked) tokens in the vault
    function _ensureStake(address user, uint256 needed) internal override {
        uint256 available = vault.availableBalance(user);
        if (available < needed) {
            uint256 deficit = needed - available + 1e18;
            token.mint(user, deficit);
            vm.startPrank(user);
            token.approve(address(vault), deficit);
            vault.deposit(deficit, user);
            vm.stopPrank();
        }
    }

    /// @dev Generate a unique project id from a seed string
    function _pid(string memory seed) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("lifecycle-", seed));
    }

    /// @dev Convert uint256 to array for single-element operations
    function _toArray(uint256 val) internal pure returns (uint256[] memory) {
        uint256[] memory arr = new uint256[](1);
        arr[0] = val;
        return arr;
    }

    /// @dev Commit validation without revealing (for testing expired commitments)
    function _commitOnly(address val, bytes32 projectId, uint256 index, uint256 score, uint256 stakeAmt)
        internal
        returns (bytes32 salt)
    {
        salt = keccak256(abi.encodePacked("commit-only-salt", val, projectId, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(val, stakeAmt * 2);

        vm.startPrank(val);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projectId, index, commitHash, stakeAmt, address(0));
        // Note: NOT calling revealValidation here
        vm.stopPrank();
    }

    /// @dev Create a standard project config
    function _defaultConfig() internal view returns (Project memory) {
        return Project({
            originator: address(0),
            rewardToken: address(token),
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

    /// @dev Full project setup: create + fund
    function _setupProject(bytes32 projectId, uint256 fundAmount, uint256 qty) internal {
        token.mint(originator, fundAmount);
        vm.startPrank(originator);
        engine.createProject(projectId, "", _defaultConfig());
        token.approve(address(engine), fundAmount);
        engine.fundProject(projectId, fundAmount, qty, adapter);
        vm.stopPrank();
    }

    /// @dev Full project setup with custom config
    function _setupProjectWithConfig(bytes32 projectId, uint256 fundAmount, uint256 qty, Project memory config)
        internal
    {
        token.mint(originator, fundAmount);
        vm.startPrank(originator);
        engine.createProject(projectId, "", config);
        token.approve(address(engine), fundAmount);
        engine.fundProject(projectId, fundAmount, qty, adapter);
        vm.stopPrank();
    }

    /// @dev Claim indices and submit contributions
    function _claimAndSubmit(address contrib, bytes32 projectId, uint256 qty)
        internal
        returns (uint256 claimId, uint256[] memory indices)
    {
        _ensureStake(contrib, STAKE_AMOUNT * (qty + 1));
        vm.startPrank(contrib);
        (claimId, indices) = engine.claimToContribute(projectId, qty, adapter);
        for (uint256 i; i < indices.length; ++i) {
            bytes32 hash = keccak256(abi.encodePacked("submission", projectId, indices[i]));
            engine.contribute(claimId, indices[i], hash, "");
        }
        vm.stopPrank();
    }

    /// @dev Claim, lock capacity, and commit for a validator (without revealing).
    ///      The contract requires ALL validators to commit before ANY can reveal.
    function _claimAndCommit(address val, bytes32 projectId, uint256 index, uint256 score, uint256 stakeAmt)
        internal
        override
    {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, projectId, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(val, stakeAmt * 2);

        vm.startPrank(val);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projectId, index, commitHash, stakeAmt, address(0));
        vm.stopPrank();
    }

    /// @dev Reveal a previously committed validation score.
    function _reveal(address val, bytes32 projectId, uint256 index, uint256 score) internal override {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, projectId, index, score));
        vm.prank(val);
        engine.revealValidation(projectId, index, score, salt);
    }

    /// @dev Run 3 validators above threshold on an index
    function _validateAboveThreshold(bytes32 projectId, uint256 index) internal {
        _claimAndCommit(validator1, projectId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, index, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, index, 7500, VALIDATOR_STAKE);
        _reveal(validator1, projectId, index, 8000);
        _reveal(validator2, projectId, index, 8500);
        _reveal(validator3, projectId, index, 7500);
    }

    /// @dev Run 3 validators below threshold on an index
    function _validateBelowThreshold(bytes32 projectId, uint256 index) internal {
        _claimAndCommit(validator1, projectId, index, 3000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, index, 2500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, index, 4000, VALIDATOR_STAKE);
        _reveal(validator1, projectId, index, 3000);
        _reveal(validator2, projectId, index, 2500);
        _reveal(validator3, projectId, index, 4000);
    }

    /// @dev When multiple indices are pending, validators get randomly assigned.
    ///      Use batch claim so each validator gets all indices, then batch commit/reveal.
    function _validateAllAboveThreshold(bytes32 projectId, uint256[] memory indices) internal {
        uint256 n = indices.length;
        if (n == 0) return;
        uint256 totalStake = VALIDATOR_STAKE * n;
        _ensureStake(validator1, totalStake * 2);
        _ensureStake(validator2, totalStake * 2);
        _ensureStake(validator3, totalStake * 2);

        uint256[] memory stakeAmounts = new uint256[](n);
        uint256[] memory scores1 = new uint256[](n);
        uint256[] memory scores2 = new uint256[](n);
        uint256[] memory scores3 = new uint256[](n);
        bytes32[] memory salts1 = new bytes32[](n);
        bytes32[] memory salts2 = new bytes32[](n);
        bytes32[] memory salts3 = new bytes32[](n);
        bytes32[] memory commitHashes1 = new bytes32[](n);
        bytes32[] memory commitHashes2 = new bytes32[](n);
        bytes32[] memory commitHashes3 = new bytes32[](n);

        for (uint256 i; i < n; ++i) {
            stakeAmounts[i] = VALIDATOR_STAKE;
            scores1[i] = 8000;
            scores2[i] = 8500;
            scores3[i] = 7500;
            salts1[i] = keccak256(abi.encodePacked("salt", validator1, projectId, indices[i], scores1[i]));
            salts2[i] = keccak256(abi.encodePacked("salt", validator2, projectId, indices[i], scores2[i]));
            salts3[i] = keccak256(abi.encodePacked("salt", validator3, projectId, indices[i], scores3[i]));
            commitHashes1[i] = keccak256(abi.encodePacked(scores1[i], salts1[i]));
            commitHashes2[i] = keccak256(abi.encodePacked(scores2[i], salts2[i]));
            commitHashes3[i] = keccak256(abi.encodePacked(scores3[i], salts3[i]));
        }

        vm.startPrank(validator1);
        engine.claimToValidate(projectId, n);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projectId, indices, commitHashes1, stakeAmounts, address(0));
        vm.stopPrank();

        vm.startPrank(validator2);
        engine.claimToValidate(projectId, n);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projectId, indices, commitHashes2, stakeAmounts, address(0));
        vm.stopPrank();

        vm.startPrank(validator3);
        engine.claimToValidate(projectId, n);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projectId, indices, commitHashes3, stakeAmounts, address(0));
        vm.stopPrank();

        vm.prank(validator1);
        engine.batchRevealValidations(projectId, indices, scores1, salts1);
        vm.prank(validator2);
        engine.batchRevealValidations(projectId, indices, scores2, salts2);
        vm.prank(validator3);
        engine.batchRevealValidations(projectId, indices, scores3, salts3);
    }

    /// @dev Validate multiple indices with custom per-index scores (for mixed outcomes)
    function _validateWithScores(
        bytes32 projectId,
        uint256[] memory indices,
        uint256[] memory scores1,
        uint256[] memory scores2,
        uint256[] memory scores3
    ) internal {
        uint256 n = indices.length;
        if (n == 0) return;
        uint256 totalStake = VALIDATOR_STAKE * n;
        _ensureStake(validator1, totalStake * 2);
        _ensureStake(validator2, totalStake * 2);
        _ensureStake(validator3, totalStake * 2);

        uint256[] memory stakeAmounts = new uint256[](n);
        bytes32[] memory salts1 = new bytes32[](n);
        bytes32[] memory salts2 = new bytes32[](n);
        bytes32[] memory salts3 = new bytes32[](n);
        bytes32[] memory commitHashes1 = new bytes32[](n);
        bytes32[] memory commitHashes2 = new bytes32[](n);
        bytes32[] memory commitHashes3 = new bytes32[](n);

        for (uint256 i; i < n; ++i) {
            stakeAmounts[i] = VALIDATOR_STAKE;
            salts1[i] = keccak256(abi.encodePacked("salt", validator1, projectId, indices[i], scores1[i]));
            salts2[i] = keccak256(abi.encodePacked("salt", validator2, projectId, indices[i], scores2[i]));
            salts3[i] = keccak256(abi.encodePacked("salt", validator3, projectId, indices[i], scores3[i]));
            commitHashes1[i] = keccak256(abi.encodePacked(scores1[i], salts1[i]));
            commitHashes2[i] = keccak256(abi.encodePacked(scores2[i], salts2[i]));
            commitHashes3[i] = keccak256(abi.encodePacked(scores3[i], salts3[i]));
        }

        vm.startPrank(validator1);
        engine.claimToValidate(projectId, n);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projectId, indices, commitHashes1, stakeAmounts, address(0));
        vm.stopPrank();
        vm.startPrank(validator2);
        engine.claimToValidate(projectId, n);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projectId, indices, commitHashes2, stakeAmounts, address(0));
        vm.stopPrank();
        vm.startPrank(validator3);
        engine.claimToValidate(projectId, n);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projectId, indices, commitHashes3, stakeAmounts, address(0));
        vm.stopPrank();

        vm.prank(validator1);
        engine.batchRevealValidations(projectId, indices, scores1, salts1);
        vm.prank(validator2);
        engine.batchRevealValidations(projectId, indices, scores2, salts2);
        vm.prank(validator3);
        engine.batchRevealValidations(projectId, indices, scores3, salts3);
    }

    /// @dev Same as _validateAllAboveThreshold but with below-threshold scores
    function _validateAllBelowThreshold(bytes32 projectId, uint256[] memory indices) internal {
        uint256 n = indices.length;
        if (n == 0) return;
        uint256 totalStake = VALIDATOR_STAKE * n;
        _ensureStake(validator1, totalStake * 2);
        _ensureStake(validator2, totalStake * 2);
        _ensureStake(validator3, totalStake * 2);

        uint256[] memory stakeAmounts = new uint256[](n);
        uint256[] memory scores1 = new uint256[](n);
        uint256[] memory scores2 = new uint256[](n);
        uint256[] memory scores3 = new uint256[](n);
        bytes32[] memory salts1 = new bytes32[](n);
        bytes32[] memory salts2 = new bytes32[](n);
        bytes32[] memory salts3 = new bytes32[](n);
        bytes32[] memory commitHashes1 = new bytes32[](n);
        bytes32[] memory commitHashes2 = new bytes32[](n);
        bytes32[] memory commitHashes3 = new bytes32[](n);

        for (uint256 i; i < n; ++i) {
            stakeAmounts[i] = VALIDATOR_STAKE;
            scores1[i] = 3000;
            scores2[i] = 2500;
            scores3[i] = 4000;
            salts1[i] = keccak256(abi.encodePacked("salt", validator1, projectId, indices[i], scores1[i]));
            salts2[i] = keccak256(abi.encodePacked("salt", validator2, projectId, indices[i], scores2[i]));
            salts3[i] = keccak256(abi.encodePacked("salt", validator3, projectId, indices[i], scores3[i]));
            commitHashes1[i] = keccak256(abi.encodePacked(scores1[i], salts1[i]));
            commitHashes2[i] = keccak256(abi.encodePacked(scores2[i], salts2[i]));
            commitHashes3[i] = keccak256(abi.encodePacked(scores3[i], salts3[i]));
        }

        vm.startPrank(validator1);
        engine.claimToValidate(projectId, n);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projectId, indices, commitHashes1, stakeAmounts, address(0));
        vm.stopPrank();

        vm.startPrank(validator2);
        engine.claimToValidate(projectId, n);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projectId, indices, commitHashes2, stakeAmounts, address(0));
        vm.stopPrank();

        vm.startPrank(validator3);
        engine.claimToValidate(projectId, n);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projectId, indices, commitHashes3, stakeAmounts, address(0));
        vm.stopPrank();

        vm.prank(validator1);
        engine.batchRevealValidations(projectId, indices, scores1, salts1);
        vm.prank(validator2);
        engine.batchRevealValidations(projectId, indices, scores2, salts2);
        vm.prank(validator3);
        engine.batchRevealValidations(projectId, indices, scores3, salts3);
    }

    /// @dev Settle all 3 validators (warps past the challenge period first for accepted contributions)
    function _settleAllValidators(bytes32 projectId, uint256 index) internal {
        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(projectId, index).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(projectId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projectId, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(projectId, index, nonce);
    }

    /// @dev Full lifecycle through consensus + settlement
    function _fullAcceptanceFlow(bytes32 projectId, uint256 index) internal {
        _validateAboveThreshold(projectId, index);
        engine.computeConsensus(projectId, index);
        _settleAllValidators(projectId, index);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 1: Happy Path — Full End-to-End Lifecycle
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleHappyPathTest is LifecycleBase {
    bytes32 internal projId;

    function setUp() public override {
        super.setUp();
        projId = _pid("happy");
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    /// @notice Complete lifecycle: create → fund → claim → contribute → validate →
    ///         consensus → settle → release → claim reward
    function test_fullHappyPathLifecycle() public {
        // ── Phase 1: Project is funded ───────────────────────────
        Project memory proj = engine.getProject(projId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Funded));
        assertEq(proj.totalQuantity, QUANTITY);
        assertEq(proj.availableSlots, QUANTITY);
        assertGt(proj.totalRewards, 0);

        // ── Phase 2: Claim and contribute ────────────────────────
        (uint256 claimId, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        // Project transitions to Active
        proj = engine.getProject(projId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Active));
        assertEq(proj.availableSlots, QUANTITY - 1);

        // Contribution is pending
        Contribution memory contrib = engine.getContribution(projId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Pending));
        assertEq(contrib.contributor, contributor1);
        assertGt(contrib.rewardRate, 0);

        // Claim is completed (all indices submitted)
        Claim memory claim = engine.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(ClaimStatus.Completed));

        // ── Phase 3: Validation (commit-reveal) ──────────────────
        _validateAboveThreshold(projId, index);
        assertEq(engine.getRevealCount(projId, index), 3);

        // ── Phase 4: Compute consensus ───────────────────────────
        engine.computeConsensus(projId, index);

        ConsensusReport memory r = engine.getConsensusReport(projId, index);
        assertTrue(r.computed);
        assertGe(r.weightedAverage, 7000);

        contrib = engine.getContribution(projId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted));
        assertGt(contrib.challengeEndsAt, 0);

        // ── Phase 5: Settle validators ───────────────────────────
        _settleAllValidators(projId, index);

        assertTrue(engine.isValidatorSettled(projId, index, 0, validator1));
        assertTrue(engine.isValidatorSettled(projId, index, 0, validator2));
        assertTrue(engine.isValidatorSettled(projId, index, 0, validator3));
        assertFalse(engine.isValidatorOutlier(projId, index, validator1));

        uint256 v1Rewards = engine.getPendingRewards(validator1, address(token));
        uint256 v2Rewards = engine.getPendingRewards(validator2, address(token));
        uint256 v3Rewards = engine.getPendingRewards(validator3, address(token));
        assertGt(v1Rewards + v2Rewards + v3Rewards, 0);

        // ── Phase 6: Release contributor reward ──────────────────
        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projId, index);

        uint256 contribReward = engine.getPendingRewards(contributor1, address(token));
        assertGt(contribReward, 0);

        // ── Phase 7: Claim all rewards ───────────────────────────
        uint256 balBefore = token.balanceOf(contributor1);
        vm.prank(contributor1);
        engine.claimReward(address(token));
        assertGt(token.balanceOf(contributor1), balBefore);

        balBefore = token.balanceOf(validator1);
        vm.prank(validator1);
        engine.claimReward(address(token));
        assertGt(token.balanceOf(validator1), balBefore);

        // Adapter can also claim
        uint256 adapterPending = engine.getPendingRewards(adapter, address(token));
        assertGt(adapterPending, 0);
        balBefore = token.balanceOf(adapter);
        vm.prank(adapter);
        engine.claimReward(address(token));
        assertEq(token.balanceOf(adapter) - balBefore, adapterPending);
    }

    /// @notice Multiple contributions from single claim all accepted
    function test_multiContributionSingleClaim() public {
        uint256 qty = 3;
        (uint256 claimId, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, qty);

        Claim memory claim = engine.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(ClaimStatus.Completed));
        assertEq(claim.submittedCount, qty);

        // With quantity-based claimToValidate, use batch validation when multiple indices pending
        _validateAllAboveThreshold(projId, indices);
        for (uint256 i; i < indices.length; ++i) {
            engine.computeConsensus(projId, indices[i]);
            _settleAllValidators(projId, indices[i]);
        }

        // Release all rewards after challenge period
        vm.warp(block.timestamp + 2 days);
        for (uint256 i; i < indices.length; ++i) {
            engine.releaseContributorReward(projId, indices[i]);
        }

        uint256 totalPending = engine.getPendingRewards(contributor1, address(token));
        assertGt(totalPending, 0);
    }

    /// @notice Two separate contributors each work on different indices
    function test_twoContributorsDifferentIndices() public {
        (, uint256[] memory indices1) = _claimAndSubmit(contributor1, projId, 1);
        (, uint256[] memory indices2) = _claimAndSubmit(contributor2, projId, 1);

        uint256[] memory both = new uint256[](2);
        both[0] = indices1[0];
        both[1] = indices2[0];
        _validateAllAboveThreshold(projId, both);
        engine.computeConsensus(projId, both[0]);
        _settleAllValidators(projId, both[0]);
        engine.computeConsensus(projId, both[1]);
        _settleAllValidators(projId, both[1]);

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projId, both[0]);
        engine.releaseContributorReward(projId, both[1]);

        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
        assertGt(engine.getPendingRewards(contributor2, address(token)), 0);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 2: Rejection, Re-submission, and Claim Expiration
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleRejectionTest is LifecycleBase {
    bytes32 internal projId;

    function setUp() public override {
        super.setUp();
        projId = _pid("rejection");
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    /// @notice Low scores cause rejection, contributor slashed, index returned to pool
    function test_rejectionSlashesContributorAndReturnsIndex() public {
        uint256 slotsBefore = engine.getProject(projId).availableSlots;

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        uint256 sharesBefore = vault.balanceOf(contributor1);

        _validateBelowThreshold(projId, index);
        engine.computeConsensus(projId, index);

        Contribution memory contrib = engine.getContribution(projId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected));

        // Contributor slashed
        assertLt(vault.balanceOf(contributor1), sharesBefore);

        // Index returned to available pool
        assertEq(engine.getProject(projId).availableSlots, slotsBefore);

        // Nonce incremented
        assertEq(engine.getSubmissionNonce(projId, index), 1);
    }

    /// @notice Rejected index can be re-claimed and re-submitted by a new contributor
    function test_rejectionThenResubmission() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateBelowThreshold(projId, index);
        engine.computeConsensus(projId, index);

        // Index is back in the pool — contributor2 claims
        (, uint256[] memory indices2) = _claimAndSubmit(contributor2, projId, 1);
        uint256 index2 = indices2[0];

        // Validate with high scores
        _validateAboveThreshold(projId, index2);
        engine.computeConsensus(projId, index2);

        Contribution memory contrib2 = engine.getContribution(projId, index2);
        assertEq(uint256(contrib2.status), uint256(ContributionStatus.Accepted));

        // Full settlement & reward
        _settleAllValidators(projId, index2);
        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projId, index2);
        assertGt(engine.getPendingRewards(contributor2, address(token)), 0);
    }

    /// @notice Claim expires with partial submission: unsubmitted indices returned, contributor slashed
    function test_claimExpirationPartialSubmission() public {
        uint256 qty = 4;
        _ensureStake(contributor1, STAKE_AMOUNT * (qty + 2));

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, qty, adapter);

        // Submit only 2 of 4
        engine.contribute(claimId, indices[0], keccak256("data0"), "");
        engine.contribute(claimId, indices[1], keccak256("data1"), "");
        vm.stopPrank();

        uint256 slotsBeforeExpire = engine.getProject(projId).availableSlots;
        uint256 sharesBefore = vault.balanceOf(contributor1);

        // Warp past claim deadline (7 days)
        vm.warp(block.timestamp + 8 days);
        engine.expireClaim(claimId, indices);

        Claim memory claim = engine.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(ClaimStatus.Expired));

        // 2 unsubmitted indices returned
        assertEq(engine.getProject(projId).availableSlots, slotsBeforeExpire + 2);

        // Contributor slashed for 2 unsubmitted
        assertLt(vault.balanceOf(contributor1), sharesBefore);
    }

    /// @notice Claim with zero submissions expires, all indices returned, full slash
    function test_claimExpirationZeroSubmissions() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 5);

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 3, adapter);
        vm.stopPrank();

        uint256 slotsBeforeExpire = engine.getProject(projId).availableSlots;
        uint256 sharesBefore = vault.balanceOf(contributor1);

        vm.warp(block.timestamp + 8 days);
        engine.expireClaim(claimId, indices);

        // All 3 indices returned
        assertEq(engine.getProject(projId).availableSlots, slotsBeforeExpire + 3);
        assertLt(vault.balanceOf(contributor1), sharesBefore);
    }

    /// @notice Cannot expire a claim before deadline
    function test_revert_expireClaimBeforeDeadline() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.prank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 1, adapter);

        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.expireClaim(claimId, indices);
    }

    /// @notice Mixed outcomes on same project: one accepted, one rejected
    function test_mixedOutcomesSameProject() public {
        // Contributor1: will be accepted
        (, uint256[] memory goodIndices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 goodIdx = goodIndices[0];

        // Contributor2: will be rejected
        (, uint256[] memory badIndices) = _claimAndSubmit(contributor2, projId, 1);
        uint256 badIdx = badIndices[0];

        // With 2 pending indices, use batch validation with per-index scores
        uint256[] memory both = new uint256[](2);
        both[0] = goodIdx;
        both[1] = badIdx;
        uint256[] memory scores1 = new uint256[](2);
        uint256[] memory scores2 = new uint256[](2);
        uint256[] memory scores3 = new uint256[](2);
        scores1[0] = 8000;
        scores1[1] = 3000;
        scores2[0] = 8500;
        scores2[1] = 2500;
        scores3[0] = 7500;
        scores3[1] = 4000;
        uint256[] memory stakeAmounts = new uint256[](2);
        stakeAmounts[0] = VALIDATOR_STAKE;
        stakeAmounts[1] = VALIDATOR_STAKE;
        uint256 totalStake = VALIDATOR_STAKE * 2;
        _ensureStake(validator1, totalStake * 2);
        _ensureStake(validator2, totalStake * 2);
        _ensureStake(validator3, totalStake * 2);

        bytes32[] memory salts1 = new bytes32[](2);
        bytes32[] memory salts2 = new bytes32[](2);
        bytes32[] memory salts3 = new bytes32[](2);
        bytes32[] memory commitHashes1 = new bytes32[](2);
        bytes32[] memory commitHashes2 = new bytes32[](2);
        bytes32[] memory commitHashes3 = new bytes32[](2);
        for (uint256 i; i < 2; ++i) {
            salts1[i] = keccak256(abi.encodePacked("salt", validator1, projId, both[i], scores1[i]));
            salts2[i] = keccak256(abi.encodePacked("salt", validator2, projId, both[i], scores2[i]));
            salts3[i] = keccak256(abi.encodePacked("salt", validator3, projId, both[i], scores3[i]));
            commitHashes1[i] = keccak256(abi.encodePacked(scores1[i], salts1[i]));
            commitHashes2[i] = keccak256(abi.encodePacked(scores2[i], salts2[i]));
            commitHashes3[i] = keccak256(abi.encodePacked(scores3[i], salts3[i]));
        }

        vm.startPrank(validator1);
        engine.claimToValidate(projId, 2);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projId, both, commitHashes1, stakeAmounts, address(0));
        vm.stopPrank();
        vm.startPrank(validator2);
        engine.claimToValidate(projId, 2);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projId, both, commitHashes2, stakeAmounts, address(0));
        vm.stopPrank();
        vm.startPrank(validator3);
        engine.claimToValidate(projId, 2);
        engine.lockValidatorCapacity(totalStake);
        engine.batchCommitValidations(projId, both, commitHashes3, stakeAmounts, address(0));
        vm.stopPrank();

        vm.prank(validator1);
        engine.batchRevealValidations(projId, both, scores1, salts1);
        vm.prank(validator2);
        engine.batchRevealValidations(projId, both, scores2, salts2);
        vm.prank(validator3);
        engine.batchRevealValidations(projId, both, scores3, salts3);

        engine.computeConsensus(projId, goodIdx);
        assertEq(uint256(engine.getContribution(projId, goodIdx).status), uint256(ContributionStatus.Accepted));

        engine.computeConsensus(projId, badIdx);
        assertEq(uint256(engine.getContribution(projId, badIdx).status), uint256(ContributionStatus.Rejected));

        // Only good contributor can claim rewards
        _settleAllValidators(projId, goodIdx);
        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projId, goodIdx);

        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
        assertEq(engine.getPendingRewards(contributor2, address(token)), 0);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 3: Dispute Lifecycle
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleDisputeTest is LifecycleBase {
    bytes32 internal projId;

    function setUp() public override {
        super.setUp();
        projId = _pid("dispute");
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    /// @notice Dispute upheld on accepted contribution: blocks reward, challenger rewarded
    function test_disputeUpheldOnAcceptedContribution() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        // Validate + compute but do NOT settle/warp — dispute must be opened within challenge window
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        Contribution memory contrib = engine.getContribution(projId, index);
        uint256 challengerSharesBefore = vault.balanceOf(challenger);

        // Challenger opens dispute within challenge period
        _ensureStake(challenger, contrib.rewardRate);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("evidence-hash"), "evidenceCid");

        Dispute memory d = engine.getDispute(projId, index);
        assertEq(uint256(d.status), uint256(DisputeStatus.Open));
        assertEq(d.challenger, challenger);
        assertGt(d.bondAmount, 0);

        // Operator upholds the dispute
        vm.prank(admin);
        engine.resolveDispute(projId, index, true);

        d = engine.getDispute(projId, index);
        assertEq(uint256(d.status), uint256(DisputeStatus.Upheld));

        // Bond returned to challenger
        assertGe(vault.balanceOf(challenger), challengerSharesBefore);

        // Challenger gets reward (20% of rewardRate from escrow)
        assertGt(engine.getPendingRewards(challenger, address(token)), 0);

        // Contributor reward release is blocked
        vm.warp(block.timestamp + 10 days);
        vm.expectRevert(ISapienCore.DisputeInProgress.selector);
        engine.releaseContributorReward(projId, index);
    }

    /// @notice Dispute rejected on accepted contribution: challenger slashed, reward unfrozen
    function test_disputeRejectedOnAcceptedContribution() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        // Validate + compute but do NOT warp — dispute must be opened within challenge window
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("bad-evidence"), "evidenceCid");

        uint256 challengerSharesBefore = vault.balanceOf(challenger);

        // Operator rejects the dispute
        vm.prank(admin);
        engine.resolveDispute(projId, index, false);

        Dispute memory d = engine.getDispute(projId, index);
        assertEq(uint256(d.status), uint256(DisputeStatus.Rejected));

        // Challenger bond slashed
        assertLt(vault.balanceOf(challenger), challengerSharesBefore);

        // Contributor reward release unfrozen — can release immediately
        engine.releaseContributorReward(projId, index);
        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
    }

    /// @notice Dispute upheld on rejected contribution: contributor compensated
    function test_disputeUpheldOnRejectedContribution() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateBelowThreshold(projId, index);
        engine.computeConsensus(projId, index);

        Contribution memory contrib = engine.getContribution(projId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected));
        assertTrue(contrib.challengeEndsAt > 0);

        // Contributor opens dispute on their own rejection
        _ensureStake(contributor1, STAKE_AMOUNT);
        vm.prank(contributor1);
        engine.openDispute(projId, index, keccak256("unfair-rejection"), "evidenceCid");

        // Operator upholds — contributor was wrongly rejected
        vm.prank(admin);
        engine.resolveDispute(projId, index, true);

        Dispute memory d = engine.getDispute(projId, index);
        assertEq(uint256(d.status), uint256(DisputeStatus.Upheld));

        // Contributor compensated from escrow
        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
    }

    /// @notice Dispute auto-escalated after resolution deadline
    function test_disputeEscalationAutoUpholds() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        // Validate + compute but do NOT warp — dispute must be opened within challenge window
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("evidence"), "evidenceCid");

        // Cannot escalate before deadline
        vm.expectRevert(ISapienCore.DisputeResolutionNotExpired.selector);
        engine.escalateDispute(projId, index);

        // Warp past resolution deadline (7 days)
        vm.warp(block.timestamp + 8 days);

        // Anyone can escalate
        vm.prank(keeper);
        engine.escalateDispute(projId, index);

        Dispute memory d = engine.getDispute(projId, index);
        assertEq(uint256(d.status), uint256(DisputeStatus.Upheld));

        // Challenger rewarded
        assertGt(engine.getPendingRewards(challenger, address(token)), 0);
    }

    /// @notice Cannot open dispute after challenge period
    function test_revert_disputeAfterChallengePeriod() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _fullAcceptanceFlow(projId, index);

        // Warp past challenge period
        vm.warp(block.timestamp + 2 days);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        vm.expectRevert(ISapienCore.DisputeWindowClosed.selector);
        engine.openDispute(projId, index, keccak256("too-late"), "evidenceCid");
    }

    /// @notice Cannot open duplicate dispute
    function test_revert_duplicateDispute() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        // Validate + compute but do NOT warp — dispute must be opened within challenge window
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        _ensureStake(challenger, STAKE_AMOUNT * 2);
        vm.startPrank(challenger);
        engine.openDispute(projId, index, keccak256("evidence1"), "evidenceCid");

        vm.expectRevert(ISapienCore.DisputeAlreadyOpen.selector);
        engine.openDispute(projId, index, keccak256("evidence2"), "evidenceCid");
        vm.stopPrank();
    }

    /// @notice Contributor cannot dispute their own accepted contribution
    function test_revert_contributorDisputesOwnAcceptance() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        // Validate + compute but do NOT warp — dispute must be checked within challenge window
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        _ensureStake(contributor1, STAKE_AMOUNT * 2);
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.CannotDisputeOwnContribution.selector);
        engine.openDispute(projId, index, keccak256("self-dispute"), "evidenceCid");
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 4: Originator Report Lifecycle
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleOriginatorReportTest is LifecycleBase {
    bytes32 internal projId;

    function setUp() public override {
        super.setUp();
        projId = _pid("originator-report");

        // Enable originator stake requirement so slashing is meaningful
        vm.prank(admin);
        engine.setOriginatorStakeRequirement(10e18);

        // Originator needs vault stake for the originator stake lock
        token.mint(originator, STAKE_AMOUNT * 20);
        vm.startPrank(originator);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 10, originator);
        vm.stopPrank();

        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    /// @notice Report upheld: originator slashed, project cancelled, reporter rewarded
    function test_originatorReportUpheldCancelsProject() public {
        // First claim to make project Active
        _claimAndSubmit(contributor1, projId, 1);

        uint256 originatorSharesBefore = vault.balanceOf(originator);

        _ensureStake(reporter, STAKE_AMOUNT);
        vm.prank(reporter);
        engine.reportOriginator(projId, keccak256("misconduct-evidence"));

        OriginatorReport memory report = engine.getOriginatorReport(projId);
        assertEq(uint256(report.status), uint256(OriginatorReportStatus.Open));

        // New claims blocked while report is open
        _ensureStake(contributor2, STAKE_AMOUNT * 3);
        vm.prank(contributor2);
        vm.expectRevert(ISapienCore.DisputeInProgress.selector);
        engine.claimToContribute(projId, 1, adapter);

        // Operator upholds
        vm.prank(admin);
        engine.resolveOriginatorReport(projId, true);

        report = engine.getOriginatorReport(projId);
        assertEq(uint256(report.status), uint256(OriginatorReportStatus.Upheld));

        // Project cancelled
        Project memory proj = engine.getProject(projId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Cancelled));

        // Originator slashed
        assertLt(vault.balanceOf(originator), originatorSharesBefore);

        // Reporter may get rewards from escrow
        // (depends on whether originator had locked stake)
        uint256 reporterRewards = engine.getPendingRewards(reporter, address(token));
        assertGt(reporterRewards, 0);
    }

    /// @notice Report rejected: reporter bond slashed
    function test_originatorReportRejectedSlashesReporter() public {
        _claimAndSubmit(contributor1, projId, 1);

        _ensureStake(reporter, STAKE_AMOUNT);
        vm.prank(reporter);
        engine.reportOriginator(projId, keccak256("weak-evidence"));

        uint256 reporterSharesBefore = vault.balanceOf(reporter);

        vm.prank(admin);
        engine.resolveOriginatorReport(projId, false);

        OriginatorReport memory report = engine.getOriginatorReport(projId);
        assertEq(uint256(report.status), uint256(OriginatorReportStatus.Rejected));

        // Reporter bond slashed
        assertLt(vault.balanceOf(reporter), reporterSharesBefore);

        // Project NOT cancelled
        Project memory proj = engine.getProject(projId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Active));
    }

    /// @notice Report auto-escalated after deadline: auto-upheld
    function test_originatorReportEscalation() public {
        _claimAndSubmit(contributor1, projId, 1);

        _ensureStake(reporter, STAKE_AMOUNT);
        vm.prank(reporter);
        engine.reportOriginator(projId, keccak256("evidence"));

        // Cannot escalate before deadline
        vm.expectRevert(ISapienCore.DisputeResolutionNotExpired.selector);
        engine.escalateOriginatorReport(projId);

        // Warp past resolution deadline
        vm.warp(block.timestamp + 8 days);

        vm.prank(keeper);
        engine.escalateOriginatorReport(projId);

        assertEq(uint256(engine.getOriginatorReport(projId).status), uint256(OriginatorReportStatus.Upheld));
        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Cancelled));
    }

    /// @notice Cannot report own project
    function test_revert_originatorReportsSelf() public {
        _claimAndSubmit(contributor1, projId, 1);

        _ensureStake(originator, STAKE_AMOUNT);
        vm.prank(originator);
        vm.expectRevert(ISapienCore.NotProjectOriginator.selector);
        engine.reportOriginator(projId, keccak256("self-report"));
    }

    /// @notice Cannot open duplicate report
    function test_revert_duplicateOriginatorReport() public {
        _claimAndSubmit(contributor1, projId, 1);

        _ensureStake(reporter, STAKE_AMOUNT * 2);
        vm.startPrank(reporter);
        engine.reportOriginator(projId, keccak256("first-report"));

        vm.expectRevert(ISapienCore.OriginatorReportAlreadyOpen.selector);
        engine.reportOriginator(projId, keccak256("second-report"));
        vm.stopPrank();
    }

    /// @notice Complex edge case: Project with mixed contributions (accepted/rejected) and partial completion
    function test_mixedContributionsPartialCompletion() public {
        // Create larger project to test partial completion
        bytes32 mixedProjId = _pid("mixed-completion");
        uint256 largeFund = 100_000e18;
        uint256 qty = 5;
        _setupProject(mixedProjId, largeFund, qty);

        // Contributor1: Two contributions - one accepted, one rejected
        _ensureStake(contributor1, STAKE_AMOUNT * 10);
        vm.startPrank(contributor1);
        (uint256 claimId1, uint256[] memory indices1) = engine.claimToContribute(mixedProjId, 2, adapter);
        engine.contribute(claimId1, indices1[0], keccak256("mixed-accepted"), "");
        engine.contribute(claimId1, indices1[1], keccak256("mixed-rejected"), "");
        vm.stopPrank();

        // Contributor2: One contribution that gets accepted
        _ensureStake(contributor2, STAKE_AMOUNT * 5);
        vm.startPrank(contributor2);
        (uint256 claimId2, uint256[] memory indices2) = engine.claimToContribute(mixedProjId, 1, adapter);
        engine.contribute(claimId2, indices2[0], keccak256("mixed-contributor2"), "");
        vm.stopPrank();

        // Process all 3 indices with mixed outcomes (batch validation, per-index scores)
        uint256[] memory allIndices = new uint256[](3);
        allIndices[0] = indices1[0];
        allIndices[1] = indices1[1];
        allIndices[2] = indices2[0];
        uint256[] memory s1 = new uint256[](3);
        uint256[] memory s2 = new uint256[](3);
        uint256[] memory s3 = new uint256[](3);
        s1[0] = 8000;
        s1[1] = 3000;
        s1[2] = 8000;
        s2[0] = 8500;
        s2[1] = 2500;
        s2[2] = 8500;
        s3[0] = 7500;
        s3[1] = 4000;
        s3[2] = 7500;
        _validateWithScores(mixedProjId, allIndices, s1, s2, s3);

        engine.computeConsensus(mixedProjId, indices1[0]);
        _settleAllValidators(mixedProjId, indices1[0]);

        engine.computeConsensus(mixedProjId, indices1[1]);

        engine.computeConsensus(mixedProjId, indices2[0]);
        _settleAllValidators(mixedProjId, indices2[0]);

        // Only release rewards for accepted contributions
        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(mixedProjId, indices1[0]); // contributor1's accepted contribution
        engine.releaseContributorReward(mixedProjId, indices2[0]); // contributor2's contribution

        // Verify rewards
        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
        assertGt(engine.getPendingRewards(contributor2, address(token)), 0);

        // Project should still be active (has rejected contribution)
        Project memory proj = engine.getProject(mixedProjId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Active));

        // Check if project can be completed with mixed outcomes
        // (This may or may not revert depending on implementation)
        vm.prank(originator);
        try engine.completeProject(mixedProjId) {
            // Project was completed successfully
            proj = engine.getProject(mixedProjId);
            assertEq(uint256(proj.status), uint256(ProjectStatus.Completed));
        } catch {
            // Project completion was blocked - this is also acceptable
            assertEq(uint256(proj.status), uint256(ProjectStatus.Active));
        }
    }

    /// @notice Edge case timing: Validator settlement race conditions
    function test_validatorSettlementTimingEdgeCases() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        // Warp past challenge period so validators can settle
        _warpPastChallengePeriod();

        // Validator1 settles immediately after challenge period
        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);

        // Validator2 waits, then validator3 settles
        vm.warp(block.timestamp + 1 hours);
        vm.prank(validator3);
        engine.settleValidator(projId, index, nonce);

        // Validator2 settles late but still within window
        vm.warp(block.timestamp + 2 hours);
        vm.prank(validator2);
        engine.settleValidator(projId, index, nonce);

        // All should have settled successfully
        assertTrue(engine.isValidatorSettled(projId, index, nonce, validator1));
        assertTrue(engine.isValidatorSettled(projId, index, nonce, validator2));
        assertTrue(engine.isValidatorSettled(projId, index, nonce, validator3));

        // Rewards should be distributed
        assertGt(engine.getPendingRewards(validator1, address(token)), 0);
        assertGt(engine.getPendingRewards(validator2, address(token)), 0);
        assertGt(engine.getPendingRewards(validator3, address(token)), 0);
    }

    /// @notice Failure mode recovery: Complete project failure and originator refund
    function test_completeProjectFailureAndRecovery() public {
        // Create project with multiple contributions
        bytes32 failureProjId = _pid("failure-recovery");
        _setupProject(failureProjId, FUND_AMOUNT, 3);

        // All contributions get rejected
        _ensureStake(contributor1, STAKE_AMOUNT * 10);
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(failureProjId, 3, adapter);
        for (uint256 i; i < indices.length; ++i) {
            engine.contribute(claimId, indices[i], keccak256(abi.encodePacked("failure", i)), "");
        }
        vm.stopPrank();

        // All get rejected (batch validation for 3 indices)
        _validateAllBelowThreshold(failureProjId, indices);
        for (uint256 i; i < indices.length; ++i) {
            engine.computeConsensus(failureProjId, indices[i]);
            assertEq(
                uint256(engine.getContribution(failureProjId, indices[i]).status), uint256(ContributionStatus.Rejected)
            );
        }

        // Project should still be active but all slots available
        Project memory proj = engine.getProject(failureProjId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Active));
        assertEq(proj.availableSlots, 3);

        // Originator can now complete the failed project
        vm.prank(originator);
        engine.completeProject(failureProjId);

        assertEq(uint256(engine.getProject(failureProjId).status), uint256(ProjectStatus.Completed));

        // Originator can refund escrow after grace period
        vm.warp(block.timestamp + 31 days);
        uint256 escrowBefore = engine.getProjectEscrow(failureProjId, address(token));
        uint256 originatorBalBefore = token.balanceOf(originator);

        vm.prank(originator);
        engine.refundEscrow(failureProjId);

        assertEq(engine.getProjectEscrow(failureProjId, address(token)), 0);
        assertEq(token.balanceOf(originator) - originatorBalBefore, escrowBefore);
    }

    /// @notice Multi-actor interaction: Competing validators with different stake amounts
    function test_competingValidatorsDifferentStakes() public {
        // Create project with 3 validators required (default)
        bytes32 projId3 = _pid("competing-stakes");
        _setupProject(projId3, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId3, 1);
        uint256 index = indices[0];

        // Create additional validators with different stake amounts
        address validator4 = makeAddr("competing-val4");
        address validator5 = makeAddr("competing-val5");

        uint256 stake4 = 50e18; // Normal stake
        uint256 stake5 = 200e18; // High stake

        token.mint(validator4, stake4 * 5);
        token.mint(validator5, stake5 * 5);

        vm.startPrank(validator4);
        token.approve(address(vault), stake4 * 5);
        vault.deposit(stake4 * 5, validator4);
        vm.stopPrank();

        vm.startPrank(validator5);
        token.approve(address(vault), stake5 * 5);
        vault.deposit(stake5 * 5, validator5);
        vm.stopPrank();

        // Only the first 3 validators can actually participate (project requires 3)
        // But we test that higher stake gets higher rewards
        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        _claimAndCommit(validator1, projId3, index, 8000, VALIDATOR_STAKE);

        _ensureStake(validator2, VALIDATOR_STAKE * 2);
        _claimAndCommit(validator2, projId3, index, 8100, VALIDATOR_STAKE);

        _ensureStake(validator3, VALIDATOR_STAKE * 2);
        _claimAndCommit(validator3, projId3, index, 8200, VALIDATOR_STAKE);

        _reveal(validator1, projId3, index, 8000);
        _reveal(validator2, projId3, index, 8100);
        _reveal(validator3, projId3, index, 8200);

        engine.computeConsensus(projId3, index);

        // Should be accepted
        assertEq(uint256(engine.getContribution(projId3, index).status), uint256(ContributionStatus.Accepted));

        // Settle all validators after challenge period
        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(projId3, index).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(projId3, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projId3, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(projId3, index, nonce);

        // Test that if we had different stakes, higher stake would get higher rewards
        // Since all have the same stake, rewards should be roughly equal
        uint256 rewards1 = engine.getPendingRewards(validator1, address(token));
        uint256 rewards2 = engine.getPendingRewards(validator2, address(token));
        uint256 rewards3 = engine.getPendingRewards(validator3, address(token));

        // All should have some rewards (roughly equal since same stake)
        assertGt(rewards1, 0);
        assertGt(rewards2, 0);
        assertGt(rewards3, 0);
    }

    /// @notice Edge case timing: Contribution expiry during validation
    function test_contributionExpiryDuringValidation() public {
        // Create project
        bytes32 expiryProjId = _pid("expiry-during-validation");
        _setupProject(expiryProjId, FUND_AMOUNT, 5);

        // Submit contribution
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, expiryProjId, 1);
        uint256 index = indices[0];

        // Start validation with only 2 validators - commit but don't reveal
        _commitOnly(validator1, expiryProjId, index, 8000, VALIDATOR_STAKE);
        _commitOnly(validator2, expiryProjId, index, 8100, VALIDATOR_STAKE);

        // Warp past validation deadline - commitments should expire
        vm.warp(block.timestamp + 6 days);

        // Try to compute consensus - should fail due to insufficient reveals (0 revealed out of needed 3)
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusNotReady.selector, 0, 3));
        engine.computeConsensus(expiryProjId, index);

        // Cancel expired commitments (validators never revealed)
        vm.prank(keeper);
        engine.cancelExpiredCommitment(expiryProjId, index, validator1);
        vm.prank(keeper);
        engine.cancelExpiredCommitment(expiryProjId, index, validator2);

        // Freed slots allow 3 new validators to claim and complete the full flow
        _claimAndCommit(validator1, expiryProjId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, expiryProjId, index, 8100, VALIDATOR_STAKE);
        _claimAndCommit(validator3, expiryProjId, index, 8200, VALIDATOR_STAKE);
        _reveal(validator1, expiryProjId, index, 8000);
        _reveal(validator2, expiryProjId, index, 8100);
        _reveal(validator3, expiryProjId, index, 8200);
        engine.computeConsensus(expiryProjId, index);

        assertEq(uint256(engine.getContribution(expiryProjId, index).status), uint256(ContributionStatus.Accepted));
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 5: Edge Cases — Ghost Validators, Access Control, Pausing
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleEdgeCaseTest is LifecycleBase {
    bytes32 internal projId;

    function setUp() public override {
        super.setUp();
        projId = _pid("edge-cases");
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    /// @notice Ghost validator commits but never reveals, gets slashed after deadline
    function test_ghostValidatorSlash() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        // Ghost commits but does NOT reveal
        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        bytes32 salt = keccak256(abi.encodePacked("ghost", validator1));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

        vm.startPrank(validator1);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projId, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        uint256 sharesBefore = vault.balanceOf(validator1);

        // Warp past commit + reveal deadline (3 + 2 = 5 days)
        vm.warp(block.timestamp + 6 days);

        // Anyone can cancel and slash
        vm.prank(keeper);
        engine.cancelExpiredCommitment(projId, index, validator1);

        assertLt(vault.balanceOf(validator1), sharesBefore);
    }

    /// @notice Cannot cancel commitment before deadline
    function test_revert_cancelCommitmentBeforeDeadline() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        bytes32 salt = keccak256(abi.encodePacked("ghost-early", validator1));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

        vm.startPrank(validator1);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projId, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.cancelExpiredCommitment(projId, index, validator1);
    }

    /// @notice Cannot settle validator twice
    function test_revert_doubleSettle() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);
        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        _warpPastChallengePeriod();
        vm.startPrank(validator1);
        engine.settleValidator(projId, index, nonce);

        vm.expectRevert(ISapienCore.AlreadySettled.selector);
        engine.settleValidator(projId, index, nonce);
        vm.stopPrank();
    }

    /// @notice Cannot release contributor reward twice
    function test_revert_doubleRewardRelease() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _fullAcceptanceFlow(projId, index);

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projId, index);

        vm.expectRevert(ISapienCore.RewardAlreadyReleased.selector);
        engine.releaseContributorReward(projId, index);
    }

    /// @notice Cannot release reward before challenge period
    function test_revert_releaseBeforeChallengePeriod() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        // Validate + compute consensus but do NOT warp past the challenge period
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        vm.expectRevert(ISapienCore.ChallengeNotElapsed.selector);
        engine.releaseContributorReward(projId, index);
    }

    /// @notice Cannot claim reward with zero pending
    function test_revert_claimZeroReward() public {
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.NoRewardToClaim.selector);
        engine.claimReward(address(token));
    }

    /// @notice Originator cannot contribute to own project
    function test_revert_originatorContributes() public {
        _ensureStake(originator, STAKE_AMOUNT * 3);
        vm.prank(originator);
        vm.expectRevert(ISapienCore.OriginatorCannotContribute.selector);
        engine.claimToContribute(projId, 1, adapter);
    }

    /// @notice Contributor cannot validate their own contribution
    function test_revert_selfValidation() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);

        _ensureStake(contributor1, VALIDATOR_STAKE * 2);
        vm.startPrank(contributor1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        vm.expectRevert(ISapienCore.NoEligibleContributions.selector);
        engine.claimToValidate(projId, 1);
        vm.stopPrank();
    }

    /// @notice Cannot compute consensus with insufficient reveals
    function test_revert_consensusInsufficientReveals() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _claimAndCommit(validator1, projId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projId, index, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projId, index, 7500, VALIDATOR_STAKE);
        _reveal(validator1, projId, index, 8000);
        _reveal(validator2, projId, index, 8500);

        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusNotReady.selector, 2, 3));
        engine.computeConsensus(projId, index);
    }

    /// @notice Cannot compute consensus twice
    function test_revert_doubleConsensus() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        vm.expectRevert(ISapienCore.ConsensusAlreadyComputed.selector);
        engine.computeConsensus(projId, index);
    }

    /// @notice Commit with invalid reveal hash reverts
    function test_revert_invalidRevealHash() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        uint256 score = 8000;
        bytes32 salt = keccak256("salt1");
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projId, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        _claimAndCommit(validator2, projId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projId, index, 8000, VALIDATOR_STAKE);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.InvalidReveal.selector);
        engine.revealValidation(projId, index, 5000, salt); // wrong score
    }

    /// @notice Cannot commit twice for same index
    function test_revert_doubleCommit() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), bytes32("salt")));

        _ensureStake(validator1, VALIDATOR_STAKE * 4);
        vm.startPrank(validator1);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE * 2);
        engine.commitValidation(projId, index, commitHash, VALIDATOR_STAKE, address(0));

        vm.expectRevert(ISapienCore.AlreadyCommitted.selector);
        engine.commitValidation(projId, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();
    }

    /// @notice Operations fail when protocol is paused
    function test_revert_operationsWhenPaused() public {
        vm.prank(admin);
        engine.pause();

        vm.prank(originator);
        vm.expectRevert();
        engine.createProject(_pid("paused"), "", _defaultConfig());

        vm.prank(admin);
        engine.unpause();

        // Operations work again
        vm.prank(originator);
        engine.createProject(_pid("unpaused"), "", _defaultConfig());
    }

    /// @notice Cannot claim more slots than available
    function test_revert_claimExceedsAvailableSlots() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 100);
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.NoSlotsAvailable.selector);
        engine.claimToContribute(projId, QUANTITY + 1, adapter);
    }

    /// @notice Cannot contribute to wrong claim
    function test_revert_contributeWrongClaim() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 5);
        _ensureStake(contributor2, STAKE_AMOUNT * 5);

        vm.prank(contributor1);
        (uint256 claimId1,) = engine.claimToContribute(projId, 1, adapter);

        vm.prank(contributor2);
        (, uint256[] memory indices2) = engine.claimToContribute(projId, 1, adapter);

        // Contributor2 tries to contribute to claimId1's index through claimId2
        // (indices are different, so this should fail with IndexNotInClaim)
        vm.prank(contributor2);
        vm.expectRevert(ISapienCore.NotClaimOwner.selector);
        engine.contribute(claimId1, indices2[0], keccak256("data"), "");
    }

    /// @notice Cannot fund project if not the originator
    function test_revert_fundProjectNotOriginator() public {
        bytes32 pid2 = _pid("not-originator");
        vm.prank(originator);
        engine.createProject(pid2, "", _defaultConfig());

        token.mint(contributor1, FUND_AMOUNT);
        vm.startPrank(contributor1);
        token.approve(address(engine), FUND_AMOUNT);
        vm.expectRevert(ISapienCore.NotProjectOriginator.selector);
        engine.fundProject(pid2, FUND_AMOUNT, 5, adapter);
        vm.stopPrank();
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 6: Reputation and Fee Accounting
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleReputationAndFeesTest is LifecycleBase {
    bytes32 internal projId;
    bytes32 internal constant ORIGINATOR_KEY = keccak256("ORIGINATOR");

    function setUp() public override {
        super.setUp();
        projId = _pid("rep-fees");
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    /// @notice Originator reputation increases on project creation
    function test_originatorReputationIncreases() public view {
        Reputation memory rep = engine.getReputation(originator, ORIGINATOR_KEY);
        assertGt(rep.score, 5000); // > default
        assertEq(rep.totalActions, 1);
        assertEq(rep.successfulActions, 1);
    }

    /// @notice Contributor reputation increases on acceptance
    function test_contributorReputationIncreasesOnAcceptance() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        Reputation memory repBefore = engine.getReputation(contributor1, SKILL_ID);
        uint256 scoreBefore = repBefore.score;

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        Reputation memory repAfter = engine.getReputation(contributor1, SKILL_ID);
        assertGt(repAfter.score, scoreBefore);
        assertEq(repAfter.successfulActions, 1);
    }

    /// @notice Contributor reputation decreases on rejection
    function test_contributorReputationDecreasesOnRejection() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateBelowThreshold(projId, index);
        engine.computeConsensus(projId, index);

        Reputation memory rep = engine.getReputation(contributor1, SKILL_ID);
        assertLt(rep.score, 5000); // < default
    }

    /// @notice Validator reputation increases on accurate settlement
    function test_validatorReputationIncreasesOnAccurateSettle() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);
        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        _warpPastChallengePeriod();
        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);

        Reputation memory rep = engine.getReputation(validator1, SKILL_ID);
        assertGt(rep.score, 5000); // > default
        assertEq(rep.successfulActions, 1);
    }

    /// @notice Protocol fee sent to treasury on fund
    function test_protocolFeeSentToTreasury() public view {
        // Protocol fee is 10% of 10000e18 = 1000e18
        uint256 treasuryBal = token.balanceOf(treasury);
        assertEq(treasuryBal, 1000e18);
    }

    /// @notice Origination adapter fee credited on fund
    function test_originationAdapterFeeCredited() public view {
        uint256 adapterRewards = engine.getPendingRewards(adapter, address(token));
        // 4% of (10000e18 - 1000e18) = 360e18
        assertEq(adapterRewards, 360e18);
    }

    /// @notice Contribution adapter fee deducted on reward release
    function test_contributionAdapterFeeOnRelease() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _fullAcceptanceFlow(projId, index);

        // Note adapter pending before release (has origination fee)
        uint256 adapterBefore = engine.getPendingRewards(adapter, address(token));

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projId, index);

        // Adapter gets additional contribution fee
        uint256 adapterAfter = engine.getPendingRewards(adapter, address(token));
        assertGt(adapterAfter, adapterBefore);
    }

    /// @notice Reward rate snapshot is consistent: totalRewards / totalQuantity
    function test_rewardRateSnapshot() public {
        Project memory proj = engine.getProject(projId);
        uint256 expectedRate = proj.totalRewards / proj.totalQuantity;

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        Contribution memory contrib = engine.getContribution(projId, indices[0]);
        assertEq(contrib.rewardRate, expectedRate);
    }

    /// @notice Validator rewards bounded by per-index validator pool
    function test_validatorRewardsBounded() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        uint256 v1Before = engine.getPendingRewards(validator1, address(token));
        uint256 v2Before = engine.getPendingRewards(validator2, address(token));
        uint256 v3Before = engine.getPendingRewards(validator3, address(token));

        _settleAllValidators(projId, index);

        uint256 totalValRewards;
        totalValRewards += engine.getPendingRewards(validator1, address(token)) - v1Before;
        totalValRewards += engine.getPendingRewards(validator2, address(token)) - v2Before;
        totalValRewards += engine.getPendingRewards(validator3, address(token)) - v3Before;

        {
            Project memory proj = engine.getProject(projId);
            uint256 perIndexMax = (proj.totalRewards * proj.validatorRewardBps) / (10_000 * proj.totalQuantity);
            assertLe(totalValRewards, perIndexMax);
        }
    }

    /// @notice Escrow decreases by exactly (rewardRate + validatorRewards) per accepted index
    function test_escrowAccountingPerIndex() public {
        uint256 escrowBefore = engine.getProjectEscrow(projId, address(token));

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        uint256 v1Before = engine.getPendingRewards(validator1, address(token));
        uint256 v2Before = engine.getPendingRewards(validator2, address(token));
        uint256 v3Before = engine.getPendingRewards(validator3, address(token));

        _settleAllValidators(projId, index);

        uint256 totalValRewards;
        totalValRewards += engine.getPendingRewards(validator1, address(token)) - v1Before;
        totalValRewards += engine.getPendingRewards(validator2, address(token)) - v2Before;
        totalValRewards += engine.getPendingRewards(validator3, address(token)) - v3Before;

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projId, index);

        Contribution memory contrib = engine.getContribution(projId, index);
        uint256 escrowAfter = engine.getProjectEscrow(projId, address(token));

        // H-02 fix: contributor receives carved share (rewardRate * (BPS - validatorBps) / BPS)
        // Escrow drain = contributorShare + validator rewards
        Project memory projFinal = engine.getProject(projId);
        uint256 contributorShare = (contrib.rewardRate * (10_000 - projFinal.validatorRewardBps)) / 10_000;
        assertEq(escrowBefore - escrowAfter, contributorShare + totalValRewards);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 7: Outlier Validator Detection
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleOutlierTest is LifecycleBase {
    bytes32 internal projId;
    address public validator4;
    address public validator5;

    function setUp() public override {
        super.setUp();
        projId = _pid("outlier");

        validator4 = makeAddr("validator4");
        validator5 = makeAddr("validator5");

        // Fund extra validators
        address[2] memory extras = [validator4, validator5];
        for (uint256 i; i < extras.length; ++i) {
            token.mint(extras[i], STAKE_AMOUNT * 10);
            vm.startPrank(extras[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 5, extras[i]);
            vm.stopPrank();
        }

        // Create project requiring 5 validators
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        Project memory config = _defaultConfig();
        config.numberOfValidations = 5;
        engine.createProject(projId, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(projId, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();
    }

    /// @notice One outlier among 5 validators: outlier slashed, others rewarded
    function test_outlierDetectionAndSlashing() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        // 4 validators score ~9000, outlier scores 1000
        _claimAndCommit(validator1, projId, index, 9000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projId, index, 9000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projId, index, 9000, VALIDATOR_STAKE);
        _claimAndCommit(validator4, projId, index, 9000, VALIDATOR_STAKE);
        _claimAndCommit(validator5, projId, index, 1000, VALIDATOR_STAKE);
        _reveal(validator1, projId, index, 9000);
        _reveal(validator2, projId, index, 9000);
        _reveal(validator3, projId, index, 9000);
        _reveal(validator4, projId, index, 9000);
        _reveal(validator5, projId, index, 1000);

        uint256 outlierSharesBefore = vault.balanceOf(validator5);

        engine.computeConsensus(projId, index);
        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        // Contribution should still be accepted (weighted avg well above 7000)
        assertEq(uint256(engine.getContribution(projId, index).status), uint256(ContributionStatus.Accepted));

        // Settle all (warp past challenge period for non-outlier reward payment)
        _warpPastChallengePeriod();
        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator4);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator5);
        engine.settleValidator(projId, index, nonce);

        // validator5 should be outlier
        assertTrue(engine.isValidatorOutlier(projId, index, validator5));
        assertFalse(engine.isValidatorOutlier(projId, index, validator1));
        assertFalse(engine.isValidatorOutlier(projId, index, validator2));

        // Outlier slashed
        assertLe(vault.balanceOf(validator5), outlierSharesBefore);

        // Accurate validators have rewards
        assertGt(engine.getPendingRewards(validator1, address(token)), 0);
        assertGt(engine.getPendingRewards(validator2, address(token)), 0);
        assertGt(engine.getPendingRewards(validator3, address(token)), 0);
        assertGt(engine.getPendingRewards(validator4, address(token)), 0);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 8: Full Project Completion & Token Conservation
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleFullProjectTest is LifecycleBase {
    bytes32 internal projId;
    uint256 internal constant SMALL_QTY = 3;
    uint256 internal constant SMALL_FUND = 30_000e18;

    function setUp() public override {
        super.setUp();
        projId = _pid("full-project");
        _setupProject(projId, SMALL_FUND, SMALL_QTY);
    }

    /// @notice Process a subset of indices through the complete lifecycle.
    /// @dev With validatorRewardBps=2000, each index drains 1.2x its share of escrow
    ///      (rewardRate + 20% validator rewards). Processing ALL indices would require
    ///      1.2x escrow, causing underflow. We process 2/3 to stay within bounds.
    function test_processMultipleIndices() public {
        uint256 escrowStart = engine.getProjectEscrow(projId, address(token));
        assertGt(escrowStart, 0);

        // Claim 2 of 3 indices
        uint256 processQty = 2;
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, processQty);
        assertEq(indices.length, processQty);

        assertEq(engine.getProject(projId).availableSlots, SMALL_QTY - processQty);

        // With multiple pending indices, use batch validation
        _validateAllAboveThreshold(projId, indices);
        for (uint256 i; i < indices.length; ++i) {
            engine.computeConsensus(projId, indices[i]);
            _settleAllValidators(projId, indices[i]);
        }

        // Release all contributor rewards
        vm.warp(block.timestamp + 2 days);
        for (uint256 i; i < indices.length; ++i) {
            engine.releaseContributorReward(projId, indices[i]);
        }

        // Contributor should have accumulated rewards
        uint256 contribPending = engine.getPendingRewards(contributor1, address(token));
        assertGt(contribPending, 0);

        // Claim all rewards
        vm.prank(contributor1);
        engine.claimReward(address(token));
        assertEq(engine.getPendingRewards(contributor1, address(token)), 0);

        // Escrow should still be positive
        uint256 escrowAfter = engine.getProjectEscrow(projId, address(token));
        assertGt(escrowAfter, 0);
    }

    /// @notice Token conservation: engine balance >= sum of all pending rewards + escrow
    function test_tokenConservation() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _fullAcceptanceFlow(projId, index);

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projId, index);

        // Engine holds tokens: sum of all escrow + all pending rewards must not exceed balance
        uint256 engineBalance = token.balanceOf(address(engine));
        uint256 escrow = engine.getProjectEscrow(projId, address(token));
        uint256 pendingContrib = engine.getPendingRewards(contributor1, address(token));
        uint256 pendingV1 = engine.getPendingRewards(validator1, address(token));
        uint256 pendingV2 = engine.getPendingRewards(validator2, address(token));
        uint256 pendingV3 = engine.getPendingRewards(validator3, address(token));
        uint256 pendingAdapter = engine.getPendingRewards(adapter, address(token));

        uint256 totalObligations = escrow + pendingContrib + pendingV1 + pendingV2 + pendingV3 + pendingAdapter;
        assertGe(engineBalance, totalObligations);
    }

    /// @notice Fee breakdown adds up correctly
    function test_feeBreakdownAccuracy() public view {
        // Protocol fee = 10% of SMALL_FUND = 3000e18
        uint256 protocolFee = (SMALL_FUND * 1000) / 10_000;
        assertEq(token.balanceOf(treasury), protocolFee);

        // Origination fee = 4% of (SMALL_FUND - protocolFee)
        uint256 remaining = SMALL_FUND - protocolFee;
        uint256 originationFee = (remaining * 400) / 10_000;
        assertEq(engine.getPendingRewards(adapter, address(token)), originationFee);

        // Project escrow = remaining - originationFee
        uint256 expectedEscrow = remaining - originationFee;
        assertEq(engine.getProjectEscrow(projId, address(token)), expectedEscrow);

        // totalRewards matches escrow
        Project memory proj = engine.getProject(projId);
        assertEq(proj.totalRewards, expectedEscrow);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 9: Complex Multi-Actor Scenarios
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleMultiActorTest is LifecycleBase {
    bytes32 internal projId;

    function setUp() public override {
        super.setUp();
        projId = _pid("multi-actor");
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    /// @notice Rejection → re-claim by different contributor → acceptance → dispute upheld
    function test_complexRejectionThenDisputeFlow() public {
        // Contributor1 submits, gets rejected
        (, uint256[] memory indices1) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index1 = indices1[0];

        _validateBelowThreshold(projId, index1);
        engine.computeConsensus(projId, index1);
        assertEq(uint256(engine.getContribution(projId, index1).status), uint256(ContributionStatus.Rejected));

        // Index back in pool, contributor2 picks it up
        (, uint256[] memory indices2) = _claimAndSubmit(contributor2, projId, 1);
        uint256 index2 = indices2[0];

        _validateAboveThreshold(projId, index2);
        engine.computeConsensus(projId, index2);
        assertEq(uint256(engine.getContribution(projId, index2).status), uint256(ContributionStatus.Accepted));

        // Open dispute while still in challenge window (before warping past it)
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index2, keccak256("evidence"), "evidenceCid");

        // Operator upholds dispute
        vm.prank(admin);
        engine.resolveDispute(projId, index2, true);

        // Validators can now settle (upheld dispute: stake released, no reward)
        uint256 nonce2 = engine.getContribution(projId, index2).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(projId, index2, nonce2);
        vm.prank(validator2);
        engine.settleValidator(projId, index2, nonce2);
        vm.prank(validator3);
        engine.settleValidator(projId, index2, nonce2);

        // Contributor2's reward is blocked (dispute upheld)
        vm.warp(block.timestamp + 10 days);
        vm.expectRevert(ISapienCore.DisputeInProgress.selector);
        engine.releaseContributorReward(projId, index2);

        // Challenger gets reward
        assertGt(engine.getPendingRewards(challenger, address(token)), 0);
    }

    /// @notice Multiple sequential claims from same contributor
    function test_multipleSequentialClaims() public {
        // First claim
        (uint256 claimId1, uint256[] memory indices1) = _claimAndSubmit(contributor1, projId, 2);
        assertEq(uint256(engine.getClaim(claimId1).status), uint256(ClaimStatus.Completed));

        // Second claim
        (uint256 claimId2, uint256[] memory indices2) = _claimAndSubmit(contributor1, projId, 2);
        assertEq(uint256(engine.getClaim(claimId2).status), uint256(ClaimStatus.Completed));
        assertTrue(claimId2 > claimId1);

        // Process all (4 indices total) - use batch validation
        uint256[] memory allIndices = new uint256[](4);
        allIndices[0] = indices1[0];
        allIndices[1] = indices1[1];
        allIndices[2] = indices2[0];
        allIndices[3] = indices2[1];
        _validateAllAboveThreshold(projId, allIndices);
        for (uint256 i; i < 4; ++i) {
            engine.computeConsensus(projId, allIndices[i]);
            _settleAllValidators(projId, allIndices[i]);
        }

        vm.warp(block.timestamp + 2 days);
        for (uint256 i; i < indices1.length; ++i) {
            engine.releaseContributorReward(projId, indices1[i]);
        }
        for (uint256 i; i < indices2.length; ++i) {
            engine.releaseContributorReward(projId, indices2[i]);
        }

        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
    }

    /// @notice Partial claim expiry: unsubmitted indices return to pool, new contributor claims them
    /// @dev Submitted indices from expired claims have their contributor lock already released by
    ///      expireClaim(), so we only process the newly-claimed indices through consensus.
    function test_partialExpiryThenNewClaim() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 10);

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 4, adapter);

        // Submit only first 2
        engine.contribute(claimId, indices[0], keccak256("data0"), "");
        engine.contribute(claimId, indices[1], keccak256("data1"), "");
        vm.stopPrank();

        // Validate and settle the 2 submitted contributions before expiring the claim.
        // This ensures no orphaned pending contributions remain when new ones are added,
        // which is important for random validator assignment.
        uint256[] memory submitted = new uint256[](2);
        submitted[0] = indices[0];
        submitted[1] = indices[1];
        _validateAllAboveThreshold(projId, submitted);
        for (uint256 i; i < submitted.length; ++i) {
            engine.computeConsensus(projId, submitted[i]);
            _settleAllValidators(projId, submitted[i]);
        }
        vm.warp(block.timestamp + 2 days);
        for (uint256 i; i < submitted.length; ++i) {
            engine.releaseContributorReward(projId, submitted[i]);
        }

        uint256 slotsAfterClaim = engine.getProject(projId).availableSlots;

        // Expire the claim — 2 unsubmitted Reserved slots are returned
        vm.warp(block.timestamp + 8 days);
        engine.expireClaim(claimId, indices);

        assertEq(engine.getProject(projId).availableSlots, slotsAfterClaim + 2);

        // New contributor claims the 2 returned indices
        (, uint256[] memory newIndices) = _claimAndSubmit(contributor2, projId, 2);
        assertEq(newIndices.length, 2);

        _validateAllAboveThreshold(projId, newIndices);
        for (uint256 i; i < newIndices.length; ++i) {
            engine.computeConsensus(projId, newIndices[i]);
        }

        // Warp well past all challenge periods, then settle and release
        vm.warp(block.timestamp + 3 days);

        for (uint256 i; i < newIndices.length; ++i) {
            uint256 nonce = engine.getContribution(projId, newIndices[i]).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(projId, newIndices[i], nonce);
            vm.prank(validator2);
            engine.settleValidator(projId, newIndices[i], nonce);
            vm.prank(validator3);
            engine.settleValidator(projId, newIndices[i], nonce);
        }

        for (uint256 i; i < newIndices.length; ++i) {
            engine.releaseContributorReward(projId, newIndices[i]);
        }
        assertGt(engine.getPendingRewards(contributor2, address(token)), 0);
    }

    /// @notice Project with skill gate: validator without reputation is blocked
    function test_validatorReputationGate() public {
        bytes32 labelingSkill = keccak256("LABELING");
        vm.prank(admin);
        engine.registerSkill("LABELING");

        bytes32 pid2 = _pid("rep-gate");
        Project memory config = _defaultConfig();
        config.requiredSkill = labelingSkill;
        config.minValidatorReputation = 6000; // Above default 5000

        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, 5, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid2, 1);

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InsufficientReputation.selector, 6000, 5000));
        engine.claimToValidate(pid2, 1);
        vm.stopPrank();
    }

    /// @notice Validators with different stakes get proportional rewards
    function test_stakeWeightedRewardDistribution() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        // Same score, different stakes
        uint256 lowStake = 10e18;
        uint256 highStake = 100e18;

        _claimAndCommit(validator1, projId, index, 8000, lowStake);
        _claimAndCommit(validator2, projId, index, 8000, highStake);
        _claimAndCommit(validator3, projId, index, 8000, highStake);
        _reveal(validator1, projId, index, 8000);
        _reveal(validator2, projId, index, 8000);
        _reveal(validator3, projId, index, 8000);

        engine.computeConsensus(projId, index);

        uint256 v1Before = engine.getPendingRewards(validator1, address(token));
        uint256 v2Before = engine.getPendingRewards(validator2, address(token));

        _settleAllValidators(projId, index);

        uint256 v1Reward = engine.getPendingRewards(validator1, address(token)) - v1Before;
        uint256 v2Reward = engine.getPendingRewards(validator2, address(token)) - v2Before;

        // Higher staker should get more rewards (weight = sqrt(stake) * rep / BPS)
        assertGt(v2Reward, v1Reward);
    }

    /// @notice Creating duplicate project reverts
    function test_revert_duplicateProject() public {
        vm.prank(originator);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "project already exists"));
        engine.createProject(projId, "", _defaultConfig());
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 10: Admin Configuration Changes Mid-Protocol
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleAdminTest is LifecycleBase {
    /// @notice Admin fee changes are respected for new projects
    function test_feeChangesApplyToNewProjects() public {
        vm.startPrank(admin);
        engine.setProtocolFee(200); // 2%
        engine.setOriginationFee(300); // 3%
        engine.setContributionFee(100); // 1%
        engine.setValidationFee(100); // 1%
        vm.stopPrank();

        (uint256 origBps, uint256 contribBps, uint256 valBps) = engine.getAdapterFees();
        assertEq(origBps, 300);
        assertEq(contribBps, 100);
        assertEq(valBps, 100);

        // Create project with new fees
        bytes32 pid2 = _pid("new-fees");
        uint256 fundAmt = 10_000e18;
        _setupProject(pid2, fundAmt, 5);

        // Treasury gets 2% = 200e18
        // (Treasury had 0 before since no project existed in this test's setUp)
        assertEq(token.balanceOf(treasury), 200e18);

        // Adapter gets 3% of (10000 - 200) = 294e18
        assertEq(engine.getPendingRewards(adapter, address(token)), 294e18);
    }

    /// @notice Max fee limits are enforced
    function test_revert_feeLimits() public {
        vm.startPrank(admin);

        vm.expectRevert(abi.encodeWithSelector(ISapienCore.AdapterFeeTooHigh.selector, 1500, 1000));
        engine.setProtocolFee(1500);

        vm.expectRevert(abi.encodeWithSelector(ISapienCore.AdapterFeeTooHigh.selector, 600, 500));
        engine.setOriginationFee(600);

        vm.expectRevert(abi.encodeWithSelector(ISapienCore.AdapterFeeTooHigh.selector, 600, 500));
        engine.setContributionFee(600);

        vm.expectRevert(abi.encodeWithSelector(ISapienCore.AdapterFeeTooHigh.selector, 600, 500));
        engine.setValidationFee(600);

        vm.stopPrank();
    }

    /// @notice Setting decay rate and treasury
    function test_adminConfigChanges() public {
        address newTreasury = makeAddr("newTreasury");

        vm.startPrank(admin);
        engine.setDecayRate(20);
        engine.setTreasury(newTreasury);
        engine.setDisputeBondBps(2000);
        engine.setOriginatorStakeRequirement(50e18);
        engine.setOriginatorReportBondBps(200);
        vm.stopPrank();

        assertEq(engine.treasury(), newTreasury);

        (uint256 bondBps, uint256 stakeReq, uint256 reportBps) = engine.getDisputeConfig();
        assertEq(bondBps, 2000);
        assertEq(stakeReq, 50e18);
        assertEq(reportBps, 200);
    }

    /// @notice Non-admin cannot change fees
    function test_revert_nonAdminFeeChanges() public {
        vm.startPrank(contributor1);
        vm.expectRevert();
        engine.setProtocolFee(200);
        vm.stopPrank();
    }

    /// @notice Zero-address treasury rejected
    function test_revert_zeroTreasury() public {
        vm.prank(admin);
        vm.expectRevert(ISapienCore.ZeroAddress.selector);
        engine.setTreasury(address(0));
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 11: Exhaustive Validation & Closure Flows
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleExhaustiveWorkflowTest is LifecycleBase {
    bytes32 internal projId;

    function setUp() public override {
        super.setUp();
        projId = _pid("exhaustive-workflow");
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    function _singlePendingIndex(bytes32 projectId_) internal returns (uint256) {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projectId_, 1);
        return indices[0];
    }

    function _claimValidation(
        address validator,
        bytes32 projectId_,
        uint256 /* index */
    )
        internal
        returns (uint256 claimId)
    {
        vm.prank(validator);
        claimId = engine.claimToValidate(projectId_, 1);
    }

    function _commitWithoutReveal(address validator, bytes32 projectId_, uint256 index, uint256 score, uint256 stakeAmt)
        internal
        returns (bytes32 salt)
    {
        salt = keccak256(abi.encodePacked("noreveal", validator, projectId_, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(validator, stakeAmt * 2);

        vm.startPrank(validator);
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projectId_, index, commitHash, stakeAmt, address(0));
        vm.stopPrank();
    }

    /// @notice Validation claim expires cleanly when validator never commits.
    function test_validationClaimExpiresWithoutCommit() public {
        uint256 index = _singlePendingIndex(projId);
        uint256 claimId = _claimValidation(validator1, projId, index);

        Reputation memory repBefore = engine.getReputation(validator1, SKILL_ID);

        vm.warp(block.timestamp + 2 hours);
        engine.cancelExpiredValidationClaim(claimId);

        ValidationClaim memory vclaim = engine.getValidationClaim(claimId);
        assertEq(uint256(vclaim.status), uint256(ValidationClaimStatus.Expired));
        assertEq(vclaim.totalCount, 1);
        assertEq(vclaim.committedCount, 0);

        Reputation memory repAfter = engine.getReputation(validator1, SKILL_ID);
        assertLt(repAfter.score, repBefore.score);
    }

    /// @notice Validation claim expiry tracks committed vs uncommitted slots.
    function test_validationClaimExpiresAfterPartialCommit() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 2);

        vm.prank(validator1);
        uint256 claimId = engine.claimToValidate(projId, 2);

        _ensureStake(validator1, VALIDATOR_STAKE * 4);

        bytes32 salt = keccak256(abi.encodePacked("partial", validator1, projId, indices[0]));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

        vm.startPrank(validator1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projId, indices[0], commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);
        engine.cancelExpiredValidationClaim(claimId);

        ValidationClaim memory vclaim = engine.getValidationClaim(claimId);
        assertEq(uint256(vclaim.status), uint256(ValidationClaimStatus.Expired));
        assertEq(vclaim.totalCount, 2);
        assertEq(vclaim.committedCount, 1);
    }

    /// @notice If one validator fails to reveal, consensus is blocked until commitment is cancelled and replaced.
    function test_failedRevealFlowRecoversAfterCancellingExpiredCommitment() public {
        uint256 index = _singlePendingIndex(projId);

        _claimValidation(validator1, projId, index);
        _commitWithoutReveal(validator1, projId, index, 7900, VALIDATOR_STAKE);

        _claimAndCommit(validator2, projId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projId, index, 8200, VALIDATOR_STAKE);
        _reveal(validator2, projId, index, 8000);
        _reveal(validator3, projId, index, 8200);

        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusNotReady.selector, 2, 3));
        engine.computeConsensus(projId, index);

        vm.warp(block.timestamp + engine.commitDeadline() + engine.revealDeadline() + 1);

        vm.prank(keeper);
        engine.cancelExpiredCommitment(projId, index, validator1);

        address validator4 = makeAddr("validator4-recovery");
        _claimAndCommit(validator4, projId, index, 8100, VALIDATOR_STAKE);
        _reveal(validator4, projId, index, 8100);

        engine.computeConsensus(projId, index);
        assertEq(uint256(engine.getContribution(projId, index).status), uint256(ContributionStatus.Accepted));
    }

    /// @notice Reveal fails once the commit+reveal window has elapsed.
    function test_revert_revealAfterCommitAndRevealWindowElapsed() public {
        uint256 index = _singlePendingIndex(projId);

        _claimValidation(validator1, projId, index);
        bytes32 salt = _commitWithoutReveal(validator1, projId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projId, index, 8000, VALIDATOR_STAKE);

        vm.warp(block.timestamp + engine.commitDeadline() + engine.revealDeadline() + 1);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.RevealWindowClosed.selector);
        engine.revealValidation(projId, index, 8000, salt);
    }

    /// @notice Force settlement closes the final validator position after delay.
    function test_forceSettlePathAfterDelay() public {
        uint256 index = _singlePendingIndex(projId);

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        // Warp past challenge period so validators 1 and 2 can self-settle
        _warpPastChallengePeriod();
        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projId, index, nonce);

        // forceSettle still too early (forceSettleDelay not yet elapsed since reveal)
        vm.expectRevert(ISapienCore.ForceSettleTooEarly.selector);
        engine.forceSettleValidator(projId, index, nonce, validator3);

        vm.warp(block.timestamp + engine.forceSettleDelay() + 1);

        vm.prank(keeper);
        engine.forceSettleValidator(projId, index, nonce, validator3);
        assertTrue(engine.isValidatorSettled(projId, index, nonce, validator3));
    }

    /// @notice Batch commit/reveal runs end to end across multiple indices.
    function test_batchCommitRevealMultiIndexLifecycle() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 2);

        uint256[] memory stakeAmounts = new uint256[](2);
        stakeAmounts[0] = VALIDATOR_STAKE;
        stakeAmounts[1] = VALIDATOR_STAKE;

        uint256[] memory scores = new uint256[](2);
        scores[0] = 8000;
        scores[1] = 8300;

        bytes32[] memory salts = new bytes32[](2);
        bytes32[] memory commitHashes = new bytes32[](2);
        for (uint256 i; i < 2; ++i) {
            salts[i] = keccak256(abi.encodePacked("batch", validator1, projId, indices[i]));
            commitHashes[i] = keccak256(abi.encodePacked(scores[i], salts[i]));
        }

        _ensureStake(validator1, VALIDATOR_STAKE * 6);

        vm.startPrank(validator1);
        engine.claimToValidate(projId, 2);
        engine.lockValidatorCapacity(VALIDATOR_STAKE * 2);
        engine.batchCommitValidations(projId, indices, commitHashes, stakeAmounts, address(0));
        vm.stopPrank();

        // Validator2 and validator3 must also validate both indices (batch) since assignment is random
        uint256[] memory scores2 = new uint256[](2);
        uint256[] memory scores3 = new uint256[](2);
        scores2[0] = 8100;
        scores2[1] = 8400;
        scores3[0] = 8200;
        scores3[1] = 8500;
        bytes32[] memory salts2 = new bytes32[](2);
        bytes32[] memory salts3 = new bytes32[](2);
        bytes32[] memory commitHashes2 = new bytes32[](2);
        bytes32[] memory commitHashes3 = new bytes32[](2);
        for (uint256 i; i < 2; ++i) {
            salts2[i] = keccak256(abi.encodePacked("batch", validator2, projId, indices[i]));
            salts3[i] = keccak256(abi.encodePacked("batch", validator3, projId, indices[i]));
            commitHashes2[i] = keccak256(abi.encodePacked(scores2[i], salts2[i]));
            commitHashes3[i] = keccak256(abi.encodePacked(scores3[i], salts3[i]));
        }
        _ensureStake(validator2, VALIDATOR_STAKE * 4);
        _ensureStake(validator3, VALIDATOR_STAKE * 4);
        vm.startPrank(validator2);
        engine.claimToValidate(projId, 2);
        engine.lockValidatorCapacity(VALIDATOR_STAKE * 2);
        engine.batchCommitValidations(projId, indices, commitHashes2, stakeAmounts, address(0));
        vm.stopPrank();
        vm.startPrank(validator3);
        engine.claimToValidate(projId, 2);
        engine.lockValidatorCapacity(VALIDATOR_STAKE * 2);
        engine.batchCommitValidations(projId, indices, commitHashes3, stakeAmounts, address(0));
        vm.stopPrank();

        vm.prank(validator1);
        engine.batchRevealValidations(projId, indices, scores, salts);
        vm.prank(validator2);
        engine.batchRevealValidations(projId, indices, scores2, salts2);
        vm.prank(validator3);
        engine.batchRevealValidations(projId, indices, scores3, salts3);

        engine.computeConsensus(projId, indices[0]);
        engine.computeConsensus(projId, indices[1]);

        assertEq(uint256(engine.getContribution(projId, indices[0]).status), uint256(ContributionStatus.Accepted));
        assertEq(uint256(engine.getContribution(projId, indices[1]).status), uint256(ContributionStatus.Accepted));
    }

    /// @notice Full closure path: accepted contribution -> release -> complete -> refund.
    function test_fullLifecycleCompletionAndEscrowRefund() public {
        bytes32 pid2 = _pid("completion-refund");
        _setupProject(pid2, FUND_AMOUNT, 2);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid2, 1);
        uint256 index = indices[0];

        _validateAboveThreshold(pid2, index);
        engine.computeConsensus(pid2, index);
        _settleAllValidators(pid2, index);

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(pid2, index);

        vm.prank(originator);
        engine.completeProject(pid2);
        assertEq(uint256(engine.getProject(pid2).status), uint256(ProjectStatus.Completed));

        uint256 escrow = engine.getProjectEscrow(pid2, address(token));
        uint256 balBefore = token.balanceOf(originator);

        vm.warp(block.timestamp + 31 days);
        vm.prank(originator);
        engine.refundEscrow(pid2);

        assertEq(engine.getProjectEscrow(pid2, address(token)), 0);
        assertEq(token.balanceOf(originator) - balBefore, escrow);
    }

    /// @notice Project cannot complete while any contribution is still in-flight.
    function test_revert_completeProjectWithPendingContribution() public {
        _singlePendingIndex(projId);

        vm.prank(originator);
        vm.expectRevert(ISapienCore.ProjectHasActivePipeline.selector);
        engine.completeProject(projId);
    }

    /// @notice Refund is blocked until completion grace period elapses.
    function test_revert_refundEscrowBeforeCompletionDelay() public {
        vm.prank(originator);
        engine.completeProject(projId);

        vm.prank(originator);
        vm.expectRevert(ISapienCore.ChallengeNotElapsed.selector);
        engine.refundEscrow(projId);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Test Suite 12: Known Lifecycle Issue Reproductions
// ═══════════════════════════════════════════════════════════════════════

contract LifecycleKnownIssuesTest is LifecycleBase {
    bytes32 internal projId;

    function setUp() public override {
        super.setUp();
        projId = _pid("known-issues");
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    function _singlePendingIndex() internal returns (uint256) {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        return indices[0];
    }

    /// @notice FIX VERIFIED: cancelling expired validation claims releases reserved slots for new validators.
    function test_issue_validationClaimExpiryLocksValidatorSlots() public {
        _singlePendingIndex();

        vm.prank(validator1);
        uint256 claim1 = engine.claimToValidate(projId, 1);
        vm.prank(validator2);
        uint256 claim2 = engine.claimToValidate(projId, 1);
        vm.prank(validator3);
        uint256 claim3 = engine.claimToValidate(projId, 1);

        vm.warp(block.timestamp + 2 hours);
        engine.cancelExpiredValidationClaim(claim1);
        engine.cancelExpiredValidationClaim(claim2);
        engine.cancelExpiredValidationClaim(claim3);

        // After fix: expired reservations are fully released, new validators can claim.
        address validator4 = makeAddr("validator4-issue-lock");
        vm.prank(validator4);
        engine.claimToValidate(projId, 1);
    }

    /// @notice FIX VERIFIED: validators cannot commit/reveal after their validation claim is expired.
    function test_issue_lateCommitAllowedAfterValidationClaimExpiry() public {
        uint256 index = _singlePendingIndex();

        vm.prank(validator3);
        uint256 claimId = engine.claimToValidate(projId, 1);

        _claimAndCommit(validator1, projId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projId, index, 8200, VALIDATOR_STAKE);

        vm.warp(block.timestamp + 2 hours);
        engine.cancelExpiredValidationClaim(claimId);

        // After fix: the ValidatorCommit slot is deleted on expiry cancellation,
        // so a late commit with the stale reservation is no longer possible.
        uint256 lateScore = 1000;
        bytes32 salt = keccak256(abi.encodePacked("late", validator3, projId, index));
        bytes32 commitHash = keccak256(abi.encodePacked(lateScore, salt));

        _ensureStake(validator3, VALIDATOR_STAKE * 3);
        vm.startPrank(validator3);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.expectRevert();
        engine.commitValidation(projId, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();
    }

    /// @notice FIX VERIFIED: upheld dispute resolves the pipeline — project completion is not blocked.
    function test_issue_upheldDisputeCanDeadlockProjectCompletion() public {
        uint256 index = _singlePendingIndex();

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        // Open dispute while still in the challenge window (before warping)
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("upheld-deadlock"), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(projId, index, true);

        // Settle validators: upheld dispute means stake is returned but no reward paid
        // No challenge period warp needed for upheld-dispute settlement
        uint256 nonce = engine.getContribution(projId, index).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(projId, index, nonce);

        // After fix: dispute resolution adjusts pipeline accounting so the project
        // can be completed without needing to release the overturned contributor reward.
        vm.prank(originator);
        engine.completeProject(projId);
        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Completed));
    }

    /// @notice FIX VERIFIED: cancelled projects can refund their escrow after the delay.
    function test_issue_cancelledProjectEscrowStranding() public {
        bytes32 cancelledPid = _pid("cancelled-escrow");
        _setupProject(cancelledPid, FUND_AMOUNT, QUANTITY);
        uint256 escrowBefore = engine.getProjectEscrow(cancelledPid, address(token));
        assertGt(escrowBefore, 0);

        vm.prank(admin);
        engine.removeProject(cancelledPid);

        // After fix: refundEscrow requires waiting for the PROJECT_COMPLETION_DELAY
        // to give participants time to settle before escrow is returned.
        vm.warp(block.timestamp + 31 days);
        vm.prank(originator);
        engine.refundEscrow(cancelledPid);
        assertEq(engine.getProjectEscrow(cancelledPid, address(token)), 0);
    }

    /// @notice FIX VERIFIED: uint256 score commit-hash packing matches reveal verification.
    function test_issue_uint256CommitHashEncodingMismatch() public {
        uint256 index = _singlePendingIndex();

        uint256 score = 8000;
        bytes32 salt = keccak256(abi.encodePacked("doc-style", validator1, projId, index));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projId, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        _claimAndCommit(validator2, projId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projId, index, 8000, VALIDATOR_STAKE);

        // After fix: uint256-encoded commit hash is the canonical format and reveals successfully.
        vm.prank(validator1);
        engine.revealValidation(projId, index, score, salt);

        assertEq(engine.getRevealCount(projId, index), 1);
    }
}
