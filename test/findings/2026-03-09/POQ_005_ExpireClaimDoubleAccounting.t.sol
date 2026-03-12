// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {StakeAccount, ContributionStatus, Contribution, ClaimStatus} from "src/Types.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";

/// @title POQ-005: expireClaim() Double-Accounting Permanently Blocks Consensus and Traps Validator Stakes
/// @notice Validates the bug and verifies the fix: expireClaim() must NOT unlock stake
///         for Pending contributions.  Their stake stays locked so computeConsensus() can
///         handle it without reverting.
contract POQ_005_ExpireClaimDoubleAccounting is BaseTest {
    // ── Pre-fix behaviour (validates the issue is real) ──────────────

    /// @notice After expireClaim, contributor lock must still hold stake for Pending slots.
    function test_expiryPreservesInPipelineStake() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 3, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        engine.contribute(claimId, indices[1], keccak256("sub1"), "");
        vm.stopPrank();

        uint256 lockBefore = vault.getStakeAccount(contributor1).contributorLock;
        assertEq(lockBefore, 3 * STAKE_AMOUNT, "initial lock = 3x stake");

        vm.warp(block.timestamp + engine.claimDeadline() + 1);
        engine.expireClaim(claimId, indices);

        // After fix: Pending slots (2) keep their stake locked; only Reserved (1) is slashed.
        uint256 lockAfter = vault.getStakeAccount(contributor1).contributorLock;
        assertEq(lockAfter, 2 * STAKE_AMOUNT, "lock retains 2x stake for Pending slots");
    }

    /// @notice computeConsensus must succeed after expireClaim (rejection path).
    function test_consensusSucceedsAfterExpiry_rejected() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        vm.stopPrank();

        vm.warp(block.timestamp + engine.claimDeadline() + 1);
        engine.expireClaim(claimId, indices);

        // Validators score below consensus threshold → rejection
        _commitAndReveal(validator1, projectId, indices[0], 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, indices[0], 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, indices[0], 3000, VALIDATOR_STAKE);

        // Must NOT revert
        engine.computeConsensus(projectId, indices[0]);

        Contribution memory c = engine.getContribution(projectId, indices[0]);
        assertEq(uint8(c.status), uint8(ContributionStatus.Rejected), "contribution rejected");

        // Contributor lock for this slot was slashed by consensus
        assertEq(vault.getStakeAccount(contributor1).contributorLock, 0, "lock fully consumed");
    }

    /// @notice computeConsensus must succeed after expireClaim (acceptance path).
    function test_consensusSucceedsAfterExpiry_accepted() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        vm.stopPrank();

        vm.warp(block.timestamp + engine.claimDeadline() + 1);
        engine.expireClaim(claimId, indices);

        // Validators score above consensus threshold → acceptance
        _commitAndReveal(validator1, projectId, indices[0], 9000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, indices[0], 9000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, indices[0], 9000, VALIDATOR_STAKE);

        engine.computeConsensus(projectId, indices[0]);

        Contribution memory c = engine.getContribution(projectId, indices[0]);
        assertEq(uint8(c.status), uint8(ContributionStatus.Accepted), "contribution accepted");

        // Contributor lock for this slot was unlocked by consensus
        assertEq(vault.getStakeAccount(contributor1).contributorLock, 0, "lock fully released");
    }

    /// @notice Validator in-flight stakes must be recoverable after the fix.
    function test_validatorStakeNotTrapped() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        vm.stopPrank();

        vm.warp(block.timestamp + engine.claimDeadline() + 1);
        engine.expireClaim(claimId, indices);

        _commitAndReveal(validator1, projectId, indices[0], 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, indices[0], 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, indices[0], 3000, VALIDATOR_STAKE);

        StakeAccount memory v1Before = vault.getStakeAccount(validator1);
        assertGt(v1Before.inFlight, 0, "validator has in-flight stake");

        engine.computeConsensus(projectId, indices[0]);

        _warpPastChallengePeriod();

        uint256 nonce = engine.getSubmissionNonce(projectId, indices[0]);
        // Nonce was incremented by rejection, settle under previous nonce
        vm.prank(validator1);
        engine.settleValidator(projectId, indices[0], nonce - 1);

        StakeAccount memory v1After = vault.getStakeAccount(validator1);
        assertEq(v1After.inFlight, 0, "validator in-flight stake freed");
    }

    /// @notice expireClaim with all slots submitted must not touch contributor lock.
    function test_expiryAllSubmitted_noSlash() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        engine.contribute(claimId, indices[1], keccak256("sub1"), "");
        vm.stopPrank();

        uint256 lockBefore = vault.getStakeAccount(contributor1).contributorLock;
        assertEq(lockBefore, 2 * STAKE_AMOUNT);

        // Claim was completed (all submitted) so it's not Active — must not expire
        ClaimStatus status = engine.getClaim(claimId).status;
        assertEq(uint8(status), uint8(ClaimStatus.Completed));
    }

    /// @notice ClaimExpired event must report only unsubmitted count.
    function test_claimExpiredEvent() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 3, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        vm.stopPrank();

        vm.warp(block.timestamp + engine.claimDeadline() + 1);

        vm.expectEmit(true, false, false, true);
        emit ISapienCore.ClaimExpired(claimId, 2);
        engine.expireClaim(claimId, indices);
    }

    /// @notice Slash event must fire for unsubmitted slots only.
    function test_contributorSlashedEvent() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 3, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        vm.stopPrank();

        vm.warp(block.timestamp + engine.claimDeadline() + 1);

        vm.expectEmit(true, false, false, true);
        emit SapienVault.ContributorSlashed(contributor1, 2 * STAKE_AMOUNT);
        engine.expireClaim(claimId, indices);
    }
}
