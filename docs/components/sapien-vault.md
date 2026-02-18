# Sapien Vault (Staking & Slashing)

The `SapienVault` is an upgradeable staking contract based on the **ERC-4626** standard. It handles the financial "skin in the game" for all protocol participants through token deposits, stake locking, and slashing.

## 📋 Responsibilities

- **Staking**: Secure storage of SAPIEN tokens deposited by users.
- **Locking**: Temporarily restricting a user's ability to withdraw funds while they have active claims or commitments.
- **Slashing**: Permanently removing a portion of a user's stake as a penalty for poor quality work or dishonest validation.
- **Inflation Protection**: Uses a decimals offset (3) to protect against common ERC-4626 inflation attacks.

## 🛠️ Key Functions

### Staking Functions

Users interact with the vault using standard ERC-4626 functions (`deposit`, `withdraw`, `mint`, `redeem`). Deposits earn "shares" representing their portion of the vault's total assets.

### Locking Logic

#### `lockStake`
Called by `SapienCore` or `ValidationOracle` when a user claims a task or sets validation capacity. Locked stake cannot be withdrawn or transferred until it is explicitly unlocked. Every lock includes a `reason` string for transparent event tracking.

#### `unlockStake`
Releases the lock on a user's assets, typically after a contribution is finalized, a claim expires, or a validator reduces their capacity.

### Slashing

#### `slash`
Removes a specified amount of assets from a user's position by burning their vault shares. 
- **Internal Mechanism**: The underlying assets remain in the vault. 
- **Effect**: Since shares are burned but assets remain, the "price per share" increases for all other stakers. This automatically redistributes the slashed value to the rest of the honest participants.

## 🛡️ Security

- **Locker/Slasher Roles**: Only authorized contracts (like `SapienCore`) can lock or slash funds.
- **Pausability**: The vault can be paused by a `PAUSER_ROLE` in case of emergencies, disabling withdrawals while maintaining deposits and internal accounting.

## 📊 View Functions

- `getStake`: Returns the total amount of tokens a user has in the vault.
- `getAvailableStake`: Returns the amount of tokens a user can withdraw (Total - Locked).
- `getLockedStake`: Returns the amount currently held for active tasks.
