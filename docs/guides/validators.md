# Guide for Validators

Validators provide the human intelligence layer of the Sapien protocol. By reaching consensus on the quality of contributions, validators secure the AI systems that rely on Sapien's Proof of Quality (PoQ). All validator operations are called on `SapienCore`.

## 1. Prerequisites

- **Stake SAPIEN**: Deposit SAPIEN tokens into the `SapienVault` via its ERC-4626 `deposit` function. Your stake weight directly influences your consensus impact through the `sqrt(stake) * reputation` weighting formula.
- **Reputation**: Your reputation is tracked per skill (e.g., `DATA_ANNOTATION`, `BOUNDING_BOX`). New skills start at 5,000 (range 500-10,000). Your skill-specific reputation affects your consensus weight via `sqrt(stake) * reputation`. Honest participation increases your skill reputation; outlier behavior decreases it.

## 2. Lock Validator Capacity

Before committing validations, you must lock a portion of your available stake as validator capacity. This creates a dedicated pool from which individual validation stakes are drawn.

```solidity
core.lockValidatorCapacity(amount);
```

- Moves `amount` from your available balance to your validator capacity bucket.
- You can adjust capacity at any time by locking more or unlocking idle capacity.
- Only idle capacity (not committed to in-flight validations) can be unlocked.

```solidity
core.unlockValidatorCapacity(amount);
```

Check your capacity with `SapienVault.getStakeAccount(address)`, which returns a `StakeAccount` containing `contributorLock`, `validatorCapacity`, and `inFlight` balances.

## 3. Claim Contributions to Validate

Request a quantity of contributions to validate. The protocol randomly assigns indices from pending contributions — you do not select specific indices. This quantity-based random assignment is an anti-collusion measure that prevents cartels from coordinating co-assignment.

```solidity
uint256 claimId = core.claimToValidate(projectId, quantity);
```

- `quantity`: Number of contributions you want to validate. The protocol randomly assigns indices from pending contributions using a Fisher-Yates shuffle seeded with `prevrandao`, `projectId`, your address, and timestamp.
- Returns a `claimId` for the validation claim.
- **Deadline**: You must commit scores within 1 hour of claiming. If you fail to commit, anyone can call `cancelExpiredValidationClaim(claimId)` to release the slots.

## 4. Commit Scores

Review the contribution data and decide on a quality score (0-10,000). Then commit a sealed hash:

```solidity
core.commitValidation(projectId, index, commitHash, stakeAmount, adapter);
```

- `commitHash`: `keccak256(abi.encodePacked(uint16(score), salt))` — the score packed as a `uint16` concatenated with a `bytes32` salt.
- `stakeAmount`: Amount of validator capacity to stake on this validation. Higher stakes increase your consensus weight but also your slashing exposure.
- `adapter`: Address of a validation adapter to receive a fee, or `address(0)` for none.

**Generating the commit hash**:

```solidity
bytes32 commitHash = keccak256(abi.encodePacked(uint16(score), salt));
```

The `stakeAmount` is moved from your validator capacity to in-flight status. It is at risk of slashing if you are classified as an outlier.

### Batch Commit

Commit scores for multiple contributions in a single transaction:

```solidity
core.batchCommitValidations(projectId, indices, commitHashes, stakeAmounts, adapter);
```

All arrays must have the same length. The same `adapter` is used for all commits in the batch.

## 5. Reveal Scores

After the commit deadline passes (default 1 day from commit), the reveal window opens. You must reveal before the reveal deadline (default 1 day after commit deadline):

```solidity
core.revealValidation(projectId, index, score, salt);
```

- `score`: The quality score you originally committed (0-10,000).
- `salt`: The `bytes32` salt used when committing.

If the revealed `score` and `salt` do not match the stored commit hash, the transaction reverts with `InvalidReveal`.

### Batch Reveal

```solidity
core.batchRevealValidations(projectId, indices, scores, salts);
```

### Non-Reveal Penalty

If you commit but fail to reveal before the reveal deadline, your committed stake remains locked. Another participant can force-settle you after the force-settle delay (default 3 days after the challenge period), causing you to be treated as an outlier.

## 6. Settlement

After consensus is computed for a contribution, each validator must settle to receive their stake back and any earned rewards.

### Consensus Computation

Anyone can call `computeConsensus` once enough validators have revealed:

```solidity
core.computeConsensus(projectId, index);
```

This calculates the stake-weighted average, standard deviation, and classifies outliers using the tiered slashing model.

### Settle Your Position

After the challenge period (default 1 day) ends with no active dispute:

```solidity
core.settleValidator(projectId, index, nonce);
```

- `nonce`: The consensus nonce for this round (found in the `Contribution` struct's `consensusNonce` field or in the `ConsensusReached` event).

**If you are accurate** (within 1.5 standard deviations of the weighted average):
- Your committed stake is returned to your validator capacity.
- You receive a share of the validator reward pool proportional to your weight (`sqrt(stake) * reputation`).
- Your skill-specific reputation increases (+10, capped at 100/day gain, max 10,000).

**If you are an outlier** (beyond 1.5 standard deviations):
- A portion of your committed stake is slashed based on the tiered schedule (see below).
- You receive no reward for this validation.
- Your skill-specific reputation decreases (-50, min 500).

### Force Settle

If a validator fails to call `settleValidator` in a timely manner, anyone can force-settle them after the force-settle delay (default 3 days after the challenge period ends):

```solidity
core.forceSettleValidator(projectId, index, nonce, validatorAddress);
```

## 7. Tiered Slashing

Outlier severity is measured in standard deviations from the weighted average. Slashing is proportional to the validator's committed stake:

| Deviation | Slash % |
|-----------|---------|
| 1.5-2 sigma | 10% |
| 2-3 sigma | 25% |
| 3-5 sigma | 50% |
| 5+ sigma | 100% |

## 8. Disputes

During the challenge period after consensus, any participant (except the contributor) can dispute the outcome:

```solidity
core.openDispute(projectId, index, evidenceHash, evidenceCid);
```

The challenger posts a bond proportional to the contribution's reward rate. If the dispute is upheld, consensus is invalidated and a new validation round begins. If rejected, the bond is forfeited to the contributor.

Disputes that are not resolved by an operator within 7 days can be escalated by anyone, at which point they are automatically upheld.

## Tips for Validators

- **Be objective**: Base your score strictly on the Task Definition Spec (TDS) provided in the project's metadata.
- **Keep secrets**: Never share your salt or score before the reveal phase to prevent collusion.
- **Stake appropriately**: Higher stakes increase your reward share but also your slashing exposure. Calibrate based on your confidence.
- **Manage capacity**: Lock enough capacity to handle your validation workload. Unlock idle capacity if you need liquidity.
- **Use batch operations**: `batchCommitValidations` and `batchRevealValidations` save gas for high-volume validation.
- **Settle promptly**: Call `settleValidator` after the challenge period to reclaim your stake and receive rewards.
