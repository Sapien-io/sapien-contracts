# Sapien PoQ Protocol Documentation

Welcome to the official documentation for the **Sapien Proof-of-Quality (PoQ) Protocol**.

Sapien PoQ is an open protocol for verifiable, consensus-based quality signals in AI workflows. It adds a verifiable quality layer to AI datasets and agent behaviors through stake-weighted verification—agnostic to whether participants are humans, AI agents, or hybrid teams.

## 📖 Navigation

### 🏗️ [Architecture](./architecture/overview.md)
Understand the high-level design, participant roles, and the [PoQ verification lifecycle](./architecture/lifecycle.md).

### 🗳️ [Validator Consensus](./validator-consensus.md)
A guide to how validators reach consensus, with swimlane diagrams explaining the commit-reveal process and weighted scoring.

### 🧩 [Components](./components/)
Detailed documentation of the protocol's core smart contracts:
- [Sapien Core](./components/sapien-core.md): Project and contribution management.
- [Validation Oracle](./components/validation-oracle.md): Consensus and commit-reveal logic.
- [Sapien Trust](./components/sapien-trust.md): Reputation (PoQ) and identity.
- [Sapien Vault](./components/sapien-vault.md): Staking, locking, and slashing.
- [Rewards](./components/rewards.md): Incentive distribution.

### ⚖️ [Consensus](./consensus/algorithms.md)
Explore the different consensus algorithms available:
- [Algorithms Comparison](./consensus/algorithms.md): Linear, Capped, Sqrt, and Hybrid.
- [Security Analysis](./consensus/security.md): Resistance to whale attacks and Sybil resistance.

### 🚀 [Guides](./guides/)
Step-by-step instructions for different protocol participants:
- [Originators](./guides/originators.md): Creating and funding projects.
- [Contributors](./guides/contributors.md): Submitting work and earning rewards.
- [Validators](./guides/validators.md): Verifying work and reaching consensus.
- [Developers](./guides/developers.md): Building oracles and integrating with PoQ.

### 🛡️ [Security](./security/overview.md)
Protocol security principles, slashing mechanisms, and auditability.

---

## 🎯 Key Value Propositions

- **Verifiable Quality**: Cryptographic proof of judgment (human or AI) for AI systems.
- **Data Sovereignty**: Your data stays in your storage; only quality signals are onchain.
- **Incentive Alignment**: Stake-weighted rewards and penalties ensure honest participation.
- **Composable**: Easily integrate with existing AI tools (CVAT, LangChain, etc.) via oracles.

---

*For more information, visit [poq.sapien.io](https://poq.sapien.io).*
