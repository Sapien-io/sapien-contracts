# Sapien Proof-of-Quality (PoQ) Protocol

[![Protocol Version](https://img.shields.io/badge/version-v0.3-blue)](./docs/COMPLETE_DOCUMENTATION.md)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

Sapien PoQ is an open protocol for verifiable, consensus-based quality signals in AI workflows. It adds a verifiable quality layer to AI datasets and agent behaviors through stake-weighted verification.

## Overview

The Sapien PoQ protocol provides a "Quality Oracle" for AI systems. It allows diverse participants to verify AI-generated data or agent behaviors, producing a verifiable quality signal that can be consumed by onchain and offchain systems.


[Yellowpaper](./docs/paper/paper.pdf)

### Key Value Propositions
- **Verifiable Quality**: Cryptographic proof of judgment for AI systems.
- **Data Sovereignty**: Your data stays in your storage; only quality signals are on-chain.
- **Incentive Alignment**: Stake-weighted rewards and penalties ensure honest participation.
- **Composable**: Easily integrate with existing AI tools (CVAT, LangChain, etc.) via oracles.

---

## Core Architecture

The protocol is implemented as a suite of modular EVM smart contracts:

- **[SapienCore.sol](./src/SapienCore.sol)**: The central coordinator managing project lifecycles, claims, and finalization.
- **[ValidationOracle.sol](./src/ValidationOracle.sol)**: A stateless consensus engine handling validator commits, reveals, and task management.
- **[SapienTrust.sol](./src/SapienTrust.sol)**: The reputation and identity layer tracking "Proof of Quality" (PoQ) scores.
- **[SapienVault.sol](./src/SapienVault.sol)**: An ERC-4626 upgradeable staking contract for financial "skin in the game."
- **[Rewards.sol](./src/Rewards.sol)**: Handles escrow, allocation, and distribution of reward tokens (e.g., USDC).

---

## Participant Roles

1.  **Originators**: The "buyers" of quality who create projects, define criteria, and fund reward pools.
2.  **Contributors**: The participants performing tasks (e.g., labeling images, generating responses, or chain-of-thought reasoning).
3.  **Validators**: Independent reviewers assessing contribution quality to reach consensus.
4.  **Oracles (Adapters)**: Technical interfaces connecting external tools to the protocol.

---

## Verification Lifecycle

1.  **Project Setup**: Originator creates and funds a project in `SapienCore`.
2.  **Work Submission**: Contributors claim slots and submit work hashes.
3.  **Validation**: Validators perform a two-step **Commit-Reveal** process in the `ValidationOracle`.
4.  **Consensus Calculation**: Pluggable algorithms calculate weighted average scores and identify outliers.
5.  **Finalization & Settlement**: `SapienCore` distributes rewards to contributors/validators and slashes outliers.

---

## Consensus Algorithms

Sapien PoQ supports multiple pluggable consensus algorithms:
- **Hybrid**: Considers both financial stake and reputation (PoQ score).
- **Sqrt Stake**: Uses quadratic weighting to balance power and resist whale dominance.
- **Capped Linear**: Traditional linear staking with a hard cap per validator.
- **Linear**: Simple stake-weighted consensus.

---

## Repository Structure

```text
.
├── src/                # Smart contract source code
│   ├── consensus/      # Pluggable consensus algorithms
│   ├── interface/      # Protocol interfaces
│   └── libraries/      # Shared logic (e.g., ConsensusLib)
├── docs/               # Detailed documentation and guides
│   ├── architecture/   # System design and lifecycles
│   ├── components/     # Component-specific details
│   └── guides/         # User and developer guides
├── test/               # Comprehensive test suite (Unit, Invariant, Fuzz)
└── script/             # Deployment and management scripts
```

---

## Development

This project uses [Foundry](https://book.getfoundry.sh/) for development and testing.

### Prerequisites
- [Foundry](https://getfoundry.sh/)
- Node.js (for optional frontend/tooling)

### Build
```bash
forge build
```

### Test
```bash
forge test
```

### Deploy (Base Sepolia)
```bash
forge script script/DeploySapienCore.s.sol --rpc-url base-sepolia --broadcast --verify
```

---

## Documentation

For complete documentation, including detailed component breakdowns and user guides, please refer to:
- [**Complete Documentation**](./docs/COMPLETE_DOCUMENTATION.md)
- [**Architecture Overview**](./docs/architecture/overview.md)
- [**Protocol Lifecycle**](./docs/architecture/lifecycle.md)

---

## Connect
- **Website**: [poq.sapien.io](https://poq.sapien.io)
- **X**: [@sapien](https://x.com/joinsapien)
