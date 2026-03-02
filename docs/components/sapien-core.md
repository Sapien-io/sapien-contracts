# SapienCore

`SapienCore` is the unified entry-point contract for the Sapien Proof-of-Quality (PoQ) protocol. It coordinates the full lifecycle — project origination, contribution claiming, commit-reveal validation, stake-weighted consensus, dispute resolution, and reward distribution.

Deployed behind an **ERC-1967 UUPS proxy** with **ERC-7201 namespaced storage**. Its only external call target is `SapienVault` for stake operations.

## Architecture

SapienCore delegates all business logic to purpose-built libraries via `DELEGATECALL`:

| Library | Responsibility |
|---------|---------------|
| `OriginationLib` | Project creation, funding, and removal |
| `ContributionLib` | Claim creation, contribution submission, claim expiration |
| `ValidationLib` | Validator capacity, validation claims, commit-reveal, consensus computation |
| `FinalizationLib` | Validator settlement, contributor reward release, reward claiming, project completion |
| `DisputeLib` | Dispute opening/resolution, originator reports |
| `ReputationLib` | Score tracking with lazy decay and daily gain caps |
| `ConsensusLib` | Stake-weighted consensus calculation with outlier detection |

Shared types live in `Types.sol` and protocol constants in `Constants.sol`.

## Origination

### `createProject(bytes32 projectId, string metadataCid, Project config)`

Registers a new project in `Created` status. The caller becomes the originator. Key configuration fields in the `Project` struct:

| Field | Description |
|-------|-------------|
| `rewardToken` | ERC-20 token used for payouts |
| `minStakeToClaim` | Minimum stake a contributor must lock per claimed slot |
| `minValidationStake` | Project-level minimum stake for validators |
| `consensusThreshold` | Basis points threshold for acceptance (e.g. 7000 = 70%) |
| `validatorRewardBps` | Percentage of reward pool reserved for validators (max 2500 = 25%) |
| `numberOfValidations` | Number of validator reveals required per contribution (1–10) |
| `minValidatorReputation` | Minimum reputation score required for validators |
| `requiredSkill` | Registered skill hash (required) — reputation accrues against this key |

### `fundProject(bytes32 projectId, uint256 amount, uint256 quantity, address adapter)`

Funds the project with reward tokens and creates contribution slots.

1. Transfers `amount` tokens from the originator
2. Deducts **protocol fee** (default 1%) to the treasury
3. Optionally pays an **origination adapter fee** (default 2%) if `adapter != address(0)`
4. Locks **originator stake** if `originatorStakeRequirement > 0` (per slot)
5. Initializes the slot index range for allocation
6. Transitions project to `Funded` status

Can be called multiple times on a `Created` or `Funded` project to add more funding.

### `removeProject(bytes32 projectId)` — OPERATOR_ROLE only

Removes a project, slashes the originator's locked stake, and cancels the project.

## Contribution

### `claimToContribute(bytes32 projectId, uint256 quantity, address adapter) → (claimId, indices[])`

Claims one or more contribution slots (max 20 per call). Locks the contributor's stake at `minStakeToClaim * quantity`. Returns a `claimId` and the assigned slot `indices`. The first claim on a `Funded` project transitions it to `Active`.

Slot allocation uses a **range + return-stack hybrid**: fresh indices come from a contiguous range, while previously returned indices (from rejections/expirations) are recycled from a LIFO stack.

### `contribute(uint256 claimId, uint256 index, bytes32 submissionHash, string dataCid)`

Submits work for a single claimed slot. Transitions the slot from `Reserved` to `Pending` and records the `submissionHash` and `dataCid`. Must be called before the claim deadline.

### `batchContribute(uint256 claimId, uint256[] indices, bytes32[] submissionHashes, string[] dataCids)`

Batch version of `contribute`.

### `expireClaim(uint256 claimId, uint256[] indices)`

Permissionless. After the claim deadline passes, returns unsubmitted slots to the pool, slashes the contributor's stake for unsubmitted slots, and unlocks stake for submitted slots. Updates contributor reputation negatively.

## Validation

### `lockValidatorCapacity(uint256 amount)` / `unlockValidatorCapacity(uint256 amount)`

Validators pre-lock tokens as "capacity" in the vault. This capacity is drawn down when committing validations, eliminating per-commit lock/unlock gas costs.

### `claimToValidate(bytes32 projectId, uint256 quantity) → claimId`

Requests a quantity of validations and receives randomly assigned pending contributions. Checks reputation requirements and prevents validators from validating their own contributions. Creates a `ValidationClaim` with a 1-hour deadline to commit.

### `commitValidation(projectId, index, commitHash, stakeAmount, adapter)`

Commits a sealed score hash (`keccak256(abi.encodePacked(score, salt))`) with a stake amount. The stake is moved from validator capacity to in-flight. Must meet both the project-level and global minimum validation stake.

### `batchCommitValidations(projectId, indices[], commitHashes[], stakeAmounts[], adapter)`

Batch version of `commitValidation`.

### `revealValidation(projectId, index, score, salt)`

Reveals the previously committed score. Verifies `hash(score, salt) == commitHash`. Must be called within the reveal window. Score range is 0–10,000. **Reverts with `CommitPhaseIncomplete` if not all required validators have committed yet** — all validators must commit before any can reveal.

### `batchRevealValidations(projectId, indices[], scores[], salts[])`

Batch version of `revealValidation`.

### `cancelExpiredValidationClaim(uint256 claimId)`

Permissionless. Cancels a validation claim after its 1-hour deadline if the validator failed to commit. Applies a reputation penalty.

## Finalization

### `computeConsensus(bytes32 projectId, uint256 index)`

Triggers stake-weighted consensus computation via `ConsensusLib` after all required reveals are in. Determines whether the contribution is `Accepted` or `Rejected` based on the project's `consensusThreshold`. Starts the challenge period.

- **Accepted**: Contributor stake unlocked, reputation increased with a quality bonus
- **Rejected**: Contributor stake slashed, reputation decreased, slot returned to the pool, submission nonce incremented for re-contribution

### `settleValidator(bytes32 projectId, uint256 index, uint256 nonce)`

Validators call this to settle after consensus. Outlier validators are slashed (tiered: 10%/25%/50%/100%); accurate validators receive their stake back plus a share of the validator reward pool. Adapter fees are deducted if applicable.

### `forceSettleValidator(projectId, index, nonce, validator)`

Permissionless. Force-settles an unresponsive validator after `forceSettleDelay` elapses past the reveal.

### `releaseContributorReward(bytes32 projectId, uint256 index)`

Releases the contributor's share of the reward (minus validator and adapter fees) to their pending balance. Requires: contribution is `Accepted`, challenge period elapsed, no active dispute.

### `claimReward(address token)`

Withdraws accumulated pending rewards for a specific token. Subject to `minClaimAmount` and `claimCooldown` restrictions.

### `cancelExpiredCommitment(projectId, index, validator)`

Permissionless keeper function. Slashes validators who committed but failed to reveal within the commit + reveal deadline window.

## Disputes

### `openDispute(projectId, index, evidenceHash, evidenceCid)`

Opens a dispute against a consensus outcome during the challenge period. Requires a bond proportional to the contribution's reward rate (`disputeBondBps`). Cannot dispute your own accepted contribution.

### `resolveDispute(projectId, index, upheld)` — OPERATOR_ROLE only

- **Upheld**: Bond returned, challenger rewarded (20% of saved/slashed amount), contributor reputation penalized
- **Rejected**: Bond slashed, challenge period ended

### `escalateDispute(projectId, index)`

Permissionless. Auto-upholds a dispute if the `DISPUTE_RESOLUTION_DEADLINE` (7 days) passes without operator resolution.

## Originator Accountability

### `reportOriginator(projectId, evidenceHash)`

Reports an originator for misconduct. Requires a bond proportional to the project's total rewards (`originatorReportBondBps`). Blocks new contribution claims while open.

### `resolveOriginatorReport(projectId, upheld)` — OPERATOR_ROLE only

- **Upheld**: Bond returned, originator stake slashed, project cancelled, reporter rewarded
- **Rejected**: Bond slashed

### `escalateOriginatorReport(projectId)`

Permissionless. Auto-upholds after `DISPUTE_RESOLUTION_DEADLINE` passes. Project is cancelled.

## Project Completion

### `completeProject(bytes32 projectId)`

Originator marks the project as completed. Requires no active pipeline contributions. Unlocks originator stake.

### `refundEscrow(bytes32 projectId)`

Originator claims remaining escrow after `PROJECT_COMPLETION_DELAY` (30 days) post-completion.

## Admin Functions

All require `DEFAULT_ADMIN_ROLE`:

### Skill Registry

| Function | Description |
|----------|-------------|
| `registerSkill(string name)` | Hashes `name` via keccak256, stores the hash, and emits `SkillRegistered(skillId, name)` |
| `deregisterSkill(string name)` | Removes the skill from the registry. Does not affect in-flight projects |

### Configuration

| Function | Default | Max |
|----------|---------|-----|
| `setProtocolFee(bps)` | 100 (1%) | 1000 (10%) |
| `setOriginationFee(bps)` | 200 (2%) | 500 (5%) |
| `setContributionFee(bps)` | 200 (2%) | 500 (5%) |
| `setValidationFee(bps)` | 200 (2%) | 500 (5%) |
| `setDecayRate(bps)` | 10 (0.1%/day) | 500 (5%/day) |
| `setDisputeBondBps(bps)` | 1000 (10%) | 5000 (50%) |
| `setOriginatorStakeRequirement(amount)` | 0 (disabled) | — |
| `setOriginatorReportBondBps(bps)` | 100 (1%) | 1000 (10%) |
| `setMinValidationStake(amount)` | 0 | — |
| `setTreasury(address)` | — | — |
| `setMinClaimAmount(amount)` | 0 | — |
| `setClaimCooldown(seconds)` | 0 | — |
| `setClaimDeadline(seconds)` | 1 day | 30 days |
| `setChallengePeriod(seconds)` | 1 day | 30 days |
| `setCommitDeadline(seconds)` | 1 day | 30 days |
| `setRevealDeadline(seconds)` | 1 day | 30 days |
| `setForceSettleDelay(seconds)` | 3 days | 90 days |
| `pause()` / `unpause()` | — | — |

## View Functions

| Function | Returns |
|----------|---------|
| `getProject(projectId)` | `Project` struct |
| `getClaim(claimId)` | `Claim` struct |
| `getValidationClaim(claimId)` | `ValidationClaim` struct |
| `getContribution(projectId, index)` | `Contribution` struct |
| `getReputation(user, key)` | `Reputation` struct (pass skill hash or originator role key) |
| `isSkillRegistered(skillId)` | `bool` — whether the skill hash is registered |
| `getPendingRewards(user, token)` | `uint256` pending balance |
| `getAdapterFees()` | Origination, contribution, validation BPS |
| `getOriginationAdapter(projectId)` | Adapter address |
| `getContributionAdapter(claimId)` | Adapter address |
| `getValidationAdapter(projectId, index, nonce, validator)` | Adapter address |
| `getDispute(projectId, index)` | `Dispute` struct (current nonce) |
| `getOriginatorReport(projectId)` | `OriginatorReport` struct |
| `getConsensusReport(projectId, index)` | `ConsensusReport` struct |
| `getSubmissionNonce(projectId, index)` | Current nonce |
| `getReturnStackTop(projectId)` | Stack height |
| `getProjectEscrow(projectId, token)` | Escrow balance |
| `getOriginatorLockedStake(projectId)` | Locked stake amount |
| `getDisputeConfig()` | Bond BPS, stake req, report bond BPS |
| `getCommitCount(projectId, index)` | Commit count for current nonce (reveals unlock when this equals `numberOfValidations`) |
| `getRevealCount(projectId, index)` | Reveal count for current nonce |
| `isValidatorOutlier(projectId, index, validator)` | `bool` |
| `isValidatorSettled(projectId, index, nonce, validator)` | `bool` |
| `vault()` | Vault address |
| `treasury()` | Treasury address |
| `claimDeadline()` / `challengePeriod()` / `commitDeadline()` / `revealDeadline()` / `forceSettleDelay()` | Current deadline values |

## Access Control

| Role | Permissions |
|------|------------|
| `DEFAULT_ADMIN_ROLE` | Fee configuration, treasury, deadlines, pause/unpause, upgrades |
| `OPERATOR_ROLE` | Project removal, dispute resolution, originator report resolution |

All other functions are permissionless (access controlled by on-chain state checks — e.g., only the originator can fund their project, only a claim owner can submit contributions).
