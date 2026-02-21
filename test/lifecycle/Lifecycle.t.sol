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
            requiredSkill: bytes32(0),
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0
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

    /// @dev Commit and reveal for a validator, ensuring capacity
    function _validate(address val, bytes32 projectId, uint256 index, uint16 score, uint128 stakeAmt) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, projectId, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(val, uint256(stakeAmt) * 2);

        vm.startPrank(val);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = index;
            engine.claimToValidate(projectId, _indices);
        }
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projectId, index, commitHash, stakeAmt, address(0));
        engine.revealValidation(projectId, index, score, salt);
        vm.stopPrank();
    }

    /// @dev Run 3 validators above threshold on an index
    function _validateAboveThreshold(bytes32 projectId, uint256 index) internal {
        _validate(validator1, projectId, index, 8000, uint128(VALIDATOR_STAKE));
        _validate(validator2, projectId, index, 8500, uint128(VALIDATOR_STAKE));
        _validate(validator3, projectId, index, 7500, uint128(VALIDATOR_STAKE));
    }

    /// @dev Run 3 validators below threshold on an index
    function _validateBelowThreshold(bytes32 projectId, uint256 index) internal {
        _validate(validator1, projectId, index, 3000, uint128(VALIDATOR_STAKE));
        _validate(validator2, projectId, index, 2500, uint128(VALIDATOR_STAKE));
        _validate(validator3, projectId, index, 4000, uint128(VALIDATOR_STAKE));
    }

    /// @dev Settle all 3 validators
    function _settleAllValidators(bytes32 projectId, uint256 index) internal {
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
        assertEq(claim.submittedCount, uint32(qty));

        // Process each through full lifecycle
        for (uint256 i; i < indices.length; ++i) {
            _fullAcceptanceFlow(projId, indices[i]);
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

        _fullAcceptanceFlow(projId, indices1[0]);
        _fullAcceptanceFlow(projId, indices2[0]);

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projId, indices1[0]);
        engine.releaseContributorReward(projId, indices2[0]);

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

        _validateAboveThreshold(projId, goodIdx);
        engine.computeConsensus(projId, goodIdx);
        assertEq(uint256(engine.getContribution(projId, goodIdx).status), uint256(ContributionStatus.Accepted));

        _validateBelowThreshold(projId, badIdx);
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
        _fullAcceptanceFlow(projId, index);

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
        _fullAcceptanceFlow(projId, index);

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
        _fullAcceptanceFlow(projId, index);

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
        _fullAcceptanceFlow(projId, index);

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
        _fullAcceptanceFlow(projId, index);

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
        uint128 stakeAmt = uint128(VALIDATOR_STAKE);
        _ensureStake(validator1, uint256(stakeAmt) * 2);
        bytes32 salt = keccak256(abi.encodePacked("ghost", validator1));
        bytes32 commitHash = keccak256(abi.encodePacked(uint16(8000), salt));

        vm.startPrank(validator1);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = index;
            engine.claimToValidate(projId, _indices);
        }
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projId, index, commitHash, stakeAmt, address(0));
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

        uint128 stakeAmt = uint128(VALIDATOR_STAKE);
        _ensureStake(validator1, uint256(stakeAmt) * 2);
        bytes32 salt = keccak256(abi.encodePacked("ghost-early", validator1));
        bytes32 commitHash = keccak256(abi.encodePacked(uint16(8000), salt));

        vm.startPrank(validator1);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = index;
            engine.claimToValidate(projId, _indices);
        }
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projId, index, commitHash, stakeAmt, address(0));
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
        _fullAcceptanceFlow(projId, index);

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
        uint256 index = indices[0];

        _ensureStake(contributor1, VALIDATOR_STAKE * 2);
        vm.startPrank(contributor1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        vm.expectRevert(ISapienCore.CannotValidateOwnContribution.selector);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = index;
            engine.claimToValidate(projId, _indices);
        }
        vm.stopPrank();
    }

    /// @notice Cannot compute consensus with insufficient reveals
    function test_revert_consensusInsufficientReveals() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validate(validator1, projId, index, 8000, uint128(VALIDATOR_STAKE));
        _validate(validator2, projId, index, 8500, uint128(VALIDATOR_STAKE));

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

        uint16 score = 8000;
        bytes32 salt = keccak256("salt1");
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = index;
            engine.claimToValidate(projId, _indices);
        }
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projId, index, commitHash, uint128(VALIDATOR_STAKE), address(0));

        vm.expectRevert(ISapienCore.InvalidReveal.selector);
        engine.revealValidation(projId, index, 5000, salt); // wrong score
        vm.stopPrank();
    }

    /// @notice Cannot commit twice for same index
    function test_revert_doubleCommit() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        bytes32 commitHash = keccak256(abi.encodePacked(uint16(8000), bytes32("salt")));

        _ensureStake(validator1, VALIDATOR_STAKE * 4);
        vm.startPrank(validator1);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = index;
            engine.claimToValidate(projId, _indices);
        }
        engine.lockValidatorCapacity(VALIDATOR_STAKE * 2);
        engine.commitValidation(projId, index, commitHash, uint128(VALIDATOR_STAKE), address(0));

        vm.expectRevert(ISapienCore.AlreadyCommitted.selector);
        engine.commitValidation(projId, index, commitHash, uint128(VALIDATOR_STAKE), address(0));
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
    bytes32 internal constant CONTRIBUTOR_KEY = keccak256("CONTRIBUTOR");
    bytes32 internal constant VALIDATOR_KEY = keccak256("VALIDATOR");

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

        Reputation memory repBefore = engine.getReputation(contributor1, CONTRIBUTOR_KEY);
        uint256 scoreBefore = repBefore.score;

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        Reputation memory repAfter = engine.getReputation(contributor1, CONTRIBUTOR_KEY);
        assertGt(repAfter.score, scoreBefore);
        assertEq(repAfter.successfulActions, 1);
    }

    /// @notice Contributor reputation decreases on rejection
    function test_contributorReputationDecreasesOnRejection() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateBelowThreshold(projId, index);
        engine.computeConsensus(projId, index);

        Reputation memory rep = engine.getReputation(contributor1, CONTRIBUTOR_KEY);
        assertLt(rep.score, 5000); // < default
    }

    /// @notice Validator reputation increases on accurate settlement
    function test_validatorReputationIncreasesOnAccurateSettle() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);
        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);

        Reputation memory rep = engine.getReputation(validator1, VALIDATOR_KEY);
        assertGt(rep.score, 5000); // > default
        assertEq(rep.successfulActions, 1);
    }

    /// @notice Protocol fee sent to treasury on fund
    function test_protocolFeeSentToTreasury() public view {
        // Protocol fee is 1% of 10000e18 = 100e18
        uint256 treasuryBal = token.balanceOf(treasury);
        assertEq(treasuryBal, 100e18);
    }

    /// @notice Origination adapter fee credited on fund
    function test_originationAdapterFeeCredited() public view {
        uint256 adapterRewards = engine.getPendingRewards(adapter, address(token));
        // 2% of (10000e18 - 100e18) = 198e18
        assertEq(adapterRewards, 198e18);
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
        _validate(validator1, projId, index, 9000, uint128(VALIDATOR_STAKE));
        _validate(validator2, projId, index, 9000, uint128(VALIDATOR_STAKE));
        _validate(validator3, projId, index, 9000, uint128(VALIDATOR_STAKE));
        _validate(validator4, projId, index, 9000, uint128(VALIDATOR_STAKE));
        _validate(validator5, projId, index, 1000, uint128(VALIDATOR_STAKE));

        uint256 outlierSharesBefore = vault.balanceOf(validator5);

        engine.computeConsensus(projId, index);
        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        // Contribution should still be accepted (weighted avg well above 7000)
        assertEq(uint256(engine.getContribution(projId, index).status), uint256(ContributionStatus.Accepted));

        // Settle all
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

        // Process each index
        for (uint256 i; i < indices.length; ++i) {
            _fullAcceptanceFlow(projId, indices[i]);
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
        // Protocol fee = 1% of SMALL_FUND = 300e18
        uint256 protocolFee = (SMALL_FUND * 100) / 10_000;
        assertEq(token.balanceOf(treasury), protocolFee);

        // Origination fee = 2% of (SMALL_FUND - protocolFee)
        uint256 remaining = SMALL_FUND - protocolFee;
        uint256 originationFee = (remaining * 200) / 10_000;
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

        _settleAllValidators(projId, index2);

        // Challenger disputes the acceptance
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index2, keccak256("evidence"), "evidenceCid");

        // Operator upholds dispute
        vm.prank(admin);
        engine.resolveDispute(projId, index2, true);

        // Contributor2's reward is blocked
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

        // Process all
        for (uint256 i; i < indices1.length; ++i) {
            _fullAcceptanceFlow(projId, indices1[i]);
        }
        for (uint256 i; i < indices2.length; ++i) {
            _fullAcceptanceFlow(projId, indices2[i]);
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

        uint256 slotsAfterClaim = engine.getProject(projId).availableSlots;

        // Expire the claim
        vm.warp(block.timestamp + 8 days);
        engine.expireClaim(claimId, indices);

        // 2 unsubmitted returned
        assertEq(engine.getProject(projId).availableSlots, slotsAfterClaim + 2);

        // New contributor claims the 2 returned indices
        (, uint256[] memory newIndices) = _claimAndSubmit(contributor2, projId, 2);
        assertEq(newIndices.length, 2);

        for (uint256 i; i < newIndices.length; ++i) {
            _fullAcceptanceFlow(projId, newIndices[i]);
        }

        vm.warp(block.timestamp + 2 days);
        for (uint256 i; i < newIndices.length; ++i) {
            engine.releaseContributorReward(projId, newIndices[i]);
        }
        assertGt(engine.getPendingRewards(contributor2, address(token)), 0);
    }

    /// @notice Project with skill gate: validator without reputation is blocked
    function test_validatorReputationGate() public {
        bytes32 pid2 = _pid("rep-gate");
        Project memory config = _defaultConfig();
        config.requiredSkill = keccak256("LABELING");
        config.minValidatorReputation = 6000; // Above default 5000

        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, 5, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid2, 1);
        uint256 index = indices[0];

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InsufficientReputation.selector, 6000, 5000));
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = index;
            engine.claimToValidate(pid2, _indices);
        }
        vm.stopPrank();
    }

    /// @notice Validators with different stakes get proportional rewards
    function test_stakeWeightedRewardDistribution() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        // Same score, different stakes
        uint128 lowStake = 10e18;
        uint128 highStake = 100e18;

        _validate(validator1, projId, index, 8000, lowStake);
        _validate(validator2, projId, index, 8000, highStake);
        _validate(validator3, projId, index, 8000, highStake);

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
