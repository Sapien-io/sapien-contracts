# Confidence-Based Staking

Sapien's validation system treats stake as a **confidence signal**. Rather than requiring a flat stake from every validator, the protocol allows each validator to choose how much to stake on each individual validation. A higher stake says "I am very confident in this score"; a lower stake says "I am less certain." This variable stake directly affects the validator's consensus weight, their potential reward, and the severity of their penalty if they turn out to be an outlier.

---

## Core Mechanic: Stake as Conviction

When a validator commits a score for a contribution, they simultaneously lock a chosen amount of tokens. This amount is bounded only by:

- A **minimum stake** set per-project (or a global minimum, whichever is higher)
- The validator's **available capacity** (tokens previously locked for validation use)

There is no maximum. A validator who has deep conviction in their assessment can stake far more than the minimum, and the protocol rewards that conviction — or punishes it — accordingly.

---

## How Stake Affects Weight

Each validator's influence on the final consensus score is determined by:

```
weight = sqrt(stake) × effectiveReputation
```

| Component | Role |
|-----------|------|
| `sqrt(stake)` | Converts the raw stake into a sublinear influence factor. Doubling your stake increases your weight by only ~41%, not 2×. This prevents whales from dominating consensus while still rewarding higher conviction. |
| `effectiveReputation` | The validator's on-chain reputation score, floored at 1,000 so that newcomers always have baseline influence. Reputation grows with accurate validations and decays with inaccurate ones. |

The final consensus score is a **weighted average** of all revealed scores, where each score is weighted by the formula above. Validators who stake more and have higher reputation pull the average more strongly toward their assessment.

### Sublinear Scaling in Practice

| Stake | sqrt(stake) | Relative Weight (at equal reputation) |
|------:|------------:|--------------------------------------:|
| 1,000 | ~31.6 | 1.0× |
| 4,000 | ~63.2 | 2.0× |
| 10,000 | 100.0 | 3.2× |
| 40,000 | 200.0 | 6.3× |
| 100,000 | 316.2 | 10.0× |

A validator staking 100× more than another gains only 10× the weight. This is the protocol's whale-resistance mechanism: capital alone cannot buy disproportionate control over outcomes.

---

## Reward Amplification

When consensus is reached and a contribution is accepted, the reward pool for validators is distributed proportionally to each **accurate** validator's weight:

```
validatorReward = totalRewardPool × validatorRewardBps × weight
                  ─────────────────────────────────────────────
                          BPS × totalQuantity × totalAccurateWeight
```

Because weight scales with `sqrt(stake)`, higher-conviction validators earn a larger share of the reward pool. This is the protocol's incentive for validators to put real capital behind assessments they believe in rather than staking the bare minimum.

### Example: Reward Difference from Confidence

Two validators assess the same contribution. Both score within consensus (accurate). Both have a reputation of 5,000.

| Validator | Stake | Weight | Share of Reward Pool |
|-----------|------:|-------:|---------------------:|
| Alice | 1,000 | 158,114 | 33.3% |
| Bob | 10,000 | 500,000 | 66.7% (← 2× the share for a confident stake) |

Bob staked 10× more than Alice but receives only ~2× the reward share, not 10×. The sublinear scaling protects the system while still meaningfully rewarding conviction.

---

## Slash Amplification

The same variable stake that amplifies rewards also amplifies penalties. When a validator's score deviates too far from the weighted consensus, they are classified as an **outlier** and slashed based on how extreme their deviation is. The slash is computed as a percentage of their **actual staked amount**, not a flat fee.

### Outlier Classification

After the weighted average and standard deviation (σ) are computed, each validator's score is measured against the consensus:

```
deviation = |validatorScore − weightedAverage|
```

If the deviation exceeds 1.5σ, the validator is flagged as an outlier and enters the tiered slash schedule:

| Tier | Deviation | Slash | Interpretation |
|------|-----------|-------|----------------|
| Accurate | ≤ 1.5σ | 0% | Within consensus — earns rewards |
| Tier 1 | > 1.5σ | 10% of stake | Mild disagreement |
| Tier 2 | > 2.0σ | 25% of stake | Significant deviation |
| Tier 3 | > 3.0σ | 50% of stake | Extreme deviation |
| Tier 4 | > 5.0σ | 100% of stake | Presumed malicious — total loss |

### Why This Matters for Confidence Staking

A validator who stakes 50,000 tokens and lands in Tier 2 loses **12,500 tokens** (25%). A validator who stakes 1,000 tokens and lands in the same tier loses only **250 tokens**. The protocol is saying: *if you express high confidence and you are wrong, the penalty is proportional to the confidence you expressed.*

This creates a natural equilibrium:

- **Confident and correct** → larger reward share
- **Confident and wrong** → larger absolute loss
- **Conservative and correct** → smaller but safe reward
- **Conservative and wrong** → manageable loss

---

## The Confidence Decision

Every validation is a risk-reward decision. Before committing, a validator implicitly answers: "How certain am I that my score will land within 1.5 standard deviations of where everyone else lands?"

### High-Confidence Strategy (large stake)

**When to use:** The validator has domain expertise, has reviewed the contribution carefully, and believes their score reflects genuine quality.

- **If correct:** Earns a disproportionately large share of the reward pool due to higher weight.
- **If outlier:** Faces a proportionally large slash. A Tier 3 outlier at 50,000 stake loses 25,000 tokens.

### Low-Confidence Strategy (minimum stake)

**When to use:** The validator is less certain — perhaps the contribution is in an unfamiliar domain, or the quality is genuinely ambiguous.

- **If correct:** Earns a smaller but non-zero share. The minimum reputation floor (1,000) ensures even low-stake validators contribute to consensus.
- **If outlier:** Loses a small absolute amount. A Tier 3 outlier at the minimum stake loses far less capital.

### The Optimal Play

The protocol is designed so that the **expected-value-maximizing strategy** is:

1. **Stake high when you genuinely know** — your domain expertise gives you a statistical edge, and the reward amplification makes high conviction profitable.
2. **Stake low when you are uncertain** — protect capital while still participating and earning reputation.
3. **Never stake high to bluff** — the outlier penalty makes over-confident bad assessments the most expensive mistake in the system.

---

## Interaction with Reputation

Stake and reputation are **multiplicative** in the weight formula. This creates compound effects:

| Scenario | Stake | Reputation | Weight | Outcome |
|----------|------:|----------:|-------:|---------|
| Expert, confident | 20,000 | 8,000 | 1,131,371 | Highest influence and reward share |
| Expert, cautious | 2,000 | 8,000 | 357,771 | Moderate influence, protected downside |
| Newcomer, confident | 20,000 | 1,000 (floor) | 141,421 | Influence limited by low reputation |
| Newcomer, cautious | 2,000 | 1,000 (floor) | 44,721 | Low influence, low risk — reputation building phase |

A newcomer who stakes aggressively still has limited influence because their reputation is at the floor (1,000). This protects the system from new entrants trying to sway consensus with capital alone. As they accumulate accurate validations and their reputation grows, the same stake level produces increasingly more weight.

Conversely, a high-reputation validator who loses confidence in a particular assessment can reduce their stake without losing their accumulated reputation advantage on future validations.

---

## Economic Invariants

The confidence-staking system maintains several protocol-level guarantees:

1. **Slash proceeds never exceed what was staked.** The maximum slash (Tier 4, 100%) takes only the staked amount, never more.

2. **Rewards are zero-sum from the project escrow.** Validator rewards come from the project's pre-funded reward pool, split between contributors and validators via `validatorRewardBps`.

3. **Weight cannot be zero.** Even at minimum stake and minimum reputation, `sqrt(minStake) × 1,000` produces a positive weight, ensuring every revealed score influences the outcome.

4. **Reputation decays independently of stake.** A validator who stops participating sees their reputation decay over time (configurable `decayRateBps` per day), reducing their future weight even if they later return with a large stake. Consistent participation is rewarded.

---

## Summary

| Action | Low Stake | High Stake |
|--------|-----------|------------|
| Score within consensus | Small reward | Large reward |
| Mild outlier (> 1.5σ) | 10% of small stake lost | 10% of large stake lost |
| Extreme outlier (> 5σ) | 100% of small stake lost | 100% of large stake lost |
| Weight contribution | Low influence on consensus | High influence on consensus |

The confidence-based staking system aligns economic incentives with honest, thoughtful validation. Validators are free to express exactly how sure they are, and the protocol translates that expression into proportional influence, proportional reward, and proportional risk.
