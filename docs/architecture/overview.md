# System Architecture Overview

Sapien PoQ is a protocol that provides a "Quality Oracle" for AI systems. It allows human experts to verify AI-generated data or agent behaviors, producing a verifiable quality signal that can be consumed by onchain and offchain systems.

## Contract Topology

v0.5 consolidates the protocol into **two deployable contracts** with **seven libraries**:

```
SapienCore (UUPS Proxy — unified entry-point)
├── OriginationLib     — Project creation & funding
├── ContributionLib    — Claim & contribute
├── ValidationLib      — Commit-reveal & consensus orchestration
├── ConsensusLib       — Stake-weighted consensus algorithm
├── FinalizationLib    — Settlement, rewards, project completion
├── DisputeLib         — Disputes & originator reports
├── ReputationLib      — PoQ reputation with lazy decay
└─→ SapienVault (UUPS Proxy) — ERC-4626 staking with typed locks
```

All libraries operate on SapienCore's **ERC-7201 namespaced storage** via `DELEGATECALL`. The only external contract call is SapienCore → SapienVault for stake operations. Shared types are centralized in `Types.sol` and protocol constants in `Constants.sol`.

## Participant Roles

### 1. Originators
Originators are the "buyers" of quality. They create projects, define quality criteria, and fund reward pools.
- **Goal**: Obtain high-quality verified data or agent behavior signals.
- **Skin in the game**: Optional per-slot stake requirement (configurable via `originatorStakeRequirement`).

### 2. Contributors
Contributors are the workers who perform tasks (e.g., labeling an image, generating an AI response).
- **Goal**: Earn rewards by providing high-quality work.
- **Skin in the game**: Must lock stake when claiming contribution slots (`minStakeToClaim`).

### 3. Validators
Validators are the independent reviewers who assess the quality of contributions using a commit-reveal scheme.
- **Goal**: Earn rewards by reaching consensus with other validators.
- **Skin in the game**: Must pre-lock validator capacity and commit per-validation stakes.

### 4. Adapters
Adapters are the technical interface between the Sapien protocol and external tools.
- **Origination adapters**: Earn fees when projects are funded.
- **Contribution adapters**: Earn fees when contributor rewards are released.
- **Validation adapters**: Earn fees when validators are settled.

## Verification Lifecycle

The PoQ process follows six distinct phases. For detailed technical flows, see the [Protocol Lifecycle Diagram](./lifecycle.md). For information on how onchain indices map to offchain data, see the [Data Index Lifecycle](./index-lifecycle.md).

### Phase 1: Project Setup
The originator creates a project via `createProject`, defining parameters like reward token, consensus threshold, number of validations, and validator reward share. They fund it via `fundProject`, which transfers tokens into escrow (after protocol and optional adapter fees) and creates contribution slots.

### Phase 2: Contribution
Contributors claim slots via `claimToContribute` (locks contributor stake) and submit work via `contribute` or `batchContribute` with a submission hash and data CID. Unsubmitted slots can be expired via `expireClaim` after the claim deadline.

### Phase 3: Validation (Commit-Reveal)
1. **Capacity Setup**: Validators pre-lock tokens as capacity via `lockValidatorCapacity`.
2. **Claim**: Validators claim specific indices via `claimToValidate` (1-hour deadline).
3. **Commit**: Validators submit `keccak256(abi.encodePacked(uint16(score), salt))` with a stake amount. Stake moves from capacity to in-flight.
4. **Reveal**: Validators reveal `score` and `salt` within the reveal window.

### Phase 4: Consensus
Once all required reveals are recorded, `computeConsensus` triggers `ConsensusLib` to calculate a stake-weighted average, identify outliers via tiered thresholds (1.5σ/2σ/3σ/5σ → 10%/25%/50%/100% slash), and set the contribution to Accepted or Rejected. The challenge period begins.

### Phase 5: Disputes
During the challenge period, anyone can open a bonded dispute against a consensus outcome. Operators resolve disputes, or they auto-escalate after 7 days. Originator accountability via `reportOriginator` allows community members to flag bad-faith projects.

### Phase 6: Settlement & Rewards
- Validators settle via `settleValidator` — outliers slashed, accurate validators rewarded.
- Contributor rewards released via `releaseContributorReward` after the challenge period.
- Users withdraw via `claimReward`.
- Originators complete projects and claim remaining escrow after a 30-day grace period.

## Technical Stack

- **Solidity**: ^0.8.30
- **Proxy Pattern**: UUPS (OpenZeppelin `UUPSUpgradeable`)
- **Storage Pattern**: ERC-7201 namespaced storage
- **Access Control**: OpenZeppelin `AccessControlUpgradeable`
- **Safety**: `ReentrancyGuardUpgradeable`, `PausableUpgradeable`
- **Token Standard**: ERC-4626 vault for staking (with inflation attack mitigation)
