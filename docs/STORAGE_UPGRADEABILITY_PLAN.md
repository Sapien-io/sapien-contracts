# Plan: ERC-7201 Namespaced Storage Migration

**Goal:** Migrate all contract state from sequential storage layout to structs with custom storage slots (ERC-7201) for better upgradeability. This eliminates storage layout collision risks during upgrades and removes dependency on the fragile `__gap` pattern.

---

## 1. Background & Motivation

### Current State
- All five upgradeable contracts use **sequential storage layout** (slot 0, 1, 2, ...)
- Each contract has a `__gap` array (31–49 slots) to reserve space for future variables
- **Problem:** Adding state in parent contracts (e.g., OpenZeppelin's `AccessControlUpgradeable`) or reordering inheritance shifts slots and corrupts data
- **Problem:** `__gap` is a blunt instrument—you must pre-allocate, and shrinking/expanding is error-prone

### Target State (ERC-7201)
- Each contract's custom state lives in a **namespace struct** at a pseudorandom slot
- Slot formula: `keccak256(abi.encode(uint256(keccak256(namespaceId)) - 1)) & ~0xff`
- Namespaces are **disjoint** from default storage and from each other
- Adding fields to a namespace struct is **append-only**—no collisions with inherited contracts
- OpenZeppelin v5.x already uses this pattern for `ReentrancyGuardUpgradeable`, `PausableUpgradeable`, etc.

---

## 2. Namespace Convention

Use the convention: `sapien.storage.<ContractName>` (e.g., `sapien.storage.SapienCore`).

---

## 3. Contract-by-Contract Plan

### 3.1 SapienCore

**Namespace:** `sapien.storage.SapienCore`  
**Complexity:** High (most state, many mappings)

**Current state (≈19 slots + gap):**

| Slot | Variable |
|------|----------|
| 0–3 | `_vault`, `_rewards`, `_trust`, `_oracle` |
| 4+ | `projects`, `claims`, `nextClaimId`, `contributions`, `indexReservations` |
| — | `availableIndices`, `stackTop`, `indexIsAvailable` |
| — | `_claimDeadlineDays`, `protocolFeeBasisPoints`, `treasury` |
| — | `consensusThreshold`, `challengePeriod` |
| — | `userActiveClaimedQuantity` |

**Proposed struct:**

```solidity
/// @custom:storage-location erc7201:sapien.storage.SapienCore
struct SapienCoreStorage {
    // Dependencies
    ISapienVault vault;
    IRewards rewards;
    ISapienTrust trust;
    IValidationOracle oracle;
    
    // Project & contribution mappings
    mapping(bytes32 => Project) projects;
    mapping(bytes32 => mapping(uint256 => Claim)) claims;
    mapping(bytes32 => uint256) nextClaimId;
    mapping(bytes32 => mapping(uint256 => Contribution)) contributions;
    mapping(bytes32 => mapping(uint256 => IndexReservation)) indexReservations;
    
    // Index management
    mapping(bytes32 => mapping(uint256 => uint256)) availableIndices;
    mapping(bytes32 => uint256) stackTop;
    mapping(bytes32 => mapping(uint256 => bool)) indexIsAvailable;
    
    // Config
    uint256 claimDeadlineDays;
    uint256 protocolFeeBasisPoints;
    address treasury;
    uint256 consensusThreshold;
    uint256 challengePeriod;
    
    // Per-user limits
    mapping(bytes32 => mapping(address => uint256)) userActiveClaimedQuantity;
    
    // Future slots (append-only for upgrades)
    // uint256 _reserved1;
    // uint256 _reserved2;
}
```

**Access pattern:**

```solidity
bytes32 private constant SAPIEN_CORE_STORAGE_LOCATION = ...; // computed

function _getSapienCoreStorage() private pure returns (SapienCoreStorage storage $) {
    assembly {
        $.slot := SAPIEN_CORE_STORAGE_LOCATION
    }
}
```

Replace all `_vault`, `_rewards`, `projects[key]`, etc. with `_getSapienCoreStorage().vault`, `_getSapienCoreStorage().projects[key]`, etc.

---

### 3.2 SapienVault

**Namespace:** `sapien.storage.SapienVault`  
**Complexity:** Low

**Current state:** `lockedStake` mapping + 49-slot gap

**Proposed struct:**

```solidity
/// @custom:storage-location erc7201:sapien.storage.SapienVault
struct SapienVaultStorage {
    mapping(address => uint256) lockedStake;
    // Future: uint256 _reserved1;
}
```

**Note:** `ERC4626Upgradeable` inherits `ERC20Upgradeable`; token balances and total supply use OpenZeppelin’s namespaced storage. Only `lockedStake` is Sapien-specific.

---

### 3.3 SapienTrust

**Namespace:** `sapien.storage.SapienTrust`  
**Complexity:** Medium

**Current state (≈10 slots + gap):**

- `vault`, `minStakeRequired`, `roleMinStake`, `reputationDecayPerDay`
- `userReputations`, `userSkills`, `lastSkillValidatedAt`, `dailyReputationGain`, `lastGainUpdateDay`
- `protocolRolesConfigured`

**Proposed struct:** Group all of the above into `SapienTrustStorage`.

---

### 3.4 Rewards

**Namespace:** `sapien.storage.Rewards`  
**Complexity:** Medium

**Current state:**

- `core`
- `projectRewards`, `contributorRewards`, `rewardsClaimed`, `validatorRewards`, `validatorRewardsClaimed`
- `totalAllocated`, `maxFeeBps`

**Proposed struct:** Single `RewardsStorage` struct with all fields.

---

### 3.5 ValidationOracle

**Namespace:** `sapien.storage.ValidationOracle`  
**Complexity:** High

**Current state (≈14 slots + gap):**

- `trust`, `vault`, `revealDeadline`
- `algorithms`, `defaultAlgorithm`
- `projectSettings`, `contributionStates`, `validatorStates`, `assignments`
- `pendingQueue`, `validationClaims`, `validationCommits`, `validations`
- `validatorActiveClaimsPerProject`

**Proposed struct:** Single `ValidationOracleStorage` struct. The existing `ProjectSettings`, `ContributionState`, etc. in `IValidationOracle` remain as nested types; they are stored via mappings inside the namespace struct.

---

## 4. Implementation Steps (Phased)

### Phase 1: Preparation
1. **Compute storage locations** for each namespace using the ERC-7201 formula.
2. **Add tests** that assert current storage layout (e.g., key mappings at expected slots) before migration—enables regression checks.
3. **Create migration branch** and ensure all tests pass on `main`.

### Phase 2: Shared Infrastructure
1. Add `src/libraries/StorageLayout.sol` (or similar) with:
   - `erc7201Slot(string memory namespace)` helper (or inline constant for each contract)
   - Optional: shared NatSpec / docs for the pattern
2. Verify Solidity 0.8.30 supports `@custom:storage-location` (supported since 0.8.20).

### Phase 3: Migrate Contracts (Low → High Risk)

**Order (by blast radius and dependency):**
1. **SapienVault** — smallest custom state, no protocol logic
2. **Rewards** — isolated, clear interface
3. **SapienTrust** — used by Oracle and Core
4. **ValidationOracle** — complex but self-contained
5. **SapienCore** — central coordinator, migrate last

**For each contract:**
1. Define `XXXStorage` struct with `@custom:storage-location erc7201:sapien.storage.XXX`.
2. Add `_getXXXStorage()` and storage location constant.
3. Replace every state variable access with `_getXXXStorage().field`.
4. **Remove** the `__gap` array.
5. Run tests and fix any regressions.
6. Optionally run storage layout checks (e.g., `forge inspect ... storage-layout` for documentation).

### Phase 4: Upgrade Path (if contracts are already deployed)

**Critical:** This migration changes storage layout. Contracts **already deployed** with the old layout will have **different data** at the new namespaced slots (they will be empty).

**Options:**
- **A. Fresh deployment only** — Use this for new deployments; do not upgrade existing proxies.
- **B. One-time migration** — Deploy a migration implementation that:
  1. Reads from old slots (0, 1, 2, …).
  2. Writes into the new namespaced struct.
  3. Is callable only once (or by admin) and then disabled.
  4. Next upgrade replaces impl with the “clean” namespaced-only implementation.
- **C. Avoid for production** — If mainnet is live with old layout, document that this refactor applies only to new chains or future versions.

---

## 5. Storage Location Computation

**Formula (Solidity):**
```solidity
keccak256(abi.encode(uint256(keccak256(bytes(namespaceId))) - 1)) & ~bytes32(uint256(0xff))
```

**Example for `sapien.storage.SapienCore`:**
```solidity
bytes32 private constant SAPIEN_CORE_STORAGE_LOCATION =
    keccak256(abi.encode(uint256(keccak256("sapien.storage.SapienCore")) - 1)) & ~bytes32(uint256(0xff));
```

Pre-compute at compile time to avoid runtime overhead. Consider a script or test to verify locations don’t collide.

---

## 6. Gas & Security Considerations

- **Gas:** No meaningful change. Storage read/write cost is the same; the slot is different but still constant.
- **Collisions:** ERC-7201 slots are chosen to avoid the default Solidity tree. Use unique namespace IDs.
- **Append-only:** When upgrading, only **append** fields to namespace structs. Do not remove or reorder.
- **Mappings:** Mappings inside namespace structs follow the same keccak256-derived layout; no special handling.

---

## 7. Checklist for Each Contract

- [ ] Namespace ID chosen and documented
- [ ] Storage struct defined with `@custom:storage-location`
- [ ] `_getXXXStorage()` and location constant added
- [ ] All state accesses migrated
- [ ] `__gap` removed
- [ ] Tests pass
- [ ] Upgrade path documented if applicable

---

## 8. References

- [EIP-7201: Namespaced Storage Layout](https://eips.ethereum.org/EIPS/eip-7201)
- [OpenZeppelin Upgradeable Docs](https://docs.openzeppelin.com/contracts/5.x/upgradeable) (storage namespaces)
- `ReentrancyGuardUpgradeable.sol` in `lib/openzeppelin-contracts-upgradeable` — reference implementation
