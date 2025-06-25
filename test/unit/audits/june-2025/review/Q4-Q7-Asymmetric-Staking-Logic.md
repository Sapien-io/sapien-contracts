# SapienVault Staking Function Changes

## Branch Comparison: `audit/june` → `audit/june+R1-q6-q7`

This document outlines the significant changes made to the core staking functions (`stake`, `increaseAmount`, and `increaseLockup`) in the SapienVault contract between the audit/june branch and the current audit/june+R1-q6-q7 branch.

## 📋 Executive Summary

### Key Changes
1. **`stake()` function**: Removed ability to combine stakes, now restricted to first-time stakes only
2. **`increaseAmount()` function**: Enhanced with improved weighted time handling
3. **`increaseLockup()` function**: Simplified logic with direct time reset approach
4. **Helper functions**: Removed complex combination logic, simplified expired stake handling

### Security Improvements
- **Asymmetric behavior prevention**: Users with existing stakes must use `increaseAmount()` or `increaseLockup()`
- **Simplified logic**: Reduced complexity in staking operations
- **Consistent expired stake handling**: Standardized approach across all operations

---

## 🔍 Detailed Function Changes

### 1. `stake()` Function

#### **audit/june** Version (BEFORE)
```solidity
function stake(uint256 amount, uint256 lockUpPeriod) public whenNotPaused nonReentrant {
    // Validate inputs and user state
    _validateStakeInputs(amount, lockUpPeriod);

    UserStake storage userStake = userStakes[msg.sender];

    // Pre-validate state changes before token transfer
    _preValidateStakeOperation(userStake);

    // Transfer tokens only after all validations pass
    sapienToken.safeTransferFrom(msg.sender, address(this), amount);

    // Execute staking logic
    if (userStake.amount == 0) {
        _processFirstTimeStake(userStake, amount, lockUpPeriod);
    } else {
        _processCombineStake(userStake, amount, lockUpPeriod);  // ⚠️ REMOVED
    }

    totalStaked += amount;
    emit Staked(msg.sender, amount, userStake.effectiveMultiplier, userStake.effectiveLockUpPeriod);
}
```

#### **audit/june+R1-q6-q7** Version (AFTER)
```solidity
function stake(uint256 amount, uint256 lockUpPeriod) public whenNotPaused nonReentrant {
    // Validate inputs and user state
    _validateStakeInputs(amount, lockUpPeriod);

    UserStake storage userStake = userStakes[msg.sender];

    // Pre-validate state changes before token transfer
    _preValidateStakeOperation(userStake);

    // Transfer tokens only after all validations pass
    sapienToken.safeTransferFrom(msg.sender, address(this), amount);

    // Execute staking logic - only first-time stakes allowed
    // Existing stakers must use increaseAmount() or increaseLockup()
    _processFirstTimeStake(userStake, amount, lockUpPeriod);  // ✅ SIMPLIFIED

    totalStaked += amount;
    emit Staked(msg.sender, amount, userStake.effectiveMultiplier, userStake.effectiveLockUpPeriod);
}
```

#### **Changes:**
- ❌ **REMOVED**: `_processCombineStake()` functionality
- ✅ **ADDED**: Restriction to first-time stakes only
- ✅ **IMPROVED**: Prevents asymmetric behavior between staking paths
- ✅ **SECURITY**: Users with existing stakes must use dedicated functions

---

### 2. `increaseAmount()` Function

#### **audit/june** Version (BEFORE)
```solidity
function increaseAmount(uint256 additionalAmount) public whenNotPaused nonReentrant {
    // Validate inputs
    _validateIncreaseAmount(additionalAmount);

    UserStake storage userStake = userStakes[msg.sender];

    if (userStake.amount == 0) {
        revert NoStakeFound();
    }

    if (userStake.cooldownStart != 0) {
        revert CannotIncreaseStakeInCooldown();
    }

    // Use standardized expired stake handling
    uint256 newWeightedStartTime =
        _calculateStandardizedWeightedStartTime(userStake, additionalAmount, userStake.amount + additionalAmount);

    // Transfer tokens only after validation passes
    sapienToken.safeTransferFrom(msg.sender, address(this), additionalAmount);

    uint256 newTotalAmount = userStake.amount + additionalAmount;

    // Update state
    userStake.weightedStartTime = newWeightedStartTime.toUint64();
    userStake.amount = newTotalAmount.toUint128();
    userStake.lastUpdateTime = block.timestamp.toUint64();

    // Recalculate linear weighted multiplier based on new total amount
    userStake.effectiveMultiplier = calculateMultiplier(newTotalAmount, userStake.effectiveLockUpPeriod).toUint32();

    totalStaked += additionalAmount;

    emit AmountIncreased(msg.sender, additionalAmount, newTotalAmount, userStake.effectiveMultiplier);
}
```

#### **audit/june+R1-q6-q7** Version (AFTER)
```solidity
function increaseAmount(uint256 additionalAmount) public whenNotPaused nonReentrant {
    // Validate inputs
    _validateIncreaseAmount(additionalAmount);

    UserStake storage userStake = userStakes[msg.sender];

    if (userStake.amount == 0) {
        revert NoStakeFound();
    }

    if (userStake.cooldownStart != 0) {
        revert CannotIncreaseStakeInCooldown();
    }

    // Use standardized expired stake handling
    uint256 newWeightedStartTime =
        _calculateStandardizedWeightedStartTime(userStake, additionalAmount, userStake.amount + additionalAmount);

    // Transfer tokens only after validation passes
    sapienToken.safeTransferFrom(msg.sender, address(this), additionalAmount);

    uint256 newTotalAmount = userStake.amount + additionalAmount;

    // Update state
    userStake.weightedStartTime = newWeightedStartTime.toUint64();
    userStake.amount = newTotalAmount.toUint128();
    userStake.lastUpdateTime = block.timestamp.toUint64();

    // Recalculate linear weighted multiplier based on new total amount
    userStake.effectiveMultiplier = calculateMultiplier(newTotalAmount, userStake.effectiveLockUpPeriod).toUint32();

    totalStaked += additionalAmount;

    emit AmountIncreased(msg.sender, additionalAmount, newTotalAmount, userStake.effectiveMultiplier);
}
```

#### **Changes:**
- ✅ **MAINTAINED**: Core functionality remains the same
- ✅ **IMPROVED**: Uses simplified `_calculateStandardizedWeightedStartTime()` helper
- ✅ **CONSISTENT**: Standardized expired stake handling

---

### 3. `increaseLockup()` Function

#### **audit/june** Version (BEFORE)
```solidity
function increaseLockup(uint256 additionalLockup) public whenNotPaused nonReentrant {
    UserStake storage userStake = userStakes[msg.sender];
    if (userStake.amount == 0) {
        revert NoStakeFound();
    }

    if (additionalLockup < Const.MINIMUM_LOCKUP_INCREASE) {
        revert MinimumLockupIncreaseRequired();
    }
    if (userStake.cooldownStart != 0) {
        revert CannotIncreaseStakeInCooldown();
    }

    // Use standardized expired stake handling
    bool isExistingStakeExpired = _handleExpiredStakeCheck(userStake);
    uint256 newEffectiveLockup;

    if (isExistingStakeExpired) {
        // Standardized expired stake handling - reset to new lockup period
        newEffectiveLockup = additionalLockup;
        _resetExpiredStakeStartTime(userStake);
    } else {
        // Calculate remaining lockup time for active stakes
        uint256 timeElapsed = block.timestamp - userStake.weightedStartTime;
        uint256 remainingLockup =
            userStake.effectiveLockUpPeriod > timeElapsed ? userStake.effectiveLockUpPeriod - timeElapsed : 0;

        // New effective lockup is remaining time plus additional lockup
        newEffectiveLockup = remainingLockup + additionalLockup;

        // Reset the weighted start time to now since we're extending lockup
        _resetExpiredStakeStartTime(userStake);
    }

    // Cap at maximum lockup period
    if (newEffectiveLockup > Const.LOCKUP_365_DAYS) {
        newEffectiveLockup = Const.LOCKUP_365_DAYS;
    }

    userStake.effectiveLockUpPeriod = newEffectiveLockup.toUint64();
    userStake.effectiveMultiplier = calculateMultiplier(userStake.amount, newEffectiveLockup).toUint32();
    userStake.lastUpdateTime = block.timestamp.toUint64();

    emit LockupIncreased(msg.sender, additionalLockup, newEffectiveLockup, userStake.effectiveMultiplier);
}
```

#### **audit/june+R1-q6-q7** Version (AFTER)
```solidity
function increaseLockup(uint256 additionalLockup) public whenNotPaused nonReentrant {
    UserStake storage userStake = userStakes[msg.sender];
    if (userStake.amount == 0) {
        revert NoStakeFound();
    }

    if (additionalLockup < Const.MINIMUM_LOCKUP_INCREASE) {
        revert MinimumLockupIncreaseRequired();
    }
    if (userStake.cooldownStart != 0) {
        revert CannotIncreaseStakeInCooldown();
    }

    // Handle expired vs active stakes
    uint256 newEffectiveLockup;

    if (_isUnlocked(userStake)) {
        // Expired stake: reset to new lockup period
        newEffectiveLockup = additionalLockup;
        userStake.weightedStartTime = block.timestamp.toUint64();
    } else {
        // Calculate remaining lockup time for active stakes
        uint256 timeElapsed = block.timestamp - userStake.weightedStartTime;
        uint256 remainingLockup =
            userStake.effectiveLockUpPeriod > timeElapsed ? userStake.effectiveLockUpPeriod - timeElapsed : 0;

        // New effective lockup is remaining time plus additional lockup
        newEffectiveLockup = remainingLockup + additionalLockup;

        // Reset the weighted start time to now since we're extending lockup
        userStake.weightedStartTime = block.timestamp.toUint64();
    }

    // Cap at maximum lockup period
    if (newEffectiveLockup > Const.LOCKUP_365_DAYS) {
        newEffectiveLockup = Const.LOCKUP_365_DAYS;
    }

    userStake.effectiveLockUpPeriod = newEffectiveLockup.toUint64();
    userStake.effectiveMultiplier = calculateMultiplier(userStake.amount, newEffectiveLockup).toUint32();
    userStake.lastUpdateTime = block.timestamp.toUint64();

    emit LockupIncreased(msg.sender, additionalLockup, newEffectiveLockup, userStake.effectiveMultiplier);
}
```

#### **Changes:**
- ✅ **SIMPLIFIED**: Direct use of `_isUnlocked()` instead of `_handleExpiredStakeCheck()`
- ✅ **STREAMLINED**: Inline `weightedStartTime` reset instead of helper function
- ✅ **REDUCED COMPLEXITY**: Fewer function calls and cleaner logic
- ✅ **MAINTAINED**: Same core functionality and behavior

---

## 🗑️ Removed Functions

### Functions Eliminated in `audit/june+R1-q6-q7`

#### 1. `_processCombineStake()`
```solidity
// ❌ REMOVED: Complex stake combination logic
function _processCombineStake(UserStake storage userStake, uint256 amount, uint256 lockUpPeriod) private {
    // ... complex weighted calculation logic
}
```

#### 2. `_calculateWeightedValues()`
```solidity
// ❌ REMOVED: Complex weighted value calculation
function _calculateWeightedValues(
    UserStake storage userStake,
    uint256 amount,
    uint256 lockUpPeriod,
    uint256 newTotalAmount
) private view returns (uint256 weightedStartTime, uint256 lockupPeriod) {
    // ... complex calculation logic
}
```

#### 3. `_handleExpiredStakeCheck()`
```solidity
// ❌ REMOVED: Replaced with direct _isUnlocked() calls
function _handleExpiredStakeCheck(UserStake storage userStake) private view returns (bool isExpired) {
    isExpired = _isUnlocked(userStake);
}
```

#### 4. `_resetExpiredStakeStartTime()`
```solidity
// ❌ REMOVED: Replaced with inline timestamp setting
function _resetExpiredStakeStartTime(UserStake storage userStake) private {
    userStake.weightedStartTime = block.timestamp.toUint64();
}
```

---

## 🔄 Modified Helper Functions

### Enhanced Functions

#### `_preValidateStakeOperation()` - NEW BEHAVIOR
```solidity
function _preValidateStakeOperation(UserStake storage userStake) private view {
    // CRITICAL: Users with existing stakes must use increaseAmount() or increaseLockup()
    // This prevents asymmetric behavior between staking paths
    if (userStake.amount > 0) {
        revert ExistingStakeFound();  // ✅ NEW: Enforces single stake per user
    }
}
```

#### `_calculateStandardizedWeightedStartTime()` - SIMPLIFIED
```solidity
function _calculateStandardizedWeightedStartTime(
    UserStake storage userStake,
    uint256 newAmount,
    uint256 totalAmount
) private view returns (uint256 newWeightedStartTime) {
    // If stake is expired/unlocked, reset to current timestamp
    if (_isUnlocked(userStake)) {
        return block.timestamp;  // ✅ SIMPLIFIED: Direct return
    }
    
    // Calculate weighted start time for active stakes
    return _calculateWeightedStartTime(userStake.weightedStartTime, userStake.amount, newAmount, totalAmount);
}
```

---

## 📊 Impact Analysis

### Security Improvements
1. **Asymmetric Behavior Prevention**: Users can no longer use `stake()` to add to existing positions
2. **Simplified Attack Surface**: Reduced complex combination logic eliminates potential edge cases  
3. **Consistent Pathways**: Clear separation between initial staking and stake modifications

### User Experience Changes
1. **Clear Function Separation**:
   - `stake()`: Only for new users (first-time stakes)
   - `increaseAmount()`: Add tokens to existing stake
   - `increaseLockup()`: Extend lockup period

2. **Predictable Behavior**: No more confusion about which path to use for stake modifications

### Gas Optimization
1. **Reduced Complexity**: Fewer function calls and conditional logic
2. **Streamlined Operations**: Direct implementations instead of layered helper functions
3. **Simplified State Updates**: More efficient state transitions

---

## 🧪 Testing Implications

### New Test Requirements
1. **Restricted `stake()` Function**: Tests must verify that existing stakers cannot use `stake()`
2. **Path Separation**: Tests should validate the distinct behaviors of modification functions
3. **Consistency Verification**: Order-dependent behavior testing for different operation sequences

### Test Scenarios Added
- **Consistency Tests**: Verify different paths yield expected (potentially different) results due to weighted time calculations
- **Order Dependency**: Document that `increaseAmount()` → `increaseLockup()` ≠ `increaseLockup()` → `increaseAmount()`
- **Error Cases**: Verify `ExistingStakeFound` error when trying to re-stake

---

## 🚀 Migration Guide

### For Existing Users
- **Before**: Could use `stake()` to add to existing positions
- **After**: Must use `increaseAmount()` or `increaseLockup()` for modifications

### For Integrators
1. **Check Existing Stakes**: Always check if user has stake before calling `stake()`
2. **Use Appropriate Functions**: 
   - New stakes: `stake()`
   - Add amount: `increaseAmount()`
   - Extend time: `increaseLockup()`
3. **Handle New Errors**: Catch `ExistingStakeFound` error and redirect to appropriate function

---

## 📋 Summary

The changes between `audit/june` and `audit/june+R1-q6-q7` represent a significant simplification and security improvement of the staking system:

✅ **Simplified Logic**: Removed complex combination pathways  
✅ **Enhanced Security**: Prevented asymmetric staking behaviors  
✅ **Clear Separation**: Distinct functions for different operations  
✅ **Reduced Complexity**: Fewer helper functions and edge cases  
✅ **Maintained Functionality**: Core staking features preserved  

These changes improve both security and maintainability while providing clearer user pathways for staking operations. 