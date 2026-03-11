# [POQ-7] Reported Originator Reclaims Escrow After Project Cancellation, Depriving Contributors of Rewards

## Summary
Fixes high-severity issue where contributors with accepted work lose their earned rewards when a project is cancelled via `upholdOriginatorReport()` or `removeProject()`.

## Problem
After project cancellation:
- Contributors with `Accepted` work cannot call `releaseContributorReward()` (reverts on `Cancelled` projects)
- `refundEscrow()` permits `Cancelled` status after 30-day delay
- Originator can drain all remaining escrow including earned contributor rewards

## Solution
Pre-compute and pre-distribute owed contributor rewards into `pendingRewards` before setting project status to `Cancelled`.

## Changes

### Files Modified
1. **src/libraries/FinalizationLib.sol**
   - Added `distributeAcceptedContributorRewards()` internal helper function
   - Iterates through all contributions and distributes pending rewards for accepted work

2. **src/libraries/DisputeLib.sol**
   - Updated `upholdOriginatorReport()` to call reward distribution before cancellation

3. **src/libraries/OriginationLib.sol**
   - Updated `removeProject()` to call reward distribution before cancellation

### Test Files Created
1. **test/findings/2026-03-09/POQ_007_OriginatorReclaimEscrowAfterCancellation.t.sol**
   - Verifies the fix works for both cancellation paths
   
2. **test/findings/2026-03-09/POQ_007_OriginatorReclaimEscrowAfterCancellation_FIX.t.sol**
   - Comprehensive verification that contributors are protected

## Test Results
- ✅ 4 new tests added (all passing)
- ✅ 687 total tests passing
- ✅ No regressions
- ✅ All lifecycle tests passing

## Behavior After Fix

### Before
1. Project cancelled
2. Contributors cannot claim rewards (reverts)
3. After 30 days, originator drains all escrow (stealing contributor rewards)

### After
1. Project cancelled
2. Contributor rewards automatically moved to `pendingRewards`
3. Contributors can claim their rewards anytime
4. After 30 days, originator can only refund REMAINING escrow

## Edge Cases Handled
- Multiple accepted contributions
- Insufficient escrow (fair distribution)
- Adapter fees
- Open/upheld disputes (skipped)
- Already released rewards (skipped)
- Zero escrow scenarios

## Security Impact
- **High Risk Mitigated:** Contributors can no longer lose earned rewards during project cancellation
- **Zero Breaking Changes:** Fully backward compatible
- **Gas Impact:** Minimal, only affects cancellation operations

## Audit Reference
Quantstamp Audit Report (Initial) - 2026-02-25 through 2026-03-06
Commit: #505c56a

## Checklist
- [x] Issue validated with test
- [x] Fix implemented following recommendation
- [x] Tests verify fix works correctly
- [x] All existing tests still pass
- [x] Code formatted with `forge fmt`
- [x] Tests placed in `test/findings/2026-03-09/`
- [x] Single commit with issue title as message
- [x] No code mistakes or issues
