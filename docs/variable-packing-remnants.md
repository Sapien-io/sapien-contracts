# Variable Packing Remnants — Resolved

All remnants of the old variable packing approach have been removed from `EngineStorage`, the source contracts, and the test suite. This document records what was found and what was fixed.

---

## 1. Misleading "packed" Comments in `src/Types.sol` ✅ Fixed

Three comments used the word "packed" inappropriately. Lines 32 and 45 described mapping consolidation (accurate, but the word "packed" implied storage slot packing). Line 48 was factually wrong — `ConsensusReport` occupies 5 storage slots (4× `uint256` + 1 `bool`), not 2.

| Line | Before | After |
|------|--------|-------|
| 32 | `// Packed range (1 mapping replaces 2; colocates start+count for 1 SLOAD)` | `// Single mapping colocates start+count for one SLOAD (replaces two mappings)` |
| 45 | `// Packed counters (1 mapping replaces 2; colocates revealCount+claimCount)` | `// Single mapping colocates revealCount+claimCount for one SLOAD (replaces two mappings)` |
| 48 | `// ── Consensus Reports (packed into 2-slot struct; keyed by nonce per RISK-006) ──` | `// ── Consensus Reports (keyed by nonce per RISK-006) ──` |

---

## 2. `uint16` Commit Hash Encoding ✅ Fixed

**Was: HIGH severity** — `abi.encodePacked` is type-sensitive: `uint16(8000)` encodes as 2 bytes, while `ValidationLib.sol` expects 32 bytes (`uint256`). Tests using `uint16` were creating hashes that the contract could never verify on reveal.

All commit hash constructions now use bare `score` (already `uint256`) or an explicit `uint256(...)` cast. Fixed across 7 test files:

| File | Locations |
|------|-----------|
| `test/lifecycle/Lifecycle.t.sol` | 4 spots |
| `test/coverage/CoverageGaps.t.sol` | 3 spots |
| `test/SapienCore.t.sol` | 1 spot |
| `test/audit/ReproduceIssues.t.sol` | 1 spot |
| `test/fuzz/Lifecycle.t.sol` | 1 spot |
| `test/findings/2026-02-18/one/SEC_L_02_RedundantZeroCheck.t.sol` | 1 spot |
| `test/invariant/handlers/SapienCoreHandler.sol` | 1 spot (also removed extraneous nonce fields from hash) |

---

## 3. `uint16` Score Variable Declarations ✅ Fixed

Local `uint16 score` variables and helper function signatures (`_validate`, `_commitWithoutReveal`, `_fuzzCommitAndReveal`, `_boundScore`, `_claimCommitReveal`) were updated to `uint256`. Fuzz test function parameters (`uint16 score1Raw`, etc.) were widened to `uint256` so the fuzzer explores the full range.

Files updated:
- `test/BaseTest.sol` — `_commitAndReveal` signature
- `test/lifecycle/Lifecycle.t.sol` — `_validate`, `_commitWithoutReveal`, local vars
- `test/coverage/CoverageGaps.t.sol` — `_validate`, local vars, `uint16[4]` scores array → `uint256[4]`
- `test/audit/ReproduceIssues.t.sol` — `_validate`
- `test/economics/ECON_ProtocolEconomics.t.sol` — `_claimCommitReveal` parameter
- `test/fuzz/Lifecycle.t.sol` — all helpers and 10 test function signatures
- `test/invariant/handlers/SapienCoreHandler.sol` — `score` local var, `NUM_VALIDATIONS` constant
- `test/findings/2026-02-18/one/SEC_M_04_NoRevealDeadline.t.sol` — local vars
- `test/findings/2026-02-18/two/RISK_009_GhostCommitments.t.sol` — local vars
- `test/findings/2026-02-18/two/RISK_010_FlashLoanConsensus.t.sol` — local vars
- `test/findings/2026-02-23/POC_002_LateCommitAfterValidationClaimExpiry.t.sol` — local var
- `test/findings/2026-02-23/fixes/FIX_2026_02_23_ExpectedBehavior.t.sol` — local var

---

## 4. `uint128(VALIDATOR_STAKE)` Casts ✅ Fixed

Both `commitValidation` and `lockValidatorCapacity` accept `uint256`. Unnecessary narrowing casts to `uint128` (remnants of when the stake field was a packed `uint128`) were removed across all test files. Every occurrence of `uint128(VALIDATOR_STAKE)` was replaced with bare `VALIDATOR_STAKE`.

Files updated: `test/SapienCore.t.sol`, `test/lifecycle/Lifecycle.t.sol`, `test/coverage/CoverageGaps.t.sol`, `test/audit/ReproduceIssues.t.sol`, `test/fuzz/Lifecycle.t.sol`, `test/invariant/handlers/SapienCoreHandler.sol`, and all `test/findings/` files.

---

## 5. `uint32(qty)` Cast in `assertEq` ✅ Fixed

`Claim.submittedCount` is now `uint256`. The cast in `test/lifecycle/Lifecycle.t.sol:284` was a leftover from when it was stored as a packed `uint32`.

**Before:** `assertEq(claim.submittedCount, uint32(qty));`  
**After:** `assertEq(claim.submittedCount, qty);`

---

## Test Results After Fixes

```
forge test (unit + integration): 412 passed, 0 failed
forge test --match-test testFuzz:  10 passed, 0 failed (256 runs each)
```
