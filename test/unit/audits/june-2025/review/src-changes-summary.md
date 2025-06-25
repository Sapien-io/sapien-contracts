# Source Code Changes Summary

## Overview
This document summarizes the changes made to the `src/` folder between commit `b8a6d92f275de744ae7b2639a7a35d5d4f5b83c7` and the current state.

## Files Changed
- **4 files** were modified
- **134 insertions** and **264 deletions** (net reduction of 130 lines)

## Major Changes

### 1. Multiplier.sol - **REMOVED**
- The entire `Multiplier.sol` library file was deleted (28 lines removed)
- This library contained:
  - Constants for basis points, base multiplier, max tokens, max lockup, and max bonus
  - A `calculateMultiplier()` function for calculating staking multipliers

### 2. SapienVault.sol - **MAJOR REFACTOR**
- **Large refactoring** with 330 lines of changes
- The multiplier calculation functionality was moved from the separate library into this contract
- Key improvements made based on audit findings:
  - Removed dependency on external Multiplier library
  - Improved precision handling in multiplier calculations
  - Fixed cooldown-related bugs and mutual exclusion issues
  - Enhanced stake increase restrictions during cooldown periods
  - Removed redundant weight lockup period calculations

### 3. ISapienVault.sol - **MINOR UPDATES**
- **18 lines changed** in the interface
- Updated to reflect the changes in the main contract

### 4. Constants.sol - **UPDATES**
- **22 lines changed**
- Updated constants to support the new multiplier implementation
- Consolidated values that were previously in the Multiplier library

## Key Architectural Changes

### Multiplier Logic Consolidation
- **Before**: Multiplier logic was in a separate `Multiplier.sol` library
- **After**: Multiplier functionality is now directly integrated into `SapienVault.sol`
- **Benefit**: Better precision handling and reduced external dependencies

### Audit-Driven Improvements
Based on the commit messages, these changes address several audit findings:
1. **Precision Loss**: Improved multiplier calculations to minimize precision loss
2. **Cooldown Bugs**: Fixed issues with early cooldown amount handling
3. **Mutual Exclusion**: Ensured proper exclusion between different cooldown paths
4. **Validation**: Enhanced minimum unstake amount validation
5. **State Management**: Improved weight and lockup period calculations

## Impact
- **Code Quality**: Simplified architecture by eliminating external library dependency
- **Security**: Fixed multiple audit-identified issues related to cooldowns and state management
- **Maintainability**: Consolidated related functionality into a single contract
- **Precision**: Improved mathematical calculations to reduce rounding errors 