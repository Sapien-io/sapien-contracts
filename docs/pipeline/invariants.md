# Sapien PoQ Protocol Invariants

This document outlines the core invariants and properties of the Sapien Proof-of-Quality (PoQ) protocol, categorized by domain.

## 1. Conservation of Value & Solvency

### [CV-01] Vault Assets Integrity
- **Description**: The vault's reported total assets must always match the actual underlying token balance held by the contract.
- **Contract**: `SapienVault`
- **Property**: `vault.totalAssets() == stakingToken.balanceOf(address(vault))`

### [CV-02] Global Rewards Solvency
- **Description**: The Rewards contract must always hold enough tokens to cover all allocated (but unclaimed) rewards for projects, contributors, and validators.
- **Contract**: `Rewards`
- **Property**: `rewardToken.balanceOf(address(rewards)) >= rewards.totalAllocated(rewardToken)`

### [CV-03] Reward Conservation (Per Project)
- **Description**: For any given project, the sum of remaining project rewards, earned contributor rewards, and earned validator rewards (unclaimed) must be consistent with the total post-fee rewards funded into the project.
- **Contract**: `Rewards`, `SapienCore`
- **Property**: `projectRewards[projectId][token] + sum(contributorRewards[all][projectId][token]) + sum(validatorRewards[all][projectId][token])` (excluding claimed) is conserved relative to funding.

### [CV-04] Stake Conservation
- **Description**: The sum of all users' stakes (assets converted from shares) must be consistent with the total assets in the vault.
- **Contract**: `SapienVault`
- **Property**: `sum(vault.convertToAssets(vault.balanceOf(user))) <= vault.totalAssets()`

## 2. Staking & Locking

### [SL-01] Stake Liquidity
- **Description**: A user's locked stake can never exceed their total stake.
- **Contract**: `SapienVault`
- **Property**: `vault.getLockedStake(user) <= vault.getStake(user)`

### [SL-02] Withdrawal Restriction
- **Description**: A user can never withdraw or transfer more than their available (unlocked) stake.
- **Contract**: `SapienVault`
- **Property**: `withdrawnAmount <= (totalStake - lockedStake)`

### [SL-03] Global Lock Integrity
- **Description**: The sum of all `lockedStake[user]` must be less than or equal to `vault.totalAssets()`.
- **Contract**: `SapienVault`
- **Property**: `sum(lockedStake[users]) <= vault.totalAssets()`

## 3. Project & Contribution Accounting

### [PA-01] Project Slot Integrity
- **Description**: The sum of submitted contributions and active claimed slots cannot exceed the total quantity available in a project.
- **Contract**: `SapienCore`
- **Property**: `p.state.submittedQuantity + p.state.activeClaimedQuantity <= p.state.totalQuantityAvailable`

### [PA-02] Reward Distribution Bound
- **Description**: The number of rewarded (finalized) contributions can never exceed the number of submitted contributions.
- **Contract**: `SapienCore`
- **Property**: `p.state.rewardedQuantity <= p.state.submittedQuantity`

### [PA-03] Claim Limit Enforcement
- **Description**: No user can have more than `MAX_CLAIMS_PER_USER` active claimed slots in a project.
- **Contract**: `SapienCore`
- **Property**: `userActiveClaimedQuantity[projectId][user] <= 10`

## 4. Validator Capacity & Oracle

### [VO-01] Validator Stake In-Flight Bound
- **Description**: A validator's in-flight stake (stake committed but not revealed) can never exceed their total locked capacity.
- **Contract**: `ValidationOracle`
- **Property**: `vState.inFlightStake <= vState.capacity`

### [VO-02] Capacity-Lock Consistency
- **Description**: A validator's capacity in the Oracle should be backed by locked stake in the Vault.
- **Contract**: `ValidationOracle`, `SapienVault`
- **Property**: `vState.capacity <= vault.getLockedStake(validator)`

### [VO-03] Queue Consistency
- **Description**: The number of pending validation slots in the queue must be consistent with the difference between `queueTail` and `queueHead`.
- **Contract**: `ValidationOracle`
- **Property**: `pendingQueueSize == queueTail - queueHead`

## 5. Reputation & Trust

### [RT-01] Reputation Bounds
- **Description**: Every user's reputation score for any role must always stay within the protocol's defined minimum and maximum bounds.
- **Contract**: `SapienTrust`
- **Property**: `500 <= trustScore <= 10000`

### [RT-02] Daily Reputation Gain Cap
- **Description**: A user's reputation cannot increase by more than `MAX_DAILY_GAIN` (1%) in a single calendar day.
- **Contract**: `SapienTrust`
- **Property**: `reputationGain(user, day) <= 100`

## 6. Fairness & Incentive Alignment

### [FI-01] Consensus Threshold
- **Description**: No contribution can be rewarded if its weighted average score is below the protocol's consensus threshold.
- **Contract**: `SapienCore`, `ValidationOracle`
- **Property**: `contribution.status == Rewarded ==> contribution.averageScore >= consensusThreshold`

### [FI-02] Sybil Resistance (Self-Validation)
- **Description**: An originator or the contributor themselves can never be assigned as a validator for the same contribution.
- **Contract**: `ValidationOracle`
- **Property**: `validator != project.originator && validator != contribution.contributor`

### [FI-03] Precision Loss Prevention
- **Description**: Effective reward per contribution slot must always be at least `MIN_REWARD_PER_SLOT` to prevent rounding to zero.
- **Contract**: `SapienCore`
- **Property**: `rewardPerSlot >= 1e15`
