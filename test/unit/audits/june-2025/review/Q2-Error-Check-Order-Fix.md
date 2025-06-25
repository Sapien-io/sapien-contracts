# Error Check Order Fix in `earlyUnstake()` Function

## Issue Summary

**Severity:** Medium  
**Type:** Logic/Testing Issue  
**Status:** ✅ FIXED  
**Date:** January 2025  

## Problem Description

The audit tests were failing because the error checking order in the `earlyUnstake()` function was causing incorrect error types to be thrown. Specifically, when a user called `earlyUnstake()` without first calling `initiateEarlyUnstake()`, the function was throwing `AmountExceedsEarlyUnstakeRequest()` instead of the expected `EarlyUnstakeCooldownRequired()` error.

### Root Cause

The issue stemmed from the order of validation checks in the `earlyUnstake()` function:

**Original (Problematic) Order:**
1. ✅ Basic validations (amount > 0, etc.)
2. ❌ **Check amount vs `earlyUnstakeCooldownAmount`** → `AmountExceedsEarlyUnstakeRequest()`
3. ❌ **Check if cooldown initiated** → `EarlyUnstakeCooldownRequired()`
4. ✅ Other validations...

**Problem:** When `initiateEarlyUnstake()` was never called:
- `userStake.earlyUnstakeCooldownAmount` = 0
- `userStake.earlyUnstakeCooldownStart` = 0
- Any positive amount would trigger check #2 first, throwing `AmountExceedsEarlyUnstakeRequest()`
- Check #3 never executed, so `EarlyUnstakeCooldownRequired()` was never thrown

### Failing Tests

```bash
[FAIL: Error != expected error: AmountExceedsEarlyUnstakeRequest() != EarlyUnstakeCooldownRequired()] 
test_Vault_SAP_1_EarlyUnstakeCannotBypassCooldown() (gas: 212014)

[FAIL: Error != expected error: AmountExceedsEarlyUnstakeRequest() != EarlyUnstakeCooldownRequired()] 
test_Vault_SAP_3_EarlyUnstakeCooldownEnforced() (gas: 41667)
```

## Solution

### Fix Applied

Reordered the validation checks to prioritize cooldown initiation validation before amount limit checks:

**Fixed Order:**
1. ✅ Basic validations (amount > 0, etc.)
2. ✅ **Check if cooldown initiated** → `EarlyUnstakeCooldownRequired()`
3. ✅ **Check amount vs `earlyUnstakeCooldownAmount`** → `AmountExceedsEarlyUnstakeRequest()`
4. ✅ Other validations...

### Code Changes

**Before (Problematic):**
```solidity
function earlyUnstake(uint256 amount) external whenNotPaused nonReentrant {
    // ... basic validations ...
    
    UserStake storage userStake = userStakes[msg.sender];

    if (userStake.amount == 0) {
        revert NoStakeFound();
    }

    // ❌ PROBLEM: Amount check happens BEFORE cooldown check
    if (amount > userStake.earlyUnstakeCooldownAmount) {
        revert AmountExceedsEarlyUnstakeRequest();
    }

    // ... other checks ...

    // ❌ This check happens TOO LATE
    if (userStake.earlyUnstakeCooldownStart == 0) {
        revert EarlyUnstakeCooldownRequired();
    }
    
    // ... rest of function ...
}
```

**After (Fixed):**
```solidity
function earlyUnstake(uint256 amount) external whenNotPaused nonReentrant {
    // ... basic validations ...
    
    UserStake storage userStake = userStakes[msg.sender];

    if (userStake.amount == 0) {
        revert NoStakeFound();
    }

    // ✅ FIXED: Cooldown check happens FIRST
    if (userStake.earlyUnstakeCooldownStart == 0) {
        revert EarlyUnstakeCooldownRequired();
    }

    if (block.timestamp < userStake.earlyUnstakeCooldownStart + Const.COOLDOWN_PERIOD) {
        revert EarlyUnstakeCooldownRequired();
    }

    // ✅ Amount check happens AFTER cooldown validation
    if (amount > userStake.earlyUnstakeCooldownAmount) {
        revert AmountExceedsEarlyUnstakeRequest();
    }
    
    // ... rest of function ...
}
```

## Technical Analysis

### Error Precedence Logic

The fix establishes a logical error precedence that aligns with the user flow:

1. **User Flow Validation:** First ensure the user has initiated the early unstake process
2. **Amount Validation:** Then validate the specific amount being requested
3. **State Validation:** Finally validate other state requirements

### Security Implications

**No Security Impact:** This change only affects error reporting order and does not change the security model:
- All the same validations are performed
- No bypass opportunities are created or removed
- The actual functionality remains identical

### Test Impact

**Positive Impact:** Tests now pass as expected:
- `test_Vault_SAP_1_EarlyUnstakeCannotBypassCooldown()` ✅ PASS
- `test_Vault_SAP_3_EarlyUnstakeCooldownEnforced()` ✅ PASS

## Verification

### Test Results

```bash
# Before Fix
[FAIL: Error != expected error: AmountExceedsEarlyUnstakeRequest() != EarlyUnstakeCooldownRequired()]

# After Fix  
[PASS] test_Vault_SAP_1_EarlyUnstakeCannotBypassCooldown() (gas: 274143)
[PASS] test_Vault_SAP_3_EarlyUnstakeCooldownEnforced() (gas: 76383)
```

### Regression Testing

All existing SapienVault tests continue to pass:
- 107 tests in `SapienVaultBasicTest` ✅ PASS
- No functionality changes or regressions introduced

## Context: Related Changes

This fix was implemented as part of a larger cleanup where cancellation functions (`cancelUnstake()` and `cancelEarlyUnstake()`) were removed from the contract. The error order fix ensures that audit tests continue to work correctly with the simplified unstaking flow.

### Removed Functions Context
- ❌ `cancelUnstake()` - Removed for UX simplification
- ❌ `cancelEarlyUnstake()` - Removed for UX simplification  
- ✅ Error order fix - Maintains test compatibility

## Benefits

1. **✅ Test Compatibility:** Audit tests now pass as expected
2. **✅ Logical Error Flow:** Error precedence follows user interaction flow
3. **✅ Better UX:** Users get more intuitive error messages
4. **✅ Maintainability:** Code is easier to understand and debug

## Conclusion

This fix resolves a testing issue without any security implications. The reordering of error checks provides a more logical error flow that aligns with user expectations and test requirements. All functionality remains identical, but error reporting is now more intuitive and consistent with the intended user experience.

**Risk Level:** Minimal (cosmetic error order change only)  
**Testing:** Comprehensive (all tests pass)  
**Impact:** Positive (better error UX and test compatibility) 