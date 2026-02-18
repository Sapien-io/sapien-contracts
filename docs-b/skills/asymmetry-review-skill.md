# Implementation and Style Asymmetry Review

Skill for identifying inconsistencies in implementation patterns, coding style, and protocol logic across the Sapien PoQ v0.5 codebase.

## Purpose

This skill ensures that the protocol maintains a high level of code quality, predictability, and safety by identifying "asymmetries" where similar problems are solved differently, or where style and structural conventions diverge.

**Architecture**: v0.5 — QualityEngine, StakeVault, ConsensusLib, Types.sol. See `docs/v0.5-contracs.md`.

---

## Review Methodology

### Phase 1: Structural Asymmetry

Check for inconsistencies in the "skeleton" of the contracts:

1. **Storage (ERC-7201)**:
   - [ ] QualityEngine and StakeVault use ERC-7201 namespaced storage — no traditional __gap.
   - [ ] New fields added to EngineStorage or StakeVaultStorage — append only, no reorder.
   - [ ] Base contracts (AccessControl, Pausable, etc.) use their standard slots.
2. **Inheritance Order**:
   - [ ] Check consistent order: AccessControl, Pausable, ReentrancyGuard (Engine), UUPS.
   - [ ] StakeVault: ERC4626Upgradeable, AccessControl, Pausable, UUPS.
3. **Function Ordering**:
   - [ ] Constructor → Initializer → External (grouped by phase) → View → Internal → Private.
4. **Section Headers**:
   - [ ] Consistent use of `// ═══` or `// ──` headers across files.

### Phase 2: Implementation Inconsistencies

1. **Error Handling**:
   - [ ] All use custom errors (e.g. `NotProjectOriginator()`) — no string reverts.
   - [ ] IQualityEngine, IStakeVault define errors; implementations use interface errors.
   - [ ] ConsensusLib uses `require` for internal validation (e.g. "ConsensusLib: no inputs").
2. **Access Control**:
   - [ ] Engine: onlyRole(OPERATOR_ROLE), onlyRole(DEFAULT_ADMIN_ROLE).
   - [ ] Vault: onlyRole(ENGINE_ROLE) for stake ops; onlyRole(DEFAULT_ADMIN_ROLE) for pause.
   - [ ] Role constants: OPERATOR_ROLE, ENGINE_ROLE — consistent naming.
3. **Event Emission**:
   - [ ] Events emitted after state changes (Checks-Effects-Interactions).
   - [ ] Similar actions emit similarly structured events (e.g. fee updates).
4. **Internal vs. External**:
   - [ ] ConsensusLib: pure internal library; no duplicate logic in Engine.
   - [ ] _updateReputation, _getReputationScore: internal helpers in Engine.

### Phase 3: Style and Documentation

1. **NatSpec**:
   - [ ] @notice, @param, @return on public/external functions.
   - [ ] @dev for complex logic (e.g. commit hash format, reward math).
2. **Naming**:
   - [ ] camelCase for variables; UPPER_SNAKE for constants.
   - [ ] Private storage: _getStorage(), _getStakeVaultStorage().
3. **Imports**:
   - [ ] Named imports: `import {Project, Claim} from "src/Types.sol"`.
   - [ ] Path style: `"src/..."`, `"@openzeppelin/..."`.

---

## Known Asymmetries (v0.5)

- **Storage**: ERC-7201 replaces __gap — add new fields to namespace struct only.
- **Errors**: IQualityEngine / IStakeVault use typed errors; ConsensusLib uses require for internal checks.
- **Interfaces**: IQualityEngine, IStakeVault, IConsensusAlgorithm — IConsensusAlgorithm not yet used in src.
- **Adapter param**: `claimToContribute` and `fundProject` accept adapter; `claimToValidate` not present (validators commit directly).

---

## Output Format

```markdown
## [CATEGORY] Title

**Location(s)**: `QualityEngine.sol`, `StakeVault.sol`

**Asymmetry**: Description of how the two locations differ.

**Risk/Impact**: Maintenance burden, potential for bugs, or decreased readability.

**Recommendation**: How to unify the implementation/style.
```

---

## Anti-Hallucination Rules

- Do not flag a difference if it is functionally required.
- Verify against Types.sol and interfaces before claiming missing types.
- Check v0.5 architecture before flagging "missing" contracts (e.g. no separate Rewards/Trust — inline in Engine).
