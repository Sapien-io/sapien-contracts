# Security Overview

The Sapien PoQ protocol is built on the principle of **Economic Security**. We use a combination of financial incentives (staking), penalties (slashing), and cryptographic proofs (commit-reveal, attestations) to ensure the integrity of AI verification, whether powered by humans or agents.

## 🛡️ Core Security Pillars

### 1. Staking (Skin in the Game)
All active participants must lock SAPIEN tokens in the `SapienVault`. This creates a tangible cost for malicious behavior and ensures that participants are economically aligned with the protocol's success.

### 2. Proof of Quality (Reputation)
Reputation is not just a badge; it is a functional component of the protocol. Your historical accuracy (PoQ score) and contribution quality affect your standing, while a history of outlier behavior as a validator reduces your reputation.

### 3. Commit-Reveal
The `ValidationOracle` enforces a commit-reveal process for all judgments. This prevents:
- **Herding**: Validators waiting to see others' scores before submitting their own.
- **Copy-Pasting**: Lazy validators mirroring the work of others without actually reviewing the task.

### 4. Slashing Mechanisms
Slashing is used to penalize specific types of bad behavior:
- **Claim Expiration (Contributors)**: If a contributor claims slots but fails to submit work before the deadline, they are slashed for the unfulfilled portion. Rejected contributions are **not** slashed — the index is re-queued for another contributor.
- **Outlier Judging (Validators)**: If a validator's score is a statistical outlier, they are slashed proportionally based on deviation severity (10% to 100%).
- **Non-Performance (Validators)**: Failure to commit after claiming a validation slot or failure to reveal after committing leads to stake forfeiture.

## 🐳 Whale and Sybil Resistance

### Whale Protection
Large token holders are prevented from dominating consensus through:
- **Quadratic Weighting**: `sqrt(stake)` reduces the power of large amounts (22% reduction in whale power vs linear weighting).
- **Weight Capping (Available)**: `ConsensusLib` provides an `applyCap` function that can limit any single validator's weight as a percentage of the total. Custom consensus algorithms can use this for additional protection.

### Sybil Resistance
Attacking the protocol with multiple small accounts is mitigated by:
- **Minimum Entry Stake**: A significant financial barrier to creating new accounts.
- **Reputation Maturity**: High-weight roles require a history of successful actions that cannot be easily faked or automated.

## 🔧 Applied Security Fixes

Documented fixes for identified vulnerabilities:

- **[Validator Rewards on Rejection](fixes/validator-rewards-on-rejection.md)**: Validators are paid only when a contribution is accepted. On rejection, no validator rewards are distributed, preserving the reward pool for re-submissions on the same index.

## 🔍 Auditability

Every final quality signal produced by the protocol is recorded as an onchain attestation. These attestations include:
- The consensus score.
- The number of validators involved.
- The algorithm used.
- References to the underlying work.

This creates an immutable audit trail for AI training data provenance and agent behavior compliance.
