# Sapien Utils Library

This directory contains utility libraries used across the Sapien smart contract ecosystem.

## Libraries

### SafeCast.sol
Provides safe casting functions for converting `uint256` to smaller unsigned integer types with overflow protection.

**Functions:**
- `toUint128(uint256)` - Safely cast to uint128
- `toUint64(uint256)` - Safely cast to uint64  
- `toUint32(uint256)` - Safely cast to uint32
- `toUint16(uint256)` - Safely cast to uint16
- `toUint8(uint256)` - Safely cast to uint8

**Usage:**
```solidity
import {SafeCast} from "src/utils/SafeCast.sol";

contract MyContract {
    using SafeCast for uint256;
    
    function example() external {
        uint256 largeNumber = 1000;
        uint128 smallNumber = largeNumber.toUint128(); // Safe conversion
    }
}
```

### Constants.sol
Centralizes common constants used across Sapien contracts for better maintainability and consistency.

**Categories:**
- **Time Constants**: Standard time periods (seconds, minutes, hours, days, years)
- **Lockup Periods**: Standard staking lockup durations (30, 90, 180, 365 days)
- **Precision**: Basis points and calculation precision constants
- **Staking Constants**: Multipliers, token decimals, minimum values
- **Security Constants**: Timelock periods, cooldown periods, penalty rates

**Usage:**
```solidity
import {Constants} from "src/utils/Constants.sol";

contract MyContract {
    uint256 private constant TIMELOCK = Constants.DEFAULT_TIMELOCK;
    uint256 private constant MIN_STAKE = Constants.MINIMUM_STAKE_AMOUNT;
}
```

## Benefits

1. **Code Reusability**: Shared utilities across multiple contracts
2. **Gas Optimization**: Optimized storage packing with safe casting
3. **Maintainability**: Centralized constants for easy updates
4. **Security**: Built-in overflow protection for type conversions
5. **Consistency**: Standardized values across the entire protocol

## Integration

All Sapien contracts have been updated to use these utilities:
- `StakingVault.sol` - Uses both SafeCast and Constants
- `RewardsDistributor.sol` - Uses Constants for timelock and precision
- `SapienRewards.sol` - Uses Constants for timelock period

This refactoring reduces code duplication, improves maintainability, and provides a solid foundation for future contract development. 