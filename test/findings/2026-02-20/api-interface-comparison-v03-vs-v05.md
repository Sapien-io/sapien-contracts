# v0.3 vs v0.5 API / Interface Comparison

**Date:** 2026-02-20
**Scope:** All contracts in `src/`
**Reference:** [v0.3 Technical Reference (docs site)](https://sapien-ai-docs-production.up.railway.app/v0.3/guides/technical-reference)

---

## 1. Architecture Delta

The most fundamental difference is contract topology.

**v0.3 (docs)** -- five contracts behind Transparent Proxies:

| Contract | Purpose |
|---|---|
| SapienCore | Central coordinator -- projects, contributions, finalization |
| SapienVault | ERC-4626 staking vault with locking and slashing |
| SapienTrust | Identity (stake-gated) and reputation (PoQ scores) |
| ValidationOracle | Commit-reveal validation and consensus orchestration |
| Rewards | Escrow and claim-based reward distribution |

**v0.5 (current)** -- two contracts with delegatecall libraries, UUPS Proxies, ERC-7201 storage:

| Contract | Purpose |
|---|---|
| QualityEngine | Merges Core, Trust, Oracle, and Rewards into one entry point |
| StakeVault | ERC-4626 vault with role-specific lock/slash functions |

Libraries: `ConsensusLib`, `ContributionLib`, `DisputeLib`, `FinalizationLib`, `OriginationLib`, `ReputationLib`, `ValidationLib`

### Summary of Structural Changes

| Aspect | v0.3 (docs) | v0.5 (current) |
|---|---|---|
| Contracts | 5 | 2 |
| Proxy pattern | Transparent Proxy | UUPS Proxy |
| Storage strategy | `__gap` arrays | ERC-7201 namespaced |
| Logic split | Cross-contract calls | delegatecall to libraries |
| Roles | SAPIEN_CORE_ROLE, LOCKER_ROLE, SLASHER_ROLE, UPDATER_ROLE, PAUSER_ROLE | ENGINE_ROLE, DEFAULT_ADMIN_ROLE, OPERATOR_ROLE |

---

## 2. Function Signature Comparison

### 2.1 Project Management

| v0.3 (SapienCore) | v0.5 (QualityEngine) | Delta |
|---|---|---|
| `createProject(bytes32, address, uint256, uint256, uint256, uint256, string)` | `createProject(bytes32 projectId, Project calldata config)` | Restructured -- v0.5 uses a config struct instead of positional args |
| `fundProject(bytes32, uint256, uint256)` | `fundProject(bytes32, uint256, uint256, address adapter)` | Added `adapter` param |
| `setClaimDeadlineDays(uint256)` | `setMinClaimAmount(uint64)` / `setClaimCooldown(uint64)` | Renamed / replaced |
| `setMaxValidations(uint256)` | _(per-project in Project struct)_ | Removed as global admin setter |
| `setProtocolFeeBasisPoints(uint256)` | `setProtocolFee(uint256 bps)` | Renamed |
| `setTreasury(address)` | `setTreasury(address)` | **Same** |
| -- | `setOriginationFee(uint256)`, `setContributionFee(uint256)`, `setValidationFee(uint256)` | New in v0.5 (adapter fee system) |
| -- | `setDecayRate(uint256)`, `setDisputeBondBps(uint256)`, `setOriginatorStakeRequirement(uint256)`, `setOriginatorReportBondBps(uint256)`, `setMinValidationStake(uint256)`, `setConsensusAlgorithm(address)` | New in v0.5 |

### 2.2 Contribution Lifecycle

| v0.3 | v0.5 | Delta |
|---|---|---|
| `claimToContribute(bytes32, uint256)` | `claimToContribute(bytes32, uint256, address adapter) returns (uint256, uint256[])` | Added adapter param and explicit return values |
| `contribute(bytes32, uint256, uint256, bytes32)` | `contribute(uint256 claimId, uint256 index, bytes32 submissionHash)` | Simplified -- dropped `projectId` (derived from claim) |
| `batchContribute(bytes32, uint256, uint256[], bytes32[])` | _(removed)_ | **Removed** |
| `releaseExpiredClaim(bytes32, uint256)` | `expireClaim(uint256 claimId, uint256[] indices)` | Merged with `reclaimExpiredIndices` |
| `reclaimExpiredIndices(bytes32, uint256[])` | _(merged into `expireClaim`)_ | **Removed** (merged) |

### 2.3 Validation (Commit-Reveal)

| v0.3 (ValidationOracle) | v0.5 (QualityEngine) | Delta |
|---|---|---|
| `setValidatorCapacity(uint256)` | `setValidatorCapacity(uint256)` | **Same** |
| -- | `reduceValidatorCapacity(uint256)` | New in v0.5 |
| `claimToValidate(bytes32, uint256)` | _(removed)_ | **Removed** -- validators commit directly |
| `commitValidation(bytes32, uint256, uint256, bytes32)` | `commitValidation(bytes32, uint256, bytes32, uint128)` | Changed -- dropped claimId, added explicit stakeAmount type |
| `revealValidation(bytes32, uint256, uint256, bytes32)` | `revealValidation(bytes32, uint256, uint16, bytes32)` | Changed -- score is uint16 not uint256 |
| `batchCommitValidations(...)` | _(removed)_ | **Removed** |
| `batchRevealValidations(...)` | _(removed)_ | **Removed** |
| `cancelExpiredValidationClaim(bytes32, uint256)` | _(removed)_ | **Removed** (no validation claims) |
| `cancelExpiredCommitment(bytes32, uint256, address)` | `cancelExpiredCommitment(bytes32, uint256, address)` | **Same** |
| `enqueueValidation(bytes32, uint256, uint256)` | _(internal / automatic)_ | Internalized |
| `registerProject(bytes32, uint256, string, address)` | _(internal / automatic)_ | Internalized |
| `setContributionContributor(bytes32, uint256, address)` | _(internal / automatic)_ | Internalized |
| `handleValidatorSlash(bytes32, uint256, address, uint256)` | _(internal / automatic)_ | Internalized |
| `resetContributionState(bytes32, uint256)` | _(internal / automatic)_ | Internalized |

### 2.4 Finalization

| v0.3 (SapienCore) | v0.5 (QualityEngine) | Delta |
|---|---|---|
| `finalizeContribution(bytes32, uint256)` | _(split into 3 steps)_ | Decomposed into separate operations |
| `batchFinalizeContributions(bytes32, uint256[])` | _(removed)_ | **Removed** |
| -- | `computeConsensus(bytes32, uint256)` | New -- step 1 of finalization |
| -- | `settleValidator(bytes32, uint256, uint256)` | New -- step 2 (per-validator) |
| -- | `forceSettleValidator(bytes32, uint256, uint256, address)` | New -- keeper fallback |
| -- | `releaseContributorReward(bytes32, uint256)` | New -- step 3 |
| -- | `completeProject(bytes32)` | New |
| -- | `refundEscrow(bytes32)` | New |

### 2.5 Rewards

| v0.3 (Rewards contract) | v0.5 (QualityEngine) | Delta |
|---|---|---|
| `claimRewards(bytes32, address)` | `claimReward(address token)` | Simplified -- no projectId needed |
| `claimAllRewards(address, bytes32[])` | _(removed)_ | **Removed** |
| `claimValidatorRewards(bytes32, address)` | _(merged into `claimReward`)_ | Merged |
| `claimAllValidatorRewards(address, bytes32[])` | _(removed)_ | **Removed** |
| `allocateRewards(bytes32, address, uint256)` | _(internal)_ | Internalized |
| `distributeReward(...)` / `distributeValidatorReward(...)` | _(internal)_ | Internalized |
| `emergencyWithdraw(address, address, uint256)` | _(removed)_ | **Removed** |
| `setCore(address)` | _(N/A -- single contract)_ | **Removed** |

### 2.6 Identity & Reputation (SapienTrust)

| v0.3 (SapienTrust) | v0.5 (QualityEngine) | Delta |
|---|---|---|
| `hasValidRole(address, bytes32)` | _(implicit in stake checks)_ | Internalized |
| `hasValidatedSkill(address, string)` | _(skill is bytes32 in Project.requiredSkill)_ | Changed type: `string` -> `bytes32` |
| `validateSkill(address, string)` | _(removed)_ | **Removed** |
| `getTrustScore(address, bytes32)` | `getReputation(address, bytes32) returns (Reputation)` | Renamed / restructured |
| `updateReputation(address, bytes32, bool, uint256)` | _(internal via ReputationLib)_ | Internalized |
| `hasRequiredStake(address)` | _(implicit)_ | Internalized |
| `minStakeRequired()` / `roleMinStake(bytes32)` | _(per-project via Project struct)_ | Moved to project config |

### 2.7 Vault

| v0.3 (SapienVault) | v0.5 (StakeVault) | Delta |
|---|---|---|
| `lockStake(address, uint256, string)` | `lockContributor(address, uint256)` / `lockValidatorCapacity(address, uint256)` | Split by role, dropped reason string |
| `unlockStake(address, uint256, string)` | `unlockContributor(address, uint256)` / `unlockValidatorCapacity(address, uint256)` | Split by role |
| `slash(address, uint256, bytes32)` | `slashContributor(address, uint256)` / `slashValidator(address, uint256)` | Split by role, dropped projectId |
| `getStake(address)` | `totalStaked(address)` | Renamed |
| `getAvailableStake(address)` | `availableBalance(address)` | Renamed |
| `getLockedStake(address)` | `getStakeAccount(address) returns (StakeAccount)` | Restructured -- returns full account |
| `totalStaked()` (global) | _(via ERC4626 `totalAssets()`)_ | Inherited |
| `stakingToken()` | _(via ERC4626 `asset()`)_ | Inherited |
| -- | `commitStake(address, uint256)` / `releaseCommit(address, uint256)` | New -- in-flight tracking |
| -- | `slashAndUnlockContributor(address, uint256, uint256)` | New -- atomic operation |

### 2.8 Disputes (entirely new in v0.5)

No v0.3 equivalent exists for:

- `openDispute(bytes32, uint256, bytes32)`
- `resolveDispute(bytes32, uint256, bool)`
- `escalateDispute(bytes32, uint256)`
- `reportOriginator(bytes32, bytes32)`
- `resolveOriginatorReport(bytes32, bool)`
- `escalateOriginatorReport(bytes32)`

---

## 3. Event Comparison

### Renamed / Restructured Events

| v0.3 | v0.5 | Notes |
|---|---|---|
| `ClaimCreated(projectId, claimId, contributor, quantity)` | `ClaimCreated(claimId, projectId, claimant, indices[])` | Index order changed; `indices[]` replaces `quantity` |
| `ClaimExpired(projectId, claimId, contributor, slashedAmount)` | `ClaimExpired(claimId, unsubmittedCount)` | Simplified |
| `ContributionFinalized(projectId, index, status, finalScore)` | Split into `ConsensusReached`, `ValidatorSettled`, `ContributorRewardReleased` | Decomposed into three events |
| `Slashed(user, sharesSlashed, assetsSlashed, slasher, projectId)` | `ContributorSlashed(user, amount)` / `ValidatorSlashed(user, amount)` | Split by role |
| `StakeLocked(user, amount, locker, reason)` | `ContributorLocked(user, amount)` / `ValidatorCapacityLocked(user, amount)` | Split by role |
| `StakeUnlocked(user, amount, locker, reason)` | `ContributorUnlocked(user, amount)` / `ValidatorCapacityUnlocked(user, amount)` | Split by role |
| `ReputationUpdated(user, role, oldScore, newScore)` | `ReputationUpdated(user, role, oldScore, newScore)` | **Same** |

### Events Removed (present in v0.3 only)

- `IndexAssigned`, `IndexReclaimed`, `ContributorRewardPreserved`
- `ProtocolFeeCollected`, `MaxValidationsUpdated`
- `SkillValidated`, `ReputationDecayUpdated`, `MinStakeRequiredUpdated`, `RoleMinStakeUpdated`
- `ValidationClaimed` (with deadline param)
- `AlgorithmRegistered`, `ProjectAlgorithmUpdated`, `ProjectMaxValidationsUpdated`
- `ProjectRequiredSkillUpdated`, `ProjectOriginatorUpdated`
- `ContributionContributorUpdated`, `RevealDeadlineUpdated`, `RevealGracePeriodUpdated`
- `ProjectRevealDeadlineUpdated`, `IndexAssignedToValidator`
- `ValidatorSlashedForExpiredClaim`, `ValidatorCapacityUpdated`
- `RewardsAllocated`, `RewardsDistributed`, `RewardsClaimed`, `CoreAddressUpdated`

### Events Added (v0.5 only)

- `StakeCommitted`, `CommitReleased`
- `OriginationFeePaid`, `ContributionAdapterFeePaid`, `ValidationAdapterFeePaid`
- `DisputeOpened`, `DisputeResolved`, `DisputeEscalated`
- `OriginatorReported`, `OriginatorReportResolved`, `OriginatorReportEscalated`
- `ProjectCancelled`, `ProjectCompleted`, `EscrowRefunded`
- `OriginationFeeUpdated`, `ContributionFeeUpdated`, `ValidationFeeUpdated`, `DecayRateUpdated`
- `DisputeBondBpsUpdated`, `OriginatorStakeRequirementUpdated`, `OriginatorReportBondBpsUpdated`
- `MinValidationStakeUpdated`, `MinContributorStakeUpdated`, `ConsensusAlgorithmUpdated`
- `MinClaimAmountUpdated`, `ClaimCooldownUpdated`

---

## 4. Error Comparison

### Renamed / Restructured Errors

| v0.3 | v0.5 | Notes |
|---|---|---|
| `Unauthorized()` | `NotProjectOriginator()`, `NotClaimOwner()`, `CannotValidateOwnContribution()`, `CannotDisputeOwnContribution()` | Split into specific errors |
| `ClaimNotActive(claimId)` | `ClaimDeadlinePassed()` / `ClaimDeadlineNotPassed()` | |
| `ClaimAlreadyExpired(claimId, deadline)` | `ClaimDeadlinePassed()` | |
| `CapacityReached()` | `NoSlotsAvailable()` | |
| `ProjectAlreadyExists(projectId)` | checked via `InvalidProjectConfig(string)` | |
| `ProjectDoesNotExist(projectId)` | `ProjectNotFunded()` / `ProjectNotActive()` | State-specific |
| `InvalidAddress()` | `ZeroAddress()` | |
| `InvalidAmount()` | `ZeroAmount()` | |
| `InsufficientContributorStake(contributor, required, actual)` | `InsufficientStake(required, available)` | Simplified params |
| `InsufficientQuantityAvailable(projectId, requested, available)` | `NoSlotsAvailable()` / `ClaimQuantityTooHigh(requested, max)` | |
| `ContributionAlreadySubmitted(index)` | checked via `IndexNotReserved()` | |
| `AlreadyRewarded()` | `RewardAlreadyReleased()` | Renamed |
| `MissingRequiredSkill(user, requiredSkill)` | `InsufficientReputation(required, actual)` | |
| `InsufficientUnlockedStake(user, req, avail)` | `InsufficientAvailableBalance(required, available)` | |
| `InsufficientLockedStake(user, req, avail)` | `InsufficientContributorLock(required, locked)` | |
| `NoSharesToSlash(user)` | _(removed -- handled by amount checks)_ | |
| `AlreadyCommitted(validator)` | `AlreadyCommitted()` | Dropped param |
| `NoUnrevealedCommit()` | `NotCommitted()` | Renamed |
| `InvalidStakeAmount()` | `ZeroAmount()` | |
| `OnlyCore()` | _(N/A -- single contract)_ | |
| `NoRewardsToClaim()` | `NoRewardToClaim()` | Renamed |
| `TransferFailed()` | _(uses SafeERC20)_ | |

### Errors Added (v0.5 only)

`OriginatorCannotContribute`, `IndexNotInClaim`, `ConsensusNotReady`, `ConsensusAlreadyComputed`, `AlreadySettled`, `ChallengeNotElapsed`, `InvalidReveal`, `NonceMismatch`, `AdapterFeeTooHigh`, `InvalidProjectConfig`, `InvalidIndex`, `IndexNotReserved`, `IndexNotSubmitted`, `RevealWindowClosed`, `ContributionNotAccepted`, `ClaimAmountTooSmall`, `ClaimCooldownActive`, `InvalidScore`, `AlreadyRevealed`, `ValidationNotClaimed`, `InvalidCommitHash`, `ProjectNotCompleted`, `ProjectHasActivePipeline`, `ForceSettleTooEarly`, `InvalidEvidenceHash`, `DisputeAlreadyOpen`, `DisputeAlreadyClosed`, `DisputeNotOpen`, `DisputeWindowClosed`, `DisputeInProgress`, `DisputeResolutionNotExpired`, `ConsensusNotComputed`, `DisputeBondTooHigh`, `OriginatorReportAlreadyOpen`, `OriginatorReportNotOpen`, `ProjectNotCancellable`

---

## 5. Type / Struct Comparison

| v0.3 | v0.5 | Notes |
|---|---|---|
| `Project { projectId, originator, rewardToken, state, config }` (nested) | `Project { originator, rewardToken, totalRewards, ... }` (flat) | Flattened -- no nested ProjectConfig/ProjectState |
| `ProjectConfig` (7 fields) | _(folded into Project)_ | Removed |
| `ProjectState` (6 mutable counters) | _(folded into Project)_ | Removed |
| `Claim { contributor, quantity, ... }` | `Claim { claimant, projectId, deadline, submittedCount, totalCount, status }` | Renamed fields, added `projectId` |
| `ClaimStatus { Active, Fulfilled, Expired, Cancelled }` | `ClaimStatus { Active, Completed, Expired }` | `Fulfilled` -> `Completed`, removed `Cancelled` |
| `ContributionStatus { Pending, Validated, Rewarded, Rejected }` | `ContributionStatus { Pending, Accepted, Rejected }` | `Validated`/`Rewarded` collapsed to `Accepted` |
| `ValidationClaim` | _(removed)_ | No validation claim concept in v0.5 |
| `Contribution` (9 fields) | `Contribution` (10 fields -- adds `rewardRate`, `challengeEndsAt`, `consensusNonce`) | Restructured |
| `ValidationCommit` (4 fields) | `ValidatorCommit` (7 fields -- adds `stakedAmount`, `revealedAt`, `score`, `settled`) | Expanded |
| `Validation` (separate struct) | _(merged into `ValidatorCommit`)_ | Merged |
| `UserReputation` (4 fields) | `Reputation` (6 fields -- adds `dailyGain`, `dailyGainDate`) | Expanded |
| `ConsensusReport` (5 fields) | `ConsensusReport` (5 different fields) | Restructured |
| `SkillInfo`, `ContributorStats`, `ProjectContributionStats`, `IndexReservation` | _(removed)_ | Removed |
| -- | `StakeAccount`, `Dispute`, `OriginatorReport`, `ValidatorConsensusResult`, `IndexRange`, `ValidationCounters` | New in v0.5 |

### Enum Comparison

| v0.3 | v0.5 | Notes |
|---|---|---|
| `ClaimStatus { Active, Fulfilled, Expired, Cancelled }` | `ClaimStatus { Active, Completed, Expired }` | `Fulfilled` -> `Completed`; `Cancelled` removed |
| `ContributionStatus { Pending, Validated, Rewarded, Rejected }` | `ContributionStatus { Pending, Accepted, Rejected }` | Simplified |
| -- | `ProjectStatus { Created, Funded, Active, Completed, Cancelled }` | New in v0.5 |
| -- | `SubmissionStatus { Empty, Reserved, Submitted, Accepted, Rejected }` | New in v0.5 |
| -- | `DisputeStatus { None, Open, Upheld, Rejected }` | New in v0.5 |
| -- | `OriginatorReportStatus { None, Open, Upheld, Rejected }` | New in v0.5 |

---

## 6. Consensus Algorithm Comparison

| Aspect | v0.3 | v0.5 |
|---|---|---|
| Interface function | `calculateConsensus(ValidationInput[])` | `calculate(ValidationInput[])` | Renamed |
| Metadata functions | `getName()`, `getSecurityGrade()`, `getDescription()` | _(removed)_ |
| Implementations | LinearStake, CappedLinear, SqrtStake, Hybrid | Single `ConsensusLib` library |
| Registration | Dynamic via `registerAlgorithm(string, address)` | Single address via `setConsensusAlgorithm(address)` |
| `ValidationInput` fields | `validator, score(0-10000), stakeAmount, reputation(0-10000)` | `validator, score(uint16), stakeAmount(uint128), reputation(uint256)` |
| `ConsensusResult` fields | `weightedAverage, stdDev, validatorsToSlash[], slashAmounts[], validatorWeights[]` | `weightedAverage, stdDeviation, validators[], isOutlier[], slashAmounts[], weights[], totalAccurateWeight` |

---

## 7. Alignment Strategy Options

### Option A: Update docs to match v0.5 (minimal code changes)

Keep the 2-contract + libraries architecture. Update the documentation to describe the current code. Optionally restore v0.3 naming where it improves clarity.

**Pros:** No contract refactoring risk, keeps gas-efficient library approach.
**Cons:** Documentation is a full rewrite.

### Option B: Restore v0.3 naming in v0.5 code

Rename contracts and key functions to match v0.3 conventions:

| Current (v0.5) | Suggested (v0.3-aligned) |
|---|---|
| `QualityEngine` | `SapienCore` |
| `StakeVault` | `SapienVault` |
| `availableBalance()` | `getAvailableStake()` |
| `totalStaked()` | `getStake()` |
| `claimant` (Claim struct) | `contributor` |
| `ClaimStatus.Completed` | `ClaimStatus.Fulfilled` |

**Pros:** Brand consistency, existing integrators recognize the API.
**Cons:** Moderate refactor, test updates.

### Option C: Restore v0.3 batch operations in v0.5

Re-add batch functions that were removed:

- `batchContribute`
- `batchCommitValidations` / `batchRevealValidations`
- `batchFinalizeContributions` (or batch `settleValidator`)

**Pros:** Gas efficiency for high-volume usage.
**Cons:** Code surface area increase.

### Option D: Restore `claimToValidate` flow

Re-introduce the validation claim concept from v0.3 where validators claim slots before committing.

**Pros:** Prevents front-running, provides assignment guarantees.
**Cons:** Adds complexity, extra storage.

---

## 8. Key Decisions Required

1. **Contract naming**: Keep `QualityEngine`/`StakeVault` or revert to `SapienCore`/`SapienVault`?
2. **Batch operations**: Should we restore `batchContribute`, `batchCommit`, `batchReveal`, `batchFinalize`?
3. **Validation claims**: Should validators go through a claim step before committing?
4. **Finalization model**: Keep the decomposed 3-step finalization (computeConsensus -> settleValidator -> releaseReward) or return to single `finalizeContribution`?
5. **Dispute system**: This is entirely new in v0.5 -- should the docs simply be updated to include it, or does it need redesign?
6. **Consensus algorithms**: Restore the pluggable multi-algorithm system from v0.3, or keep the single-algorithm approach in v0.5?
