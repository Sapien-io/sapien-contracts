# Lifecycle Testing Skill

This skill guides the creation of comprehensive test suites for the Sapien PoQ v0.5 protocol lifecycle. It focuses on **State-Transition Verification** to ensure fixes, optimizations, and improvements are correctly implemented across all phases.

## Purpose

To systematically verify that every function call in the protocol lifecycle:
1. Transitions the system from a valid Pre-State to a valid Post-State.
2. Emits correct events for indexing.
3. Handles edge cases and reverts on invalid inputs.
4. Maintains protocol invariants (solvency, fairness).

**Target**: `test/lifecycle/` directory.

**Architecture**: Sapien PoQ v0.5 -- SapienCore + SapienVault + 7 libraries (OriginationLib, ContributionLib, ValidationLib, ConsensusLib, FinalizationLib, DisputeLib, ReputationLib).

---

## Testing Strategy: State-Transition Verification

For every step in the lifecycle, tests must verify three components:
1. **Pre-State**: Assert initial balances, structs, and configurations.
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
  - Fee Math: Test with 1 wei, prime numbers, checking for rounding to zero.
  - Config Limits: Max numberOfValidations (10), invalid validatorRewardBps.
  - Originator stake requirement: `originatorLockedStake` when enabled.

### Phase 2: Contribution
**Goal**: Verify reservation logic and stake locking.

- **Functions**: `claimToContribute`, `contribute`, `batchContribute`, `expireClaim`.
- **State Assertions**:
  - **Vault**: `vault.getStakeAccount(user).contributorLock` increases by `minStakeToClaim * quantity`.
  - **Index allocation**: Range+stack hybrid; `indexRange` for sequential allocation, `returnStack` for returned indices.
  - **Claim**: `engine.getClaim(claimId)` has `projectId`, `deadline`, `status`, `totalCount`, `submittedCount`.
  - **Contribution**: `engine.getContribution(projectId, index)` shows `Reserved` then `Pending`.
- **Events**: `ClaimCreated`, `ContributionSubmitted`, `ClaimExpired`.
- **Edge Cases**:
  - **Index Reuse**: Verify returned indices are claimable by the next contributor.
  - **Double Submit**: Prevent submitting same index twice.
  - **Partial Expiry**: Submitted indices stay in pipeline; unsubmitted returned.

### Phase 3: Validation (Commit-Reveal)
**Goal**: Prevent gaming of the consensus mechanism.

- **Functions**: `lockValidatorCapacity`, `unlockValidatorCapacity`, `claimToValidate`, `commitValidation`, `batchCommitValidations`, `revealValidation`, `batchRevealValidations`.
- **State Assertions**:
  - **Capacity**: `vault.getStakeAccount(user).validatorCapacity` locked.
  - **Commit**: `validatorCapacity` -> `inFlight` via `commitStake`; `ValidatorCommit` struct stored with commitHash, stakedAmount.
  - **Reveal**: `revealedValidators` populated; stake stays in-flight until settlement.
  - **Ghost**: `cancelExpiredCommitment` slashes committed-but-unrevealed validators.
- **Events**: `ValidationCommitted`, `ValidationRevealed`.
- **Edge Cases**:
  - **Ghost Validators**: `cancelExpiredCommitment` slashing and consensus unblocking.
  - **Commit Hash**: `keccak256(abi.encodePacked(score, salt))` -- stake tracked separately in `ValidatorCommit.stakedAmount`.
  - **Reputation Gate**: `minValidatorReputation` blocks low-rep validators.
  - **Validation Claims**: `claimToValidate` with expiry; `cancelExpiredValidationClaim` for cleanup.

### Phase 4: Finalization and Rewards
**Goal**: Accuracy of consensus and fairness of distribution.

- **Functions**: `computeConsensus`, `settleValidator`, `forceSettleValidator`, `releaseContributorReward`, `claimReward`.
- **State Assertions**:
  - **Consensus**: ConsensusReport stored with weightedAverage, stdDeviation. Contribution status set to Accepted/Rejected.
  - **Reputation**: Updated via ReputationLib for contributors and validators.
  - **Rewards**: pendingRewards credited; project escrow debited.
  - **Vault**: Accurate validators' stake released; outliers slashed with tiered amounts.
- **Events**: `ConsensusReached`, `ValidatorSettled`, `ContributorRewardReleased`, `RewardClaimed`.
- **Edge Cases**:
  - **Re-queuing**: Rejected contributions increment submissionNonce; index returned to stack.
  - **Challenge Period**: Blocks early reward release.
  - **Disputes**: Open/upheld dispute blocks reward release.
  - **Force Settlement**: `forceSettleValidator` after `forceSettleDelay`.

---

## Recommended Test Architecture

### 1. Happy Path (`EndToEnd.t.sol`)
A single file running the flow A-to-Z to verify integration.
```
createProject -> fundProject -> claimToContribute -> contribute ->
claimToValidate -> commitValidation -> revealValidation (xN) ->
computeConsensus -> settleValidator (xN) ->
releaseContributorReward -> claimReward
```

### 2. Edge Case Suite
- `test_ghostValidatorSlash` -- `cancelExpiredCommitment`
- `test_claimExpirationPartialSubmission` -- `expireClaim` atomically returns indices
- `test_rejectionThenResubmission` -- nonce invalidation, index re-pooling
- `test_disputeUpheldOnAcceptedContribution` -- blocks reward release
- `test_disputeUpheldOnRejectedContribution` -- contributor compensation
- `test_validationClaimExpiry` -- `cancelExpiredValidationClaim`

### 3. Invariant Fuzzing
Properties that must hold true after *any* sequence of actions.
- `vault.totalAssets() >= sum(contributorLock + validatorCapacity + inFlight)` per user
- `engine.getProjectEscrow(projectId, token) >= sum(pendingRewards)` for that project
- `availableSlots + indices in pipeline = totalQuantity` per project

---

## Optimization and Debugging

- **Gas Reports**: Run `forge test --gas-report` to identify expensive functions (e.g., `computeConsensus`, `settleValidator`).
- **Coverage**: Run `forge coverage` to ensure ConsensusLib branching (outlier tiers) and DisputeLib paths are fully tested.
