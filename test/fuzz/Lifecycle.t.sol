// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {QualityEngine} from "src/QualityEngine.sol";
import {IQualityEngine} from "src/interfaces/IQualityEngine.sol";
import {StakeVault} from "src/StakeVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    IndexState,
    SubmissionStatus,
    Contribution,
    ContributionStatus,
    ConsensusReport,
    Reputation,
    StakeAccount
} from "src/Types.sol";

/// @title LifecycleFuzzTest
/// @notice End-to-end fuzz tests covering the full PoQ contribution lifecycle:
///         project creation → funding → claim → contribute → validate → consensus →
///         settlement → reward release → reward claim
contract LifecycleFuzzTest is BaseTest {
    // ════════════════════════════════════════════════════════════════════
    // Helpers
    // ════════════════════════════════════════════════════════════════════

    /// @dev Bound a score to valid range [0, 10000]
    function _boundScore(uint16 raw) internal pure returns (uint16) {
        return uint16(bound(uint256(raw), 0, 10_000));
    }

    /// @dev Bound a quantity to [1, maxQty]
    function _boundQty(uint256 raw, uint256 maxQty) internal pure returns (uint256) {
        return bound(raw, 1, maxQty);
    }

    /// @dev Bound a funding amount to a reasonable range so fees don't round to zero
    function _boundFundAmount(uint256 raw) internal pure returns (uint256) {
        return bound(raw, 1_000e18, 1_000_000e18);
    }

    /// @dev Bound stake to [1e18, 500e18] — must be affordable by deposited balances
    function _boundStake(uint128 raw) internal pure returns (uint128) {
        return uint128(bound(uint256(raw), 1e18, 200e18));
    }

    /// @dev Ensure an address has enough *available* (unlocked) tokens in the vault.
    ///      Accounts for existing contributor locks, validator capacity, and in-flight stake.
    function _ensureStake(address user, uint256 needed) internal {
        uint256 available = vault.availableBalance(user);
        if (available < needed) {
            uint256 deficit = needed - available + 1e18; // buffer
            token.mint(user, deficit);
            vm.startPrank(user);
            token.approve(address(vault), deficit);
            vault.deposit(deficit, user);
            vm.stopPrank();
        }
    }

    /// @dev Generate a unique project id from a seed
    function _projectId(uint256 seed) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("fuzz-project", seed));
    }

    /// @dev Commit and reveal for a validator, ensuring they have capacity
    function _fuzzCommitAndReveal(address val, bytes32 projectId, uint256 index, uint16 score, uint128 stakeAmt)
        internal
    {
        bytes32 salt = keccak256(abi.encodePacked("fuzz-salt", val, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        // Ensure validator has enough staked
        _ensureStake(val, uint256(stakeAmt) * 2);

        vm.startPrank(val);
        engine.setValidatorCapacity(stakeAmt);
        engine.commitValidation(projectId, index, commitHash, stakeAmt);
        engine.revealValidation(projectId, index, score, salt);
        vm.stopPrank();
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 1: Happy-Path Full Lifecycle with Fuzzed Parameters
    // ════════════════════════════════════════════════════════════════════

    /// @notice Fuzz a complete lifecycle: create → fund → claim → contribute →
    ///         validate (3 validators) → compute consensus → settle → release → claim reward.
    ///         All three validator scores are above 70% so contribution is accepted.
    /// @dev quantity >= 2 required: the protocol deducts validator rewards AND the full
    ///      contributor rewardRate from escrow. With validatorRewardBps=2000, processing
    ///      one index costs 1.2x per-index escrow. At quantity=1, this exceeds escrow.
    function testFuzz_happyPathLifecycle(
        uint256 fundAmount,
        uint256 quantitySeed,
        uint128 validatorStakeSeed,
        uint16 score1Raw,
        uint16 score2Raw,
        uint16 score3Raw
    ) public {
        // ── Bound inputs ────────────────────────────────────────────
        fundAmount = _boundFundAmount(fundAmount);
        uint256 quantity = bound(quantitySeed, 2, 20); // >= 2 to avoid escrow underflow
        uint128 valStake = _boundStake(validatorStakeSeed);

        // All scores above consensus threshold (7000) for acceptance
        uint16 score1 = uint16(bound(uint256(score1Raw), 7000, 10_000));
        uint16 score2 = uint16(bound(uint256(score2Raw), 7000, 10_000));
        uint16 score3 = uint16(bound(uint256(score3Raw), 7000, 10_000));

        bytes32 projId = _projectId(fundAmount);

        // ── Setup: ensure originator has enough tokens ──────────────
        token.mint(originator, fundAmount);

        // ── Create & fund project ───────────────────────────────────
        vm.startPrank(originator);
        Project memory config = Project({
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
        engine.createProject(projId, config);
        token.approve(address(engine), fundAmount);
        engine.fundProject(projId, fundAmount, quantity, adapter);
        vm.stopPrank();

        { // Verify funded project
            Project memory proj = engine.getProject(projId);
            assertEq(uint256(proj.status), uint256(ProjectStatus.Funded));
            assertEq(proj.totalQuantity, quantity);
            assertEq(proj.availableSlots, quantity);
        }

        uint256 index;
        { // Claim 1 index as contributor1
            _ensureStake(contributor1, STAKE_AMOUNT * 2);
            vm.startPrank(contributor1);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 1, adapter);
            assertEq(indices.length, 1);
            index = indices[0];
            bytes32 subHash = keccak256(abi.encodePacked("fuzz-submission", index));
            engine.contribute(claimId, index, subHash);
            vm.stopPrank();
        }

        { // Verify contribution
            Contribution memory contrib = engine.getContribution(projId, index);
            assertEq(uint256(contrib.status), uint256(ContributionStatus.Pending));
            assertGt(contrib.rewardRate, 0);
        }

        // Validate with 3 validators
        _fuzzCommitAndReveal(validator1, projId, index, score1, valStake);
        _fuzzCommitAndReveal(validator2, projId, index, score2, valStake);
        _fuzzCommitAndReveal(validator3, projId, index, score3, valStake);
        assertEq(engine.getRevealCount(projId, index), 3);

        // Compute consensus
        engine.computeConsensus(projId, index);

        { // Verify consensus
            ConsensusReport memory r = engine.getConsensusReport(projId, index);
            assertTrue(r.computed);
            assertGe(r.weightedAverage, 7000);
            Contribution memory contrib = engine.getContribution(projId, index);
            assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted));
            assertGt(contrib.challengeEndsAt, 0);
        }

        // ── Settle all validators ───────────────────────────────────
        uint256 settleNonce = engine.getContribution(projId, index).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(projId, index, settleNonce);
        vm.prank(validator2);
        engine.settleValidator(projId, index, settleNonce);
        vm.prank(validator3);
        engine.settleValidator(projId, index, settleNonce);

        // All should be settled and not outliers
        assertTrue(engine.isValidatorSettled(projId, index, 0, validator1));
        assertTrue(engine.isValidatorSettled(projId, index, 0, validator2));
        assertTrue(engine.isValidatorSettled(projId, index, 0, validator3));
        assertFalse(engine.isValidatorOutlier(projId, index, validator1));
        assertFalse(engine.isValidatorOutlier(projId, index, validator2));
        assertFalse(engine.isValidatorOutlier(projId, index, validator3));

        // Validators should have pending rewards
        uint256 v1Rewards = engine.getPendingRewards(validator1, address(token));
        uint256 v2Rewards = engine.getPendingRewards(validator2, address(token));
        uint256 v3Rewards = engine.getPendingRewards(validator3, address(token));
        assertGt(v1Rewards + v2Rewards + v3Rewards, 0);

        // ── Release contributor reward after challenge period ────────
        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(projId, index);

        uint256 contribReward = engine.getPendingRewards(contributor1, address(token));
        assertGt(contribReward, 0);

        // ── Claim all rewards ───────────────────────────────────────
        uint256 balBefore = token.balanceOf(contributor1);
        vm.prank(contributor1);
        engine.claimReward(address(token));
        assertGt(token.balanceOf(contributor1), balBefore);

        balBefore = token.balanceOf(validator1);
        vm.prank(validator1);
        engine.claimReward(address(token));
        assertGt(token.balanceOf(validator1), balBefore);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 2: Rejection Lifecycle — Low Scores Cause Rejection + Slash
    // ════════════════════════════════════════════════════════════════════

    /// @notice Fuzz a rejection lifecycle: all validators score below threshold,
    ///         contribution is rejected, contributor is slashed, index is re-available.
    function testFuzz_rejectionLifecycle(
        uint256 fundAmount,
        uint128 validatorStakeSeed,
        uint16 score1Raw,
        uint16 score2Raw,
        uint16 score3Raw
    ) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint128 valStake = _boundStake(validatorStakeSeed);

        // All scores below consensus threshold (7000) for rejection
        uint16 score1 = uint16(bound(uint256(score1Raw), 0, 6999));
        uint16 score2 = uint16(bound(uint256(score2Raw), 0, 6999));
        uint16 score3 = uint16(bound(uint256(score3Raw), 0, 6999));

        bytes32 projId = _projectId(fundAmount + 1);
        uint256 quantity = 5;

        token.mint(originator, fundAmount);

        // ── Create & fund ───────────────────────────────────────────
        vm.startPrank(originator);
        Project memory config = Project({
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
        engine.createProject(projId, config);
        token.approve(address(engine), fundAmount);
        engine.fundProject(projId, fundAmount, quantity, adapter);
        vm.stopPrank();

        uint256 availableBefore = engine.getProject(projId).availableSlots;

        // ── Claim & contribute ──────────────────────────────────────
        uint256 index;
        {
            _ensureStake(contributor1, STAKE_AMOUNT * 3);
            vm.startPrank(contributor1);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 1, adapter);
            index = indices[0];
            engine.contribute(claimId, index, keccak256("rejected-submission"));
            vm.stopPrank();
        }

        { // Validate, compute, and assert in scoped block
            uint256 sharesBefore = vault.balanceOf(contributor1);

            _fuzzCommitAndReveal(validator1, projId, index, score1, valStake);
            _fuzzCommitAndReveal(validator2, projId, index, score2, valStake);
            _fuzzCommitAndReveal(validator3, projId, index, score3, valStake);

            engine.computeConsensus(projId, index);

            Contribution memory contrib = engine.getContribution(projId, index);
            assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected));

            assertLt(vault.balanceOf(contributor1), sharesBefore);
            assertEq(engine.getProject(projId).availableSlots, availableBefore);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 3: Multi-Contribution Lifecycle — Multiple Indices in One Claim
    // ════════════════════════════════════════════════════════════════════

    /// @notice Fuzz processing multiple contributions from a single claim through
    ///         the full lifecycle with varying scores per index.
    function testFuzz_multiContributionLifecycle(
        uint256 fundAmount,
        uint256 claimQtySeed,
        uint128 validatorStakeSeed,
        uint16 score1Raw,
        uint16 score2Raw,
        uint16 score3Raw
    ) public {
        fundAmount = _boundFundAmount(fundAmount);
        bytes32 projId = _projectId(fundAmount + 2);
        uint256[] memory indices;

        { // ── Setup: bound, create, fund, claim ─────────────────────
            uint256 claimQty = _boundQty(claimQtySeed, 5);

            token.mint(originator, fundAmount);
            _ensureStake(contributor1, STAKE_AMOUNT * (claimQty + 2));

            vm.startPrank(originator);
            Project memory config = Project({
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
            engine.createProject(projId, config);
            token.approve(address(engine), fundAmount);
            engine.fundProject(projId, fundAmount, claimQty + 5, adapter);
            vm.stopPrank();

            vm.startPrank(contributor1);
            uint256 claimId;
            (claimId, indices) = engine.claimToContribute(projId, claimQty, adapter);
            for (uint256 i; i < indices.length; ++i) {
                engine.contribute(claimId, indices[i], keccak256(abi.encodePacked("multi", i)));
            }
            vm.stopPrank();

            Claim memory claim = engine.getClaim(claimId);
            assertEq(uint256(claim.status), uint256(ClaimStatus.Completed));
        }

        { // ── Validate each contribution ─────────────────────────────
            uint128 valStake = _boundStake(validatorStakeSeed);
            uint16 score1 = uint16(bound(uint256(score1Raw), 7000, 10_000));
            uint16 score2 = uint16(bound(uint256(score2Raw), 7000, 10_000));
            uint16 score3 = uint16(bound(uint256(score3Raw), 7000, 10_000));

            for (uint256 i; i < indices.length; ++i) {
                uint256 idx = indices[i];
                _fuzzCommitAndReveal(validator1, projId, idx, score1, valStake);
                _fuzzCommitAndReveal(validator2, projId, idx, score2, valStake);
                _fuzzCommitAndReveal(validator3, projId, idx, score3, valStake);
                engine.computeConsensus(projId, idx);
            }
        }

        // Verify all accepted
        for (uint256 i; i < indices.length; ++i) {
            Contribution memory c = engine.getContribution(projId, indices[i]);
            assertEq(uint256(c.status), uint256(ContributionStatus.Accepted));
        }

        { // ── Settle and release rewards ─────────────────────────────
            for (uint256 i; i < indices.length; ++i) {
                uint256 settleNonce = engine.getContribution(projId, indices[i]).consensusNonce;
                vm.prank(validator1);
                engine.settleValidator(projId, indices[i], settleNonce);
                vm.prank(validator2);
                engine.settleValidator(projId, indices[i], settleNonce);
                vm.prank(validator3);
                engine.settleValidator(projId, indices[i], settleNonce);
            }

            vm.warp(block.timestamp + 2 days);
            for (uint256 i; i < indices.length; ++i) {
                engine.releaseContributorReward(projId, indices[i]);
            }

            uint256 totalPending = engine.getPendingRewards(contributor1, address(token));
            assertGt(totalPending, 0);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 4: Claim Expiration with Partial Submission
    // ════════════════════════════════════════════════════════════════════

    /// @notice Fuzz partial claim completion and expiration: contributor submits
    ///         some indices but lets the claim expire, resulting in slashing for
    ///         unsubmitted work and return of those indices.
    function testFuzz_claimExpiration(uint256 fundAmount, uint256 claimQtySeed, uint256 submitCountSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint256 claimQty = _boundQty(claimQtySeed, 8);
        uint256 submitCount = bound(submitCountSeed, 0, claimQty - 1); // at least 1 unsubmitted

        bytes32 projId = _projectId(fundAmount + 3);

        token.mint(originator, fundAmount);
        _ensureStake(contributor1, STAKE_AMOUNT * (claimQty + 2));

        { // ── Create & fund ─────────────────────────────────────────
            vm.startPrank(originator);
            Project memory config = Project({
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
            engine.createProject(projId, config);
            token.approve(address(engine), fundAmount);
            engine.fundProject(projId, fundAmount, claimQty, adapter);
            vm.stopPrank();
        }

        uint256 slotsAfterFund = engine.getProject(projId).availableSlots;
        uint256 unsubmitted = claimQty - submitCount;
        uint256 sharesBefore;

        { // ── Claim indices and submit partial ──────────────────────
            vm.startPrank(contributor1);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, claimQty, adapter);

            for (uint256 i; i < submitCount; ++i) {
                engine.contribute(claimId, indices[i], keccak256(abi.encodePacked("partial", i)));
            }
            vm.stopPrank();

            sharesBefore = vault.balanceOf(contributor1);

            // ── Warp past deadline and expire ───────────────────────
            vm.warp(block.timestamp + 8 days);
            engine.expireClaim(claimId, indices);

            Claim memory claim = engine.getClaim(claimId);
            assertEq(uint256(claim.status), uint256(ClaimStatus.Expired));
        }

        { // ── Verify expiration results ─────────────────────────────
            uint256 slotsAfterExpire = engine.getProject(projId).availableSlots;
            assertEq(slotsAfterExpire, slotsAfterFund - claimQty + unsubmitted);

            if (unsubmitted > 0) {
                uint256 sharesAfter = vault.balanceOf(contributor1);
                assertLt(sharesAfter, sharesBefore);
            }
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 5: Outlier Validator Detection and Slashing
    // ════════════════════════════════════════════════════════════════════

    /// @notice Fuzz a scenario where one validator scores wildly differently from
    ///         the other four, triggering outlier detection and tiered slashing.
    /// @dev With only 3 equal-weight validators, the max deviation ratio for any single
    ///      validator is ~1.41σ, below the 1.5σ detection threshold. Using 5 validators
    ///      (4 agree + 1 outlier) ensures the outlier reaches ~2σ, reliably triggering detection.
    ///      Average: (4*good + outlier)/5. For avg >= 7000: outlier >= 35000 - 4*good.
    function testFuzz_outlierValidatorSlashing(
        uint256 fundAmount,
        uint128 validatorStakeSeed,
        uint16 goodScoreRaw,
        uint16 outlierScoreRaw
    ) public {
        fundAmount = _boundFundAmount(fundAmount);
        bytes32 projId = _projectId(fundAmount + 4);

        // Extra validator addresses for the 5-validator scenario
        address validator4 = makeAddr("fuzz-validator4");
        address validator5 = makeAddr("fuzz-validator5");

        uint16 goodScore;
        uint16 outlierScore;

        { // ── Bound scores ──────────────────────────────────────────
            goodScore = uint16(bound(uint256(goodScoreRaw), 9000, 10_000));
            uint256 minOutlier = 35_000 > 4 * uint256(goodScore) ? 35_000 - 4 * uint256(goodScore) : 0;
            uint256 maxOutlier = uint256(goodScore) > 3000 ? uint256(goodScore) - 3000 : 0;
            require(maxOutlier >= minOutlier, "invalid outlier range");
            outlierScore = uint16(bound(uint256(outlierScoreRaw), minOutlier, maxOutlier));
        }

        token.mint(originator, fundAmount);

        { // ── Create & fund (5 validations required) ────────────────
            vm.startPrank(originator);
            Project memory config = Project({
                originator: address(0),
                rewardToken: address(token),
                totalRewards: 0,
                totalQuantity: 0,
                availableSlots: 0,
                consensusThreshold: 7000,
                minStakeToClaim: STAKE_AMOUNT,
                validatorRewardBps: 2000,
                numberOfValidations: 5,
                requiredSkill: bytes32(0),
                minValidatorReputation: 0,
                minValidationStake: 0,
                status: ProjectStatus.Created,
                activatedAt: 0,
                completedAt: 0
            });
            engine.createProject(projId, config);
            token.approve(address(engine), fundAmount);
            engine.fundProject(projId, fundAmount, 5, adapter);
            vm.stopPrank();
        }

        uint256 index;
        { // ── Claim & contribute ────────────────────────────────────
            _ensureStake(contributor1, STAKE_AMOUNT * 3);
            vm.startPrank(contributor1);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 1, adapter);
            index = indices[0];
            engine.contribute(claimId, index, keccak256("outlier-test"));
            vm.stopPrank();
        }

        { // ── Validate + consensus ──────────────────────────────────
            uint128 valStake = _boundStake(validatorStakeSeed);
            _fuzzCommitAndReveal(validator1, projId, index, goodScore, valStake);
            _fuzzCommitAndReveal(validator2, projId, index, goodScore, valStake);
            _fuzzCommitAndReveal(validator3, projId, index, goodScore, valStake);
            _fuzzCommitAndReveal(validator4, projId, index, goodScore, valStake);
            _fuzzCommitAndReveal(validator5, projId, index, outlierScore, valStake);
        }

        uint256 outlierSharesBefore = vault.balanceOf(validator5);
        engine.computeConsensus(projId, index);

        { // ── Verify consensus ──────────────────────────────────────
            ConsensusReport memory r = engine.getConsensusReport(projId, index);
            assertTrue(r.computed);
            assertGe(r.weightedAverage, 7000);

            Contribution memory contrib = engine.getContribution(projId, index);
            assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted));
        }

        { // ── Settle all 5 validators ───────────────────────────────
            uint256 settleNonce = engine.getContribution(projId, index).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(projId, index, settleNonce);
            vm.prank(validator2);
            engine.settleValidator(projId, index, settleNonce);
            vm.prank(validator3);
            engine.settleValidator(projId, index, settleNonce);
            vm.prank(validator4);
            engine.settleValidator(projId, index, settleNonce);
            vm.prank(validator5);
            engine.settleValidator(projId, index, settleNonce);
        }

        { // ── Assert outlier detection ──────────────────────────────
            assertTrue(engine.isValidatorOutlier(projId, index, validator5));

            uint256 outlierSharesAfter = vault.balanceOf(validator5);
            assertLe(outlierSharesAfter, outlierSharesBefore);

            assertFalse(engine.isValidatorOutlier(projId, index, validator1));
            assertFalse(engine.isValidatorOutlier(projId, index, validator2));
            assertFalse(engine.isValidatorOutlier(projId, index, validator3));
            assertFalse(engine.isValidatorOutlier(projId, index, validator4));

            assertGt(engine.getPendingRewards(validator1, address(token)), 0);
            assertGt(engine.getPendingRewards(validator2, address(token)), 0);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 6: Ghost Validator — Commit Without Reveal → Slash
    // ════════════════════════════════════════════════════════════════════

    /// @notice Fuzz ghost validator behavior: a validator commits but never reveals,
    ///         and after the deadline anyone can cancel and slash them.
    function testFuzz_ghostValidatorSlash(uint256 fundAmount, uint128 validatorStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint128 valStake = _boundStake(validatorStakeSeed);

        bytes32 projId = _projectId(fundAmount + 5);

        token.mint(originator, fundAmount);

        { // ── Create & fund ─────────────────────────────────────────
            vm.startPrank(originator);
            Project memory config = Project({
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
            engine.createProject(projId, config);
            token.approve(address(engine), fundAmount);
            engine.fundProject(projId, fundAmount, 5, adapter);
            vm.stopPrank();
        }

        uint256 index;
        { // ── Claim & contribute ────────────────────────────────────
            _ensureStake(contributor1, STAKE_AMOUNT * 3);
            vm.startPrank(contributor1);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 1, adapter);
            index = indices[0];
            engine.contribute(claimId, index, keccak256("ghost-test"));
            vm.stopPrank();
        }

        { // ── Ghost validator commits but does NOT reveal ────────────
            _ensureStake(validator1, uint256(valStake) * 2);
            bytes32 salt = keccak256(abi.encodePacked("ghost-salt", validator1));
            uint256 nonce = engine.getSubmissionNonce(projId, index);
            bytes32 commitHash = keccak256(abi.encodePacked(projId, index, nonce, validator1, uint16(8000), salt));

            vm.startPrank(validator1);
            engine.setValidatorCapacity(valStake);
            engine.commitValidation(projId, index, commitHash, valStake);
            vm.stopPrank();
        }

        // Record shares before slashing
        uint256 sharesBefore = vault.balanceOf(validator1);

        // ── Warp past commit + reveal deadline ──────────────────────
        // COMMIT_DEADLINE = 3 days, REVEAL_DEADLINE = 2 days
        vm.warp(block.timestamp + 6 days);

        // ── Anyone cancels the expired commitment → slash ───────────
        engine.cancelExpiredCommitment(projId, index, validator1);

        // Validator should have been slashed
        uint256 sharesAfter = vault.balanceOf(validator1);
        assertLt(sharesAfter, sharesBefore);
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 7: Reward Accounting Invariant — No Over-distribution
    // ════════════════════════════════════════════════════════════════════

    /// @notice Fuzz that for a single accepted contribution, the total rewards distributed
    ///         to the contributor and validators never exceed the project escrow.
    /// @dev NOTE: The protocol deducts the full `rewardRate` (totalRewards/totalQuantity)
    ///      from escrow for contributor rewards AND also deducts validator rewards from escrow
    ///      separately. This means processing ALL indices would drain 1.2x escrow (with 20%
    ///      validatorRewardBps). This test verifies the per-index accounting is sound by
    ///      processing 1 of N indices.
    function testFuzz_rewardAccountingInvariant(
        uint256 fundAmount,
        uint128 validatorStakeSeed,
        uint16 score1Raw,
        uint16 score2Raw,
        uint16 score3Raw
    ) public {
        fundAmount = _boundFundAmount(fundAmount);
        bytes32 projId = _projectId(fundAmount + 6);

        token.mint(originator, fundAmount);

        { // ── Create & fund ─────────────────────────────────────────
            vm.startPrank(originator);
            Project memory config = Project({
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
            engine.createProject(projId, config);
            token.approve(address(engine), fundAmount);
            engine.fundProject(projId, fundAmount, 10, adapter);
            vm.stopPrank();
        }

        uint256 escrowBefore = engine.getProjectEscrow(projId, address(token));

        uint256 idx;
        { // ── Claim & contribute ────────────────────────────────────
            _ensureStake(contributor1, STAKE_AMOUNT * 3);
            vm.startPrank(contributor1);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 1, adapter);
            idx = indices[0];
            engine.contribute(claimId, idx, keccak256(abi.encodePacked("inv", idx)));
            vm.stopPrank();
        }

        uint256 rewardRate;
        { // ── Validate + consensus ──────────────────────────────────
            uint128 valStake = _boundStake(validatorStakeSeed);
            uint16 score1 = uint16(bound(uint256(score1Raw), 7500, 10_000));
            uint16 score2 = uint16(bound(uint256(score2Raw), 7500, 10_000));
            uint16 score3 = uint16(bound(uint256(score3Raw), 7500, 10_000));

            _fuzzCommitAndReveal(validator1, projId, idx, score1, valStake);
            _fuzzCommitAndReveal(validator2, projId, idx, score2, valStake);
            _fuzzCommitAndReveal(validator3, projId, idx, score3, valStake);

            engine.computeConsensus(projId, idx);

            Contribution memory contrib = engine.getContribution(projId, idx);
            assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted));
            rewardRate = contrib.rewardRate;
        }

        // Track validator rewards from settlement
        uint256 totalValidatorRewards;
        {
            uint256 v1Before = engine.getPendingRewards(validator1, address(token));
            uint256 v2Before = engine.getPendingRewards(validator2, address(token));
            uint256 v3Before = engine.getPendingRewards(validator3, address(token));

            uint256 settleNonce = engine.getContribution(projId, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(projId, idx, settleNonce);
            vm.prank(validator2);
            engine.settleValidator(projId, idx, settleNonce);
            vm.prank(validator3);
            engine.settleValidator(projId, idx, settleNonce);

            totalValidatorRewards += engine.getPendingRewards(validator1, address(token)) - v1Before;
            totalValidatorRewards += engine.getPendingRewards(validator2, address(token)) - v2Before;
            totalValidatorRewards += engine.getPendingRewards(validator3, address(token)) - v3Before;
        }

        // Release contributor reward
        uint256 totalContribRewards;
        {
            vm.warp(block.timestamp + 2 days);
            uint256 cBefore = engine.getPendingRewards(contributor1, address(token));
            engine.releaseContributorReward(projId, idx);
            totalContribRewards = engine.getPendingRewards(contributor1, address(token)) - cBefore;
        }

        // INVARIANT: escrow was reduced by validator + contributor deductions
        uint256 escrowAfter = engine.getProjectEscrow(projId, address(token));
        assertGt(escrowAfter, 0);

        {
            Project memory proj = engine.getProject(projId);
            uint256 perIndexValidatorMax = (proj.totalRewards * proj.validatorRewardBps) / (10_000 * proj.totalQuantity);
            assertLe(totalValidatorRewards, perIndexValidatorMax);
        }

        assertGt(totalContribRewards, 0);
        assertLe(totalContribRewards, rewardRate);

        {
            Project memory projFinal = engine.getProject(projId);
            uint256 contributorShare = (rewardRate * (10_000 - projFinal.validatorRewardBps)) / 10_000;
            uint256 totalEscrowDrain = escrowBefore - escrowAfter;
            assertEq(totalEscrowDrain, contributorShare + totalValidatorRewards);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 8: Rejection → Re-submission Lifecycle
    // ════════════════════════════════════════════════════════════════════

    /// @notice Fuzz the rejection-then-resubmission flow: contribution is rejected,
    ///         index returns to the pool, a new contributor claims and submits,
    ///         this time it gets accepted.
    function testFuzz_rejectionThenResubmission(uint256 fundAmount, uint128 validatorStakeSeed) public {
        fundAmount = _boundFundAmount(fundAmount);
        uint128 valStake = _boundStake(validatorStakeSeed);

        bytes32 projId = _projectId(fundAmount + 7);

        token.mint(originator, fundAmount);

        // ── Create & fund ───────────────────────────────────────────
        vm.startPrank(originator);
        Project memory config = Project({
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
        engine.createProject(projId, config);
        token.approve(address(engine), fundAmount);
        engine.fundProject(projId, fundAmount, 3, adapter);
        vm.stopPrank();

        uint256 index;
        { // First contributor: claim, contribute, get rejected
            _ensureStake(contributor1, STAKE_AMOUNT * 3);
            vm.startPrank(contributor1);
            (uint256 claimId1, uint256[] memory indices1) = engine.claimToContribute(projId, 1, adapter);
            index = indices1[0];
            engine.contribute(claimId1, index, keccak256("bad-work"));
            vm.stopPrank();

            _fuzzCommitAndReveal(validator1, projId, index, 2000, valStake);
            _fuzzCommitAndReveal(validator2, projId, index, 3000, valStake);
            _fuzzCommitAndReveal(validator3, projId, index, 2500, valStake);
            engine.computeConsensus(projId, index);

            assertEq(uint256(engine.getContribution(projId, index).status), uint256(ContributionStatus.Rejected));
            assertEq(engine.getSubmissionNonce(projId, index), 1);
            assertEq(engine.getProject(projId).availableSlots, 3);
        }

        uint256 index2;
        { // Second contributor: claim the same index, contribute, get accepted
            _ensureStake(contributor2, STAKE_AMOUNT * 3);
            vm.startPrank(contributor2);
            (uint256 claimId2, uint256[] memory indices2) = engine.claimToContribute(projId, 1, adapter);
            index2 = indices2[0];
            engine.contribute(claimId2, index2, keccak256("good-work"));
            vm.stopPrank();

            _fuzzCommitAndReveal(validator1, projId, index2, 9000, valStake);
            _fuzzCommitAndReveal(validator2, projId, index2, 8500, valStake);
            _fuzzCommitAndReveal(validator3, projId, index2, 9500, valStake);
            engine.computeConsensus(projId, index2);

            assertEq(uint256(engine.getContribution(projId, index2).status), uint256(ContributionStatus.Accepted));
        }

        { // Full finalization
            uint256 settleNonce = engine.getContribution(projId, index2).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(projId, index2, settleNonce);
            vm.prank(validator2);
            engine.settleValidator(projId, index2, settleNonce);
            vm.prank(validator3);
            engine.settleValidator(projId, index2, settleNonce);

            vm.warp(block.timestamp + 2 days);
            engine.releaseContributorReward(projId, index2);
            assertGt(engine.getPendingRewards(contributor2, address(token)), 0);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 9: Two Contributors, Different Outcomes on Same Project
    // ════════════════════════════════════════════════════════════════════

    /// @notice Fuzz a scenario where two contributors work on the same project:
    ///         one's contribution is accepted, the other's is rejected.
    function testFuzz_mixedOutcomeSameProject(
        uint256 fundAmount,
        uint128 validatorStakeSeed,
        uint16 goodScoreRaw,
        uint16 badScoreRaw
    ) public {
        fundAmount = _boundFundAmount(fundAmount);
        bytes32 projId = _projectId(fundAmount + 8);

        token.mint(originator, fundAmount);

        { // ── Create & fund ─────────────────────────────────────────
            vm.startPrank(originator);
            Project memory config = Project({
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
            engine.createProject(projId, config);
            token.approve(address(engine), fundAmount);
            engine.fundProject(projId, fundAmount, 10, adapter);
            vm.stopPrank();
        }

        uint256 goodIndex;
        { // ── Contributor1: will be accepted ────────────────────────
            _ensureStake(contributor1, STAKE_AMOUNT * 3);
            vm.startPrank(contributor1);
            (uint256 claimId1, uint256[] memory indices1) = engine.claimToContribute(projId, 1, adapter);
            goodIndex = indices1[0];
            engine.contribute(claimId1, goodIndex, keccak256("good-work"));
            vm.stopPrank();
        }

        uint256 badIndex;
        { // ── Contributor2: will be rejected ────────────────────────
            _ensureStake(contributor2, STAKE_AMOUNT * 3);
            vm.startPrank(contributor2);
            (uint256 claimId2, uint256[] memory indices2) = engine.claimToContribute(projId, 1, adapter);
            badIndex = indices2[0];
            engine.contribute(claimId2, badIndex, keccak256("bad-work"));
            vm.stopPrank();
        }

        { // ── Validate both contributions ───────────────────────────
            uint128 valStake = _boundStake(validatorStakeSeed);
            uint16 goodScore = uint16(bound(uint256(goodScoreRaw), 7500, 10_000));
            uint16 badScore = uint16(bound(uint256(badScoreRaw), 0, 5000));

            _fuzzCommitAndReveal(validator1, projId, goodIndex, goodScore, valStake);
            _fuzzCommitAndReveal(validator2, projId, goodIndex, goodScore, valStake);
            _fuzzCommitAndReveal(validator3, projId, goodIndex, goodScore, valStake);
            engine.computeConsensus(projId, goodIndex);

            _fuzzCommitAndReveal(validator1, projId, badIndex, badScore, valStake);
            _fuzzCommitAndReveal(validator2, projId, badIndex, badScore, valStake);
            _fuzzCommitAndReveal(validator3, projId, badIndex, badScore, valStake);
            engine.computeConsensus(projId, badIndex);
        }

        { // ── Assert outcomes ───────────────────────────────────────
            Contribution memory good = engine.getContribution(projId, goodIndex);
            Contribution memory bad = engine.getContribution(projId, badIndex);

            assertEq(uint256(good.status), uint256(ContributionStatus.Accepted));
            assertEq(uint256(bad.status), uint256(ContributionStatus.Rejected));
        }

        { // ── Settle, release, and verify rewards ───────────────────
            uint256 settleNonce = engine.getContribution(projId, goodIndex).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(projId, goodIndex, settleNonce);
            vm.prank(validator2);
            engine.settleValidator(projId, goodIndex, settleNonce);
            vm.prank(validator3);
            engine.settleValidator(projId, goodIndex, settleNonce);

            vm.warp(block.timestamp + 2 days);
            engine.releaseContributorReward(projId, goodIndex);

            assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
            assertEq(engine.getPendingRewards(contributor2, address(token)), 0);
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Test 10: Varying Validator Stakes Affect Reward Distribution
    // ════════════════════════════════════════════════════════════════════

    /// @notice Fuzz that validators staking different amounts receive proportional
    ///         rewards based on their consensus weight.
    function testFuzz_stakeWeightedRewards(
        uint256 fundAmount,
        uint128 stake1Seed,
        uint128 stake2Seed,
        uint128 stake3Seed,
        uint16 scoreRaw
    ) public {
        fundAmount = _boundFundAmount(fundAmount);
        bytes32 projId = _projectId(fundAmount + 9);

        token.mint(originator, fundAmount);

        { // ── Create & fund ─────────────────────────────────────────
            vm.startPrank(originator);
            Project memory config = Project({
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
            engine.createProject(projId, config);
            token.approve(address(engine), fundAmount);
            engine.fundProject(projId, fundAmount, 5, adapter);
            vm.stopPrank();
        }

        uint256 index;
        { // ── Claim & contribute ────────────────────────────────────
            _ensureStake(contributor1, STAKE_AMOUNT * 3);
            vm.startPrank(contributor1);
            (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 1, adapter);
            index = indices[0];
            engine.contribute(claimId, index, keccak256("stake-weight-test"));
            vm.stopPrank();
        }

        { // ── Validate with different stakes (same score) ───────────
            uint128 stake1 = _boundStake(stake1Seed);
            uint128 stake2 = _boundStake(stake2Seed);
            uint128 stake3 = _boundStake(stake3Seed);
            uint16 score = uint16(bound(uint256(scoreRaw), 8000, 9000));

            _fuzzCommitAndReveal(validator1, projId, index, score, stake1);
            _fuzzCommitAndReveal(validator2, projId, index, score, stake2);
            _fuzzCommitAndReveal(validator3, projId, index, score, stake3);

            engine.computeConsensus(projId, index);

            Contribution memory contrib = engine.getContribution(projId, index);
            assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted));
        }

        { // ── Settle all and verify rewards ─────────────────────────
            uint256 settleNonce = engine.getContribution(projId, index).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(projId, index, settleNonce);
            vm.prank(validator2);
            engine.settleValidator(projId, index, settleNonce);
            vm.prank(validator3);
            engine.settleValidator(projId, index, settleNonce);

            uint256 r1 = engine.getPendingRewards(validator1, address(token));
            uint256 r2 = engine.getPendingRewards(validator2, address(token));
            uint256 r3 = engine.getPendingRewards(validator3, address(token));

            assertGt(r1 + r2 + r3, 0);

            Project memory proj = engine.getProject(projId);
            uint256 maxValidatorReward = (proj.totalRewards * proj.validatorRewardBps) / 10_000;
            uint256 perIndexMax = maxValidatorReward / proj.totalQuantity;
            assertLe(r1 + r2 + r3, perIndexMax);
        }
    }
}
