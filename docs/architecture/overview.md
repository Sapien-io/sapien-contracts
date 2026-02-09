# System Architecture Overview

Sapien PoQ is designed as a modular protocol that provides a "Quality Oracle" for AI systems. It allows human experts to verify AI-generated data or agent behaviors, producing a verifiable quality signal that can be consumed by onchain and offchain systems.

## 👥 Participant Roles

The protocol defines four primary roles:

### 1. Originators
Originators are the "buyers" of quality. They create projects, define quality criteria, and fund reward pools.
- **Goal**: Obtain high-quality verified data or agent behavior signals.
- **Requirement**: Must stake SAPIEN tokens to create projects.

### 2. Contributors
Contributors are the workers who perform tasks (e.g., labeling an image, generating an AI response).
- **Goal**: Earn rewards by providing high-quality work.
- **Requirement**: Must stake SAPIEN tokens to claim work slots.

### 3. Validators
Validators are the independent reviewers who assess the quality of contributions.
- **Goal**: Earn rewards by reaching consensus with other validators.
- **Requirement**: Must stake SAPIEN tokens to participate in committees.

### 4. Oracles (Adapters)
Oracles are the technical interface between the Sapien protocol and external tools.
- **Contributor Oracles**: Connect tools like CVAT or custom AI pipelines to submit work.
- **Validator Oracles**: Provide interfaces for human reviewers to submit scores.

## 🔄 Verification Lifecycle

The PoQ process follows five distinct phases. For a detailed technical flow, see the [Protocol Lifecycle Diagram](./lifecycle.md). For information on how onchain indices map to offchain data (e.g., S3 buckets), see the [Data Index Lifecycle](./index-lifecycle.md).

### Phase 1: Project Setup
The Originator creates a project in `SapienCore`, defining parameters like the required skill, minimum quality score, and reward distribution. They fund the project with reward tokens (e.g., USDC).

### Phase 2: Work Submission
Contributors claim slots and submit their work. The work itself stays in the Originator's storage (e.g., S3, IPFS); only a hash and reference are submitted to `SapienCore`.

### Phase 3: Validation (Commit-Reveal)
To prevent collusion and herding, validators use a two-step process in the `ValidationOracle`:
1. **Capacity Setup**: Validators lock a fixed amount of stake to establish "Validation Capacity," allowing them to handle multiple tasks efficiently.
2. **Commit**: Validators submit a hash of their score and a secret salt, increasing their "In-Flight Stake."
3. **Reveal**: After the commit period, validators reveal their actual score and salt. This releases their "In-Flight Stake" back into their capacity pool.

### Phase 4: Consensus Calculation
Once enough reveals are gathered (or the deadline passes), the `ValidationOracle` uses a pluggable consensus algorithm (e.g., Hybrid or Sqrt Stake) to calculate a weighted average score and identify outliers. `ConsensusLib` handles the statistical heavy lifting, including standard deviation and tiered slashing calculations.

### Phase 5: Finalization & Settlement
`SapienCore` finalizes the contribution:
- If accepted: Rewards are distributed via the `Rewards` contract to the contributor and honest validators.
- If rejected: The work is released back into the project pool for another contributor to attempt.
- Outlier validators are slashed via the `SapienVault`, and their reputation in `SapienTrust` is penalized.

## 🏗️ Technical Stack

The protocol is implemented as a suite of EVM smart contracts:
- **Core Logic**: `SapienCore`
- **Consensus Oracle**: `ValidationOracle`
- **Reputation & Identity**: `SapienTrust`
- **Staking & Slashing**: `SapienVault`
- **Incentives**: `Rewards`

All quality signals are recorded as verifiable attestations, making them auditable and composable with other protocols.
