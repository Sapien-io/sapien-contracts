# SapienVault

SapienVault is an **ERC-4626** vault over a single ERC-20 asset (the SAPIEN token in production). It mints **vault shares** (`vSAPIEN`) representing pro-rata ownership of the underlying asset, and adds **stake locking**, **engine-controlled unlock/slash**, **pause**, and **minimum deposit age** controls for MEV and flash-loan resistance.

The implementation is **upgradeable (UUPS)** and is meant to be used behind an **ERC-1967** proxy. The implementation’s constructor disables initializers; configuration happens in `initialize(asset, admin)`.

---

## Role in the protocol

SapienVault is the **economic-security layer** for Sapien's Proof-of-Quality (PoQ) network — purely an **asset-locking and slashing mechanism**. It does not score, evaluate, or judge contribution quality on-chain; it only escrows collateral and applies penalties when instructed.

The validation work itself lives **off-chain** in the **PoQ engine**: a server (or set of servers) operated by Sapien that ingests contributions, runs the PoQ scoring pipeline, reaches consensus on outcomes, and produces the unlock/slash decisions that the vault then enforces on-chain. The vault holds `ENGINE_ROLE` open for that server's smart account.

Lifecycle as seen by the vault:

1. A contributor **deposits** the asset and **`lockStake`s** an amount as collateral against future contributions.
2. The off-chain PoQ engine evaluates their contributions. Outcomes are committed back on-chain by the engine calling either:
   - **`unlockStake(user, amount)`** — contribution accepted; collateral returned to available balance.
   - **`slashStake(user, amount)`** — contribution rejected as low-quality, dishonest, or otherwise penalty-worthy; the corresponding shares are burned, redistributing value to the remaining honest stakers.
3. The contributor `withdraw`s whatever remains.

In short: the **vault** is the on-chain custodian and slashing tool; the **engine** is the off-chain authority that decides when slashing happens. Trust in the engine is concentrated in `ENGINE_ROLE` and is therefore the protocol's primary off-chain trust assumption (see [Roles](#roles) and the repository [README](../README.md#roles--trust-assumptions)).

---

## Architecture

| Layer | Contracts |
|-------|-----------|
| Vault logic | `SapienVault` — `ERC4626Upgradeable`, `AccessControlUpgradeable`, `PausableUpgradeable`, `UUPSUpgradeable` |
| Types | `Types.sol` — `StakeAccount`, `SapienVaultStorage` (namespaced storage layout) |
| Interface | `ISapienVault` — errors, events, external API |

Custom state (per-user locks, deposit timestamps, `minDepositAge`) lives in **ERC-7201-style namespaced storage** (`SapienVaultStorage`), not in the default OpenZeppelin storage slots, to reduce upgrade collision risk. The namespace string is `"sapien.storage.SapienVault"`. The pure function `verifyStorageLocation()` checks that the derived slot matches the implementation’s hard-coded slot.

---

## Roles

| Role | Held by | On-chain capabilities |
|------|---------|-----------------------|
| `DEFAULT_ADMIN_ROLE` | Sapien governance multisig (production) | Grant/revoke roles, `setMinDepositAge`, `pause` / `unpause`, `rescueETH`, UUPS upgrades (`upgradeToAndCall`) |
| `ENGINE_ROLE` | The off-chain **PoQ engine** signing key | `unlockStake`, `slashStake` only |

`ENGINE_ROLE` is the on-chain identity of the off-chain PoQ validation server. The engine never holds user funds directly: it only signs transactions that mutate `lockedAmount` and burn shares. Pause halts both `unlockStake` and `slashStake`, so admin can stop a misbehaving or compromised engine instantly; permanent neutralisation is `revokeRole(ENGINE_ROLE, …)`.

`lockStake` is **not** gated by `ENGINE_ROLE`; the **share holder** calls it themselves to move value from “available” into “locked” within their own position, signalling willingness to be evaluated by the engine.

---

## ERC-4626 surface

Standard entry points apply: `deposit`, `mint`, `withdraw`, `redeem`, plus `preview*` / `convert*` helpers from OpenZeppelin.

- **Asset**: the token passed to `initialize`.
- **Shares**: ERC-20 `"Sapien PoQ Vault"` / `"vSAPIEN"`.
- **Decimals**: underlying asset decimals **plus** an internal offset of **3** (`_decimalsOffset`), mitigating the classic first-depositor / donation inflation attack on ERC-4626.

Integrators should use **`maxDeposit` / `maxMint` / `maxWithdraw` / `maxRedeem`** before submitting transactions; these reflect pause state, locked stake, and `minDepositAge` where applicable.

---

## Stake model

Each address has one logical **stake account**:

- **`lockedAmount`** (asset terms): portion of the user’s economic stake that is **locked** and cannot be withdrawn or transferred as shares (except as constrained by `maxRedeem` / transfers).
- **Available** balance (conceptually): total position in asset terms minus `lockedAmount` — exposed as `availableBalance(user)`.

Operations:

1. **`lockStake(amount)`** (holder, `whenNotPaused`): moves `amount` from available to locked. Requires `amount <= availableBalance(msg.sender)`, non-zero amount, and **deposit age** satisfied (see below).
2. **`unlockStake(user, amount)`** (`ENGINE_ROLE`): reduces `user`’s `lockedAmount` only (no share mint/burn).
3. **`slashStake(user, amount)`** (`ENGINE_ROLE`): reduces `lockedAmount` and **burns** shares corresponding to `amount` in asset terms via `convertToShares` / `_burn`. Remaining stakers gain pro-rata on the underlying (standard ERC-4626 behavior after burn).

---

## Minimum deposit age (`minDepositAge`)

Configurable by admin up to **`MAX_MIN_DEPOSIT_AGE` (7 days)**.

When `minDepositAge > 0`:

- On every **`deposit` / `mint`**, the **`receiver`**’s `lastDepositTimestamp` is set to `block.timestamp` (in `_deposit`).
- For **peer-to-peer share transfers** (`transfer` / `transferFrom`, both sides non-zero), the **recipient**’s `lastDepositTimestamp` is set when `value > 0`. **Zero-value transfers do not reset** the recipient’s timer.
- **`lockStake`**, **outgoing transfers** (sender), **`maxWithdraw`**, and **`maxRedeem`** require the relevant address to have “aged” its last inbound event by at least `minDepositAge`, or `lastDepositTimestamp == 0` is treated as exempt for the age check where implemented.

This slows flash-loan style positioning and immediate exits after inbound liquidity, at the cost of a **known griefing trade-off**: anyone can send a user a tiny share transfer to reset that user’s timer (documented in-code). Product and UX should account for that.

If `minDepositAge == 0`, these time checks are effectively disabled (timestamps may still be written).

---

## Pause

When paused:

- **`maxDeposit` / `maxMint`**: 0.
- **`maxWithdraw` / `maxRedeem`**: 0 (implementation returns 0 when `paused()`).
- **Wallet-to-wallet share movements**: blocked in `_update` via `whenNotPaused` for `transfer` / `transferFrom`.
- **`lockStake`**: blocked (`whenNotPaused`).

Admin can `pause` / `unpause` with `DEFAULT_ADMIN_ROLE`.

---

## Withdrawals and locked stake

Withdrawals and redemptions are limited so users cannot exit **locked** value as assets:

- `maxWithdraw` / `maxRedeem` cap by **`availableBalance(owner)`** (converted to shares where needed) and by the parent ERC-4626 caps.

Users must **`unlockStake`** (via engine) or be **`slashStake`**’d to reduce locked amounts before that value becomes withdrawable.

---

## Upgrades

UUPS pattern: only **`DEFAULT_ADMIN_ROLE`** may authorize upgrades (`_authorizeUpgrade`). Always validate new implementations with your tooling (e.g. OpenZeppelin Upgrades) and follow a timelock / multisig process in production.

---

## Errors (custom)

| Error | When |
|-------|------|
| `InsufficientAvailableBalance(required, available)` | `lockStake` exceeds available |
| `InsufficientLockedAmount(required, locked)` | `unlockStake` / `slashStake` exceeds locked |
| `TransferExceedsUnlockedShares()` | Transfer would leave sender with fewer shares than needed to cover locked stake |
| `DepositTooRecent(requiredMinAge, actualAge)` | `minDepositAge` not satisfied |
| `MinDepositAgeTooHigh(requested, max)` | Admin set age above `MAX_MIN_DEPOSIT_AGE` |
| `ZeroAmount()` | Zero amount on lock/unlock/slash |
| `ZeroAddress()` | `initialize` with zero asset or admin |

OpenZeppelin **`AccessControlUnauthorizedAccount`** may surface on role-gated calls. ERC-4626 **`ERC4626ExceededMaxWithdraw`** / **`ERC4626ExceededMaxRedeem`** (etc.) apply when callers exceed `max*` limits.

---

## Events

- `StakeLocked(user, amount)`
- `StakeUnlocked(user, amount)`
- `StakeSlashed(user, amount)`
- `MinDepositAgeUpdated(newAge)`

Standard ERC-4626 `Deposit`, `Withdraw`, and ERC-20 `Transfer` events also apply.

---

## Integrator checklist

1. Treat the vault as **ERC-4626**: use previews and `max*` functions.
2. If **`minDepositAge > 0`**, expect **delayed** `lockStake`, transfers, and full withdrawals after any **deposit, mint, or inbound transfer** to the user.
3. **Locked stake** reduces **`maxWithdraw` / `maxRedeem`**; unlocking is **off-chain policy + `ENGINE_ROLE`** on-chain.
4. **Slashing** burns shares; indexers should track `StakeSlashed` and share supply, not only `lockedAmount`.
5. Deploy behind **ERC-1967 proxy**; call **`initialize(asset, admin)`** once; never rely on unproxied implementation for user funds.

---

## Further reading

- [OpenZeppelin ERC-4626](https://docs.openzeppelin.com/contracts/erc4626)
- [Foundry book](https://book.getfoundry.sh/) — build, test, and deploy in this repo

Deployed addresses and Makefile targets are summarized in the repository [README](../README.md).
