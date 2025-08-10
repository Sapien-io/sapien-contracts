# Sapien Protocol Deployment Guide

This guide provides step-by-step instructions for deploying the complete Sapien AI protocol across all supported networks.

## Overview

The Sapien protocol consists of the following core contracts:

1. **SapienToken** - The native ERC20 token
2. **TimelockController** - Governance timelock for upgrades (48-hour delay)
3. **SapienQA** - Quality assurance penalty management
4. **SapienVault** - Staking vault with reputation system
5. **SapienRewards** - Reward distribution system
6. **USDCRewards** - USDC-based reward distribution (optional)
7. **BatchRewards** - Batch claiming for multiple reward contracts

## Prerequisites

### Required Tools
- Foundry (forge, cast)
- Make
- Git
- Access to deployer private key
- Network RPC endpoints

### Environment Setup
```bash
# Clone the repository
git clone <repository-url>
cd sapien-contracts

# Install dependencies
forge install

# Set up environment variables
export RPC_URL="your-network-rpc"
export ETHERSCAN_API_KEY="your-etherscan-api-key"
```

## Supported Networks

| Network | Chain ID | Description |
|---------|----------|-------------|
| Local Anvil | 31337 | Local development |
| Base Sepolia | 84532 | Testnet |
| Tenderly Fork | 8453420 | Virtual testnet |
| Base Mainnet | 8453 | Production |

## Actor Configuration

The protocol uses predefined actor addresses for each network, configured in `script/Actors.sol`:

### Core Actors
- **Foundation Safe 1**: Primary foundation treasury
- **Foundation Safe 2**: Secondary foundation operations
- **Security Council**: Emergency operations and governance
- **Sapien Labs**: Protocol administration
- **Blended**: Multi-signature combination of foundation + corp

### Operational Actors
- **Rewards Admin**: Manages reward token deposits/withdrawals
- **Rewards Manager**: Signs reward claims
- **QA Manager**: Executes quality assurance decisions
- **QA Signer**: Creates signatures for QA decisions
- **Pauser**: Emergency pause capabilities
- **Timelock Proposer**: Proposes governance actions
- **Timelock Executor**: Executes governance actions
- **Timelock Admin**: Manages timelock roles

## Deployment Order

**⚠️ CRITICAL: Follow this exact order. Dependencies between contracts require specific deployment sequence.**

Setup the Globals env vars:

```
export ETHERSCAN_API_KEY=
export ACCOUNT=
export RPC_URL=
```

### 1. Deploy SapienToken

```bash
# Deploy the token
export CONTRACT=SapienToken
make deploy-contract

# Verify deployment
cast call $SAPIEN_TOKEN_ADDRESS "totalSupply()" --rpc-url $RPC_URL
cast call $SAPIEN_TOKEN_ADDRESS "balanceOf(address)" $BLENDED_ADDRESS --rpc-url $RPC_URL
```

**Expected Output:**
- Token deployed with 1 billion SAPIEN supply
- All tokens sent to Blended multisig
- Contract verified on Etherscan

### 2. Deploy TimelockController

```bash
# Deploy timelock with 48-hour delay
export CONTRACT=DeployTimelock
make deploy-script

# Verify configuration
cast call $TIMELOCK_ADDRESS "getMinDelay()" --rpc-url $RPC_URL
```

**Expected Output:**
- Timelock deployed with 48-hour minimum delay
- Proposer, executor, and admin roles assigned
- Contract verified on Etherscan

**Configuration:**
- **Proposer**: Security Council (can propose operations)
- **Executor**: Sapien Labs (can execute after delay)
- **Admin**: Blended (can manage timelock roles)

### 3. Deploy SapienQA

```bash
# Deploy QA contract (vault address placeholder)
export CONTRACT=DeployQA
# Verify initialization
cast call $QA_PROXY_ADDRESS "treasury()" --rpc-url $RPC_URL
```

**Expected Output:**
- QA implementation and proxy deployed
- Timelock set as proxy admin
- Vault address set to placeholder (address(1))

**⚠️ Note:** Vault address will be updated after vault deployment.

### 4. Deploy SapienVault

```bash
# Deploy vault contract
export CONTRACT=DeploySapienVault
make deploy-script

# Verify configuration
cast call $VAULT_PROXY_ADDRESS "sapienToken()" --rpc-url $RPC_URL
cast call $VAULT_PROXY_ADDRESS "treasury()" --rpc-url $RPC_URL
```

**Expected Output:**
- Vault implementation and proxy deployed
- SAPIEN token configured for staking
- QA contract granted SAPIEN_QA_ROLE

### 5. Update QA Contract Vault Address

After vault deployment, update the QA contract's vault address.


### 6. Deploy SapienRewards

```bash
# Deploy SAPIEN token rewards contract
export CONTRACT=DeploySapienRewards
make deploy-script

# Verify configuration
cast call $SAPIEN_REWARDS_PROXY_ADDRESS "rewardToken()" --rpc-url $RPC_URL
```

**Expected Output:**
- Rewards implementation and proxy deployed
- SAPIEN token configured as reward token
- Admin and manager roles assigned

### 7. Deploy USDC Token (Testnet Only)

For testnets, deploy a mock USDC token:

```bash
# Deploy mock USDC (testnet only)
forge script script/DeployUSDCToken.s.sol --rpc-url $RPC_URL --broadcast --verify
```

### 8. Deploy USDCRewards (Optional)

```bash
# Deploy USDC rewards contract
export CONTRACT=DeployUSDCRewards
make deploy-script

# Verify configuration
cast call $USDC_REWARDS_PROXY_ADDRESS "rewardToken()" --rpc-url $RPC_URL
```

### 9. Deploy BatchRewards

```bash
# Deploy batch rewards contract
export CONTRACT=DeployBatchRewards
make deploy-script

# Verify configuration
cast call $BATCH_REWARDS_ADDRESS "sapienRewards()" --rpc-url $RPC_URL
cast call $BATCH_REWARDS_ADDRESS "usdcRewards()" --rpc-url $RPC_URL
```

## Post-Deployment Configuration

### Role Management

After deployment, several role management actions are required:

#### 1. Revoke Deployer Admin Roles

The deployer receives DEFAULT_ADMIN_ROLE during initialization but should be revoked.

#### 2. Grant Timelock Admin Roles

Grant DEFAULT_ADMIN_ROLE to timelock for governance.

#### 3. Grant BatchRewards BATCH_CLAIMER_ROLE

For SapienRewards and USDCRewards.

#### 4. Grant SapienVault.SAPIEN_QA_ROLE

### Contract Verification

Verify all contracts are properly configured:

```bash
# Run role verification script
forge script script/CheckRoles.s.sol --rpc-url $RPC_URL --broadcast
```

## Network-Specific Addresses

After deployment, update `script/Contracts.sol` with the deployed addresses for your network.

### Mainnet Checklist

Before mainnet deployment:

- [ ] All actor addresses are correct multisig addresses
- [ ] Timelock delay is set to 48 hours minimum
- [ ] All roles are properly assigned to multisigs
- [ ] Deployer admin roles are revoked
- [ ] Contracts are verified on Etherscan
- [ ] Integration tests pass
- [ ] Security audit completed

## Integration Testing

Run comprehensive integration tests after deployment:

```bash
# Test the complete protocol flow
forge test --match-contract LocalIntegration --rpc-url $RPC_URL

# Test specific contract functionality
forge test --match-contract SapienVault --rpc-url $RPC_URL
forge test --match-contract SapienRewards --rpc-url $RPC_URL
forge test --match-contract SapienQA --rpc-url $RPC_URL
```

## Roles and Permissions Summary

### SapienVault
- **DEFAULT_ADMIN_ROLE**: Timelock (treasury management, role assignment)
- **PAUSER_ROLE**: Security Council (emergency pause)
- **SAPIEN_QA_ROLE**: SapienQA contract (penalty enforcement)

### SapienRewards
- **DEFAULT_ADMIN_ROLE**: Timelock (contract administration)
- **REWARD_ADMIN_ROLE**: Sapien Labs (token deposits/withdrawals)
- **REWARD_MANAGER_ROLE**: Rewards Manager (signature generation)
- **BATCH_CLAIMER_ROLE**: BatchRewards contract (batch claiming)
- **PAUSER_ROLE**: Security Council (emergency pause)

### SapienQA
- **DEFAULT_ADMIN_ROLE**: Timelock (contract administration)
- **QA_MANAGER_ROLE**: QA Manager (execute QA decisions)
- **QA_SIGNER_ROLE**: QA Signer (create decision signatures)

### TimelockController
- **PROPOSER_ROLE**: Security Council (propose operations)
- **EXECUTOR_ROLE**: Sapien Labs (execute operations)
- **CANCELLER_ROLE**: Security Council (cancel operations)
- **TIMELOCK_ADMIN_ROLE**: Blended (manage timelock roles)

## Troubleshooting

### Common Issues

1. **"Contract not deployed" errors**: Ensure contracts are deployed in correct order
2. **Role assignment failures**: Verify deployer has admin role before revoking
3. **QA vault update**: Must use timelock to update vault address after deployment
4. **Proxy verification**: Use implementation addresses for Etherscan verification

### Emergency Procedures

In case of critical issues:

1. **Pause Contracts**: Security Council can pause SapienVault and SapienRewards
2. **Emergency Withdrawal**: Admin can withdraw funds when contracts are paused
3. **Timelock Cancellation**: Security Council can cancel pending timelock operations

## Contact Information

For deployment support or issues:
- Technical Documentation: `/notes/` directory
- Smart Contract Code: `/src/` directory
- Deployment Scripts: `/script/` directory
- Test Suite: `/test/` directory

---

**⚠️ WARNING**: Always test deployments on testnets before mainnet deployment. Ensure all multisig addresses are correct and accessible before deploying to production.
