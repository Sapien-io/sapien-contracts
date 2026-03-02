# Sapien PoQ Protocol — Contracts and Interfaces Reference

**Version:** v0.5
**Last Updated:** February 2026

This document provides a comprehensive reference for all smart contracts, libraries, and interfaces in the Sapien PoQ Protocol v0.5.

---

## Table of Contents

1. [Contract Topology](#contract-topology)
2. [Core Contracts](#core-contracts)
   - [SapienCore](#sapiencore)
   - [SapienVault](#sapienvault)
3. [Libraries](#libraries)
   - [OriginationLib](#originationlib)
   - [ContributionLib](#contributionlib)
   - [ValidationLib](#validationlib)
   - [ConsensusLib](#consensuslib)
   - [FinalizationLib](#finalizationlib)
   - [DisputeLib](#disputelib)
   - [ReputationLib](#reputationlib)
4. [Interfaces](#interfaces)
   - [ISapienCore](#isapiencore)
   - [ISapienVault](#isapienvault)
5. [Shared Types](#shared-types)
6. [Constants](#constants)
7. [Access Control](#access-control)
8. [Storage Layout](#storage-layout)

---

## Contract Topology

v0.5 consolidates the protocol into two deployable contracts with seven libraries:

```
SapienCore (UUPS Proxy — unified entry-point)
├── OriginationLib    (project creation & funding)
├── ContributionLib   (claim & contribute)
├── ValidationLib     (commit-reveal & consensus orchestration)
├── ConsensusLib      (stake-weighted consensus algorithm)
├── FinalizationLib   (settlement, rewards, project completion)
├── DisputeLib        (disputes & originator reports)
├── ReputationLib     (PoQ reputation with lazy decay)
└── SapienVault ──── (ERC-4626 staking with typed locks)
```

All libraries operate on SapienCore's ERC-7201 namespaced storage via `DELEGATECALL`. The only external contract call is from SapienCore → SapienVault for stake operations.

---

## Core Contracts

### SapienCore

**File:** `src/SapienCore.sol`

**Inheritance:** `AccessControlUpgradeable`, `PausableUpgradeable`, `ReentrancyGuardUpgradeable`, `UUPSUpgradeable`, `ISapienCore`

**Description:** Unified contract for the Sapien PoQ protocol — project management, claims, contributions, validations, consensus, reputation, and reward distribution. Deployed behind an ERC-1967 proxy with ERC-7201 namespaced storage.

#### `initialize`
```solidity
function initialize(address admin_, address vault_, address treasury_) external initializer
```
Initializes the contract with admin, vault, and treasury addresses. Sets default fee rates and deadlines.

#### Origination Functions

```solidity
function createProject(bytes32 projectId, string calldata metadataCid, Project calldata config) external
```
Register a new project. The caller becomes the originator. Project starts in `Created` status.

```solidity
function fundProject(bytes32 projectId, uint256 amount, uint256 quantity, address adapter) external
```
Fund a project with reward tokens and create contribution slots. Deducts protocol fee, optional origination adapter fee, and locks originator stake if required.

```solidity
function removeProject(bytes32 projectId) external  // OPERATOR_ROLE only
```
Remove a project, slash originator stake, cancel the project.

#### Contribution Functions

```solidity
function claimToContribute(bytes32 projectId, uint256 quantity, address adapter)
    external returns (uint256 claimId, uint256[] memory indices)
```
Claim contribution slots. Locks contributor stake. Returns claim ID and assigned indices.

```solidity
function contribute(uint256 claimId, uint256 index, bytes32 submissionHash, string calldata dataCid) external
```
Submit work for a single claimed slot. Transitions slot from Reserved → Pending.

```solidity
function batchContribute(
    uint256 claimId, uint256[] calldata indices,
    bytes32[] calldata submissionHashes, string[] calldata dataCids
) external
```
Batch version of `contribute`.

```solidity
function expireClaim(uint256 claimId, uint256[] calldata indices) external
```
Expire a claim after deadline. Returns unsubmitted slots, slashes contributor.

#### Validation Functions

```solidity
function lockValidatorCapacity(uint256 amount) external
function unlockValidatorCapacity(uint256 amount) external
```
Lock/unlock tokens as validator capacity.

```solidity
function claimToValidate(bytes32 projectId, uint256 quantity)
    external returns (uint256 claimId)
```
Specify how many contributions to validate; the protocol randomly assigns from pending contributions. Anti-collusion: validators cannot choose which contributions to validate. 1-hour deadline to commit.

```solidity
function commitValidation(
    bytes32 projectId, uint256 index, bytes32 commitHash,
    uint256 stakeAmount, address adapter
) external
```
Commit a sealed validation score. `commitHash = keccak256(abi.encodePacked(uint16(score), salt))`.

```solidity
function batchCommitValidations(
    bytes32 projectId, uint256[] calldata indices,
    bytes32[] calldata commitHashes, uint256[] calldata stakeAmounts, address adapter
) external
```
Batch version of `commitValidation`.

```solidity
function revealValidation(bytes32 projectId, uint256 index, uint256 score, bytes32 salt) external
```
Reveal a committed score. Score range: 0–10,000. Reverts with `CommitPhaseIncomplete` until all required validators have committed.

```solidity
function batchRevealValidations(
    bytes32 projectId, uint256[] calldata indices,
    uint256[] calldata scores, bytes32[] calldata salts
) external
```
Batch version of `revealValidation`.

```solidity
function cancelExpiredValidationClaim(uint256 claimId) external
```
Cancel a validation claim after the 1-hour deadline.

#### Finalization Functions

```solidity
function computeConsensus(bytes32 projectId, uint256 index) external
```
Compute stake-weighted consensus. Sets contribution to Accepted/Rejected.

```solidity
function settleValidator(bytes32 projectId, uint256 index, uint256 nonce) external
```
Settle a validator's stake and rewards after consensus.

```solidity
function forceSettleValidator(
    bytes32 projectId, uint256 index, uint256 nonce, address validator
) external
```
Force-settle an unresponsive validator after `forceSettleDelay`.

```solidity
function releaseContributorReward(bytes32 projectId, uint256 index) external
```
Release contributor reward after challenge period.

```solidity
function claimReward(address token) external
```
Withdraw accumulated pending rewards.

```solidity
function cancelExpiredCommitment(bytes32 projectId, uint256 index, address validator) external
```
Slash a validator who committed but failed to reveal.

#### Dispute Functions

```solidity
function openDispute(
    bytes32 projectId, uint256 index, bytes32 evidenceHash, string calldata evidenceCid
) external
```
Open a dispute during the challenge period. Requires bond.

```solidity
function resolveDispute(bytes32 projectId, uint256 index, bool upheld) external  // OPERATOR_ROLE
```
Resolve an open dispute.

```solidity
function escalateDispute(bytes32 projectId, uint256 index) external
```
Auto-uphold after resolution deadline (7 days).

#### Originator Report Functions

```solidity
function reportOriginator(bytes32 projectId, bytes32 evidenceHash) external
```
Report an originator for misconduct. Requires bond.

```solidity
function resolveOriginatorReport(bytes32 projectId, bool upheld) external  // OPERATOR_ROLE
```
Resolve an originator report.

```solidity
function escalateOriginatorReport(bytes32 projectId) external
```
Auto-uphold after resolution deadline.

#### Project Completion Functions

```solidity
function completeProject(bytes32 projectId) external
```
Mark project as completed. Unlocks originator stake.

```solidity
function refundEscrow(bytes32 projectId) external
```
Refund remaining escrow after 30-day grace period.

#### Admin Functions

All require `DEFAULT_ADMIN_ROLE`:

```solidity
function setProtocolFee(uint256 bps) external        // max 1000 (10%)
function setOriginationFee(uint256 bps) external      // max 500 (5%)
function setContributionFee(uint256 bps) external     // max 500 (5%)
function setValidationFee(uint256 bps) external       // max 500 (5%)
function setDecayRate(uint256 bps) external            // max 500 (5%/day)
function setDisputeBondBps(uint256 bps) external       // max 5000 (50%)
function setOriginatorStakeRequirement(uint256 amount) external
function setOriginatorReportBondBps(uint256 bps) external  // max 1000 (10%)
function setMinValidationStake(uint256 amount) external
function setTreasury(address treasury_) external
function setMinClaimAmount(uint256 amount) external
function setClaimCooldown(uint256 cooldown) external
function setClaimDeadline(uint256 deadline) external   // max 30 days
function setChallengePeriod(uint256 period) external   // max 30 days
function setCommitDeadline(uint256 deadline) external  // max 30 days
function setRevealDeadline(uint256 deadline) external  // max 30 days
function setForceSettleDelay(uint256 delay) external   // max 90 days
function pause() external
function unpause() external
```

#### View Functions

```solidity
function getProject(bytes32 projectId) external view returns (Project memory)
function getClaim(uint256 claimId) external view returns (Claim memory)
function getValidationClaim(uint256 claimId) external view returns (ValidationClaim memory)
function getContribution(bytes32 projectId, uint256 index) external view returns (Contribution memory)
function getReputation(address user, bytes32 role) external view returns (Reputation memory)
function getPendingRewards(address user, address token) external view returns (uint256)
function getAdapterFees() external view returns (uint256, uint256, uint256)
function getOriginationAdapter(bytes32 projectId) external view returns (address)
function getContributionAdapter(uint256 claimId) external view returns (address)
function getValidationAdapter(bytes32 projectId, uint256 index, uint256 nonce, address validator)
    external view returns (address)
function getDispute(bytes32 projectId, uint256 index) external view returns (Dispute memory)
function getOriginatorReport(bytes32 projectId) external view returns (OriginatorReport memory)
function getConsensusReport(bytes32 projectId, uint256 index) external view returns (ConsensusReport memory)
function getSubmissionNonce(bytes32 projectId, uint256 index) external view returns (uint256)
function getReturnStackTop(bytes32 projectId) external view returns (uint256)
function getProjectEscrow(bytes32 projectId, address token) external view returns (uint256)
function getOriginatorLockedStake(bytes32 projectId) external view returns (uint256)
function getDisputeConfig() external view returns (uint256, uint256, uint256)
function getRevealCount(bytes32 projectId, uint256 index) external view returns (uint256)
function isValidatorOutlier(bytes32 projectId, uint256 index, address validator) external view returns (bool)
function isValidatorSettled(bytes32 projectId, uint256 index, uint256 nonce, address validator)
    external view returns (bool)
function vault() external view returns (address)
function treasury() external view returns (address)
function claimDeadline() external view returns (uint256)
function challengePeriod() external view returns (uint256)
function commitDeadline() external view returns (uint256)
function revealDeadline() external view returns (uint256)
function forceSettleDelay() external view returns (uint256)
```

---

### SapienVault

**File:** `src/SapienVault.sol`

**Inheritance:** `ERC4626Upgradeable`, `AccessControlUpgradeable`, `PausableUpgradeable`, `UUPSUpgradeable`, `ISapienVault`

**Description:** ERC-4626 vault for SAPIEN token staking with typed lock categories (contributor locks, validator capacity, in-flight stakes). Tracks deposit timestamps for min-deposit-age checks (anti-flash-staking). Uses ERC-7201 namespaced storage (`sapien.storage.StakeVault`).

#### `initialize`
```solidity
function initialize(IERC20 asset_, address admin_) external initializer
```
Initializes the vault with the staking token and admin address. Share token is named "Sapien Vault Token" (vSAPIEN).

#### Contributor Operations (ENGINE_ROLE)

```solidity
function lockContributor(address user, uint256 amount) external
function unlockContributor(address user, uint256 amount) external
function slashContributor(address user, uint256 amount) external
function slashAndUnlockContributor(address user, uint256 slashAmount, uint256 unlockAmount) external
```

#### Validator Operations (ENGINE_ROLE)

```solidity
function lockValidatorCapacity(address user, uint256 amount) external   // requires deposit age >= minDepositAge (if set)
function unlockValidatorCapacity(address user, uint256 amount) external
function commitStake(address user, uint256 amount) external
function releaseCommit(address user, uint256 amount) external
function slashValidator(address user, uint256 amount) external
```

#### Admin Functions (DEFAULT_ADMIN_ROLE)

```solidity
function setMinDepositAge(uint256 age) external   // max 7 days; 0 = disabled
```

#### View Functions

```solidity
function getStakeAccount(address user) external view returns (StakeAccount memory)
function minDepositAge() external view returns (uint256)
function availableBalance(address user) public view returns (uint256)
function totalStaked(address user) external view returns (uint256)
function maxRedeem(address owner) public view returns (uint256)
function maxWithdraw(address owner) public view returns (uint256)
function maxDeposit(address) public view returns (uint256)
function maxMint(address) public view returns (uint256)
function verifyStorageLocation() external pure returns (bool)
```

#### Events

```solidity
event ContributorLocked(address indexed user, uint256 amount)
event ContributorUnlocked(address indexed user, uint256 amount)
event ContributorSlashed(address indexed user, uint256 amount)
event ValidatorCapacityLocked(address indexed user, uint256 amount)
event ValidatorCapacityUnlocked(address indexed user, uint256 amount)
event StakeCommitted(address indexed user, uint256 amount)
event CommitReleased(address indexed user, uint256 amount)
event ValidatorSlashed(address indexed user, uint256 amount)
event MinDepositAgeUpdated(uint256 newAge)
```

#### Errors

```solidity
error InsufficientAvailableBalance(uint256 required, uint256 available)
error InsufficientContributorLock(uint256 required, uint256 locked)
error InsufficientValidatorCapacity(uint256 required, uint256 capacity)
error InsufficientInFlight(uint256 required, uint256 inFlight)
error TransferExceedsUnlockedShares()
error DepositTooRecent(uint256 required, uint256 actual)
error MinDepositAgeTooHigh(uint256 requested, uint256 max)
error ZeroAmount()
error ZeroAddress()
```

---

## Libraries

### OriginationLib

**File:** `src/libraries/OriginationLib.sol`

Handles project creation, funding, and operator removal. Validates project configuration, transfers tokens, deducts protocol and adapter fees, locks originator stake, and initializes index ranges.

**Functions:** `createProject`, `fundProject`, `removeProject`

### ContributionLib

**File:** `src/libraries/ContributionLib.sol`

Manages contribution claims and submissions. Uses a range + return-stack hybrid for slot allocation. Locks contributor stake on claim, tracks pending contributions, slashes unsubmitted slots on expiration.

**Functions:** `claimToContribute`, `contribute`, `batchContribute`, `expireClaim`

### ValidationLib

**File:** `src/libraries/ValidationLib.sol`

Manages validator capacity, validation claims, commit-reveal scoring, and consensus computation. Enforces reputation checks, minimum stake requirements, and commit-reveal hash verification.

**Functions:** `lockValidatorCapacity`, `unlockValidatorCapacity`, `claimToValidate`, `commitValidation`, `batchCommitValidations`, `revealValidation`, `batchRevealValidations`, `cancelExpiredValidationClaim`, `computeConsensus`

### ConsensusLib

**File:** `src/libraries/ConsensusLib.sol`

Pure library implementing stake-weighted consensus with outlier detection and tiered slashing. Weight = `sqrt(stake) × max(reputation, 100)`.

**Tiered Slashing:**

| Tier | Deviation | Slash |
|------|-----------|-------|
| 1 | > 1.5σ | 10% |
| 2 | > 2.0σ | 25% |
| 3 | > 3.0σ | 50% |
| 4 | > 5.0σ | 100% |

**Functions:** `calculate`

### FinalizationLib

**File:** `src/libraries/FinalizationLib.sol`

Handles validator settlement, contributor reward release, reward claiming, expired commitment cleanup, project completion, and escrow refunds. Applies adapter fee deductions during settlement.

**Functions:** `settleValidator`, `forceSettleValidator`, `releaseContributorReward`, `claimReward`, `cancelExpiredCommitment`, `completeProject`, `refundEscrow`

### DisputeLib

**File:** `src/libraries/DisputeLib.sol`

Manages dispute opening, resolution (uphold/reject), and originator accountability reports. Disputes are keyed by nonce to prevent cross-nonce poisoning. Handles bond locking/slashing and challenger rewards.

**Functions:** `openDispute`, `upholdDispute`, `rejectDispute`, `reportOriginator`, `upholdOriginatorReport`, `rejectOriginatorReport`

### ReputationLib

**File:** `src/libraries/ReputationLib.sol`

Implements PoQ reputation with lazy decay and daily gain caps. Scores range from 500–10,000 (default 5,000). Success gives +10 (+ bonus), failure gives -50. Max daily gain: 100.

**Functions:** `getScore`, `getScoreCached`, `update`

---

## Interfaces

### ISapienCore

**File:** `src/interfaces/ISapienCore.sol`

Complete interface for SapienCore covering origination, contribution, validation, finalization, disputes, originator reports, project completion, admin, and view functions. Defines all protocol errors (60+) and events (40+), including `NoEligibleContributions` (reverted when `claimToValidate` finds no eligible pending contributions for random assignment).

### ISapienVault

**File:** `src/interfaces/ISapienVault.sol`

Interface for SapienVault defining contributor lock/unlock/slash operations, validator capacity/commit/release/slash operations, and view functions.

---

## Shared Types

**File:** `src/Types.sol`

### Enums

| Enum | Values |
|------|--------|
| `ProjectStatus` | Created, Funded, Active, Completed, Cancelled |
| `ClaimStatus` | Active, Completed, Expired |
| `ContributionStatus` | Empty, Reserved, Pending, Accepted, Rejected |
| `DisputeStatus` | None, Open, Upheld, Rejected |
| `OriginatorReportStatus` | None, Open, Upheld, Rejected |
| `ValidationClaimStatus` | Active, Fulfilled, Expired |

### Core Structs

#### `Project`
```solidity
struct Project {
    address originator;
    address rewardToken;
    uint256 totalRewards;
    uint256 totalQuantity;
    uint256 availableSlots;
    uint256 minStakeToClaim;
    uint256 minValidationStake;
    bytes32 requiredSkill;
    uint256 consensusThreshold;      // basis points (e.g. 7000 = 70%)
    uint256 validatorRewardBps;      // 0–2500
    uint256 numberOfValidations;
    uint256 minValidatorReputation;
    ProjectStatus status;
    uint256 activatedAt;
    uint256 completedAt;
}
```

#### `Claim`
```solidity
struct Claim {
    address claimant;
    bytes32 projectId;
    uint256 deadline;
    uint256 submittedCount;
    uint256 totalCount;
    ClaimStatus status;
}
```

#### `Contribution`
```solidity
struct Contribution {
    address contributor;
    uint256 claimId;
    ContributionStatus status;
    bool rewardReleased;
    bytes32 submissionHash;
    uint256 rewardRate;
    uint256 submittedAt;
    uint256 challengeEndsAt;
    uint256 consensusNonce;
}
```

#### `Reputation`
```solidity
struct Reputation {
    uint256 score;
    uint256 totalActions;
    uint256 successfulActions;
    uint256 lastUpdated;
    uint256 dailyGain;
    uint256 dailyGainDate;
}
```

#### `StakeAccount`
```solidity
struct StakeAccount {
    uint256 contributorLock;
    uint256 validatorCapacity;
    uint256 inFlight;
}
```

#### `ValidationClaim`
```solidity
struct ValidationClaim {
    address validator;
    bytes32 projectId;
    uint256[] indices;
    uint256 deadline;
    uint256 committedCount;
    uint256 totalCount;
    ValidationClaimStatus status;
}
```

#### `ValidatorCommit`
```solidity
struct ValidatorCommit {
    bytes32 commitHash;
    uint256 stakedAmount;
    uint256 commitTimestamp;
    uint256 revealedAt;
    uint256 score;
    bool claimed;
    bool settled;
    uint256 validationClaimId;
    address adapter;
}
```

#### `Dispute`
```solidity
struct Dispute {
    address challenger;
    uint256 openedAt;
    DisputeStatus status;
    uint256 bondAmount;
    uint256 resolvedAt;
    bytes32 evidenceHash;
}
```

#### `OriginatorReport`
```solidity
struct OriginatorReport {
    address reporter;
    uint256 reportedAt;
    OriginatorReportStatus status;
    uint256 bondAmount;
    uint256 resolvedAt;
    bytes32 evidenceHash;
}
```

#### `ConsensusReport`
```solidity
struct ConsensusReport {
    uint256 weightedAverage;
    uint256 stdDeviation;
    uint256 totalAccurateWeight;
    uint256 nonce;
    bool computed;
}
```

#### `ValidatorConsensusResult`
```solidity
struct ValidatorConsensusResult {
    bool isOutlier;
    uint256 slashAmount;
    uint256 weight;
}
```

#### `ValidationInput` / `ConsensusResult`
```solidity
struct ValidationInput {
    address validator;
    uint256 score;
    uint256 stakeAmount;
    uint256 reputation;
}

struct ConsensusResult {
    uint256 weightedAverage;
    uint256 stdDeviation;
    address[] validators;
    bool[] isOutlier;
    uint256[] slashAmounts;
    uint256[] weights;
    uint256 totalAccurateWeight;
}
```

---

## Constants

**File:** `src/Constants.sol`

### Roles
| Constant | Value |
|----------|-------|
| `OPERATOR_ROLE` | `keccak256("OPERATOR_ROLE")` |

### Limits
| Constant | Value |
|----------|-------|
| `MAX_CLAIM_QUANTITY` | 20 |
| `MAX_NUMBER_OF_VALIDATIONS` | 10 |
| `BPS` | 10,000 |

### Fee Caps (BPS)
| Constant | Value | Percentage |
|----------|-------|------------|
| `MAX_PROTOCOL_FEE_BPS` | 1000 | 10% |
| `MAX_ADAPTER_FEE_BPS` | 500 | 5% |
| `MAX_VALIDATOR_REWARD_BPS` | 2500 | 25% |

### Default Deadlines
| Constant | Value |
|----------|-------|
| `DEFAULT_CHALLENGE_PERIOD` | 1 day |
| `DEFAULT_CLAIM_DEADLINE` | 1 day |
| `DEFAULT_COMMIT_DEADLINE` | 1 day |
| `DEFAULT_REVEAL_DEADLINE` | 1 day |
| `DEFAULT_FORCE_SETTLE_DELAY` | 3 days |
| `VALIDATION_CLAIM_DEADLINE` | 1 hour |

### Max Deadlines
| Constant | Value |
|----------|-------|
| `MAX_CHALLENGE_PERIOD` | 30 days |
| `MAX_CLAIM_DEADLINE` | 30 days |
| `MAX_COMMIT_DEADLINE` | 30 days |
| `MAX_REVEAL_DEADLINE` | 30 days |
| `MAX_FORCE_SETTLE_DELAY` | 90 days |

### Dispute Constants
| Constant | Value |
|----------|-------|
| `DISPUTE_RESOLUTION_DEADLINE` | 7 days |
| `MAX_DISPUTE_BOND_BPS` | 5000 (50%) |
| `DISPUTE_CHALLENGER_REWARD_BPS` | 2000 (20%) |
| `MAX_ORIGINATOR_REPORT_BOND_BPS` | 1000 (10%) |
| `MAX_DECAY_RATE_BPS` | 500 (5%/day) |
| `PROJECT_COMPLETION_DELAY` | 30 days |

### Reputation Constants
| Constant | Value |
|----------|-------|
| `DEFAULT_REPUTATION` | 5,000 |
| `MAX_REPUTATION` | 10,000 |
| `MIN_REPUTATION` | 500 |
| `SUCCESS_INCREASE` | +10 |
| `REJECTION_DECREASE` | -50 |
| `MAX_DAILY_GAIN` | 100 |

### Role Keys
| Constant | Value |
|----------|-------|
| `ORIGINATOR_ROLE_KEY` | `keccak256("ORIGINATOR")` |
| `CONTRIBUTOR_ROLE_KEY` | `keccak256("CONTRIBUTOR")` |
| `VALIDATOR_ROLE_KEY` | `keccak256("VALIDATOR")` |

---

## Access Control

| Role | Contract | Permissions |
|------|----------|------------|
| `DEFAULT_ADMIN_ROLE` | SapienCore | Fee config, treasury, deadlines, pause, upgrades |
| `OPERATOR_ROLE` | SapienCore | Project removal, dispute resolution, originator report resolution |
| `DEFAULT_ADMIN_ROLE` | SapienVault | Pause/unpause, upgrades |
| `ENGINE_ROLE` | SapienVault | All lock/unlock/slash/commit/release operations |

All other functions are permissionless with on-chain state checks (e.g., only the originator can fund their project, only a claim owner can submit contributions).

---

## Storage Layout

Both contracts use **ERC-7201 namespaced storage** to prevent storage collisions during upgrades.

### SapienCore
- **Namespace:** `sapien.storage.SapienCore`
- **Slot:** `0xb21037e32bd67da4126ec23c3d75228183c819f055709f5aa59aa33cc3fd2b00`
- **Struct:** `EngineStorage` (see `Types.sol`)

### SapienVault
- **Namespace:** `sapien.storage.StakeVault`
- **Slot:** `0x0745d816f844b8d3ebe69904ebcd305a06dedec42070def1e397b29c2e74a900`
- **Struct:** `SapienVaultStorage` containing `mapping(address => StakeAccount)`, `mapping(address => uint256) lastDepositTimestamp` (for min-deposit-age checks), and `minDepositAge`

### Upgradeability
- Both contracts use **UUPS proxy pattern** (OpenZeppelin `UUPSUpgradeable`)
- Upgrade authorization requires `DEFAULT_ADMIN_ROLE`
- Storage gaps are replaced by ERC-7201 namespaced storage, which avoids slot collision entirely

---

## Security Considerations

1. **Reentrancy Protection**: SapienCore uses `ReentrancyGuardUpgradeable` on all state-modifying functions
2. **Access Control**: Role-based via OpenZeppelin `AccessControlUpgradeable`
3. **Pausability**: Both contracts support emergency pause
4. **Commit-Reveal**: Prevents validator score herding and collusion
5. **Tiered Slashing**: Graduated penalties (10%–100%) proportional to deviation
6. **Dispute System**: Bonded disputes with escalation for unresponsive operators
7. **ERC-4626 Inflation Protection**: 3-decimal offset in SapienVault
8. **Transfer Guards**: Share transfers restricted by locked amounts
9. **Nonce-Keyed Disputes**: Prevents cross-nonce dispute poisoning

---

## Additional Resources

- **Component Details**: [components/](./components/)
- **Architecture Overview**: [architecture/overview.md](./architecture/overview.md)
- **User Guides**: [guides/](./guides/)
- **Security Audit Scope**: [security/AUDIT_SCOPE.md](./security/AUDIT_SCOPE.md)
