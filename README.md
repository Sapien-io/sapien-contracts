# Sapien Protocol — Proof of Quality (PoQ)

Onchain quality oracle for AI systems. Human experts verify AI-generated data and agent behaviors through stake-weighted consensus, producing verifiable quality signals consumable by onchain and offchain systems.

## How it works

Originators post projects with reward pools. Contributors claim slots and submit work. Validators independently score each contribution using a commit-reveal scheme. Stake-weighted consensus determines acceptance or rejection, with outlier validators slashed and accurate ones rewarded. Reputation accrues per skill, so a validator's track record on `DATA_ANNOTATION` is independent of their `BOUNDING_BOX` performance.

```
Originator creates project (skill: DATA_ANNOTATION, 3 validators required)
    │
    ▼
Contributor claims slot → submits work (hash + CID)
    │
    ▼
Validators commit sealed scores → reveal scores + salt
    │
    ▼
computeConsensus() → stake-weighted average
    ├── Above threshold → Accepted (contributor rewarded, validators rewarded)
    └── Below threshold → Rejected (contributor slashed, slot recycled)
         Outlier validators slashed via tiered penalties (1.5σ–5σ → 10%–100%)
```

## Architecture

Two deployable contracts, seven libraries, all operating on shared ERC-7201 namespaced storage:

```
SapienCore (UUPS Proxy)
├── OriginationLib    — project creation, funding, completion
├── ContributionLib   — claim slots, submit work, expiry
├── ValidationLib     — commit-reveal, consensus orchestration
├── ConsensusLib      — stake-weighted average, outlier detection
├── FinalizationLib   — settlement, rewards, force-settle
├── DisputeLib        — bonded disputes, originator reports
├── ReputationLib     — skill-based reputation with lazy decay
└─→ SapienVault (UUPS Proxy, ERC-4626) — staking with typed locks
```

| Component | Lines | Description |
|-----------|-------|-------------|
| `SapienCore` | 711 | Unified entry-point, admin config, delegates to libraries |
| `SapienVault` | 323 | ERC-4626 vault with contributor/validator/in-flight lock buckets |
| `Types.sol` | 288 | Shared structs, enums, storage layout |
| `ConsensusLib` | 144 | Pure consensus math — weighted average, stddev, tiered slashing |
| `ValidationLib` | 397 | Commit-reveal flow, validation claims, consensus triggering |
| `FinalizationLib` | 289 | Post-consensus settlement and reward distribution |
| `ContributionLib` | 242 | Contribution claims, submissions, expiry |
| `DisputeLib` | 223 | Dispute lifecycle and originator accountability |
| `OriginationLib` | 181 | Project creation, funding, escrow management |
| `ReputationLib` | 99 | Score updates with lazy decay and daily gain caps |
| `Constants.sol` | 57 | Protocol-wide parameters and limits |

## Key mechanisms

### Skill-based reputation

Reputation is tracked per skill, not per role. Every project requires a registered skill (e.g., `keccak256("DATA_ANNOTATION")`). Contributors and validators build reputation against that skill through their work. A validator with high `DATA_ANNOTATION` reputation gets more consensus weight on `DATA_ANNOTATION` projects but starts at default (5,000) on `BOUNDING_BOX` projects.

- Score range: 500–10,000 (default: 5,000)
- Success: +10 points (capped at +100/day)
- Failure: -50 points
- Lazy decay: configurable rate (default 0.1%/day)

### Consensus

`ConsensusLib.calculate` computes a weighted average where each validator's weight is `sqrt(stake) * effectiveReputation`. Validators deviating beyond 1.5 standard deviations are classified as outliers with tiered slashing (10%/25%/50%/100% of stake). When honest validators have higher skill reputation, their scores carry proportionally more weight.

### Staking

`SapienVault` implements ERC-4626 with three lock categories per user:

- **Contributor lock** — held while contribution slots are active
- **Validator capacity** — pre-locked pool drawn down per commit
- **In-flight** — committed to active validations

Slashing burns shares, redistributing underlying assets to all remaining stakers.

### Disputes

During the challenge period after consensus, anyone can open a bonded dispute. Operators resolve disputes within 7 days, or they auto-escalate (upheld by default). Upheld disputes return the bond + reward the challenger 20% of saved/slashed amounts.

## Getting started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (forge, anvil)
- Solidity ^0.8.30

### Build

```bash
forge build
```

### Test

```bash
# Full test suite
forge test

# Specific test contract
forge test --match-contract SkillReputation -vv

# Coverage
make coverage
```

### Local deployment

```bash
# Start Anvil (raised code-size limit for large contract)
make anvil

# Deploy to local Anvil
make deploy-anvil
```

### Lint

```bash
make lint
```

## Test suite

| Category | Files | Coverage |
|----------|-------|----------|
| Core unit tests | `SapienCore.t.sol`, `SapienVault.t.sol`, `ConsensusLib.t.sol` | Core contract logic |
| Library fuzz tests | `test/libraries/*Fuzz.t.sol` | Fuzz testing per library |
| Lifecycle tests | `test/lifecycle/*.t.sol` | Multi-phase end-to-end scenarios |
| Skill reputation | `SkillReputation.t.sol` | Skill isolation, consensus weight, cross-skill independence |
| Validator alignment | `ValidatorAlignment.t.sol` | Outlier detection, Sybil resistance, incentive alignment |
| Economic invariants | `EconomicInvariants.t.sol` | Token conservation, fee accounting |
| Invariant tests | `test/invariant/` | Stateful invariant testing with handler contracts |
| Security findings | `test/findings/` | Regression tests for identified and fixed issues |

## Documentation

Detailed documentation lives in [`docs/`](docs/):

- [Architecture overview](docs/architecture/overview.md) — contract topology, participant roles, lifecycle phases
- [SapienCore reference](docs/components/sapien-core.md) — all functions, events, access control
- [SapienVault reference](docs/components/sapien-vault.md) — ERC-4626 vault, lock categories, slashing
- [ReputationLib](docs/components/reputation-lib.md) — skill-based reputation, decay, update triggers
- [Protocol lifecycle](docs/guides/protocol-lifecycle.md) — frontend integration guide with state machines
- Role guides: [Originators](docs/guides/originators.md) | [Contributors](docs/guides/contributors.md) | [Validators](docs/guides/validators.md)

## License

MIT
