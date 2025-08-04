# Audit Findings Checklist - July 2025

## High Risk Issues

- [x] **Finding #1**: Maximum Stake Cap Bypass via increaseAmount May Let Users Exceed Protocol Limits

`commit 9b1892822481160d12e23bc7d5dd48f0fa967439`

- [x] **Finding #2**: Users' tokens that have passed the cooldownTime can be penalized unfairly via processQAPenalty()

We are not going to implement this fix because it allows a user to withdraw collateral and bypass quality assurance procedures. If a user has a stake collateral amount that is not subject to quality assurance, the user may be eligible to access tasks or provide contributions that do not pass quality standards and immediately remove their stake collateral. This would negate quality assurance guarantees.

## Medium Risk Issues

- [ ] **Finding #3**: Missing Lower‑Bound Check in setMaximumStakeAmount May Lead to Staking Freeze (Denial of Service)
- [ ] **Finding #4**: Loose Lock‑up Validation in isValidLockUpPeriod May Lead to Lockup Gaming and Reduced Commitment

## Low Risk Issues

- [ ] **Finding #5**: Unrestricted Cooldown "Refresh" in initiateUnstake May Trap Funds Indefinitely
- [ ] **Finding #6**: Unrestricted emergencyWithdraw Parameter in SapienVault May Lead to Unauthorized Token Drain and Accounting Inconsistency
- [ ] **Finding #7**: Lack of Pause Control in batchClaimRewards May Lead to Inconsistent Claim Behavior During Emergencies
- [ ] **Finding #8**: Missing zero address in claimRewardFor function of SapienRewards contract

## Informational Issues

- [ ] **Finding #9**: Centralization could lead to bricking the contracts entirely

---

**Progress Summary:**
- High Risk: 2/2 resolved
- Medium Risk: 0/2 resolved
- Low Risk: 0/4 resolved
- Informational: 0/1 resolved
- **Total: 2/9 resolved**


