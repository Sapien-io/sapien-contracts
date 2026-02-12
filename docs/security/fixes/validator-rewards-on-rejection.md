# Fix: Validator Rewards on Rejection (M-1 / H-1)

**Status:** Fixed  
**Location:** `SapienCore.sol`  
**Related findings:** Opus 4.6 M-1 (Double Validator Reward Payout), H-1 (Reward Pool Drain Through Repeated Rejections)

## Summary

Validators are now paid **only when a contribution is accepted**. When a contribution is rejected, validators receive no rewards—even though outlier slashing still applies. This prevents reward pool drain when rejected tasks are re-submitted and re-validated on the same index.

---

## Root Cause

When a contribution was rejected, validators were still paid because:

1. **`resetContributionState()` does not clear validations.** Per the F-08 gas design, the `ValidationOracle` only clears `contributionStates` and `assignments`; it does not delete the `validations[projectId][contributionIndex]` array. This saves gas but leaves validation data intact.

2. **`_distributeValidatorRewards` ran unconditionally.** On every finalization (accepted or rejected), `_processValidators` called `_distributeValidatorRewards`. Since `_fetchValidations()` still returned data after rejection, validators were paid.

3. **Rejection → resubmit doubled validator payouts.** When a contribution was rejected, the index returned to the pool. A new contributor could submit on the same index. The oracle retained validations from both rounds. Paying all validators would drain the pool: validators from the rejected round and from the accepted round would both be paid from the same reward pool, despite only one contribution being accepted.

### Economic impact

- Project tasks go back into the pool when rejected.
- If validators were paid on rejection, they would be paid again when the same slot was re-done and accepted.
- This would increase validation cost relative to the fixed pool of rewards.

---

## Fix Applied

### 1. Pay validators only on acceptance

- Pass `accepted` into `_processValidators`.
- Call `_distributeValidatorRewards` only when `accepted == true`.
- Slashing of outliers continues for both accepted and rejected contributions.

### 2. Filter validations by submission

In `_distributeValidatorRewards`, only include validations where `v.submittedAt > contributionSubmittedAt`. This ensures we pay only validators from the **current** submission, not from a prior rejected round when the same index is re-submitted.

### Code changes (SapienCore.sol)

- `_finalizeContribution`: Captures `contributionSubmittedAt` before potential deletion; passes `accepted` and `contributionSubmittedAt` to `_processValidators`.
- `_processValidators`: New parameters `accepted` and `contributionSubmittedAt`; only calls `_distributeValidatorRewards` when `accepted == true`.
- `_distributeValidatorRewards`: Filters fetched validations to those with `submittedAt > contributionSubmittedAt` before computing and distributing rewards.

---

## Verification

All reward-related tests pass:

- `Opus4_M1_ValidatorRewardOnRejection`: `test_M1_PoolNotDrainedOnRejection`, `test_M1_FullCycleRejectionThenAcceptance`, `test_M1_DocumentOrderingDependency`
- `RewardPoolDrain`: `test_H1_Investigation_ValidatorRewardsNotPaidOnRejection`, `test_H1_PoolConsistentAfterRejectionThenAcceptance`, `test_H1_ValidatorsGetNoRewardOnRejection`, `test_H1_RewardFormula_UsesStaticTotal`
- `UnrecoverableRewardsFromRejections`: `test_RejectedContributionPreservesRewards`, `test_PreservedRewardsAreReusableByNextContributor`, `test_AcceptedContributionsDistributeRewardsProperly`

---

## Invariants

- **Validator rewards** are distributed only when `accepted == true`.
- **Slashing** runs for both accepted and rejected contributions.
- **Reward pool** is unchanged on rejection; preserved contributor rewards remain available for the next submission on that index.
