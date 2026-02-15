# Reputation System

The Sapien protocol uses a **Proof of Quality (PoQ)** reputation system implemented in `SapienTrust.sol`. Reputation is a per-user, per-role score that measures historical performance and directly influences consensus weight, reward distribution, and protocol access.

---

## Overview

| Property | Value |
|---|---|
| Score range | 0 – 10,000 (basis points) |
| Default score | 5,000 (50%) |
| Maximum score | 10,000 (100%) |
| Minimum score | 500 (5%) |
| Storage pattern | ERC-7201 namespaced (`sapien.storage.SapienTrust`) |
| Contract | `SapienTrust.sol` (upgradeable, `AccessControlUpgradeable`) |

Reputation is tracked **per address per role**. A single user has independent reputation scores for their activity as an Originator, Contributor, and Validator.

---

## Data Model

```solidity
struct UserReputation {
    uint256 score;              // 0-10000 (starts at 5000)
    uint256 totalActions;       // Total validations/contributions/projects
    uint256 successfulActions;  // Accurate validations/accepted contributions
    uint256 lastUpdated;        // Timestamp of last update
}
```

Stored in a double mapping:

```solidity
mapping(address => mapping(bytes32 => UserReputation)) userReputations;
```

The `bytes32` key is the role identifier:

| Role | Key |
|---|---|
| Originator | `keccak256("ORIGINATOR_ROLE")` |
| Contributor | `keccak256("CONTRIBUTOR_ROLE")` |
| Validator | `keccak256("VALIDATOR_ROLE")` |

---

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `DEFAULT_REPUTATION` | 5,000 | Starting score for new participants (50%) |
| `MAX_REPUTATION` | 10,000 | Ceiling — cannot exceed (100%) |
| `MIN_REPUTATION` | 500 | Floor — cannot drop below (5%) |
| `SUCCESS_INCREASE` | 10 | Base gain per successful action (+0.1%) |
| `REJECTION_DECREASE` | 50 | Penalty for a rejected action (-0.5%) |
| `SLASH_DECREASE` | 100 | Penalty for a slashing event (-1%) |
| `MAX_DAILY_GAIN` | 100 | Maximum cumulative daily reputation gain (1%) |
| `MIN_REPUTATION_FLOOR` | 1,000 | Weight-calculation floor in `ConsensusLib` (10%) |

---

## How Reputation Changes

### Successful Actions (+)

When `updateReputation(user, role, true, qualityScore)` is called:

1. **Base increase**: `SUCCESS_INCREASE` (10 bps = +0.1%).
2. **Quality bonus**: If `qualityScore > 5000`, an additional bonus of up to 10 bps is applied:
   ```
   bonus = ((qualityScore - 5000) * 10) / 5000
   ```
   This means a perfect quality score of 10,000 yields a total increase of ~20 bps (+0.2%).
3. **Daily cap**: The total gain for a user in a single UTC day is capped at `MAX_DAILY_GAIN` (100 bps = 1%). Any excess is discarded.
4. **Ceiling**: The score is capped at `MAX_REPUTATION` (10,000).

### Failed Actions (-)

When `updateReputation(user, role, false, qualityScore)` is called:

- **Slash** (`qualityScore == 0`): Penalty of `SLASH_DECREASE` (100 bps = -1%). Applied when a validator is an outlier, misses a commit deadline, or misses a reveal deadline.
- **Rejection** (`qualityScore != 0`): Penalty of `REJECTION_DECREASE` (50 bps = -0.5%). Applied when a contribution is rejected by consensus.

In both cases the score is floored at `MIN_REPUTATION` (500).

### Asymmetry by Design

Reputation is **hard to earn and easy to lose**:

- A single successful action gains at most +0.2%.
- A single slash costs -1% (5x the max gain).
- A rejection costs -0.5% (2.5x the max gain).
- Daily gains are capped at 1%, but there is **no daily cap on losses**.

---

## Lazy Decay

Reputation decays over time when a participant is inactive. Decay is applied **lazily** — it is calculated on-the-fly whenever reputation is read (`getTrustScore`) or written (`updateReputation`), not via a background process.

### Decay Formula

```
totalDecay = (currentScore * decayRate * timePassed) / (10000 * 1 day)
```

- `decayRate` is configurable in basis points per day (e.g., 10 = 0.1%/day).
- Decay is linear (not compounding).
- If the total decay would reduce the score to or below `MIN_REPUTATION`, the score is set to `MIN_REPUTATION`.
- No decay is applied if less than 1 full day has passed since the last update.

### Overflow Protection

If `timePassed * decayRate >= 10000 * 1 day`, the score is immediately set to `MIN_REPUTATION` instead of attempting the calculation (prevents overflow and handles extended inactivity).

### Admin Configuration

```solidity
function setReputationDecay(uint256 _decayRate) external onlyRole(DEFAULT_ADMIN_ROLE);
```

- Max decay rate: 10,000 bps (100% per day).
- Setting to 0 disables decay entirely.
- Emits `ReputationDecayUpdated(uint256 decayRate)`.

---

## When Reputation is Updated

### Originators

| Trigger | Success | Quality Score | Location |
|---|---|---|---|
| Project created | `true` | `0` | `SapienCore.createProject()` |

Originators receive a small reputation bump each time they create and fund a project.

### Contributors

| Trigger | Success | Quality Score | Location |
|---|---|---|---|
| Contribution accepted | `true` | Weighted average of validator scores | `SapienCore._finalizeContribution()` |
| Contribution rejected | `false` | Weighted average of validator scores | `SapienCore._finalizeContribution()` |

The `qualityScore` is the consensus-weighted average of all validator scores for that contribution, allowing high-quality contributions to earn a quality bonus.

### Validators

| Trigger | Success | Quality Score | Location |
|---|---|---|---|
| Accurate validation (not an outlier) | `true` | `0` | `SapienCore._distributeValidatorRewards()` |
| Outlier validation (slashed) | `false` | `0` | `SapienCore._processSlashing()` |
| Expired claim (failed to commit) | `false` | `0` | `ValidationOracle.cancelExpiredValidationClaim()` |
| Expired commitment (committed but failed to reveal) | `false` | `0` | `ValidationOracle._cancelExpiredCommitment()` |

Validators are penalized with `qualityScore == 0` (slash-level penalty) for all failure modes.

---

## Reputation and Consensus Weight

Reputation directly influences how much a validator's score matters in consensus and how rewards are distributed.

### Weight Formula

Defined in `ConsensusLib.calculateBaseWeight()`:

```
effectiveRep = max(reputation, MIN_REPUTATION_FLOOR)
weight = (stakeAmount * effectiveRep) / 10000
```

- `MIN_REPUTATION_FLOOR` (1,000 = 10%) prevents zero-weight validators — even a heavily penalized validator retains some influence.
- The formula normalizes reputation to a 0–1 multiplier applied to stake.

### Examples

| Stake | Reputation | Effective Rep | Weight |
|---|---|---|---|
| 100 tokens | 10,000 (max) | 10,000 | 100 |
| 100 tokens | 5,000 (default) | 5,000 | 50 |
| 100 tokens | 500 (min) | 1,000 (floor) | 10 |
| 200 tokens | 7,500 | 7,500 | 150 |

### Usage in Consensus

- Consensus algorithms (e.g., `SqrtStakeConsensus`) use `calculateBaseWeight` as the base for computing validator weights.
- These weights determine how much each validator's score influences the final weighted average.

### Usage in Reward Distribution

- `SapienCore._distributeValidatorRewards()` distributes rewards proportionally to validator weight.
- When consensus weights are available (from the `ConsensusReport`), those are used directly for reward distribution to ensure weight parity between consensus influence and rewards (M-1 fix).
- Falls back to `calculateBaseWeight(stake, reputation)` when consensus weights are unavailable.

Reward formula:

```
reward = (totalRewards * validatorBasisPoints * weight) / (10000 * totalQuantity * totalAccurateWeight)
```

---

## Reputation-Gated Access

### Project-Level Minimum Validator Reputation

Originators (or admins) can set a minimum reputation requirement for validators on a per-project basis:

```solidity
function setProjectMinValidatorReputation(bytes32 projectId, uint256 minReputation) external;
```

- Range: 0–10,000 (0 = no requirement, which is the default).
- Checked in `ValidationOracle.claimToValidate()` when a validator attempts to claim a validation slot.
- If the validator's reputation is below the threshold, the transaction reverts with `InsufficientValidatorReputation`.

This creates an **eligibility tier** system where high-value projects can restrict validation to experienced, reputable validators.

---

## Access Control

Only authorized protocol contracts can modify reputation:

| Function | Required Role | Granted To |
|---|---|---|
| `updateReputation()` | `UPDATER_ROLE` | `SapienCore`, `ValidationOracle` |
| `setReputationDecay()` | `DEFAULT_ADMIN_ROLE` | Protocol admin |

The `UPDATER_ROLE` is granted via a one-time `setupProtocolRoles(core, oracle)` call during deployment. This function can only be called once (`protocolRolesConfigured` flag).

---

## Events

| Event | Emitted When |
|---|---|
| `ReputationUpdated(address user, bytes32 role, uint256 oldScore, uint256 newScore)` | Any reputation change |
| `ReputationDecayUpdated(uint256 decayRate)` | Admin changes the decay rate |

---

## Errors

| Error | Trigger |
|---|---|
| `DecayRateOutOfRange(uint256 provided, uint256 max)` | `setReputationDecay` called with rate > 10,000 |
| `InsufficientValidatorReputation(address validator, uint256 required, uint256 actual)` | Validator tries to claim a slot but reputation is below project minimum |
| `ReputationOutOfRange(uint256 provided, uint256 max)` | `setProjectMinValidatorReputation` called with value > 10,000 |

---

## Lifecycle Example

1. **Alice** stakes tokens in `SapienVault` and becomes eligible to participate.
2. She validates a contribution. Her default reputation is **5,000**.
3. Her validation aligns with consensus (not an outlier) — reputation increases to **5,010** (+0.1%).
4. She validates again accurately — reputation reaches **5,020**.
5. She submits an outlier validation and is slashed — reputation drops to **4,920** (-1%).
6. She goes inactive for 10 days with a decay rate of 10 bps/day. On her next action, lazy decay is applied:
   ```
   decay = (4920 * 10 * 10 days) / (10000 * 1 day) = ~49
   ```
   Her reputation after decay: **4,871**.
7. A high-value project requires min validator reputation of 6,000. Alice cannot claim validation slots for that project until she rebuilds her reputation.

---

## Key Design Decisions

1. **Per-role tracking**: A poor validator reputation does not affect a user's contributor reputation. Each role is evaluated independently.
2. **Asymmetric incentives**: Losing reputation is significantly faster than gaining it, discouraging low-quality participation.
3. **Daily gain cap**: Prevents reputation farming through high-volume low-effort actions.
4. **Lazy decay**: Avoids gas-expensive periodic updates while still penalizing inactivity.
5. **Reputation floor**: `MIN_REPUTATION` (500) ensures participants are never fully locked out. The `MIN_REPUTATION_FLOOR` (1,000) in weight calculation ensures even low-rep validators retain minimal influence.
6. **Stake-reputation product**: Weight is `stake * reputation`, meaning both economic commitment and historical quality contribute to influence. A whale with poor reputation has less influence than a moderate staker with excellent reputation.

---

## Related Contracts

| Contract | Role in Reputation |
|---|---|
| `SapienTrust.sol` | Core reputation storage, update logic, decay, and access control |
| `ISapienTrust.sol` | Interface definition |
| `ISharedTypes.sol` | `UserReputation` struct, role constants |
| `SapienCore.sol` | Triggers reputation updates for originators, contributors, and validators |
| `ValidationOracle.sol` | Triggers reputation penalties for expired claims/commitments; enforces project-level reputation gates |
| `ConsensusLib.sol` | `calculateBaseWeight()` — converts reputation into consensus/reward weight |
| `SapienVault.sol` | Stake management (separate from reputation but used alongside it in weight calculation) |
