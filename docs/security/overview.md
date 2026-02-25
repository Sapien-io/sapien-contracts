# Security Overview

The Sapien PoQ protocol is built on the principle of **Economic Security**. We use a combination of financial incentives (staking), penalties (slashing), and cryptographic proofs (commit-reveal) to ensure the integrity of human-powered AI verification.

## Architecture (v0.5)

Sapien PoQ v0.5 consolidates the protocol into two contracts and seven libraries:

| Component | Role |
|-----------|------|
| **SapienCore** | Unified protocol logic: projects, claims, contributions, validations, consensus, reputation, rewards, disputes |
| **SapienVault** | ERC-4626 vault with typed stake locks (contributor, validator capacity, in-flight) |
| **OriginationLib** | Project creation, funding, removal |
| **ContributionLib** | Claim-to-contribute, submission, expiry |
| **ValidationLib** | Commit-reveal validation, consensus computation |
| **ConsensusLib** | Pure math: sqrt(stake) x reputation weighting, outlier detection, tiered slashing |
| **FinalizationLib** | Validator settlement, contributor reward release, reward claiming |
| **DisputeLib** | Dispute lifecycle, originator reports, escalation |
| **ReputationLib** | Per-role reputation scoring with time-based decay |

**Trust boundary**: SapienCore holds `ENGINE_ROLE` on SapienVault. SapienCore is the only external caller of vault stake operations. All libraries operate via `DELEGATECALL` in SapienCore's storage context.

Both contracts use **ERC-7201 namespaced storage** and are deployed behind **ERC-1967 proxies** with **UUPS** upgrade authorization.

---

## Core Security Pillars

### 1. Staking (Skin in the Game)

All active participants must hold shares in `SapienVault` (ERC-4626). Stake is categorized into typed locks:

- **Contributor Lock** -- locked when claiming contribution slots, slashed on rejection or expiry.
- **Validator Capacity** -- pre-committed stake ceiling for validation work.
- **In-Flight Stake** -- moved from capacity when committing to a specific validation; subject to slashing if the validator is an outlier.

Transfer and withdrawal guards enforce that locked shares cannot be moved or redeemed.

### 2. Proof of Quality (Reputation)

Reputation is a functional component of the consensus engine. Each participant has per-role reputation (originator, contributor, validator) scored 0--10,000 basis points with time-based decay.

In `ConsensusLib`, validator weight is calculated as `sqrt(stake) * effectiveReputation`, where `effectiveReputation` is clamped to a minimum floor of 100. This makes historical accuracy a direct multiplier on voting power.

### 3. Commit-Reveal

`ValidationLib` enforces a commit-reveal process for all human quality judgments:

- **Commit phase**: Validators submit `keccak256(abi.encodePacked(score, salt))` along with their stake amount (tracked separately in `ValidatorCommit.stakedAmount`).
- **Reveal phase**: Validators reveal score and salt; the committed stake amount is used for consensus weighting and slashing calculations.

This prevents:
- **Herding**: Validators waiting to see others' scores before submitting.
- **Score copying**: Lazy validators mirroring without reviewing.
- **Stake manipulation**: The committed stake amount is stored at commit time and cannot be changed at reveal.

### 4. Tiered Slashing

Slashing penalizes specific types of bad behavior with proportional severity:

**Validator outlier slashing** (tiered by standard deviation from consensus):

| Deviation | Slash % of Staked Amount |
|-----------|--------------------------|
| > 1.5 sigma | 10% |
| > 2 sigma | 25% |
| > 3 sigma | 50% |
| > 5 sigma | 100% |

**Contributor slashing**:
- Work rejected by consensus: contributor lock slashed.
- Claim expiry (slots claimed but not submitted): contributor lock slashed.

**Non-performance slashing**:
- Ghost validators (commit but never reveal): slashed via permissionless `cancelExpiredCommitment`.
- Expired contribution claims: slashed via permissionless `expireClaim`.

### 5. Dispute System

The protocol includes a post-consensus challenge mechanism:

- **Consensus disputes**: Any participant can challenge a consensus outcome during the challenge period by posting a bond (percentage of `rewardRate`). If upheld, the bond is returned and the challenger receives a reward. If rejected, the bond is slashed.
- **Originator reports**: Any participant can report originator misconduct by posting a bond (percentage of `totalRewards`). If upheld, the originator's locked stake is slashed and the project is cancelled.
- **Auto-escalation**: If neither dispute type is resolved within the 7-day resolution deadline, any participant can escalate, which auto-upholds the dispute.

### 6. Nonce-Based Re-Validation

When a contribution is rejected, its `submissionNonce` is incremented, invalidating all stale validation data. The index is returned to the available pool for a new contributor to claim and submit fresh work. This prevents stale consensus data from carrying over across submission cycles.

---

## Whale and Sybil Resistance

### Whale Protection

Large token holders are prevented from dominating consensus through:
- **Quadratic Weighting**: `sqrt(stake)` reduces the marginal influence of large stake amounts. Doubling your stake only increases your weight by ~41%.

### Sybil Resistance

Attacking the protocol with multiple small accounts is mitigated by:
- **Random validator assignment**: Validators request a quantity via `claimToValidate(projectId, quantity)` and receive randomly assigned pending contributions, preventing index cherry-picking and coordination attacks.
- **Minimum Entry Stake**: Configurable per-project `minStakeToClaim` and `minValidationStake` barriers.
- **Reputation Maturity**: High validator weight requires a history of successful actions (reputation earned over time with daily gain caps).
- **Reputation Decay**: Inactive participants lose reputation over time, preventing one-time reputation farming.

---

## Transfer and Withdrawal Guards

SapienVault enforces that locked stake cannot exit the system:

- **`maxRedeem` / `maxWithdraw`**: Overridden to exclude locked amounts from available redemption.
- **`_update` (transfer guard)**: Peer-to-peer share transfers are blocked if they would reduce the sender's balance below their total locked amount.
- **Paused state**: All deposits, withdrawals, and redemptions return 0 when the vault is paused.

---

## Storage Safety (ERC-7201)

Both contracts use ERC-7201 namespaced storage:

- **SapienCore**: Namespace `sapien.storage.SapienCore` -- all protocol state (projects, claims, contributions, validations, consensus, reputation, rewards, disputes) in a single `EngineStorage` struct.
- **SapienVault**: Namespace `sapien.storage.StakeVault` -- stake account mappings in `SapienVaultStorage`.

This eliminates storage collision risks between protocol state and OpenZeppelin base contract storage. New fields are safely added by appending to the namespace struct.

---

## Auditability

Every consensus outcome is recorded onchain with:
- The weighted average score and standard deviation.
- Per-validator outlier classification and slash amounts.
- Contribution acceptance/rejection status.
- Dispute outcomes and originator report resolutions.

Events are emitted at every state transition for offchain indexing and audit trail construction.
