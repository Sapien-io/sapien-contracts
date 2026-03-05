// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
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
    StakeAccount,
    ValidationClaim,
    ValidationClaimStatus,
    Dispute,
    DisputeStatus,
    OriginatorReport,
    OriginatorReportStatus
} from "src/Types.sol";

/// @title LivenessBase — shared helpers for liveness improvement tests
contract LivenessBase is BaseTest {
    address public challenger = makeAddr("challenger");
    address public reporter = makeAddr("reporter");
    address public keeper = makeAddr("keeper");

    function setUp() public virtual override {
        super.setUp();

        address[2] memory extras = [challenger, reporter];
        for (uint256 i; i < extras.length; ++i) {
            token.mint(extras[i], STAKE_AMOUNT * 10);
            vm.startPrank(extras[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 5, extras[i]);
            vm.stopPrank();
        }
    }

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

    function _pid(string memory seed) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("liveness-", seed));
    }

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

    function _setupProject(bytes32 projectId, uint256 fundAmount, uint256 qty) internal {
        token.mint(originator, fundAmount);
        vm.startPrank(originator);
        engine.createProject(projectId, "", _defaultConfig());
        token.approve(address(engine), fundAmount);
        engine.fundProject(projectId, fundAmount, qty, adapter);
        vm.stopPrank();
    }

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

    function _reveal(address val, bytes32 projectId, uint256 index, uint256 score) internal override {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, projectId, index, score));
        vm.prank(val);
        engine.revealValidation(projectId, index, score, salt);
    }

    function _validateAboveThreshold(bytes32 projectId, uint256 index) internal {
        _claimAndCommit(validator1, projectId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, index, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, index, 7500, VALIDATOR_STAKE);
        _reveal(validator1, projectId, index, 8000);
        _reveal(validator2, projectId, index, 8500);
        _reveal(validator3, projectId, index, 7500);
    }

    function _validateBelowThreshold(bytes32 projectId, uint256 index) internal {
        _claimAndCommit(validator1, projectId, index, 3000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, index, 2500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, index, 4000, VALIDATOR_STAKE);
        _reveal(validator1, projectId, index, 3000);
        _reveal(validator2, projectId, index, 2500);
        _reveal(validator3, projectId, index, 4000);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// 3A: Cancelled-Project Validator Recovery Tests
// ═══════════════════════════════════════════════════════════════════════

contract CancelledProjectValidatorRecoveryTest is LivenessBase {
    bytes32 internal projId;

    function setUp() public override {
        super.setUp();
        projId = _pid("cancel-recovery");
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    /// @notice Validator reveals, project gets cancelled, keeper releases stake
    function test_releaseValidatorOnCancelledProject_happyPath() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        StakeAccount memory v1Before = vault.getStakeAccount(validator1);

        vm.prank(admin);
        engine.removeProject(projId);
        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Cancelled));

        vm.prank(keeper);
        engine.releaseValidatorOnCancelledProject(projId, index, nonce, validator1);

        StakeAccount memory v1After = vault.getStakeAccount(validator1);
        assertGt(v1After.validatorCapacity, v1Before.validatorCapacity);
        assertEq(v1After.inFlight, v1Before.inFlight - VALIDATOR_STAKE);
        assertTrue(engine.isValidatorSettled(projId, index, nonce, validator1));
    }

    /// @notice Revert if project is not cancelled
    function test_revert_releaseValidatorOnActiveProject() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        vm.prank(keeper);
        vm.expectRevert(ISapienCore.ProjectNotCancelled.selector);
        engine.releaseValidatorOnCancelledProject(projId, index, nonce, validator1);
    }

    /// @notice Revert if validator already settled
    function test_revert_releaseAlreadySettled() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        vm.prank(admin);
        engine.removeProject(projId);

        vm.prank(keeper);
        engine.releaseValidatorOnCancelledProject(projId, index, nonce, validator1);

        vm.prank(keeper);
        vm.expectRevert(ISapienCore.AlreadySettled.selector);
        engine.releaseValidatorOnCancelledProject(projId, index, nonce, validator1);
    }

    /// @notice Multiple validators recovered across different contributions
    function test_multipleValidatorsRecovered() public {
        // Submit two contributions separately and validate sequentially to avoid
        // random index assignment issues with claimToValidate
        (, uint256[] memory idx0) = _claimAndSubmit(contributor1, projId, 1);
        _validateAboveThreshold(projId, idx0[0]);
        engine.computeConsensus(projId, idx0[0]);

        (, uint256[] memory idx1) = _claimAndSubmit(contributor2, projId, 1);
        _validateAboveThreshold(projId, idx1[0]);
        engine.computeConsensus(projId, idx1[0]);

        uint256 nonce0 = engine.getContribution(projId, idx0[0]).consensusNonce;
        uint256 nonce1 = engine.getContribution(projId, idx1[0]).consensusNonce;

        vm.prank(admin);
        engine.removeProject(projId);

        address[3] memory validators = [validator1, validator2, validator3];
        for (uint256 i; i < validators.length; ++i) {
            vm.prank(keeper);
            engine.releaseValidatorOnCancelledProject(projId, idx0[0], nonce0, validators[i]);

            vm.prank(keeper);
            engine.releaseValidatorOnCancelledProject(projId, idx1[0], nonce1, validators[i]);

            assertTrue(engine.isValidatorSettled(projId, idx0[0], nonce0, validators[i]));
            assertTrue(engine.isValidatorSettled(projId, idx1[0], nonce1, validators[i]));
        }
    }

    /// @notice Committed but not revealed validator can also be released on cancelled project
    function test_committedNotRevealedValidatorRecovery() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, projId, index, uint256(8000)));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));
        _ensureStake(validator1, VALIDATOR_STAKE * 2);

        vm.startPrank(validator1);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projId, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        uint256 nonce = engine.getSubmissionNonce(projId, index);

        StakeAccount memory before = vault.getStakeAccount(validator1);
        assertGt(before.inFlight, 0);

        vm.prank(admin);
        engine.removeProject(projId);

        vm.prank(keeper);
        engine.releaseValidatorOnCancelledProject(projId, index, nonce, validator1);

        StakeAccount memory after_ = vault.getStakeAccount(validator1);
        assertEq(after_.inFlight, before.inFlight - VALIDATOR_STAKE);
    }

    /// @notice Originator report upheld cancellation also allows validator recovery
    function test_originatorReportCancellationRecovery() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        _ensureStake(reporter, STAKE_AMOUNT * 2);
        vm.prank(reporter);
        engine.reportOriginator(projId, keccak256("evidence"));

        vm.prank(admin);
        engine.resolveOriginatorReport(projId, true);
        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Cancelled));

        vm.prank(keeper);
        engine.releaseValidatorOnCancelledProject(projId, index, nonce, validator1);
        assertTrue(engine.isValidatorSettled(projId, index, nonce, validator1));
    }
}

// ═══════════════════════════════════════════════════════════════════════
// 3B: Terminal Upheld-Dispute Contribution Status Tests
// ═══════════════════════════════════════════════════════════════════════

contract UpheldDisputeTerminalStatusTest is LivenessBase {
    bytes32 internal projId;
    uint256 internal index;
    uint256 internal nonce;

    function setUp() public override {
        super.setUp();
        projId = _pid("disputed-status");
        _setupProject(projId, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        index = indices[0];

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        nonce = engine.getContribution(projId, index).consensusNonce;

        assertEq(uint256(engine.getContribution(projId, index).status), uint256(ContributionStatus.Accepted));
    }

    /// @notice Upheld dispute on accepted contribution sets ContributionStatus.Disputed
    function test_upheldDisputeSetsDisputedStatus() public {
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("evidence"), "cid");

        vm.prank(admin);
        engine.resolveDispute(projId, index, true);

        Contribution memory contrib = engine.getContribution(projId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Disputed));
    }

    /// @notice releaseContributorReward reverts after upheld dispute (status is Disputed)
    function test_revert_releaseContributorRewardAfterUpheldDispute() public {
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("evidence"), "cid");

        vm.prank(admin);
        engine.resolveDispute(projId, index, true);

        _warpPastChallengePeriod();

        vm.expectRevert(ISapienCore.ContributionNotAccepted.selector);
        engine.releaseContributorReward(projId, index);
    }

    /// @notice completeProject works after upheld dispute (pendingContributions was decremented)
    function test_completeProjectAfterUpheldDispute() public {
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("evidence"), "cid");

        vm.prank(admin);
        engine.resolveDispute(projId, index, true);

        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(projId, index, nonce);

        vm.prank(originator);
        engine.completeProject(projId);
        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Completed));
    }

    /// @notice Validators settling after upheld dispute get stake back but no reward
    function test_validatorSettlementAfterUpheldDispute_noReward() public {
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("evidence"), "cid");

        vm.prank(admin);
        engine.resolveDispute(projId, index, true);

        uint256 escrowBefore = engine.getProjectEscrow(projId, address(token));
        uint256 v1RewardsBefore = engine.getPendingRewards(validator1, address(token));

        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);

        uint256 escrowAfter = engine.getProjectEscrow(projId, address(token));
        uint256 v1RewardsAfter = engine.getPendingRewards(validator1, address(token));

        assertEq(escrowAfter, escrowBefore, "No escrow should be consumed for disputed contribution");
        assertEq(v1RewardsAfter, v1RewardsBefore, "No reward should accrue for disputed contribution");
        assertTrue(engine.isValidatorSettled(projId, index, nonce, validator1));
    }

    /// @notice Rejected dispute does NOT set Disputed status (stays Accepted)
    function test_rejectedDisputeKeepsAcceptedStatus() public {
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("evidence"), "cid");

        vm.prank(admin);
        engine.resolveDispute(projId, index, false);

        Contribution memory contrib = engine.getContribution(projId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted));
    }

    /// @notice Escalated dispute (auto-upheld) also sets Disputed status
    function test_escalatedDisputeSetsDisputedStatus() public {
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("evidence"), "cid");

        vm.warp(block.timestamp + 7 days + 1);

        engine.escalateDispute(projId, index);

        Contribution memory contrib = engine.getContribution(projId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Disputed));
    }
}

// ═══════════════════════════════════════════════════════════════════════
// 3C: Integration Scenario Tests
// ═══════════════════════════════════════════════════════════════════════

contract LivenessIntegrationTest is LivenessBase {
    /// @notice Full lifecycle: contributions accepted, dispute upheld, project completed, escrow refunded
    function test_fullLifecycle_disputeUpheld_thenCompleted() public {
        bytes32 projId = _pid("integration-dispute");
        _setupProject(projId, FUND_AMOUNT, 2);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 2);
        uint256 idx0 = indices[0];
        uint256 idx1 = indices[1];

        // Validate both above threshold
        _validateAboveThreshold(projId, idx0);
        _validateAboveThreshold(projId, idx1);
        engine.computeConsensus(projId, idx0);
        engine.computeConsensus(projId, idx1);

        uint256 nonce0 = engine.getContribution(projId, idx0).consensusNonce;
        uint256 nonce1 = engine.getContribution(projId, idx1).consensusNonce;

        // Dispute idx0 — upheld
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, idx0, keccak256("bad-work"), "cid");
        vm.prank(admin);
        engine.resolveDispute(projId, idx0, true);

        assertEq(uint256(engine.getContribution(projId, idx0).status), uint256(ContributionStatus.Disputed));

        // Settle all validators on both contributions
        address[3] memory validators = [validator1, validator2, validator3];

        // idx0: disputed — validators get stake back, no reward
        for (uint256 i; i < 3; ++i) {
            vm.prank(validators[i]);
            engine.settleValidator(projId, idx0, nonce0);
        }

        // idx1: accepted — warp past challenge, settle with reward
        _warpPastChallengePeriod();
        for (uint256 i; i < 3; ++i) {
            vm.prank(validators[i]);
            engine.settleValidator(projId, idx1, nonce1);
        }

        // Release contributor reward only for idx1 (idx0 is disputed)
        engine.releaseContributorReward(projId, idx1);

        // Complete project
        vm.prank(originator);
        engine.completeProject(projId);
        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Completed));

        // Refund escrow after grace period
        vm.warp(block.timestamp + 31 days);
        uint256 escrowRemaining = engine.getProjectEscrow(projId, address(token));
        if (escrowRemaining > 0) {
            vm.prank(originator);
            engine.refundEscrow(projId);
            assertEq(engine.getProjectEscrow(projId, address(token)), 0);
        }
    }

    /// @notice Full lifecycle: validators in-flight, project cancelled, validators recovered, escrow refunded
    function test_fullLifecycle_cancelledProject_validatorRecovery() public {
        bytes32 projId = _pid("integration-cancel");
        _setupProject(projId, FUND_AMOUNT, 2);

        // Submit and validate sequentially to avoid random assignment issues
        (, uint256[] memory idx0) = _claimAndSubmit(contributor1, projId, 1);
        _validateAboveThreshold(projId, idx0[0]);
        engine.computeConsensus(projId, idx0[0]);

        (, uint256[] memory idx1) = _claimAndSubmit(contributor2, projId, 1);
        _validateAboveThreshold(projId, idx1[0]);
        engine.computeConsensus(projId, idx1[0]);

        uint256 nonce0 = engine.getContribution(projId, idx0[0]).consensusNonce;
        uint256 nonce1 = engine.getContribution(projId, idx1[0]).consensusNonce;

        // Record in-flight stakes before cancellation
        StakeAccount memory v1Before = vault.getStakeAccount(validator1);
        assertGt(v1Before.inFlight, 0, "Validator should have in-flight stake");

        // Cancel project
        vm.prank(admin);
        engine.removeProject(projId);
        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Cancelled));

        // Normal settlement should revert
        vm.prank(validator1);
        vm.expectRevert(ISapienCore.ProjectNotActive.selector);
        engine.settleValidator(projId, idx0[0], nonce0);

        // Recover all validators via keeper
        address[3] memory validators = [validator1, validator2, validator3];
        for (uint256 i; i < 3; ++i) {
            vm.startPrank(keeper);
            engine.releaseValidatorOnCancelledProject(projId, idx0[0], nonce0, validators[i]);
            engine.releaseValidatorOnCancelledProject(projId, idx1[0], nonce1, validators[i]);
            vm.stopPrank();
        }

        // Verify in-flight stake is fully released
        StakeAccount memory v1After = vault.getStakeAccount(validator1);
        assertEq(v1After.inFlight, 0, "All in-flight stake should be released");

        // Refund escrow after grace period
        vm.warp(block.timestamp + 31 days);
        uint256 escrowRemaining = engine.getProjectEscrow(projId, address(token));
        if (escrowRemaining > 0) {
            vm.prank(originator);
            engine.refundEscrow(projId);
            assertEq(engine.getProjectEscrow(projId, address(token)), 0);
        }
    }

    /// @notice Upheld originator report cancels project, validators recover, escrow refunded
    function test_fullLifecycle_originatorReport_validatorRecovery_escrowRefund() public {
        bytes32 projId = _pid("integration-report");
        _setupProject(projId, FUND_AMOUNT, 1);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        uint256 nonce = engine.getContribution(projId, index).consensusNonce;

        // Report originator
        _ensureStake(reporter, STAKE_AMOUNT * 2);
        vm.prank(reporter);
        engine.reportOriginator(projId, keccak256("misconduct"));

        vm.prank(admin);
        engine.resolveOriginatorReport(projId, true);

        // Recover validators
        address[3] memory validators = [validator1, validator2, validator3];
        for (uint256 i; i < 3; ++i) {
            vm.prank(keeper);
            engine.releaseValidatorOnCancelledProject(projId, index, nonce, validators[i]);
        }

        // Refund remaining escrow after delay
        vm.warp(block.timestamp + 31 days);
        uint256 escrowRemaining = engine.getProjectEscrow(projId, address(token));
        if (escrowRemaining > 0) {
            vm.prank(originator);
            engine.refundEscrow(projId);
        }
    }
}
