# Sapien Core

`SapienCore` is the central coordinator of the Sapien PoQ protocol. It manages the lifecycle of projects, claims, and contributions, and triggers the finalization process that involves rewards and slashing.

## 📋 Responsibilities

- **Project Management**: Creation and funding of projects.
- **Contribution Lifecycle**: Handling claims to contribute, work submission, and finalization.
- **Coordination**: Interfacing with `SapienVault`, `SapienTrust`, `ValidationOracle`, and `Rewards`.

## 🛠️ Key Functions

### Project Functions

#### `createProject`
Allows an Originator to initialize a new project with specific parameters:
- `projectId`: A unique `bytes32` identifier (usually a hash of the project metadata).
- `rewardToken`: The ERC20 token used for payouts.
- `ipfsCid`: The original IPFS CID of the project spec document.
- `minStakeToClaim`: Minimum stake required for a contributor to claim slots.
- `minStakeToContribute`: Minimum stake required to contribute (optional/secondary check).
- `numberOfValidations`: Exact number of validations required per contribution (also determines queue slots, defaults to 3).
- `validatorRewardBasisPoints`: The percentage of the reward pool reserved for validators (e.g., 1000 = 10%). Capped at 2500 (25%).
- `requiredSkill`: Optional skill requirement for contributors.

#### `fundProject`
Originators add reward tokens and increase the available quantity of contribution slots.

**Protocol Fee**: When funding a project, a configurable protocol fee (default 1% = 100 basis points) is automatically deducted from the funding amount and sent to the Sapien treasury. The remaining amount is allocated to the project's reward pool.

- `projectId`: The project identifier
- `rewardAmount`: Total amount of reward tokens to deposit (protocol fee is deducted from this)
- `quantity`: Number of contribution slots to add

**Note**: The protocol fee is only collected if:
- `protocolFeeBasisPoints > 0`
- `treasury` address is set
- `rewardAmount > 0`

#### `setProtocolFeeBasisPoints`
Admin-only function to configure the protocol fee percentage.
- `_feeBasisPoints`: Fee in basis points (e.g., 100 = 1%, max 300 = 3%)

#### `setTreasury`
Admin-only function to set the address that receives protocol fees.
- `_treasury`: The treasury address (must not be zero address)

#### `reclaimExpiredIndices`
Allows anyone to reclaim contribution slots that were reserved but not submitted within the deadline. This restores the `activeClaimedQuantity` and makes the slots available for other contributors.

### Contribution Functions

#### `claimToContribute`
Contributors claim a specific number of slots in a project. This:
1. Verifies the contributor's stake in `SapienVault` meets `minStakeToClaim`.
2. Locks the required stake in the vault.
3. Reserves specific contribution indices for the contributor using an internal `IndexReservation` system.
4. Returns a `claimId` used for subsequent submissions.

#### `contribute` / `batchContribute`
Contributors submit a `submissionHash` (e.g., an IPFS CID) for specific indices within their claim. 
- Must be called before the claim or index reservation deadline.
- Submissions are automatically enqueued in the `ValidationOracle` for review.

#### `releaseExpiredClaim`
Marks a claim as expired if the contributor failed to submit work before the deadline.
- Unlocks the contributor's stake but applies a slash penalty based on the `minStakeToClaim`.

#### `finalizeContribution`
Triggers consensus evaluation and processes the outcome. It:
1. Requests consensus from the `ValidationOracle` (checks if minimum reveals and deadlines are met).
2. Updates the contributor's reputation in `SapienTrust` (Success increase or Rejection penalty).
3. For accepted work: sets a **challenge period** (`challengeEndsAt`) during which rewards cannot be claimed, and auto-validates the contributor's skill if the project requires one.
4. For rejected work: re-queues the index back to the pool of available slots and resets the contribution state.
5. Executes slashing via `SapienVault` for outlier validators identified by consensus.
6. Distributes validator rewards (only on acceptance) proportional to consensus algorithm weights.
7. Unlocks the contributor's stake if the entire claim is processed.

#### `claimContributionReward`
After a contribution is finalized as accepted and the challenge period has elapsed, the contributor (or anyone on their behalf) can call this to trigger the actual reward distribution via the `Rewards` contract. This two-step process (finalize → claim after challenge period) provides a window for disputes before rewards are irreversibly distributed.

## 🚨 Events

- `ProjectCreated`: Emitted when a new project is registered.
- `ProjectFunded`: Emitted when a project receives funding.
- `ProtocolFeeCollected`: Emitted when a protocol fee is collected during project funding.
- `OperatorFeePaid`: Emitted when an operator fee is collected during project funding.
- `ContributionSubmitted`: Emitted when a contributor submits work.
- `ContributionFinalized`: Emitted when consensus is reached and rewards/slashing are processed.
- `ContributionRewarded`: Emitted when a contributor claims their reward after the challenge period.
- `ConsensusReached`: Emitted with the weighted average score and validator count.
- `ContributorRewardPreserved`: Emitted on rejection showing the reward amount preserved for the next contributor.
- `ConsensusThresholdUpdated`: Emitted when the consensus threshold is changed.
- `ChallengePeriodUpdated`: Emitted when the challenge period is changed.

## 🔐 Access Control

- **ORIGINATOR_ROLE**: Required to create projects.
- **CONTRIBUTOR_ROLE**: Required to claim slots and submit work.
- **DEFAULT_ADMIN_ROLE**: Global administration and configuration (protocol fee, treasury, and other protocol parameters).

## 💰 Protocol Fee

The protocol charges a configurable fee on project funding to support protocol operations and the Sapien treasury.

- **Default Fee**: 1% (100 basis points)
- **Maximum Fee**: 3% (300 basis points, enforced by `MAX_PROTOCOL_FEE_BPS`)
- **Operator Fee**: Up to 2% (200 basis points, enforced by `MAX_ORGINATION_OPERATOR_FEE_BPS`) — optional fee collected by third-party interfaces
- **Collection**: Automatically deducted from `fundProject` calls
- **Recipient**: Sapien treasury address (configurable by admin)
- **Configuration**: Admin can update fee percentage and treasury address via `setProtocolFeeBasisPoints()` and `setTreasury()`

The fee is calculated as: `protocolFee = (rewardAmount * protocolFeeBasisPoints) / 10000`

The remaining amount after fee deduction is allocated to the project's reward pool for distribution to contributors and validators.

## ⏰ Challenge Period

Accepted contributions enter a configurable challenge period (default 1 day) before rewards can be claimed. This provides a window for disputes. The contributor (or anyone) calls `claimContributionReward` after the period elapses to trigger the reward transfer.
