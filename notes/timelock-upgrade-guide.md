# TimelockController Contract Upgrades from Safe Multisig

This guide explains how to upgrade contracts using OpenZeppelin's TimelockController through a Safe multisig wallet.

## Overview

The TimelockController provides a secure governance mechanism with time delays for critical operations. When using it with a Safe multisig, operations require two phases:

1. **Schedule Phase**: Propose the operation (requires PROPOSER_ROLE)
2. **Execute Phase**: Execute after delay period (requires EXECUTOR_ROLE)

## Prerequisites

- Safe multisig with appropriate roles on TimelockController
- Operation scheduled at least `minDelay` seconds ago
- Access to the scheduled operation details (target, value, data, predecessor, salt)

## Role Requirements

### PROPOSER_ROLE
- Can schedule new operations
- Typically held by governance contracts or trusted entities

### EXECUTOR_ROLE
- Can execute operations after the delay period
- Your Safe multisig should have this role

### ADMIN_ROLE
- Can grant/revoke other roles
- Can change the minimum delay
- Usually held by the timelock itself

## Deploy new Implementation Contract

The first step is to deploy a new implementation of the contract you want to upgrade:

Setup the path variables:
```
export RPC_URL=
export CONTRACT=SapienVault | SapienRewards | SapienQA
export ETHERSCAN_API_KEY=Etherscan api key (basescan.org)
export ACCOUNT=The wallet address in cast for deployments

The run:

make deploy-contract
```

## Using scripts/Upgrader.s.sol

See the Upgrade scripts for more info.

0 = Vault
1 = Rewards
2 = QA

`forge script script/Upgrader.s.sol --sig "generateUpgradePayload(uint8,address)" 1 0xNEW_IMPLEMENTATION_ADDRESS --rpc-url $RPC_URL`

## Step-by-Step Process

### Phase 1: Scheduling an Operation

This is typically done by a governance proposal or by an address with PROPOSER_ROLE.

```solidity
// Example: Schedule a contract upgrade
TimelockController timelock = TimelockController(payable(TIMELOCK_ADDRESS));

bytes memory upgradeCallData = abi.encodeWithSelector(
    ProxyAdmin.upgrade.selector,
    PROXY_ADDRESS,
    NEW_IMPLEMENTATION_ADDRESS
);

bytes32 salt = keccak256(abi.encodePacked("upgrade", block.timestamp));

timelock.schedule(
    PROXY_ADMIN_ADDRESS,  // target
    0,                    // value
    upgradeCallData,      // data
    bytes32(0),          // predecessor
    salt,                // salt
    timelock.getMinDelay() // delay
);
```

### Phase 2: Executing from Safe Multisig

#### 2.1 Gather Operation Details

You need these parameters from the scheduling transaction:
- `target`: The contract address to call
- `value`: ETH value to send (usually 0)
- `data`: The encoded function call
- `predecessor`: Previous operation dependency (usually bytes32(0))
- `salt`: Unique identifier for the operation

#### 2.2 Verify Operation Status

Use the TimelockController to check:

```solidity
bytes32 operationId = timelock.hashOperation(target, value, data, predecessor, salt);

bool isReady = timelock.isOperationReady(operationId);
bool isPending = timelock.isOperationPending(operationId);
bool isDone = timelock.isOperationDone(operationId);
```

The operation must be "ready" (scheduled and delay period passed) to execute.

#### 2.3 Generate Safe Transaction

Create a transaction to the TimelockController's `execute` function:

```solidity
bytes memory executeCallData = abi.encodeWithSelector(
    TimelockController.execute.selector,
    target,      // target contract
    value,       // value to send
    data,        // function call data
    predecessor, // predecessor operation
    salt         // salt from scheduling
);
```

#### 2.4 Submit to Safe

In the Safe UI:
- **To Address**: TimelockController address
- **Value**: 0
- **Data**: The `executeCallData` from step 2.3

## Common Upgrade Scenarios

### 1. Upgrading a Proxy Contract

**Target**: ProxyAdmin contract address  
**Data**: `ProxyAdmin.upgrade(proxy, newImplementation)`  

### 2. Updating Contract Parameters

**Target**: The contract being updated  
**Data**: Function call to update parameters (e.g., `setFeeRate(newRate)`)  

### 3. Granting/Revoking Roles

**Target**: The contract with access control  
**Data**: `grantRole(role, account)` or `revokeRole(role, account)`  

### 4. Updating TimelockController Delay

**Target**: TimelockController itself  
**Data**: `updateDelay(newDelayInSeconds)`  

## Finding Scheduled Operations

### Method 1: Event Logs

Look for the `CallScheduled` event:

```solidity
event CallScheduled(
    bytes32 indexed id,
    uint256 indexed index,
    address target,
    uint256 value,
    bytes data,
    bytes32 predecessor,
    uint256 delay
);
```

### Method 2: CallSalt Event

For operations with custom salts, check `CallSalt`:

```solidity
event CallSalt(bytes32 indexed id, bytes32 salt);
```

The `id` in this event is your operation ID.

## Troubleshooting

### "TimelockController: operation is not ready"

- Check if enough time has passed since scheduling
- Verify the operation hasn't been executed already
- Confirm the operation ID is correct

### "AccessControl: account is missing role"

- Verify your Safe has EXECUTOR_ROLE on the TimelockController
- Check role with: `timelock.hasRole(EXECUTOR_ROLE, SAFE_ADDRESS)`

### "TimelockController: operation already executed"

- The operation has already been executed
- Check with: `timelock.isOperationDone(operationId)`

### Simulation Failures

- Verify all parameters match exactly from the scheduling transaction
- Check that the target contract exists and function signature is correct
- Ensure any prerequisites (like contract state) are satisfied

## Security Considerations

1. **Verify Parameters**: Always double-check that the operation parameters match what was scheduled
2. **Time Sensitivity**: Some operations may become invalid if too much time passes
3. **Front-running**: Be aware that execute transactions are public and can be front-run
4. **Testing**: Test operations on testnets or forks when possible

## Tools and Scripts

### Using Foundry Scripts

The repository includes helpful scripts in `script/TimelockDelay.s.sol`:

```bash
# Check operation status
forge script script/TimelockDelay.s.sol \
  --sig 'debugOperationStatus(address,address,uint256,bytes,bytes32,bytes32)' \
  TIMELOCK_ADDRESS TARGET VALUE DATA PREDECESSOR SALT \
  --rpc-url RPC_URL

# Generate Safe execution payload
forge script script/TimelockDelay.s.sol \
  --sig 'generateSafeExecutionPayloadOffline(address,uint256,bytes32)' \
  TIMELOCK_ADDRESS NEW_DELAY SALT
```

### Using Cast

```bash
# Check if Safe has executor role
cast call TIMELOCK_ADDRESS "hasRole(bytes32,address)" \
  EXECUTOR_ROLE SAFE_ADDRESS --rpc-url RPC_URL

# Check operation status
cast call TIMELOCK_ADDRESS "isOperationReady(bytes32)" \
  OPERATION_ID --rpc-url RPC_URL
```

## Example: Complete Upgrade Flow

1. **Governance proposes upgrade** (has PROPOSER_ROLE)
2. **Wait for delay period** (e.g., 48 hours)
3. **Safe owners review** the scheduled operation
4. **Generate execution transaction** using scripts
5. **Submit to Safe** and gather signatures
6. **Execute** the multisig transaction

## Roles Reference

```solidity
bytes32 public constant TIMELOCK_ADMIN_ROLE = 0x00;
bytes32 public constant PROPOSER_ROLE = keccak256("PROPOSER_ROLE");
bytes32 public constant EXECUTOR_ROLE = keccak256("EXECUTOR_ROLE");
bytes32 public constant CANCELLER_ROLE = keccak256("CANCELLER_ROLE");
```

- **TIMELOCK_ADMIN_ROLE**: `0x0000000000000000000000000000000000000000000000000000000000000000`
- **PROPOSER_ROLE**: `0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1`
- **EXECUTOR_ROLE**: `0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63`
- **CANCELLER_ROLE**: `0xfd643c72710c63c0180259aba6b2d05451e3591a24e58b62239378085726f783`

---

*This guide assumes you're using OpenZeppelin's TimelockController. Always refer to the latest documentation and test thoroughly before executing on mainnet.* 