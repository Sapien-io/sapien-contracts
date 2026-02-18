# Lifecycle Testing Skill

This skill guides the creation of comprehensive test suites for the Sapien PoQ v0.5 protocol lifecycle. It focuses on **State-Transition Verification** to ensure fixes, optimizations, and improvements are correctly implemented across all phases.

## Purpose

To systematically verify that every function call in the protocol lifecycle:
1. Transitions the system from a valid Pre-State to a valid Post-State.
2. Emits correct events for indexing.
3. Handles edge cases and reverts on invalid inputs.
4. Maintains protocol invariants (solvency, fairness).

**Target**: `test/lifecycle/` directory.

**Architecture Reference**: `docs/v0.5-contracs.md` — Sapien PoQ v0.5 uses two contracts (`QualityEngine`, `StakeVault`) and one library (`ConsensusLib`).

---

## Contract Topology (v0.5)

```
QualityEngine (single contract)
├── Project management
├── Claim & index management
├── Contribution tracking
├── Validation state machine (commit-reveal)
├── Consensus computation (via ConsensusLib)
├── Reputation (inline)
├── Reward escrow & distribution (inline)
├── Disputes & originator accountability
└── calls ──→ StakeVault (external, stake operations only)

StakeVault (ERC-4626)
├── Deposits / withdrawals
├── Contributor locks (contributorLock)
├── Validator capacity (validatorCapacity)
├── In-flight stake (inFlight)
└── Slashing (share burn)
```

---

## Testing Strategy: State-Transition Verification

For every step in the lifecycle, tests must verify three components:
1. **Pre-State**: Assert initial balances, structs, configurations.
2. **Action**: Execute the function (via `vm.prank`).
3. **Post-State**: Assert final balances, struct updates, and events.

---

## Phase-by-Phase Testing Guide

### Phase 1: Project Setup

**Goal**: Ensure configuration is sanitized and funds/fees are handled correctly.

- **Functions**: `createProject`, `fundProject`.
- **State Assertions**:
  - `engine.getProject(id)` struct populated (all config fields).
  - `engine.getProjectEscrow(projectId, token)` += `amount - protocolFee - originationFee`.
  - `token.balanceOf(treasury)` += protocol fee.
  - `engine.getPendingRewards(adapter, token)` += origination fee (if adapter set).
  - Originator reputation updated via `engine.getReputation(originator, ORIGINATOR_ROLE_KEY)`.
- **Events**: `ProjectCreated`, `ProjectFunded`, `OriginationFeePaid`.
- **Edge Cases**:
  - Fee math: 1 wei, prime numbers, rounding to zero.
  - Config limits: zero numberOfValidations, invalid validatorRewardBps.
  - Originator stake requirement: `originatorLockedStake` when enabled.

### Phase 2: Claim & Contribute

**Goal**: Verify index reservation, stake locking, and contribution submission.

- **Functions**: `claimToContribute`, `contribute`, `expireClaim`.
- **State Assertions**:
  - **Vault**: `vault.getStakeAccount(user).contributorLock` increases by `minStakeToClaim * quantity`.
  - **Index stack**: `availableIndexTop` decreases; indices popped from `availableIndexStack`.
  - **Claim**: `engine.getClaim(claimId)` has `indices[]`, `deadline`, `status`.
  - **Index states**: `engine.getIndexState(projectId, index)` shows `Reserved` then `Submitted`.
  - **Expiry**: `expireClaim` returns unsubmitted indices to stack atomically; contributor slashed.
- **Events**: `ClaimCreated`, `ContributionSubmitted`, `ClaimExpired`.
- **Edge Cases**:
  - Index reuse: After `expireClaim`, indices must be claimable by the next contributor.
  - Double submit: Prevent submitting same index twice.
  - Partial expiry: Submitted indices stay in pipeline; unsubmitted returned.
  - Originator cannot contribute; contributor cannot validate own work.

### Phase 3: Validation (Commit-Reveal)

**Goal**: Prevent gaming of the consensus mechanism.

- **Functions**: `setValidatorCapacity`, `commitValidation`, `revealValidation`, `cancelExpiredCommitment`.
- **State Assertions**:
  - **Capacity**: `vault.getStakeAccount(user).validatorCapacity` locked.
  - **Commit**: `validatorCapacity` → `inFlight` via `commitStake`; `commitHashes` stored.
  - **Reveal**: `reveals` populated; stake stays in-flight until settlement.
  - **Ghost**: `cancelExpiredCommitment` slashes committed-but-unrevealed validators.
- **Events**: `ValidationCommitted`, `ValidationRevealed`.
- **Edge Cases**:
  - Ghost validators: `cancelExpiredCommitment` slashing and queue unblocking.
  - Commit hash: `keccak256(abi.encodePacked(score, salt))` — stake amount not in hash (committed amount tracked separately in `committedStakes`).
  - Reputation gate: `minValidatorReputation` blocks low-rep validators.
  - No `claimToValidate` — validators commit directly; `validationClaimCount` caps at `numberOfValidations`.

### Phase 4: Finalization (Three Independent Phases)

**Goal**: Accuracy of consensus and fairness of distribution. v0.5 splits into three steps.

**Step 1: `computeConsensus`** (anyone can call, computed once, cached)

- **State Assertions**:
  - `consensusComputed`, `consensusWeightedAverage`, `consensusStdDeviation` stored.
  - Contribution status → `Accepted` or `Rejected`.
  - If accepted: contributor stake unlocked; index state → `Accepted`.
  - If rejected: contributor slashed; index pushed back to available stack; `submissionNonce` incremented.
- **Events**: `ConsensusReached`.
- **Zero external calls** during consensus (reputation inline, ConsensusLib via delegatecall).

**Step 2: `settleValidator`** (each validator pulls their own outcome)

- **State Assertions**:
  - Outliers: `slashValidator` called; reputation penalty.
  - Accurate: stake released; `pendingRewards` credited; validator adapter fee if set.
  - `consensusSettled[validator]` marked true.
- **Events**: `ValidatorSettled`.

**Step 3: `releaseContributorReward`** + **`claimReward`**

- **State Assertions**:
  - `releaseContributorReward`: Only after `challengeEndsAt` elapsed; dispute must not be open/upheld.
  - `pendingRewards` credited; contribution adapter fee deducted.
  - `claimReward`: Universal for contributors, validators, adapters.
- **Events**: `ContributorRewardReleased`, `RewardClaimed`.
- **Edge Cases**:
  - Challenge period blocks early release.
  - Dispute blocks reward release.
  - Rejected contributions: index returned, nonce incremented, new contributor can reclaim.

### Phase 5: Disputes & Originator Reports

**Goal**: Consensus outcome challenges and originator accountability.

- **Functions**: `openDispute`, `resolveDispute`, `escalateDispute`; `reportOriginator`, `resolveOriginatorReport`, `escalateOriginatorReport`.
- **State Assertions**:
  - Dispute: Bond locked; challenge period extended; upheld/rejected outcomes.
  - Originator report: Blocks new claims; project cancelled if upheld.
  - Auto-escalation after 7-day deadline.
- **Events**: `DisputeOpened`, `DisputeResolved`, `DisputeEscalated`; `OriginatorReported`, etc.
- **Edge Cases**:
  - Contributor cannot dispute own acceptance.
  - Duplicate dispute/report reverts.
  - Escrow sufficiency for overturned rejections.

---

## Recommended Test Architecture

### 1. Happy Path (`Lifecycle.t.sol`)

Single file running the flow A-to-Z:
```
createProject → fundProject → claimToContribute → contribute →
commitValidation → revealValidation (×N) → computeConsensus →
settleValidator (×N) → releaseContributorReward → claimReward
```

### 2. Edge Case Suite

- `test_ghostValidatorSlash` — `cancelExpiredCommitment`
- `test_claimExpirationPartialSubmission` — `expireClaim` atomically returns indices
- `test_rejectionThenResubmission` — nonce invalidation, index re-pooling
- `test_disputeUpheldOnAcceptedContribution` — blocks reward release
- `test_disputeUpheldOnRejectedContribution` — contributor compensation

### 3. Invariant Fuzzing

- `vault.totalAssets() >= sum(contributorLock + validatorCapacity + inFlight)` per user
- `engine.getProjectEscrow(projectId, token) >= sum(pendingRewards)` for that project
- `availableSlots + indices in pipeline = totalQuantity` per project

---

## Optimization & Debugging

- **Gas Reports**: `forge test --gas-report` — focus on `computeConsensus`, `settleValidator` loops.
- **Coverage**: `forge coverage` — ensure ConsensusLib branching (outlier tiers) fully tested.
