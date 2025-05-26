# SapienRewards Solidity API

The **SapienRewards** contract is designed for token-based reward management, using a Bloom filter for efficient tracking of redeemed order IDs. This contract supports features like pausing, ownership, upgradeability, and reentrancy protection.

## Contract: `SapienRewards`
*Location*: `contracts/artifacts/SapienRewards.sol`

### Modifiers

- **`hasTokenBalance`**
  - **Definition**: `modifier hasTokenBalance(uint256 amount)`
  - **Description**: Ensures the contract holds a sufficient token balance before processing a reward.

---

### Functions

1. **`initialize`**
   - **Signature**: `function initialize(address _rewardToken, address _authorizedSigner) public`
   - **Description**: Initializes the contract with the token address and authorized signer address.

2. **`claimReward`**
   - **Signature**: `function claimReward(uint256 rewardAmount, bytes32 orderId, bytes memory signature) external`
   - **Description**: Allows a user to claim rewards by providing a valid signature, checks if the order ID is already redeemed using a Bloom filter.

3. **`isOrderRedeemed`**
   - **Signature**: `function isOrderRedeemed(address user, bytes32 orderId) internal view returns (bool)`
   - **Description**: Checks if an order ID has potentially been redeemed based on the user’s Bloom filter.

4. **`addOrderToBloomFilter`**
   - **Signature**: `function addOrderToBloomFilter(address user, bytes32 orderId) internal`
   - **Description**: Marks an order ID in the user’s Bloom filter to track redemption.

5. **`verifyOrder`**
   - **Signature**: `function verifyOrder(address user, uint256 rewardAmount, bytes32 orderId, bytes memory signature) internal view returns (bool)`
   - **Description**: Verifies that an order was signed by the authorized signer.

6. **`getMessageHash`**
   - **Signature**: `function getMessageHash(address user, uint256 rewardAmount, bytes32 orderId, address userWallet) public pure returns (bytes32)`
   - **Description**: Generates the hash used to verify the order’s signature.

7. **`recoverSigner`**
   - **Signature**: `function recoverSigner(bytes32 messageHash, bytes memory signature) public pure returns (address)`
   - **Description**: Recovers the signer’s address from the signature.

8. **`splitSignature`**
   - **Signature**: `function splitSignature(bytes memory sig) public pure returns (bytes32 r, bytes32 s, uint8 v)`
   - **Description**: Splits the signature into `r`, `s`, and `v` components.

9. **`depositTokens`**
   - **Signature**: `function depositTokens(uint256 amount) external`
   - **Description**: Allows the contract owner to deposit tokens.

10. **`withdrawTokens`**
    - **Signature**: `function withdrawTokens(uint256 amount) external`
    - **Description**: Allows the contract owner to withdraw tokens.

11. **`pause`**
    - **Signature**: `function pause() external`
    - **Description**: Pauses contract operations.

12. **`unpause`**
    - **Signature**: `function unpause() external`
    - **Description**: Resumes contract operations.

13. **`_authorizeUpgrade`**
    - **Signature**: `function _authorizeUpgrade(address newImplementation) internal`
    - **Description**: Ensures only the owner can upgrade the contract.

---

### Inheritance

- **`ReentrancyGuardUpgradeable`**
  - - **`__ReentrancyGuard_init`**: Initializes reentrancy guard.
  - - **`_reentrancyGuardEntered`**: Checks if a function is currently entered to prevent reentrancy.

- **`UUPSUpgradeable`**
  - - **`upgradeToAndCall`**: Upgrades contract and executes a function.
  - - **`_checkProxy` / `_checkNotDelegated`**: Ensures function calls are from proxy or not via delegatecall.

- **`PausableUpgradeable`**
  - - **`_pause` / `_unpause`**: Pauses/unpauses the contract.

- **`OwnableUpgradeable`**
  - - **`transferOwnership`**: Transfers contract ownership.

---

### Events

- **`RewardClaimed`**
  - **Definition**: `event RewardClaimed(address indexed user, uint256 amount, bytes32 orderId)`
  - **Description**: Emitted when a reward is successfully claimed.

- **`WithdrawalProcessed`**
  - **Definition**: `event WithdrawalProcessed(address indexed user, bytes32 indexed eventOrderId, bool success, string reason)`
  - **Description**: Emitted when a reward withdrawal is processed.

- **`Paused`**
  - **Definition**: `event Paused(address account)`
  - **Description**: Emitted when the contract is paused.

- **`Unpaused`**
  - **Definition**: `event Unpaused(address account)`
  - **Description**: Emitted when the contract is unpaused.

- **`OwnershipTransferred`**
  - **Definition**: `event OwnershipTransferred(address previousOwner, address newOwner)`
  - **Description**: Emitted when contract ownership is transferred.

---

### Notes
The `SapienRewards` contract integrates several upgradeable modules to support advanced functionalities, including proxy compatibility (`UUPSUpgradeable`), reentrancy protection (`ReentrancyGuardUpgradeable`), pause capability (`PausableUpgradeable`), and ownership management (`OwnableUpgradeable`).
