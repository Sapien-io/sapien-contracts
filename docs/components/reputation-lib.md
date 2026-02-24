# ReputationLib

`ReputationLib` implements the Proof of Quality (PoQ) reputation system. It is a library that operates on `SapienCore`'s ERC-7201 namespaced storage via `DELEGATECALL`, keeping all reputation logic internal to the core contract. It tracks the historical performance of all participants — originators, contributors, and validators — using role-specific scores with lazy decay and daily gain caps.

## Reputation Model

### Score Range

| Parameter | Value |
|-----------|-------|
| Default (new users) | 5,000 |
| Minimum | 500 |
| Maximum | 10,000 |

### Role Keys

Reputation is tracked per-role using `bytes32` keys:

- `keccak256("ORIGINATOR")` — Originator reputation
- `keccak256("CONTRIBUTOR")` — Contributor reputation
- `keccak256("VALIDATOR")` — Validator reputation

Projects can also specify a `requiredSkill` hash, in which case validator reputation is tracked under that skill key instead of the generic validator role.

### Reputation Struct

```
Reputation {
    score            // Current reputation score
    totalActions     // Lifetime action count
    successfulActions // Lifetime successful actions
    lastUpdated      // Timestamp of last update (for decay)
    dailyGain        // Gain accumulated today
    dailyGainDate    // Date of current daily gain tracking
}
```

## Update Logic

### `update(address user, bytes32 role, bool success, uint256 bonus)`

Called internally by the protocol libraries at key lifecycle points:

**On success** (`success = true`):
- Base gain: `SUCCESS_INCREASE` = **+10 points**
- Optional bonus (e.g. quality bonus from consensus score)
- Subject to `MAX_DAILY_GAIN` = **100 points/day** cap
- Capped at `MAX_REPUTATION` = 10,000

**On failure** (`success = false`):
- Penalty: `REJECTION_DECREASE` = **-50 points**
- Floored at `MIN_REPUTATION` = 500

### When Reputation Updates

| Event | Role | Success? | Bonus |
|-------|------|----------|-------|
| Project created | Originator | Yes | 0 |
| Contribution accepted | Contributor | Yes | Quality bonus based on consensus score |
| Contribution rejected | Contributor | No | — |
| Claim expired (unsubmitted slots) | Contributor | No | — |
| Validator settled (accurate) | Validator | Yes | 0 |
| Validator settled (outlier) | Validator | No | — |
| Validation claim expired (uncommitted) | Validator | No | — |
| Expired commitment cancelled | Validator | No | — |
| Dispute upheld (accepted contribution) | Contributor | No | — |
| Dispute upheld (rejected contribution) | Contributor | Yes | 0 |
| Originator report upheld | Originator | No | — |
| Project removed by operator | Originator | No | — |

## Lazy Decay

Reputation decays passively over time to incentivize consistent participation.

### Mechanism

Decay is applied "lazily" whenever a score is read or updated — not on every block. The formula:

```
daysSinceUpdate = (now - lastUpdated) / 1 day
decayAmount = score * decayRateBps * daysSinceUpdate / 10000
newScore = max(score - decayAmount, MIN_REPUTATION)
```

### Configuration

- **Default decay rate**: 10 BPS (0.1% per day)
- **Maximum decay rate**: 500 BPS (5% per day)
- Configurable via `SapienCore.setDecayRate(bps)`

## Query Functions

### `getScore(address user, bytes32 role) → uint256`

Returns the user's current reputation score with lazy decay applied. Uses the stored `decayRateBps`.

### `getScoreCached(address user, bytes32 role, uint256 cachedDecayBps) → uint256`

Same as `getScore` but accepts a pre-cached decay rate to avoid redundant storage reads in loops (gas optimization).

## Sybil Resistance

The reputation system works in concert with staking to prevent reputation farming:

1. **Stake requirements**: Contributors must lock stake to claim slots; validators must lock capacity
2. **Asymmetric penalties**: Failures cost 5x more than successes gain (-50 vs +10)
3. **Daily gain cap**: Maximum +100 points/day prevents rapid reputation inflation
4. **Reputation floor**: Scores cannot drop below 500, but low reputation restricts access to projects with `minValidatorReputation` thresholds
