# Sapien PoQ v0.5 — Focused Security Review Plan

**Analysis Date:** 2026-02-16  
**Protocol:** Sapien Proof-of-Quality v0.5  
**Analysis Type:** Regression & Risk Assessment  

---

## Executive Summary

The v0.5 implementation introduces **9 critical regressions** including **3 release blockers** that must be addressed before deployment. The protocol's economic security model is fundamentally broken, with share transfers bypassing all stake locks and zero-stake validations undermining consensus integrity.

**Gate Status: FAIL** — Deployment blocked by permanent stake locks and escrow insolvency risks.

---

## Critical Review Hotspots

### 🔥 RELEASE BLOCKERS (Must Fix Before Deploy)

#### 1. **Validator Stake Lock on Rejection** (H-01)
**Location:** `src/libraries/FinalizationLib.sol:39-96`, `src/libraries/ValidationLib.sol:150-232`
**Risk:** Permanent stake loss on routine rejection
**Review Focus:**
- `settleValidator()` gate: `if (!report.computed) revert`
- `computeConsensus()` logic: `report.computed = true` only on acceptance
- Validator settlement path for rejected contributions

#### 2. **Escrow Underflow in Settlement** (H-02)
**Location:** `src/libraries/FinalizationLib.sol:74-96`
**Risk:** Protocol insolvency, settlement failures
**Review Focus:**
- `settleValidator()` deduction: `$.projectEscrow -= reward` (no guard)
- Compare with dispute resolution guards in `DisputeLib.sol`
- Multiple settlement scenarios depleting escrow

#### 3. **Share Transfers Bypass Locks** (C-02)
**Location:** `src/StakeVault.sol:17-25`
**Risk:** Complete economic security negation
**Review Focus:**
- ERC4626 inheritance without `_update()` override
- Share transfer mechanism vs. lock enforcement
- `_burnShares()` dependency on share ownership

#### 4. **Zero Hash Commit Bypass** (C-03)
**Location:** `src/libraries/ValidationLib.sol:53-109`
**Risk:** Permanent contribution DoS
**Review Focus:**
- Commit hash validation: `if (commitHash == bytes32(0)) revert`
- Duplicate prevention logic bypass
- Zero-stake commit exploitation

---

### 🔥 HIGH PRIORITY (Fix Before Mainnet)

#### 5. **Consensus Not Nonce-Keyed** (H-03)
**Location:** `src/Types.sol:57`, `src/libraries/FinalizationLib.sol:58-59`
**Risk:** Validators locked out of resubmissions
**Review Focus:**
- `validatorConsensus` mapping key structure
- Nonce increment on rejection: `$.submissionNonce[projectId][index]++`
- Settlement permanence across nonces

#### 6. **Zero-Stake Validations** (H-05)
**Location:** `src/libraries/ValidationLib.sol:88-94`, `src/libraries/ConsensusLib.sol:40-50`
**Risk:** Risk-free consensus manipulation
**Review Focus:**
- Minimum stake enforcement logic
- ConsensusLib weight calculation: `weight = stakeAmount > 0 ? stakeAmount : 1`
- Sybil attack vectors

#### 7. **No Validator Capacity Unlock** (H-04)
**Location:** `src/libraries/ValidationLib.sol:39-47`, `src/StakeVault.sol:115-135`
**Risk:** Permanent validator stake trap
**Review Focus:**
- `setValidatorCapacity()` vs. missing `reduceValidatorCapacity()`
- `unlockValidatorCapacity()` exists but never called
- Validator exit mechanisms

---

### ⚠️ MEDIUM PRIORITY (Fix in v0.6)

#### 8. **Fee-on-Transfer Token Handling** (M-02)
**Location:** `src/QualityEngine.sol:280-300`
**Risk:** Escrow accounting errors
**Review Focus:**
- `fundProject()` balance crediting
- Actual received vs. input amount
- Token behavior assumptions

#### 9. **Dispute Escrow Underflow** (M-04)
**Location:** `src/libraries/DisputeLib.sol:930-945`, `src/libraries/DisputeLib.sol:995-1010`
**Risk:** Stuck dispute resolution
**Review Focus:**
- Challenger reward deduction guards
- `resolveDispute()` vs. `escalateDispute()` patterns
- Escrow sufficiency checks

#### 10. **Missing Project Completion** (M-03)
**Location:** `src/libraries/FinalizationLib.sol:170-188`
**Risk:** Permanent escrow and stake locks
**Review Focus:**
- `completeProject()` implementation
- Escrow refund mechanisms
- Originator stake unlocking

---

### 🔍 LOW PRIORITY (Cleanup)

#### 11. **Dead Consensus Algorithm Feature** (L-02)
**Location:** `src/Types.sol:17`, `src/libraries/ValidationLib.sol:262`
**Risk:** Implementation confusion
**Review Focus:**
- `consensusAlgorithm` storage usage
- Direct `ConsensusLib.calculate()` calls
- Pluggable algorithm interface

#### 12. **Validation Adapter Fee Logic** (M-06)
**Location:** `src/libraries/FinalizationLib.sol:79-93`, `src/Types.sol:69`
**Risk:** Escrow accounting inconsistency
**Review Focus:**
- `validationAdapter` mapping population
- Fee deduction in settlement
- Phantom balance creation

---

## Review Methodology

### Phase 1: Critical Path Analysis
1. **Settlement Flows**: Trace validator settlement on acceptance vs rejection
2. **Escrow Accounting**: Verify all deduction paths have sufficiency guards
3. **Lock Mechanisms**: Test share transfers against lock enforcement
4. **Commit-Reveal**: Validate hash uniqueness and zero-hash handling

### Phase 2: Economic Security
1. **Stake Requirements**: Minimum enforcement across all operations
2. **Unlock Paths**: Complete lifecycle for all lock types
3. **Slashing Mechanisms**: Verify execution under all conditions
4. **Reward Distribution**: Escrow conservation and insolvency protection

### Phase 3: Consensus Integrity
1. **Nonce Isolation**: Storage collision prevention across submissions
2. **Weight Calculation**: Stake-to-weight conversion validation
3. **Outlier Detection**: Algorithm correctness and manipulation resistance
4. **State Transitions**: Proper finalization and cleanup

### Phase 4: Integration Testing
1. **End-to-End Flows**: Complete project lifecycle with edge cases
2. **Failure Scenarios**: Partial failures and recovery mechanisms
3. **Multi-User Interactions**: Race conditions and timing dependencies
4. **Token Behaviors**: Fee-on-transfer and rebasing token handling

---

## Testing Priorities

### 🧪 Must Test Before Deploy
1. **Rejection Settlement**: Validator stake recovery on contribution rejection
2. **Escrow Boundaries**: Settlement behavior at escrow limits
3. **Share Transfer Attacks**: Lock bypass exploitation attempts
4. **Zero Hash DoS**: Commit validation with malicious inputs

### 🧪 High Priority Tests
1. **Consensus Resubmission**: Validator participation in rejected index resubmissions
2. **Zero Stake Impact**: Consensus manipulation with zero-stake validators
3. **Capacity Management**: Validator stake locking/unlocking lifecycle
4. **Multi-Dispute Scenarios**: Escrow depletion through dispute spam

### 🧪 Coverage Gaps to Address
1. **ERC-4626 Edge Cases**: Share transfers, inflation attacks, fee-on-transfer
2. **Consensus Algorithm**: Weight calculation, outlier detection, manipulation vectors
3. **Dispute Escalation**: Auto-uphold timing and economic incentives
4. **Adapter Fee Flows**: Complete fee waterfall and escrow accounting

---

## Risk Mitigation Timeline

### Week 1: Release Blockers
- Fix validator settlement on rejection
- Add escrow underflow guards
- Implement share transfer locks
- Block zero hash commits

### Week 2: Economic Security
- Enforce minimum validation stake
- Add validator capacity unlock
- Fix consensus nonce keying
- Complete project lifecycle

### Week 3: Consensus Integrity
- Validate consensus algorithm
- Test outlier detection
- Review dispute mechanisms
- Integration testing

### Week 4: Final Validation
- Full security audit
- Economic modeling
- Mainnet simulation
- Deployment preparation

---

## Success Criteria

The v0.5 protocol is ready for deployment when:
- ✅ All release blockers resolved
- ✅ Economic security model intact (no lock bypasses)
- ✅ Consensus integrity maintained (no manipulation vectors)
- ✅ All funds have clear recovery paths
- ✅ Complete test coverage for critical paths
- ✅ Independent security review completed