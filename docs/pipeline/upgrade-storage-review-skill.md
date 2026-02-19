# Upgrade & Storage Review Skill

Purpose: Prevent silent protocol death from storage collisions and unsafe upgrades.

## Target Architecture (v0.5)

- **QualityEngine**: ERC-1967 proxy + UUPS; ERC-7201 namespaced storage `sapien.storage.QualityEngine`.
- **StakeVault**: ERC-1967 proxy + UUPS; ERC-7201 namespaced storage `sapien.storage.StakeVault`.
- **ConsensusLib**: Stateless library, no storage.

---

## What It Checks

### Storage Slot Collisions

- **ERC-7201**: Each contract uses a single namespace slot derived from `keccak256("sapien.storage.<ContractName>") - 1`.
- **QualityEngine**: EngineStorage struct contains all protocol state (projects, claims, contributions, validations, consensus, reputation, rewards, disputes). No overlap with OZ base contracts (AccessControl, Pausable, ReentrancyGuard store in their own slots).
- **StakeVault**: StakeVaultStorage contains `mapping(address => StakeAccount)`. ERC4626, AccessControl, Pausable use OZ storage patterns.
- **Migration**: Adding new fields to EngineStorage or StakeVaultStorage — append to struct; do not reorder or remove. Check that new fields do not change layout of existing ones.

### Missing __gap

- ERC-7201 namespaced storage **does not use** traditional proxy __gap, because the entire namespace is a single slot. New mappings/fields are added inside the namespace struct.
- For OZ base contracts (AccessControl, Pausable, etc.), their storage is in standard slots — upgrades to OZ versions may require __gap if layout changes. Document OZ versions used.

### Unsafe Initializer Logic

- [ ] Constructor calls `_disableInitializers()`.
- [ ] `initialize` uses `initializer` modifier (runs once).
- [ ] No re-initialization paths.
- [ ] Parameters: admin, vault, treasury, consensusAlgorithm (QualityEngine); admin (StakeVault).
- [ ] Engine grants ENGINE_ROLE to vault — verify vault initialized before Engine, and Engine receives vault address.

### Proxy Admin Attack Surface

- [ ] UUPS: implementation upgrade via `upgradeTo`/`upgradeToAndCall` — authorized by `_authorizeUpgrade`.
- [ ] DEFAULT_ADMIN_ROLE holds upgrade authority.
- [ ] No separate ProxyAdmin contract in src (deployment concern).
- [ ] Self-destruct in implementation: UUPS uses `ERC1967Upgrade`; verify implementation has no selfdestruct.

### Upgrade Authorization Logic

- [ ] QualityEngine: `_authorizeUpgrade` onlyRole(DEFAULT_ADMIN_ROLE).
- [ ] StakeVault: `_authorizeUpgrade` onlyRole(DEFAULT_ADMIN_ROLE).
- [ ] Upgrade order: If Engine and Vault have cross-dependencies, document upgrade sequence.
- [ ] ENGINE_ROLE: After Engine upgrade, new implementation must still have ENGINE_ROLE on vault. Role is on vault, not engine — so engine address unchanged; no role re-grant needed.

---

## Storage Layout Reference (v0.5)

### QualityEngine — EngineStorage

- External: vault, consensusAlgorithm, treasury
- Fees: protocolFeeBps, originationFeeBps, contributionFeeBps, validationFeeBps, decayRateBps
- Counter: nextClaimId
- Mappings: projects, claims, indexStates, availableIndexStack, availableIndexTop, contributions, submissionNonce, commitHashes, commitTimestamps, reveals, revealCount, revealedValidators
- Consensus: consensusWeightedAverage, consensusStdDeviation, consensusNonce, consensusComputed, consensusIsOutlier, consensusSlashAmount, consensusWeight, consensusSettled, consensusTotalAccurateWeight
- Reputation: reputation
- Rewards: projectEscrow, pendingRewards
- Adapters: originationAdapter, contributionAdapter, validationAdapter
- Validation claims: validationClaimed, validationClaimCount, committedStakes
- Disputes: disputes, disputeBondBps
- Originator: originatorLockedStake, originatorReports, originatorStakeRequirement, originatorReportBondBps

### StakeVault — StakeVaultStorage

- accounts: mapping(address => StakeAccount)
- StakeAccount: contributorLock, validatorCapacity, inFlight

---

## Output

- **findings_upgrade.json**: Storage collision risk, init issues, auth issues, upgrade hooks.
- **storage_layout.diff**: If PR changes storage — document layout delta.
