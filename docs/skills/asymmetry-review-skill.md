# Implementation and Style Asymmetry Review

Skill for identifying inconsistencies in implementation patterns, coding style, and protocol logic across the Sapien V2 codebase.

## Purpose

This skill ensures that the protocol maintains a high level of code quality, predictability, and safety by identifying "asymmetries" where similar problems are solved differently, or where style and structural conventions diverge.

## Review Methodology

### Phase 1: Structural Asymmetry

Check for inconsistencies in the "skeleton" of the contracts:

1.  **Storage Gaps**:
    - [ ] Compare `__gap` sizes across upgradeable contracts.
    - [ ] Verify if gaps are consistently placed at the end of state variables.
    - [ ] Check if the total slot count (variables + gap) is consistent (e.g., aiming for 50 or 100 slots).
    - **Current Observation**: `SapienCore` (33), `SapienVault` (49), `Rewards` (42), `ValidationOracle` (25).
2.  **Inheritance Order**:
    - [ ] Check if `Initializable`, `AccessControlUpgradeable`, `ReentrancyGuardUpgradeable`, and `PausableUpgradeable` are inherited in a consistent order.
3.  **Function Ordering**:
    - [ ] Verify if the standard order is followed: Constructor -> Initializer -> Receive/Fallback -> External -> Public -> Internal -> Private.
4.  **Section Headers**:
    - [ ] Ensure `// ============================================` or similar headers are used consistently across all files.

### Phase 2: Implementation Inconsistencies

Check how logic is implemented across contracts:

1.  **Error Handling**:
    - [ ] Identify mixing of `revert("string")` and `revert CustomError()`.
    - [ ] Check if `ISharedTypes.sol` constants (e.g., `UNAUTHORIZED_NOT_CLAIM_OWNER`) are used consistently or if some contracts define their own.
    - [ ] Verify if `require` is used instead of `if (...) revert`.
2.  **Access Control**:
    - [ ] Compare the use of `onlyRole(ROLE)` vs. internal `_checkRole` functions.
    - [ ] Verify if role definitions (e.g., `SAPIEN_CORE_ROLE` vs `CORE_ROLE`) are consistent across `ISharedTypes.sol` and implementations.
3.  **Event Emission**:
    - [ ] Check if events are emitted *after* state changes (Checks-Effects-Interactions).
    - [ ] Verify if similar state changes (e.g., setting a threshold) emit similarly structured events across contracts.
4.  **Internal vs. External Helpers**:
    - [ ] Look for duplicated logic that should be moved to a library (e.g., `ConsensusLib.sol`).

### Phase 3: Style and Documentation

1.  **Natspec Completeness**:
    - [ ] Ensure all public/external functions have `@notice`, `@param`, and `@return`.
    - [ ] Check for `@dev` comments explaining complex logic or security considerations.
2.  **Naming Conventions**:
    - [ ] Check for mixed casing in variables (camelCase vs snake_case).
    - [ ] Verify consistency in private/internal variable prefixes (e.g., `_variableName`).
3.  **Import Style**:
    - [ ] Check if imports are named (e.g., `import {X} from "..."`) or global.
    - [ ] Verify consistency in pathing (relative vs absolute).

## Known Asymmetries (Current State)

-   **Storage Gaps**: High variance in gap sizes (`SapienCore`: 33, `SapienVault`: 49, `Rewards`: 42, `ValidationOracle`: 25).
-   **Error Handling**: [Note: The `revert("Max validations cannot exceed 100")` has been removed; `numberOfValidations` is now set per-project without a global cap.] Some contracts use string reverts while others use pure custom errors.
-   **Unauthorized Reasons**: `ISharedTypes.sol` defines string constants for reasons (e.g., `UNAUTHORIZED_NOT_CLAIM_OWNER`) and a single `error Unauthorized(string reason)`. Some contracts use this pattern, while others use dedicated error types like `error OnlyCore()`.
-   **Constants**: `ValidationOracle` uses error codes from `ISharedTypes.sol` inside `revert Unauthorized(CODE)`, while `Rewards` uses dedicated custom error types like `revert OnlyCore()`.

## Output Format

### Asymmetry Finding Template

```markdown
## [CATEGORY] Title

**Location(s)**: `ContractA.sol`, `ContractB.sol`

**Asymmetry**: Description of how the two locations differ.

**Risk/Impact**: Maintenance burden, potential for bugs, or decreased readability.

**Recommendation**: How to unify the implementation/style.
```

---

## Anti-Hallucination Rules

-   Do not flag a difference if it is functionally required by the specific contract.
-   Always verify against the latest `ISharedTypes.sol` before claiming a constant is missing or redundant.
-   Check inheritance depth before flagging inheritance order as incorrect.
