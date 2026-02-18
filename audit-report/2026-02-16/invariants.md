# Sapien PoQ v0.5 — Protocol Invariants

## Overview

This document defines the core invariants and security properties that must hold true for the Sapien PoQ v0.5 protocol to maintain its security guarantees. These invariants are designed for formal verification and comprehensive fuzz testing.

## Core Protocol Invariants

### Asset Conservation Invariants

**Invariant 1: ERC20 Reward Token Conservation**
```
∀ projectId, token ∈ Project.rewardTokens:
  projectEscrow[projectId][token] + ∑(pendingRewards[user][token] for all users) + ∑(claimedRewards) + adapterFees[token] + treasuryFees[token] = initialFunding[projectId][token]
```
*Description*: All reward tokens funded to a project must be accounted for across escrow, pending rewards, claimed amounts, and collected fees. No tokens can be created or destroyed improperly.

**Invariant 2: SAPIEN Stake Token Conservation**
```
∀ user ∈ Users:
  StakeVault.balanceOf(user) = availableBalance[user] + contributorLock[user] + validatorCapacity[user] + inFlight[user]
```
*Description*: A user's total staked SAPIEN tokens must equal the sum of all accounting states. Stake cannot disappear or be created outside of deposit/withdraw operations.

**Invariant 3: Global Stake Accounting**
```
StakeVault.totalSupply() = ∑(availableBalance[user] + contributorLock[user] + validatorCapacity[user] + inFlight[user] for all users)
```
*Description*: The total staked SAPIEN tokens in the vault must equal the sum of all user accounting states.

### Escrow Integrity Invariants

**Invariant 4: Project Escrow Balance**
```
∀ projectId:
  projectEscrow[projectId][token] ≥ ∑(releasedRewards[projectId][index] + validatorRewards[projectId][index] + disputeRedistributions[projectId][index] for all indices)
```
*Description*: Project escrow must always have sufficient balance to cover all distributed rewards and settlements.

**Invariant 5: Pending Rewards Accounting**
```
∀ user, token:
  pendingRewards[user][token] = ∑(earnedRewards[user][token]) - ∑(claimedRewards[user][token])
```
*Description*: Pending rewards must accurately reflect earned but unclaimed amounts.

### State Transition Invariants

**Invariant 6: Project State Machine**
```
∀ projectId:
  Project.state ∈ {CREATED, FUNDED, ACTIVE, COMPLETED, CANCELLED}
```
Valid transitions:
- CREATED → FUNDED (via fundProject)
- FUNDED → ACTIVE (via first claimToContribute)
- ACTIVE → COMPLETED (via completeProject when all indices settled)
- Any state → CANCELLED (via resolveOriginatorReport if upheld)

**Invariant 7: Index State Machine**
```
∀ projectId, index:
  Index.state ∈ {UNCLAIMED, CLAIMED, SUBMITTED, CONSENSUS_COMPUTED, SETTLED, DISPUTED, COMPLETED}
```
Valid transitions follow the critical flow sequence with proper ordering constraints.

**Invariant 8: Stake State Transitions**
```
∀ user:
  Stake transitions maintain conservation and proper sequencing:
  - available → contributorLock (claimToContribute)
  - contributorLock → available (successful contribution)
  - contributorLock → burned (failed contribution)
  - available → validatorCapacity (setValidatorCapacity)
  - validatorCapacity → inFlight (commitValidation)
  - inFlight → validatorCapacity (successful validation)
  - inFlight → burned (failed validation)
```

## Economic Security Invariants

### Slashing Invariants

**Invariant 9: Slashing Conservation**
```
Total slashed amounts ≤ total staked tokens initially deposited
Slashing cannot create new tokens or affect unstaked balances
```
*Description*: Slashing can only burn existing staked tokens, never create new tokens or affect user wallet balances.

**Invariant 10: Validator Slashing Fairness**
```
∀ validator, projectId, index:
  If validator.isOutlier[projectId][index]:
    slashedAmount ≤ validator.stakeAmount[projectId][index]
```
*Description*: Validator slashing cannot exceed the stake amount committed to that validation.

**Invariant 11: Contributor Slashing Proportionality**
```
∀ contributor, projectId, index:
  If contribution.rejected && !dispute.upheld:
    slashedAmount = contributor.stakeAmount * SLASH_PERCENTAGE
```
*Description*: Contributor slashing for rejected work follows defined penalty rates.

**Invariant 12: Originator Accountability**
```
∀ projectId:
  If originatorReport.upheld:
    slashedAmount ≤ originatorLockedStake[projectId]
```
*Description*: Originator slashing cannot exceed their locked stake for accountability.

### Reward Distribution Invariants

**Invariant 13: Reward Bounds**
```
∀ contribution ∈ acceptedContributions:
  0 ≤ contribution.rewardAmount ≤ project.maxRewardPerContribution
```
*Description*: Distributed rewards cannot exceed project funding limits.

**Invariant 14: Fee Conservation**
```
∀ projectId, token:
  adapterFees[projectId][token] + treasuryFees[projectId][token] ≤ project.totalRewards[projectId][token] * MAX_FEE_PERCENTAGE
```
*Description*: Collected fees cannot exceed reasonable percentage of project funding.

**Invariant 15: Validator Reward Source**
```
∀ validatorReward ∈ distributedRewards:
  validatorReward.source = projectEscrow[token] || disputeRedistribution
```
*Description*: Validator rewards come from legitimate sources (escrow or dispute settlements).

**Invariant 16: Contributor Reward Calculation**
```
∀ acceptedContribution:
  rewardAmount = project.rewardRate * contribution.qualityScore
```
*Description*: Contributor rewards are calculated based on project parameters and consensus score.

### Bond Requirements

**Invariant 17: Dispute Bond Sufficiency**
```
∀ dispute ∈ activeDisputes:
  dispute.bondAmount ≥ MIN_DISPUTE_BOND
```
*Description*: All disputes must have sufficient bonded stake to deter frivolous challenges.

**Invariant 18: Bond Return Correctness**
```
∀ resolvedDispute:
  If dispute.upheld: challenger receives bond back + portion of counterparty stake
  If dispute.rejected: challenger bond is slashed
```
*Description*: Dispute bond settlement follows correct economic incentives.

**Invariant 19: Originator Report Bond**
```
∀ originatorReport ∈ activeReports:
  report.bondAmount ≥ MIN_ORIGINATOR_REPORT_BOND
```
*Description*: Originator misconduct reports require sufficient bonds.

### Economic Attack Prevention

**Invariant 20: Sybil Attack Prevention**
```
∀ user:
  user.stakeAmount ≥ minStakeRequirement ⇒ user can participate
```
*Description*: Minimum stake requirements prevent Sybil attacks.

**Invariant 21: Griefing Attack Prevention**
```
∀ maliciousAction:
  costOfAttack > potentialGain
```
*Description*: Economic incentives prevent profitable griefing attacks.

**Invariant 22: Front-Running Prevention**
```
∀ timeSensitiveOperation:
  operation requires stake commitment or has economic consequences
```
*Description*: Time-sensitive operations have economic barriers to front-running.

### Reward Distribution Invariants

**Invariant 11: Reward Bounds**
```
∀ contribution ∈ acceptedContributions:
  0 ≤ contribution.rewardAmount ≤ project.maxRewardPerContribution
```
*Description*: Distributed rewards cannot exceed project funding limits.

**Invariant 12: Fee Conservation**
```
∀ projectId, token:
  adapterFees[projectId][token] + treasuryFees[projectId][token] ≤ project.totalRewards[projectId][token] * MAX_FEE_PERCENTAGE
```
*Description*: Collected fees cannot exceed reasonable percentage of project funding.

### Bond Requirements

**Invariant 13: Dispute Bond Sufficiency**
```
∀ dispute ∈ activeDisputes:
  dispute.bondAmount ≥ MIN_DISPUTE_BOND
```
*Description*: All disputes must have sufficient bonded stake to deter frivolous challenges.

**Invariant 14: Originator Stake Requirements**
```
∀ projectId:
  If originatorStakeRequirement > 0:
    originatorLockedStake[projectId] ≥ originatorStakeRequirement
```
*Description*: Originators must maintain required stake for accountability.

## Consensus Algorithm Invariants

### Weighted Consensus Properties

**Invariant 23: Consensus Validity**
```
∀ consensusResult ∈ computedConsensus:
  consensusResult.score ∈ [MIN_SCORE, MAX_SCORE]
  consensusResult.confidence ∈ [0, MAX_CONFIDENCE]
```
*Description*: Consensus results must produce valid score ranges and confidence intervals.

**Invariant 24: Participation Requirements**
```
∀ consensusComputation:
  consensusResult.participantCount ≥ MIN_VALIDATORS
```
*Description*: Consensus requires minimum validator participation to be valid.

**Invariant 25: Stake Weighting Correctness**
```
∀ validator ∈ consensusParticipants:
  validator.weight = sqrt(validator.stakeAmount)
  ∑(validator.weights) > 0
```
*Description*: Validator weights must be correctly calculated and non-zero for valid consensus.

**Invariant 26: Weighted Average Correctness**
```
∀ consensusResult:
  consensusResult.weightedMean = ∑(validator.weight[i] * validator.score[i]) / ∑(validator.weight[i])
```
*Description*: Consensus produces mathematically correct weighted averages.

**Invariant 27: Outlier Detection Soundness**
```
∀ validator ∈ consensusParticipants:
  If |validator.score - consensusResult.weightedMean| > consensusResult.standardDeviation * OUTLIER_THRESHOLD:
    validator.isOutlier = true
```
*Description*: Outlier detection is based on statistical measures and consistent thresholds.

**Invariant 28: Consensus Determinism**
```
∀ identicalInputs:
  consensusAlgorithm.calculate(inputs1) == consensusAlgorithm.calculate(inputs2)
```
*Description*: Consensus algorithm produces deterministic results for identical inputs.

**Invariant 29: Consensus Algorithm Safety**
```
∀ consensusCall:
  consensusAlgorithm cannot modify contract storage
  consensusAlgorithm cannot call external contracts
```
*Description*: Consensus algorithm is isolated and cannot cause side effects.

**Invariant 30: Minimum Participation Enforcement**
```
∀ consensusComputation:
  If participantCount < MIN_VALIDATORS:
    consensusResult = INVALID_CONSENSUS
```
*Description*: Insufficient participation prevents consensus computation.

### Outlier Detection

**Invariant 18: Outlier Classification**
```
∀ validator ∈ consensusParticipants:
  If |validator.score - consensusResult.weightedMean| > consensusResult.standardDeviation * OUTLIER_THRESHOLD:
    validator.isOutlier = true
```
*Description*: Outlier detection must be based on statistical measures from the consensus algorithm.

## Temporal and Sequencing Invariants

### Time Window Invariants

**Invariant 31: Deadline Enforcement**
```
∀ claim ∈ activeClaims:
  If block.timestamp > claim.deadline:
    claim.state = EXPIRED
```
*Description*: Expired claims must be properly marked and cleaned up.

**Invariant 32: Validation Windows**
```
∀ validation ∈ activeValidations:
  commitWindow: [contribution.timestamp, contribution.timestamp + COMMIT_WINDOW]
  revealWindow: [commit.timestamp, commit.timestamp + REVEAL_WINDOW]
```
*Description*: Validation phases must respect proper time sequencing.

**Invariant 33: Challenge Periods**
```
∀ consensusResult ∈ computedConsensus:
  challengeWindow: [consensus.timestamp, consensus.timestamp + CHALLENGE_PERIOD]
  If block.timestamp > consensus.timestamp + CHALLENGE_PERIOD:
    consensus.finalized = true
```
*Description*: Challenge periods must elapse before final settlement.

**Invariant 34: Escalation Timeouts**
```
∀ unresolvedDispute:
  If block.timestamp > dispute.timestamp + OPERATOR_TIMEOUT:
    dispute.canEscalate = true
```
*Description*: Unresolved disputes can be escalated after operator timeout.

**Invariant 35: Report Resolution Windows**
```
∀ originatorReport:
  resolutionWindow: [report.timestamp, report.timestamp + OPERATOR_TIMEOUT]
  If block.timestamp > report.timestamp + OPERATOR_TIMEOUT:
    report.canEscalate = true
```
*Description*: Originator reports have bounded resolution times.

### Flow Sequencing Invariants

**Invariant 36: Project Setup Flow**
```
∀ projectId:
  project.funded ⇒ project.created
  project.active ⇒ project.funded
  project.completed ⇒ project.active
```
*Description*: Project states must be reached in proper sequence.

**Invariant 37: Contribution Flow**
```
∀ projectId, index:
  contribution.submitted ⇒ index.claimed
  validation.committed ⇒ contribution.submitted
  consensus.computed ⇒ validation.revealed
  settlement.complete ⇒ consensus.computed
```
*Description*: Contribution processing follows strict ordering.

**Invariant 38: Validation Commit-Reveal**
```
∀ validation ∈ activeValidations:
  validation.revealed ⇒ validation.committed
  validation.revealTime > validation.commitTime
  validation.revealTime ≤ validation.commitTime + REVEAL_WINDOW
```
*Description*: Commit-reveal scheme maintains temporal integrity.

**Invariant 39: Phased Finalization**
```
∀ projectId, index:
  ¬(settlingValidators[projectId][index] ∧ releasingRewards[projectId][index])
  ¬(computingConsensus[projectId][index] ∧ settlingValidators[projectId][index])
```
*Description*: Phased operations prevent single-transaction failures from cascading.

**Invariant 40: Dispute Timing**
```
∀ dispute ∈ activeDisputes:
  dispute.timestamp > consensus.timestamp
  dispute.timestamp ≤ consensus.timestamp + CHALLENGE_PERIOD
```
*Description*: Disputes can only be opened during challenge periods.

### Critical Flow Properties

**Invariant 41: Index Allocation Soundness**
```
∀ claimToContribute:
  ∀ i,j ∈ indices: i ≠ j ⇒ indices[i] ≠ indices[j]
  ∀ i ∈ indices: 0 ≤ indices[i] < project.quantity
```
*Description*: Index allocation prevents duplicates and out-of-bounds access.

**Invariant 42: Stake State Consistency**
```
∀ stakeMovement:
  oldState + movement = newState
  No intermediate states visible to external observers
```
*Description*: Stake state transitions are atomic and consistent.

**Invariant 43: Escrow Accounting**
```
∀ rewardDistribution:
  escrowBalance_pre - distributedAmount = escrowBalance_post
  distributedAmount ≤ escrowBalance_pre
```
*Description*: Escrow debits match distribution amounts.

**Invariant 44: Pending Rewards Accounting**
```
∀ rewardCredit:
  pendingRewards_post[user][token] = pendingRewards_pre[user][token] + creditAmount
∀ rewardClaim:
  claimedAmount ≤ pendingRewards_pre[user][token]
```
*Description*: Pending rewards track earned and claimed amounts accurately.

### Sequencing Invariants

**Invariant 22: Flow Ordering**
```
∀ projectId, index:
  consensusComputed[projectId][index] ⇒ contributionSubmitted[projectId][index]
  validatorSettled[projectId][index] ⇒ consensusComputed[projectId][index]
  rewardReleased[projectId][index] ⇒ consensusAccepted[projectId][index] ∧ challengePeriodElapsed[projectId][index]
```
*Description*: Critical flows must execute in proper sequence with appropriate preconditions.

**Invariant 23: Phase Separation**
```
∀ projectId, index:
  ¬(consensusComputing[projectId][index] ∧ validatorSettling[projectId][index])
  ¬(validatorSettling[projectId][index] ∧ rewardReleasing[projectId][index])
```
*Description*: Phased finalization prevents single-transaction reverts from cascading failures.

## Access Control Invariants

### Role-Based Access

**Invariant 24: Admin Function Restrictions**
```
∀ adminFunction ∈ {setProtocolFee, setConsensusAlgorithm, pause, unpause}:
  caller.hasRole(DEFAULT_ADMIN_ROLE)
```
*Description*: Administrative functions require proper role authorization.

**Invariant 25: Operator Function Restrictions**
```
∀ operatorFunction ∈ {resolveDispute, resolveOriginatorReport}:
  caller.hasRole(OPERATOR_ROLE)
```
*Description*: Dispute resolution requires operator role.

### Permissionless Operations

**Invariant 26: Permissionless Function Availability**
```
∀ permissionlessFunction ∈ {computeConsensus, settleValidator, releaseContributorReward, cancelExpiredCommitment, escalateDispute}:
  function callable by any address with valid preconditions
```
*Description*: Permissionless functions must be callable by anyone when preconditions are met.

## Reputation System Invariants

**Invariant 27: Reputation Bounds**
```
∀ user:
  MIN_REPUTATION ≤ user.reputation ≤ MAX_REPUTATION
```
*Description*: Reputation scores must stay within defined bounds.

**Invariant 28: Reputation Decay**
```
∀ user, timeDelta:
  If timeDelta > DECAY_INTERVAL:
    user.reputation = user.reputation * (1 - decayRate)^(timeDelta / DECAY_INTERVAL)
```
*Description*: Reputation decay must be applied correctly over time.

**Invariant 29: Reputation Updates**
```
∀ reputationUpdate ∈ {successfulValidation, failedValidation, consensusAgreement, consensusDisagreement}:
  |reputationDelta| ≤ MAX_REPUTATION_DELTA
```
*Description*: Reputation changes must be bounded to prevent extreme swings.

## External Dependency Invariants

### ERC-4337 Account Abstraction

**Invariant 30: Smart Account Security**
```
∀ userOperation ∈ submittedOperations:
  userOperation.signature validates against user.account
  Session keys respect scope limitations (server cannot access sensitive functions)
```
*Description*: Account abstraction operations must maintain proper authorization.

### Consensus Algorithm Safety

**Invariant 31: Algorithm Interface Compliance**
```
∀ consensusAlgorithm ∈ registeredAlgorithms:
  algorithm.calculate(validations) returns ConsensusResult with required fields
  algorithm does not modify contract storage
  algorithm is deterministic for same inputs
```
*Description*: Pluggable consensus algorithms must be safe and deterministic.

### ERC-4626 Vault Safety

**Invariant 32: Vault Share Accounting**
```
∀ user:
  vault.convertToAssets(vault.balanceOf(user)) = totalUserStake
  vault.maxRedeem(user) = availableBalance[user]
```
*Description*: ERC-4626 vault must maintain correct share-to-asset conversions and withdrawal limits.

## Failure Mode Invariants

### Graceful Degradation

**Invariant 33: Partial Failure Containment**
```
∀ failedOperation ∈ {consensusComputation, validatorSettlement, rewardRelease}:
  failure affects only specific index/project, not global state
```
*Description*: Individual operation failures must not cascade to affect unrelated state.

**Invariant 34: Escrow Protection**
```
∀ disputeResolution, projectCancellation:
  remainingEscrow returned to originator
  No escrow lost to failed operations
```
*Description*: Escrow must be protected even in failure scenarios.

### Reentrancy Protection

**Invariant 35: Reentrancy Guards**
```
∀ nonReentrant function ∈ {fundProject, claimToContribute, commitValidation, revealValidation, computeConsensus, settleValidator, releaseContributorReward, claimReward}:
  function cannot be re-entered during execution
```
*Description*: Critical economic functions must prevent reentrancy attacks.

## Monitoring and Alerting Invariants

### Critical Metrics

**Invariant 36: System Health Metrics**
```
Total escrowed value > 0 ⇒ system operational
∑(staked tokens) > MIN_TOTAL_STAKED
Active projects < MAX_ACTIVE_PROJECTS
```
*Description*: Key system metrics must stay within healthy bounds.

**Invariant 37: Anomaly Detection**
```
Alert if:
  escrowBalance[project] < expectedRemaining[project]
  stakeAccounting[user] inconsistent
  reputationChange[user] > MAX_REPUTATION_DELTA
```
*Description*: Anomalies in critical accounting must trigger alerts.

These invariants provide comprehensive coverage of the protocol's security properties and should be tested through formal verification tools and extensive fuzz testing campaigns.