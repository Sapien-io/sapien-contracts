# QA Penalty Cooldown Double Counting Fix

## Issue Description

There was a critical bug in the `processQAPenalty()` function where tokens currently in the cooldown period were being double counted when calculating the maximum penalty amount.

### Root Cause

In the `_calculateApplicablePenalty()` function, the calculation was:

```solidity
uint256 totalAvailable = uint256(userStake.amount) + uint256(userStake.cooldownAmount);
```

This is incorrect because `cooldownAmount` is a **subset** of `amount`, not additional tokens.

### How the Staking System Works

1. When users stake tokens, they are stored in `userStake.amount`
2. When users initiate unstaking, tokens move into cooldown but remain part of the total staked amount:
   - `userStake.amount` remains unchanged (still contains all staked tokens)
   - `userStake.cooldownAmount` tracks how many of those tokens are in cooldown
3. When unstaking is completed, **both** `amount` and `cooldownAmount` are reduced by the same value

### The Bug

The penalty calculation incorrectly treated `cooldownAmount` as additional tokens, leading to:

- If a user staked 5000 tokens and put 2000 in cooldown
- Bug calculation: `totalAvailable = 5000 + 2000 = 7000` ❌
- Correct calculation: `totalAvailable = 5000` ✅

This allowed penalties to be applied against more tokens than were actually staked.

## Example Scenarios

### Scenario 1: Partial Cooldown
- User stakes: 5000 tokens
- User initiates cooldown: 2000 tokens
- State: `amount = 5000`, `cooldownAmount = 2000`
- Bug: Max penalty = 7000 tokens ❌
- Fix: Max penalty = 5000 tokens ✅

### Scenario 2: Full Cooldown
- User stakes: 3000 tokens  
- User initiates cooldown: 3000 tokens (all tokens)
- State: `amount = 3000`, `cooldownAmount = 3000`
- Bug: Max penalty = 6000 tokens ❌ (double counting all tokens!)
- Fix: Max penalty = 3000 tokens ✅

## The Fix

Changed `_calculateApplicablePenalty()` from:

```solidity
function _calculateApplicablePenalty(UserStake storage userStake, uint256 requestedPenalty)
    internal
    view
    returns (uint256)
{
    uint256 totalAvailable = uint256(userStake.amount) + uint256(userStake.cooldownAmount); // BUG
    return requestedPenalty > totalAvailable ? totalAvailable : requestedPenalty;
}
```

To:

```solidity
function _calculateApplicablePenalty(UserStake storage userStake, uint256 requestedPenalty)
    internal
    view
    returns (uint256)
{
    // Fix: cooldownAmount is a subset of amount, not additional to it
    // Only use amount as the maximum penalty, since cooldownAmount is already counted within amount
    uint256 totalAvailable = uint256(userStake.amount);
    return requestedPenalty > totalAvailable ? totalAvailable : requestedPenalty;
}
```

## Why This Fix is Correct

1. **Semantic Correctness**: `cooldownAmount` represents tokens that are "marked for unstaking" but are still part of the user's stake
2. **Consistency with Unstaking Logic**: During `unstake()`, both `amount` and `cooldownAmount` are reduced by the same value
3. **Financial Correctness**: Penalties should only be applied against actually staked tokens, not double-counted tokens

## Testing

The fix was verified with comprehensive tests that:

1. Demonstrate the bug existed (penalties could exceed staked amounts)
2. Verify the fix prevents double counting
3. Ensure all existing functionality remains intact

### Test Results

- ✅ All existing SapienVault tests pass (91/91)
- ✅ All existing QA tests pass (26/26)  
- ✅ New double counting tests pass (2/2)

## Impact

- **Security**: Prevents over-penalization of users
- **Fairness**: Ensures penalties are calculated against actual stake amounts
- **Consistency**: Aligns penalty calculation with the rest of the staking logic

This fix ensures that QA penalties are calculated correctly and fairly, without double counting tokens that are in cooldown. 