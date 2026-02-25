# Mechanism Design Findings

**Date:** 2026-02-24
**Scope:** ConsensusLib, ReputationLib, ValidationLib, FinalizationLib
**Focus:** Adversarial resilience, economic incentive alignment, edge-case stability

---

## Overall Assessment

The confidence-based staking design is elegant and directionally correct. Using `sqrt(stake) × reputation` balances whale resistance with long-term credibility, and the variable stake model properly aligns conviction with economic risk. The σ-based tiered slashing is adaptive and more sophisticated than fixed thresholds. The incentive structure makes sense: stake high when you have edge, stake low when uncertain, never bluff.

---

## Findings

### 1. Collusion Risk — Coordinated High-Rep Validators Can Skew Consensus

**Severity:** High
**Location:** `ConsensusLib.sol:106-111`

Outlier detection is purely statistical — it assumes the majority is honest. If 4 out of 5 validators collude and score identically, the 1 honest validator becomes the "outlier" and gets slashed. The colluders face zero penalty because the σ-based detection has no notion of ground truth.

```solidity
if (stdDev > 0 && deviation > (stdDev * TIER_1_THRESHOLD) / PRECISION) {
    isOutlier[i] = true;
    slashAmounts[i] = _computeSlash(deviation, stdDev, inputs[i].stakeAmount);
} else {
    totalAccurateWeight += weights[i];
}
```

**Mitigations:**

- **Validator assignment randomization:** Instead of self-selection, assign validators pseudo-randomly (block hash + project seed) to prevent cartels from guaranteeing co-assignment.
- **Maximum overlap cap:** Limit how many times the same set of validators can validate together within a project (track pair-wise co-validation counts).
- **Cross-round correlation monitoring:** Track whether the same clique consistently validates together and scores identically; flag via disputes.
- **Dispute escalation for pattern detection:** Strengthen the on-chain evidence path for operator-filed disputes when correlated behavior is detected.

---

### 2. Thin Validator Sets Create σ Instability

**Severity:** Medium
**Location:** `ConsensusLib.sol:81`, `Constants.sol` (no enforced minimum `numberOfValidations`)

With only 3 validators (the default), standard deviation is statistically fragile. One validator scoring slightly differently can unpredictably trigger or avoid outlier detection. With 3 data points, σ is inherently noisy.

Confirmed by tests: scores 7200/6800/7000 produce σ ≈ 163 BPS. Maximum deviation (200) is below 1.5σ (245), so no outliers. But shifting one score to 7400 could suddenly trigger detection. Small input changes produce discontinuous outcomes.

**Mitigations:**

- **Minimum validator count floor:** Enforce `numberOfValidations >= 5` in `createProject`. With 5+ validators, σ stabilizes meaningfully.
- **Minimum σ threshold:** Add a floor below which outlier detection is disabled entirely — if all validators roughly agree (σ < ~200 BPS), treat everyone as accurate.
- **Confidence weighting by n:** Scale the outlier threshold dynamically — e.g., require `1.5σ × sqrt(5/n)` deviation, so smaller sets need proportionally larger deviations.

---

### 3. Reputation Floor Allows Large-Capital Newcomers Meaningful Influence

**Severity:** Medium
**Location:** `ConsensusLib.sol:47-49`

`MIN_REPUTATION_FLOOR` is 1,000. A brand new validator with zero history gets `effectiveRep = 1000`. A 10-round veteran with a perfect record has ~5,100. That's only a 5.1× reputation multiplier. Meanwhile, `sqrt(stake)` grows without bound — staking 25× more gives `sqrt(25) = 5×` in stake weight, essentially neutralizing the reputation advantage.

```solidity
uint256 effectiveRep = inp.reputation < MIN_REPUTATION_FLOOR ? MIN_REPUTATION_FLOOR : inp.reputation;
uint256 sqrtStake = Math.sqrt(inp.stakeAmount);
uint256 w = sqrtStake * effectiveRep;
```

**Mitigations:**

- **Reduce `MIN_REPUTATION_FLOOR`:** Drop to 100 or 1, requiring newcomers 2,500×–25,000,000× more stake to match reputation weight. Simplest lever.
- **Exponential reputation scaling:** Use `reputation^1.5` instead of linear, widening the gap between veterans and newcomers.
- **Probation period:** Require N successful low-stake validations before allowing high-stake commitments.
- **Project-level reputation gate:** Already exists (`minValidatorReputation` on Project struct). Originators can exclude newcomers. Confirmed working via `test_reputationGateBlocksDegradedValidators`.

---

### 4. No Flash Staking Protection

**Severity:** Medium
**Location:** `SapienVault.sol` (deposit flow)

There is no lock-up period on validator deposits. A whale can deposit, validate, and withdraw in adjacent blocks. The `lockValidatorCapacity` / `commitStake` flow locks tokens during the validation window, but there is no minimum holding period *before* participating.

**Mitigations:**

- **Minimum deposit age:** Track `depositTimestamp` in the vault; require tokens to have been deposited for N days before counting toward validator capacity.
- **Warmup period:** Deposited tokens don't become available for validation until a warmup passes (similar to proof-of-stake warmup mechanics).

---

### 5. Contributor Rewards Not Influenced by Quality

**Severity:** Low (Design Choice)
**Location:** `FinalizationLib.sol:168`

Contributor rewards are flat per accepted contribution — every accepted slot in the same project pays identically regardless of quality score:

```solidity
uint256 contributorShare = (contrib.rewardRate * (C.BPS - proj.validatorRewardBps)) / C.BPS;
```

Quality only affects *reputation*, not *payout*. A barely-passing contribution (7000 weighted avg) earns the same tokens as an excellent one (9500). The quality bonus (`weightedAverage × 20 / BPS`) only modifies the reputation score.

This means the economic incentive for a contributor is binary: clear the threshold or don't. There is no marginal incentive to exceed it.

**Mitigations:**

- **Quality multiplier on rewards:** Scale contributor share by quality — e.g., `contributorShare × qualityMultiplier / BPS` where the multiplier ranges from 80% at threshold to 120% at max score. This creates direct economic incentive to maximize quality rather than just clear the bar.
- **Tiered reward bands:** Define discrete quality tiers (Good/Excellent/Outstanding) with increasing reward multipliers.

---

## Prioritized Recommendations

| Priority | Finding | Effort | Impact | Status |
|----------|---------|--------|--------|--------|
| 1 | Minimum validator floor (≥5) | Low | High — stabilizes σ and makes collusion harder | Open |
| 2 | Reduce `MIN_REPUTATION_FLOOR` | Low | High — single constant change with large anti-whale/sybil impact | **Resolved** — reduced to 100 |
| 3 | Minimum deposit age (anti-flash-staking) | Medium | Medium — vault change, prevents hit-and-run validation | **Resolved** — `minDepositAge` added to vault (default 0, max 7 days) |
| 4 | Validator assignment randomization | High | High — strongest structural defense against collusion | **Resolved** — `claimToValidate(projectId, quantity)` with Fisher-Yates shuffle |
| 5 | Quality-scaled contributor rewards | Medium | Medium — economic design enhancement | Open |

---

## Test Coverage

These findings were validated by the following test suites in `test/lifecycle/`:

| Test File | Category | Tests |
|-----------|----------|-------|
| `QualitySeparation.t.sol` | Quality divergence, redemption arcs, quality bonus differentiation | 3 |
| `ValidatorAlignment.t.sol` | Outlier detection, Sybil resistance, split opinion, honest vs dishonest earnings | 4 |
| `EconomicInvariants.t.sol` | Solvency at every step, funds conservation, escrow drain bounds | 3 |
| `ReputationDynamics.t.sol` | Reputation divergence, reputation gating, inactivity decay | 3 |
| `ThresholdEdgeCases.t.sol` | Exact/boundary thresholds, stake weight shifting, unanimous max score | 6 |

Key results from test runs:

- **Quality separation:** 581-point reputation gap between good (5181) and bad (4600) contributors over 8 rounds; 53,637 vs 0 SAPIEN rewards
- **Sybil resistance confirmed:** 1 honest validator (500e18 stake) overrides 2 sybils (1e18 each); weighted avg 7884, sybils detected as outliers with 50%+ slashing
- **Outlier detection:** Validator scoring 2000 among four scoring 8500 is detected at ~2σ, slashed 25% (12,500 shares)
- **Reputation gating works:** After 3 outlier rounds, validator rep drops to 4842; blocked by gate at 4843 while fresh validators (5000) pass
- **Economic conservation exact:** 50,000 funded = 5,000 treasury + 18,000 claimed + 27,000 engine balance
- **Decay formula verified:** 21-day gap decays score from 5010 by 105 points; matches `score × decayBps × days / BPS` exactly
