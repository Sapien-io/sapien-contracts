# SAP-5 Security Fix: Missing Expiration Check when Adding to Existing Stake

## Vulnerability Summary

**Issue**: SAP-5 - Missing Expiration Check when Adding to Existing Stake  
**Severity**: Medium  
**Status**: ✅ Fixed  
**File(s) affected**: `src/SapienVault.sol`

## Vulnerability Description

The `stake()` and `increaseAmount()` functions allowed users to add tokens to stakes without validating that the initial stake's lockup period had not ended. This enabled a timelock bypass vulnerability where:

1. **Users could exploit weighted averaging**: When adding tokens to an expired stake, the weighted start time calculation would average the old expired timestamp with the current timestamp
2. **Reduced effective lockup periods**: This resulted in `newWeightedStartTime + effectiveLockUpPeriod < block.timestamp`, meaning stakes became immediately unlocked
3. **Multiplier exploitation**: Users could benefit from increased multipliers while being able to unlock their tokens at any time

## Technical Root Cause

In the original implementation:

```solidity
// In _calculateWeightedValues() function
uint256 timeElapsed = block.timestamp - uint256(userStake.weightedStartTime);
uint256 remainingExistingLockup = uint256(userStake.effectiveLockUpPeriod) > timeElapsed
    ? uint256(userStake.effectiveLockUpPeriod) - timeElapsed
    : 0; // ← When stake expired, this became 0
```

When `remainingExistingLockup` was 0 (expired stake), the weighted lockup calculation would still proceed, allowing users to benefit from reduced effective lockup periods.

## Proof of Concept

### Before Fix:
1. User stakes 5,000 SAPIEN for 30 days
2. Wait 31 days (stake expires)
3. User adds 100,000 SAPIEN for 365 days to the expired stake
4. **Result**: Effective lockup becomes ~363 days instead of 365 days
5. **Impact**: User gets high multiplier but reduced lockup commitment

### After Fix:
1. User stakes 5,000 SAPIEN for 30 days  
2. Wait 31 days (stake expires)
3. User adds 100,000 SAPIEN for 365 days to the expired stake
4. **Result**: Weighted start time resets to current timestamp, full 365-day lockup applied
5. **Impact**: No exploitation possible, proper lockup enforced

## Implemented Fix

### Changes Made

1. **Modified `_processCombineStake()` function**:
   - Added expiration check using `_isUnlocked(userStake)`
   - If existing stake is expired, reset `weightedStartTime` to current timestamp
   - Apply full new lockup period without weighted averaging

2. **Modified `increaseAmount()` function**:
   - Added same expiration check logic
   - Reset weighted start time for expired stakes
   - Maintain security while preserving functionality

### Code Changes

```solidity
// SAP-5 FIX: Check if existing stake has expired
bool isExistingStakeExpired = _isUnlocked(userStake);

if (isExistingStakeExpired) {
    // If existing stake is expired, reset weighted start time to current timestamp
    // This prevents users from benefiting from reduced lockup periods due to weighted averaging
    newValues.weightedStartTime = block.timestamp;
    newValues.effectiveLockup = lockUpPeriod;
    
    // Ensure lockup period doesn't exceed maximum
    if (newValues.effectiveLockup > Const.LOCKUP_365_DAYS) {
        newValues.effectiveLockup = Const.LOCKUP_365_DAYS;
    }
} else {
    // Calculate new weighted values normally for non-expired stakes
    newValues = _calculateWeightedValues(userStake, amount, lockUpPeriod, newTotalAmount);
}
```

## Test Coverage

### Vulnerability Tests
- `test_SAP5_Vulnerability_MissingExpirationCheck()`: Demonstrates the original vulnerability
- `test_SAP5_Fix_ValidationDemo()`: Shows the fix working for `stake()` function  
- `test_SAP5_Fix_IncreaseAmountVulnerability()`: Verifies fix for `increaseAmount()` function

### Test Results
- **Before Fix**: 365-day lockup → 363-day effective lockup (2-day reduction)
- **After Fix**: 365-day lockup → 365-day effective lockup (no reduction)

## Alternative Solutions Considered

### Option 1: Reject Operations on Expired Stakes
```solidity
if (_isUnlocked(userStake)) {
    revert CannotAddToExpiredStake();
}
```
**Pros**: Simple, clear rejection of problematic operations  
**Cons**: Poor user experience, requires users to unstake before re-staking

### Option 2: Reset Weighted Start Time (Implemented)
```solidity
if (isExistingStakeExpired) {
    newValues.weightedStartTime = block.timestamp;
    newValues.effectiveLockup = lockUpPeriod;
}
```
**Pros**: Maintains functionality while preventing exploitation  
**Cons**: Slightly more complex logic

## Security Considerations

1. **No Breaking Changes**: Existing functionality preserved for non-expired stakes
2. **Backward Compatibility**: Fix doesn't affect normal staking operations
3. **Conservative Approach**: When in doubt, applies stricter lockup rules
4. **Consistent Behavior**: Both `stake()` and `increaseAmount()` handle expiration identically

## Gas Impact

- **Minimal overhead**: Added one `_isUnlocked()` check per operation
- **No significant gas increase**: Logic branching replaces complex weighted calculations for expired stakes
- **Overall gas reduction**: Simpler logic path for expired stakes

## Conclusion

The SAP-5 vulnerability has been successfully fixed by implementing expiration checks in both the `stake()` and `increaseAmount()` functions. The fix:

- ✅ Prevents timelock bypass exploitation
- ✅ Maintains backward compatibility  
- ✅ Preserves user experience for legitimate operations
- ✅ Applies conservative security approach
- ✅ Includes comprehensive test coverage

The implementation follows the security principle of "fail secure" - when dealing with expired stakes, the system applies the strictest possible lockup rules to prevent any potential exploitation. 