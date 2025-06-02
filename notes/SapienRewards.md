# SapienRewards Contract Documentation

## Overview

**Contract:** SapienRewards  
**Purpose:** Handles off-chain signed reward claims using EIP-712 signatures. Also supports deposits, withdrawals, and reconciliation of reward token balances.

### Key Features

- EIP-712 offchain reward claims with signature validation
- Secure and permissioned reward fund management
- Order ID tracking for anti-replay
- Pause/resume functionality for emergency control
- Compatible with multi-role governance and admin controls

---

## Initialization

```solidity
function initialize(address admin, address rewardManager, address rewardAdmin, address newRewardToken)
```

Initializes the contract and assigns admin, reward manager, reward admin roles, and reward token address.

---

## Roles

| Role | Description |
|------|-------------|
| `DEFAULT_ADMIN_ROLE` | Full permissions over contract configuration |
| `PAUSER_ROLE` | Can pause/unpause contract |
| `REWARD_ADMIN_ROLE` | Manages deposits, withdrawals, reconciliations |
| `REWARD_MANAGER_ROLE` | Signs reward claims (EIP-712) and validates inputs |

---

## Claiming Rewards

### `claimReward(uint256 rewardAmount, bytes32 orderId, bytes memory signature)`

- Uses off-chain signed data
- Requires a valid EIP-712 signature from `REWARD_MANAGER_ROLE`
- Verifies:
  - Amount > 0
  - Signature validity
  - Order ID not reused
  - Sufficient funds

### `validateAndGetHashToSign(...)`

- Called by reward server to generate the correct hash to sign
- Ensures values are valid and returns EIP-712 hash

### `getOrderRedeemedStatus(user, orderId)`

- Returns if a reward order has already been redeemed

---

## Administrative Functions

### Deposit / Withdraw / Reconcile

- **`depositRewards(amount)`** – Moves tokens into the contract (tracked)
- **`withdrawRewards(amount)`** – Pulls tokens out (requires enough available)
- **`recoverUnaccountedTokens(amount)`** – Withdraws untracked tokens
- **`reconcileBalance()`** – Adjusts internal accounting to match actual token balance

---

## View Functions

- **`getAvailableRewards()`** – Tracked reward balance
- **`getRewardTokenBalances()`** – Returns both tracked and total token balances
- **`getDomainSeparator()`** – Current EIP-712 domain separator

---

## EIP-712 Hashing Internals

### `_getStructHash(...)`

Returns:

```solidity
keccak256(abi.encode(
  Const.REWARD_CLAIM_TYPEHASH,
  userWallet,
  rewardAmount,
  orderId
))
```

### `_getHashToSign(...)`

Returns:

```solidity
keccak256(abi.encodePacked(
  "\x19\x01",
  getDomainSeparator(),
  _getStructHash(...)
))
```

---

## Events

| Event | Description |
|-------|-------------|
| `RewardTokenSet(address)` | Token changed |
| `RewardsDeposited(sender, amount, available)` | Tokens added to pool |
| `RewardsWithdrawn(sender, amount, available)` | Tokens removed |
| `RewardClaimed(user, amount, orderId)` | Claim executed |
| `UnaccountedTokensRecovered(sender, amount)` | Recovery executed |
| `RewardsReconciled(untracked, newAvailable)` | Auto-sync between balance and accounting |

---

## Errors & Reverts

- **`ZeroAddress()`** – For invalid input addresses
- **`InvalidAmount()`** – For zero or out-of-range values
- **`InvalidOrderId(orderId)`** – Malformed or reused ID
- **`InsufficientAvailableRewards()`** – Not enough tokens to fulfill reward
- **`RewardsManagerCannotClaim()`** – Prevents role abuse
- **`RewardExceedsMaxAmount(...)`** – Prevents excessive claims
- **`OrderAlreadyUsed()`** – Prevents replay attack
- **`InvalidSignatureOrParameters(...)`** – Catch-all for signature issues
- **`UnauthorizedSigner(address)`** – Recovered signer lacks correct role

---

## Security Considerations

- Replay protection with orderId
- Chain fork detection with domain separator recalculation
- Role-restricted admin flows (ERC20 deposits, withdrawals)
- Pausable contract architecture for emergency mitigation

---

## Recommendations / Notes

- Clients must use the correct `domainSeparator()` when signing
- Reward managers should never share their private keys
- Integrate `claimReward` into UI with EIP-712 signing flows
- Consider implementing expiration for signed orders (future version)

---

## Contract Version

```solidity
function version() public pure returns (string memory) {
    return "0.1.2";
}
```


---
