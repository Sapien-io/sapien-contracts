# ValidationLib & ConsensusLib (formerly ValidationOracle)

> **v0.5 change**: The standalone `ValidationOracle` contract has been replaced by two libraries — `ValidationLib` (commit-reveal workflow and consensus orchestration) and `ConsensusLib` (the consensus algorithm itself). Both operate on `SapienCore`'s ERC-7201 namespaced storage via `DELEGATECALL`.

## ValidationLib

Manages the full validation lifecycle: validator capacity, validation claims, commit-reveal scoring, and consensus computation.

### Validator Capacity

Before participating, validators pre-lock tokens as "capacity" in the vault:

#### `lockValidatorCapacity(uint256 amount)`
Moves tokens from available balance to the `validatorCapacity` bucket via `SapienVault`.

#### `unlockValidatorCapacity(uint256 amount)`
Returns capacity tokens to available balance.

This capacity model eliminates per-commit lock/unlock transactions, significantly reducing gas costs for active validators.

### Validation Claims

#### `claimToValidate(bytes32 projectId, uint256[] indices) → claimId`

Validators claim the right to validate specific contribution indices. Guards:

- Contribution must be in `Pending` status
- Validator cannot validate their own contribution
- Validator must meet project's `minValidatorReputation` (checked against `requiredSkill` if set)
- Cannot claim the same index twice
- Cannot exceed the project's `numberOfValidations` per index
- Deadline: **1 hour** (`VALIDATION_CLAIM_DEADLINE`)

Creates a `ValidationClaim` struct tracking the validator, indices, deadline, and commitment progress.

#### `cancelExpiredValidationClaim(uint256 claimId)`

Permissionless. Cancels the claim after the 1-hour deadline if the validator failed to commit all indices. Applies a reputation penalty for uncommitted slots.

### Commit-Reveal

#### Commit Phase

**`commitValidation(projectId, index, commitHash, stakeAmount, adapter)`**

- `commitHash` = `keccak256(abi.encodePacked(uint16(score), salt))`
- `stakeAmount` must meet both the project's `minValidationStake` and the global `minValidationStake`
- Stake is moved from `validatorCapacity` → `inFlight` in the vault
- Optional `adapter` address for fee attribution

**`batchCommitValidations(projectId, indices[], commitHashes[], stakeAmounts[], adapter)`** — batch version.

#### Reveal Phase

**`revealValidation(projectId, index, score, salt)`**

- Score range: 0–10,000
- Must reveal within the **reveal window** (commit timestamp + commit deadline + reveal deadline)
- Hash verification: `keccak256(uint16(score) || salt)` must match the stored commit

**`batchRevealValidations(projectId, indices[], scores[], salts[])** — batch version.

### Consensus Computation

#### `computeConsensus(bytes32 projectId, uint256 index)`

Triggered after all required reveals are recorded. Orchestrates:

1. Builds `ValidationInput[]` from revealed validators (scores, stakes, reputation)
2. Calls `ConsensusLib.calculate()` for the consensus result
3. Stores `ConsensusReport` and per-validator `ValidatorConsensusResult`
4. Updates contribution status:
   - **Score ≥ consensusThreshold** → `Accepted`, contributor stake unlocked, reputation boosted with quality bonus
   - **Score < consensusThreshold** → `Rejected`, contributor stake slashed, slot returned to pool, nonce incremented

---

## ConsensusLib

A pure library implementing stake-weighted consensus with outlier detection and tiered slashing.

### Weight Calculation

```
weight = sqrt(stake) × effectiveReputation
```

Where `effectiveReputation = max(reputation, MIN_REPUTATION_FLOOR=1000)`.

### Algorithm

1. **Pass 1 — Weighted Average**: Compute `Σ(score × weight) / Σ(weight)` using high-precision arithmetic
2. **Pass 2 — Standard Deviation**: Compute weighted variance and take the square root
3. **Pass 3 — Outlier Classification**: Flag validators whose deviation from the mean exceeds thresholds

### Outlier Detection & Tiered Slashing

| Tier | Deviation | Slash % |
|------|-----------|---------|
| Tier 1 | > 1.5σ | 10% of stake |
| Tier 2 | > 2.0σ | 25% of stake |
| Tier 3 | > 3.0σ | 50% of stake |
| Tier 4 | > 5.0σ | 100% of stake |

Validators within 1.5σ of the mean are classified as "accurate" and contribute to `totalAccurateWeight` (used for reward distribution).

### Output

```
ConsensusResult {
    weightedAverage      // Final consensus score
    stdDeviation         // Standard deviation (in PRECISION units)
    validators[]         // Ordered validator addresses
    isOutlier[]          // Per-validator outlier flag
    slashAmounts[]       // Per-validator slash amount
    weights[]            // Per-validator weight
    totalAccurateWeight  // Sum of weights for non-outlier validators
}
```

### Stored On-Chain

Per contribution index and nonce:

- `ConsensusReport` — weighted average, std deviation, total accurate weight, nonce, computed flag
- `ValidatorConsensusResult` — per-validator outlier flag, slash amount, weight

## Deadlines & Timing

| Parameter | Default | Max | Set Via |
|-----------|---------|-----|---------|
| Validation claim deadline | 1 hour | — | Constant (`VALIDATION_CLAIM_DEADLINE`) |
| Commit deadline | 1 day | 30 days | `setCommitDeadline(seconds)` |
| Reveal deadline | 1 day | 30 days | `setRevealDeadline(seconds)` |
| Challenge period | 1 day | 30 days | `setChallengePeriod(seconds)` |
| Force-settle delay | 3 days | 90 days | `setForceSettleDelay(seconds)` |
