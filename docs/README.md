# Sapien PoQ Protocol Documentation

Welcome to the official documentation for the **Sapien Proof-of-Quality (PoQ) Protocol**.

Sapien PoQ is an open protocol for verifiable, consensus-based quality signals in AI workflows. It adds a verifiable quality layer to AI datasets and agent behaviors through stake-weighted human verification.

---

## Architecture

**v0.5** — Two contracts, seven libraries.

| Contract / Library | Purpose |
|---|---|
| [SapienCore](./components/sapien-core.md) | Unified entry-point: project origination, contribution, commit-reveal validation, consensus, disputes, reputation, and reward distribution. Deployed behind an ERC-1967 UUPS proxy with ERC-7201 namespaced storage. |
| [SapienVault](./components/sapien-vault.md) | ERC-4626 staking vault: deposits, withdrawals, contributor locks, validator capacity, in-flight tracking, and share-burn slashing. |
| OriginationLib | Project creation and funding, fee waterfall, originator stake. |
| ContributionLib | Claims, index allocation (range + stack hybrid), contribution submission, claim expiry. |
| ValidationLib | Commit-reveal state machine, validation claims, batch commits/reveals. |
| ConsensusLib | Stake-weighted consensus with sqrt(stake) x reputation weighting, outlier detection, tiered slashing (1.5-5 sigma). |
| FinalizationLib | Validator settlement, contributor reward release, reward claiming. |
| DisputeLib | Consensus disputes, originator reports, 7-day escalation, bond management. |
| ReputationLib | Asymmetric reputation (hard to earn, easy to lose), lazy decay, daily gain cap. |

---

## Navigation

### [Architecture Overview](./architecture/overview.md)
High-level design, participant roles, and contract topology.

### [Lifecycle](./architecture/lifecycle.md)
The full data point lifecycle from project creation through consensus and settlement. See also the [index lifecycle](./architecture/index-lifecycle.md) for index-level state transitions.

### [Validator Consensus](./validator-consensus.md)
How validators reach consensus via commit-reveal, with swimlane diagrams explaining weighted scoring.

### [Consensus Algorithms](./consensus/algorithms.md)
Consensus algorithm details: sqrt(stake) weighting, outlier tiers, and security properties.

### [Design Specification](./v0.5-contracs.md)
The v0.5 design spec: data model, lifecycle phases, reputation system, dispute mechanism, ERC-4337 integration, and migration path.

### [Off-Chain Systems](./offchain/v0.5-offchain.md)
Architecture for off-chain components: web app, API server, Ponder indexer, keeper service, data storage, account abstraction infrastructure, and notifications.

### [UX Lifecycle](./offchain/v0.5-ux.md)
Complete user experience lifecycle for each protocol role: originator, contributor, validator, and adapter.

---

## Guides

Step-by-step instructions for different protocol participants:

- [Originators](./guides/originators.md) — Creating and funding projects.
- [Contributors](./guides/contributors.md) — Submitting work and earning rewards.
- [Validators](./guides/validators.md) — Verifying work and reaching consensus.
- [Developers](./guides/developers.md) — Building integrations with PoQ.
- [Fees](./guides/fees.md) — Protocol fees, adapter fees, and the fee waterfall.
- [Wagmi/React](./guides/wagmi-react-implementation.md) — Frontend integration guide.

---

## Security

- [Security Overview](./security/overview.md) — Protocol security principles, slashing mechanisms, and auditability.
- [Audit Scope](./security/AUDIT_SCOPE.md) — Audit scope and findings.
- [Lifecycle Flow Issues](./security/lifecycle-flow-issues.md) — Confirmed lifecycle/liveness issues from exhaustive workflow testing.
- [Contracts & Interfaces](./contracts-and-interfaces.md) — Contract interface reference.

---

## Key Value Propositions

- **Verifiable Quality**: Cryptographic proof of human judgment for AI systems.
- **Data Sovereignty**: Your data stays in your storage; only quality signals are onchain.
- **Incentive Alignment**: Stake-weighted rewards and penalties ensure honest participation.
- **Composable**: Integrate with existing AI tools via adapters.

---

*For more information, visit [poq.sapien.io](https://poq.sapien.io).*
