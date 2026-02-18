# Sapien PoQ v0.5 — Risk-Based Fix Plan

## Executive Summary

**Total Findings:** 23 unique issues (after deduplication)  
**Release Blockers:** 8 must-fix issues  
**Overall Risk:** CRITICAL - Protocol not deployable in current state  
**Estimated Total Effort:** 45-50 developer days  
**Timeline:** 8-10 weeks for complete remediation  

## Risk-Based Prioritization Methodology

Fixes are prioritized by Risk Score (Severity × Likelihood), with the following ordering:
1. **Release Blockers** (Risk Score ≥ 12) - Must fix before deployment
2. **High Priority** (Risk Score 8-11) - Fix in first production release
3. **Medium Priority** (Risk Score 6-7) - Fix in subsequent releases
4. **Low Priority** (Risk Score ≤ 5) - Nice-to-have improvements

---

## 🔴 RELEASE BLOCKERS (8 Issues, 22 Days Effort)

### P0 - Critical Path (Fix Immediately - 5 Issues, 10 Days)

| Risk ID | Title | Risk Score | Owner | Effort | Timeline |
|---------|-------|------------|-------|--------|----------|
| RISK-002 | Missing ENGINE_ROLE Grant | 25 (EXTREME) | Smart Contract Team | 1 day | Week 1 |
| RISK-001 | ERC4626 Share Transfer Bypass | 20 (VERY HIGH) | Smart Contract Team | 2 days | Week 1 |
| RISK-003 | Validator Settlement Blocked | 20 (VERY HIGH) | Smart Contract Team | 1 day | Week 1 |
| RISK-007 | Zero-Stake Validation Bypass | 16 (HIGH) | Smart Contract Team | 1 day | Week 1 |
| RISK-004 | Consensus Oracle Manipulation | 15 (HIGH) | Smart Contract Team | 5 days | Week 1-2 |

### P1 - High Risk (Fix Before Release - 3 Issues, 12 Days)

| Risk ID | Title | Risk Score | Owner | Effort | Timeline |
|---------|-------|------------|-------|--------|----------|
| RISK-012 | Validator Capacity Lock Without Unlock | 16 (HIGH) | Smart Contract Team | 2 days | Week 2 |
| RISK-005 | Escrow Underflow in Validator Settlement | 12 (MODERATE) | Smart Contract Team | 2 days | Week 2 |
| RISK-006 | Consensus Storage Collision | 12 (MODERATE) | Smart Contract Team | 3 days | Week 2 |

---

## 🟡 HIGH PRIORITY (5 Issues, 15 Days Effort)

### P2 - Economic Attack Vectors (Week 3-4)

| Risk ID | Title | Risk Score | Owner | Effort | Timeline |
|---------|-------|------------|-------|--------|----------|
| RISK-009 | Free Option via Ghost Validators | 12 (MODERATE) | Smart Contract Team | 4 days | Week 3 |
| RISK-010 | Consensus Flash Loan Manipulation | 12 (MODERATE) | Smart Contract Team | 5 days | Week 3-4 |
| RISK-011 | Project Funding Sandwich Attack | 12 (MODERATE) | Smart Contract Team | 3 days | Week 4 |
| RISK-013 | No Timelock on UUPS Upgrades | 8 (MODERATE) | DevOps/Security | 3 days | Week 4 |

---

## 🟢 MEDIUM PRIORITY (7 Issues, 13 Days Effort)

### P3 - Protocol Improvements (Week 5-6)

| Risk ID | Title | Risk Score | Owner | Effort | Timeline |
|---------|-------|------------|-------|--------|----------|
| RISK-008 | Arithmetic Overflow in Consensus | 8 (MODERATE) | Smart Contract Team | 1 day | Week 5 |
| RISK-014 | Reputation Manipulation via Zero Hash | 9 (MODERATE) | Smart Contract Team | 1 day | Week 5 |
| RISK-015 | Dispute Griefing via Bond Arbitrage | 9 (MODERATE) | Smart Contract Team | 3 days | Week 5 |
| RISK-016 | Reputation Farming via Flash Projects | 6 (LOW) | Smart Contract Team | 4 days | Week 6 |
| RISK-017 | Validator Reward Dilution | 6 (LOW) | Smart Contract Team | 4 days | Week 6 |

---

## 🔵 LOW PRIORITY (3 Issues, 5 Days Effort)

### P4 - Nice-to-Have (Week 7-8)

| Risk ID | Title | Risk Score | Owner | Effort | Timeline |
|---------|-------|------------|-------|--------|----------|
| RISK-018 | Originator Stake Timing Attack | 6 (LOW) | Smart Contract Team | 2 days | Week 7 |
| RISK-019 | Malicious Adapter Token Transfer | 6 (LOW) | Smart Contract Team | 3 days | Week 7 |
| RISK-020 | Fee-on-Transfer Token Accounting | 6 (LOW) | Smart Contract Team | 2 days | Week 7 |
| RISK-021 | ERC-7201 Storage Location Unverified | 6 (LOW) | Smart Contract Team | 1 day | Week 8 |
| RISK-022 | Fee Rounding Bias | 6 (LOW) | Smart Contract Team | 2 days | Week 8 |
| RISK-023 | Reward Claiming Gas Griefing | 4 (LOW) | Smart Contract Team | 1 day | Week 8 |

---

## 📋 Fix Implementation Details

### Critical Path Fixes (P0)

#### RISK-002: Missing ENGINE_ROLE Grant
**Implementation:**
- Add `engine.grantRole(C.ENGINE_ROLE, address(engine));` in QualityEngine.initialize()
- Test: Verify vault operations work after initialization

#### RISK-001: ERC4626 Share Transfer Bypass
**Implementation:**
- Override `_update()` in StakeVault to check locked balances before transfers
- Add validation: `require(balanceOf(from) - value >= lockedAmount, "TransferExceedsUnlockedShares");`

#### RISK-003: Validator Settlement Blocked
**Implementation:**
- Set `report.computed = true` in both acceptance and rejection paths in ValidationLib.computeConsensus()
- Ensure validators can always settle after consensus computation

#### RISK-007: Zero-Stake Validation Bypass
**Implementation:**
- Change ConsensusLib weighting: `weight = stakeAmount > 0 ? sqrtStake * effectiveRep : 0;`
- Reject zero-stake validations entirely: `require(stakeAmount > 0, "ZeroStakeNotAllowed");`

#### RISK-004: Consensus Oracle Manipulation
**Implementation:**
- Implement quadratic staking: `weight = stakeAmount * stakeAmount * effectiveRep / PRECISION`
- Add minimum stake thresholds that scale with project size
- Implement cross-validation correlation checks

### High Priority Fixes (P1)

#### RISK-012: Validator Capacity Lock Without Unlock
**Implementation:**
- Add `unlockValidatorCapacity()` function callable by validators
- Allow full reduction of committed capacity, not just from active commitments

#### RISK-005: Escrow Underflow Protection
**Implementation:**
- Add escrow balance check in FinalizationLib.settleValidator(): `require(escrowBalance >= reward, "InsufficientEscrow");`

#### RISK-006: Consensus Storage Collision
**Implementation:**
- Change mapping key from `(projectId, index, validator)` to `(projectId, index, nonce, validator)`
- Use submissionNonce in validatorConsensus mapping

### Economic Attack Mitigations (P2)

#### RISK-009: Free Option via Ghost Validators
**Implementation:**
- Implement forced reveal mechanism with time-based randomization
- Add reputation penalties for non-reveal even without slashing
- Reduce commit windows and increase reveal requirements

#### RISK-010: Consensus Flash Loan Manipulation
**Implementation:**
- Implement stake commitment lock periods (minimum 1 day)
- Add stake age requirements for validation weight
- Use time-averaged stake calculations

#### RISK-011: Project Funding MEV
**Implementation:**
- Implement commit-reveal for index claiming
- Add random index assignment with post-reveal shuffling
- Add funding cooldown period before indices become claimable

---

## 🧪 Testing Strategy

### Pre-Deployment Testing
- **Unit Tests:** All fixes require comprehensive unit test coverage
- **Integration Tests:** Cross-contract interaction validation
- **Invariant Testing:** Re-run A5 fuzz testing on all fixes
- **Economic Testing:** Simulate attack vectors with test scenarios

### Security Review
- **Internal Review:** Smart contract team review of all fixes
- **External Audit:** Third-party security audit of critical fixes
- **Economic Analysis:** Re-run A6 economic analysis on remediated issues

### Deployment Checklist
- [ ] All P0 fixes implemented and tested
- [ ] All P1 fixes implemented and tested
- [ ] Fuzz testing passes (A5 re-run)
- [ ] Economic analysis shows acceptable risk (A6 re-run)
- [ ] Upgrade safety verified (A7 re-run)
- [ ] Mainnet simulation testing complete

---

## 📊 Success Metrics

### Risk Reduction Targets
- **Critical Issues:** 4 → 0 (100% reduction)
- **High Issues:** 9 → 2 (78% reduction)
- **Overall Risk Score:** Average risk score < 8 for remaining issues

### Protocol Health Metrics
- **Deployment Readiness:** Achieve "READY" status
- **Economic Security:** "SECURE" rating
- **Consensus Integrity:** "ROBUST" rating
- **Fund Safety:** "SECURE" rating

---

## 🚨 Contingency Plans

### Rollback Strategy
- UUPS upgrade pattern allows for emergency rollback
- Timelock implementation (RISK-013) provides 48h delay for safe rollback
- Circuit breaker mechanisms for critical functions

### Monitoring & Alerting
- Real-time invariant monitoring post-deployment
- Economic attack detection systems
- Automated alerting for unusual consensus patterns

---

## 📞 Communication Plan

### Internal Stakeholders
- **Daily Updates:** Progress on critical fixes
- **Weekly Reviews:** Full team status updates
- **Risk Reviews:** Weekly risk assessment updates

### External Stakeholders
- **Progress Reports:** Bi-weekly updates to investors/community
- **Security Disclosures:** Responsible disclosure for critical findings
- **Transparency:** Open publication of fix implementations

---

## 🎯 Next Steps

1. **Immediate (Week 1):** Begin P0 fixes, assign team resources
2. **Week 2:** Complete P0, begin P1 fixes
3. **Week 3-4:** Complete P1-P2, begin testing
4. **Week 5-6:** Complete P3 fixes, full integration testing
5. **Week 7-8:** Complete P4 fixes, security audit
6. **Week 9-10:** Deployment preparation and go-live

**Total Timeline:** 8-10 weeks  
**Go-Live Criteria:** All release blockers fixed, comprehensive testing passed, security audit clean