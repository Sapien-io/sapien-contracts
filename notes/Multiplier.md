# 📈 Multiplier Contract

**Title**: Multiplier – Sapien AI Staking Multiplier Calculator  
**Author**: Sapien AI Core Team  
**License**: BSD-3-Clause  
**Version**: Solidity 0.8.30  

---

## 🧠 Overview

The `Multiplier` contract provides reward multiplier calculations for the Sapien AI staking system based on two primary variables:

- **Stake Amount**
- **Lock-up Duration**

It supports a discrete tier-based matrix with optional interpolation for time values, ensuring a flexible and fair staking rewards system.

---

## 🧮 Multiplier Matrix

| **Time Period** | ≤1K    | 1K–2.5K | 2.5K–5K | 5K–7.5K | 7.5K–10K | 10K+   |
|-----------------|--------|---------|---------|---------|----------|--------|
| **30 days**     | 1.05x  | 1.14x   | 1.23x   | 1.32x   | 1.41x    | 1.50x  |
| **90 days**     | 1.10x  | 1.19x   | 1.28x   | 1.37x   | 1.46x    | 1.55x  |
| **180 days**    | 1.25x  | 1.34x   | 1.43x   | 1.52x   | 1.61x    | 1.70x  |
| **365 days**    | 1.50x  | 1.59x   | 1.68x   | 1.77x   | 1.86x    | 1.95x  |

> 📌 **Formula**:  
> `Final Multiplier = Duration Multiplier + (Tier Factor × 0.45x)`

---

## 🧩 Core Functions

### `calculateMultiplier(uint256 amount, uint256 lockUpPeriod) → uint256`

Calculates the total multiplier for a given stake based on the lock-up period and amount staked.

- Returns `0` if the lock-up period or amount is invalid.
- Uses a linear interpolation between discrete lock-up durations.
- Multiplier is returned in basis points (e.g., 15000 = 1.50x).

---

### `getDurationMultiplier(uint256 lockUpPeriod) → uint256`

Returns a base multiplier for lock-up duration using predefined constants or interpolates if the duration falls between defined tiers.

---

### `getAmountTierFactor(uint256 amount) → uint256`

Determines the tier factor (0 to 10000 basis points) based on the staked amount:

| Amount Range (Tokens) | Basis Points | Multiplier Weight |
|------------------------|--------------|-------------------|
| ≤ 1,000               | 0            | 0.00x             |
| 1,001–2,499           | 2000         | 0.09x             |
| 2,500–4,999           | 4000         | 0.18x             |
| 5,000–7,499           | 6000         | 0.27x             |
| 7,500–9,999           | 8000         | 0.36x             |
| ≥ 10,000              | 10000        | 0.45x             |

---

### `interpolate(x, x1, x2, y1, y2) → uint256`

Performs linear interpolation to find the output `y` for a given input `x` between points `(x1, y1)` and `(x2, y2)`.

---

### `isValidLockupPeriod(lockUpPeriod) → bool`

Checks if the given lock-up period is within the supported range (30 to 365 days).

---

## 🧱 Constants (Expected from `Constants.sol`)

- `LOCKUP_30_DAYS = 30 days`
- `LOCKUP_90_DAYS = 90 days`
- `LOCKUP_180_DAYS = 180 days`
- `LOCKUP_365_DAYS = 365 days`
- `MIN_MULTIPLIER = 10500`
- `MAX_MULTIPLIER = 15000`
- `BASIS_POINTS = 10000`
- `TOKEN_DECIMALS = 1e18`
- `MINIMUM_STAKE_AMOUNT = 1000 * 1e18`

Tier Factors (as token thresholds):

- `T1_FACTOR = 1000`
- `T2_FACTOR = 2500`
- `T3_FACTOR = 5000`
- `T4_FACTOR = 7500`
- `T5_FACTOR = 10000`

---

## ✅ Example

**Input**:
- Amount: 3,000 tokens
- Lock-up: 90 days

**Output**:
- Duration Multiplier: 1.10x (11000 basis points)
- Tier Factor: 40% → 0.18x (4000 basis points × 0.45 = 1800)
- **Total**: `11000 + 1800 = 12800` → **1.28x**

---

## 🔒 Security and Validation Notes

- Strict input validation ensures safety against invalid lock-ups or zero-stake edge cases.
- No external state changes; all logic is pure and deterministic.
- Easily extendable with future tier ranges or interpolated multiplier scaling.

---

## 🔗 Interfaces & Dependencies

- `IMultiplier.sol`: Interface declaration
- `Constants.sol`: Static configuration values for time/tiers

---

## 🛠️ Use Cases

- Calculate staking rewards based on dynamic user choices
- Simulate multiplier values in UI/UX
- Integrate into reward contracts or dashboards for dynamic yield calculation

---