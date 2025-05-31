# Staking Multiplier System

This document describes a **staking system** that establishes **multipliers** based on **staked amount** and **lock duration**.

---

## 🧠 Core Concept

Instead of earning rewards, users stake tokens to establish a **multiplier** for other system functions (governance, utility, etc.):

> "More tokens + longer lock = higher **multiplier**"

---

## 🧮 Multiplier Formula

The multiplier is calculated based on both **amount** and **duration**:

```
multiplier = base_multiplier + (amount_factor * duration_factor)
```

Where:
- **Base multiplier**: `1.0` (minimum multiplier)
- **Maximum multiplier**: `2.25`
- **Amount factor**: Scaled by staked amount relative to maximum
- **Duration factor**: Scaled by lock duration relative to maximum

---

## 📊 Multiplier Range

**Multiplier Range**: `1.0` to `2.25`

The multiplier is determined by two inputs:
1. **Amount**: How many tokens are staked
2. **Duration**: How long tokens are locked

---

## ⚙️ Input Parameters

### Amount Input
- **Minimum stake**: 1,000 SAPIEN tokens
- **Maximum consideration**: No hard cap, but diminishing returns after certain thresholds
- **Amount scaling**: Linear or logarithmic scaling to prevent whale dominance

### Duration Input
- **30 days**: `1.05x` multiplier
- **90 days**: `1.10x` multiplier  
- **180 days**: `1.25x` multiplier
- **365 days**: `1.50x` multiplier
- **Custom durations**: Interpolated between fixed points

---

## 🔢 Example Multiplier Calculations

Assuming a combined formula where both amount and duration contribute:

| Staked Amount | Lock Duration | Base | Duration Bonus | Amount Bonus | **Final Multiplier** |
|---------------|---------------|------|----------------|--------------|---------------------|
| 1,000 SAPIEN  | 30 days       | 1.0  | +0.05         | +0.00        | **1.05x**          |
| 10,000 SAPIEN | 90 days       | 1.0  | +0.10         | +0.15        | **1.25x**          |
| 50,000 SAPIEN | 180 days      | 1.0  | +0.25         | +0.40        | **1.65x**          |
| 100,000 SAPIEN| 365 days      | 1.0  | +0.50         | +0.75        | **2.25x**          |

---

## 🔄 Multiplier Behavior

### Time Decay
- **Option A**: Multiplier remains constant throughout lock period
- **Option B**: Multiplier decays linearly as lock time remaining decreases
- **Option C**: Multiplier maintained until unlock, then resets

### Staking Updates
- **Additional stakes**: Can increase multiplier by adding more tokens
- **Lock extensions**: Can extend duration to maintain/increase multiplier
- **Partial unstaking**: Reduces multiplier proportionally

---

## 🎯 Use Cases for Multiplier

The established multiplier can be used for:
- **Governance voting power**: `votes = tokens × multiplier`
- **Platform utility bonuses**: Enhanced features based on multiplier
- **Access tiers**: Higher multipliers unlock premium features
- **Future rewards**: If rewards are later introduced, multiplier affects distribution

---

## 🛡️ Benefits

- **Commitment rewarded**: Longer locks and larger stakes get higher multipliers
- **Flexible system**: No ongoing reward distribution complexity
- **Clear incentives**: Predictable multiplier based on stake commitment
- **Anti-gaming**: Combination of amount + duration prevents simple exploits

---

## 🔧 Implementation Considerations

### Multiplier Storage
```solidity
struct StakeInfo {
    uint256 amount;
    uint256 lockDuration;
    uint256 startTime;
    uint256 multiplier;  // Calculated and stored
    bool isActive;
}
```

### Calculation Function
```solidity
function calculateMultiplier(
    uint256 amount, 
    uint256 duration
) external pure returns (uint256) {
    // Implementation of multiplier calculation
    // Returns value between 1.0 and 2.25 (scaled by 10000)
}
```

### Multiplier Query
```solidity
function getActiveMultiplier(address user) 
    external view returns (uint256) {
    // Returns current multiplier for user
    // Accounts for any time decay if implemented
}
```
