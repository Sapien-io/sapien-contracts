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
   - **`slashStake(user, amount)`** — contribution rejected as low-quality, dishonest, or otherwise penalty-worthy; shares are burned so the user loses exactly `amount` of value, which redistributes to the remaining honest stakers (see [Slashing](#slashing-sap-2) for the dilution-compensated burn).
3. The contributor `withdraw`s whatever remains.

In short: the **vault** is the on-chain custodian and slashing tool; the **engine** is the off-chain authority that decides when slashing happens. Trust in the engine is concentrated in `ENGINE_ROLE` and is therefore the protocol's primary off-chain trust assumption (see [Roles](#roles) and the repository [README](../README.md#roles--trust-assumptions)).

---

## Architecture

| Layer | Contracts |
|-------|-----------|
| Vault logic | `SapienVault` — `ERC4626Upgradeable`, `AccessControlDefaultAdminRulesUpgradeable`, `PausableUpgradeable`, `UUPSUpgradeable` |
| Types | `Types.sol` — `StakeAccount`, `Tranche`, `SapienVaultStorage` (namespaced storage layout) |
| Interface | `ISapienVault` — errors, events, external API |

Custom state (per-user locks, share tranches, `minDepositAge`) lives in **ERC-7201-style namespaced storage** (`SapienVaultStorage`), not in the default OpenZeppelin storage slots, to reduce upgrade collision risk. The namespace string is `"sapien.storage.SapienVault"`. The pure function `verifyStorageLocation()` checks that the derived slot matches the implementation’s hard-coded slot. The tranche-accounting fields are appended to the struct, so the namespaced slot is unchanged across the SAP-1 upgrade.

---

## Roles

| Role | Held by | On-chain capabilities |
|------|---------|-----------------------|
| `DEFAULT_ADMIN_ROLE` | Sapien governance multisig (production) | Grant/revoke other roles, two-step admin handover, `setMinDepositAge`, `setMinTrancheSize`, `pause` / `unpause`, `rescueETH`, UUPS upgrades (`upgradeToAndCall`) |
| `ENGINE_ROLE` | The off-chain **PoQ engine** signing key | `unlockStake`, `slashStake` only |

`ENGINE_ROLE` is the on-chain identity of the off-chain PoQ validation server. The engine never holds user funds directly: it only signs transactions that mutate `lockedAmount` and burn shares. Pause halts both `unlockStake` and `slashStake`, so admin can stop a misbehaving or compromised engine instantly; permanent neutralisation is `revokeRole(ENGINE_ROLE, …)`.

`lockStake` is **not** gated by `ENGINE_ROLE`; the **share holder** calls it themselves to move value from “available” into “locked” within their own position, signalling willingness to be evaluated by the engine.

### Admin role rules (S2)

`DEFAULT_ADMIN_ROLE` is governed by `AccessControlDefaultAdminRulesUpgradeable`, which adds three guarantees on top of plain `AccessControl`:

- **Single admin.** Exactly one address holds `DEFAULT_ADMIN_ROLE` at a time; `grantRole(DEFAULT_ADMIN_ROLE, …)` reverts. `defaultAdmin()` (and the ERC-5313 `owner()`) returns that address.
- **Two-step, time-locked handover.** Rotating the admin is `beginDefaultAdminTransfer(newAdmin)` followed by `acceptDefaultAdminTransfer()` from `newAdmin`, only after `defaultAdminDelay()` (seeded to `DEFAULT_ADMIN_TRANSFER_DELAY` = 3 days, itself retunable via the time-locked `changeDefaultAdminDelay`). A pending transfer can be cancelled before acceptance.
- **Renounce disabled.** `renounceRole(DEFAULT_ADMIN_ROLE, …)` reverts with `DefaultAdminRenounceDisabled` so the vault can never be left ownerless. Other roles (e.g. `ENGINE_ROLE`) renounce normally.

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
- **Available** balance (conceptually): **matured** position in asset terms minus `lockedAmount` — exposed as `availableBalance(user)`. Only shares that have cleared `minDepositAge` count; immature shares are excluded until they age (see below).

Operations:

1. **`lockStake(amount)`** (holder, `whenNotPaused`): moves `amount` from available to locked. Requires `amount <= availableBalance(msg.sender)` (matured, unlocked balance) and a non-zero amount.
2. **`unlockStake(user, amount)`** (`ENGINE_ROLE`): reduces `user`’s `lockedAmount` only (no share mint/burn).
3. **`slashStake(user, amount)`** (`ENGINE_ROLE`): reduces `lockedAmount` and **burns** shares so the user's value drops by exactly `amount` (see [Slashing](#slashing-sap-2)). Remaining stakers gain the slashed value on the underlying.

<a id="slashing-sap-2"></a>
### Slashing (SAP-2)

Because a slash burns shares without moving any SAPIEN out of the vault, `totalAssets()` is unchanged and the surviving shares appreciate. A naive burn of `convertToShares(amount)` would let the slashed user **recapture** part of the penalty through that exchange-rate bump (and recapture ~all of it if they dominated the pool) — the original SAP-2 finding.

To neutralise this, the burn is **dilution-compensated**. With virtual pool totals `A = totalAssets()+1`, `S = totalSupply()+10^offset`, user balance `b`, and `s_D = convertToShares(amount)`:

```
sharesBurned = s_D * S / (S + s_D - b)   (rounded down, capped at b)
```

This is the share quantity whose removal lowers `convertToAssets(b)` by exactly `amount`, so the slashed user bears the full intended damage and the recaptured value flows to the **other** stakers. Rounding is **down** so realized damage never exceeds `amount`, keeping the post-slash invariant `convertToAssets(balanceOf(user)) >= lockedAmount` intact. The denominator is always positive (the inflation-mitigation virtual shares guarantee `S > totalSupply() >= b`). A slash worth less than one share rounds to zero and reverts `ZeroShareSlash`. When the burn exceeds the user's matured shares it spills into their immature tranches (FIFO), so the full penalty is always realizable.

---

## Minimum deposit age (`minDepositAge`)

Configurable by admin up to **`MAX_MIN_DEPOSIT_AGE` (7 days)**.

The cooldown is enforced **per share cohort (tranche)**, not on a user’s whole balance (SAP-1 refactor). Each address tracks:

- **immature tranches** — `{shares, startTime}` cohorts still inside the `minDepositAge` window, and
- an aggregated **`matureShares`** bucket — shares that have cleared the window and are freely actionable.

When `minDepositAge > 0`:

- On every **`deposit` / `mint`** (by **any** caller, including third-party/delegate deposits), the minted shares are recorded as a new immature tranche for the receiver. This closes the delegate-deposit bypass (SAP-3).
- A cohort **matures** once `block.timestamp - startTime >= minDepositAge`, after which it folds into `matureShares`.
- **`lockStake`**, **outgoing transfers**, **`maxWithdraw`**, and **`maxRedeem`** act only on **matured, unlocked** shares.
- **Peer-to-peer transfers** move only matured shares, and the recipient receives them as matured — **age travels with the shares**. A transfer therefore cannot reset a recipient’s cooldown, so the previous dust-transfer griefing vector is gone (SAP-1). It also means already-matured funds are never re-frozen by a later deposit (SAP-6).
- The number of concurrent immature tranches per user is capped (`MAX_IMMATURE_TRANCHES`); at the cap a new inflow coalesces into the newest cohort, bounding the gas of maturation so dust deposits cannot grief.
- **`minTrancheSize`** (asset terms, admin-configurable, default `0` = disabled) rejects deposits/mints that would record an immature cohort below the threshold when `minDepositAge > 0`. This blocks dust-deposit griefing without affecting small deposits when the MEV guard is off.

`maturedShares(user)` and `pendingShares(user)` expose the split (`matured + pending == balanceOf`). For a single call that also reports the configured `minAge` and the seconds until the user's next cohort matures, use **`depositAgeStatus(user)`** → `(matured, pending, minAge, nextMaturityRemaining)` (S1). This lets integrators tell a cooldown apart from a pause, a lock, or an empty balance when `maxWithdraw(user) == 0`.

If `minDepositAge == 0`, deposits are immediately mature and the time checks are effectively disabled.

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

- `maxWithdraw` / `maxRedeem` cap by the owner’s **matured, unlocked** balance (converted to shares where needed) and by the parent ERC-4626 caps. Recently-deposited (immature) shares are excluded until they age, but already-matured shares stay withdrawable regardless of later deposits.

Users must **`unlockStake`** (via engine) or be **`slashStake`**’d to reduce locked amounts before that value becomes withdrawable.

---

## Upgrades

UUPS pattern: only **`DEFAULT_ADMIN_ROLE`** may authorize upgrades (`_authorizeUpgrade`). Always validate new implementations with your tooling (e.g. OpenZeppelin Upgrades) and follow a timelock / multisig process in production.

The SAP-1 tranche + S2 role-rules upgrade is applied via `upgradeToAndCall(newImpl, initializeV2(currentAdmin))` (see `script/UpgradeVault.s.sol`, env `VAULT_ADMIN`). `initializeV2` is a `reinitializer(2)` that:

- migrates each user's pre-upgrade balance and age **lazily** into the tranche model the first time their account is touched after the upgrade (a `0` legacy timestamp migrates as fully matured) — no batch migration required; and
- seeds the `AccessControlDefaultAdminRules` storage (`defaultAdmin`, delay) to `currentAdmin`, which **must already hold** `DEFAULT_ADMIN_ROLE` on the live vault, so the upgrade calldata can only bless the incumbent admin.

---

## Errors (custom)

| Error | When |
|-------|------|
| `InsufficientAvailableBalance(required, available)` | `lockStake` exceeds available |
| `InsufficientLockedAmount(required, locked)` | `unlockStake` / `slashStake` exceeds locked |
| `TransferExceedsUnlockedShares()` | Transfer exceeds the sender's matured, unlocked shares (covers both locked stake and not-yet-matured shares) |
| `MinDepositAgeTooHigh(requested, max)` | Admin set age above `MAX_MIN_DEPOSIT_AGE` |
| `ZeroAmount()` | Zero amount on lock/unlock/slash |
| `ZeroShareSlash()` | Slash amount rounds to zero shares (below one share's value) |
| `ZeroAddress()` | `initialize` with zero asset/admin, or `initializeV2` with a non-admin `currentAdmin_` |
| `DefaultAdminRenounceDisabled()` | Attempt to renounce `DEFAULT_ADMIN_ROLE` (S2) |

OpenZeppelin **`AccessControlUnauthorizedAccount`** may surface on role-gated calls. ERC-4626 **`ERC4626ExceededMaxWithdraw`** / **`ERC4626ExceededMaxRedeem`** (etc.) apply when callers exceed `max*` limits.

---

## Events

- `StakeLocked(user, amount)`
- `StakeUnlocked(user, amount)`
- `StakeSlashed(user, amount)` — intended net asset damage
- `SharesSlashed(user, shares)` — exact shares burned (exceeds the naive `amount`-equivalent; see [Slashing](#slashing-sap-2))
- `MinDepositAgeUpdated(oldAge, newAge)` — carries both values; only emitted on an actual change (S1, S3)
- `MinTrancheSizeUpdated(newSize)`

Standard ERC-4626 `Deposit`, `Withdraw`, and ERC-20 `Transfer` events also apply, as do the `AccessControlDefaultAdminRules` admin-transfer/delay events (S2).

---

## Integrator checklist

1. Treat the vault as **ERC-4626**: use previews and `max*` functions.
2. If **`minDepositAge > 0`**, expect freshly **deposited/minted** shares to be **delayed** for `lockStake`, transfers, and withdrawals until they mature; already-matured shares (including matured shares received via transfer) are actionable immediately. Use `maturedShares` / `pendingShares` (or `depositAgeStatus` for the full split plus time-to-maturity) to inspect the state.
3. **Locked stake** reduces **`maxWithdraw` / `maxRedeem`**; unlocking is **off-chain policy + `ENGINE_ROLE`** on-chain.
4. **Slashing** burns shares (more than the naive `amount`-equivalent, by design — SAP-2); indexers should track `StakeSlashed`/`SharesSlashed` and share supply, not only `lockedAmount`.
5. Deploy behind **ERC-1967 proxy**; call **`initialize(asset, admin)`** once; never rely on unproxied implementation for user funds.

---

## Further reading

- [OpenZeppelin ERC-4626](https://docs.openzeppelin.com/contracts/erc4626)
- [Foundry book](https://book.getfoundry.sh/) — build, test, and deploy in this repo

Deployed addresses and Makefile targets are summarized in the repository [README](../README.md).
