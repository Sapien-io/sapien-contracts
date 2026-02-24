# Unused Code Report

**Date:** 2026-02-24
**Scope:** `src/` folder — all contracts, libraries, interfaces, and type definitions

---

## Summary

| Category                        | Finding Count |
| ------------------------------- | ------------- |
| Unused Constants                | 0             |
| Unused Functions                | 0             |
| Unused Imports                  | 0             |
| Unused Storage Fields           | 0             |
| Enum Values Never Referenced    | 3             |
| Interface-Missing View Functions| 12 (resolved) |

---

## Findings

### F-01: Enum Values Defined but Never Explicitly Referenced

**Severity:** Informational
**Files:** `src/Types.sol`

Three enum values are defined but never explicitly referenced by name anywhere in the `src/` codebase:

#### `DisputeStatus.None`

```solidity
// src/Types.sol:117-122
enum DisputeStatus {
    None,   // <-- never referenced by name
    Open,
    Upheld,
    Rejected
}
```

`DisputeStatus.None` is the default zero-value for uninitialized `Dispute` storage entries. It is relied upon implicitly — when a dispute hasn't been created, `dispute.status` evaluates to `0` (i.e. `None`), and all code paths check for `== Open`, `== Upheld`, or `== Rejected`. No code ever explicitly checks `== DisputeStatus.None` or references it by name.

#### `OriginatorReportStatus.None`

```solidity
// src/Types.sol:124-129
enum OriginatorReportStatus {
    None,   // <-- never referenced by name
    Open,
    Upheld,
    Rejected
}
```

Same pattern as `DisputeStatus.None`. Used only as the implicit default for uninitialized `OriginatorReport` entries.

#### `ClaimStatus.Completed`

```solidity
// src/Types.sol:103-107
enum ClaimStatus {
    Active,
    Completed,  // <-- set but never read
    Expired
}
```

`ClaimStatus.Completed` is **set** in `ContributionLib.sol:153` when all slots in a contribution claim are filled, but it is never **read or checked** by name. The only status checks on claims are `!= ClaimStatus.Active` (which catches both `Completed` and `Expired` implicitly).

| Location | Usage |
| --- | --- |
| `ContributionLib.sol:95` | `claim.status = ClaimStatus.Active` (set) |
| `ContributionLib.sol:125` | `claim.status != ClaimStatus.Active` (check) |
| `ContributionLib.sol:153` | `claim.status = ClaimStatus.Completed` (set, **never read**) |
| `ContributionLib.sol:178` | `claim.status != ClaimStatus.Active` (check) |
| `ContributionLib.sol:230` | `claim.status = ClaimStatus.Expired` (set) |

**Recommendation:** These enum values serve as semantic labels for off-chain consumers reading state via `getClaim()` or `getDispute()`. If that's intentional, consider adding a comment documenting the pattern. Otherwise, consider adding explicit checks (e.g. `require(dispute.status == DisputeStatus.None)`) to make the "uninitialized" semantics explicit and guard against unintended reuse.

---

### F-02: SapienCore View Functions Missing from ISapienCore Interface — RESOLVED

**Severity:** Informational
**Status:** Resolved
**Files:** `src/SapienCore.sol`, `src/interfaces/ISapienCore.sol`

12 public/external view functions were implemented in `SapienCore` but not declared in the `ISapienCore` interface. All 12 have now been added to the interface with NatSpec documentation, and `@inheritdoc ISapienCore` annotations were added to the implementations. The `ConsensusReport` type was also added to the interface's import list.

| Function | Status |
| --- | --- |
| `getReturnStackTop(bytes32)` | Added |
| `getSubmissionNonce(bytes32, uint256)` | Added |
| `getConsensusReport(bytes32, uint256)` | Added |
| `isValidatorOutlier(bytes32, uint256, address)` | Added |
| `isValidatorSettled(bytes32, uint256, uint256, address)` | Added |
| `vault()` | Added |
| `treasury()` | Added |
| `getProjectEscrow(bytes32, address)` | Added |
| `getOriginatorLockedStake(bytes32)` | Added |
| `getDisputeConfig()` | Added |
| `getRevealCount(bytes32, uint256)` | Added |
| `decayRateBps()` | Added |

---

## Items Verified as Used

The following categories were audited and found to have **no unused items**:

### Constants (37 in `Constants.sol` + 9 in `ConsensusLib.sol` + 1 in `SapienVault.sol`)

All constants are referenced outside their defining file or used within internal library logic. Specifically:

- **`Constants.sol`** — All 37 constants are used across `SapienCore.sol`, `ContributionLib.sol`, `FinalizationLib.sol`, `OriginationLib.sol`, `ValidationLib.sol`, `DisputeLib.sol`, `ReputationLib.sol`, and `ConsensusLib.sol`.
- **`ConsensusLib.sol`** — All 9 internal constants (`MIN_REPUTATION_FLOOR`, `PRECISION`, `TIER_*_THRESHOLD`, `TIER_*_SLASH_BPS`) are used within `ConsensusLib.calculate()` and its private helpers.
- **`SapienVault.sol`** — `ENGINE_ROLE` is used in access control modifiers within the vault.

### Functions

All library functions (`ContributionLib`, `FinalizationLib`, `OriginationLib`, `ValidationLib`, `ReputationLib`, `DisputeLib`, `ConsensusLib`) are called from `SapienCore.sol` or internally within their respective libraries. All private/internal helpers are invoked within their defining files.

### Imports

All imports across every file in `src/` are used. No orphaned import statements found.

### Storage Fields

All fields in the `EngineStorage` struct (ERC-7201 namespaced storage) are read and/or written to across the library files.

### Errors and Events

All 55 custom errors and 45 events defined in `ISapienCore.sol` are used (reverted or emitted) in the implementation.
