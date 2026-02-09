# Fee Structure

This document explains the fee structure in the Sapien V2 protocol, covering protocol fees and operator fees at different stages.

## Overview

The protocol has multiple fee collection points to support different participants in the ecosystem:

| Fee Type | Collected When | Maximum | Recipient |
|----------|---------------|---------|-----------|
| Protocol Fee | Project funding | 3% (300 bps) | Protocol Treasury |
| Originator Fee | Project funding | 2% (200 bps) | Dapp/Frontend operator |
| Contributor Fee | Contributor reward claim | 4% (400 bps, configurable) | Dapp/Frontend operator |
| Validator Fee | Validator reward claim | 4% (400 bps, configurable) | Dapp/Frontend operator |

## Protocol Fee

The protocol collects a fee on all project funding to sustain development and operations.

### Configuration

- **Default:** 1% (100 basis points)
- **Maximum:** 3% (300 basis points) - hardcoded as `MAX_PROTOCOL_FEE_BPS`
- **Configurable by:** Protocol admin via `setProtocolFeeBasisPoints()`
- **Recipient:** Treasury address set via `setTreasury()`

### How It Works

When an originator funds a project, the protocol fee is deducted from the reward amount:

```
Effective Rewards = Funded Amount - Protocol Fee - Operator Fee
```

**Example:**
- Originator funds project with 100 ETH
- Protocol fee: 1% = 1 ETH → sent to treasury
- Remaining 99 ETH available for rewards (before operator fee)

### Code Reference

```solidity
// SapienCore.sol
if (rewardAmount > 0 && protocolFeeBasisPoints > 0 && treasury != address(0)) {
    protocolFee = (rewardAmount * protocolFeeBasisPoints) / 10000;
    rewardAmountAfterFee = rewardAmount - protocolFee;
    project.rewardToken.safeTransferFrom(msg.sender, treasury, protocolFee);
}
```

## Originator Fee

Dapp operators who facilitate project creation can collect a fee when originators fund projects.

### Configuration

- **Maximum:** 2% (200 basis points) - hardcoded as `MAX_OPERATOR_FEE_BPS`
- **Set by:** Originator when calling `fundProject()`
- **Recipient:** Specified operator address

### How It Works

The protocol fee is deducted **first**, then the operator fee is taken from the remainder:

```
1. Protocol Fee = Funded Amount × Protocol Fee BPS / 10000
2. Operator Fee = (Funded Amount - Protocol Fee) × Operator Fee BPS / 10000
3. Available Rewards = Funded Amount - Protocol Fee - Operator Fee
```

**Example:**
- Originator funds 1000 ETH with 2% operator fee and 1% protocol fee
- Protocol fee: 1% of 1000 = 10 ETH → sent to treasury
- Operator fee: 2% of remaining 990 = 19.8 ETH → sent to operator
- Available for rewards: 970.2 ETH

### Usage

```solidity
// Fund project with operator fee
core.fundProject(
    projectId,
    100 ether,      // rewardAmount
    10,             // quantity (slots)
    operatorAddress, // operator receiving fee
    200             // 2% fee in basis points
);

// Fund project without operator fee
core.fundProject(projectId, 100 ether, 10);
```

## Contributor Fee

Dapp operators can collect a fee when contributors claim their rewards.

### Configuration

- **Default Maximum:** 4% (400 basis points)
- **Absolute Maximum:** 10% (1000 basis points) - hardcoded as `MAX_FEE_BPS_CAP`
- **Configurable by:** Admin via `setMaxFeeBps()` on Rewards contract
- **Set by:** Contributor when calling claim functions
- **Recipient:** Specified by contributor

### Usage

```solidity
// Claim with operator fee
rewards.claimRewards(
    projectId,
    tokenAddress,
    operatorAddress,  // fee recipient
    100               // 1% fee in basis points
);

// Claim all projects with operator fee
rewards.claimAllRewards(
    tokenAddress,
    projectIds,       // array of project IDs
    operatorAddress,
    100
);

// Claim without fee
rewards.claimRewards(projectId, tokenAddress, address(0), 0);
```

### How It Works

The fee is deducted from the claimed amount:

```
Net Reward = Earned Reward - (Earned Reward × Fee BPS / 10000)
Operator Fee = Earned Reward × Fee BPS / 10000
```

**Example:**
- Contributor earned 10 ETH
- Claims with 2% operator fee
- Operator receives: 0.2 ETH
- Contributor receives: 9.8 ETH

## Validator Fee

Dapp operators can collect a fee when validators claim their rewards.

### Configuration

- **Default Maximum:** 4% (400 basis points)
- **Absolute Maximum:** 10% (1000 basis points) - hardcoded as `MAX_FEE_BPS_CAP`
- **Configurable by:** Admin via `setMaxFeeBps()` on Rewards contract
- **Set by:** Validator when calling claim functions
- **Recipient:** Specified by validator

### Usage

```solidity
// Claim validator rewards with operator fee
rewards.claimValidatorRewards(
    projectId,
    tokenAddress,
    operatorAddress,
    100               // 1% fee
);

// Claim all validator rewards
rewards.claimAllValidatorRewards(
    tokenAddress,
    projectIds,
    operatorAddress,
    100
);

// Claim without fee
rewards.claimValidatorRewards(projectId, tokenAddress, address(0), 0);
```

### How It Works

The fee is deducted from the claimed amount (same formula as contributor fee):

```
Net Reward = Earned Reward - (Earned Reward × Fee BPS / 10000)
Operator Fee = Earned Reward × Fee BPS / 10000
```

**Example:**
- Validator earned 5 ETH
- Claims with 1% operator fee
- Operator receives: 0.05 ETH
- Validator receives: 4.95 ETH

## Validator Reward Allocation

Validators earn a percentage of each contribution's reward pool, set at project creation.

### Configuration

- **Default:** 10% (1000 basis points)
- **Maximum:** 25% (2500 basis points)
- **Set by:** Originator at project creation

### Distribution

```
Contributor Share = Total Rewards × (10000 - Validator BPS) / 10000
Validator Pool = Total Rewards × Validator BPS / 10000
```

Validator rewards are distributed proportionally based on:
1. Stake amount committed during validation
2. Accuracy (validators who matched consensus receive rewards)

**Example:**
- Project funded with 100 ETH (after fees)
- Validator reward: 10% = 10 ETH pool for validators
- Contributor reward: 90% = 90 ETH pool for contributors
- Per contribution: 90 ETH / 10 slots = 9 ETH per contributor

## Fee Flow Diagram

```
                    ┌─────────────────────────────────────────┐
                    │         Originator Funds Project        │
                    │             (1000 ETH)                  │
                    └─────────────────┬───────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────┐
                    │         Protocol Fee (1%)               │
                    │         → 10 ETH to Treasury            │
                    └─────────────────┬───────────────────────┘
                                      │ (990 ETH remaining)
                    ┌─────────────────▼───────────────────────┐
                    │        Originator Fee (2%)              │
                    │         → 19.8 ETH to Frontend          │
                    └─────────────────┬───────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────┐
                    │       Available Rewards Pool            │
                    │              970.2 ETH                  │
                    └─────────────────┬───────────────────────┘
                                      │
          ┌───────────────────────────┴───────────────────────┐
          │                                                   │
          ▼                                                   ▼
┌─────────────────────┐                           ┌─────────────────────┐
│  Contributor Share  │                           │   Validator Share   │
│   90% = 873.18 ETH  │                           │   10% = 97.02 ETH   │
└─────────┬───────────┘                           └─────────┬───────────┘
          │                                                   │
          ▼                                                   ▼
┌─────────────────────┐                           ┌─────────────────────┐
│  Contributor Fee    │                           │   Validator Fee     │
│   (1% on claim)     │                           │   (1% on claim)     │
│   → 8.73 ETH fee    │                           │   → 0.97 ETH fee    │
│   → 864.45 ETH net  │                           │   → 96.05 ETH net   │
└─────────────────────┘                           └─────────────────────┘
```

## Best Practices for Dapp Operators

1. **Transparent Fee Disclosure:** Always display fees clearly to users before transactions
2. **Reasonable Fees:** Keep fees competitive - high fees will drive users to other frontends
3. **Consistent Experience:** Use the same fee structure across your platform
4. **No Fees for Basics:** Consider zero fees for small claims or first-time users

## Admin Functions

### Protocol Admin

```solidity
// Set protocol fee (SapienCore)
core.setProtocolFeeBasisPoints(100); // 1%

// Set treasury address (SapienCore)
core.setTreasury(treasuryAddress);

// Set max claim operator fee (Rewards)
rewards.setMaxFeeBps(400); // 4% max
```

### Constants

| Constant | Value | Contract |
|----------|-------|----------|
| `MAX_PROTOCOL_FEE_BPS` | 300 (3%) | SapienCore |
| `MAX_OPERATOR_FEE_BPS` | 200 (2%) | SapienCore |
| `DEFAULT_MAX_FEE_BPS` | 400 (4%) | Rewards |
| `MAX_FEE_BPS_CAP` | 1000 (10%) | Rewards |

## Events

```solidity
// Emitted when protocol fee is collected
event ProtocolFeeCollected(bytes32 indexed projectId, address indexed token, uint256 amount);

// Emitted when funding operator fee is paid
event OperatorFeePaid(bytes32 indexed projectId, address indexed operator, uint256 amount);

// Emitted when claim operator fee is collected
event OperatorFeeCollected(address indexed claimer, address indexed feeRecipient, address indexed token, uint256 amount);

// Emitted when protocol fee rate is updated
event ProtocolFeeUpdated(uint256 feeBasisPoints);

// Emitted when max claim fee is updated
event MaxFeeBpsUpdated(uint256 maxFeeBps);
```
