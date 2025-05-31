# SapienVault Linear Weighted Multiplier System with Global Network Effects

## Overview

The SapienVault contract uses an advanced **Linear Weighted Multiplier System** that combines **three key factors** to determine staking rewards:

1. **Time Factor** (lockup duration) - 0% to 25% bonus
2. **Amount Factor** (stake size) - 0% to 25% bonus  
3. **Global Factor** (network participation) - 0.5x to 1.5x coefficient

This creates a fair, progressive system where both commitment (time and capital) and network health contribute to multipliers.

## Individual Multiplier Calculation

### Base Formula

```solidity
individualMultiplier = baseMultiplier + timeBonus + amountBonus
finalMultiplier = (individualMultiplier × globalCoefficient) / 10000
```

Where:
- **Base Multiplier**: 10,000 basis points (100%)
- **Time Bonus**: 0-2,500 basis points (0-25%)
- **Amount Bonus**: 0-2,500 basis points (0-25%)
- **Global Coefficient**: 5,000-15,000 basis points (0.5x-1.5x)

### 1. Time Factor (Linear Progression)

Time commitment is rewarded linearly based on lockup duration:

| Lockup Period | Time Factor | Time Bonus | Description |
|---------------|-------------|------------|-------------|
| **0 days**    | 0.0         | **0%**     | No time commitment |
| **91 days**   | 0.25        | **6.25%**  | Quarter commitment |
| **183 days**  | 0.5         | **12.5%**  | Half commitment |
| **274 days**  | 0.75        | **18.75%** | Three-quarter commitment |
| **365 days**  | 1.0         | **25%**    | Maximum commitment |

**Formula**: `timeFactor = min(lockupDays / 365, 1.0)` → `timeBonus = timeFactor × 25%`

### 2. Amount Factor (Logarithmic Progression)

Stake size is rewarded logarithmically to prevent whale dominance while encouraging larger stakes:

| Stake Amount | Amount Factor | Amount Bonus | Description |
|-------------|---------------|--------------|-------------|
| **1,000**    | 0.0          | **0%**       | Minimum stake |
| **10,000**   | ~0.25        | **~6.25%**   | Small holder |
| **100,000**  | ~0.5         | **~12.5%**   | Medium holder |
| **1,000,000** | ~0.75        | **~18.75%**  | Large holder |
| **10,000,000** | 1.0         | **25%**      | Maximum stake |

**Formula**: `amountFactor = log₁₀(amount/minStake) / log₁₀(maxAmount/minStake)` → `amountBonus = amountFactor × 25%`

### 3. Individual Multiplier Examples

| Stake | Duration | Time Bonus | Amount Bonus | Individual Total |
|-------|----------|------------|--------------|------------------|
| 1K tokens | 30 days | 2.05% | 0% | **102.05%** |
| 10K tokens | 90 days | 6.16% | ~6.25% | **112.41%** |
| 100K tokens | 180 days | 12.33% | ~12.5% | **124.83%** |
| 1M tokens | 365 days | 25% | ~18.75% | **143.75%** |
| 10M tokens | 365 days | 25% | 25% | **150%** |

## Global Network Coefficient (Sigmoid Function)

The **Global Coefficient** creates network effects that benefit all stakers based on total network participation. It uses a sigmoid-like function with three distinct zones:

### Coefficient Zones

#### Zone 1: Bootstrap Phase (0-10% staked)
- **Range**: 0.5x to 1.0x coefficient
- **Purpose**: Incentivize early adoption
- **Formula**: `5000 + (stakingRatio × 5000) / 1000`

#### Zone 2: Optimal Zone (10-50% staked)  
- **Range**: 1.0x to 1.5x coefficient
- **Purpose**: Reward healthy network participation
- **Formula**: `10000 + ((stakingRatio - 1000) × 5000) / 4000`

#### Zone 3: Over-staking Protection (50-100% staked)
- **Range**: 1.5x down to 1.0x coefficient  
- **Purpose**: Prevent excessive staking concentration
- **Formula**: `15000 - ((stakingRatio - 5000) × 5000) / 5000`

### Global Coefficient Examples

| Network Staked | Staking Ratio | Global Coefficient | Effect |
|----------------|---------------|-------------------|---------|
| **5%** | 500 BP | **0.75x** | Bootstrap incentive |
| **10%** | 1,000 BP | **1.0x** | Neutral baseline |
| **20%** | 2,000 BP | **1.125x** | Healthy growth |
| **30%** | 3,000 BP | **1.25x** | Strong participation |
| **50%** | 5,000 BP | **1.5x** | Peak optimization |
| **70%** | 7,000 BP | **1.25x** | Over-concentration warning |
| **100%** | 10,000 BP | **1.0x** | Maximum dampening |

## Complete Multiplier Examples

### Example 1: Small Stake, Network Growth
- **Stake**: 10K tokens, 180 days
- **Individual**: 112.41% (base + 6.16% time + 6.25% amount)
- **Network**: 20% staked → 1.125x coefficient
- **Final**: 112.41% × 1.125 = **126.46%**

### Example 2: Large Stake, Optimal Network
- **Stake**: 1M tokens, 365 days  
- **Individual**: 143.75% (base + 25% time + 18.75% amount)
- **Network**: 50% staked → 1.5x coefficient
- **Final**: 143.75% × 1.5 = **215.63%**

### Example 3: Maximum Theoretical
- **Stake**: 10M tokens, 365 days
- **Individual**: 150% (base + 25% time + 25% amount)
- **Network**: 50% staked → 1.5x coefficient  
- **Final**: 150% × 1.5 = **225%**

## Weighted Average System (Stake Combinations)

When combining multiple stakes through `increaseAmount()` or additional `stake()` calls:

### Weighted Formulas

```solidity
// Weighted lockup calculation
newEffectiveLockup = (existingLockup × existingAmount + newLockup × newAmount) / totalAmount

// Weighted start time calculation  
newWeightedStartTime = (existingStartTime × existingAmount + currentTime × newAmount) / totalAmount

// Final multiplier recalculated with new total amount and weighted lockup
finalMultiplier = calculateLinearWeightedMultiplier(totalAmount, newEffectiveLockup)
```

### Combination Examples

#### Progressive Staking Strategy
1. **Initial**: 10K tokens @ 90 days → ~112% multiplier
2. **Add**: 50K tokens @ 365 days → Weighted ~306 days → ~136% individual 
3. **Add**: 100K tokens @ 365 days → Weighted ~342 days → ~142% individual
4. **Final**: 160K tokens with strong individual + network multipliers

#### Impact of Network Growth
As the network grows during your staking period, your effective multiplier improves automatically through the global coefficient.

## Strategic Implications

### For Individual Stakers

1. **Both Time and Amount Matter**: Maximum rewards require both long lockups AND significant stakes
2. **Progressive Building**: Start small and add larger amounts with longer lockups to optimize weighted averages
3. **Network Timing**: Early stakers benefit as network participation grows
4. **Logarithmic Amount Scaling**: Diminishing returns prevent whale dominance while rewarding scale

### For Network Health

1. **Balanced Incentives**: System rewards both commitment types equally (time vs capital)
2. **Network Effects**: All stakers benefit when participation reaches optimal levels
3. **Anti-Concentration**: Over-staking protection prevents excessive centralization
4. **Bootstrap Support**: Lower participation is incentivized to reach optimal levels

## Technical Implementation

### Core Functions

```solidity
// Main calculation function
function _calculateLinearWeightedMultiplier(uint256 amount, uint256 effectiveLockup) 
    returns (uint256 finalMultiplier)

// Individual multiplier components
function _calculateIndividualMultiplier(uint256 amount, uint256 effectiveLockup)
    returns (uint256 individualMultiplier)

// Global network effects
function _calculateGlobalCoefficient() 
    returns (uint256 globalCoefficient)

// Logarithmic amount scaling
function _calculateAmountFactor(uint256 amount)
    returns (uint256 amountFactor)
```

### Public View Functions

```solidity
// Get detailed breakdown for any stake scenario
function getMultiplierBreakdown(uint256 amount, uint256 duration)
    returns (
        uint256 individualMultiplier,
        uint256 globalCoefficient, 
        uint256 finalMultiplier,
        uint256 stakingRatio
    )

// Get current network statistics
function getGlobalStakingStats()
    returns (
        uint256 totalStakedAmount,
        uint256 totalSupplyAmount,
        uint256 stakingRatioBasisPoints,
        uint256 globalCoefficient
    )
```

## System Constants

### Multiplier Bounds
- **Base Multiplier**: 10,000 basis points (100%)
- **Maximum Individual**: 15,000 basis points (150%)  
- **Maximum Final**: 22,500 basis points (225%)
- **Minimum Final**: 5,000 basis points (50%)

### Amount Scaling
- **Minimum Stake**: 1,000 tokens
- **Maximum Amount Factor**: 10,000,000 tokens
- **Logarithmic Base**: 10

### Global Coefficient Range
- **Minimum**: 5,000 basis points (0.5x)
- **Maximum**: 15,000 basis points (1.5x)
- **Optimal Zone**: 10-50% network participation

## Summary

| Component | Range | Purpose |
|-----------|-------|---------|
| **Time Bonus** | 0-25% | Reward long-term commitment |
| **Amount Bonus** | 0-25% | Reward capital commitment (logarithmic) |
| **Global Coefficient** | 0.5x-1.5x | Create network effects and prevent over-concentration |
| **Final Range** | 50-225% | Comprehensive reward spectrum |

The SapienVault Linear Weighted Multiplier System creates a sophisticated, fair, and network-aware staking mechanism that:

- **Requires both time AND capital commitment** for maximum rewards
- **Prevents whale dominance** through logarithmic amount scaling
- **Creates positive network effects** that benefit all participants
- **Maintains healthy decentralization** through over-staking protection
- **Supports network growth** with bootstrap incentives

This design ensures the protocol remains both attractive to large stakeholders and accessible to smaller participants, while maintaining optimal network health through intelligent economic incentives.
