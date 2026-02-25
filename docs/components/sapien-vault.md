# SapienVault

`SapienVault` is an ERC-4626 vault for SAPIEN token staking with **typed lock categories**. It holds all user funds and implements distinct lock buckets for contributors and validators, in-flight stake tracking, and share-burn slashing.

Deployed behind an **ERC-1967 UUPS proxy** with **ERC-7201 namespaced storage** (namespace: `sapien.storage.StakeVault`).

## Architecture

The vault uses a `StakeAccount` struct per user with three distinct lock categories:

```
StakeAccount {
    contributorLock    // Tokens locked when claiming contribution slots
    validatorCapacity  // Tokens pre-locked as validation capacity
    inFlight           // Tokens committed to active validations (drawn from capacity)
}
```

**Available balance** = `convertToAssets(shares) - contributorLock - validatorCapacity - inFlight`

Only the available balance can be withdrawn or transferred.

## Staking (ERC-4626)

Users interact with standard ERC-4626 functions:

- `deposit(assets, receiver)` — Deposit SAPIEN tokens, receive vault shares
- `withdraw(assets, receiver, owner)` — Withdraw up to available balance
- `mint(shares, receiver)` — Mint specific number of shares
- `redeem(shares, receiver, owner)` — Redeem shares for assets

**Inflation attack mitigation**: The vault uses a `_decimalsOffset()` of 3 (virtual shares), preventing common ERC-4626 donation attacks.

**Pause protection**: When paused, `maxDeposit`, `maxMint`, `maxRedeem`, and `maxWithdraw` all return 0, blocking all ERC-4626 operations.

## Deposit Age Tracking (Flash Staking Prevention)

To prevent flash staking (deposit-validate-withdraw in adjacent blocks), the vault tracks per-user deposit age:

- **`lastDepositTimestamp`**: Recorded on each deposit; updated whenever the user deposits.
- **`minDepositAge`**: Admin-configurable minimum age (in seconds) that deposits must reach before they can be used for validator capacity. Defaults to 0 (disabled).
- **`lockValidatorCapacity`** checks that `block.timestamp - lastDepositTimestamp >= minDepositAge` before allowing capacity lock.
- Admin sets via `setMinDepositAge(uint256 age)` (max 7 days).

| Error | Description |
|-------|-------------|
| `DepositTooRecent(uint256 required, uint256 actual)` | User attempted to lock validator capacity before deposits aged past `minDepositAge` |
| `MinDepositAgeTooHigh(uint256 requested, uint256 max)` | Admin attempted to set `minDepositAge` above 7 days |

## Contributor Operations

Called by `SapienCore` (requires `ENGINE_ROLE`):

### `lockContributor(address user, uint256 amount)`
Locks tokens from the user's available balance into the `contributorLock` bucket. Called when a contributor claims slots, posts a dispute bond, or posts an originator report bond.

### `unlockContributor(address user, uint256 amount)`
Releases tokens from `contributorLock` back to available balance. Called when contributions are accepted, claims complete, or dispute bonds are returned.

### `slashContributor(address user, uint256 amount)`
Removes tokens from `contributorLock` and burns the equivalent shares. Called when contributors fail to submit, contributions are rejected, or dispute bonds are forfeited.

### `slashAndUnlockContributor(address user, uint256 slashAmount, uint256 unlockAmount)`
Atomic operation that slashes unsubmitted slots and unlocks submitted slots from a single claim. Avoids two separate calls for claim expiration.

## Validator Operations

Called by `SapienCore` (requires `ENGINE_ROLE`):

### `lockValidatorCapacity(address user, uint256 amount)`
Moves tokens from available balance to the `validatorCapacity` bucket. Validators pre-lock capacity before claiming validations.

### `unlockValidatorCapacity(address user, uint256 amount)`
Returns tokens from `validatorCapacity` to available balance.

### `commitStake(address user, uint256 amount)`
Moves tokens from `validatorCapacity` to `inFlight`. Called when a validator commits a validation score.

### `releaseCommit(address user, uint256 amount)`
Returns tokens from `inFlight` back to `validatorCapacity`. Called when a validator is settled as accurate.

### `slashValidator(address user, uint256 amount)`
Removes tokens from `inFlight` and burns the equivalent shares. Called when a validator is identified as an outlier.

## Transfer Guard

Share transfers between users are restricted: the sender must retain enough shares to cover their total locked amount (`contributorLock + validatorCapacity + inFlight`). Mints and burns are unrestricted.

## Events

| Event | Description |
|-------|-------------|
| `ContributorLocked(user, amount)` | Contributor stake locked |
| `ContributorUnlocked(user, amount)` | Contributor stake unlocked |
| `ContributorSlashed(user, amount)` | Contributor shares burned |
| `ValidatorCapacityLocked(user, amount)` | Validator capacity locked |
| `ValidatorCapacityUnlocked(user, amount)` | Validator capacity unlocked |
| `StakeCommitted(user, amount)` | Stake moved to in-flight |
| `CommitReleased(user, amount)` | Stake returned from in-flight to capacity |
| `ValidatorSlashed(user, amount)` | Validator shares burned |
| `MinDepositAgeUpdated(uint256 newAge)` | Admin updated the minimum deposit age |

## View Functions

| Function | Returns |
|----------|---------|
| `getStakeAccount(user)` | Full `StakeAccount` struct |
| `availableBalance(user)` | Withdrawable token amount |
| `totalStaked(user)` | Total assets (all categories) |
| `maxRedeem(owner)` | Maximum redeemable shares (respects locks + pause) |
| `maxWithdraw(owner)` | Maximum withdrawable assets (respects locks + pause) |
| `maxDeposit(address)` | `type(uint256).max` or 0 when paused |
| `maxMint(address)` | `type(uint256).max` or 0 when paused |
| `verifyStorageLocation()` | Validates ERC-7201 storage slot derivation |
| `minDepositAge()` | Returns the minimum deposit age (seconds) required before locking validator capacity |

### Admin Functions

| Function | Description |
|----------|-------------|
| `setMinDepositAge(uint256 age)` | Sets the minimum deposit age (max 7 days). Default 0 (disabled). |

## Access Control

| Role | Permissions |
|------|------------|
| `ENGINE_ROLE` | All lock/unlock/slash/commit/release operations (granted to `SapienCore`) |
| `DEFAULT_ADMIN_ROLE` | Pause/unpause, upgrades, `setMinDepositAge` |

## Slashing Economics

When shares are burned via slashing, the underlying assets remain in the vault. Since fewer shares now represent the same pool of assets, the "price per share" increases for all remaining stakers. This redistributes slashed value to honest participants.
