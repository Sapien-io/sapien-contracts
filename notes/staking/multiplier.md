# SapienVault Multiplier System: Stake Amount vs Lockup Period

## Overview

The SapienVault contract uses a sophisticated multiplier system that combines **lockup periods** and **stake amounts** to determine effective multipliers for staking rewards. This document explains the relationship between these two factors.

## Base Multiplier System (Lockup Period Primary)

The **lockup period** is the primary factor that determines the base multiplier:

| Lockup Period | Multiplier Value | Effective Rate | Description |
|---------------|------------------|----------------|-------------|
| **30 days**   | 10,500          | **1.05x**      | Minimum commitment |
| **90 days**   | 11,000          | **1.10x**      | Short-term commitment |
| **180 days**  | 12,500          | **1.25x**      | Medium-term commitment |
| **365 days**  | 15,000          | **1.50x**      | Maximum commitment |

### Key Points

- **Stake amount does NOT directly affect the base multiplier**
- Only the lockup period determines the multiplier tier
- Linear interpolation is used for non-standard lockup periods between tiers
- Multipliers are expressed in basis points (10,000 = 1.00x)

## Weighted Average System (Where Stake Amount Matters)

The **stake amount** becomes crucial when **combining multiple stakes** through:

- `increaseAmount()` function (adds more tokens to existing stake)
- Additional `stake()` calls (combines with existing stake)

### Weighted Lockup Formula

```solidity
effectiveLockup = (existingLockup × existingAmount + newLockup × newAmount) / totalAmount
```

### Weighted Start Time Formula

```solidity
weightedStartTime = (existingStartTime × existingAmount + currentTime × newAmount) / totalAmount
```

## Example Scenarios

### Scenario 1: Same Lockup Periods

- **Existing**: 1,000 tokens @ 30 days (1.05x multiplier)
- **Adding**: 1,000 tokens @ 30 days (1.05x multiplier)
- **Result**: 2,000 tokens @ 30 days (1.05x multiplier)
- **Effect**: No change in multiplier

### Scenario 2: Small Amount, Long Lockup

- **Existing**: 10,000 tokens @ 30 days (30-day lockup)
- **Adding**: 1,000 tokens @ 365 days (365-day lockup)
- **Weighted lockup**: `(30 × 10,000 + 365 × 1,000) / 11,000 = 60.45 days`
- **Result**: 11,000 tokens @ ~60 days (interpolated multiplier ~1.077x)
- **Effect**: Slight increase in effective multiplier

### Scenario 3: Large Amount, Long Lockup

- **Existing**: 1,000 tokens @ 30 days (30-day lockup)
- **Adding**: 10,000 tokens @ 365 days (365-day lockup)
- **Weighted lockup**: `(30 × 1,000 + 365 × 10,000) / 11,000 = 334.5 days`
- **Result**: 11,000 tokens @ ~335 days (interpolated multiplier ~1.47x)
- **Effect**: Dramatic increase to near-maximum multiplier

### Scenario 4: Strategic Progression

- **Step 1**: Stake 1,000 tokens @ 30 days → 1.05x multiplier
- **Step 2**: Add 5,000 tokens @ 180 days → Weighted ~154 days → ~1.235x multiplier
- **Step 3**: Add 10,000 tokens @ 365 days → Weighted ~298 days → ~1.435x multiplier
- **Final**: 16,000 tokens with high effective multiplier

## Linear Interpolation for Effective Multipliers

The system uses **linear interpolation** to calculate multipliers for effective lockup periods between standard tiers:

### Between 30-90 days

```solidity
ratio = (effectiveLockup - 30_days) / (90_days - 30_days)
multiplier = 10,500 + ((11,000 - 10,500) × ratio / 10,000)
```

### Between 90-180 days

```solidity
ratio = (effectiveLockup - 90_days) / (180_days - 90_days)
multiplier = 11,000 + ((12,500 - 11,000) × ratio / 10,000)
```

### Between 180-365 days

```solidity
ratio = (effectiveLockup - 180_days) / (365_days - 180_days)
multiplier = 12,500 + ((15,000 - 12,500) × ratio / 10,000)
```

## Special Cases

### Lockup Extension

When using `increaseLockup()`:

- Calculates remaining time from current lockup
- Adds additional lockup period
- Resets weighted start time to current timestamp
- Immediately updates multiplier based on new effective lockup

### Maximum Caps

- **Maximum lockup period**: 365 days (capped)
- **Maximum multiplier**: 1.50x (15,000 basis points)
- **Minimum stake**: 1,000 tokens per operation

## Strategic Implications

### For Users

1. **Start Small**: Begin with minimum stake and short lockup to test
2. **Progressive Increases**: Add larger amounts with longer lockups to boost multiplier
3. **Weight Leverage**: Larger additional stakes have more influence on weighted average
4. **Timing Matters**: Later additions reset weighted start time

### For Protocol

1. **Incentive Alignment**: Rewards both commitment (lockup) and investment size (amount)
2. **Flexibility**: Users can gradually increase commitment without penalty
3. **No Gaming**: Weighted averages prevent manipulation through multiple small stakes

## Technical Implementation

### Data Structures

```solidity
struct UserStake {
    uint128 amount;                    // Total staked amount
    uint64 weightedStartTime;          // Weighted average start time
    uint64 effectiveLockUpPeriod;      // Weighted average lockup period
    uint32 effectiveMultiplier;        // Calculated multiplier
    // ... other fields
}
```

### Key Functions

- `_calculateWeightedValues()`: Computes new weighted averages
- `_calculateEffectiveMultiplier()`: Interpolates multiplier from lockup period
- `_getMultiplierForPeriod()`: Returns base multipliers for standard periods

## Summary

| Factor | Role | Impact |
|--------|------|--------|
| **Lockup Period** | Primary | Determines base multiplier tier |
| **Stake Amount** | Secondary | Acts as weight in averaging calculations |
| **Combination** | Synergistic | Enables progressive multiplier optimization |

The SapienVault multiplier system elegantly balances **time commitment** (lockup periods) with **capital commitment** (stake amounts), creating a fair and flexible staking mechanism that rewards both long-term holders and larger investors while maintaining system integrity through weighted averaging.
