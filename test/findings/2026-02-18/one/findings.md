# Release Blockers — Sapien PoQ v0.5 (Feb 18 Follow-Up)

## Executive Summary

**Status:** CONDITIONAL — CLOSE TO DEPLOYABLE
**Blockers:** 3 issues must be fixed before mainnet deployment (down from 8)
**Impact:** Consensus manipulation, DoS on rejected contributions, escrow insolvency
**Timeline:** 1 week to address all blockers + 1 week testing
**Progress:** 9 of 23 original findings fixed since Feb 16

---

## Blocker 1: RISK-004 — Sybil Consensus Manipulation (CRITICAL)
**Risk Score:** 15 | **Effort:** 3 days | **Status:** STILL OPEN

### Problem
`sqrt(stake) * reputation` weighting in ConsensusLib enables Sybil splitting amplification. An attacker splitting 10,000 tokens across 10 accounts gains 3.16x more consensus weight than a single account with the same total stake.

### Impact
- Consensus outcomes manipulable by coordinated low-stake accounts
- Quality assurance system becomes unreliable
- Economic incentives broken for honest validators

### Evidence
```solidity
// ConsensusLib.sol:47-49
uint256 sqrtStake = Math.sqrt(uint256(inp.stakeAmount));
uint256 w = sqrtStake * effectiveRep;
```

### Fix
Replace `sqrt(stake)` with `stake * stake` (quadratic) or at minimum `stake` (linear), making splitting economically disadvantageous.

---

## Blocker 2: NEW-001 — Claim Expiry Premature Stake Unlock (HIGH)
**Risk Score:** 16 | **Effort:** 1 day | **Status:** NEW

### Problem
`expireClaim()` unlocks contributor stake for submitted (in-pipeline) indices. If those contributions are later rejected by `computeConsensus()`, the slash operation reverts because the lock has already been released.

### Impact
- Contributions permanently stuck after claim expiry + rejection
- Validator stake permanently locked for stuck contributions
- DoS vector: submit low-quality work, let claim expire, rejection permanently blocked

### Evidence
```solidity
// ContributionLib.sol:211-214
uint256 unlockAmount = uint256(claim.submittedCount) * proj.minStakeToClaim;
// Unlocks stake for indices still in validation pipeline

// ValidationLib.sol:228-229 — later tries to slash but lock is already 0
$.vault.slashContributor(contrib.contributor, minStake); // REVERTS
```

### Attack Scenario
1. Claim 5 indices → locks 5 * minStake
2. Submit 3 (low quality), leave 2 unsubmitted
3. Deadline passes → `expireClaim()` slashes 2, unlocks 3 → lock = 0
4. Validators reject submission → `computeConsensus()` reverts on slash
5. Contribution and validator stakes permanently frozen

### Fix
Do not unlock submitted indices' stake during claim expiry:
```solidity
uint256 slashAmount = unsubmitted > 0 ? proj.minStakeToClaim * unsubmitted : 0;
// Only slash unsubmitted; leave submitted indices' lock for consensus to handle
if (slashAmount > 0) {
    $.vault.slashContributor(claim.claimant, slashAmount);
}
```

---

## Blocker 3: RISK-005 — Escrow Underflow in Settlement (HIGH)
**Risk Score:** 12 | **Effort:** 1 day | **Status:** STILL OPEN

### Problem
Validator settlement deducts rewards from project escrow without checking sufficiency. Dispute resolutions also deduct from escrow. Combined, this creates a race condition where early settlers receive rewards and later ones get reverts.

### Impact
- Later-settling validators lose earned rewards
- Protocol insolvency per-project
- Settlement becomes first-come-first-served

### Evidence
```solidity
// FinalizationLib.sol:87 — No sufficiency check
$.projectEscrow[projectId][proj.rewardToken] -= reward;

// DisputeLib.sol:86-88 — Disputes drain from same pool
$.projectEscrow[projectId][rewardToken] -= challengerReward;
```

### Fix
Cap reward at available escrow balance:
```solidity
uint256 available = $.projectEscrow[projectId][proj.rewardToken];
if (reward > available) reward = available;
$.projectEscrow[projectId][proj.rewardToken] -= reward;
```

---

## Verification Checklist

### Pre-Deployment Requirements
- [ ] All 3 blockers fixed and unit tested
- [ ] Cross-contract integration tests pass for claim expiry + rejection flow
- [ ] Fuzz testing confirms escrow never underflows
- [ ] Sybil resistance validated with new weighting function
- [ ] Regression tests for all 9 previously fixed issues still pass

### Critical Path Testing
- [ ] Partially expired claims with subsequent rejection → no revert
- [ ] Escrow remains solvent after disputes + all settlements
- [ ] Sybil splitting provides no weight advantage with new formula
- [ ] All previously fixed issues (RISK-001,003,006,007,012,014,021,023) still hold

---

## Timeline

### Week 1: Fix Blockers (5 days)
- **Day 1**: NEW-001 — Remove submitted-index unlock from expireClaim
- **Day 1**: RISK-005 — Add escrow sufficiency check
- **Days 2-4**: RISK-004 — Replace sqrt weighting with superlinear staking
- **Day 5**: Integration testing of all three fixes

### Week 2: Verification (5 days)
- Full test suite execution
- Fuzz testing with new weighting
- Security review of fixes
- Regression testing

**Total:** 2 weeks to clear all blockers
**Team:** 1-2 smart contract developers

---

## Comparison: Feb 16 vs Feb 18

| Metric | Feb 16 | Feb 18 |
|--------|--------|--------|
| Release Blockers | 8 | 3 |
| Critical Issues | 4 | 1 |
| Protocol Functional | No | Yes (with edge cases) |
| ERC4626 Bypass | Open | **Fixed** |
| Validator Settlement | Broken | **Fixed** |
| Storage Collisions | Open | **Fixed** |
| Zero-Stake Bypass | Open | **Fixed** |
| Sybil Resistance | Open | Open |
| Escrow Solvency | Open | Open |
| Deployment Estimate | 8-10 weeks | 2-4 weeks |
