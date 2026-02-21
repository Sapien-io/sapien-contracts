# State Lifecycle Analysis: Claims, Contributions & Validations

## Architecture Overview

Everything flows through `QualityEngine.sol`, which delegates to specialized libraries via `DELEGATECALL`:

- **`ContributionLib`** — Claims and contribution submission
- **`ValidationLib`** — Commit-reveal validation and consensus
- **`FinalizationLib`** — Validator settlement and reward release
- **`ConsensusLib`** — Weighted scoring and outlier detection

All share storage via the ERC-7201 namespaced `EngineStorage` defined in `Types.sol`.

---

## State Machines

### 1. Claim States (`ClaimStatus`)

```
   claimToContribute()
         │
         ▼
     ┌────────┐
     │ Active │
     └───┬────┘
         │
    ┌────┴────────────────┐
    │                     │
    │ all indices         │ deadline passed
    │ submitted           │ (permissionless)
    │                     │
    ▼                     ▼
┌───────────┐      ┌──────────┐
│ Completed │      │ Expired  │
└───────────┘      └──────────┘
```

- **Active**: Created via `claimToContribute()`. Contributor has 7 days (`CLAIM_DEADLINE`) to submit all claimed indices.
- **Completed**: Transitions when `submittedCount == totalCount` (all indices submitted via `contribute()`).
- **Expired**: Anyone can call `expireClaim()` after the deadline passes. Unsubmitted indices are recycled back to the return stack, stake is slashed for unsubmitted indices, but already-submitted contributions continue through the validation pipeline.

### 2. Contribution States (`ContributionStatus`)

```
    contribute()
         │
         ▼
     ┌─────────┐
     │ Pending │
     └───┬─────┘
         │
    computeConsensus()
         │
    ┌────┴────────────────┐
    │                     │
    │ weighted avg        │ weighted avg
    │ >= threshold        │ < threshold
    │                     │
    ▼                     ▼
┌──────────┐       ┌──────────┐
│ Accepted │       │ Rejected │
└────┬─────┘       └──────────┘
     │
     │ challengeEndsAt elapsed
     │ + no open dispute
     │
     ▼
 [Reward Released]
  (rewardReleased = true)
```

- **Pending**: Created when contributor calls `contribute()` with a `submissionHash`. This is the state where validators can commit/reveal scores.
- **Accepted**: Set by `computeConsensus()` when the stake-weighted average score meets or exceeds `consensusThreshold`. A challenge period (`CHALLENGE_PERIOD = 1 day`) begins. Contributor stake is unlocked and reputation is boosted.
- **Rejected**: Set when weighted average falls below threshold. The index's `submissionNonce` is incremented (invalidating any stale validation data), the index is recycled to the return stack, contributor stake is slashed, and reputation is penalized.
- **Reward Released**: After challenge period elapses with no upheld dispute, `releaseContributorReward()` credits the contributor's `pendingRewards`.

### 3. Validation States (Implicit in `ValidatorCommit`)

There is no explicit enum — the state is inferred from fields:

```
 setValidatorCapacity()
         │
         ▼
  [Capacity Locked]
         │
  commitValidation()
         │
         ▼
   ┌───────────┐
   │ Committed │  (commitHash != 0, revealedAt == 0)
   └─────┬─────┘
         │
    ┌────┴──────────────────┐
    │                       │
    │ revealValidation()    │ deadline expires
    │                       │ (permissionless)
    ▼                       ▼
┌──────────┐        ┌────────────────────┐
│ Revealed │        │ Expired/Cancelled  │
└────┬─────┘        │ (cancelExpiredCommit│
     │              │  → full slash)     │
     │              └────────────────────┘
     │
  computeConsensus()
     + settleValidator()
     │
     ▼
┌──────────┐
│ Settled  │  (settled == true)
└──────────┘
   ├── Non-outlier: stake released, reward credited, reputation up
   └── Outlier: stake slashed (tiered 10-100%), reputation down
```

**Key deadlines:**
- `COMMIT_DEADLINE = 3 days` — window for validators to commit
- `REVEAL_DEADLINE = 2 days` — window to reveal after commit deadline
- `FORCE_SETTLE_DELAY = 30 days` — after which anyone can force-settle an unresponsive validator

### 4. Index States (`SubmissionStatus`)

The per-index lifecycle ties everything together:

```
  Empty → Reserved → Submitted → Accepted
    ▲         │           │          │
    │         │           │          │ (rejected)
    └─────────┴───────────┴──────────┘
         (recycled to return stack)
```

---

## End-to-End Data Flow

### Phase 1: Claiming

1. Contributor calls **`claimToContribute(projectId, quantity)`**
2. Stake locked: `minStakeToClaim * quantity` via `StakeVault`
3. Indices allocated (return stack first, then sequential range)
4. `Claim` created: `Active`, deadline = now + 7 days
5. Each `IndexState` set to `Reserved`
6. Project activates if first claim (`Funded` → `Active`)

### Phase 2: Contributing

1. Contributor calls **`contribute(claimId, index, submissionHash)`** (once per index)
2. `Contribution` created with `status = Pending`, `rewardRate` snapshot
3. `IndexState` transitions to `Submitted`
4. `pendingContributions[projectId]` incremented (blocks project completion)
5. When `submittedCount == totalCount`, claim transitions to `Completed`

### Phase 3: Validation (Commit-Reveal)

1. Validator calls **`commitValidation(projectId, index, commitHash, stakeAmount)`**
   - Stake moves from `validatorCapacity` → `inFlight`
   - `ValidatorCommit` stored, `claimCount` incremented
2. Validator calls **`revealValidation(projectId, index, score, salt)`**
   - Hash verified: `keccak256(score, salt) == commitHash`
   - Score recorded, `revealCount` incremented, added to `revealedValidators[]`

### Phase 4: Consensus

1. Anyone calls **`computeConsensus(projectId, index)`** once `revealCount >= numberOfValidations`
2. `ConsensusLib.calculate()` runs:
   - Weight per validator: `sqrt(stake) * effectiveReputation`
   - Computes weighted average and standard deviation
   - Classifies outliers (deviation > 1.5σ)
   - Determines tiered slash amounts (10%/25%/50%/100% based on deviation severity)
3. `ConsensusReport` stored (keyed by nonce for isolation)
4. Contribution outcome:
   - **Accepted**: challenge period starts, contributor stake unlocked, reputation boosted
   - **Rejected**: `submissionNonce` incremented, index recycled, contributor slashed

### Phase 5: Settlement & Finalization

1. Each validator calls **`settleValidator(projectId, index, nonce)`**
   - Outliers: stake slashed, reputation penalized
   - Accurate: stake released, validator reward credited proportional to weight
2. After challenge period, **`releaseContributorReward(projectId, index)`**
   - Requires no open/upheld dispute
   - Credits `pendingRewards[contributor][token]`
   - Decrements `pendingContributions`
3. Users call **`claimReward(token)`** to withdraw accumulated rewards

---

## Key Coordination Mechanisms

| Mechanism | Purpose |
|---|---|
| **`submissionNonce`** | Increments on rejection, isolating validation data across contribution cycles. Prevents stale commit/reveals from affecting a new submission at the same index. |
| **`pendingContributions`** | Counter per project tracking in-flight contributions. Blocks `completeProject()` until all reach terminal state. |
| **`challengeEndsAt`** | 1-day window after consensus for disputes before rewards can be released. |
| **Index return stack** | Recycled indices (from expirations/rejections) are pushed to a stack for O(1) reallocation. |
| **Stake lifecycle** | Contributor: `available → locked → unlocked/slashed`. Validator: `capacity → inFlight → released/slashed`. |

---

## Dispute Layer (Cross-Cutting)

Disputes can be opened during the challenge period and affect all three components:

- **Upheld on Accepted contribution**: Contributor penalized, challenger rewarded, blocks reward release
- **Upheld on Rejected contribution**: Contributor compensated, challenger rewarded
- **Rejected dispute**: Challenger's bond is slashed
- **Escalation**: If operator doesn't resolve within `DISPUTE_RESOLUTION_DEADLINE` (7 days), the dispute is automatically upheld

All disputes are keyed by `consensusNonce` to prevent cross-nonce state poisoning.
