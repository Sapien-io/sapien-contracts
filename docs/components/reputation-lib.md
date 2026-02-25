# ReputationLib

`ReputationLib` implements the Proof of Quality (PoQ) reputation system. It is a library that operates on `SapienCore`'s ERC-7201 namespaced storage via `DELEGATECALL`, keeping all reputation logic internal to the core contract. It tracks the historical performance of all participants using scores with lazy decay and daily gain caps.

## Reputation Model

### Score Range

| Parameter | Value |
|-----------|-------|
| Default (new users) | 5,000 |
| Minimum | 500 |
| Maximum | 10,000 |

### Reputation Keys

Reputation is stored in `mapping(address => mapping(bytes32 => Reputation))`. The `bytes32` key determines what the reputation is tracked against.

**Skill-based reputation (contributors and validators):**

Every project requires a registered skill (e.g., `keccak256("DATA_ANNOTATION")`). All contributor and validator reputation accrues against the project's skill hash. This means a user's performance on `DATA_ANNOTATION` tasks is tracked independently from their performance on `BOUNDING_BOX` tasks. Contributors and validators share the same reputation bucket for a given skill — good work on a skill builds a single reputation score regardless of role.

Users who have never worked on a particular skill start at `DEFAULT_REPUTATION` (5,000) and can participate in any project whose `minValidatorReputation` threshold is at or below that level.

**Originator reputation:**

Originator reputation uses a fixed key `keccak256("ORIGINATOR")` and is not skill-specific. It reflects operational reliability across all projects.

### Skill Registry

Skills are managed by the protocol admin via `SapienCore`:

- `registerSkill(string name)` — Hashes the name via `keccak256` and registers it. Emits `SkillRegistered(bytes32 indexed skillId, string name)`.
- `deregisterSkill(string name)` — Removes the skill from the registry. Does not affect in-flight projects.
- `isSkillRegistered(bytes32 skillId)` — View function to check registration status.

Every project must specify a registered skill in its `requiredSkill` field. Projects cannot be created with an unregistered or zero skill.

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

| Event | Key | Success? | Bonus |
|-------|-----|----------|-------|
| Project created | `ORIGINATOR_ROLE_KEY` | Yes | 0 |
| Contribution accepted | `proj.requiredSkill` | Yes | Quality bonus based on consensus score |
| Contribution rejected | `proj.requiredSkill` | No | — |
| Claim expired (unsubmitted slots) | `proj.requiredSkill` | No | — |
| Validator settled (accurate) | `proj.requiredSkill` | Yes | 0 |
| Validator settled (outlier) | `proj.requiredSkill` | No | — |
| Validation claim expired (uncommitted) | `proj.requiredSkill` | No | — |
| Expired commitment cancelled | `proj.requiredSkill` | No | — |
| Dispute upheld (accepted contribution) | `proj.requiredSkill` | No | — |
| Dispute upheld (rejected contribution) | `proj.requiredSkill` | Yes | 0 |
| Originator report upheld | `ORIGINATOR_ROLE_KEY` | No | — |
| Project removed by operator | `ORIGINATOR_ROLE_KEY` | No | — |

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

### `getScore(address user, bytes32 key) → uint256`

Returns the user's current reputation score with lazy decay applied. The `key` is a skill hash for contributors/validators (e.g., `keccak256("DATA_ANNOTATION")`) or `ORIGINATOR_ROLE_KEY` for originators.

### `getScoreCached(address user, bytes32 key, uint256 cachedDecayBps) → uint256`

Same as `getScore` but accepts a pre-cached decay rate to avoid redundant storage reads in loops (gas optimization).

### Querying via SapienCore

`SapienCore.getReputation(address user, bytes32 key)` returns the full `Reputation` struct. Pass a skill hash to query skill-specific reputation, or `keccak256("ORIGINATOR")` for originator reputation.

## Sybil Resistance

The reputation system works in concert with staking to prevent reputation farming:

1. **Stake requirements**: Contributors must lock stake to claim slots; validators must lock capacity
2. **Asymmetric penalties**: Failures cost 5x more than successes gain (-50 vs +10)
3. **Daily gain cap**: Maximum +100 points/day prevents rapid reputation inflation
4. **Reputation floor**: Scores cannot drop below 500, but low reputation restricts access to projects with `minValidatorReputation` thresholds
