# Consensus Algorithm

The protocol uses a single, unified consensus algorithm implemented in `ConsensusLib`.

## Algorithm: Stake-Weighted Consensus with Outlier Detection

**File:** `src/libraries/ConsensusLib.sol`

### Weight Calculation

```
weight = sqrt(stake) × effectiveReputation
effectiveReputation = max(reputation, MIN_REPUTATION_FLOOR = 100)
```

This formula provides:
- **Whale resistance**: `sqrt(stake)` ensures sublinear scaling — doubling your stake only increases weight by ~41%
- **Quality alignment**: Reputation factor rewards consistent accuracy
- **Newcomer inclusion**: Minimum reputation floor of 100 ensures new validators always have some influence

### Algorithm Steps

**Pass 1 — Weighted Sum**

For each validator, compute weight and accumulate the weighted sum:

```
totalWeight = Σ(weight_i)
weightedSum = Σ(score_i × weight_i)
weightedAverage = weightedSum / totalWeight
```

Uses high-precision arithmetic (1e18) to avoid rounding errors.

**Pass 2 — Standard Deviation**

Compute the weighted variance and take the square root:

```
variance = Σ(weight_i × (score_i - weightedAverage)²) / totalWeight
stdDev = sqrt(variance)
```

**Pass 3 — Outlier Classification**

Flag validators whose deviation from the mean exceeds tiered thresholds:

| Tier | Deviation Threshold | Slash Percentage | Description |
|------|-------------------|-----------------|-------------|
| Accurate | ≤ 1.5σ | 0% | Earns rewards |
| Tier 1 | > 1.5σ | 10% of stake | Mild disagreement |
| Tier 2 | > 2.0σ | 25% of stake | Significant deviation |
| Tier 3 | > 3.0σ | 50% of stake | Extreme deviation |
| Tier 4 | > 5.0σ | 100% of stake | Malicious outlier |

### Output

```solidity
struct ConsensusResult {
    uint256 weightedAverage;      // Final consensus score (0–10,000)
    uint256 stdDeviation;         // Standard deviation (precision-scaled)
    address[] validators;         // Ordered validator addresses
    bool[] isOutlier;             // Per-validator outlier flag
    uint256[] slashAmounts;       // Per-validator slash amount (in tokens)
    uint256[] weights;            // Per-validator weight
    uint256 totalAccurateWeight;  // Sum of weights for non-outlier validators
}
```

## How it Works: Example

**Scenario:** 3 validators assess a contribution

| Validator | Score | Stake | Reputation | Weight (sqrt × rep) |
|-----------|-------|-------|------------|-------------------|
| V1 | 8,500 | 10,000 | 7,000 | 100 × 7,000 = 700,000 |
| V2 | 8,000 | 5,000 | 6,000 | 70.7 × 6,000 = 424,264 |
| V3 | 3,000 | 2,000 | 5,000 | 44.7 × 5,000 = 223,607 |

**Weighted average**: ~7,215

**Standard deviation**: Computed from weighted variance

**Classification**:
- V1 (8,500): Within 1.5σ → **Accurate** → Earns rewards
- V2 (8,000): Within 1.5σ → **Accurate** → Earns rewards
- V3 (3,000): > 5σ deviation → **Tier 4 Outlier** → 100% stake slashed

**Contribution outcome**: If consensus threshold is 7,000 (70%), score 7,215 ≥ 7,000 → **Accepted**

## Reward Distribution

Accurate validators share the validator reward pool proportional to their consensus weight:

```
validatorReward = (totalRewards × validatorRewardBps × weight) / (BPS × totalQuantity × totalAccurateWeight)
```

Contributors receive the remaining share:

```
contributorReward = rewardRate × (BPS - validatorRewardBps) / BPS
```

Where `rewardRate = totalRewards / totalQuantity`.

## Why a Single Algorithm?

A single consensus algorithm is the right design for the protocol:

1. **Simplicity** — one well-tested path reduces attack surface and audit burden
2. **No trade-off decisions** — originators don't need to reason about algorithm security properties
3. **Comprehensive** — it incorporates `sqrt(stake)` whale resistance, reputation weighting, and tiered slashing in a single formula

## Security Properties

| Threat | Mitigation |
|--------|------------|
| Whale controls consensus | `sqrt(stake)` provides sublinear scaling |
| Sybil attack (many accounts) | Weight = `sqrt(stake) × reputation` — expensive to build both |
| Lazy validation | Tiered slashing penalizes outliers proportionally |
| Score herding | Commit-reveal hides scores until all committed |
| Ghost validators | `cancelExpiredCommitment` slashes non-revealers |
| Coordinated outlier attack | Standard deviation naturally penalizes coordinated groups |
