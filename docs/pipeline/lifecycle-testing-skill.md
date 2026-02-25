# Lifecycle Testing Skill

This skill guides the creation of comprehensive test suites for the Sapien PoQ v0.5 protocol lifecycle. It focuses on **State-Transition Verification** to ensure fixes, optimizations, and improvements are correctly implemented across all phases.

## Purpose

To systematically verify that every function call in the protocol lifecycle:
1. Transitions the system from a valid Pre-State to a valid Post-State.
2. Emits correct events for indexing.
3. Handles edge cases and reverts on invalid inputs.
4. Maintains protocol invariants (solvency, fairness).

**Target**: `test/lifecycle/` directory.

**Architecture Reference**: Sapien PoQ v0.5 uses two contracts (`SapienCore`, `SapienVault`) and seven libraries (`OriginationLib`, `ContributionLib`, `ValidationLib`, `ConsensusLib`, `FinalizationLib`, `DisputeLib`, `ReputationLib`).

---

## Contract Topology (v0.5)

```
SapienCore (single contract, delegates to libraries)
├── Project management (OriginationLib)
├── Claim & index management (ContributionLib)
├── Contribution tracking (ContributionLib)
├── Validation state machine -- commit-reveal (ValidationLib)
├── Consensus computation (ValidationLib + ConsensusLib)
├── Reputation (ReputationLib, inline via DELEGATECALL)
├── Reward escrow & distribution (FinalizationLib)
├── Disputes & originator accountability (DisputeLib)
└── calls ──→ SapienVault (external, stake operations only)

SapienVault (ERC-4626)
├── Deposits / withdrawals
├── Contributor locks (contributorLock)
├── Validator capacity (validatorCapacity)
├── In-flight stake (inFlight)
├── Transfer/withdrawal guards
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
  - Originator stake locked in vault if `originatorStakeRequirement > 0`.
- **Events**: `ProjectCreated`, `ProjectFunded`, `OriginationFeePaid`.
- **Edge Cases**:
  - Fee math: 1 wei, prime numbers, rounding to zero.
  - Config limits: zero numberOfValidations, invalid validatorRewardBps.
  - Originator stake requirement: `originatorLockedStake` when enabled.

### Phase 2: Claim and Contribute

**Goal**: Verify index reservation, stake locking, and contribution submission.

- **Functions**: `claimToContribute`, `contribute`, `batchContribute`, `expireClaim`.
- **State Assertions**:
  - **Vault**: `vault.getStakeAccount(user).contributorLock` increases by `minStakeToClaim * quantity`.
  - **Index allocation**: Range+stack hybrid -- `indexRange` provides initial sequential allocation; `returnStack` receives returned indices.
  - **Claim**: `engine.getClaim(claimId)` has `projectId`, `deadline`, `status`, `totalCount`, `submittedCount`.
  - **Contribution**: `engine.getContribution(projectId, index)` shows `Reserved` then `Pending` after submission.
  - **Expiry**: `expireClaim` returns unsubmitted indices to return stack atomically; contributor slashed for unsubmitted slots, unlocked for submitted slots.
- **Events**: `ClaimCreated`, `ContributionSubmitted`, `ClaimExpired`.
- **Edge Cases**:
  - Index reuse: After `expireClaim`, indices must be claimable by the next contributor.
  - Double submit: Prevent submitting same index twice.
  - Partial expiry: Submitted indices stay in pipeline; unsubmitted returned.
  - Originator cannot contribute to own project.

### Phase 3: Validation (Commit-Reveal)

**Goal**: Prevent gaming of the consensus mechanism.

- **Functions**: `lockValidatorCapacity`, `unlockValidatorCapacity`, `claimToValidate`, `commitValidation`, `batchCommitValidations`, `revealValidation`, `batchRevealValidations`, `cancelExpiredValidationClaim`.
- **State Assertions**:
  - **Capacity**: `vault.getStakeAccount(user).validatorCapacity` locked.
  - **Commit**: `validatorCapacity` -> `inFlight` via `commitStake`; `ValidatorCommit` struct stored with commitHash, stakedAmount, commitTimestamp.
  - **Reveal**: `revealedValidators` populated; stake stays in-flight until settlement.
  - **Ghost**: `cancelExpiredCommitment` slashes committed-but-unrevealed validators.
  - **Validation claims**: `claimToValidate(projectId, quantity)` randomly assigns pending contributions; expired claims cancelled via `cancelExpiredValidationClaim`.
- **Events**: `ValidationCommitted`, `ValidationRevealed`.
- **Edge Cases**:
  - Ghost validators: `cancelExpiredCommitment` slashing and consensus unblocking.
  - Commit hash: `keccak256(abi.encodePacked(score, salt))` -- stake amount tracked separately in `ValidatorCommit.stakedAmount`.
  - Reputation gate: `minValidatorReputation` blocks low-rep validators.
  - Validation claim expiry: uncommitted claims can be cancelled after deadline.

### Phase 4: Finalization (Three Independent Phases)

**Goal**: Accuracy of consensus and fairness of distribution. v0.5 splits into three steps.

**Step 1: `computeConsensus`** (anyone can call, computed once per nonce, cached)

- **State Assertions**:
  - `ConsensusReport` stored: `weightedAverage`, `stdDeviation`, `totalAccurateWeight`, `nonce`, `computed`.
  - Per-validator: `ValidatorConsensusResult` stored with `isOutlier`, `slashAmount`, `weight`.
  - Contribution status -> `Accepted` or `Rejected` (based on consensusThreshold).
  - If accepted: contributor stake unlocked; `challengeEndsAt` set.
  - If rejected: contributor slashed; index pushed to return stack; `submissionNonce` incremented.
- **Events**: `ConsensusReached`.
- **Zero external calls** during consensus (ConsensusLib is pure math, reputation via DELEGATECALL).

**Step 2: `settleValidator`** (each validator pulls their own outcome)

- **State Assertions**:
  - Outliers: `slashValidator` called on vault; reputation penalty via ReputationLib.
  - Accurate: stake released (`releaseCommit`); `pendingRewards` credited; validator adapter fee if set.
  - `ValidatorCommit.settled` marked true.
- **Events**: `ValidatorSettled`.
- **`forceSettleValidator`**: permissionless after `forceSettleDelay`; settles on behalf of a validator.

**Step 3: `releaseContributorReward`** + **`claimReward`**

- **State Assertions**:
  - `releaseContributorReward`: Only after `challengeEndsAt` elapsed; dispute must not be open/upheld.
  - `pendingRewards` credited; contribution adapter fee deducted.
  - `claimReward`: Universal for contributors, validators, adapters -- transfers from projectEscrow via token transfer.
- **Events**: `ContributorRewardReleased`, `RewardClaimed`.
- **Edge Cases**:
  - Challenge period blocks early release.
  - Open/upheld dispute blocks reward release.
  - Rejected contributions: index returned, nonce incremented, new contributor can reclaim.

### Phase 5: Disputes and Originator Reports

**Goal**: Consensus outcome challenges and originator accountability.

- **Functions**: `openDispute`, `resolveDispute`, `escalateDispute`; `reportOriginator`, `resolveOriginatorReport`, `escalateOriginatorReport`.
- **State Assertions**:
  - Dispute: Bond locked from challenger's contributor lock; challenge period extended on accepted contributions; upheld/rejected outcomes.
  - Originator report: Bond locked; project cancelled if upheld; originator stake slashed.
  - Auto-escalation after 7-day `DISPUTE_RESOLUTION_DEADLINE`.
  - Disputes keyed by consensus nonce (prevents cross-nonce poisoning).
- **Events**: `DisputeOpened`, `DisputeResolved`, `DisputeEscalated`; `OriginatorReported`, `OriginatorReportResolved`, `OriginatorReportEscalated`.
- **Edge Cases**:
  - Contributor cannot dispute own acceptance.
  - Duplicate dispute/report reverts.
  - Escrow sufficiency for overturned rejections.
  - One active originator report per project.

### Phase 6: Project Completion and Escrow Refund

**Goal**: Ensure project lifecycle terminates cleanly.

- **Functions**: `completeProject`, `refundEscrow`.
- **State Assertions**:
  - `completeProject`: Only when all slots filled and finalized; project status -> `Completed`.
  - `refundEscrow`: After completion delay, remaining escrow returned to originator.
  - Originator stake unlocked on completion.
- **Events**: `ProjectCompleted`.

---

## Recommended Test Architecture

### 1. Happy Path (`Lifecycle.t.sol`)

Single file running the flow A-to-Z:
```
createProject -> fundProject -> claimToContribute -> contribute ->
claimToValidate -> commitValidation -> revealValidation (xN) -> computeConsensus ->
settleValidator (xN) -> releaseContributorReward -> claimReward
```

### 2. Edge Case Suite

- `test_ghostValidatorSlash` -- `cancelExpiredCommitment`
- `test_claimExpirationPartialSubmission` -- `expireClaim` atomically returns indices
- `test_rejectionThenResubmission` -- nonce invalidation, index re-pooling
- `test_disputeUpheldOnAcceptedContribution` -- blocks reward release
- `test_disputeUpheldOnRejectedContribution` -- contributor compensation
- `test_validationClaimExpiry` -- `cancelExpiredValidationClaim`
- `test_forceSettleAfterDelay` -- `forceSettleValidator`

### 3. Invariant Fuzzing

- `vault.totalAssets() >= sum(contributorLock + validatorCapacity + inFlight)` per user
- `engine.getProjectEscrow(projectId, token) >= sum(pendingRewards)` for that project
- `availableSlots + indices in pipeline = totalQuantity` per project

---

## Optimization and Debugging

- **Gas Reports**: `forge test --gas-report` -- focus on `computeConsensus`, `settleValidator` loops.
- **Coverage**: `forge coverage` -- ensure ConsensusLib branching (outlier tiers) fully tested.
