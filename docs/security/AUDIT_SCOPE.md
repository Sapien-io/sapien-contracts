# Sapien PoQ Protocol -- Audit Scoping Document

**Date:** February 2026
**Version:** v0.5
**Solidity Version:** ^0.8.30
**License:** MIT
**Framework:** Foundry (forge, via-ir enabled, optimizer 200 runs)
**Target Chain:** Base (L2) -- currently deployed on Base Sepolia testnet
**Repository:** `sapien-contracts`

---

## 1. Project Overview

Sapien Proof-of-Quality (PoQ) Protocol is an open protocol for verifiable, consensus-based quality signals in AI workflows. It adds a verifiable quality layer to AI datasets and agent behaviors through stake-weighted human verification.

**Core concept:** Originators create projects (tasks needing human verification), Contributors submit work against those projects, and Validators stake tokens to commit-reveal quality scores. A single consensus algorithm (`ConsensusLib`) aggregates validator scores using `sqrt(stake) * reputation` weighting, determines contributor rewards, applies tiered slashing to outlier validators, and updates reputation.

### Protocol Participants

| Role | Description |
|------|-------------|
| **Originator** | Creates projects, defines parameters, funds reward pools |
| **Contributor** | Claims contribution slots, submits work (offchain data, onchain hash) |
| **Validator** | Locks validator capacity, commits/reveals quality scores via commit-reveal |
| **Admin** | Configures protocol parameters, authorizes upgrades |
| **Operator** | Resolves disputes and originator reports |
| **Keeper** | Calls permissionless functions: `expireClaim`, `computeConsensus`, `cancelExpiredCommitment`, `escalateDispute`, `escalateOriginatorReport`, `forceSettleValidator`, `completeProject` |

### Key Protocol Flows

1. **Project Creation** -- Originator creates a project with reward token, quantity, and parameters; funds the reward pool.
2. **Contribution Lifecycle** -- Claim slots (locks contributor stake) -> Submit work (hash + IPFS CID) -> Await validation.
3. **Validation (Commit-Reveal)** -- Lock validator capacity -> Claim validation assignment -> Commit `keccak256(score, salt)` with stake -> Reveal score + salt -> Consensus computed.
4. **Finalization (3-phase)** -- `computeConsensus` (accept/reject, outlier detection) -> `settleValidator` (per-validator stake release/slash + reward credit) -> `releaseContributorReward` + `claimReward` (after challenge period).
5. **Disputes** -- `openDispute` (bond posted) -> `resolveDispute` / `escalateDispute` (auto-uphold after 7 days).
6. **Originator Reports** -- `reportOriginator` (bond posted) -> `resolveOriginatorReport` / `escalateOriginatorReport` -> project cancellation if upheld.

---

## 2. Contracts in Scope

### 2.1 Summary Table

| # | Contract/Library | File | Complexity |
|---|------------------|------|------------|
| 1 | `SapienCore` | `src/SapienCore.sol` | **High** |
| 2 | `SapienVault` | `src/SapienVault.sol` | Medium |
| 3 | `OriginationLib` | `src/libraries/OriginationLib.sol` | Medium |
| 4 | `ContributionLib` | `src/libraries/ContributionLib.sol` | Medium |
| 5 | `ValidationLib` | `src/libraries/ValidationLib.sol` | **High** |
| 6 | `ConsensusLib` | `src/libraries/ConsensusLib.sol` | Medium |
| 7 | `FinalizationLib` | `src/libraries/FinalizationLib.sol` | **High** |
| 8 | `DisputeLib` | `src/libraries/DisputeLib.sol` | Medium |
| 9 | `ReputationLib` | `src/libraries/ReputationLib.sol` | Low |
| 10 | `Types` | `src/Types.sol` | Low |
| 11 | `Constants` | `src/Constants.sol` | Low |

**Interfaces (define events, errors, function signatures):**

| # | Interface | File |
|---|-----------|------|
| 12 | `ISapienCore` | `src/interfaces/ISapienCore.sol` |
| 13 | `ISapienVault` | `src/interfaces/ISapienVault.sol` |

---

## 3. Architecture

### 3.1 Contract Topology

```
SapienCore (ERC-1967 proxy + UUPS)
├── OriginationLib (DELEGATECALL)
├── ContributionLib (DELEGATECALL)
├── ValidationLib (DELEGATECALL)
│   └── ConsensusLib (internal pure library)
├── FinalizationLib (DELEGATECALL)
│   └── ReputationLib (DELEGATECALL)
├── DisputeLib (DELEGATECALL)
│   └── ReputationLib (DELEGATECALL)
└── calls ──→ SapienVault (external, stake operations only)

SapienVault (ERC-1967 proxy + UUPS)
├── ERC4626Upgradeable (deposits, withdrawals, shares)
├── Typed stake locks (contributorLock, validatorCapacity, inFlight)
├── Slashing (share burn)
└── Transfer/withdrawal guards
```

**Data flow:** `SapienCore (via libraries) -> SapienVault` for all stake operations. No callbacks from vault to core.

### 3.2 Contract Descriptions

#### SapienCore -- HIGH COMPLEXITY

Unified protocol coordinator deployed behind an ERC-1967 proxy. Delegates to seven libraries via DELEGATECALL. Handles:
- Project creation, funding, and removal (OriginationLib)
- Contribution slot claiming with range+stack index management (ContributionLib)
- Contribution submission with hash and IPFS CID (ContributionLib)
- Commit-reveal validation lifecycle (ValidationLib)
- Consensus computation with sqrt(stake)*reputation weighting (ValidationLib + ConsensusLib)
- 3-phase finalization: compute consensus, settle validators, release rewards (FinalizationLib)
- Dispute lifecycle with bonds and auto-escalation (DisputeLib)
- Originator accountability reports (DisputeLib)
- Per-role reputation with time-based decay (ReputationLib)
- Adapter fee collection (origination, contribution, validation)
- Protocol fee and treasury management

**Security surface:** `nonReentrant` on all value-flow functions, `AccessControlUpgradeable` (DEFAULT_ADMIN_ROLE, OPERATOR_ROLE), cross-contract calls to SapienVault, ERC-7201 namespaced storage, UUPS upgrade authorization.

#### SapienVault -- MEDIUM COMPLEXITY

ERC-4626 compliant vault for staking with typed locks and slashing:
- Token deposit -> vault share issuance
- Three lock categories: `contributorLock`, `validatorCapacity`, `inFlight`
- Stake transitions: capacity -> inFlight (on commit), inFlight -> capacity (on release)
- Slashing via share burning (contributor slash, validator slash)
- Transfer guard: prevents share transfers that would breach locked amounts
- Withdrawal guard: `maxRedeem`/`maxWithdraw` exclude locked amounts
- Paused state blocks all deposits, withdrawals, and redemptions

**Security surface:** `ENGINE_ROLE` restricts all stake operations to SapienCore, ERC-4626 inflation attack mitigation (`_decimalsOffset = 3`), share/asset conversion math, locked balance enforcement on transfers.

#### Libraries (via DELEGATECALL from SapienCore)

| Library | Responsibility |
|---------|----------------|
| **OriginationLib** | `createProject`, `fundProject`, `removeProject` -- project config validation, escrow deposits, protocol/adapter fee deduction, originator stake locking |
| **ContributionLib** | `claimToContribute`, `contribute`, `batchContribute`, `expireClaim` -- index allocation (range+stack hybrid), contributor stake locking, submission hash storage |
| **ValidationLib** | `lockValidatorCapacity`, `unlockValidatorCapacity`, `claimToValidate`, `commitValidation`, `batchCommitValidations`, `revealValidation`, `batchRevealValidations`, `computeConsensus`, `cancelExpiredValidationClaim` -- commit-reveal lifecycle, consensus computation, nonce-based re-validation |
| **ConsensusLib** | `calculate` -- pure math for weighted average, standard deviation, outlier detection (1.5/2/3/5 sigma tiers), tiered slash computation |
| **FinalizationLib** | `settleValidator`, `forceSettleValidator`, `releaseContributorReward`, `claimReward`, `completeProject`, `refundEscrow`, `cancelExpiredCommitment` -- per-validator settlement, reward distribution, escrow management |
| **DisputeLib** | `openDispute`, `upholdDispute`, `rejectDispute`, `reportOriginator`, `upholdOriginatorReport`, `rejectOriginatorReport` -- dispute bonds, challenger rewards, originator slashing, project cancellation |
| **ReputationLib** | `update` -- per-role reputation scoring (0-10,000 BPS), success/failure adjustments, time-based decay, daily gain caps |

---

## 4. External Dependencies

| Library | Version | Usage |
|---------|---------|-------|
| **OpenZeppelin Contracts** | v5.x | `IERC20`, `SafeERC20`, `Math` |
| **OpenZeppelin Contracts Upgradeable** | v5.x | `Initializable`, `AccessControlUpgradeable`, `ReentrancyGuardUpgradeable`, `PausableUpgradeable`, `ERC4626Upgradeable`, `ERC20Upgradeable`, `UUPSUpgradeable` |
| **Forge Std** | latest | Testing only |

No custom or non-standard libraries. No inline assembly (except ERC-7201 storage slot derivation), no `delegatecall` to untrusted targets, no `selfdestruct`.

---

## 5. Upgradeability

Both contracts use the **UUPS Upgradeable** pattern with ERC-1967 proxies:

| Contract | Upgradeable | Pattern | Storage |
|----------|------------|---------|---------|
| SapienCore | Yes | UUPS + `AccessControlUpgradeable` | ERC-7201 namespaced (`sapien.storage.SapienCore`) |
| SapienVault | Yes | UUPS + `ERC4626Upgradeable` + `AccessControlUpgradeable` | ERC-7201 namespaced (`sapien.storage.StakeVault`) |

**Storage safety:** ERC-7201 namespaced storage eliminates collision risk with base contract storage. New fields are added by appending to the namespace struct; no traditional `__gap` is needed.

**Upgrade authorization:** `_authorizeUpgrade` restricted to `DEFAULT_ADMIN_ROLE` on both contracts.

---

## 6. Access Control and Roles

| Role | Granted To | Permissions |
|------|-----------|-------------|
| `DEFAULT_ADMIN_ROLE` | Admin multisig | Grant/revoke roles, configure fees/deadlines, pause/unpause, authorize upgrades |
| `OPERATOR_ROLE` | Operator address | `resolveDispute`, `resolveOriginatorReport`, `removeProject` |
| `ENGINE_ROLE` | SapienCore contract | All stake operations on SapienVault (`lockContributor`, `unlockContributor`, `slashContributor`, `lockValidatorCapacity`, `unlockValidatorCapacity`, `commitStake`, `releaseCommit`, `slashValidator`, `slashAndUnlockContributor`) |

Permissionless functions (callable by anyone): `createProject`, `fundProject`, `claimToContribute`, `contribute`, `expireClaim`, `lockValidatorCapacity`, `unlockValidatorCapacity`, `claimToValidate`, `commitValidation`, `revealValidation`, `computeConsensus`, `settleValidator`, `forceSettleValidator`, `releaseContributorReward`, `claimReward`, `openDispute`, `escalateDispute`, `reportOriginator`, `escalateOriginatorReport`, `cancelExpiredCommitment`, `cancelExpiredValidationClaim`, `completeProject`, `refundEscrow`.

---

## 7. Key Security Considerations

### 7.1 Known Attack Surfaces

| Area | Risk | Description |
|------|------|-------------|
| Commit-Reveal Integrity | High | Validators commit `keccak256(score, salt)` then reveal. Committed stake tracked separately in `ValidatorCommit.stakedAmount` to prevent stake manipulation between commit and reveal. |
| Ghost Validator Evasion | High | Validators who commit but never reveal must be slashed via permissionless `cancelExpiredCommitment`. |
| Tiered Slashing Math | High | ConsensusLib computes outlier deviation in PRECISION (1e18) units; tiered slash BPS applied to committed stake. Overflow protection in variance calculation. |
| Dispute Bond Sufficiency | Medium | Dispute bonds come from challenger's contributor lock. Upheld disputes distribute rewards from project escrow. Must not exceed escrow balance. |
| Nonce-Based Re-validation | Medium | Rejected contributions increment `submissionNonce`, invalidating stale validation state. New validators see a fresh nonce for the re-opened index. |
| Precision Loss | Medium | Consensus calculations, reward distributions, and fee calculations involve division. ConsensusLib uses 1e18 precision. BPS (10,000) for fees. |
| ERC-4626 Inflation | Medium | First-depositor attack mitigated via `_decimalsOffset() = 3`. |
| Transfer Guard | Medium | SapienVault `_update` override blocks share transfers that would breach locked amounts. Must account for all three lock types. |
| Index Management | Medium | Range+stack hybrid for index allocation. Expired/rejected indices returned to stack. Race conditions in rapid claim sequences. |
| Sybil Resistance | Medium | Per-project stake requirements, reputation-weighted consensus, daily reputation gain caps. |
| Auto-Escalation | Medium | Disputes and originator reports auto-uphold after 7-day `DISPUTE_RESOLUTION_DEADLINE`. Escalation is permissionless. |
| Fee Calculations | Low-Medium | Protocol fee (max 10%), adapter fees (max 5% each for origination/contribution/validation), validator reward (max 25%). Rounding and precision. |
| Timestamp Dependence | Low | Claim deadlines, commit/reveal deadlines, challenge periods, dispute resolution deadlines, reputation decay all use `block.timestamp`. |

### 7.2 Tokens Handled

- **Staking Token:** Single ERC-20 token used for vault deposits (set at initialization)
- **Reward Tokens:** Per-project ERC-20 tokens (arbitrary, set by originator at project creation)
- **Vault Shares:** ERC-20 (ERC-4626 shares) issued by SapienVault (`vSAPIEN`)

All ERC-20 interactions use OpenZeppelin's `SafeERC20`. Fee-on-transfer and rebasing tokens are **not** explicitly supported.

### 7.3 Mathematical Operations

- Weighted average consensus: `sqrt(stake) * effectiveReputation` weight, multiplication before division
- Standard deviation calculation: weighted variance with overflow protection, OpenZeppelin `Math.sqrt`
- Tiered slash computation: deviation-in-sigma thresholds (1.5/2/3/5 sigma) -> BPS-based slash
- Reputation scoring: success/failure adjustments, time-based decay (BPS per day), daily gain caps
- Reward pro-rata distribution: per-validator weight / totalAccurateWeight
- Fee deductions: BPS-based protocol, origination, contribution, validation fees
- Share/asset conversions: ERC-4626 `convertToShares`/`convertToAssets`
- Slashing: share burn via `_burnShares(user, assetAmount)`

---

## 8. Testing Overview

### Test Categories

- **Core unit tests:** SapienCore, SapienVault, ConsensusLib, individual library tests
- **Lifecycle tests:** End-to-end happy path, phased finalization, dispute flows
- **Invariant tests:** Vault solvency, escrow conservation, index tracking
- **Fuzz tests:** Consensus edge cases, fee calculations, reputation decay
- **Adversarial tests:** Flash loan attacks, sybil/collusion, ghost validators, dispute griefing
- **Finding-specific tests:** Reproductions of previously identified vulnerabilities

---

## 9. Deployment Information

| Parameter | Value |
|-----------|-------|
| Target chain | Base (Ethereum L2) |
| Current deployment | Base Sepolia testnet (chain ID 84532) |
| Proxy pattern | ERC-1967 + UUPS |
| Storage pattern | ERC-7201 namespaced |
| Solidity compiler | 0.8.30 |
| Optimizer | Enabled, 200 runs |
| via-ir | Enabled |
| Contract verification | Basescan API |

### Deployed Contracts (Base Sepolia)

| Contract | Description |
|----------|-------------|
| SapienCore (proxy) | Unified protocol logic |
| SapienVault (proxy) | ERC-4626 staking vault |

---

## 10. Scope Clarifications

### In Scope
- All `.sol` files in `src/` (contracts, libraries, interfaces, types, constants)
- Upgradeability (initialization, ERC-7201 storage layout, UUPS authorization)
- Cross-contract interactions: SapienCore <-> SapienVault trust boundary
- Library DELEGATECALL safety (all libraries operate on SapienCore's storage)
- Economic/game-theoretic attacks (sybil, collusion, flash loans, dispute griefing)
- Mathematical correctness (consensus, rewards, slashing, reputation)
- Dispute and originator report lifecycle (bonds, escalation, auto-uphold)

### Out of Scope
- OpenZeppelin library internals (assumed audited)
- Proxy contract implementation (standard OZ ERC-1967)
- Frontend application
- Test contracts (`test/` directory)
- Deployment scripts (`script/` directory)
- Offchain components (IPFS storage, indexers)

---

## 11. Contact

For questions about the codebase, architecture decisions, or to request access to additional documentation, please reach out to the project team.
