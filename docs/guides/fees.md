# Fee Structure

This document explains the fee structure in the Sapien PoQ v0.5 protocol. All fees are managed within `SapienCore` — there is no separate Rewards contract.

## Overview

| Fee Type | Collected When | Default | Maximum | Recipient |
|----------|---------------|---------|---------|-----------|
| Protocol Fee | Project funding | 10% (1000 bps) | 10% (1000 bps) | Protocol treasury |
| Origination Adapter Fee | Project funding | 4% (400 bps) | 5% (500 bps) | Adapter address |
| Contribution Adapter Fee | Contributor reward release | 3% (300 bps) | 5% (500 bps) | Adapter address |
| Validation Adapter Fee | Validator settlement | 3% (300 bps) | 5% (500 bps) | Adapter address |
| Validator Reward Allocation | Per-contribution split | Set per project | 25% (2500 bps) | Validators |

## Protocol Fee

The protocol collects a fee on all project funding to sustain development and operations.

### Configuration

- **Default**: 10% (1000 basis points)
- **Maximum**: 10% (1000 basis points) — `MAX_PROTOCOL_FEE_BPS`
- **Configurable by**: Protocol admin via `setProtocolFee()`
- **Recipient**: Treasury address set via `setTreasury()`

### How It Works

When an originator funds a project, the protocol fee is deducted first:

```
Protocol Fee = Funded Amount * Protocol Fee BPS / 10000
```

**Example**:
- Originator funds project with 1000 USDC
- Protocol fee: 10% = 100 USDC sent to treasury
- Remaining: 900 USDC available for adapter fee and reward pool

## Origination Adapter Fee

Adapters (dapps/frontends) that facilitate project creation receive a fee when originators fund projects.

### Configuration

- **Default**: 4% (400 basis points)
- **Maximum**: 5% (500 basis points) — `MAX_ADAPTER_FEE_BPS`
- **Set by**: Originator when calling `fundProject()` by passing an `adapter` address
- **Recipient**: Adapter address specified in `fundProject()`

### How It Works

The protocol fee is deducted first, then the origination adapter fee is taken from the remainder:

```
1. Protocol Fee = Funded Amount * Protocol Fee BPS / 10000
2. Adapter Fee = (Funded Amount - Protocol Fee) * Origination Fee BPS / 10000
3. Reward Pool = Funded Amount - Protocol Fee - Adapter Fee
```

**Example**:
- Originator funds 1000 USDC with adapter (10% protocol fee, 4% origination fee)
- Protocol fee: 10% of 1000 = 100 USDC to treasury
- Adapter fee: 4% of 900 = 36.00 USDC to adapter
- Reward pool: 864.00 USDC

### Usage

```solidity
// Fund project with adapter fee
core.fundProject(projectId, 1000e6, 10, adapterAddress);

// Fund project without adapter fee
core.fundProject(projectId, 1000e6, 10, address(0));
```

## Contribution Adapter Fee

Adapters that facilitate contributor participation receive a fee when contributor rewards are released.

### Configuration

- **Default**: 3% (300 basis points)
- **Maximum**: 5% (500 basis points) — `MAX_ADAPTER_FEE_BPS`
- **Set by**: Contributor when calling `claimToContribute()` by passing an `adapter` address
- **Recipient**: Adapter address specified during claim creation

### How It Works

The adapter address is recorded when the contributor claims slots. When `releaseContributorReward` is called for an accepted contribution, the adapter fee is deducted from the contributor's reward:

```
Adapter Fee = Contributor Reward * Contribution Fee BPS / 10000
Net Reward = Contributor Reward - Adapter Fee
```

**Example**:
- Contributor earned 9 USDC for an accepted contribution
- Contribution adapter fee: 3% = 0.27 USDC to adapter
- Net reward: 8.73 USDC credited to contributor's pending balance

### Usage

```solidity
// Claim with adapter
(uint256 claimId, uint256[] memory indices) = core.claimToContribute(
    projectId, 5, adapterAddress
);

// Claim without adapter
(uint256 claimId, uint256[] memory indices) = core.claimToContribute(
    projectId, 5, address(0)
);
```

## Validation Adapter Fee

Adapters that facilitate validator participation receive a fee when validators are settled.

### Configuration

- **Default**: 3% (300 basis points)
- **Maximum**: 5% (500 basis points) — `MAX_ADAPTER_FEE_BPS`
- **Set by**: Validator when calling `commitValidation()` by passing an `adapter` address
- **Recipient**: Adapter address specified during commit

### How It Works

The adapter address is recorded when the validator commits a score. When the validator is settled as accurate (not an outlier), the adapter fee is deducted from their reward share:

```
Adapter Fee = Validator Reward Share * Validation Fee BPS / 10000
Net Reward = Validator Reward Share - Adapter Fee
```

### Usage

```solidity
// Commit with adapter
core.commitValidation(projectId, index, commitHash, stakeAmount, adapterAddress);

// Commit without adapter
core.commitValidation(projectId, index, commitHash, stakeAmount, address(0));
```

## Validator Reward Allocation

Validators earn a percentage of each contribution's reward, set by the originator at project creation.

### Configuration

- **Maximum**: 25% (2500 basis points) — `MAX_VALIDATOR_REWARD_BPS`
- **Set by**: Originator in the `Project` config at creation time (`validatorRewardBps`)

### Distribution

```
Contributor Reward = Reward Rate * (10000 - Validator Reward BPS) / 10000
Validator Pool = Reward Rate * Validator Reward BPS / 10000
```

The validator pool is distributed proportionally based on each accurate validator's weight (`sqrt(stake) * reputation`).

**Example**:
- Contribution reward rate: 100 USDC
- Validator reward: 10% = 10 USDC pool for validators
- Contributor reward: 90% = 90 USDC for the contributor

## Dispute and Report Bonds

### Dispute Bond

When opening a dispute against a contribution's consensus outcome, the challenger posts a bond:

- **Calculated as**: `rewardRate * disputeBondBps / 10000`
- **Maximum**: 50% (5000 basis points) — `MAX_DISPUTE_BOND_BPS`
- **Configurable by**: Protocol admin via `setDisputeBondBps()`
- **If upheld**: Bond returned to challenger; challenger also receives 20% of saved/slashed amount
- **If rejected**: Bond forfeited to the contributor

### Originator Report Bond

When reporting an originator for misconduct, the reporter posts a bond:

- **Calculated as**: `totalRewards * originatorReportBondBps / 10000`
- **Maximum**: 10% (1000 basis points) — `MAX_ORIGINATOR_REPORT_BOND_BPS`
- **Configurable by**: Protocol admin via `setOriginatorReportBondBps()`
- **If upheld**: Bond returned; project cancelled; originator stake slashed
- **If rejected**: Bond forfeited

## Originator Stake Requirement

Originators must lock a per-slot stake when funding projects as a commitment to project quality:

- **Configured by**: Protocol admin via `setOriginatorStakeRequirement()`
- **Total locked**: `originatorStakeRequirement * quantity`
- **Returned**: When the originator calls `completeProject` after all contributions are processed

## Claim Protection

Two safeguards prevent reward claim abuse:

| Parameter | Description | Configured By |
|-----------|-------------|---------------|
| `minClaimAmount` | Minimum pending balance required to call `claimReward` | `setMinClaimAmount()` |
| `claimCooldown` | Minimum time between successive `claimReward` calls per user | `setClaimCooldown()` |

## Fee Flow Diagram

```
                    ┌─────────────────────────────────────────┐
                    │         Originator Funds Project        │
                    │             (1000 USDC)                 │
                    └─────────────────┬───────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────┐
                    │         Protocol Fee (10%)              │
                    │         100 USDC → Treasury             │
                    └─────────────────┬───────────────────────┘
                                      │ (900 USDC remaining)
                    ┌─────────────────▼───────────────────────┐
                    │    Origination Adapter Fee (4%)         │
                    │         36.00 USDC → Adapter            │
                    └─────────────────┬───────────────────────┘
                                      │
                    ┌─────────────────▼───────────────────────┐
                    │         Reward Pool: 864.00 USDC        │
                    │    Per-contribution: 86.40 USDC (10)    │
                    └─────────────────┬───────────────────────┘
                                      │
          ┌───────────────────────────┴───────────────────────┐
          │                                                   │
          ▼                                                   ▼
┌─────────────────────┐                           ┌─────────────────────┐
│  Contributor Share   │                           │  Validator Pool     │
│  90% = 77.76 USDC   │                           │  10% = 8.64 USDC   │
└─────────┬───────────┘                           └─────────┬───────────┘
          │                                                   │
          ▼                                                   ▼
┌─────────────────────┐                           ┌─────────────────────┐
│ Contribution Adapter │                           │ Validation Adapter  │
│   Fee (3% on release)│                           │  Fee (3% on settle) │
│   2.33 USDC → Adapter│                           │   0.26 USDC → Adapt.│
│   75.43 USDC net     │                           │   8.38 USDC net     │
└─────────────────────┘                           └─────────────────────┘
```

## Admin Functions

### Fee Configuration

```solidity
core.setProtocolFee(1000);            // 10% protocol fee
core.setOriginationFee(400);          // 4% origination adapter fee
core.setContributionFee(300);         // 3% contribution adapter fee
core.setValidationFee(300);           // 3% validation adapter fee
core.setTreasury(treasuryAddress);    // treasury address
```

### Bond Configuration

```solidity
core.setDisputeBondBps(1000);             // 10% of rewardRate
core.setOriginatorStakeRequirement(1e18); // 1 SAPIEN per slot
core.setOriginatorReportBondBps(500);     // 5% of totalRewards
```

### Claim Protection

```solidity
core.setMinClaimAmount(1e6);    // minimum 1 USDC (6 decimals) to claim
core.setClaimCooldown(3600);    // 1 hour cooldown between claims
```

### Deadline Configuration

```solidity
core.setClaimDeadline(1 days);        // contributor claim deadline
core.setChallengePeriod(1 days);      // post-consensus challenge window
core.setCommitDeadline(1 days);       // validator commit deadline
core.setRevealDeadline(1 days);       // validator reveal deadline
core.setForceSettleDelay(3 days);     // delay before force-settle
```

## Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `MAX_PROTOCOL_FEE_BPS` | 1000 (10%) | Maximum protocol fee |
| `MAX_ADAPTER_FEE_BPS` | 500 (5%) | Maximum adapter fee (all types) |
| `MAX_VALIDATOR_REWARD_BPS` | 2500 (25%) | Maximum validator reward allocation |
| `MAX_DISPUTE_BOND_BPS` | 5000 (50%) | Maximum dispute bond |
| `MAX_ORIGINATOR_REPORT_BOND_BPS` | 1000 (10%) | Maximum originator report bond |
| `MAX_DECAY_RATE_BPS` | 500 (5%) | Maximum reputation decay per day |
| `BPS` | 10,000 | Basis points denominator |

## Events

```solidity
event ProtocolFeeUpdated(uint256 newFeeBps);
event OriginationFeeUpdated(uint256 newFeeBps);
event ContributionFeeUpdated(uint256 newFeeBps);
event ValidationFeeUpdated(uint256 newFeeBps);
event TreasuryUpdated(address indexed newTreasury);
event DisputeBondBpsUpdated(uint256 newBps);
event OriginatorStakeRequirementUpdated(uint256 newAmount);
event OriginatorReportBondBpsUpdated(uint256 newBps);
event MinClaimAmountUpdated(uint256 newAmount);
event ClaimCooldownUpdated(uint256 newCooldown);

event OriginationFeePaid(bytes32 indexed projectId, address indexed adapter, uint256 amount);
event ContributionAdapterFeePaid(bytes32 indexed projectId, uint256 indexed index, address indexed adapter, uint256 amount);
event ValidationAdapterFeePaid(bytes32 indexed projectId, uint256 indexed index, address indexed adapter, uint256 amount);
```
