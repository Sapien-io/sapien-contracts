          _____                    _____                    _____                    _____                    _____                    _____          
         /\    \                  /\    \                  /\    \                  /\    \                  /\    \                  /\    \         
        /::\    \                /::\    \                /::\    \                /::\    \                /::\    \                /::\____\        
       /::::\    \              /::::\    \              /::::\    \               \:::\    \              /::::\    \              /::::|   |        
      /::::::\    \            /::::::\    \            /::::::\    \               \:::\    \            /::::::\    \            /:::::|   |        
     /:::/\:::\    \          /:::/\:::\    \          /:::/\:::\    \               \:::\    \          /:::/\:::\    \          /::::::|   |        
    /:::/__\:::\    \        /:::/__\:::\    \        /:::/__\:::\    \               \:::\    \        /:::/__\:::\    \        /:::/|::|   |        
    \:::\   \:::\    \      /::::\   \:::\    \      /::::\   \:::\    \              /::::\    \      /::::\   \:::\    \      /:::/ |::|   |        
  ___\:::\   \:::\    \    /::::::\   \:::\    \    /::::::\   \:::\    \    ____    /::::::\    \    /::::::\   \:::\    \    /:::/  |::|   | _____  
 /\   \:::\   \:::\    \  /:::/\:::\   \:::\    \  /:::/\:::\   \:::\____\  /\   \  /:::/\:::\    \  /:::/\:::\   \:::\    \  /:::/   |::|   |/\    \ 
/::\   \:::\   \:::\____\/:::/  \:::\   \:::\____\/:::/  \:::\   \:::|    |/::\   \/:::/  \:::\____\/:::/__\:::\   \:::\____\/:: /    |::|   /::\____\
\:::\   \:::\   \::/    /\::/    \:::\  /:::/    /\::/    \:::\  /:::|____|\:::\  /:::/    \::/    /\:::\   \:::\   \::/    /\::/    /|::|  /:::/    /
 \:::\   \:::\   \/____/  \/____/ \:::\/:::/    /  \/_____/\:::\/:::/    /  \:::\/:::/    / \/____/  \:::\   \:::\   \/____/  \/____/ |::| /:::/    / 
  \:::\   \:::\    \               \::::::/    /            \::::::/    /    \::::::/    /            \:::\   \:::\    \              |::|/:::/    /  
   \:::\   \:::\____\               \::::/    /              \::::/    /      \::::/____/              \:::\   \:::\____\             |::::::/    /   
    \:::\  /:::/    /               /:::/    /                \::/____/        \:::\    \               \:::\   \::/    /             |:::::/    /    
     \:::\/:::/    /               /:::/    /                  ~~               \:::\    \               \:::\   \/____/              |::::/    /     
      \::::::/    /               /:::/    /                                     \:::\    \               \:::\    \                  /:::/    /      
       \::::/    /               /:::/    /                                       \:::\____\               \:::\____\                /:::/    /       
        \::/    /                \::/    /                                         \::/    /                \::/    /                \::/    /        
         \/____/                  \/____/                                           \/____/                  \/____/                  \/____/         
                                                                                                                                                      

A suite of upgradeable smart contracts for managing token distribution, staking, and rewards in the Sapien ecosystem.

## Overview

The Sapien smart contracts consist of four main components:

1. **SapTestToken (ERC20)**: An upgradeable ERC20 token with sophisticated vesting schedules for different allocation types (investors, team, rewards, etc.).
2. **SapienStaking**: Enables users to stake tokens with different lock-up periods (1/3/6/12 months) and earn corresponding multipliers.
3. **SapienRewards**: Manages reward token distribution using EIP-712 signatures for secure claiming.
4. **Rewards**: A base contract for reward token management and distribution.

## Key Features

### SapTestToken
- Implements vesting schedules for different token allocations
- Controlled by a Gnosis Safe multisig
- Supports pausing and UUPS upgradeability
- Total supply: 1 billion tokens distributed across:
  - Investors (30%)
  - Team & Advisors (20%)
  - Labeling Rewards (15%)
  - Airdrops (15%)
  - Community Treasury (10%)
  - Staking Incentives (5%)
  - Liquidity Incentives (5%)

### SapienStaking
- Four staking periods with corresponding multipliers:
  - 30 days: up to 1.05x
  - 90 days: up to 1.10x
  - 180 days: up to 1.25x
  - 365 days: up to 1.50x
- Granular multiplier calculation based on stake amount
- 2-day cooldown period for unstaking
- Instant unstake option with 20% penalty
- EIP-712 signature verification for all actions

### Rewards System
- Secure reward distribution using EIP-712 signatures
- Prevention of double-claiming through order ID tracking
- Upgradeable architecture with pause functionality
- Owner controls for token deposits and withdrawals

## Deployment

1. Deploy implementation contracts
2. Deploy proxy contracts using UUPS pattern
3. Initialize contracts with required parameters:
```solidity
// SapTestToken
function initialize(address _gnosisSafeAddress, uint256 _totalSupply)

// SapienStaking
function initialize(IERC20 sapienToken_, address sapienAddress_)

// SapienRewards
function initialize(address _authorizedSigner_)
```

## Contract Interaction

### Staking
```solidity
// Stake tokens
function stake(
    uint256 amount,
    uint256 lockUpPeriod,
    bytes32 orderId,
    bytes memory signature
)

// Initiate unstaking (starts cooldown)
function initiateUnstake(
    uint256 amount,
    bytes32 newOrderId,
    bytes32 stakeOrderId,
    bytes memory signature
)

// Complete unstake after cooldown
function unstake(
    uint256 amount,
    bytes32 newOrderId,
    bytes32 stakeOrderId,
    bytes memory signature
)

// Instant unstake with penalty
function instantUnstake(
    uint256 amount,
    bytes32 newOrderId,
    bytes32 stakeOrderId,
    bytes memory signature
)
```

### Rewards
```solidity
// Claim rewards
function claimReward(
    uint256 rewardAmount,
    bytes32 orderId,
    bytes memory signature
)
```

### Token Management
```solidity
// Release vested tokens
function releaseTokens(AllocationType allocationType)

// Update vesting schedule
function updateVestingSchedule(
    AllocationType allocationType,
    uint256 cliff,
    uint256 start,
    uint256 duration,
    uint256 amount,
    address safe
)
```

## Security Features

- Reentrancy protection on all sensitive functions
- Two-step ownership transfers
- Pausable functionality for emergency stops
- EIP-712 signatures for action verification
- Upgradeable architecture using UUPS pattern
- Comprehensive access controls
- Order ID tracking to prevent double-spending

## Development

### Prerequisites
- Node.js 14+
- Hardhat
- OpenZeppelin Contracts

### Testing
```shell
npx hardhat test
REPORT_GAS=true npx hardhat test
```

### Deployment
```shell
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.ts
```

## License

MIT 
