# Upgrade and Storage Review Skill

Purpose: Prevent silent protocol death from storage collisions and unsafe upgrades.

## Target Architecture (v0.5)

- **SapienCore**: ERC-1967 proxy + UUPS; ERC-7201 namespaced storage `sapien.storage.SapienCore`.
- **SapienVault**: ERC-1967 proxy + UUPS; ERC-7201 namespaced storage `sapien.storage.StakeVault`.
- **Libraries**: OriginationLib, ContributionLib, ValidationLib, ConsensusLib, FinalizationLib, DisputeLib, ReputationLib -- stateless libraries linked at deploy time; each deployed library that accesses storage uses ERC-7201 to resolve the same `sapien.storage.SapienCore` namespace slot.

---

## What It Checks

### Storage Slot Collisions

- **ERC-7201**: Each contract uses a single namespace slot derived from `keccak256(abi.encode(uint256(keccak256("sapien.storage.<Namespace>")) - 1)) & ~bytes32(uint256(0xff))`.
- **SapienCore**: `EngineStorage` struct contains all protocol state (projects, claims, indexRange, returnStack, contributions, validatorCommits, revealedValidators, validationCounters, consensusReports, validatorConsensus, reputation, pendingRewards, projectEscrow, disputes, originatorReports, originatorLockedStake, pendingContributions, configurable deadlines, validation claims). No overlap with OZ base contracts (AccessControl, Pausable, ReentrancyGuard store in their own ERC-7201 slots).
- **SapienVault**: `SapienVaultStorage` contains `mapping(address => StakeAccount)`. ERC4626, AccessControl, Pausable use OZ storage patterns.
- **Libraries**: Each library that accesses `EngineStorage` has its own `_getStorage()` function resolving the same slot as SapienCore. Verify all libraries use the identical slot constant (`0xb21037e32bd67da4126ec23c3d75228183c819f055709f5aa59aa33cc3fd2b00`).
- **Migration**: Adding new fields to `EngineStorage` or `SapienVaultStorage` -- append to struct; do not reorder or remove. Check that new fields do not change layout of existing ones.

### Missing __gap

- ERC-7201 namespaced storage **does not use** traditional proxy `__gap`, because the entire namespace is a single slot. New mappings/fields are added inside the namespace struct.
- For OZ base contracts (AccessControl, Pausable, etc.), their storage is in standard slots -- upgrades to OZ versions may require `__gap` if layout changes. Document OZ versions used.

### Unsafe Initializer Logic

- [ ] Constructor calls `_disableInitializers()`.
- [ ] `initialize` uses `initializer` modifier (runs once).
- [ ] No re-initialization paths.
- [ ] SapienCore parameters: admin, vault, treasury.
- [ ] SapienVault parameters: asset token, admin.
- [ ] SapienCore grants no roles to vault -- vault's ENGINE_ROLE is granted to SapienCore's address separately (deployment concern).

### Proxy Admin Attack Surface

- [ ] UUPS: implementation upgrade via `upgradeToAndCall` -- authorized by `_authorizeUpgrade`.
- [ ] `DEFAULT_ADMIN_ROLE` holds upgrade authority on both contracts.
- [ ] No separate ProxyAdmin contract in src (deployment concern).
- [ ] No selfdestruct in implementation.

### Upgrade Authorization Logic

- [ ] SapienCore: `_authorizeUpgrade` `onlyRole(DEFAULT_ADMIN_ROLE)`.
- [ ] SapienVault: `_authorizeUpgrade` `onlyRole(DEFAULT_ADMIN_ROLE)`.
- [ ] Upgrade order: SapienCore and SapienVault have cross-dependencies; document upgrade sequence.
- [ ] ENGINE_ROLE: After SapienCore upgrade, new implementation is behind the same proxy address, so ENGINE_ROLE on vault remains valid -- no role re-grant needed.
- [ ] Library upgrades: Libraries are linked at compile time. Upgrading a library requires deploying a new SapienCore implementation with the new library linked, then upgrading the proxy.

---

## Storage Layout Reference (v0.5)

### SapienCore -- EngineStorage

- External references: vault (ISapienVault), treasury (address)
- Fees: protocolFeeBps, originationFeeBps, contributionFeeBps, validationFeeBps, decayRateBps
- Dispute config: disputeBondBps, originatorReportBondBps, originatorStakeRequirement, minValidationStake
- Counter: nextClaimId, nextValidationClaimId
- Mappings: projects, claims, indexRange, returnStack, returnStackTop, contributions, submissionNonce, validatorCommits, revealedValidators, validationCounters
- Consensus: consensusReports (keyed by projectId, index, nonce), validatorConsensus
- Reputation: reputation (address => role => Reputation)
- Rewards: projectEscrow (projectId => token => amount), pendingRewards (user => token => amount)
- Adapters: originationAdapter, contributionAdapter
- Disputes: disputes (keyed by projectId, index, nonce)
- Originator: originatorLockedStake, originatorReports
- Pipeline: pendingContributions
- Claim protection: minClaimAmount, claimCooldown, lastClaimTime
- Configurable deadlines: claimDeadline, challengePeriod, commitDeadline, revealDeadline, forceSettleDelay
- Validation claims: validationClaims

### SapienVault -- SapienVaultStorage

- accounts: mapping(address => StakeAccount)
- StakeAccount: contributorLock, validatorCapacity, inFlight

---

## Output

- **findings_upgrade.json**: Storage collision risk, init issues, auth issues, upgrade hooks.
- **storage_layout.diff**: If PR changes storage -- document layout delta.
