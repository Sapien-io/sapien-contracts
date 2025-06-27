# Rewards Signature and Order ID System

This document explains the cryptographic signature system and order ID structure used in the SapienRewards contract for secure reward claims.

## Overview

The SapienRewards system uses EIP-712 typed data signatures combined with specially crafted order IDs that embed expiry timestamps. This provides a secure, gasless authorization mechanism where:

1. **Backend** generates signed attestations for user rewards
2. **Users** submit these signatures to claim rewards on-chain
3. **Smart contract** validates signatures and enforces expiry rules

## Order ID Structure

### Format
Order IDs are 32-byte (256-bit) values with a specific structure:

```
┌─────────────────────────────┬────────────────────┐
│     24 bytes (192 bits)     │  8 bytes (64 bits) │
│        Unique Prefix        │   Expiry Timestamp │
└─────────────────────────────┴────────────────────┘
│                             │                    │
│  keccak256(identifier)      │   Unix timestamp   │
│  First 24 bytes             │   (uint64)         │
```

### Generation Algorithm

```solidity
function createOrderIdWithExpiry(string identifier, uint64 expiryTimestamp) -> bytes32 {
    bytes32 hash = keccak256(abi.encodePacked(identifier, expiryTimestamp));
    bytes24 prefix = bytes24(hash);  // First 24 bytes
    return bytes32(abi.encodePacked(prefix, expiryTimestamp));
}
```

### Example
```
Identifier: "user_reward_claim_123"
Expiry: 1750854479 (Fri Jun 27 2025 14:27:59 GMT)

Generated OrderID:
0xdc4ed5eaa780bf211b36081f5f6ca6a5e38c71c01b24147b00000000685e9f4f
│                                                        │                   │
│  24-byte prefix from keccak256(identifier + timestamp) │ 8-byte timestamp  │
```

## Expiry Validation Rules

The contract enforces strict timing rules on order IDs:

### 1. **Not Expired**
```solidity
if (block.timestamp >= orderTimestamp) {
    revert OrderExpired(orderId, orderTimestamp);
}
```

### 2. **Not Too Soon** 
```solidity
if (orderTimestamp < block.timestamp + MIN_ORDER_EXPIRY_DURATION) {
    revert ExpiryTooSoon(orderId, orderTimestamp);
}
```
- `MIN_ORDER_EXPIRY_DURATION = 1 minute`
- Prevents replay attacks and ensures sufficient time for transaction processing

### 3. **Not Too Far**
```solidity
if (orderTimestamp > block.timestamp + MAX_ORDER_EXPIRY_DURATION) {
    revert ExpiryTooFar(orderId, orderTimestamp);
}
```
- `MAX_ORDER_EXPIRY_DURATION = 5 minutes`
- Limits the validity window to prevent long-lived signatures

### Valid Window
Orders must expire between **1-5 minutes** from the current block timestamp.

## EIP-712 Signature System

### Typed Data Structure
```solidity
struct RewardClaim {
    address userWallet;
    uint256 rewardAmount; 
    bytes32 orderId;
}
```

### Domain Separator
```solidity
EIP712Domain {
    string name: "SapienRewards"
    string version: "1.0"
    uint256 chainId: [current chain ID]
    address verifyingContract: [contract address]
}
```

### Type Hash
```solidity
REWARD_CLAIM_TYPEHASH = keccak256(
    "RewardClaim(address userWallet,uint256 rewardAmount,bytes32 orderId)"
);
```

### Signature Generation Process

1. **Create Struct Hash**:
```solidity
structHash = keccak256(abi.encode(
    REWARD_CLAIM_TYPEHASH,
    userWallet,
    rewardAmount, 
    orderId
));
```

2. **Create Digest**:
```solidity
digest = keccak256(abi.encodePacked(
    "\x19\x01",
    DOMAIN_SEPARATOR,
    structHash
));
```

3. **Sign Digest**:
```javascript
signature = await rewardManagerWallet.signMessage(ethers.getBytes(digest));
```

### Solidity Test Helper

```solidity
function createOrderIdWithExpiry(
    string memory identifier, 
    uint64 expiryTimestamp
) internal pure returns (bytes32) {
    bytes24 randomPart = bytes24(keccak256(abi.encodePacked(identifier, expiryTimestamp)));
    return bytes32(abi.encodePacked(randomPart, expiryTimestamp));
}
```

## Security Considerations

### 1. **Signature Validation**
- Only accounts with `REWARD_MANAGER_ROLE` can create valid signatures
- ECDSA signature recovery is used to verify signer identity
- Invalid signatures are rejected with `UnauthorizedSigner` error

### 2. **Replay Protection**
- Each `orderId` can only be used once per user
- Mapping tracks: `redeemedOrders[user][orderId] = true`
- Duplicate usage reverts with `OrderAlreadyUsed` error

### 3. **Time-Based Security**
- Short validity windows (1-5 minutes) limit attack surfaces
- Block timestamp used for validation (not `block.number`)
- Miners can manipulate timestamps by ~15 seconds maximum

### 4. **Amount Validation**
- Rewards cannot exceed `MAX_REWARD_AMOUNT`
- Contract must have sufficient `availableRewards` 
- Zero amounts are rejected

### 5. **Role-Based Access**
- Reward managers cannot claim rewards themselves
- Prevents insider abuse of the signature system

## Error Reference

| Error Selector | Error | Description |
|----------------|-------|-------------|
| `0x90c1d80f` | `OrderExpired(bytes32,uint256)` | Order timestamp has passed |
| `0xb558d548` | `ExpiryTooSoon(bytes32,uint256)` | Order expires within 1 minute |
| `0x[unknown]` | `ExpiryTooFar(bytes32,uint256)` | Order expires beyond 5 minutes |

## Usage Workflow

### Backend (Reward Manager)
1. User completes qualifying action
2. Backend calculates reward amount
3. Backend creates unique order ID with future expiry
4. Backend signs EIP-712 typed data
5. Backend returns signature to user

### Frontend (User)
1. Receives signature from backend
2. Submits transaction calling `claimReward(amount, orderId, signature)`
3. Contract validates signature and timing
4. Tokens transferred to user wallet

### Smart Contract
1. Validates order ID expiry timing
2. Verifies EIP-712 signature authenticity
3. Checks signer has `REWARD_MANAGER_ROLE`
4. Marks order as redeemed
5. Transfers reward tokens

## Testing

### Key Test Cases
- ✅ Valid orders within 1-5 minute window
- ❌ Expired orders (past timestamp)
- ❌ Too soon orders (< 1 minute)
- ❌ Too far orders (> 5 minutes)
- ❌ Invalid signatures
- ❌ Duplicate order usage
- ❌ Unauthorized signers

### Example Test
```solidity
function test_ValidRewardClaim() public {
    uint64 validExpiry = uint64(block.timestamp + 2 minutes);
    bytes32 orderId = createOrderIdWithExpiry("test_order", validExpiry);
    
    bytes memory signature = createSignature(user, 1000e18, orderId);
    
    vm.prank(user);
    bool success = sapienRewards.claimReward(1000e18, orderId, signature);
    
    assertTrue(success);
    assertEq(rewardToken.balanceOf(user), 1000e18);
}
```

## Troubleshooting Common Issues

### 1. `OrderExpired` Error
- **Cause**: Order timestamp is in the past
- **Solution**: Create new order with future timestamp
- **Check**: Compare `extractExpiryFromOrderId(orderId)` with current time

### 2. `ExpiryTooSoon` Error  
- **Cause**: Order expires within 1 minute
- **Solution**: Create order that expires at least 60 seconds in future
- **Check**: Ensure `expiryTimestamp >= currentTime + 60`

### 3. `ExpiryTooFar` Error
- **Cause**: Order expires more than 5 minutes in future
- **Solution**: Create order that expires within 5 minutes
- **Check**: Ensure `expiryTimestamp <= currentTime + 300`

### 4. `InsufficientFunds` Error
- **Cause**: User account lacks ETH for gas fees
- **Solution**: Fund account with ETH
- **Fix**: `cast rpc anvil_setBalance [address] 0x8ac7230489e80000`

### 5. Time Synchronization Issues
- **Problem**: Frontend time differs from blockchain time
- **Solution**: Always use blockchain timestamp when creating orders
- **Example**: Use `provider.getBlock('latest').timestamp`

## Integration Notes

- **Gas Estimation**: Orders too close to expiry may fail during gas estimation
- **Time Synchronization**: Ensure backend and blockchain time are synchronized
- **Error Handling**: Parse custom error selectors for specific failure reasons
- **Retry Logic**: Regenerate orders on expiry-related failures
- **Testing**: Use Anvil's time manipulation for comprehensive testing

## Constants Reference

```solidity
// From src/utils/Constants.sol
uint256 internal constant MIN_ORDER_EXPIRY_DURATION = 1 minutes;  // 60 seconds
uint256 internal constant MAX_ORDER_EXPIRY_DURATION = 5 minutes;  // 300 seconds
```