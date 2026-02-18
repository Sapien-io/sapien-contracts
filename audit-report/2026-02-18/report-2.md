# Sapien PoQ v0.5 — Security Audit Report (Follow-Up)

## Audit Information

**Protocol**: Sapien PoQ (Proof-of-Quality) v0.5
**Audit Date**: February 18, 2026
**Prior Audit**: February 16, 2026 (23 findings)
**Scope**: QualityEngine.sol, StakeVault.sol, ConsensusLib.sol, all libraries and interfaces in `src/`
**Methodology**: Manual security review guided by security-review, lifecycle-testing, and adversarial-testing skills
**Commit**: `HEAD` (v0.5 branch)

---

## Executive Summary

### Protocol Overview
Sapien PoQ v0.5 is a decentralized quality oracle protocol for AI workflow verification through stake-weighted consensus. The protocol consolidates into 2 core contracts (QualityEngine + StakeVault) plus 6 libraries, implementing ERC-7201 namespaced storage and phased finalization with commit-reveal validation.

### Progress Since Feb 16 Audit

| Metric | Feb 16 | Feb 18 | Delta |
|--------|--------|--------|-------|
| **Total Findings** | 23 | 17 | -6 |
| **Critical** | 4 | 1 | -3 |
| **High** | 9 | 6 | -3 |
| **Medium** | 7 | 7 | +0 |
| **Low** | 3 | 3 | +0 |
| **Release Blockers** | 8 | 3 | -5 |
| **Fixed** | 0 | 9 | +9 |
| **New Issues Found** | — | 3 | +3 |

### Audit Results Summary

| Severity | Count | Status |
|----------|-------|--------|
| **CRITICAL** | 1 | RELEASE BLOCKED |
| **HIGH** | 6 | RELEASE BLOCKED (1 new) |
| **MEDIUM** | 7 | REQUIRES ATTENTION (1 new) |
| **LOW** | 3 | ACCEPTABLE RISK (1 new) |

**Overall Assessment**: **CONDITIONAL — CLOSE TO DEPLOYABLE**
**Risk Level**: HIGH — 3 release blockers remain (down from 8)
**Estimated Remaining Remediation**: 12-15 developer days
**Timeline**: 3-4 weeks to production readiness

### Key Improvements
1. **ERC4626 share transfer bypass** (RISK-001) — FIXED via `_update()` override
2. **Validator settlement blocking** (RISK-003) — FIXED, `computed=true` set on both accept/reject
3. **Consensus storage collision** (RISK-006) — FIXED, nonce added to all mapping keys
4. **Zero-stake validation bypass** (RISK-007) — FIXED, explicit zero-stake rejection
5. **Validator capacity lock** (RISK-012) — FIXED, `reduceValidatorCapacity()` implemented
6. **Zero hash bypass** (RISK-014) — FIXED, `bytes32(0)` commit hash rejected
7. **ERC-7201 storage location** (RISK-021) — FIXED, `verifyStorageLocation()` added
8. **Reward claiming griefing** (RISK-023) — FIXED, min claim amount + cooldown
9. **Arithmetic overflow** (RISK-008) — FIXED, variance overflow protection added

### Remaining Key Risks
1. **Sybil consensus manipulation** remains the top critical risk (unchanged)
2. **NEW**: Claim expiry unlocks in-pipeline stake, causing consensus reverts
3. **Escrow insolvency** risk persists through dispute deductions

---

## Fixed Findings (9 Issues)

The following issues from the Feb 16 audit have been successfully remediated:

### RISK-001: ERC4626 Share Transfer Bypass — FIXED
**Original Severity**: CRITICAL | **Fix**: `_update()` override in StakeVault

StakeVault now overrides `_update()` (line 236) to prevent share transfers when the sender has locked balances. Mints and burns remain unrestricted.

```solidity
// StakeVault.sol:236-244
function _update(address from, address to, uint256 value) internal override {
    if (from != address(0) && to != address(0)) {
        StakeAccount storage acct = _getStakeVaultStorage().accounts[from];
        uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
        uint256 lockedShares = convertToShares(totalLocked);
        if (balanceOf(from) - value < lockedShares) revert TransferExceedsUnlockedShares();
    }
    super._update(from, to, value);
}
```

---

### RISK-003: Validator Settlement Blocked on Rejection — FIXED
**Original Severity**: CRITICAL | **Fix**: `report.computed = true` set in both paths

ValidationLib.computeConsensus() now sets `report.computed = true` regardless of whether the contribution is accepted or rejected (line 208), allowing validators to settle after any consensus outcome.

---

### RISK-006: Consensus Storage Collision on Resubmission — FIXED
**Original Severity**: HIGH | **Fix**: Nonce dimension added to all consensus mappings

All consensus-related mappings now include nonce as a key:
- `validatorCommits[projectId][index][nonce][validator]`
- `validatorConsensus[projectId][index][nonce][validator]`
- `consensusReports[projectId][index][nonce]`
- `revealedValidators[projectId][index][nonce]`
- `validationCounters[projectId][index][nonce]`

---

### RISK-007: Zero-Stake Validation Bypass — FIXED
**Original Severity**: HIGH | **Fix**: Explicit zero-stake rejection

ValidationLib.commitValidation() now rejects zero-stake commits at line 88:
```solidity
if (stakeAmount == 0) revert IQualityEngine.InsufficientStake(1, 0);
```

---

### RISK-008: Arithmetic Overflow in Consensus — FIXED
**Original Severity**: HIGH | **Fix**: Overflow protection in variance calculation

ConsensusLib now checks for overflow in the weighted variance computation (lines 72-76) and uses `Math.mulDiv` for safe division (line 56).

---

### RISK-012: Validator Capacity Lock Without Unlock — FIXED
**Original Severity**: HIGH | **Fix**: `reduceValidatorCapacity()` + `unlockValidatorCapacity()`

Validators can now reduce their capacity via `reduceValidatorCapacity()` which calls `vault.unlockValidatorCapacity()`.

---

### RISK-014: Reputation Manipulation via Zero Hash — FIXED
**Original Severity**: MEDIUM | **Fix**: Zero hash commits rejected

```solidity
if (commitHash == bytes32(0)) revert IQualityEngine.InvalidCommitHash();
```

---

### RISK-021: ERC-7201 Storage Location Unverified — FIXED
**Original Severity**: LOW | **Fix**: `verifyStorageLocation()` added

StakeVault now includes an on-chain verification function that recomputes the ERC-7201 storage slot derivation and compares against the hardcoded constant.

---

### RISK-023: Reward Claiming Gas Griefing — FIXED
**Original Severity**: LOW | **Fix**: Minimum claim amount + cooldown

FinalizationLib.claimReward() now enforces `minClaimAmount` and `claimCooldown` checks, with per-user `lastClaimTime` tracking.

---

## Critical Findings (1 Issue)

### RISK-004: Consensus Oracle Manipulation via Sybil Coordination
**Risk Score**: 15 (HIGH) | **Likelihood**: MEDIUM | **Impact**: CONSENSUS_BECOMES_UNRELIABLE
**Status**: STILL OPEN — unchanged from Feb 16

#### Description
Consensus algorithm uses `sqrt(stake) * reputation` weighting, enabling coordinated Sybil attacks where multiple low-stake accounts can manipulate consensus outcomes. The sublinear (square root) stake weighting means splitting stake across N accounts gives N * sqrt(stake/N) > sqrt(stake) total weight.

#### Technical Details
```solidity
// ConsensusLib.sol:47-49
uint256 sqrtStake = Math.sqrt(uint256(inp.stakeAmount));
uint256 w = sqrtStake * effectiveRep;
if (w == 0) w = 1;
```

#### Exploit Scenario
1. Attacker has 10,000 tokens. Single account weight: sqrt(10000) * 5000 = 500,000
2. Split into 10 accounts with 1,000 each: 10 * sqrt(1000) * 5000 = 10 * 31.6 * 5000 = 1,581,138
3. 3.16x weight amplification through Sybil splitting
4. Coordinated scores overwhelm honest validators

#### Impact
- Consensus integrity compromised for any project
- Quality assurance system becomes gameable
- Economic model undermined

#### Recommended Fix
Replace sqrt weighting with superlinear staking: `weight = (stakeAmount * stakeAmount * effectiveRep) / PRECISION`, making Sybil splitting economically disadvantageous.

---

## High Priority Findings (6 Issues)

### NEW-001: Claim Expiry Premature Stake Unlock
**Risk Score**: 16 (HIGH) | **Likelihood**: HIGH | **Impact**: CONSENSUS_REVERTS_ON_REJECTION
**Status**: NEW

#### Description
When `expireClaim()` is called on a partially-submitted claim, it unlocks the contributor's stake for all submitted indices. However, those submitted contributions are still in the validation pipeline. If any are later rejected by `computeConsensus()`, the slash operation reverts because the contributor's lock has already been released.

#### Technical Details
```solidity
// ContributionLib.sol:211-214 — expireClaim unlocks submitted indices
uint256 slashAmount = unsubmitted > 0 ? proj.minStakeToClaim * unsubmitted : 0;
uint256 unlockAmount = uint256(claim.submittedCount) * proj.minStakeToClaim;
if (slashAmount > 0 || unlockAmount > 0) {
    $.vault.slashAndUnlockContributor(claim.claimant, slashAmount, unlockAmount);
}

// ValidationLib.sol:228-229 — computeConsensus tries to slash on rejection
if (minStake > 0) {
    $.vault.slashContributor(contrib.contributor, minStake);
}
```

#### Exploit Scenario
1. Contributor claims 5 indices (locks 5 * minStake)
2. Submits 3, leaves 2 unsubmitted, deadline passes
3. Anyone calls `expireClaim()`: slashes 2 * minStake, unlocks 3 * minStake
4. Contributor's lock is now 0
5. Validators evaluate the 3 submitted contributions and reject one
6. `computeConsensus()` calls `vault.slashContributor(contributor, minStake)` — **REVERT** (InsufficientContributorLock)
7. Contribution is permanently stuck — cannot be finalized

#### Impact
- **Consensus Blocking**: Rejected contributions after expired claims can never finalize
- **Validator Stake Lock**: Validators who committed to these contributions have permanently locked stake
- **DoS Vector**: Malicious contributors can intentionally trigger this by submitting low-quality work on expired claims

#### Recommended Fix
Do not unlock submitted indices' stake during claim expiry. Only slash unsubmitted indices:
```solidity
uint256 slashAmount = unsubmitted > 0 ? proj.minStakeToClaim * unsubmitted : 0;
uint256 unlockAmount = 0; // Do NOT unlock submitted indices — they're still in pipeline
if (slashAmount > 0) {
    $.vault.slashAndUnlockContributor(claim.claimant, slashAmount, unlockAmount);
}
```

---

### RISK-005: Escrow Underflow in Validator Settlement
**Risk Score**: 12 (MODERATE) | **Likelihood**: MEDIUM | **Impact**: VALIDATORS_LOSE_EARNED_REWARDS
**Status**: STILL OPEN

#### Description
Validator settlement deducts rewards from project escrow without verifying sufficiency. Combined with dispute resolutions that also deduct from escrow, later-settling validators can face reverts when escrow is depleted.

#### Technical Details
```solidity
// FinalizationLib.sol:87
$.projectEscrow[projectId][proj.rewardToken] -= reward; // Reverts on underflow (0.8+)

// DisputeLib.sol:86-88 — Disputes also deduct from escrow
if (challengerReward > 0 && $.projectEscrow[projectId][rewardToken] >= challengerReward) {
    $.projectEscrow[projectId][rewardToken] -= challengerReward;
}
```

#### Impact
- First-to-settle validators get rewards; later ones get reverts
- Protocol insolvency risk when disputes drain escrow
- Settlement becomes a race condition

#### Recommended Fix
Add escrow sufficiency check before reward deduction; cap reward at available escrow:
```solidity
uint256 available = $.projectEscrow[projectId][proj.rewardToken];
if (reward > available) reward = available;
```

---

### RISK-009: Free Option via Ghost Validator Commitments
**Risk Score**: 12 (MODERATE) | **Likelihood**: MEDIUM | **Impact**: VALIDATORS_BECOME_RISK_FREE
**Status**: STILL OPEN

Validators can commit without revealing, observing others' reveals before deciding. `cancelExpiredCommitment` exists but only after `COMMIT_DEADLINE + REVEAL_DEADLINE` (5 days), creating a large free option window. No reveal deadline is enforced in `revealValidation()`.

#### Recommended Fix
Enforce reveal deadline in `revealValidation()`:
```solidity
if (block.timestamp > vc.commitTimestamp + C.REVEAL_DEADLINE) revert RevealWindowClosed();
```

---

### RISK-010: Consensus Flash Loan Manipulation
**Risk Score**: 12 (MODERATE) | **Likelihood**: MEDIUM | **Impact**: CONSENSUS_MANIPULABLE_VIA_FLASH_LOANS
**Status**: STILL OPEN

No stake age requirements or commitment lock periods. Flash-borrowed tokens can be deposited, used for validator capacity, and returned in the same transaction block.

#### Recommended Fix
Implement minimum stake age (e.g., 1 epoch / 1 day) before stake qualifies for validation.

---

### RISK-011: Project Funding Sandwich Attack
**Risk Score**: 12 (MODERATE) | **Likelihood**: MEDIUM | **Impact**: ORIGINATORS_PAY_MEV_TAX
**Status**: STILL OPEN

Index claiming is deterministic and frontrunnable. Attackers can monitor `fundProject` transactions and front-run to claim valuable early indices.

#### Recommended Fix
Implement commit-reveal for index claiming or use randomized index assignment.

---

### RISK-013: No Timelock on UUPS Upgrades
**Risk Score**: 8 (MODERATE) | **Likelihood**: LOW | **Impact**: INSTANT_PROTOCOL_TAKEOVER
**Status**: STILL OPEN

Both QualityEngine and StakeVault use `onlyRole(DEFAULT_ADMIN_ROLE)` for `_authorizeUpgrade()` with no timelock delay.

```solidity
// QualityEngine.sol:539
function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

// StakeVault.sol:268
function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
```

#### Recommended Fix
Deploy behind `TimelockController` with minimum 48h delay for upgrades.

---

## Medium Priority Findings (7 Issues)

### RISK-002: Missing ENGINE_ROLE Grant (Deployment Concern)
**Risk Score**: 8 (MODERATE) | **Likelihood**: LOW | **Impact**: PROTOCOL_NON_FUNCTIONAL_IF_MISSED
**Status**: STILL OPEN — Downgraded from CRITICAL to MEDIUM

QualityEngine.initialize() does not grant ENGINE_ROLE to itself on the StakeVault. This requires the deployment admin to manually call `stakeVault.grantRole(ENGINE_ROLE, qualityEngineAddress)` after deployment. If missed, all staking operations revert.

**Note**: This is a deployment procedure concern, not a code vulnerability. The protocol cannot self-configure this role because it requires admin authority on a separate contract.

#### Recommended Fix
Either accept as deployment checklist item (with automated deployment scripts) or modify `StakeVault.initialize()` to accept an engine address parameter.

---

### NEW-002: No Reveal Deadline Enforcement in revealValidation
**Risk Score**: 9 (MODERATE) | **Likelihood**: MEDIUM | **Impact**: STRATEGIC_REVEAL_TIMING
**Status**: NEW

`revealValidation()` does not enforce any deadline relative to the commit timestamp. Validators can delay reveals indefinitely until `cancelExpiredCommitment` is called (after 5 days). This enables strategic timing: observe other reveals, then reveal only if beneficial.

```solidity
// ValidationLib.sol:112 — No deadline check
function revealValidation(bytes32 projectId, uint256 index, uint16 score, bytes32 salt) public {
    // ... checks commit exists and not already revealed
    // MISSING: deadline enforcement
}
```

#### Recommended Fix
Add: `if (block.timestamp > vc.commitTimestamp + C.REVEAL_DEADLINE) revert IQualityEngine.RevealWindowClosed();`

---

### RISK-015: Dispute Griefing via Bond Arbitrage
**Risk Score**: 9 (MODERATE) | **Likelihood**: MEDIUM | **Impact**: CONTRIBUTORS_DELAYED_REWARDS
**Status**: STILL OPEN

Dispute bonds scale with `rewardRate * disputeBondBps / BPS` with a minimum of 1 wei. Low-value contributions have negligible bond requirements, enabling cheap griefing.

---

### RISK-016: Reputation Farming via Flash Projects
**Risk Score**: 6 (LOW) | **Likelihood**: LOW | **Impact**: REPUTATION_INFLATION
**Status**: STILL OPEN

No minimum project duration or cooldown prevents self-dealing reputation extraction.

---

### RISK-017: Validator Reward Dilution via Capacity Gaming
**Risk Score**: 6 (LOW) | **Likelihood**: LOW | **Impact**: VALIDATOR_REWARDS_UNPREDICTABLE
**Status**: STILL OPEN

Selective reveal strategy enables validators to only participate in profitable validations.

---

### RISK-018: Originator Stake Timing Attack
**Risk Score**: 6 (LOW) | **Likelihood**: LOW | **Impact**: ORIGINATORS_BYPASS_ACCOUNTABILITY
**Status**: STILL OPEN

`originatorStakeRequirement` is read from current storage at funding time, not fixed at project creation. Admin parameter changes affect existing projects.

---

### RISK-019: Malicious Adapter Token Transfer Manipulation
**Risk Score**: 6 (LOW) | **Likelihood**: LOW | **Impact**: CENSORSHIP_OF_USERS
**Status**: STILL OPEN

Adapter contracts can implement arbitrary logic in fee collection paths.

---

## Low Priority Findings (3 Issues)

### NEW-003: Dead Code — validationFeeBps and consensusAlgorithm
**Risk Score**: 3 (LOW) | **Likelihood**: N/A | **Impact**: MISLEADING_CONFIGURATION
**Status**: NEW

Two storage variables are configured via admin setters but never used in protocol logic:

1. **`validationFeeBps`** — Set via `setValidationFee()`, stored in EngineStorage, but never deducted during validation operations. `commitValidation()` does not accept an adapter parameter.

2. **`consensusAlgorithm`** — Set via `setConsensusAlgorithm()`, stored in EngineStorage, but consensus is computed directly via `ConsensusLib.calculate()` instead of calling the stored address.

#### Impact
- Admin may believe these parameters are active when they have no effect
- Dead code increases attack surface and audit burden

#### Recommended Fix
Either implement the intended functionality or remove the dead storage variables and setters.

---

### RISK-020: Fee-on-Transfer Token Accounting Errors
**Risk Score**: 4 (LOW) | **Likelihood**: LOW | **Impact**: ACCOUNTING_INCONSISTENCIES
**Status**: PARTIALLY FIXED

`OriginationLib.fundProject()` correctly uses before/after balance checks for fee-on-transfer tokens. However, `FinalizationLib.claimReward()` and `refundEscrow()` use direct `safeTransfer` without verifying actual received amounts.

---

### RISK-022: Fee Rounding Bias in Multi-Fee Waterfall
**Risk Score**: 6 (LOW) | **Likelihood**: LOW | **Impact**: ADAPTERS_RECEIVE_LESS_FEES
**Status**: STILL OPEN

Sequential fee deductions (protocol fee → origination fee → escrow) create cumulative rounding bias favoring the protocol treasury.

---

## Release Blockers (3 Issues)

### Blocker 1: RISK-004 — Sybil Consensus Manipulation (CRITICAL)
**Effort:** 3 days

`sqrt(stake) * reputation` weighting enables 3.16x Sybil amplification. Replace with superlinear staking.

### Blocker 2: NEW-001 — Claim Expiry Premature Stake Unlock (HIGH)
**Effort:** 1 day

`expireClaim()` unlocks in-pipeline stake, causing `computeConsensus()` to revert on rejection. Do not unlock submitted indices' stake.

### Blocker 3: RISK-005 — Escrow Underflow in Settlement (HIGH)
**Effort:** 1 day

Validator settlement deducts from escrow without sufficiency check. Cap reward at available balance.

**Total blocker remediation**: 5 days + 1 week testing

---

## Remediation Plan

### Phase 1: Critical Blockers (Week 1) — 5 days
| Issue | Fix | Effort |
|-------|-----|--------|
| NEW-001 | Remove submitted-index unlock from `expireClaim` | 1 day |
| RISK-004 | Replace sqrt weighting with superlinear staking | 3 days |
| RISK-005 | Add escrow sufficiency check before reward deduction | 1 day |

### Phase 2: High Priority (Week 2) — 5 days
| Issue | Fix | Effort |
|-------|-----|--------|
| NEW-002 | Add reveal deadline enforcement | 0.5 days |
| RISK-009 | Strengthen reveal deadline + slashing for non-reveal | 1.5 days |
| RISK-010 | Implement stake age requirements | 2 days |
| RISK-013 | Deploy behind TimelockController | 1 day |

### Phase 3: Medium Priority (Weeks 3-4) — 5 days
| Issue | Fix | Effort |
|-------|-----|--------|
| RISK-002 | Automated deployment script with ENGINE_ROLE grant | 0.5 days |
| RISK-011 | Randomized index assignment | 1.5 days |
| RISK-015 | Scale dispute bonds with project value | 1 day |
| RISK-018 | Snapshot stake requirement at project creation | 0.5 days |
| NEW-003 | Remove dead code or implement validation adapter fees | 1 day |

---

## Trust & Centralization Analysis

| Role | Attack Surface | Current Risk | Change from Feb 16 |
|------|----------------|--------------|---------------------|
| **DEFAULT_ADMIN_ROLE** | Upgrade, treasury, all parameters | **HIGH** | Unchanged |
| **ENGINE_ROLE** | All staking operations | **LOW** | Automated (QualityEngine only) |
| **OPERATOR_ROLE** | Dispute resolution | **MEDIUM** | Unchanged |

---

## Conclusion

The Sapien PoQ v0.5 protocol has made **significant progress** since the February 16 audit, fixing 9 of 23 original findings including the most critical protocol-breaking issues (ERC4626 bypass, validator settlement blocking, consensus storage collision, zero-stake bypass). The core protocol flows now function correctly.

However, **3 release blockers remain**:
1. **Sybil consensus manipulation** (RISK-004) — the most architecturally significant issue
2. **Claim expiry premature unlock** (NEW-001) — a new regression that causes consensus reverts
3. **Escrow insolvency risk** (RISK-005) — validator settlement race condition

The new claim expiry bug (NEW-001) is particularly concerning as it introduces a DoS vector that didn't exist before. This should be the highest priority fix as it's a 1-day effort.

**Deployment Recommendation**: Fix the 3 release blockers (estimated 5 days), then conduct targeted re-audit of the consensus weighting changes and claim expiry fix before proceeding to mainnet.

---

*This report was generated on February 18, 2026. All findings are based on manual code review of the `src/` directory guided by the security-review, lifecycle-testing, and adversarial-testing skills.*
