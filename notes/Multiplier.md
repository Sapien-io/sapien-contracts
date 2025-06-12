# Multiplier Library Documentation

**Title**: Multiplier – Sapien AI Staking Multiplier Calculator  
**Type**: Solidity Library  
**License**: BSD-3-Clause  
**Version**: Solidity 0.8.30  

---

## Overview

The `Multiplier` library provides comprehensive reward multiplier calculations for the Sapien AI staking system. It implements a sophisticated tier-based matrix system that calculates multipliers based on two primary variables: stake amount and lockup duration. The library supports both discrete tier calculations and linear interpolation for intermediate values.

---

## Mathematical Formula

The multiplier calculation follows this core formula:

**Final Multiplier = Duration Base Multiplier + Amount Tier Bonus**

Where:
- **Duration Base Multiplier**: Base multiplier determined by lockup period
- **Amount Tier Bonus**: Additional bonus based on staked amount tier

### Formula Implementation
```solidity
Final Multiplier = getDurationMultiplier(lockUpPeriod) + 
                  (getAmountTierFactor(amount) * (MAX_MULTIPLIER - MIN_MULTIPLIER) / BASIS_POINTS)
```

---

## Multiplier Matrix

| **Time Period** | ≤1K    | 1K–2.5K | 2.5K–5K | 5K–7.5K | 7.5K–10K | 10K+   |
|-----------------|--------|---------|---------|---------|----------|--------|
| **30 days**     | 1.05x  | 1.14x   | 1.23x   | 1.32x   | 1.41x    | 1.50x  |
| **90 days**     | 1.10x  | 1.19x   | 1.28x   | 1.37x   | 1.46x    | 1.55x  |
| **180 days**    | 1.25x  | 1.34x   | 1.43x   | 1.52x   | 1.61x    | 1.70x  |
| **365 days**    | 1.50x  | 1.59x   | 1.68x   | 1.77x   | 1.86x    | 1.95x  |

**Note**: All multipliers expressed in basis points (10000 = 1.00x)

---

## Core Functions

### Primary Calculation Function

#### `calculateMultiplier(uint256 amount, uint256 lockUpPeriod)`
```solidity
function calculateMultiplier(uint256 amount, uint256 lockUpPeriod) 
    internal pure returns (uint256)
```

Calculates the complete multiplier for a given stake based on amount and lockup period.

**Parameters:**
- `amount`: Staked token amount (in wei, 18 decimals)
- `lockUpPeriod`: Lockup duration in seconds

**Returns:** Multiplier in basis points (e.g., 15000 = 1.50x)

**Validation:**
- Lockup period must be between 30-365 days
- Amount must meet minimum stake requirements
- Reverts with appropriate errors for invalid inputs

**Implementation Details:**
1. Validates input parameters
2. Calculates base duration multiplier
3. Determines amount tier factor
4. Combines factors using additive formula
5. Returns final multiplier in basis points

### Duration Multiplier Calculation

#### `getDurationMultiplier(uint256 lockUpPeriod)`
```solidity
function getDurationMultiplier(uint256 lockUpPeriod) 
    internal pure returns (uint256 multiplier)
```

Calculates base multiplier for lockup duration using discrete values or linear interpolation.

**Discrete Periods:**
- 30 days: 10500 basis points (1.05x)
- 90 days: 11000 basis points (1.10x)
- 180 days: 12500 basis points (1.25x)
- 365 days: 15000 basis points (1.50x)

**Interpolation:**
For non-discrete periods, uses linear interpolation between known points:
- 30-90 days: Interpolates between 1.05x and 1.10x
- 90-180 days: Interpolates between 1.10x and 1.25x
- 180-365 days: Interpolates between 1.25x and 1.50x

### Amount Tier Calculation

#### `getAmountTierFactor(uint256 amount)`
```solidity
function getAmountTierFactor(uint256 amount) 
    internal pure returns (uint256 factor)
```

Determines tier factor based on staked amount using discrete thresholds.

**Tier Structure:**

| Amount Range (Tokens) | Basis Points | Multiplier Weight | Tier |
|------------------------|--------------|-------------------|------|
| < 1,000               | 0            | 0.00x             | 0    |
| 1,000–2,499           | 2000         | 0.09x             | 1    |
| 2,500–4,999           | 4000         | 0.18x             | 2    |
| 5,000–7,499           | 6000         | 0.27x             | 3    |
| 7,500–9,999           | 8000         | 0.36x             | 4    |
| ≥ 10,000              | 10000        | 0.45x             | 5    |

**Implementation:**
- Converts amount from wei to token units (divides by TOKEN_DECIMALS)
- Uses threshold comparisons for tier assignment
- Returns percentage factor (0-10000 basis points)

### Linear Interpolation

#### `interpolate(uint256 x, uint256 x1, uint256 x2, uint256 y1, uint256 y2)`
```solidity
function interpolate(uint256 x, uint256 x1, uint256 x2, uint256 y1, uint256 y2) 
    internal pure returns (uint256)
```

Performs linear interpolation between two points for smooth multiplier transitions.

**Parameters:**
- `x`: Input value to interpolate
- `x1`, `x2`: Input bounds (x1 < x2)
- `y1`, `y2`: Output bounds corresponding to x1, x2

**Validation:**
- Requires x2 > x1 (ascending input)
- Requires y2 >= y1 (non-decreasing output)
- Requires x1 <= x <= x2 (input within bounds)

**Formula:** `y1 + ((x - x1) * (y2 - y1)) / (x2 - x1)`

---

## Constants Integration

The library integrates with `Constants.sol` for system-wide consistency:

### Lockup Periods
- `LOCKUP_30_DAYS = 30 days`
- `LOCKUP_90_DAYS = 90 days`
- `LOCKUP_180_DAYS = 180 days`
- `LOCKUP_365_DAYS = 365 days`

### Multiplier Bounds
- `MIN_MULTIPLIER = 10500` (1.05x)
- `MAX_MULTIPLIER = 15000` (1.50x)
- `BASIS_POINTS = 10000` (100%)

### Token Configuration
- `TOKEN_DECIMALS = 1e18` (18 decimal places)
- `MINIMUM_STAKE_AMOUNT = 250 * TOKEN_DECIMALS`

### Tier Thresholds (in tokens, excluding decimals)
- `TIER_1_THRESHOLD = 1000` (1,000 tokens)
- `TIER_2_THRESHOLD = 2500` (2,500 tokens)
- `TIER_3_THRESHOLD = 5000` (5,000 tokens)
- `TIER_4_THRESHOLD = 7500` (7,500 tokens)
- `TIER_5_THRESHOLD = 10000` (10,000 tokens)

---

## Validation and Error Handling

### Input Validation
The library performs comprehensive validation:

```solidity
// Lockup period validation
if (lockUpPeriod < Const.LOCKUP_30_DAYS || lockUpPeriod > Const.LOCKUP_365_DAYS) {
    revert ISapienVault.InvalidLockupPeriod();
}

// Minimum stake validation
if (amount < Const.MINIMUM_STAKE_AMOUNT) {
    revert ISapienVault.MinimumStakeAmountRequired();
}
```

### Error Conditions
- `InvalidLockupPeriod()`: Lockup outside 30-365 day range
- `MinimumStakeAmountRequired()`: Amount below minimum threshold
- Interpolation errors for invalid bounds or parameters

---

## Implementation Examples

### Basic Calculation
```solidity
uint256 amount = 3000 * 1e18;        // 3,000 tokens
uint256 lockup = 90 days;            // 90-day lockup

uint256 multiplier = Multiplier.calculateMultiplier(amount, lockup);
// Result: 12800 basis points (1.28x)

// Breakdown:
// - Duration: 1.10x (11000 basis points)
// - Tier factor: 40% (4000 basis points)
// - Tier bonus: 4000 * 4500 / 10000 = 1800 basis points
// - Total: 11000 + 1800 = 12800 (1.28x)
```

### Edge Case Examples
```solidity
// Minimum stake, minimum lockup
uint256 minMultiplier = Multiplier.calculateMultiplier(250 * 1e18, 30 days);
// Result: 10500 (1.05x) - Tier 0, no bonus

// Maximum tier, maximum lockup
uint256 maxMultiplier = Multiplier.calculateMultiplier(15000 * 1e18, 365 days);
// Result: 19500 (1.95x) - Maximum possible multiplier

// Interpolated lockup
uint256 interpMultiplier = Multiplier.calculateMultiplier(5000 * 1e18, 45 days);
// Result: Interpolated between 30-day and 90-day base multipliers
```

---

## Security Considerations

### Pure Function Design
- **No State Changes**: All functions are pure, preventing external state modification
- **Deterministic**: Same inputs always produce same outputs
- **Gas Efficient**: No storage reads or writes

### Input Validation
- **Bounds Checking**: All parameters validated against defined ranges
- **Overflow Protection**: Uses SafeCast for type conversions
- **Zero Handling**: Proper handling of edge cases and zero values

### Mathematical Precision
- **Integer Arithmetic**: Uses integer math to avoid floating-point precision issues
- **Basis Points**: Consistent use of basis points (10000 = 100%) for precision
- **Interpolation Safety**: Validates interpolation bounds to prevent calculation errors

---

## Integration Notes

### Library Usage
```solidity
import {Multiplier} from "src/Multiplier.sol";

// Direct usage in contracts
uint256 userMultiplier = Multiplier.calculateMultiplier(stakeAmount, lockupPeriod);
```

### Gas Optimization
- **Library Implementation**: Deployed as library for code reuse
- **Pure Functions**: No state access reduces gas costs
- **Efficient Calculations**: Optimized arithmetic operations

### Interface Compatibility
- Compatible with `ISapienVault` interface requirements
- Supports all SapienVault multiplier calculation needs
- Consistent with broader protocol design patterns

---

## Testing and Validation

### Matrix Verification
The implementation has been extensively tested to ensure:
- Exact matches for all discrete multiplier matrix values
- Correct interpolation for intermediate lockup periods
- Proper tier boundary handling
- Edge case robustness

### Invariant Properties
- Multipliers increase monotonically with amount and duration
- Tier boundaries produce expected jumps in multiplier values
- Interpolation produces smooth transitions between discrete periods
- All calculations remain within expected bounds

---

## Usage in SapienVault

The Multiplier library is integrated into SapienVault for:
- **Initial Stake Calculation**: Computing multiplier for new stakes
- **Stake Combination**: Calculating effective multipliers for combined stakes
- **UI Display**: Providing multiplier information for user interfaces
- **Reward Distribution**: Supporting reward calculation systems

The library provides the mathematical foundation for the protocol's reputation and reward systems, ensuring fair and predictable multiplier calculations across all user interactions.