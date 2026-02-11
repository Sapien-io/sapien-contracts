# Security Overview

The Sapien PoQ protocol is built on the principle of **Economic Security**. We use a combination of financial incentives (staking), penalties (slashing), and cryptographic proofs (commit-reveal, attestations) to ensure the integrity of AI verification, whether powered by humans or agents.

## 🛡️ Core Security Pillars

### 1. Staking (Skin in the Game)
All active participants must lock SAPIEN tokens in the `SapienVault`. This creates a tangible cost for malicious behavior and ensures that participants are economically aligned with the protocol's success.

### 2. Proof of Quality (Reputation)
Reputation is not just a badge; it is a functional component of the consensus engine. In algorithms like **Hybrid Consensus**, your historical accuracy (PoQ score) directly increases your voting power, while a history of outlier behavior reduces it.

### 3. Commit-Reveal
The `ValidationOracle` enforces a commit-reveal process for all judgments. This prevents:
- **Herding**: Validators waiting to see others' scores before submitting their own.
- **Copy-Pasting**: Lazy validators mirroring the work of others without actually reviewing the task.

### 4. Slashing Mechanisms
Slashing is used to penalize three specific types of bad behavior:
- **Poor Quality (Contributors)**: If work is rejected by consensus, the contributor loses stake proportional to the quality gap.
- **Outlier Judging (Validators)**: If a validator's score is a statistical outlier, they are slashed to discourage lazy or malicious voting.
- **Non-Performance**: Failure to fulfill a claim or reveal a commit leads to stake forfeiture.

## 🐳 Whale and Sybil Resistance

### Whale Protection
Large token holders are prevented from dominating consensus through:
- **Quadratic Weighting**: `sqrt(stake)` reduces the power of large amounts.
- **Hard Caps**: No single validator can account for more than 30% of a committee's total weight.

### Sybil Resistance
Attacking the protocol with multiple small accounts is mitigated by:
- **Minimum Entry Stake**: A significant financial barrier to creating new accounts.
- **Reputation Maturity**: High-weight roles require a history of successful actions that cannot be easily faked or automated.

## 🔍 Auditability

Every final quality signal produced by the protocol is recorded as an onchain attestation. These attestations include:
- The consensus score.
- The number of validators involved.
- The algorithm used.
- References to the underlying work.

This creates an immutable audit trail for AI training data provenance and agent behavior compliance.
