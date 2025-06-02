# SapienVault Contract Documentation

## Overview

**Contract:** SapienVault  
**Purpose:** Manages staking, lockup, cooldown, and reward multiplier logic for Sapien Protocol.

**Inheritance:**
- `AccessControlUpgradeable`
- `PausableUpgradeable`
- `ReentrancyGuardUpgradeable`

**Features:**
- Single stake per user
- Weighted average calculations for lockup and multiplier
- Dynamic reward multiplier via external Multiplier contract
- Role-based access control for admin, pauser, and QA functions
- Cooldown and penalty systems

---

## Initialization

```solidity
function initialize(
    address token,
    address admin,
    address newTreasury,
    address newMultiplierContract,
    address sapienQA
)
```

Initializes the staking vault with references to token, admin, treasury, multiplier logic, and QA roles.

---

## Roles

| Role | Description |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Full administrative rights |
| `PAUSER_ROLE` | Authorized to pause/unpause contract |
| `SAPIEN_QA_ROLE` | Allowed to impose penalties on users |

---

## Core State Variables

- `IERC20 public sapienToken` – The Sapien ERC20 token
- `address public treasury` – Penalty destination
- `IMultiplier public multiplier` – External contract for multiplier logic
- `uint256 public totalStaked` – Total amount staked
- `mapping(address => UserStake) public userStakes` – Stake data per user

---

## Staking API

### Stake Tokens

```solidity
function stake(uint256 amount, uint256 lockUpPeriod)
```

Stake a defined amount with a specific lock-up duration. Lock-up periods must be between 30–365 days.

### Increase Amount

```solidity
function increaseAmount(uint256 additionalAmount)
```

Adds more tokens to an existing stake without changing the lock-up period.

### Increase Lockup

```solidity
function increaseLockup(uint256 additionalLockup)
```

Extends the lock-up period. Must be a minimum of defined seconds (e.g., 7 days).

---

## Unstaking Flow

### Initiate Unstake

```solidity
function initiateUnstake(uint256 amount)
```

Moves tokens to cooldown. Can only be called after lock-up ends.

### Complete Unstake

```solidity
function unstake(uint256 amount)
```

Withdraws tokens after cooldown completes.

### Early Unstake (With Penalty)

```solidity
function earlyUnstake(uint256 amount)
```

Allows immediate withdrawal but applies a penalty.

---

## QA Penalty System

### Apply QA Penalty

```solidity
function processQAPenalty(address userAddress, uint256 penaltyAmount)
```

Transfers stake from user to treasury. Can be partial if the user has insufficient balance. Only callable by QA role.

---

## Multiplier Logic

### Calculate Multiplier

```solidity
function calculateMultiplier(uint256 amount, uint256 effectiveLockup)
```

Fetches the multiplier for a user based on stake and lock-up duration via Multiplier contract.

---

## View Functions

### getUserStakingSummary

Returns a comprehensive breakdown of a user's stake:

- **total staked**
- **unlocked amount**
- **locked amount**
- **cooldown amount**
- **amount ready for unstake**
- **effective multiplier**
- **lock-up period**
- **time until unlock**

### Other Helper View Functions

- `getTotalStaked(user)`
- `getTotalUnlocked(user)`
- `getTotalLocked(user)`
- `getTotalInCooldown(user)`
- `getTotalReadyForUnstake(user)`
- `hasActiveStake(user)`

---

## Events

| Event | Description |
|-------|-------------|
| `Staked` | Emitted when tokens are staked |
| `AmountIncreased` | Emitted when more tokens are added to a stake |
| `LockupIncreased` | Emitted when lockup is increased |
| `UnstakingInitiated` | Emitted when unstaking is initiated |
| `Unstaked` | Emitted when unstaking is complete |
| `EarlyUnstake` | Emitted on early unstake with penalty |
| `SapienTreasuryUpdated` | Treasury address updated |
| `MultiplierUpdated` | Multiplier contract address updated |
| `EmergencyWithdraw` | Admin withdraws in paused state |
| `QAPenaltyProcessed` | QA penalty applied successfully |
| `QAPenaltyPartial` | Partial penalty due to insufficient stake |
| `QAStakeReduced` | Breakdown of stake deductions from active/cooldown |
| `QAUserStakeReset` | Emitted when a user's stake is fully cleared |

---

## Safeguards & Validation

- **Reentrancy protection** on all external state-changing functions
- **Role-based access control** using OpenZeppelin AccessControl
- **Overflow checks** on all weighted calculations
- **Emergency withdraw** only when paused

---

## Design Notes

- **Single stake model** simplifies calculations and user flows
- **Weighted logic** maintains fairness for combined stakes
- **Cooldown** prevents instant withdrawals post-lockup
- **Penalty system** aligns economic incentives with quality assurance

---

## Dependencies

- `Constants.sol`: System-wide time and threshold definitions
- `Common.sol`: Re-export of OpenZeppelin libraries
- `IMultiplier.sol`: External interface for multiplier lookup
- `SafeCast.sol`: Safe casting utility

---

## TODO / Suggestions

- [ ] Add support for partial withdrawals while still locked
- [ ] Consider per-user staking cap or whitelist functionality
- [ ] Emit more granular events for frontend traceability (e.g., cooldown started, unlocks completed)

---
