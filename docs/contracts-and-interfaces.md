# Sapien PoQ Protocol - Contracts and Interfaces Reference

**Version:** v0.3  
**Last Updated:** January 23rd, 2026

This document provides a comprehensive reference for all smart contracts and interfaces in the Sapien PoQ Protocol, including their NatSpec documentation.

---

## Table of Contents

1. [Core Contracts](#core-contracts)
   - [SapienCore](#sapiencore)
   - [SapienVault](#sapienvault)
   - [SapienTrust](#sapientrust)
   - [ValidationOracle](#validationoracle)
   - [Rewards](#rewards)
2. [Consensus Algorithms](#consensus-algorithms)
   - [HybridConsensus](#hybridconsensus)
   - [SqrtStakeConsensus](#sqrtstakeconsensus)
   - [LinearStakeConsensus](#linearstakeconsensus)
   - [CappedLinearConsensus](#cappedlinearconsensus)
3. [Interfaces](#interfaces)
   - [ISapienCore](#isapiencore)
   - [ISapienVault](#isapienvault)
   - [ISapienTrust](#isapientrust)
   - [IValidationOracle](#ivalidationoracle)
   - [IRewards](#irewards)
   - [IConsensusAlgorithm](#iconsensusalgorithm)
   - [ISharedTypes](#isharedtypes)

---

## Core Contracts

### SapienCore

**File:** `src/SapienCore.sol`

**Description:**
```solidity
/**
 * @title SapienCore
 * @notice Central coordinator for projects, contributions, and rewards.
 * @dev Merges ProjectRegistry and ContributionManager.
 *      Hierarchy: Core -> Oracle -> Trust -> Vault.
 */
```

**Key Functions:**

#### `initialize`
```solidity
/**
 * @notice Initialize the SapienCore contract
 * @param _vault Address of the SapienVault contract
 * @param _rewards Address of the Rewards contract
 * @param _trust Address of the SapienTrust contract
 * @param _oracle Address of the ValidationOracle contract
 * @param _admin Address to grant DEFAULT_ADMIN_ROLE
 */
function initialize(
    address _vault,
    address _rewards,
    address _trust,
    address _oracle,
    address _admin
) public initializer
```

#### `createProject`
```solidity
/**
 * @notice Create a new project in the protocol
 * @param projectId Unique identifier for the project
 * @param rewardToken ERC20 token to be used for rewards
 * @param minStakeToClaim Minimum stake required for a contributor to claim a slot
 * @param minStakeToContribute Minimum stake required for a contributor to participate (legacy)
 * @param minValidations Minimum number of validations required to finalize a contribution
 * @param validatorRewardBasisPoints Percentage of rewards allocated to validators (bps)
 * @param requiredSkill Specific skill that contributors will earn upon successful completion
 * @return The hashed projectId (bytes32)
 */
function createProject(
    bytes32 projectId,
    address rewardToken,
    uint256 minStakeToClaim,
    uint256 minStakeToContribute,
    uint256 minValidations,
    uint256 validatorRewardBasisPoints,
    string calldata requiredSkill
) external returns (bytes32)
```

#### `fundProject`
```solidity
/**
 * @notice Fund an existing project with rewards and contribution quantity
 * @param projectId Unique identifier for the project
 * @param rewardAmount Amount of reward tokens to add
 * @param quantity Number of contribution slots to add
 */
function fundProject(bytes32 projectId, uint256 rewardAmount, uint256 quantity) external
```

#### `claimToContribute`
```solidity
/**
 * @notice Claim a number of contribution slots in a project
 * @param projectId Unique identifier for the project
 * @param quantity Number of slots to claim
 * @return claimId Unique identifier for the created claim
 */
function claimToContribute(bytes32 projectId, uint256 quantity) external returns (uint256 claimId)
```

#### `contribute`
```solidity
/**
 * @notice Submit a contribution for a specific slot in a claim
 * @param projectId Unique identifier for the project
 * @param claimId Unique identifier for the claim
 * @param contributionIndex The index within the project's contribution sequence
 * @param submissionHash Hash of the submitted work (e.g. IPFS CID)
 */
function contribute(
    bytes32 projectId,
    uint256 claimId,
    uint256 contributionIndex,
    bytes32 submissionHash
) external
```

#### `finalizeContribution`
```solidity
/**
 * @notice Finalize a contribution by calculating consensus and distributing rewards/slashing
 * @param projectId Unique identifier for the project
 * @param contributionIndex The index within the project's contribution sequence
 */
function finalizeContribution(bytes32 projectId, uint256 contributionIndex) external
```

**Events:**
- `ProjectCreated(bytes32 indexed projectId, address indexed originator, string requiredSkill)`
- `ProjectFunded(bytes32 indexed projectId, uint256 rewardAmount, uint256 quantity)`
- `ClaimCreated(bytes32 indexed projectId, uint256 indexed claimId, address indexed contributor, uint256 quantity)`
- `ContributionSubmitted(bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed contributor)`
- `ContributionFinalized(bytes32 indexed projectId, uint256 indexed contributionIndex, ContributionStatus status, uint256 finalScore)`

**Errors:**
- `ProjectAlreadyExists(bytes32 projectId)`
- `ProjectDoesNotExist(bytes32 projectId)`
- `InsufficientContributorStake(address contributor, uint256 required, uint256 actual)`
- `ContributionAlreadySubmitted(uint256 index)`
- `MissingRequiredSkill(address user, string requiredSkill)`

---

### SapienVault

**File:** `src/SapienVault.sol`

**Description:**
```solidity
/**
 * @title SapienVault
 * @notice ERC-4626 compliant vault for staking with slashing capability (Upgradeable)
 * @dev Users deposit staking tokens and receive vault shares.
 *      Slashing burns shares from penalized users, reducing their position.
 *      Uses transparent proxy pattern for upgradeability.
 */
```

**Key Functions:**

#### `initialize`
```solidity
/**
 * @notice Initialize the vault (replaces constructor for upgradeable pattern)
 * @param _stakingToken The underlying token to be staked
 * @param _defaultAdmin The address to grant DEFAULT_ADMIN_ROLE
 */
function initialize(address _stakingToken, address _defaultAdmin) public initializer
```

#### `lockStake`
```solidity
/**
 * @notice Lock a user's stake to prevent withdrawals/transfers
 * @dev Can only be called by addresses with LOCKER_ROLE (e.g., ProjectRegistry)
 * @param user The user whose stake to lock
 * @param amount The amount to lock
 * @param reason The reason for locking (for event tracking)
 */
function lockStake(address user, uint256 amount, string calldata reason) external
```

#### `unlockStake`
```solidity
/**
 * @notice Unlock a user's stake to allow withdrawals/transfers
 * @dev Can only be called by addresses with LOCKER_ROLE
 * @param user The user whose stake to unlock
 * @param amount The amount to unlock
 * @param reason The reason for unlocking (for event tracking)
 */
function unlockStake(address user, uint256 amount, string calldata reason) external
```

#### `slash`
```solidity
/**
 * @notice Slash a user's stake by burning their vault shares
 * @dev Can only be called by addresses with SLASHER_ROLE
 * @param user The user whose stake to slash
 * @param amount The amount to slash (in underlying tokens)
 * @param projectId The project ID for tracking purposes
 * @return The amount of shares burned
 */
function slash(address user, uint256 amount, bytes32 projectId) external returns (uint256)
```

**Events:**
- `Slashed(address indexed user, uint256 sharesSlashed, uint256 assetsSlashed, address indexed slasher, bytes32 projectId)`
- `StakeLocked(address indexed user, uint256 amount, address indexed locker, string reason)`
- `StakeUnlocked(address indexed user, uint256 amount, address indexed locker, string reason)`

**Errors:**
- `InsufficientUnlockedStake(address user, uint256 required, uint256 available)`
- `InsufficientLockedStake(address user, uint256 required, uint256 available)`
- `NoSharesToSlash(address user)`

---

### SapienTrust

**File:** `src/SapienTrust.sol`

**Description:**
```solidity
/**
 * @title SapienTrust
 * @notice Unified identity and reputation layer for Sapien V2
 * @dev Simplified Proof of Quality (PoQ) reputation system with implicit identity via staking.
 */
```

**Key Functions:**

#### `initialize`
```solidity
/**
 * @notice Initialize the SapienTrust contract
 * @param _vault Address of the SapienVault contract
 * @param _minStake Minimum stake required for participation
 * @param _decayRate Reputation decay rate per day (in basis points)
 * @param _admin Address to grant DEFAULT_ADMIN_ROLE
 */
function initialize(address _vault, uint256 _minStake, uint256 _decayRate, address _admin) public initializer
```

#### `hasEnoughStake`
```solidity
/**
 * @notice Check if a user is eligible for a role based on their stake.
 * @param user The address to check.
 * @param role The role to check eligibility for.
 * @return True if user meets the protocol's minimum staking requirements.
 */
function hasEnoughStake(address user, bytes32 role) public view
```

#### `getTrustScore`
```solidity
/**
 * @notice Get the trust score (reputation) of a user for a specific role
 * @param user Address of the user
 * @param role Role identifier
 * @return Reputation score (0-10000, where 5000 is default)
 */
function getTrustScore(address user, bytes32 role) external view returns (uint256)
```

#### `updateReputation`
```solidity
/**
 * @notice Update a user's reputation based on their performance
 * @param user Address of the user
 * @param role Role identifier
 * @param success True if the action was successful/accurate
 * @param qualityScore Score of the specific action (if applicable)
 */
function updateReputation(address user, bytes32 role, bool success, uint256 qualityScore) external
```

**Events:**
- `ReputationUpdated(address indexed user, bytes32 role, uint256 oldScore, uint256 newScore)`
- `SkillValidated(address indexed user, string skill, uint256 completionCount)`

**Constants:**
- `DEFAULT_REPUTATION = 5000` (50%)
- `MAX_REPUTATION = 10000` (100%)
- `MIN_REPUTATION = 500` (5%)
- `SLASH_DECREASE = 100` (-1%)
- `SUCCESS_INCREASE = 10` (+0.1%)
- `REJECTION_DECREASE = 50` (-0.5%)

---

### ValidationOracle

**File:** `src/ValidationOracle.sol`

**Description:**
```solidity
/**
 * @title ValidationOracle
 * @notice Stateless consensus oracle for Sapien V2
 * @dev Manages commit-reveal validation and pluggable consensus algorithms.
 *      Hierarchy: Oracle -> Trust -> Vault. No dependency on SapienCore.
 */
```

**Key Functions:**

#### `initialize`
```solidity
/**
 * @notice Initialize the ValidationOracle contract
 * @param _trust Address of the SapienTrust contract
 * @param _vault Address of the SapienVault contract
 * @param _defaultAlgorithmName Name of the default consensus algorithm
 * @param _admin Address to grant DEFAULT_ADMIN_ROLE
 */
function initialize(
    address _trust,
    address _vault,
    string memory _defaultAlgorithmName,
    address _admin
) public initializer
```

#### `claimToValidate`
```solidity
/**
 * @notice Claim a number of validation slots in a project
 * @param projectId Unique identifier for the project
 * @param quantity Number of slots to claim
 * @return claimId Unique identifier for the created validation claim
 */
function claimToValidate(bytes32 projectId, uint256 quantity) external returns (uint256 claimId)
```

#### `commitValidation`
```solidity
/**
 * @notice Commit a validation score hash
 * @param projectId Unique identifier for the project
 * @param claimId Unique identifier for the validation claim
 * @param contributionIndex The index within the project's contribution sequence
 * @param commitHash keccak256(score, salt)
 */
function commitValidation(
    bytes32 projectId,
    uint256 claimId,
    uint256 contributionIndex,
    bytes32 commitHash
) external
```

#### `revealValidation`
```solidity
/**
 * @notice Reveal a committed validation score
 * @param projectId Unique identifier for the project
 * @param contributionIndex The index within the project's contribution sequence
 * @param score The validation score (0-10000)
 * @param salt The salt used in the commit
 */
function revealValidation(
    bytes32 projectId,
    uint256 contributionIndex,
    uint256 score,
    bytes32 salt
) external
```

#### `getConsensus`
```solidity
/**
 * @notice Calculate consensus for a contribution
 * @param projectId Unique identifier for the project
 * @param contributionIndex The index within the project's contribution sequence
 * @param minValidations Minimum validations required to reach consensus
 * @return report Final consensus report containing average, count, and slashes
 */
function getConsensus(bytes32 projectId, uint256 contributionIndex, uint256 minValidations)
    external
    view
    returns (ConsensusReport memory report)
```

**Events:**
- `ValidationClaimed(bytes32 indexed projectId, uint256 indexed claimId, address indexed validator, uint256 deadline)`
- `ValidationCommitted(bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed validator, bytes32 commitHash)`
- `ValidationRevealed(bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed validator, uint256 score)`
- `ConsensusReached(bytes32 indexed projectId, uint256 indexed contributionIndex, uint256 weightedAverage, uint256 validatorCount)`

**Errors:**
- `AlreadyCommitted(address validator)`
- `NoUnrevealedCommit()`
- `InvalidCommitHash()`
- `ClaimExpired()`
- `MissingRequiredSkill(address user, string requiredSkill)`

---

### Rewards

**File:** `src/Rewards.sol`

**Description:**
```solidity
/**
 * @title Rewards
 * @notice Upgradeable reward distribution contract for the Sapien protocol
 * @dev Uses transparent proxy pattern for upgradeability
 */
```

**Key Functions:**

#### `initialize`
```solidity
/**
 * @notice Initialize the Rewards contract
 * @param _defaultAdmin The address to grant DEFAULT_ADMIN_ROLE
 */
function initialize(address _defaultAdmin) public initializer
```

#### `allocateRewards`
```solidity
/**
 * @notice Allocate rewards for a project (called during funding)
 * @param projectId Unique identifier for the project
 * @param token The reward token address
 * @param amount The amount of rewards to allocate
 */
function allocateRewards(bytes32 projectId, address token, uint256 amount) external
```

#### `distributeReward`
```solidity
/**
 * @notice Distribute rewards to a contributor (called when contribution is validated)
 * @param projectId Unique identifier for the project
 * @param contributor The address to receive rewards
 * @param token The reward token address
 * @param amount The amount of rewards to distribute
 */
function distributeReward(bytes32 projectId, address contributor, address token, uint256 amount) external
```

#### `distributeValidatorReward`
```solidity
/**
 * @notice Distribute rewards to a validator (called when consensus is reached)
 * @param projectId Unique identifier for the project
 * @param validator The address to receive rewards
 * @param token The reward token address
 * @param amount The amount of rewards to distribute
 */
function distributeValidatorReward(bytes32 projectId, address validator, address token, uint256 amount) external
```

#### `claimRewards`
```solidity
/**
 * @notice Claim available rewards for a contributor
 * @param projectId Unique identifier for the project
 * @param token The reward token address
 */
function claimRewards(bytes32 projectId, address token) external
```

**Events:**
- `RewardsAllocated(bytes32 indexed projectId, address indexed token, uint256 amount)`
- `RewardsDistributed(bytes32 indexed projectId, address indexed user, address indexed token, uint256 amount)`
- `RewardsClaimed(address indexed user, bytes32 indexed projectId, address indexed token, uint256 amount)`

**Errors:**
- `OnlyCore()`
- `NoRewardsToClaim()`
- `InsufficientProjectRewards(bytes32 projectId, address token, uint256 required, uint256 available)`

---

## Consensus Algorithms

### HybridConsensus

**File:** `src/consensus/HybridConsensus.sol`

**Description:**
```solidity
/**
 * @title HybridConsensus
 * @notice Final solution - combines sqrt stake, reputation, and cap
 * @dev Weight = min(sqrt(stake) × reputation, 30% cap)
 * Security Grade: A- (best overall protection)
 */
```

**Key Functions:**

#### `calculateConsensus`
```solidity
/**
 * @notice Calculate consensus from validator inputs
 * @param validations Array of validator inputs
 * @return result Consensus calculation result
 */
function calculateConsensus(ValidationInput[] calldata validations)
    external
    pure
    returns (ConsensusResult memory result)
```

**Algorithm Details:**
- Weight calculation: `min(sqrt(stake) × reputation, 30% cap)`
- Security Grade: **A-**
- Best overall protection combining whale resistance, quality incentives, and hard limits

---

### SqrtStakeConsensus

**File:** `src/consensus/SqrtStakeConsensus.sol`

**Description:**
```solidity
/**
 * @title SqrtStakeConsensus
 * @notice Square root stake weighting - reduces whale power sublinearly
 * @dev Weight = sqrt(stake)
 * Security Grade: A- (reduces whale power by 22%)
 */
```

**Algorithm Details:**
- Weight calculation: `sqrt(stake)`
- Security Grade: **A-**
- Reduces whale power by 22%, proven in quadratic voting research

---

### LinearStakeConsensus

**File:** `src/consensus/LinearStakeConsensus.sol`

**Description:**
```solidity
/**
 * @title LinearStakeConsensus
 * @notice Current system - linear stake-weighted consensus
 * @dev Weight = stake (vulnerable to whale attacks with >50% stake)
 * Security Grade: C+ (vulnerable to whale manipulation)
 */
```

**Algorithm Details:**
- Weight calculation: `stake`
- Security Grade: **C+**
- Vulnerable to whale attacks (>50% stake)

---

### CappedLinearConsensus

**File:** `src/consensus/CappedLinearConsensus.sol`

**Description:**
```solidity
/**
 * @title CappedLinearConsensus
 * @notice Quick fix - linear stake-weighted with 30% cap per validator
 * @dev Weight = min(stake, 30% of total stake)
 * Security Grade: B+ (prevents single whale dominance)
 */
```

**Algorithm Details:**
- Weight calculation: `min(stake, 30% of total stake)`
- Security Grade: **B+**
- Prevents single whale dominance

---

## Interfaces

### ISapienCore

**File:** `src/interface/ISapienCore.sol`

**Description:**
```solidity
/**
 * @title ISapienCore
 * @notice Single Source of Truth for Sapien V2 protocol
 * @dev Combines Project management and Contribution lifecycle
 */
```

**Key Functions:**
- `createProject(...)` - Create a new project
- `fundProject(...)` - Fund a project with rewards
- `claimToContribute(...)` - Claim contribution slots
- `contribute(...)` - Submit a contribution
- `finalizeContribution(...)` - Finalize a contribution
- `getProject(...)` - Get project details
- `getContribution(...)` - Get contribution details

---

### ISapienVault

**File:** `src/interface/ISapienVault.sol`

**Description:**
```solidity
/**
 * @title ISapienVault
 * @notice Interface for the Sapien staking vault with slashing capability (Upgradeable)
 * @dev Defines additional slashing and locking functionality beyond ERC-4626 standard
 */
```

**Key Functions:**
- `getStake(address user)` - Get user's total stake
- `lockStake(...)` - Lock a user's stake
- `unlockStake(...)` - Unlock a user's stake
- `slash(...)` - Slash a user's stake
- `getAvailableStake(address user)` - Get available (unlocked) stake
- `getLockedStake(address user)` - Get locked stake

---

### ISapienTrust

**File:** `src/interface/ISapienTrust.sol`

**Description:**
```solidity
/**
 * @title ISapienTrust
 * @notice Unified identity and reputation layer for Sapien V2
 * @dev Manages simplified user skills and Proof of Quality (PoQ) reputation.
 *      Identity is implicit: anyone with sufficient stake can participate.
 */
```

**Key Functions:**
- `hasEnoughStake(address user, bytes32 role)` - Check role eligibility
- `hasValidatedSkill(address user, string skill)` - Check skill validation
- `validateSkill(address user, string skill)` - Mark skill as validated
- `getTrustScore(address user, bytes32 role)` - Get reputation score
- `updateReputation(...)` - Update user reputation
- `hasRequiredStake(address user)` - Check minimum stake requirement

---

### IValidationOracle

**File:** `src/interface/IValidationOracle.sol`

**Description:**
```solidity
/**
 * @title IValidationOracle
 * @notice Stateless consensus oracle for Sapien V2
 * @dev Manages the commit-reveal process and consensus calculations
 */
```

**Key Functions:**
- `claimToValidate(...)` - Claim validation slots
- `enqueueValidation(...)` - Enqueue contribution for validation
- `commitValidation(...)` - Commit validation score hash
- `revealValidation(...)` - Reveal committed validation score
- `getConsensus(...)` - Calculate consensus for a contribution
- `getValidations(...)` - Get all revealed validations
- `registerProject(...)` - Register a new project
- `setProjectAlgorithm(...)` - Set consensus algorithm for project

---

### IRewards

**File:** `src/interface/IRewards.sol`

**Description:**
```solidity
/**
 * @title IRewards
 * @notice Interface for reward distribution contract
 */
```

**Key Functions:**
- `allocateRewards(...)` - Allocate rewards for a project
- `distributeReward(...)` - Distribute rewards to contributor
- `distributeValidatorReward(...)` - Distribute rewards to validator
- `claimRewards(...)` - Claim available rewards
- `getAvailableRewards(...)` - Get available rewards for contributor
- `getAvailableValidatorRewards(...)` - Get available rewards for validator

---

### IConsensusAlgorithm

**File:** `src/interface/IConsensusAlgorithm.sol`

**Description:**
```solidity
/**
 * @title IConsensusAlgorithm
 * @notice Interface for pluggable consensus algorithms
 * @dev Implementations calculate weighted consensus from validator inputs
 */
```

**Key Functions:**
- `calculateConsensus(...)` - Calculate consensus from validator inputs
- `getName()` - Get algorithm name
- `getSecurityGrade()` - Get security grade
- `getDescription()` - Get algorithm description

**Structs:**
```solidity
struct ValidationInput {
    address validator;
    uint256 score; // 0-10000 (0-100%)
    uint256 stakeAmount; // Amount staked by validator
    uint256 reputation; // 0-10000 from SapienPoQ
}

struct ConsensusResult {
    uint256 weightedAverage; // Final consensus score (0-10000)
    uint256 stdDev; // Standard deviation
    address[] validatorsToSlash; // Validators identified as outliers
    uint256[] slashAmounts; // Corresponding slash amounts
    uint256[] validatorWeights; // Weight assigned to each validator
}
```

---

### ISharedTypes

**File:** `src/interface/ISharedTypes.sol`

**Description:**
```solidity
/**
 * @title ISharedTypes
 * @notice Shared type definitions used across multiple protocol interfaces
 * @dev Centralizes structs and enums to avoid duplication and struct conversion overhead
 */
```

**Key Structs:**

#### `Project`
```solidity
struct Project {
    bytes32 projectId;
    address originator;
    IERC20 rewardToken;
    ProjectState state;
    ProjectConfig config;
}
```

#### `Contribution`
```solidity
struct Contribution {
    bytes32 projectId;
    address contributor;
    uint256 claimId;
    uint256 contributionIndex;
    bytes32 submissionHash;
    uint256 submittedAt;
    uint256 totalValidations;
    uint256 averageScore;
    ContributionStatus status;
}
```

#### `Validation`
```solidity
struct Validation {
    bytes32 projectId;
    address validator;
    uint256 contributionIndex;
    uint256 score;
    uint256 stakeAmount;
    uint256 submittedAt;
    bool rewarded;
    bool slashed;
}
```

#### `ConsensusReport`
```solidity
struct ConsensusReport {
    uint256 weightedAverage;
    uint256 validatorCount;
    bool isReady;
    address[] validatorsToSlash;
    uint256[] slashAmounts;
}
```

**Enums:**
- `ClaimStatus`: Active, Fulfilled, Expired, Cancelled
- `ContributionStatus`: Pending, Validated, Rewarded, Rejected

**Constants:**
- `CONTRIBUTOR_ROLE`
- `VALIDATOR_ROLE`
- `ORIGINATOR_ROLE`
- `LOCKER_ROLE`
- `SLASHER_ROLE`
- `PAUSER_ROLE`
- `UPDATER_ROLE`
- `SAPIEN_CORE_ROLE`

---

## Contract Hierarchy

```
SapienCore (Central Coordinator)
├── ValidationOracle (Consensus Engine)
│   ├── SapienTrust (Reputation & Identity)
│   │   └── SapienVault (Staking & Slashing)
│   └── ConsensusAlgorithm (Pluggable)
└── Rewards (Reward Distribution)
    └── SapienVault (Staking & Slashing)
```

---

## Access Control Roles

| Role | Purpose | Contracts |
|------|---------|-----------|
| `DEFAULT_ADMIN_ROLE` | Full administrative control | All contracts |
| `ORIGINATOR_ROLE` | Create and fund projects | SapienCore |
| `CONTRIBUTOR_ROLE` | Submit contributions | SapienCore |
| `VALIDATOR_ROLE` | Validate contributions | ValidationOracle |
| `LOCKER_ROLE` | Lock/unlock stakes | SapienVault |
| `SLASHER_ROLE` | Slash stakes | SapienVault |
| `PAUSER_ROLE` | Pause contracts | SapienVault, Rewards |
| `UPDATER_ROLE` | Update reputation | SapienTrust |
| `SAPIEN_CORE_ROLE` | Core protocol operations | ValidationOracle |

---

## Upgradeability

All core contracts use the **Upgradeable Proxy Pattern** (OpenZeppelin):
- `SapienCore`: Upgradeable
- `SapienVault`: Upgradeable (ERC4626Upgradeable)
- `SapienTrust`: Upgradeable
- `ValidationOracle`: Upgradeable
- `Rewards`: Upgradeable

**Storage Gaps:**
- All contracts include storage gaps for future upgrades
- Storage gaps prevent storage collision in upgrades

---

## Security Considerations

1. **Reentrancy Protection**: All contracts use `ReentrancyGuardUpgradeable`
2. **Access Control**: Role-based access control via OpenZeppelin `AccessControl`
3. **Pausability**: Critical contracts can be paused in emergencies
4. **Slashing**: Economic penalties for malicious behavior
5. **Commit-Reveal**: Prevents validator collusion
6. **Consensus Algorithms**: Pluggable algorithms with security grades

---

## Additional Resources

- **Complete Documentation**: [COMPLETE_DOCUMENTATION.md](./COMPLETE_DOCUMENTATION.md)
- **Architecture Overview**: [architecture/overview.md](./architecture/overview.md)
- **Component Details**: [components/](./components/)
- **User Guides**: [guides/](./guides/)

---

*This document is automatically generated from contract NatSpec comments. For the most up-to-date information, refer to the source code.*
