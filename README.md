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

## Deployment Guide

This project includes deployment scripts for each contract individually or deploying all contracts at once. The scripts handle contract deployment in the correct order and save deployment information for future reference.

### Prerequisites

- Node.js 14+
- Hardhat installed
- Configuration file (optional)

### Configuration

Create a configuration file at `config/deploy-config.json` to customize deployment parameters:

Example configuration:
    {
      "tokenName": "Sapien Token",
      "tokenSymbol": "SAP",
      "initialSupply": "1000000000000000000000000",
      "minStakeAmount": "100000000000000000000",
      "lockPeriod": 604800,
      "earlyWithdrawalPenalty": 1000,
      "rewardRate": 100,
      "rewardInterval": 2592000,
      "bonusThreshold": "1000000000000000000000",
      "bonusRate": 50
    }

If not provided, the deployment scripts will use sensible defaults.

### Running Deployment Scripts

You can also deploy contracts individually if needed:

    # Deploy only the SAP Token
    npx hardhat run scripts/deploy-sap-test-token.js --network base-sepolia

    # Deploy only the Staking contract
    npx hardhat run scripts/deploy-sapien-staking.js --network base-sepolia

    # Deploy only the Rewards contract
    npx hardhat run scripts/deploy-sapien-rewards.js --network base-sepolia

Note: Individual deployments require previous contracts to be deployed first (e.g., deploying the Staking contract requires the SAP Token to be deployed first).

### Deployment Artifacts

All deployment information is saved to the `deployments/<network-name>/` directory:

- `SapToken.json`: Contains SAP Token deployment details
- `SapienStaking.json`: Contains Staking contract deployment details  
- `SapienRewards.json`: Contains Rewards contract deployment details
- `DeploymentSummary.json`: Contains complete deployment summary (when using deploy-all.js)

### Verifying Deployment

After deployment, you can verify the contracts on Basescan:

    npx hardhat verify --network <network-name> <contract-address> <constructor-args>

For example, to verify the SAP Token:

    npx hardhat verify --network base-sepolia 0xYourTokenAddress "Sapien Token" "SAP" "1000000000000000000000000"


#### Initialize Individual Contracts

You can also initialize contracts individually if needed:

    # Initialize only the SAP Token
    npx hardhat run scripts/initialize-sap-token.js --network <network-name>

    # Initialize only the Staking contract
    npx hardhat run scripts/initialize-sapien-staking.js --network <network-name>

    # Initialize only the Rewards contract
    npx hardhat run scripts/initialize-sapien-rewards.js --network <network-name>

Note: Individual initializations should still be performed in order (Token → Staking → Rewards) to ensure proper contract interactions.

#### Upgrade Contracts

Each contract can be upgraded individually when needed. Make sure to thoroughly test upgrades on a testnet before deploying to mainnet.

    # Upgrade the SAP Token
    npx hardhat run scripts/upgrade-sap-token.js --network <network-name>

    # Upgrade the Staking contract
    npx hardhat run scripts/upgrade-sapien-staking.js --network <network-name>

    # Upgrade the Rewards contract
    npx hardhat run scripts/upgrade-sapien-rewards.js --network <network-name>

Note: Contract upgrades maintain all existing state and balances. The upgrade scripts include verification steps to ensure contract relationships remain intact after the upgrade.

#### Pause Contracts

Contracts can be paused individually or all at once in case of emergency. The pause functionality will stop all state-changing operations while allowing read operations to continue.

    # Pause the SAP Token
    npx hardhat run scripts/pause-sap-token.js --network <network-name>

    # Pause the Staking contract
    npx hardhat run scripts/pause-sapien-staking.js --network <network-name>

    # Pause the Rewards contract
    npx hardhat run scripts/pause-sapien-rewards.js --network <network-name>

    # Pause all contracts
    npx hardhat run scripts/pause-all.js --network <network-name>

Note: When using pause-all.js, contracts are paused in reverse dependency order (Rewards → Staking → Token) to ensure system safety. Only accounts with the appropriate permissions can pause contracts.

#### Manage Rewards Contract

The Rewards contract can be configured and managed through several administrative functions. These operations require the calling account to have owner permissions.

    # Set the reward token address
    npx hardhat run scripts/set-reward-token.js --network <network-name>

    # Deposit tokens to the rewards contract
    DEPOSIT_AMOUNT=1000000 npx hardhat run scripts/deposit-rewards.js --network <network-name>

    # Withdraw tokens from the rewards contract
    WITHDRAW_AMOUNT=100000 npx hardhat run scripts/withdraw-rewards.js --network <network-name>

    # Release tokens for a specific allocation type
    ALLOCATION_TYPE=0 npx hardhat run scripts/release-tokens.js --network <network-name>

    # Propose a new rewards contract
    NEW_REWARDS_CONTRACT=0x... npx hardhat run scripts/propose-rewards-contract.js --network <network-name>

    # Accept the proposed rewards contract
    npx hardhat run scripts/accept-rewards-contract.js --network <network-name>

Note: Deposit and withdrawal amounts are specified in whole tokens (they will be automatically converted to the correct decimal places). The DEPOSIT_AMOUNT and WITHDRAW_AMOUNT environment variables must be set before running those scripts. Make sure the calling account has sufficient token balance for deposits and appropriate permissions for all operations.

Note: ALLOCATION_TYPE corresponds to the following values:
    0: INVESTORS
    1: TEAM
    2: REWARDS
    3: AIRDROP
    4: COMMUNITY_TREASURY
    5: STAKING_INCENTIVES
    6: LIQUIDITY_INCENTIVES
The calling account must be either the Gnosis Safe or the authorized rewards contract. Ensure the cliff period has been reached and tokens are available for release.

# Update a vesting schedule
ALLOCATION_TYPE=0 \
CLIFF_DAYS=365 \
START_TIMESTAMP=1735689600 \
DURATION_DAYS=1460 \
AMOUNT=1000000 \
SAFE_ADDRESS=0x... \
npx hardhat run scripts/update-vesting-schedule.js --network <network-name>

Note: When updating a vesting schedule, all parameters must be provided. CLIFF_DAYS and DURATION_DAYS are specified in days, AMOUNT is in whole tokens, and START_TIMESTAMP should be a Unix timestamp in seconds. The operation requires the calling account to be the Gnosis Safe. If tokens have already been released, certain parameters cannot be modified.

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

## License

MIT
