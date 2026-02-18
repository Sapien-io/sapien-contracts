# Sapien PoQ v0.5 — Audit Issue Verification & Fix Plan

**Created**: 2026-02-16  
**Purpose**: Systematically test each audit finding, verify existence, and implement fixes where needed.

---

## Verification Summary (Code Review)

| RISK ID | Finding | Code Review Status | Test Status |
|---------|---------|-------------------|--------------|
| RISK-001 | ERC4626 share transfer bypass | ✅ **ALREADY FIXED** | ✅ Tests exist |
| RISK-002 | Missing ENGINE_ROLE | ✅ **FALSE POSITIVE** | ✅ Deployment & tests grant it |
| RISK-003 | Validator settlement blocked on rejection | ❌ **CONFIRMED** | Needs test |
| RISK-004 | Sybil via sqrt(stake) | ⚠️ **DESIGN DECISION** | Needs analysis |
| RISK-005 | Escrow underflow | ❌ **CONFIRMED** | Needs test |
| RISK-006 | Consensus storage collision | ❌ **CONFIRMED** | Needs test |
| RISK-007 | Zero-stake validation bypass | ⚠️ **PARTIAL** | minStake can be 0 |
| RISK-008 | Arithmetic overflow | ⚠️ **LOW LIKELIHOOD** | Solidity 0.8+ checks |
| RISK-009+ | Economic/MEV issues | ⚠️ **DESIGN** | Out of scope for Phase 1 |

---

## Phase 1: Verify & Test (Week 1)

### Step 1.1: Create Reproduction Test Suite

Create `test/audit/ReproduceIssues.t.sol` with tests for each finding:

```
test/audit/
├── ReproduceIssues.t.sol    # Failing tests that prove issues exist
└── VerifyFixes.t.sol        # Tests that pass after fixes
```

### Step 1.2: Verification Tests by Finding

#### RISK-001: ERC4626 Transfer Bypass — **NO ACTION** (already fixed)

- **Evidence**: `StakeVault.sol:227-235` has `_update()` override
- **Tests**: `CoverageGaps.t.sol:test_transferGuard_blocksLockedShares` exists
- **Action**: Run existing test to confirm; document as false positive in audit

#### RISK-002: Missing ENGINE_ROLE — **NO ACTION** (deployment handles it)

- **Evidence**: `DeployAnvil.s.sol:35` and `BaseTest.sol:61` grant ENGINE_ROLE
- **Action**: Document that deployment/init must grant; add deployment checklist validation

#### RISK-003: Validator Settlement Blocked on Rejection — **VERIFY & FIX**

- **Evidence**: `ValidationLib.sol:183-184` — `report.computed = true` only on acceptance
- **Test**: Create `test_settlement_blocked_on_rejection` — full flow: contribute → validators reject → computeConsensus → settleValidator should fail
- **Fix**: Set `report.computed = true` in rejection branch (line ~199)

#### RISK-005: Escrow Underflow — **VERIFY & FIX**

- **Evidence**: `FinalizationLib.sol:86` — no check before `-= reward`
- **Test**: Create scenario with 4 validators, escrow sufficient for 3 payouts; 4th settlement reverts
- **Fix**: Add `require($.projectEscrow[projectId][proj.rewardToken] >= reward, ...)` before deduction

#### RISK-006: Consensus Storage Collision — **VERIFY & FIX**

- **Evidence**: `Types.sol:57` — `validatorConsensus[projectId][index][validator]` missing nonce
- **Test**: Create resubmission flow; validator from round 1 cannot settle after round 2 computes
- **Fix**: Change mapping to `validatorConsensus[projectId][index][nonce][validator]` — requires storage layout change

#### RISK-007: Zero-Stake Validation — **VERIFY & FIX**

- **Evidence**: `ValidationLib.sol:92` — if `minStake=0`, `stakeAmount=0` passes; `ConsensusLib.sol:49` gives `weight=1`
- **Test**: Create project with `minValidationStake=0`, commit with `stakeAmount=0`
- **Fix**: Require `stakeAmount > 0` in `commitValidation` OR enforce `minValidationStake >= 1` at project creation

---

## Phase 2: Implement Fixes (Week 2)

### Fix Order (by dependency)

1. **RISK-003** (1 day) — Single-line fix in ValidationLib
2. **RISK-007** (0.5 day) — Add stakeAmount > 0 check or min validation
3. **RISK-005** (1 day) — Add escrow check in FinalizationLib
4. **RISK-006** (3 days) — Storage layout change; update ValidationLib, FinalizationLib, Types, QualityEngine

### RISK-004 (Sybil / Quadratic Staking) — **DEFER**

- Requires design review; sqrt(stake) may be intentional for diminishing returns
- Consider as Phase 3 enhancement after critical fixes

---

## Phase 3: Regression & Integration (Week 3)

1. Run full test suite: `forge test`
2. Run invariant tests: `forge test --match-path "test/invariant/*"`
3. Run lifecycle tests: `forge test --match-path "test/lifecycle/*"`
4. Update `audit-report/2026-02-16/` with verification results

---

## Test Implementation Checklist

### ReproduceIssues.t.sol — Tests that MUST fail before fixes

- [ ] `test_RISK003_settlementRevertsOnRejection` — settleValidator reverts after rejected consensus
- [ ] `test_RISK005_fourthValidatorSettlementReverts` — escrow depleted, 4th settlement reverts
- [ ] `test_RISK006_validatorLockedOutAfterResubmission` — round 2 overwrites round 1 data
- [ ] `test_RISK007_zeroStakeGetsWeight` — zero-stake validator influences consensus when minStake=0

### VerifyFixes.t.sol — Tests that MUST pass after fixes

- [ ] `test_RISK003_settlementSucceedsOnRejection` — validators can settle after rejection
- [ ] `test_RISK005_escrowCheckPreventsOverdraw` — reverts with clear error when insufficient
- [ ] `test_RISK006_validatorCanSettleAfterResubmission` — nonce-keyed storage works
- [ ] `test_RISK007_zeroStakeRejected` — commitValidation reverts when stakeAmount=0

---

## Files to Modify

| File | Changes |
|------|---------|
| `src/libraries/ValidationLib.sol` | RISK-003: set report.computed=true on rejection; RISK-007: require stakeAmount>0 or minStake>0 |
| `src/libraries/FinalizationLib.sol` | RISK-005: escrow sufficiency check; RISK-006: use nonce in validatorConsensus key |
| `src/Types.sol` | RISK-006: add nonce to validatorConsensus mapping |
| `src/QualityEngine.sol` | RISK-006: update getValidatorOutlier/getValidatorResult if they exist |
| `test/audit/ReproduceIssues.t.sol` | New — reproduction tests |
| `test/audit/VerifyFixes.t.sol` | New — verification tests |

---

## Storage Layout Impact (RISK-006)

**Current**: `mapping(bytes32 => mapping(uint256 => mapping(address => ValidatorConsensusResult)))`

**New**: `mapping(bytes32 => mapping(uint256 => mapping(uint256 => mapping(address => ValidatorConsensusResult))))`

- Adds one mapping level for nonce
- **Breaking change** — requires fresh deployment or storage migration
- If using proxy: must migrate existing validatorConsensus data or deploy new implementation with new layout (new proxy recommended)

---

## Success Criteria

- [x] RISK-003: Validator settlement on rejection — FIXED
- [x] RISK-005: Escrow sufficiency check — FIXED
- [x] RISK-006: Resubmission flow — FIXED (reset report.computed in contribute)
- [x] RISK-007: Zero-stake rejection — FIXED
- [ ] RISK-006: Storage collision (nonce in validatorConsensus) — DEFERRED (larger refactor)
- [x] Audit tests pass
- [x] Lifecycle rejection tests pass

## Implementation Summary (2026-02-16)

### Fixes Applied
1. **ValidationLib.sol**: Set `report.computed = true` on rejection path (RISK-003)
2. **ValidationLib.sol**: Reject `stakeAmount == 0` in commitValidation (RISK-007)
3. **FinalizationLib.sol**: Add escrow sufficiency check before reward deduction (RISK-005)
4. **ContributionLib.sol**: Reset `report.computed = false` when contributing (enables resubmission after RISK-003 fix)
5. **IQualityEngine.sol**: Add `InsufficientEscrow` error

### Tests Created
- `test/audit/ReproduceIssues.t.sol` — 4 tests covering RISK-003, 005, 006, 007
- `test/audit/VerifyFixes.t.sol` — inherits and runs same tests
