# Tenderly Integration Tests

Virtual Testnet: Base Mainnet, Chad's Tenderly Account, project Sapien AI


This directory contains integration tests designed to run against deployed contracts on Tenderly's virtual testnet.

## Setup Requirements

Before running the integration tests, you must set the following environment variables:

### Required Environment Variables

1. **TENDERLY_VIRTUAL_TESTNET_RPC_URL**: The RPC URL for your Tenderly virtual testnet
   ```bash
   export TENDERLY_VIRTUAL_TESTNET_RPC_URL="https://virtual.mainnet.rpc.tenderly.co/..."
   ```

2. **TENDERLY_TEST_PRIVATE_KEY**: The private key corresponding to the deployed contract administrator/manager roles
   ```bash
   export TENDERLY_TEST_PRIVATE_KEY="0x..."
   ```

### Key Role Mappings

The `TENDERLY_TEST_PRIVATE_KEY` should correspond to addresses that have the following roles in the deployed contracts:

- **QA_MANAGER**: Address `0x0C6F86b338417B3b7FCB9B344DECC51d072919c9`
- **REWARDS_MANAGER**: Address `0x0C6F86b338417B3b7FCB9B344DECC51d072919c9`
- **TREASURY/ADMIN**: Address `0x0C6F86b338417B3b7FCB9B344DECC51d072919c9`

All roles use the same address in the Tenderly deployment, so you need one private key that corresponds to `0x0C6F86b338417B3b7FCB9B344DECC51d072919c9`.

## Common Issues

### UnauthorizedSigner Errors

If you see errors like:
```
[FAIL: UnauthorizedSigner(0x6E9972213BF459853FA33E28Ab7219e9157C8d02)]
```

This means the `TENDERLY_TEST_PRIVATE_KEY` environment variable is not set, and the test is using a fallback private key that doesn't have the required permissions.

**Solution**: Set the correct `TENDERLY_TEST_PRIVATE_KEY` environment variable.

### InsufficientAvailableRewards Errors

If you see errors like:
```
[FAIL: InsufficientAvailableRewards()]
```

This means the rewards contract doesn't have enough tokens to fulfill the reward claims. This usually happens after the `UnauthorizedSigner` issue is fixed but the rewards contract hasn't been properly funded.

**Solution**: The tests automatically fund the rewards contract if the treasury has sufficient balance. Check that the treasury address has enough tokens.

## Quick Setup Verification

Before running tests, use the verification script to check your setup:

```bash
cd test/integration
./verify-setup.sh
```

This script will check:
- Environment variables are set correctly  
- RPC endpoint is accessible
- Private key format and address derivation
- Foundry configuration

## Running the Tests

Once you have the environment variables set:

```bash
# Run all integration tests
FOUNDRY_PROFILE=tenderly forge test --match-path "test/integration/" -v

# Run specific test files
FOUNDRY_PROFILE=tenderly forge test --match-contract "TenderlyIntegrationTest" -v
FOUNDRY_PROFILE=tenderly forge test --match-contract "TenderlyRewardsIntegrationTest" -v
FOUNDRY_PROFILE=tenderly forge test --match-contract "TenderlyQAIntegrationTest" -v
FOUNDRY_PROFILE=tenderly forge test --match-contract "TenderlyVaultIntegrationTest" -v

# Run with verbose output for debugging
FOUNDRY_PROFILE=tenderly forge test --match-test "test_name" -vvv
```

## Test File Overview

- **TenderlyIntegration.t.sol**: General integration tests covering all main user flows
- **TenderlyRewards.t.sol**: Specific tests for the rewards claiming system
- **TenderlyQA.t.sol**: Specific tests for the QA penalty system
- **TenderlyVault.t.sol**: Specific tests for vault staking operations

## Troubleshooting

1. **Environment Variable Issues**: Ensure both `TENDERLY_VIRTUAL_TESTNET_RPC_URL` and `TENDERLY_TEST_PRIVATE_KEY` are exported in your shell
2. **Network Issues**: Verify your Tenderly virtual testnet is running and accessible
3. **Contract Deployment**: Ensure all contracts are properly deployed to your Tenderly testnet
4. **Private Key Permissions**: Verify the private key corresponds to an address with the required roles

For more detailed debugging, run tests with `-vvv` flag to see full transaction traces.

## Deployed Contract Addresses

The tests use the following deployed contract addresses on the Tenderly testnet:

- **SapienToken**: `0xd3a8f3e472efB7246a5C3c604Aa034b6CDbE702F`
- **Multiplier**: `0x4Fd7836c7C3Cb0EE140F50EeaEceF1Cbe19D8b55`
- **SapienQA**: `0x5ed9315ab0274B0C546b71ed5a7ABE9982FF1E8D`
- **SapienVault (Proxy)**: `0x35977d540799db1e8910c00F476a879E2c0e1a24`
- **SapienRewards (Proxy)**: `0xcCa75eFc3161CF18276f84C3924FC8dC9a63E28C` 