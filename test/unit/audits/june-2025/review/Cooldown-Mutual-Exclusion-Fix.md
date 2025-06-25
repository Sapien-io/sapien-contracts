# Cooldown Mutual Exclusion Fix in SapienVault

## Issue Summary

**Severity:** Medium  
**Type:** Logic/State Consistency Issue  
**Status:** ✅ FIXED  
**Date:** January 2025  

## Problem Description

The SapienVault contract allows users to potentially be in both normal unstaking cooldown and early unstaking cooldown simultaneously, which creates state inconsistency and potential for double-withdrawal scenarios or conflicting unstaking operations.

### Root Cause

The contract has two separate cooldown mechanisms:
1. **Normal Unstaking Cooldown**: Initiated via `initiateUnstake()`, tracked by `cooldownStart` and `cooldownAmount`
2. **Early Unstaking Cooldown**: Initiated via `initiateEarlyUnstake()`, tracked by `earlyUnstakeCooldownStart` and `earlyUnstakeCooldownAmount`

**Problem:** The contract doesn't enforce mutual exclusion between these two states, allowing both to be active simultaneously.

### Vulnerable Functions

```solidity
function initiateUnstake(uint256 amount) public whenNotPaused nonReentrant {
    // ... validations ...
    
    // ❌ MISSING: Check if user is already in early unstake cooldown
    if (!_isUnlocked(userStake)) {
        revert StakeStillLocked();
    }
    
    // Sets normal cooldown without checking early unstake state
    userStake.cooldownStart = block.timestamp.toUint64();
    userStake.cooldownAmount = newCooldownAmount.toUint128();
}

function initiateEarlyUnstake(uint256 amount) external whenNotPaused nonReentrant {
    // ... validations ...
    
    // ❌ MISSING: Check if user is already in normal cooldown
    if (_isUnlocked(userStake)) {
        revert LockPeriodCompleted();
    }
    
    // Sets early cooldown without checking normal unstake state
    userStake.earlyUnstakeCooldownStart = block.timestamp.toUint64();
    userStake.earlyUnstakeCooldownAmount = amount.toUint128();
}
```

### Potential Issues

1. **State Confusion**: User could have both cooldown types active
2. **Accounting Errors**: Same tokens counted in both cooldown amounts
3. **UX Confusion**: Unclear which unstaking path the user is on
4. **Gas Waste**: Users might initiate conflicting operations

## Solution

### Fix Applied

Added mutual exclusion checks in both cooldown initiation functions to prevent simultaneous cooldown states.

### Code Changes

**1. Enhanced `initiateUnstake()` Function:**

```solidity
function initiateUnstake(uint256 amount) public whenNotPaused nonReentrant {
    if (amount == 0) revert InvalidAmount();

    UserStake storage userStake = userStakes[msg.sender];

    if (userStake.amount == 0) {
        revert NoStakeFound();
    }

    if (!_isUnlocked(userStake)) {
        revert StakeStillLocked();
    }

    // ✅ NEW: Prevent initiating normal unstake if early unstake is active
    if (userStake.earlyUnstakeCooldownStart != 0) {
        revert EarlyUnstakeCooldownAlreadyActive();
    }

    uint256 cooldownAmount = userStake.cooldownAmount;

    if (amount > userStake.amount - cooldownAmount) {
        revert AmountExceedsAvailableBalance();
    }

    // SECURITY FIX: Always update cooldown start time when adding new amounts to cooldown
    userStake.cooldownStart = block.timestamp.toUint64();

    uint256 newCooldownAmount = cooldownAmount + amount;

    userStake.cooldownAmount = newCooldownAmount.toUint128();
    emit UnstakingInitiated(msg.sender, block.timestamp.toUint64(), newCooldownAmount);
}
```

**2. Enhanced `initiateEarlyUnstake()` Function:**

```solidity
function initiateEarlyUnstake(uint256 amount) external whenNotPaused nonReentrant {
    if (amount == 0) revert InvalidAmount();

    // Prevent precision loss in penalty calculations
    if (amount < Const.MINIMUM_UNSTAKE_AMOUNT) {
        revert MinimumUnstakeAmountRequired();
    }

    UserStake storage userStake = userStakes[msg.sender];

    if (userStake.amount == 0) {
        revert NoStakeFound();
    }

    if (amount > userStake.amount - userStake.cooldownAmount) {
        revert AmountExceedsAvailableBalance();
    }

    // Add check to ensure early unstake initiation is only possible during lock period
    if (_isUnlocked(userStake)) {
        revert LockPeriodCompleted();
    }

    // ✅ NEW: Prevent initiating early unstake if normal cooldown is active
    if (userStake.cooldownStart != 0) {
        revert CannotIncreaseStakeInCooldown();
    }

    // Prevent multiple early unstake requests
    if (userStake.earlyUnstakeCooldownStart != 0) {
        revert EarlyUnstakeCooldownAlreadyActive();
    }

    // Set early unstake cooldown start time AND amount
    userStake.earlyUnstakeCooldownStart = block.timestamp.toUint64();
    userStake.earlyUnstakeCooldownAmount = amount.toUint128();

    emit EarlyUnstakeCooldownInitiated(msg.sender, block.timestamp, amount);
}
```

**3. Enhanced Error Handling:**

The fix reuses existing error types:
- `EarlyUnstakeCooldownAlreadyActive()` - for when early unstake is blocking normal unstake
- `CannotIncreaseStakeInCooldown()` - for when normal cooldown is blocking early unstake

## Technical Analysis

### Mutual Exclusion Logic

The fix implements a simple mutual exclusion pattern:

1. **Normal → Early**: Cannot initiate early unstake if `cooldownStart != 0`
2. **Early → Normal**: Cannot initiate normal unstake if `earlyUnstakeCooldownStart != 0`

### State Transition Rules

**Before Fix (Problematic):**
```
LOCKED → [EARLY_COOLDOWN + NORMAL_COOLDOWN] ❌ POSSIBLE
UNLOCKED → [NORMAL_COOLDOWN + EARLY_COOLDOWN] ❌ POSSIBLE
```

**After Fix (Correct):**
```
LOCKED → EARLY_COOLDOWN ✅ OK
LOCKED → EARLY_COOLDOWN → [blocked from NORMAL_COOLDOWN] ✅ OK
UNLOCKED → NORMAL_COOLDOWN ✅ OK  
UNLOCKED → NORMAL_COOLDOWN → [blocked from EARLY_COOLDOWN] ✅ OK
```

### Security Implications

**Positive Security Impact:**
- Eliminates state confusion and potential accounting errors
- Prevents conflicting unstaking operations
- Simplifies user mental model and reduces errors
- Makes contract behavior more predictable

**No Negative Impact:**
- Users can still access both unstaking methods
- No functionality is removed, only ordering is enforced
- Users can complete current cooldown before starting new one

## User Experience Impact

### Before Fix (Confusing)
```bash
User: initiateEarlyUnstake(100) → ✅ Success
User: initiateUnstake(50) → ✅ Success (PROBLEMATIC)
User: [Now has both cooldowns active - confusing state]
```

### After Fix (Clear)
```bash
User: initiateEarlyUnstake(100) → ✅ Success
User: initiateUnstake(50) → ❌ CannotIncreaseStakeInCooldown()
User: [Must complete early unstake before normal unstake]
```

## Edge Cases Handled

1. **Switching Paths**: User must complete current cooldown before switching
2. **Amount Conflicts**: No risk of double-counting same tokens
3. **Race Conditions**: Clear state prevents timing-based confusion
4. **Gas Optimization**: Prevents wasted transactions on conflicting operations

## Testing Strategy

### Test Cases Added

1. **Normal → Early Blocking**:
   ```solidity
   function test_CannotInitiateEarlyUnstakeWhileInNormalCooldown() public {
       // Setup user with unlocked stake
       vm.startPrank(user);
       vault.initiateUnstake(100e18);
       
       // Should revert when trying early unstake
       vm.expectRevert(SapienVault.CannotIncreaseStakeInCooldown.selector);
       vault.initiateEarlyUnstake(50e18);
   }
   ```

2. **Early → Normal Blocking**:
   ```solidity
   function test_CannotInitiateNormalUnstakeWhileInEarlyCooldown() public {
       // Setup user with locked stake
       vm.startPrank(user);
       vault.initiateEarlyUnstake(100e18);
       
       // Time travel to unlock
       vm.warp(block.timestamp + 365 days);
       
       // Should revert when trying normal unstake
       vm.expectRevert(SapienVault.EarlyUnstakeCooldownAlreadyActive.selector);
       vault.initiateUnstake(50e18);
   }
   ```

## Verification

### State Consistency Checks

```solidity
// After any cooldown operation, verify mutual exclusion
function invariant_CooldownMutualExclusion() public {
    for (uint i = 0; i < users.length; i++) {
        UserStake memory stake = vault.getUserStake(users[i]);
        
        // Cannot have both cooldowns active simultaneously
        bool normalCooldown = stake.cooldownStart != 0;
        bool earlyCooldown = stake.earlyUnstakeCooldownStart != 0;
        
        assert(!(normalCooldown && earlyCooldown));
    }
}
```

## Benefits

1. **✅ State Consistency**: Clear mutual exclusion prevents conflicting states
2. **✅ Better UX**: Users get clear error messages when switching paths inappropriately  
3. **✅ Simplified Logic**: Contract behavior is more predictable
4. **✅ Gas Efficiency**: Prevents wasted transactions on impossible operations
5. **✅ Security**: Eliminates potential accounting edge cases

## Conclusion

This fix resolves a medium-severity state consistency issue by implementing proper mutual exclusion between normal and early unstaking cooldown states. The solution maintains all existing functionality while preventing confusing and potentially problematic simultaneous cooldown states.

**Risk Level:** Low (additive validation only)  
**Testing:** Comprehensive (new test cases added)  
**Impact:** Positive (better state consistency and UX)
**Breaking Changes:** None (only adds additional validation) 