// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {DisputeStatus, ContributionStatus} from "src/Types.sol";

/// @title POQ-013: Upheld Dispute Does Not Restore Slot Lifecycle or Pay Challenger Consistently
/// @notice Tests for Medium severity finding from Quantstamp Audit (2026-02-25 through 2026-03-06)
/// @dev This test verifies two sub-issues:
///      Sub-issue A: upholdDispute() on Accepted contribution doesn't restore slot lifecycle
///      Sub-issue B: For Rejected contributions, challenger reward payment can be silently skipped
contract POQ_013_UpheldDisputeSlotLifecycleAndPayment is BaseTest {
    /// @notice Sub-issue A: Upheld dispute on Accepted contribution does not restore slot lifecycle
    /// @dev When a dispute is upheld on an Accepted contribution:
    ///      - pendingContributions is decremented (correct)
    ///      - But status is NOT changed to terminal state
    ///      - availableSlots is NOT incremented
    ///      - returnStack is NOT updated
    ///      - submissionNonce is NOT incremented
    ///      Result: Slot is permanently consumed and cannot be reused
    function test_POQ013A_UpheldDisputeOnAcceptedDoesNotRestoreSlot() public {
        bytes32 projectId = _createAndFundProject();

        // Get state before any claims
        uint256 totalSlots = engine.getProject(projectId).totalQuantity;

        // Claim and contribute
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        // Get state after claim but before dispute
        uint256 returnStackTopBefore = engine.getReturnStackTop(projectId);
        uint256 submissionNonceBefore = engine.getSubmissionNonce(projectId, idx);

        // Validate and accept contribution
        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // Verify contribution was accepted
        assertEq(
            uint256(engine.getContribution(projectId, idx).status),
            uint256(ContributionStatus.Accepted),
            "contribution should be accepted"
        );

        // Open and uphold dispute
        vm.prank(contributor2);
        engine.openDispute(projectId, idx, keccak256("evidence"), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(projectId, idx, 0, true);

        // Verify dispute was upheld
        assertEq(
            uint256(engine.getDispute(projectId, idx).status), uint256(DisputeStatus.Upheld), "dispute should be upheld"
        );

        // Get state after dispute resolution
        uint256 availableSlotsAfter = engine.getProject(projectId).availableSlots;
        uint256 returnStackTopAfter = engine.getReturnStackTop(projectId);
        uint256 submissionNonceAfter = engine.getSubmissionNonce(projectId, idx);

        // AFTER FIX: availableSlots should be restored to full capacity
        assertEq(availableSlotsAfter, totalSlots, "availableSlots should be restored to total capacity");

        // AFTER FIX: returnStack should be updated with the returned index
        assertEq(returnStackTopAfter, returnStackTopBefore + 1, "returnStack should have index pushed");

        // AFTER FIX: submissionNonce should be incremented
        assertEq(submissionNonceAfter, submissionNonceBefore + 1, "submissionNonce should be incremented");
    }

    /// @notice Sub-issue B: Challenger reward ordering issue for Rejected contributions
    /// @dev When a dispute is upheld on a Rejected contribution:
    ///      - Contributor compensation is paid first (lines 97-101)
    ///      - Challenger reward is paid second (lines 104-107)
    ///      - If escrow is insufficient after compensation, challenger gets nothing
    ///      - This ordering is problematic - should either check atomically or use pro-rata
    function test_POQ013B_UpheldDisputeOnRejectedPaymentOrdering() public {
        bytes32 projectId = _createAndFundProject();

        // Claim and contribute
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        // Validate and reject contribution (low scores)
        _commitAndReveal(validator1, projectId, idx, 2000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 2000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 2000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // Verify contribution was rejected
        assertEq(
            uint256(engine.getContribution(projectId, idx).status),
            uint256(ContributionStatus.Rejected),
            "contribution should be rejected"
        );

        // Open and uphold dispute
        vm.prank(contributor2);
        engine.openDispute(projectId, idx, keccak256("evidence"), "evidenceCid");

        address rewardToken = engine.getProject(projectId).rewardToken;
        uint256 challengerBalanceBefore = engine.getPendingRewards(contributor2, rewardToken);
        uint256 contributorBalanceBefore = engine.getPendingRewards(contributor1, rewardToken);

        vm.prank(admin);
        engine.resolveDispute(projectId, idx, 0, true);

        uint256 challengerBalanceAfter = engine.getPendingRewards(contributor2, rewardToken);
        uint256 contributorBalanceAfter = engine.getPendingRewards(contributor1, rewardToken);

        // Both parties should be paid when escrow is sufficient
        assertGt(contributorBalanceAfter - contributorBalanceBefore, 0, "contributor got compensation");
        assertGt(challengerBalanceAfter - challengerBalanceBefore, 0, "challenger got reward");

        // This test documents the current behavior
        // The issue is that in low-escrow scenarios, the ordering matters
        // and challenger could be silently skipped
    }

    /// @notice Demonstrates that consumed slot prevents new contributions
    /// @dev After an upheld dispute on Accepted contribution, the slot is permanently lost
    function test_POQ013A_ConsumedSlotPreventsNewContributions() public {
        bytes32 projectId = _createAndFundProject();

        // Claim and contribute first time
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        // Validate and accept
        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        engine.computeConsensus(projectId, idx);

        // Uphold dispute
        vm.prank(contributor2);
        engine.openDispute(projectId, idx, keccak256("evidence"), "evidenceCid");
        vm.prank(admin);
        engine.resolveDispute(projectId, idx, 0, true);

        // Try to claim same slot again - should work after fix, but won't work before fix
        // because the slot is not returned to the pool
        uint256 availableSlots = engine.getProject(projectId).availableSlots;

        // AFTER FIX: availableSlots should be restored, allowing slot reuse
        assertEq(availableSlots, QUANTITY, "slot should be restored");
    }
}
