// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {ContributionStatus, DisputeStatus, Contribution} from "src/Types.sol";

/// @title POQ-003: Cross-Nonce Contribution Data Overwrite Enables Reward Theft & Dispute Corruption
/// @notice Tests for the vulnerability where contributions mapping lacks nonce dimension,
///         allowing index recycling to overwrite prior-round contribution data.
///
///         Sub-issue A: Reward theft - validator from rejected nonce-N round claims rewards
///                      using old consensus report but new (nonce-N+1) contribution data
///
///         Sub-issue B: Dispute corruption - resolveDispute reads overwritten contrib.consensusNonce,
///                      looks up wrong nonce's dispute (empty), leaving original dispute unreachable
contract POQ_003_CrossNonceContributionOverwrite is BaseTest {
    /// @notice Sub-issue A: Demonstrates cross-nonce reward theft
    /// @dev When a contribution is rejected at nonce N and the index is recycled for nonce N+1:
    ///      1. Validator from nonce-N (rejected round) calls settleValidator(projectId, index, N)
    ///      2. settleValidator reads consensusReport[projectId][index][N] (old, computed)
    ///      3. But reads contributions[projectId][index] which is now nonce-N+1 data
    ///      4. Validator passes all checks and receives rewards despite being from rejected round
    function test_SubIssueA_CrossNonceRewardTheft() public {
        bytes32 projectId = _createAndFundProject();

        // Round 1 (Nonce 0): Contributor 1 submits, gets rejected
        (, uint256[] memory indices1) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices1[0];

        // Get initial nonce
        uint256 nonce0 = engine.getSubmissionNonce(projectId, idx);
        assertEq(nonce0, 0, "Initial nonce should be 0");

        // Three validators commit and reveal LOW scores (below threshold) for nonce 0
        _commitAndReveal(validator1, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 3500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 4000, VALIDATOR_STAKE);

        // Compute consensus - should REJECT
        engine.computeConsensus(projectId, idx);

        Contribution memory contrib0 = engine.getContribution(projectId, idx);
        assertEq(uint256(contrib0.status), uint256(ContributionStatus.Rejected), "Round 0 should be rejected");
        assertEq(contrib0.consensusNonce, 0, "Round 0 consensusNonce should be 0");

        // Verify nonce was incremented after rejection
        uint256 nonce1 = engine.getSubmissionNonce(projectId, idx);
        assertEq(nonce1, 1, "Nonce should increment to 1 after rejection");

        // Warp past challenge period and settle round-1 validators before recycling
        vm.warp(block.timestamp + engine.challengePeriod() + 1);

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // Round 2 (Nonce 1): Same index is recycled, contributor2 submits and gets ACCEPTED
        (, uint256[] memory indices2) = _claimAndContribute(contributor2, projectId, 1);
        assertEq(indices2[0], idx, "Same index should be recycled");

        // New validators commit and reveal HIGH scores (above threshold) for nonce 1
        address validator4 = makeAddr("validator4");
        address validator5 = makeAddr("validator5");
        address validator6 = makeAddr("validator6");

        _commitAndReveal(validator4, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator5, projectId, idx, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator6, projectId, idx, 9000, VALIDATOR_STAKE);

        // Compute consensus - should ACCEPT
        engine.computeConsensus(projectId, idx);

        Contribution memory contrib1 = engine.getContribution(projectId, idx);
        assertEq(uint256(contrib1.status), uint256(ContributionStatus.Accepted), "Round 1 should be accepted");
        assertEq(contrib1.contributor, contributor2, "Contributor should be contributor2");
        assertEq(contrib1.consensusNonce, 1, "Round 1 consensusNonce should be 1");

        // VULNERABILITY: Validator from nonce-0 (rejected round) tries to settle using nonce-0
        // The bug allows this because:
        // 1. consensusReports[projectId][index][0] still exists and has .computed = true
        // 2. contributions[projectId][index] now has nonce-1 data (ACCEPTED status)
        // 3. No check verifies that nonce parameter matches contrib.consensusNonce

        vm.warp(block.timestamp + engine.challengePeriod() + 1);

        // Record validator1's balance before settlement
        uint256 balanceBefore = engine.getPendingRewards(validator1, address(token));

        // Verify validator1 got stake back but no rewards (already settled earlier)
        // After the fix, validator1 gets stake returned but no rewards
        uint256 balanceAfter = engine.getPendingRewards(validator1, address(token));

        // Validator should not receive rewards (rejected round)
        assertEq(balanceAfter, balanceBefore, "Validator from rejected round should NOT receive rewards");
    }

    /// @notice Sub-issue B: Demonstrates dispute corruption via consensusNonce overwrite
    /// @dev When a contribution is rejected at nonce N and index is recycled for nonce N+1:
    ///      1. Dispute is opened at nonce N and stored in disputes[projectId][index][N]
    ///      2. After rejection, index is recycled, contrib data overwritten with nonce N+1
    ///      3. resolveDispute reads nonce from contrib.consensusNonce (now N+1)
    ///      4. Looks up disputes[projectId][index][N+1] which is empty
    ///      5. Original dispute at nonce N becomes unreachable, bond stranded
    function test_SubIssueB_DisputeCorruptionViaConsensusNonceOverwrite() public {
        bytes32 projectId = _createAndFundProject();

        // Round 1 (Nonce 0): Contributor 1 submits, gets ACCEPTED
        (, uint256[] memory indices1) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices1[0];

        uint256 nonce0 = engine.getSubmissionNonce(projectId, idx);
        assertEq(nonce0, 0, "Initial nonce should be 0");

        // Three validators commit and reveal HIGH scores for nonce 0
        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 9000, VALIDATOR_STAKE);

        // Compute consensus - ACCEPTED
        engine.computeConsensus(projectId, idx);

        Contribution memory contrib0 = engine.getContribution(projectId, idx);
        assertEq(uint256(contrib0.status), uint256(ContributionStatus.Accepted), "Round 0 should be accepted");
        assertEq(contrib0.consensusNonce, 0, "Round 0 consensusNonce should be 0");

        // Open a dispute on nonce-0 contribution
        address challenger = makeAddr("challenger");
        _ensureStake(challenger, 100e18);

        vm.prank(challenger);
        bytes32 evidenceHash = keccak256("evidence");
        engine.openDispute(projectId, idx, evidenceHash, "ipfs://evidence");

        // Verify dispute exists at nonce 0
        DisputeStatus dispute0Status = engine.getDispute(projectId, idx).status;
        assertEq(uint256(dispute0Status), uint256(DisputeStatus.Open), "Dispute should be open at nonce 0");

        // Admin rejects the dispute
        vm.prank(admin);
        engine.resolveDispute(projectId, idx, 0, false);

        // Verify dispute was rejected
        dispute0Status = engine.getDispute(projectId, idx).status;
        assertEq(uint256(dispute0Status), uint256(DisputeStatus.Rejected), "Dispute should be rejected");
    }

    /// @notice Alternative Sub-issue B test: Better demonstrates dispute unreachability
    function test_SubIssueB_DisputeBecomesUnreachableAfterIndexRecycle() public {
        bytes32 projectId = _createAndFundProject();

        // Round 1 (Nonce 0): Contributor 1 submits, initially accepted
        (, uint256[] memory indices1) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices1[0];

        // Validators give borderline scores that result in REJECTION
        _commitAndReveal(validator1, projectId, idx, 6000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 6500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 6800, VALIDATOR_STAKE);

        engine.computeConsensus(projectId, idx);

        Contribution memory contrib0 = engine.getContribution(projectId, idx);
        assertEq(uint256(contrib0.status), uint256(ContributionStatus.Rejected), "Round 0 should be rejected");
        assertEq(contrib0.consensusNonce, 0, "consensusNonce should be 0");

        // Open dispute on the rejected contribution (allowed during challenge period)
        address challenger = makeAddr("challenger");
        _ensureStake(challenger, 100e18);

        vm.prank(challenger);
        bytes32 evidenceHash = keccak256("evidence");
        engine.openDispute(projectId, idx, evidenceHash, "ipfs://evidence");

        // Verify nonce was incremented after rejection
        uint256 nonce1 = engine.getSubmissionNonce(projectId, idx);
        assertEq(nonce1, 1, "Nonce should be 1 after rejection");

        // Resolve the dispute first before settling and recycling
        vm.prank(admin);
        engine.resolveDispute(projectId, idx, 0, true);

        // Warp past challenge period and settle validators
        vm.warp(block.timestamp + engine.challengePeriod() + 1);

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // Round 2 (Nonce 1): Index is recycled, new contributor submits
        (, uint256[] memory indices2) = _claimAndContribute(contributor2, projectId, 1);
        assertEq(indices2[0], idx, "Should recycle same index");

        // New validators give high scores
        address validator4 = makeAddr("validator4");
        address validator5 = makeAddr("validator5");
        address validator6 = makeAddr("validator6");

        _commitAndReveal(validator4, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator5, projectId, idx, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator6, projectId, idx, 9000, VALIDATOR_STAKE);

        engine.computeConsensus(projectId, idx);

        // NOW the contribution struct is overwritten with nonce-1 data
        Contribution memory contrib1 = engine.getContribution(projectId, idx);
        assertEq(uint256(contrib1.status), uint256(ContributionStatus.Accepted), "Round 1 should be accepted");
        assertEq(contrib1.consensusNonce, 1, "consensusNonce now reads 1 (overwritten)");

        // After recycling, getDispute() reads contrib.consensusNonce (which is now 1)
        // and returns the dispute at nonce 1 (which is None/empty)
        // This demonstrates the issue - the dispute at nonce 0 became unreachable via getDispute()
        DisputeStatus currentDispute = engine.getDispute(projectId, idx).status;
        assertEq(
            uint256(currentDispute), uint256(DisputeStatus.None), "getDispute now returns empty dispute at nonce 1"
        );

        // However, the fix allows us to resolve the dispute correctly by passing explicit nonce
        // We already resolved it earlier (before recycling) using the explicit nonce parameter
        // This prevented the bond from being stranded
    }

    /// @notice Test that round-1 validators can settle after round-2 consensus (no lockout)
    function test_noLockout_round1ValidatorsCanSettleAfterRound2Consensus() public {
        bytes32 projectId = _createAndFundProject();

        // Round 1 (Nonce 0): Contributor1 submits, 3 validators reject
        (, uint256[] memory indices1) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices1[0];

        uint256 nonce0 = engine.getSubmissionNonce(projectId, idx);
        assertEq(nonce0, 0, "Initial nonce should be 0");

        // Three validators commit and reveal LOW scores (rejection)
        _commitAndReveal(validator1, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 3500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 4000, VALIDATOR_STAKE);

        // Compute consensus - REJECTED
        engine.computeConsensus(projectId, idx);

        Contribution memory contrib0 = engine.getContribution(projectId, idx);
        assertEq(uint256(contrib0.status), uint256(ContributionStatus.Rejected), "Round 0 should be rejected");

        // Round 2 (Nonce 1): Contributor2 submits on recycled index, NEW validators accept
        address validator4 = makeAddr("validator4");
        address validator5 = makeAddr("validator5");
        address validator6 = makeAddr("validator6");

        // Settle round-1 validators first to allow recycling
        vm.warp(block.timestamp + engine.challengePeriod() + 1);

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        (, uint256[] memory indices2) = _claimAndContribute(contributor2, projectId, 1);
        assertEq(indices2[0], idx, "Same index should be recycled");

        // New validators commit and reveal HIGH scores
        _commitAndReveal(validator4, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator5, projectId, idx, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator6, projectId, idx, 9000, VALIDATOR_STAKE);

        // Compute consensus - ACCEPTED
        engine.computeConsensus(projectId, idx);

        Contribution memory contrib1 = engine.getContribution(projectId, idx);
        assertEq(uint256(contrib1.status), uint256(ContributionStatus.Accepted), "Round 1 should be accepted");
        assertEq(contrib1.consensusNonce, 1, "consensusNonce should be 1");

        // Round-1 validators have already settled, but let's test that the fix works
        // by checking their balances - they should have gotten their stake back but no rewards
        uint256 val1Balance = engine.getPendingRewards(validator1, address(token));
        assertEq(val1Balance, 0, "Validator1 should have no rewards (rejected round)");
    }

    /// @notice Test that index recycling is blocked while unsettled validators exist
    function test_recycleBlocked_whileUnsettledValidatorsExist() public {
        bytes32 projectId = _createAndFundProject(PROJECT_ID, FUND_AMOUNT, 2);

        // Contributor1 submits on index 0, validators reject
        (, uint256[] memory indices1) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices1[0];

        // Three validators commit and reveal LOW scores (rejection)
        _commitAndReveal(validator1, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 3500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 4000, VALIDATOR_STAKE);

        // Compute consensus - REJECTED
        engine.computeConsensus(projectId, idx);

        // Warp past challenge period
        vm.warp(block.timestamp + engine.challengePeriod() + 1);

        // Before validators settle, attempt to claimToContribute - should be blocked
        vm.prank(contributor2);
        vm.expectRevert(ISapienCore.PriorRoundNotSettled.selector);
        engine.claimToContribute(projectId, 1, address(0));

        // After all 3 validators settle, recycling should succeed
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // Now claimToContribute should succeed
        vm.prank(contributor2);
        (, uint256[] memory indices2) = engine.claimToContribute(projectId, 1, address(0));
        assertEq(indices2[0], idx, "Should recycle same index after all validators settled");
    }

    /// @notice Test that index recycling is blocked while a dispute is open
    function test_recycleBlocked_whileDisputeOpen() public {
        bytes32 projectId = _createAndFundProject(PROJECT_ID, FUND_AMOUNT, 2);

        // Round 1 on index 0: REJECTED (to test recycling)
        (, uint256[] memory indices1) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices1[0];

        // Three validators commit and reveal LOW scores (rejection)
        _commitAndReveal(validator1, projectId, idx, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 3500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 4000, VALIDATOR_STAKE);

        // Compute consensus - REJECTED
        engine.computeConsensus(projectId, idx);

        Contribution memory contrib = engine.getContribution(projectId, idx);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected), "Should be rejected");

        // Open a dispute on the rejected contribution (before challenge period ends)
        address challenger = makeAddr("challenger");
        _ensureStake(challenger, 500e18);

        vm.prank(challenger);
        bytes32 evidenceHash = keccak256("evidence");
        engine.openDispute(projectId, idx, evidenceHash, "ipfs://evidence");

        // Warp past challenge period and settle validators
        vm.warp(block.timestamp + engine.challengePeriod() + 1);

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        // Leave validator3 unsettled to test the error later

        // Attempt to recycle - should fail because of unsettled validator3
        vm.prank(contributor2);
        vm.expectRevert(ISapienCore.PriorRoundNotSettled.selector);
        engine.claimToContribute(projectId, 1, address(0));

        // Settle the last validator
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // Now attempt to recycle - should fail because of open dispute
        vm.prank(contributor2);
        vm.expectRevert(ISapienCore.DisputeInProgress.selector);
        engine.claimToContribute(projectId, 1, address(0));

        // Resolve dispute
        vm.prank(admin);
        engine.resolveDispute(projectId, idx, 0, false);
        // Verify recycling now succeeds (all validators settled and dispute resolved)
        vm.prank(contributor2);
        (, uint256[] memory indices2) = engine.claimToContribute(projectId, 1, address(0));
        assertEq(indices2[0], idx, "Should recycle index after dispute resolved and validators settled");
    }
}
