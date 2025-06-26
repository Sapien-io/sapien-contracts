# Localhost Integration Tests

This directory contains comprehensive integration tests designed to run against locally deployed contracts on Anvil.

## Overview

The `LocalIntegrationTest` contract provides end-to-end testing of the Sapien protocol against real deployed contracts running on a local Anvil node. These tests validate all core user flows including:

- User onboarding and basic token operations
- Complete staking journeys (conservative, aggressive, strategic users)
- Stake modifications (increase amount, extend lockup)
- Unstaking processes (normal and early withdrawal)
- Reward claiming with cryptographic signatures
- Multiplier calculations across all tiers
- High-load scenarios with multiple concurrent users

## Prerequisites

1. **Anvil running locally**: You need a local Anvil node running on port 8545
2. **Contracts deployed** (optional): The tests can either use pre-deployed contracts or deploy them automatically

## Quick Start

### Method 1: Let tests deploy contracts automatically

```bash
# Start Anvil in one terminal
anvil

# In another terminal, run the tests
FOUNDRY_PROFILE=localhost forge test --match-path "test/localhost/LocalIntegration.t.sol" --fork-url http://localhost:8545 -v
```

### Method 2: Deploy contracts first, then test

```bash
# Start Anvil
anvil

# Deploy contracts (in another terminal)
./scripts/deploy_localhost.sh

# Run tests against deployed contracts
FOUNDRY_PROFILE=localhost forge test --match-path "test/localhost/LocalIntegration.t.sol" --fork-url http://localhost:8545 -v
```

## Test Structure

### Contract Deployment Strategy

The test automatically detects whether contracts are already deployed at expected addresses:

- **If contracts exist**: Uses the existing deployed contracts
- **If contracts don't exist**: Deploys fresh contracts for testing

This design allows for flexible testing against both fresh deployments and existing contract states.

### Test User Personas

The tests use realistic user personas with different staking strategies:

- **Conservative Staker**: Small stakes, short lockups (low risk)
- **Aggressive Staker**: Large stakes, long lockups (high risk/reward)
- **Strategic Staker**: Dynamic adjustments to stakes and lockups
- **Emergency User**: Tests early withdrawal scenarios
- **QA Victim**: Tests penalty enforcement (currently disabled)

### Available Test Functions

| Test Function | Description | Validates |
|---------------|-------------|-----------|
| `test_Integration_BasicUserOnboarding` | Basic ERC20 operations | Token transfers, approvals |
| `test_Integration_StakingJourney` | Multi-user staking scenarios | Stake creation, multipliers |
| `test_Integration_StakeModifications` | Dynamic stake changes | Amount increases, lockup extensions |
| `test_Integration_UnstakingProcess` | Normal unstaking flow | Cooldown periods, withdrawals |
| `test_Integration_EarlyUnstaking` | Emergency withdrawals | Penalty calculations |
| `test_Integration_RewardClaiming` | EIP-712 reward claims | Signature verification |
| `test_Integration_MultiplierCalculations` | Tier-based multipliers | All amount/duration combinations |
| `test_Integration_CompleteUserJourney` | End-to-end user flow | Full protocol interaction |
| `test_Integration_HighLoadScenario` | System stress testing | Concurrent operations |

## Configuration

### Foundry Profile

The tests use the `localhost` profile defined in `foundry.toml`:

```toml
[profile.localhost]
test = "test/localhost"
fork_url = "http://localhost:8545"
fork_block_number = 0
```

### Test Constants

Key test parameters can be modified in the contract:

```solidity
uint256 public constant INITIAL_USER_BALANCE = 1_000_000 * 1e18; // 1M tokens per user
uint256 public constant SMALL_STAKE = 5_000 * 1e18;
uint256 public constant MEDIUM_STAKE = 25_000 * 1e18;
uint256 public constant LARGE_STAKE = 100_000 * 1e18;
```

### System Accounts

The tests use Anvil's default accounts:

- **Admin**: `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` (Account 0)
- **Treasury**: `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` (Account 1) 
- **QA Manager**: `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` (Account 2)
- **Rewards Manager**: `0x90F79bf6EB2c4f870365E785982E1f101E93b906` (Account 3)

## Usage Examples

### Running Specific Tests

```bash
# Test only basic user onboarding
FOUNDRY_PROFILE=localhost forge test --match-test "test_Integration_BasicUserOnboarding" --fork-url http://localhost:8545 -vv

# Test staking functionality
FOUNDRY_PROFILE=localhost forge test --match-test "test_Integration_Staking" --fork-url http://localhost:8545 -v

# Test with maximum verbosity for debugging
FOUNDRY_PROFILE=localhost forge test --match-test "test_Integration_RewardClaiming" --fork-url http://localhost:8545 -vvvv
```

### Continuous Integration

For CI/CD pipelines:

```bash
# Start Anvil in background
anvil &
ANVIL_PID=$!

# Wait for Anvil to start
sleep 2

# Run tests
FOUNDRY_PROFILE=localhost forge test --match-path "test/localhost/LocalIntegration.t.sol" --fork-url http://localhost:8545
TEST_RESULT=$?

# Cleanup
kill $ANVIL_PID

exit $TEST_RESULT
```

## Key Features

### 🚀 **Automatic Contract Deployment**
- Tests work with or without pre-deployed contracts
- Deploys full protocol stack if needed
- Uses actual contract interactions, not mocks

### 🔐 **Cryptographic Verification**
- EIP-712 signature testing for rewards
- Real private key/address validation
- Domain separator verification

### 🏗️ **Real Protocol Interactions**
- Tests against actual deployed contracts
- Validates cross-contract communications
- Ensures integration consistency

### 📊 **Comprehensive Coverage**
- All user journey scenarios
- Edge cases and failure modes
- High-load stress testing

## Troubleshooting

### Common Issues

1. **"LocalIntegrationTest: Must run on Anvil"**
   - Ensure Anvil is running on port 8545
   - Check that `block.chainid == 31337`

2. **"Treasury doesn't have enough tokens"**
   - Verify SapienToken deployment succeeded
   - Check that treasury received initial token supply

3. **"InsufficientAvailableRewards"**
   - Rewards contract needs proper funding via `depositRewards()`
   - Direct token transfers don't count as available rewards

4. **Gas estimation errors**
   - Increase Anvil gas limit: `anvil --gas-limit 300000000`

### Debugging

Enable maximum verbosity for detailed transaction traces:

```bash
FOUNDRY_PROFILE=localhost forge test --match-path "test/localhost/LocalIntegration.t.sol" --fork-url http://localhost:8545 -vvvv
```

## Contributing

When adding new integration tests:

1. **Follow naming convention**: `test_Integration_[Feature]`
2. **Use realistic scenarios**: Model after actual user behavior
3. **Add comprehensive validation**: Verify all state changes
4. **Document test purpose**: Clear comments explaining what's being tested
5. **Handle edge cases**: Include failure scenarios where appropriate

## Notes

- **QA Penalty Test**: Currently disabled due to EIP-712 signature verification complexities
- **Performance**: Tests complete in ~5 seconds on typical hardware
- **Deterministic**: Tests use fixed Anvil accounts for reproducible results
- **Stateless**: Each test run starts with fresh contract state 