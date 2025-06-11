# SAP-5 Stake Bypass Test Suite

## Overview

This directory contains the comprehensive test suite for **SAP-5: Missing Expiration Check when Adding to Existing Stake** vulnerability and its fix.

## Files

- `JuneAudit_SAP_5.t.sol` - Main test file with comprehensive SAP-5 vulnerability tests
- `STAKE_BYPASS.md` - Detailed documentation of the vulnerability and fix
- `README.md` - This file

## Test Coverage

### Core Vulnerability Tests

1. **`test_SAP5_Vulnerability_MissingExpirationCheck()`**
   - Demonstrates the original vulnerability where adding to expired stakes bypassed lockup periods
   - Shows that the fix properly prevents timelock bypass exploitation
   - Verifies full 365-day lockup is maintained after fix

2. **`test_SAP5_Fix_IncreaseAmountVulnerability()`**
   - Tests the fix specifically for the `increaseAmount()` function
   - Confirms that `increaseAmount()` properly resets weighted start time for expired stakes
   - Validates that expired stakes are properly relocked

3. **`test_SAP5_Fix_ValidationDemo()`**
   - Demonstrates proper behavior with the SAP-5 fix implementation
   - Shows recommended behavior when adding to expired stakes
   - Confirms security enforcement while maintaining functionality

### Edge Case Tests

4. **`test_SAP5_EdgeCase_ExactExpirationBoundary()`**
   - Tests boundary condition where stake expires exactly at lockup period
   - Ensures fix works correctly at exact expiration timestamp
   - Validates proper behavior at edge boundaries

5. **`test_SAP5_NormalWeightedCalculations_StillWork()`**
   - Verifies that normal weighted calculations remain functional for non-expired stakes
   - Ensures the fix doesn't break legitimate weighted averaging
   - Confirms backward compatibility for normal operations

## Test Results Summary

```
✓ test_SAP5_EdgeCase_ExactExpirationBoundary() (gas: 250837)
✓ test_SAP5_Fix_IncreaseAmountVulnerability() (gas: 269430)
✓ test_SAP5_Fix_ValidationDemo() (gas: 267644)
✓ test_SAP5_NormalWeightedCalculations_StillWork() (gas: 255472)
✓ test_SAP5_Vulnerability_MissingExpirationCheck() (gas: 277554)

Suite result: ok. 5 passed; 0 failed; 0 skipped
```

## Running the Tests

### Run all SAP-5 tests:
```bash
forge test --match-path "test/unit/june-audit-findings/sap-5-stake-bypass/JuneAudit_SAP_5.t.sol" -vv
```

### Run specific test:
```bash
forge test --match-test "test_SAP5_Vulnerability_MissingExpirationCheck" -vv
```

### Run with detailed output:
```bash
forge test --match-path "test/unit/june-audit-findings/sap-5-stake-bypass/JuneAudit_SAP_5.t.sol" -vvv
```

## Vulnerability Summary

**Before Fix**: 
- Users could add tokens to expired stakes
- Weighted calculations resulted in reduced effective lockup periods
- Example: 365-day intended lockup → 363-day actual lockup

**After Fix**:
- System detects expired stakes and resets weighted start time
- Full intended lockup period is applied
- Example: 365-day intended lockup → 365-day actual lockup

## Security Verification

The test suite validates:
- [x] Vulnerability is prevented in `stake()` function
- [x] Vulnerability is prevented in `increaseAmount()` function  
- [x] Normal weighted calculations preserved for active stakes
- [x] Edge cases handled correctly
- [x] No breaking changes to existing functionality
- [x] Gas efficiency maintained

## Related Files

- **Core Fix**: `src/SapienVault.sol` (lines 689-720, 390-450)
- **Documentation**: `test/unit/june-audit-findings/sap-5-stake-bypass/STAKE_BYPASS.md`
- **Original Issue**: SAP-5 from June 2024 Security Audit 