# Implementation and Style Asymmetry Review

Skill for identifying inconsistencies in implementation patterns, coding style, and protocol logic across the Sapien PoQ v0.5 codebase.

## Purpose

This skill ensures that the protocol maintains a high level of code quality, predictability, and safety by identifying "asymmetries" where similar problems are solved differently, or where style and structural conventions diverge.

**Architecture**: v0.5 -- SapienCore, SapienVault, 7 libraries (OriginationLib, ContributionLib, ValidationLib, ConsensusLib, FinalizationLib, DisputeLib, ReputationLib), Types.sol, Constants.sol. See `docs/security/AUDIT_SCOPE.md`.

---

## Review Methodology

### Phase 1: Structural Asymmetry

Check for inconsistencies in the "skeleton" of the contracts:

1. **Storage (ERC-7201)**:
   - [ ] SapienCore and SapienVault use ERC-7201 namespaced storage -- no traditional __gap.
   - [ ] All 7 libraries that access EngineStorage use the same ERC-7201 slot constant.
   - [ ] New fields added to EngineStorage or SapienVaultStorage -- append only, no reorder.
   - [ ] Base contracts (AccessControl, Pausable, etc.) use their standard slots.
2. **Inheritance Order**:
   - [ ] SapienCore: AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable.
   - [ ] SapienVault: ERC4626Upgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable.
3. **Function Ordering**:
   - [ ] Constructor -> Initializer -> External (grouped by phase) -> View -> Internal -> Private.
4. **Section Headers**:
   - [ ] Consistent use of `// ═══` or `// ──` headers across files.

### Phase 2: Implementation Inconsistencies

1. **Error Handling**:
   - [ ] All use custom errors (e.g. `NotProjectOriginator()`) -- no string reverts in contracts.
   - [ ] ISapienCore, ISapienVault define errors; implementations and libraries use interface errors.
   - [ ] ConsensusLib uses `require` for internal validation (e.g. "ConsensusLib: no inputs").
2. **Access Control**:
   - [ ] SapienCore: onlyRole(OPERATOR_ROLE), onlyRole(DEFAULT_ADMIN_ROLE).
   - [ ] SapienVault: onlyRole(ENGINE_ROLE) for stake ops; onlyRole(DEFAULT_ADMIN_ROLE) for pause/upgrade.
   - [ ] Role constants: OPERATOR_ROLE (in Constants.sol), ENGINE_ROLE (in SapienVault) -- consistent naming.
3. **Event Emission**:
   - [ ] Events emitted after state changes (Checks-Effects-Interactions).
   - [ ] Similar actions emit similarly structured events (e.g. fee updates, stake operations).
4. **Library Patterns**:
   - [ ] All libraries that access storage use identical `_getStorage()` with same slot constant.
   - [ ] ConsensusLib: pure math, no storage access.
   - [ ] ReputationLib: used by both FinalizationLib and DisputeLib -- consistent call patterns.

### Phase 3: Style and Documentation

1. **NatSpec**:
   - [ ] @notice, @param, @return on public/external functions.
   - [ ] @dev for complex logic (e.g. commit hash format, reward math).
   - [ ] @inheritdoc for interface implementations.
2. **Naming**:
   - [ ] camelCase for variables; UPPER_SNAKE for constants.
   - [ ] Private storage accessors: `_getStorage()`, `_getSapienVaultStorage()`.
3. **Imports**:
   - [ ] Named imports: `import {Project, Claim} from "src/Types.sol"`.
   - [ ] Path style: `"src/..."`, `"@openzeppelin/..."`.

---

## Known Asymmetries (v0.5)

- **Storage**: ERC-7201 replaces __gap -- add new fields to namespace struct only.
- **Errors**: ISapienCore / ISapienVault use typed errors; ConsensusLib uses require for internal checks.
- **Interfaces**: ISapienCore, ISapienVault -- no IConsensusAlgorithm (pluggable algorithms removed; ConsensusLib is the single implementation).
- **Adapter param**: `fundProject` and `claimToContribute` accept adapter; `commitValidation` accepts adapter; each stored in separate adapter mappings.

---

## Output Format

```markdown
## [CATEGORY] Title

**Location(s)**: `SapienCore.sol`, `SapienVault.sol`

**Asymmetry**: Description of how the two locations differ.

**Risk/Impact**: Maintenance burden, potential for bugs, or decreased readability.

**Recommendation**: How to unify the implementation/style.
```

---

## Anti-Hallucination Rules

- Do not flag a difference if it is functionally required.
- Verify against Types.sol and interfaces before claiming missing types.
- Check v0.5 architecture before flagging "missing" contracts (e.g. no separate Rewards, SapienTrust, ValidationOracle -- all inline in SapienCore via libraries).
