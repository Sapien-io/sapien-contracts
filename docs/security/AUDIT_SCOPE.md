# Sapien PoQ Protocol — Audit Scoping Document

**Date:** February 6, 2026
**Version:** v2 (contracts-v2)
**Solidity Version:** ^0.8.30
**License:** MIT
**Framework:** Foundry (forge, via-ir enabled, optimizer 200 runs)
**Target Chain:** Base (L2) — currently deployed on Base Sepolia testnet
**Repository:** `contracts-v2`

---

## 1. Project Overview

Sapien Proof-of-Quality (PoQ) Protocol is an open protocol for verifiable, consensus-based quality signals in AI workflows. It adds a verifiable quality layer to AI datasets and agent behaviors through stake-weighted human verification.

**Core concept:** Originators create projects (tasks needing human verification), Contributors submit work against those projects, and Validators stake tokens to commit-reveal quality scores. A pluggable consensus algorithm aggregates validator scores, determines contributor rewards, and slashes outlier validators.

### Protocol Participants

| Role | Description |
|------|-------------|
| **Originator** | Creates projects, defines parameters, funds reward pools |
| **Contributor** | Claims contribution slots, submits work (offchain data, onchain hash) |
| **Validator** | Stakes tokens, commits/reveals quality scores via commit-reveal scheme |
| **Admin** | Configures protocol parameters, registers consensus algorithms |

### Key Protocol Flows

1. **Project Creation** — Originator creates a project with reward tokens, quantity, and parameters
2. **Contribution Lifecycle** — Claim slot → Submit work (hash) → Await validation
3. **Validation (Commit-Reveal)** — Validators claim assignment → Commit hash(score, stake, salt) → Reveal score → Consensus computed
4. **Finalization** — Consensus determines accept/reject → Rewards distributed or refunded → Outlier validators slashed → Reputation updated

---

## 2. Contracts in Scope

### 2.1 Summary Table

| # | Contract | File | Lines | nSLOC | Complexity |
|---|----------|------|-------|-------|------------|
| 1 | `SapienCore` | `src/SapienCore.sol` | 1,018 | 583 | **High** |
| 2 | `ValidationOracle` | `src/ValidationOracle.sol` | 1,090 | 660 | **High** |
| 3 | `Rewards` | `src/Rewards.sol` | 517 | 243 | Medium |
| 4 | `SapienVault` | `src/SapienVault.sol` | 329 | 167 | Medium |
| 5 | `SapienTrust` | `src/SapienTrust.sol` | 323 | 137 | Low-Medium |
| 6 | `ConsensusLib` | `src/libraries/ConsensusLib.sol` | 279 | 148 | Medium |
| 7 | `HybridConsensus` | `src/consensus/HybridConsensus.sol` | 96 | 64 | Medium |
| 8 | `CappedLinearConsensus` | `src/consensus/CappedLinearConsensus.sol` | 141 | 71 | Medium |
| 9 | `LinearStakeConsensus` | `src/consensus/LinearStakeConsensus.sol` | 70 | 39 | Low |
| 10 | `SqrtStakeConsensus` | `src/consensus/SqrtStakeConsensus.sol` | 64 | 39 | Low |

**Interfaces (define structs, events, errors — auditor should review for completeness):**

| # | Interface | File | Lines | nSLOC |
|---|-----------|------|-------|-------|
| 11 | `ISharedTypes` | `src/interface/ISharedTypes.sol` | 221 | 148 |
| 12 | `IValidationOracle` | `src/interface/IValidationOracle.sol` | 394 | 149 |
| 13 | `ISapienCore` | `src/interface/ISapienCore.sol` | 226 | 106 |
| 14 | `IRewards` | `src/interface/IRewards.sol` | 210 | 65 |
| 15 | `IConsensusAlgorithm` | `src/interface/IConsensusAlgorithm.sol` | 69 | 27 |
| 16 | `ISapienVault` | `src/interface/ISapienVault.sol` | 67 | 25 |
| 17 | `ISapienTrust` | `src/interface/ISapienTrust.sol` | 130 | 23 |

### 2.2 Totals

| Metric | Count |
|--------|-------|
| Total `.sol` files | 17 |
| Total lines (all files) | 5,244 |
| **Implementation nSLOC** | **2,151** |
| Interface/type nSLOC | 543 |
| **Total nSLOC** | **2,694** |

---

## 3. Architecture

### 3.1 Contract Hierarchy

```
SapienCore (central coordinator)
    ├── ValidationOracle (consensus & commit-reveal)
    │       ├── SapienTrust (reputation & identity)
    │       │       └── SapienVault (ERC-4626 staking)
    │       └── SapienVault (stake locking/slashing)
    ├── SapienTrust (reputation updates)
    ├── SapienVault (stake operations)
    ├── Rewards (reward distribution)
    └── Consensus Algorithms (pluggable, registered on Oracle)
            ├── HybridConsensus (default)
            ├── CappedLinearConsensus
            ├── LinearStakeConsensus
            └── SqrtStakeConsensus
```

**Data flow:** `Core → Oracle → Trust → Vault`

### 3.2 Contract Descriptions

#### SapienCore (583 nSLOC) — HIGH COMPLEXITY

Central coordinator merging project registry and contribution management. Handles:
- Project creation (IPFS-linked, configurable parameters)
- Contribution slot claiming with index management (stack-based re-queuing)
- Contribution submission (offchain data, onchain submission hash)
- Contribution finalization (triggers reward distribution or refund)
- Protocol and operator fee collection (basis points)
- Reward redistribution from rejections to remaining pool
- Batch operations (batch claim, batch contribute)

**Security surface:** 9 functions with `nonReentrant`, role-based access control (ORIGINATOR, CONTRIBUTOR roles), cross-contract calls to Oracle/Trust/Vault/Rewards, index management state machine, fee calculations.

#### ValidationOracle (660 nSLOC) — HIGH COMPLEXITY

Stateless consensus oracle managing the full validation lifecycle:
- Commit-reveal validation scheme (keccak256 hash commitments)
- Validator assignment and capacity management
- Reveal deadline enforcement with expired commitment handling
- Consensus calculation via pluggable algorithm registry
- Outlier detection and slash amount computation
- Batch commit/reveal operations
- Per-project algorithm and parameter configuration

**Security surface:** 3 functions with `nonReentrant`, commit-reveal integrity, deadline/timing logic, cross-contract calls to Trust/Vault, validator stake locking, ghost validator prevention (expired commitment slashing).

#### Rewards (243 nSLOC) — MEDIUM COMPLEXITY

Upgradeable reward distribution contract:
- Contributor reward allocation and claiming
- Validator reward allocation and claiming
- Project reward pool management
- Operator fee handling (per-project configurable)
- Maximum fee cap enforcement
- Refund of unclaimed project rewards
- Pausable operations

**Security surface:** 4 functions with `nonReentrant`, ERC-20 token transfers (SafeERC20), allocated vs available balance tracking, fee calculations.

#### SapienVault (167 nSLOC) — MEDIUM COMPLEXITY

ERC-4626 compliant vault for staking with slashing:
- Token deposit → vault share issuance
- Stake locking (prevents withdrawal during active validations)
- Slashing (burns shares proportional to penalty)
- Transfer restrictions (locked stake cannot be transferred)
- Pausable operations

**Security surface:** 1 function with `nonReentrant`, ERC-4626 inflation attack mitigation (`_decimalsOffset`), share/asset conversion math, locked balance enforcement on transfers.

#### SapienTrust (137 nSLOC) — LOW-MEDIUM COMPLEXITY

Reputation and identity management:
- Per-role reputation scoring (0-10,000 basis points)
- Reputation decay over time (configurable rate)
- Skill validation tracking with cooldown periods
- Minimum stake requirements per role
- Implicit identity via vault staking

**Security surface:** No reentrancy guard (no external calls beyond reads), role-based updates, timestamp-based decay calculations.

#### Consensus Algorithms (213 nSLOC combined) — MEDIUM COMPLEXITY

Four pluggable consensus implementations sharing a common library:

| Algorithm | Weight Formula | Cap | Security Grade |
|-----------|---------------|-----|----------------|
| **HybridConsensus** | `min(sqrt(stake) × reputation, 30% cap)` | 30% | A- |
| **CappedLinearConsensus** | `min(stake × reputation, cap)` | Configurable | B+ |
| **LinearStakeConsensus** | `stake × reputation` | None | C+ |
| **SqrtStakeConsensus** | `sqrt(stake) × reputation` | None | B |

All algorithms use `ConsensusLib` for shared calculations:
- Weighted average computation
- Standard deviation calculation
- Outlier identification (>1.5 σ deviation → slash)
- Integer square root (Babylonian method)

**Security surface:** Pure math operations, precision loss risks in division, potential overflow in multiplication, outlier threshold calibration.

---

## 4. External Dependencies

| Library | Version | Usage |
|---------|---------|-------|
| **OpenZeppelin Contracts** | v5.x (latest) | `IERC20`, `SafeERC20`, `Math`, `IERC4626` |
| **OpenZeppelin Contracts Upgradeable** | v5.x (latest) | `Initializable`, `AccessControlUpgradeable`, `ReentrancyGuardUpgradeable`, `PausableUpgradeable`, `ERC4626Upgradeable`, `ERC20Upgradeable` |
| **Forge Std** | latest | Testing only |

No custom or non-standard libraries. No assembly blocks, no `delegatecall`, no `selfdestruct`, no inline assembly.

---

## 5. Upgradeability

All core contracts use the **Transparent Proxy Upgradeable** pattern:

| Contract | Upgradeable | Pattern | Storage Gaps |
|----------|------------|---------|--------------|
| SapienCore | Yes | `Initializable` + `AccessControlUpgradeable` | To verify |
| ValidationOracle | Yes | `Initializable` + `AccessControlUpgradeable` | To verify |
| Rewards | Yes | `Initializable` + `AccessControlUpgradeable` | To verify |
| SapienVault | Yes | `Initializable` + `ERC4626Upgradeable` | Yes (`uint256[49]`) |
| SapienTrust | Yes | `Initializable` + `AccessControlUpgradeable` | To verify |
| Consensus Algorithms | No | Stateless, non-upgradeable | N/A |

**Note:** Proxy contracts themselves are not in scope (using standard OpenZeppelin `TransparentUpgradeableProxy`). Auditor should verify storage layout compatibility and initialization protection.

---

## 6. Access Control & Roles

| Role | Granted To | Permissions |
|------|-----------|-------------|
| `DEFAULT_ADMIN_ROLE` | Deployer/Admin | Grant/revoke all roles, configure protocol parameters |
| `ORIGINATOR_ROLE` | Project creators | Create projects, fund reward pools |
| `CONTRIBUTOR_ROLE` | Workers | Claim contribution slots, submit work |
| `VALIDATOR_ROLE` | Validators | Claim validation assignments, commit/reveal scores |
| `SAPIEN_CORE_ROLE` | SapienCore contract | Call privileged functions on ValidationOracle |
| `UPDATER_ROLE` | SapienCore / ValidationOracle | Update reputation on SapienTrust |
| `LOCKER_ROLE` | ValidationOracle | Lock/unlock stake on SapienVault |
| `SLASHER_ROLE` | ValidationOracle / SapienCore | Slash stake on SapienVault |
| `PAUSER_ROLE` | Admin | Pause/unpause Rewards and Vault |

---

## 7. Key Security Considerations

### 7.1 Known Attack Surfaces

| Area | Risk | Description |
|------|------|-------------|
| Commit-Reveal Integrity | High | Validators commit `keccak256(score, stakeAmount, salt)` then reveal. Must ensure committed stake is used for slashing, not revealed stake ("1-Wei Shield Attack"). |
| Ghost Validator Evasion | High | Validators who commit but never reveal must be slashed via `cancelExpiredCommitment`. |
| Precision Loss | Medium | Consensus calculations, reward distributions, and fee calculations involve division. Must multiply before dividing. |
| CEI Pattern | Medium | Cross-contract calls to Oracle/Trust/Vault/Rewards must follow Checks-Effects-Interactions pattern. |
| ERC-4626 Inflation | Medium | First-depositor attack mitigated via `_decimalsOffset()`. |
| Index Management | Medium | Stack-based index re-queuing (claim → expire/reject → re-queue). Race conditions in rapid claim sequences. |
| Sybil Resistance | Medium | Role separation (Originator ≠ Contributor ≠ Validator), stake requirements, reputation-weighted consensus. |
| Fee Calculations | Low-Medium | Protocol fee (max 3%), operator fee (max 2%), validator reward (basis points). Rounding and precision. |
| Timestamp Dependence | Low | Claim deadlines, reveal deadlines, reputation decay all use `block.timestamp`. |

### 7.2 Tokens Handled

- **Staking Token:** Single ERC-20 token used for vault deposits (set at initialization)
- **Reward Tokens:** Per-project ERC-20 tokens (arbitrary, set by originator at project creation)
- **Vault Shares:** ERC-20 (ERC-4626 shares) issued by SapienVault

All ERC-20 interactions use OpenZeppelin's `SafeERC20`. Fee-on-transfer and rebasing tokens are **not** explicitly supported.

### 7.3 Mathematical Operations

- Weighted average consensus (multiplication before division)
- Standard deviation calculation (Babylonian sqrt)
- Reputation decay (basis points per day, timestamp-based)
- Reward pro-rata distribution
- Slashing (share burning proportional to penalty)

---

## 8. Testing Overview

| Metric | Count |
|--------|-------|
| Test files | 58 |
| Total test lines | ~16,900 |
| Test categories | Unit, integration, lifecycle, invariant, adversarial, findings-specific |

### Test Categories

- **Core unit tests:** `SapienCore.t.sol`, `Oracle.t.sol`, `Vault.t.sol`, `Trust.t.sol`, `Rewards.t.sol`, `Consensus.t.sol`
- **Lifecycle tests:** `Lifecycle.t.sol`, `lifecycle/EndToEnd.t.sol`, `lifecycle/Adversarial.t.sol`
- **Invariant tests:** `Invariants.t.sol`, `InvariantsV2.t.sol`, `lifecycle/Invariants.t.sol` (configured: 256 runs, depth 15)
- **Fuzz tests:** `FrontendFuzz.t.sol`, `ConfidenceBasedStaking.t.sol`
- **Security finding reproductions (30+ files):** Cover previously identified vulnerabilities including reentrancy, precision loss, zero-stake DoS, validator collusion, timestamp manipulation, index race conditions, fee-on-transfer tokens, vault vampirism, reputation overflow, and more

### Notable Finding-Specific Tests

| Test File | Vulnerability Covered |
|-----------|-----------------------|
| `ReentrancyCEIViolation.t.sol` | CEI pattern violations |
| `ValidationOracleReentrancy.t.sol` | Reentrancy in oracle |
| `PrecisionLoss.t.sol` | Division before multiplication |
| `ExpiredCommitment.t.sol` | Ghost validator evasion |
| `VaultVampirism.t.sol` | ERC-4626 inflation attack |
| `ValidatorCollusionAttack.t.sol` | Sybil/collusion scenarios |
| `MildOutlierEscapeSlashing.t.sol` | Outlier detection edge cases |
| `ZeroStakeValidatorDoS.t.sol` | Zero-value boundary attacks |
| `IndexReclamationRace.t.sol` | Index re-queuing race conditions |
| `TaskRewardDilution.t.sol` | Reward distribution manipulation |

---

## 9. Deployment Information

| Parameter | Value |
|-----------|-------|
| Target chain | Base (Ethereum L2) |
| Current deployment | Base Sepolia testnet (chain ID 84532) |
| Proxy pattern | Transparent Upgradeable Proxy |
| Solidity compiler | 0.8.30 |
| Optimizer | Enabled, 200 runs |
| via-ir | Enabled |
| Contract verification | Basescan API |

### Deployed Contracts (Base Sepolia — latest)

| Contract | Proxy Address |
|----------|---------------|
| SapienCore | `0xba050696Ad19E1961485B300D3b0Cb3D35eB640b` |
| ValidationOracle | `0x6c1Bb25b2eDcF7a970bD42F97d72676fAAF8a8D4` |
| SapienTrust | `0x21d2391D6bB9A9928EC15b24f1efC8b9DFCEf7A9` |
| SapienVault | `0x1A7673226d6CD1634e7c78E2D48B351d9E306423` |
| Rewards | `0xC8996Af3b3D8642dc231F06b6D5486CA3378ac88` |

---

## 10. Documentation Available

The repository includes extensive documentation in `docs/`:

- **Architecture Overview** — System design, participant roles, contract hierarchy
- **Component Docs** — Per-contract detailed documentation
- **Consensus Algorithms** — Mathematical specifications for all four algorithms
- **Participant Guides** — Step-by-step flows for originators, contributors, validators
- **Security Overview** — Known threat model and mitigations
- **White Paper** — Available at `notes/paper/whitepaper.pdf`
- **Security Notes** — Detailed write-ups for 16+ previously identified and fixed vulnerabilities in `notes/security/`

---

## 11. Scope Clarifications

### In Scope
- All 17 `.sol` files in `src/` (contracts, interfaces, library)
- Upgradeability (initialization, storage layout, proxy compatibility)
- Cross-contract interactions and trust boundaries
- Economic/game-theoretic attacks (Sybil, collusion, front-running)
- Mathematical correctness (consensus, rewards, slashing)

### Out of Scope
- OpenZeppelin library internals (assumed audited)
- Proxy contract implementation (standard OZ `TransparentUpgradeableProxy`)
- Frontend application (`app/` directory)
- Test contracts (`test/` directory)
- Deployment scripts (`script/` directory)
- offchain components (IPFS storage, indexers)

---

## 12. Contact

For questions about the codebase, architecture decisions, or to request access to additional documentation, please reach out to the project team.
