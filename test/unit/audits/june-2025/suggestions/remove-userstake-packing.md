# Gas Cost Comparison: Packed vs Unpacked UserStake

`commit 062146c06c82ba1f17c53bfa855d31389959b20f (HEAD -> audit/june+remove-variable-packing-test)`

## Deployment Costs

| Metric | Packed (Before) | Unpacked (After) | Difference | % Change |
|--------|----------------|------------------|------------|----------|
| Deployment Cost | 2,944,552 | 2,419,047 | -525,505 | -17.8% |
| Deployment Size | 13,399 | 10,968 | -2,431 | -18.1% |

*Note: Deployment costs decreased due to removal of SafeCast operations, despite larger storage requirements*

## Function Gas Costs (Average)

| Function | Packed (Before) | Unpacked (After) | Difference | % Change |
|----------|----------------|------------------|------------|----------|
| **Core Operations** |
| `stake` | 120,714 | 171,906 | +51,192 | **+42.4%** |
| `increaseAmount` | 46,991 | 52,596 | +5,605 | **+11.9%** |
| `increaseLockup` | 27,187 | 36,457 | +9,270 | **+34.1%** |
| `initiateUnstake` | 21,854 | 57,930 | +36,076 | **+165.1%** |
| `unstake` | 41,955 | 55,947 | +13,992 | **+33.3%** |
| `earlyUnstake` | 47,303 | 56,272 | +8,969 | **+19.0%** |
| **View Functions** |
| `getUserStakingSummary` | 11,730 | 23,417 | +11,687 | **+99.6%** |
| `getTotalStaked` | 2,596 | 2,578 | -18 | **-0.7%** |
| `getTotalInCooldown` | 7,307 | 17,657 | +10,350 | **+141.7%** |
| `getTotalLocked` | 7,456 | 17,790 | +10,334 | **+138.6%** |
| `getTotalUnlocked` | 7,572 | 17,854 | +10,282 | **+135.8%** |
| `getTotalReadyForUnstake` | 7,529 | 17,864 | +10,335 | **+137.3%** |
| `hasActiveStake` | 2,603 | 2,586 | -17 | **-0.7%** |
| **Admin Functions** |
| `processQAPenalty` | 69,666 | 75,527 | +5,861 | **+8.4%** |

## Key Insights

### 📈 Most Impacted Operations
1. **`initiateUnstake`**: +165.1% (+36,076 gas)
2. **`getTotalInCooldown`**: +141.7% (+10,350 gas)  
3. **`getTotalLocked`**: +138.6% (+10,334 gas)
4. **`getUserStakingSummary`**: +99.6% (+11,687 gas)

### 💰 Gas Cost Impact Summary
- **High-frequency operations** (stake, view functions): **+42% to +165%** increase
- **State-reading functions**: **+136% to +142%** increase (due to reading multiple uint256 slots vs packed data)
- **Simple getters**: Minimal impact (-0.7% to +8.4%)

### 🎯 Trade-offs Analysis

**Benefits of Removing Packing:**
- ✅ **Simpler code**: No SafeCast operations needed
- ✅ **Lower deployment cost**: -17.8% (-525,505 gas)
- ✅ **Reduced complexity**: Easier to audit and maintain
- ✅ **No overflow concerns**: uint256 eliminates casting risks

**Costs of Removing Packing:**
- ❌ **Higher runtime costs**: +8% to +165% for most operations
- ❌ **More storage slots**: 8 slots vs 3 slots per user (167% increase)
- ❌ **Higher view function costs**: Especially impactful for frontend integrations

### 💡 Recommendation
The **165% gas increase** for `initiateUnstake` and **~140% increase** for view functions represent significant ongoing costs for users. While the code is simpler without packing, the runtime gas penalty may outweigh the benefits for a production system with high usage.
