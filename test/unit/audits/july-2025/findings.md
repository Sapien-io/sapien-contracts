# Audit Findings Checklist - July 2025

## High Risk Issues

- [y] **Finding #1**: Maximum Stake Cap Bypass via increaseAmount May Let Users Exceed Protocol Limits

`commit 9aa946b37ff47e6f1db1b168ff2475b157cbe535`
`commit 734036a39be2f232ff8a584f0362790a31265c70` (Revert some fixes applied for #2 that got merged here)

- [n] **Finding #2**: Users' tokens that have passed the cooldownTime can be penalized unfairly via processQAPenalty()

We are not going to implement this fix because it allows a user to withdraw collateral and bypass quality assurance procedures. If a user has a stake collateral amount that is not subject to quality assurance, the user may be eligible to access tasks or provide contributions that do not pass quality standards and immediately remove their stake collateral. This would negate quality assurance guarantees. Will not implement this suggested fix.

## Medium Risk Issues

- [y] **Finding #3**: Missing Lower‑Bound Check in setMaximumStakeAmount May Lead to Staking Freeze (Denial of Service)

`commit 06afdfe2214c19f5d251ab1ab42cec98fd618755`

- [n] **Finding #4**: Loose Lock‑up Validation in isValidLockUpPeriod May Lead to Lockup Gaming and Reduced Commitment

Task availability for tiers is subject to the amount staked. We have decided that discrete lockup tiers is problematic when combining multiple stake amounts and loose tier validation is optimal with less complexity. Will not implement this suggested fix.

## Low Risk Issues

- [n] **Finding #5**: Unrestricted Cooldown "Refresh" in initiateUnstake May Trap Funds Indefinitely

Blocking multiple calls to initiateUnstake would be a classic case of "security theater" - appearing secure while creating worse problems:

❌ Doesn't actually prevent the SAP-1 exploit
❌ Creates terrible user experience
❌ Breaks legitimate use cases
❌ Introduces new attack vectors
❌ Adds unnecessary complexity

The cooldown refresh approach is superior because it:
✅ Actually prevents the SAP-1 exploit
✅ Maintains user flexibility
✅ Keeps implementation simple
✅ Creates no new attack vectors

- [ ] **Finding #6**: Unrestricted emergencyWithdraw Parameter in SapienVault May Lead to Unauthorized Token Drain and Accounting Inconsistency

`commit dc31e62adfc2f668cc74afff5aaaaa182ec0f445`

- [y] **Finding #7**: Lack of Pause Control in batchClaimRewards May Lead to Inconsistent Claim Behavior During Emergencies

`commit 92461853eb5886c2ea56106d1c6f95a1f2bb7f43`

- [n] **Finding #8**: Missing zero address in claimRewardFor function of SapienRewards contract

Will not implement a check for this.

## Informational Issues

- [n] **Finding #9**: Centralization could lead to bricking the contracts entirely

Contract upradeability is a design choice.




