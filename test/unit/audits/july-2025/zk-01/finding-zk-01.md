# ZK-01: Maximum Stake Cap Bypass via increaseAmount May Let Users Exceed Protocol Limits

**Severity:** High  
**Status:** Resolved

## Description

The validation helper for `increaseAmount()` checks only the additional amount against `maximumStakeAmount`, not the combined total. This allows a user with an existing stake to bypass the protocol's maximum stake limit by adding incremental amounts that individually pass validation but exceed the cap when combined.

### Current Vulnerable Implementation

```solidity
function _validateIncreaseAmount(uint256 additionalAmount, UserStake storage userStake) private view {
    if (additionalAmount == 0) revert InvalidAmount();
    if (additionalAmount > maximumStakeAmount) revert StakeAmountTooLarge();
    if (userStake.amount == 0) revert NoStakeFound();
    // Missing: userStake.amount + additionalAmount <= maximumStakeAmount
}
```

### The Problem

The function validates `additionalAmount` against the maximum but fails to check if the **total resulting stake** (`userStake.amount + additionalAmount`) would exceed the protocol limit. This creates a bypass mechanism for the fundamental stake cap control.

## Attack Scenario

**Impact Scenario:**

1. **Protocol Setup**: `maximumStakeAmount = 2,500 tokens`
2. **Initial Stake**: User stakes 2,000 tokens ✅ (passes validation)
3. **Bypass Attempt**: User calls `increaseAmount(600)` 
4. **Validation**: 600 < 2,500 ✅ (passes individual check)
5. **Result**: Final stake = 2,600 tokens ❌ **Exceeds protocol cap by 100 tokens**

**This violates protocol invariants and undermines the maximum stake control mechanism.**

## Impact

### Protocol Integrity
- **Invariant Violation**: Breaks fundamental assumption that no user can stake more than the maximum limit
- **Risk Management Failure**: Bypasses controls designed to limit individual exposure and concentration
- **Economic Model Disruption**: May affect tokenomics assumptions about maximum individual participation

### Security Implications
- **Unfair Advantage**: Exploiters can accumulate more stake than intended, gaining disproportionate influence
- **Governance Impact**: Could concentrate voting power beyond intended limits
- **Systemic Risk**: Multiple users exploiting this could destabilize the protocol's risk profile

### Regulatory/Compliance Risk
- **Position Limits**: May violate regulatory requirements for maximum individual positions
- **Risk Controls**: Circumvents compliance mechanisms tied to stake amount limits

## Recommendation

### Proposed Fix

Add total stake validation to prevent cap bypass:

```solidity
function _validateIncreaseAmount(uint256 additionalAmount, UserStake storage userStake) private view {
    if (additionalAmount == 0) revert InvalidAmount();
    if (additionalAmount > maximumStakeAmount) revert StakeAmountTooLarge();
+   if (userStake.amount + additionalAmount > maximumStakeAmount) revert StakeAmountTooLarge();
    if (userStake.amount == 0) revert NoStakeFound();
    // ... rest of validation logic
}
```

### Key Changes

1. **Total Validation**: Check that `userStake.amount + additionalAmount <= maximumStakeAmount`
2. **Consistent Error**: Use same `StakeAmountTooLarge()` error for clarity
3. **Placement**: Validate total before other business logic checks

### Alternative Enhanced Error Handling

For better user experience, consider a specific error:

```solidity
error TotalStakeExceedsMaximum(uint256 currentStake, uint256 additionalAmount, uint256 maximum);

// In validation:
if (userStake.amount + additionalAmount > maximumStakeAmount) {
    revert TotalStakeExceedsMaximum(userStake.amount, additionalAmount, maximumStakeAmount);
}
```

This ensures that the protocol's maximum stake limit is enforced consistently across all staking operations, preventing users from bypassing fundamental protocol controls.
