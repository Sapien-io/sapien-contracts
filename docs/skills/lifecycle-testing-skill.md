# Lifecycle Testing Skill

This skill guides the creation of comprehensive test suites for the Sapien V2 protocol lifecycle. It focuses on **State-Transition Verification** to ensure fixes, optimizations, and improvements are correctly implemented across all phases.

## Purpose

To systematically verify that every function call in the protocol lifecycle:
1.  Transitions the system from a valid Pre-State to a valid Post-State.
2.  Emits correct events for indexing.
3.  Handles edge cases and reverts on invalid inputs.
4.  Maintains protocol invariants (solvency, fairness).

**Target**: `test/lifecycle/` directory.

---

## 🏗️ Testing Strategy: State-Transition Verification

For every step in the lifecycle, tests must verify three components:
1.  **Pre-State**: Assert initial balances, pointers, and configurations.
2.  **Action**: Execute the function (via `vm.prank`).
3.  **Post-State**: Assert final balances, pointers, struct updates, and events.

---

## 🔄 Phase-by-Phase Testing Guide

### Phase 1: Project Setup
**Goal**: Ensure configuration is sanitized and funds/fees are handled correctly.

-   **Functions**: `createProject`, `fundProject`.
-   **State Assertions**:
    -   `projects[id]` struct populated (check all config fields).
    -   `rewards` contract balance += `amount - fee`.
    -   `treasury` balance += `fee`.
    -   Originator has `ORIGINATOR_ROLE` in Trust contract.
-   **Events**: `ProjectCreated`, `ProjectFunded`, `ProtocolFeeCollected`.
-   **Edge Cases**:
    -   Fee Math: Test with 1 wei, prime numbers, checking for rounding to zero.
    -   Config Limits: Max validations > 100, zero deadlines.

### Phase 2: Contribution
**Goal**: Verify reservation logic and "Skin in the Game" locking.

-   **Functions**: `claimToContribute`, `contribute`, `releaseExpiredClaim`, `reclaimExpiredIndices`.
-   **State Assertions**:
    -   **Queue**: `indexReservations` maps index $\to$ user.
    -   **Vault**: `vault.getLockedStake` increases by `minStakeToClaim`.
    -   **Inventory**: `activeClaimedQuantity` updates correctly.
-   **Events**: `ClaimCreated`, `IndexAssigned`, `ContributionSubmitted`.
-   **Edge Cases**:
    -   **Index Reuse**: Verify `reclaimExpiredIndices` actually makes indices available for the next `claimToContribute`.
    -   **Double Submit**: Prevent submitting same index twice.

### Phase 3: Validation (Commit-Reveal)
**Goal**: Prevent gaming of the consensus mechanism.

-   **Functions**: `setValidatorCapacity`, `claimToValidate`, `commitValidation`, `revealValidation`.
-   **State Assertions**:
    -   **Capacity**: `inFlightStake` $\le$ `capacity`.
    -   **Queue**: `pendingQueue` head/tail pointers advance.
    -   **Commit**: Hash stored in `validationCommits`.
    -   **Reveal**: `validations` array populated, `inFlightStake` decrements.
-   **Events**: `ValidationClaimed`, `ValidationCommitted`, `ValidationRevealed`.
-   **Edge Cases**:
    -   **Ghost Validators**: Test `cancelExpiredCommitment` (slashing + queue unblocking).
    -   **Stake Mismatch**: Commit with low stake, reveal with high stake (ensure committed amount is used).

### Phase 4: Finalization & Rewards
**Goal**: Accuracy of consensus and fairness of distribution.

-   **Functions**: `finalizeContribution`.
-   **State Assertions**:
    -   **Consensus**: Manually calculate weighted average vs on-chain result.
    -   **Reputation**: Trust scores update up/down.
    -   **Rewards**: Balances transfer correctly.
    -   **Vault**: Honest stakes unlocked, outliers slashed.
-   **Events**: `ContributionFinalized`, `ReputationUpdated`, `RewardsDistributed`.
-   **Edge Cases**:
    -   **Re-queuing**: Rejected contributions must be cleared (`resetContributionState`) for new contributors.
    -   **Dust**: Check for rounding dust in Rewards contract.

---

## 🧪 Recommended Test Architecture

Structure your tests in `test/lifecycle/` using these patterns:

### 1. Happy Path (`EndToEnd.t.sol`)
A single file running the flow A-to-Z to verify integration.
```solidity
function test_EndToEnd_Lifecycle() public {
    // 1. Setup (Originator)
    // 2. Contribute (Contributor)
    // 3. Validate (Validator)
    // 4. Finalize (Keeper/Any)
    // 5. Assert Final Balances & Reputation
}
```

### 2. Edge Case Suite (`Adversarial.t.sol`)
Specific tests for the "Edge Cases & Timeouts" section of the architecture docs.
-   `test_ReclaimExpiredIndices_Loop`
-   `test_GhostValidator_Slashing`
-   `test_FrontRun_Claim`

### 3. Invariant Fuzzing (`Invariants.t.sol`)
Properties that must hold true after *any* sequence of actions.
-   `vault.totalAssets() >= sum(user_locks)`
-   `project.totalRewardsAvailable >= sum(unclaimed_allocations)`

---

## 🛠️ Optimization & Debugging

-   **Gas Reports**: Run `forge test --gas-report` to identify expensive loops (e.g., in `finalizeContribution`).
-   **Coverage**: Run `forge coverage` to ensure consensus branching logic in `ValidationOracle` is fully tested.
