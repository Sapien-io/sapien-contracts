# POQ-7 Fix Summary: Originator Reclaims Escrow After Project Cancellation

## Issue Summary
**Severity:** High

After project cancellation via `upholdOriginatorReport()` or `removeProject()`, contributors with `Accepted` work could not call `releaseContributorReward()` (reverts on `Cancelled` projects). However, `refundEscrow()` explicitly permits `Cancelled` status. After 30 days, the punished originator could drain all remaining escrow including earned contributor rewards.

## Files Modified
1. `src/libraries/FinalizationLib.sol` - Added `distributeAcceptedContributorRewards()` helper
2. `src/libraries/DisputeLib.sol` - Updated `upholdOriginatorReport()` to pre-distribute rewards
3. `src/libraries/OriginationLib.sol` - Updated `removeProject()` to pre-distribute rewards

## Solution Implemented
Pre-compute and pre-distribute owed contributor rewards into `pendingRewards` as part of the cancellation flow, before setting project status to `Cancelled`.

### Key Changes:

#### 1. New Helper Function (`FinalizationLib.distributeAcceptedContributorRewards`)
```solidity
function distributeAcceptedContributorRewards(bytes32 projectId) internal {
    // Iterates through all contributions
    // For each Accepted contribution that hasn't been released:
    //   - Marks as rewardReleased
    //   - Calculates contributor share
    //   - Transfers from projectEscrow to pendingRewards
    //   - Handles adapter fees
    //   - Decrements pendingContributions
}
```

#### 2. Updated Cancellation Flows
Both `upholdOriginatorReport()` and `removeProject()` now call `distributeAcceptedContributorRewards(projectId)` before setting project status to `Cancelled`.

## Test Coverage
Created comprehensive test suite in `test/findings/2026-03-09/`:
- `POQ_007_OriginatorReclaimEscrowAfterCancellation.t.sol` - Shows vulnerability is fixed
- `POQ_007_OriginatorReclaimEscrowAfterCancellation_FIX.t.sol` - Verifies correct behavior

### Test Results
- All 4 new tests pass
- All 687 existing tests continue to pass
- No regressions detected

## Behavior After Fix

### Before Fix:
1. Project cancelled → Contributors' `Accepted` work locked
2. `releaseContributorReward()` reverts (project is `Cancelled`)
3. After 30 days → Originator calls `refundEscrow()` and steals contributor rewards

### After Fix:
1. Project cancelled → Contributors' rewards automatically distributed to `pendingRewards`
2. Contributors can call `claimReward()` anytime to withdraw their tokens
3. After 30 days → Originator can only refund REMAINING escrow (not contributor portions)

## Edge Cases Handled
- Multiple accepted contributions are all processed
- Handles cases where escrow is insufficient (fair distribution)
- Respects adapter fees
- Skips contributions with open or upheld disputes
- Skips contributions already released
- Safely handles zero escrow scenarios
