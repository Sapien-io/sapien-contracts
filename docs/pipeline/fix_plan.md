forge t# Fix Plan

This plan outlines the recommended order of fixes based on severity and operational impact.

## Phase 1: Release Blockers (Immediate)

### 1. [F-01] Storage Collision in SapienCore
- **Priority:** Critical
- **Effort:** Low
- **Fix:** Move `userActiveClaimedQuantity` to the end of the state variable list in `SapienCore.sol`, before `__gap`. Decrement `__gap` by 1.

### 2. [F-02] Oracle Trust Assumption
- **Priority:** High
- **Effort:** High
- **Fix:** Implement a challenge period in `SapienCore` after consensus is reached but before rewards are distributed.

### 3. [F-03] Missing Role Grant Logic
- **Priority:** Medium (Deployment Blocker)
- **Effort:** Low
- **Fix:** Update `initialize` functions in `SapienCore` or `ValidationOracle` to grant `UPDATER_ROLE` on `SapienTrust` to the necessary addresses.

## Phase 2: High Priority Logic & Economics

### 4. [F-06] Inflation Attack Risk in SapienVault
- **Priority:** Medium
- **Effort:** Low
- **Fix:** Mint a small amount of "dead" shares to `address(0)` during `SapienVault` initialization.

### 5. [F-07] Validator Reward Rounding to Zero
- **Priority:** Medium
- **Effort:** Medium
- **Fix:** Implement a minimum reward amount or increase precision for reward calculations in `SapienCore`.

### 6. [F-05] Queue Pollution in ValidationOracle
- **Priority:** Medium
- **Effort:** Medium
- **Fix:** Add a `submissionNonce` to contributions and ensure validators can only claim/commit to the latest nonce.

### 7. [F-04] Storage Gap Inconsistency in ValidationOracle
- **Priority:** Medium
- **Effort:** Low
- **Fix:** Standardize the total slot count to 50 and adjust `__gap` based on the number of used slots.

## Phase 3: Performance & Griefing Mitigations

### 8. [F-08] Inefficient Storage Deletion
- **Priority:** Medium
- **Effort:** Medium
- **Fix:** Replace `delete` of arrays with a mapping-based tracking system or use nonces to invalidate old submissions.

### 9. [F-09] Liveness Griefing via Reveal Delay
- **Priority:** Medium
- **Effort:** Medium
- **Fix:** Implement a mechanism to proceed with consensus if a threshold of reveals is met, even if some commits are pending.

### 10. [F-10] Validator Queue Monopoly
- **Priority:** Medium
- **Effort:** Medium
- **Fix:** Introduce a per-validator claim limit per contribution or project.

### 11. [F-11] Reward Rate Manipulation (Sandwiching)
- **Priority:** Medium
- **Effort:** Medium
- **Fix:** Snapshot the reward rate at the time of submission or implement a delay between funding and finalization.

## Phase 4: Optimizations & Best Practices

### 12. [F-12] Unbounded Loops in SapienCore
- **Priority:** Low
- **Effort:** Low
- **Fix:** Add `require(input.length <= MAX_BATCH_SIZE)` to all batch processing functions.

### 13. [F-14] Emergency Withdrawal Risk
- **Priority:** Low
- **Effort:** Low
- **Fix:** Ensure `totalAllocated` is updated in all functions that increase user-claimable balances.

### 14. [F-16] Redundant Reward Logic
- **Priority:** Low
- **Effort:** Trivial
- **Fix:** Cache the result of `_calculateContributorReward` in `_finalizeContribution`.

### 15. [F-17] Packing Opportunities
- **Priority:** Low
- **Effort:** Medium
- **Fix:** Refactor `ISharedTypes.sol` to use smaller `uint` types for tightly packed storage.

### 16. [F-13] Unreclaimable Reward Dust
- **Priority:** Low
- **Effort:** Low
- **Fix:** Add an administrative function to withdraw trapped "dust" from the `Rewards` contract.

### 17. [F-20] Anti-dilution Behavior Change
- **Priority:** Low
- **Effort:** Trivial
- **Fix:** Update documentation and frontend tooltips to reflect the new anti-dilution logic.
