# ZK-01 Solution: Maximum Stake Cap Bypass via increaseAmount

## Vulnerability Analysis

### Issue Summary
- **Finding ID**: ZK-01  
- **Severity**: High  
- **Status**: Identified - Requires Fix  
- **Component**: `SapienVault._validateIncreaseAmount()`

### Root Cause
The `_validateIncreaseAmount()` function only validates the additional amount against the protocol's maximum stake limit, but fails to check if the combined total (existing stake + additional amount) exceeds the maximum allowed stake amount.

### Current Vulnerable Code
```solidity
function _validateIncreaseAmount(uint256 additionalAmount, UserStake storage userStake) private view {
    if (additionalAmount == 0) revert InvalidAmount();
    if (additionalAmount > maximumStakeAmount) revert StakeAmountTooLarge(); // ❌ Only checks individual amount
    if (userStake.amount == 0) revert NoStakeFound();
    // ❌ Missing: Total stake validation
}
```

### Attack Vector
1. **Setup**: Protocol sets `maximumStakeAmount = 2,500 tokens`
2. **Initial Stake**: User stakes `2,000 tokens` ✅ (valid, under cap)
3. **Exploit**: User calls `increaseAmount(600)` ✅ (600 < 2,500, passes validation)
4. **Result**: Final stake = `2,600 tokens` ❌ (exceeds protocol cap by 100 tokens)

### Impact Assessment

#### **Business Impact**
- **Protocol Invariant Violation**: Undermines fundamental economic design limits
- **Risk Concentration**: Allows dangerous accumulation beyond intended thresholds
- **Fairness Issues**: Creates advantage for exploiters over rule-following users
- **Governance Imbalance**: May concentrate voting power beyond intended limits

#### **Technical Impact**
- **Economic Model Disruption**: Breaks tokenomics assumptions about maximum individual exposure
- **Risk Management Failure**: Bypasses risk controls designed to limit individual positions
- **Systemic Risk**: Could lead to protocol instability if multiple users exploit this

#### **Regulatory/Compliance Risk**
- **Capital Limits**: May violate regulatory requirements for position sizing
- **AML/KYC**: Could circumvent compliance controls tied to stake amounts

### Historical Context
This finding is part of a pattern of validation bypasses in the SapienVault system:
- **SAP-5 (June 2025)**: Missing expiration check when adding to existing stakes
- **Pattern**: Incremental functions lacking comprehensive validation

## Recommended Fix

### Primary Solution
Add total stake validation to prevent cap bypass:

```solidity
function _validateIncreaseAmount(uint256 additionalAmount, UserStake storage userStake) private view {
    if (additionalAmount == 0) revert InvalidAmount();
    if (additionalAmount > maximumStakeAmount) revert StakeAmountTooLarge();
+   if (userStake.amount + additionalAmount > maximumStakeAmount) revert StakeAmountTooLarge();
    if (userStake.amount == 0) revert NoStakeFound();
    
    if (userStake.cooldownStart != 0 || userStake.earlyUnstakeCooldownStart != 0) {
        revert CannotIncreaseStakeInCooldown();
    }
}
```

### Alternative Error Handling
Consider adding a specific error for better UX:
```solidity
error TotalStakeExceedsMaximum(uint256 currentStake, uint256 additionalAmount, uint256 maximum);

// In validation:
if (userStake.amount + additionalAmount > maximumStakeAmount) {
    revert TotalStakeExceedsMaximum(userStake.amount, additionalAmount, maximumStakeAmount);
}
```

## Testing Strategy

### Test Cases Required
1. **Vulnerability Test**: Demonstrate the bypass without fix
2. **Fix Validation**: Confirm the fix prevents the bypass
3. **Edge Cases**: Test boundary conditions at the maximum limit
4. **Regression Test**: Ensure normal operations still work

### Test Implementation
```solidity
function test_ZK01_MaximumStakeCapBypassVulnerability() public {
    // Test the vulnerability exists without the fix
}

function test_ZK01_MaximumStakeCapBypassPrevention() public {
    // Test the fix prevents the bypass
}
```

## Security Recommendations

### Immediate Actions
1. **Apply Fix**: Implement the total stake validation immediately
2. **Deploy**: Update contracts with the fix
3. **Audit**: Review all similar validation functions for similar issues

### Long-term Improvements
1. **Validation Framework**: Create comprehensive validation helpers
2. **Invariant Testing**: Add property-based tests for protocol invariants
3. **Security Reviews**: Systematic review of all incremental functions

### Code Review Checklist
- [ ] All incremental functions validate total results, not just increments
- [ ] Protocol invariants are enforced at all entry points
- [ ] Error messages provide clear feedback to users
- [ ] Edge cases and boundary conditions are properly handled

## Conclusion

ZK-01 represents a significant security vulnerability that allows users to bypass fundamental protocol limits. The fix is straightforward but critical for maintaining protocol integrity. This finding also highlights the need for more systematic validation approaches in incremental operations.

**Priority**: Immediate fix required before any production deployment. 