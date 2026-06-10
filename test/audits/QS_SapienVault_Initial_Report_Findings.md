# SapienVault — Quantstamp Audit Findings TODO

Source: `audits/QS_SapienVault_Initial_Report.pdf` (Quantstamp, DRAFT)
Timeline: 2026-05-18 → 2026-05-20 · Commit: `#e9ecac2`
Total findings: 7 (1 High, 2 Medium, 1 Low, 3 Informational). SAP-1/SAP-2/SAP-3/SAP-5/SAP-6 **Resolved**, SAP-4 **Mitigated**, SAP-7 **Documented**.

## Summary

| ID | Description | Severity | Status |
|------|-------------|----------|--------|
| SAP-1 | Shares Transfer Griefing Vector | High | Resolved (per-stake tranche refactor) |
| SAP-2 | Partial Slashes Are Self-Redistributed Back to the Slashed Holder | Medium | Resolved (dilution-compensated burn) |
| SAP-3 | MEV: Protection Bypass via Delegate Deposits | Medium | Resolved (all mints age the receiver) |
| SAP-4 | MEV: Fresh Deposits Capture Slash Redistribution | Low | Mitigated (fresh shares immature in slash window) |
| SAP-5 | minDepositAge Is Not Initialized | Informational | Resolved (seeded at init/upgrade) |
| SAP-6 | Global Token Age Requirement May Punish Active Users | Informational | Resolved (cooldown is per-tranche) |
| SAP-7 | MEV Guard May Break Composability | Informational | Documented (receive-side improved; same-tx deposit+forward still limited) |

---

## Findings

- [x] **SAP-1 — Shares Transfer Griefing Vector** · High · Resolved
  - File(s): `SapienVault.sol`, `Types.sol`
  - Problem: The MEV-protection cooldown applies globally to a user's entire token balance and is triggered by incoming share transfers, not just self-deposits. An attacker can repeatedly send dust shares so the recipient never passes the deposit-age check, locking that account out of staking, transferring, and redeeming/withdrawing.
  - Recommendation: Refactor the MEV protection to track individual stakes/tranches rather than a single global age on the full balance. Each stake enforces a minimum `stakeAmount`, a `startDate`, and optionally an earliest withdrawable `maturityDate`; mature stakes squash into an aggregated `stakedBalance`. This also lets users withdraw unused assets immediately.
  - Resolution: Replaced the per-user global `lastDepositTimestamp` with per-user share tranches `{shares, startTime}` plus an aggregated `matureShares` bucket (`_settle`/`_pushImmature`/`_matureSharesView`). The cooldown now binds to the specific shares that arrive; transfers move only matured shares and the recipient receives them as matured (age travels with the shares), so an inbound dust transfer can no longer freeze a victim. A per-user tranche cap (`MAX_IMMATURE_TRANCHES`) bounds maturation gas. Admin-configurable `minTrancheSize` rejects sub-threshold immature cohorts when `minDepositAge > 0`. Shipped as a UUPS upgrade with lazy per-user migration (`initializeV2`). Tests: `test/audits/SAP1_SharesTransferGriefing.t.sol`, `test/SapienVaultMigration.t.sol`.

- [x] **SAP-2 — Partial Slashes Are Self-Redistributed Back to the Slashed Holder** · Medium · Resolved
  - File(s): `src/SapienVault.sol`
  - Problem: `slashStake` reduced `lockedAmount` and burned `previewWithdraw(amount)` shares, but no SAPIEN leaves the vault. Because OZ's `totalAssets()` is the raw token balance (`ERC4626Upgradeable.sol:138-140`), the slashed value stays in the pool and lifts the exchange rate for all remaining shares — including those still held by the slashed user, who could redeem ~their full deposit.
  - Exploit scenario:
    - User deposits 1000 SAPIEN into an empty/attacker-dominated vault.
    - After `minDepositAge`, user locks 400 via `lockStake`.
    - Engine honestly calls `slashStake(user, 400e18)`.
    - Shares burn but 400 SAPIEN stays in `totalAssets()`.
    - User's remaining shares absorb the rate bump and redeem ~the full deposit.
  - Recommendation: Change slashing so the intended damage is the input parameter; the function should compute the dilution effect and burn up to that amount of shares from the user, if available.
  - Resolution: `slashStake` now treats `amount` as the *intended net damage* and sizes the burn to compensate for the exchange-rate dilution via `_slashShareAmount`. With virtual pool totals `A = totalAssets()+1`, `S = totalSupply()+10^offset`, balance `b`, and `s_D = convertToShares(amount)`, it burns `x = s_D·S/(S + s_D − b)` (rounded down, capped at `b`) — the share quantity whose removal lowers `convertToAssets(b)` by exactly `amount`, so the recaptured value flows to the *other* stakers instead of back to the slashed user. Rounding down keeps `convertToAssets(balanceOf) >= lockedAmount` intact; the `_update` burn branch spills into immature tranches when the burn exceeds matured shares; a sub-share slash reverts `ZeroShareSlash`. A new `SharesSlashed(user, shares)` event reports the exact burn. Per the operating model there is never a sole staker, so the slash is always effective. Tests: `test/audits/SAP2_PartialSlashSelfRedistribution.t.sol` (now proving the resolution, incl. a two-staker fuzz), plus updated slash tests in `test/SapienVault.t.sol`.

- [x] **SAP-3 — MEV: Protection Bypass via Delegate Deposits** · Medium · Resolved
  - File(s): `src/SapienVault.sol`
  - Problem: `_deposit()` refreshes the deposit timestamp only when `caller == receiver` (`src/SapienVault.sol:119-123`), so a helper can mint shares to an aged receiver without resetting their cooldown. Minted shares enter via `_update(address(0), receiver, shares)`, which skips the wallet-to-wallet timestamp branch — letting users immediately use deposited tokens to lock stakes or grief via transfers.
  - Exploit scenario:
    - Malicious user sets up contract A as passthrough and owner of vault shares.
    - Deposits routed via custom contract B to circumvent the self-deposit check.
    - A immediately uses the tokens since A's `lastDepositTimestamp` is never updated.
    - Both contracts can be set up and executed atomically, enabling MEV exploits.
  - Recommendation: Ensure MEV protection holds equally for all balance-modifying vectors. Consider the SAP-1 staking refactor to avoid introducing a new griefing vector.
  - Resolution: Tranche creation moved into the `_update` mint branch (`from == 0`), which fires for every mint regardless of caller, so delegate/third-party deposits land as immature shares for the receiver. The original timestamp-stamping `_deposit` override was removed; a slimmer `_deposit` override was later re-introduced solely to enforce `minTrancheSize` on new immature cohorts (it does no age accounting). Test: `test/audits/SAP3_MevBypassViaDelegateDeposits.t.sol`.

- [x] **SAP-4 — MEV: Fresh Deposits Capture Slash Redistribution** · Low · Mitigated
  - File(s): `src/SapienVault.sol`
  - Problem: If a slash is pending or predictable, a MEV operator can deposit to capture the resulting exchange-rate increase. The SAP-3 bypass even allows immediate redeems. Even without the bypass, share value is strictly increasing over time, so the only attacker risk is opportunity cost of locked assets.
  - Exploit scenario:
    - `minDepositAge` is nonzero; attacker controls a helper plus an aged/timestamp-free receiver.
    - A slash is visible, predictable, or orderable in the same block.
    - Helper calls `deposit(A, receiver)` before the slash; receiver gets shares without a fresh timestamp.
    - Engine honestly slashes another account, lifting the exchange rate.
    - Receiver immediately redeems, capturing redistribution that should have gone to incumbents.
  - Recommendation: Delay minting of shares on deposits. Link buying/redeeming of shares to locked stakes so only active stakes profit from redistribution. Users supply assets via a new entrypoint, then later deposit/mint (equivalent to locking a stake); override internal ERC-4626 so share value is not derived from the vault's total asset balance.
  - Resolution (partial): The SAP-1 tranche refactor closes the SAP-3 delegate path and makes all freshly-deposited shares immature, so they cannot be redeemed or transferred in the slash window — flash-positioned fresh capital can no longer capture redistribution. Capture now requires aged, at-risk capital (the incumbent reward the design intends). The deeper "share value not derived from total assets" redesign (which also addresses SAP-2) remains out of scope. Test: `test/audits/SAP4_FreshDepositsCaptureSlashRedistribution.t.sol`.

- [x] **SAP-5 — minDepositAge Is Not Initialized** · Informational · Resolved
  - File(s): `SapienVault.sol`
  - Problem: `minDepositAge` is admin-configurable but not initialized at setup, so it defaults to 0 and the MEV protection is initially disabled.
  - Recommendation: Set `minDepositAge` to a constant or `initialize()` parameter, and emit a `MinDepositAgeUpdated` event.
  - Resolution: Added the `DEFAULT_MIN_DEPOSIT_AGE = 1 days` constant and seed it in `initialize` (fresh deployments) and `initializeV2` (the live UUPS upgrade path, guarded on `minDepositAge == 0` so a pre-upgrade admin value is preserved), each emitting `MinDepositAgeUpdated`. The MEV guard is now active out of the box and admin-retunable within `[0, MAX_MIN_DEPOSIT_AGE]`. Test: `test/audits/SAP5_MinDepositAgeNotInitialized.t.sol` (now asserts the seeded default), plus `test_initialize_seedsDefaultMinDepositAge` in `test/SapienVault.t.sol`.

- [x] **SAP-6 — Global Token Age Requirement May Punish Active Users** · Informational · Resolved
  - File(s): `SapienVault.sol`
  - Problem: The cooldown applies to a user's entire balance, blocking redeems of recently unlocked stakes when there is deposit overlap. Active users must carefully schedule low-frequency deposits, and cannot control unstake time since unlock is engine-permissioned.
  - Recommendation: Refactor MEV protection to allow withdraws independently from deposits. The suggested staking refactor (SAP-1) fully mitigates this.
  - Resolution: Per-tranche maturation means a fresh deposit only delays its own cohort; already-matured shares stay withdrawable. Test: `test/audits/SAP6_GlobalTokenAgePunishesActiveUsers.t.sol`.

- [~] **SAP-7 — MEV Guard May Break Composability** · Informational · Documented
  - File(s): `SapienVault.sol`
  - Problem: The cooldown can break ERC-4626 composability by blocking immediate use of deposited/transferred tokens. Routing funds through an intermediary (auto-compounder, router, multi-step zapper) and acting on the shares in the same transaction will revert.
  - Recommendation: Refactor the staking system as suggested (SAP-1), or document this behavior.
  - Resolution: The receive side is improved — an integrator sent matured shares can act on them in the same transaction (age travels with shares). Same-tx deposit-and-forward of freshly-minted shares still reverts (now `TransferExceedsUnlockedShares`), which is the intended MEV guard and is documented. Test: `test/audits/SAP7_MevGuardBreaksComposability.t.sol`.

---

## Auditor Suggestions

- [x] **S1 — Expose Explicit Cooldown State for Users and Integrators** · Resolved
  - File(s): `src/SapienVault.sol`
  - Problem: `lastDepositTimestamp` drives cooldown enforcement but is only used internally (`_hasMetDepositAge` / `_requireDepositAgeMet`). The public surface does not expose the per-user timestamp or remaining cooldown, so when `maxWithdraw(owner) == 0` an integrator cannot distinguish paused, locked, in-cooldown, no-shares, or other caps.
  - Recommendation: Add cooldown read helpers, e.g.
    - `function lastDepositTimestamp(address user) external view returns (uint256);`
    - `function depositAgeStatus(address user) external view returns (bool hasMetAge, uint256 lastTimestamp, uint256 minAge, uint256 remaining);`
    - Emit both old and new values in `MinDepositAgeUpdated` for off-chain monitoring.
  - Resolution: Adapted to the tranche model — there is no longer a single per-user `lastDepositTimestamp`, so the literal getter is moot. Added `depositAgeStatus(user) -> (matured, pending, minAge, nextMaturityRemaining)`, where `nextMaturityRemaining` counts down to the user's oldest still-immature cohort (0 when nothing is pending or the guard is off). This, together with the existing `maturedShares`/`pendingShares`, lets integrators tell a cooldown apart from a pause, a lock, or an empty balance when `maxWithdraw == 0`. `MinDepositAgeUpdated` now carries `(oldAge, newAge)`. Test: `test/audits/S1_ExposeCooldownState.t.sol`.

- [x] **S2 — Improved Role Management** · Resolved
  - File(s): `SapienVault.sol`
  - Recommendation: Switch from `AccessControlUpgradeable` to `AccessControlDefaultAdminRulesUpgradeable` for two-step admin transfers with time locks and strict single-admin enforcement. Also override/disable the ability to renounce ownership.
  - Resolution: `SapienVault` now extends `AccessControlDefaultAdminRulesUpgradeable` (single `DEFAULT_ADMIN_ROLE` holder, two-step time-locked handover via `beginDefaultAdminTransfer`/`acceptDefaultAdminTransfer`, initial delay `DEFAULT_ADMIN_TRANSFER_DELAY = 3 days`). `renounceRole(DEFAULT_ADMIN_ROLE, …)` is hard-disabled (`DefaultAdminRenounceDisabled`) so the vault can never be left ownerless; other roles renounce normally. `initialize` installs the admin via `__AccessControlDefaultAdminRules_init`. Per the "still on V1" deployment state, the migration is folded into the existing `initializeV2(currentAdmin_)` (no V3): it seeds the rules storage to the incumbent admin and reverts unless `currentAdmin_` already holds the role. Tests: `test/audits/S2_ImprovedRoleManagement.t.sol`, `test/SapienVaultMigration.t.sol`.

- [x] **S3 — Code Improvements** · Resolved (a kept by decision)
  - File(s): `SapienVault.sol`, `Types.sol`
  - Recommendations:
    - In `Types.sol`, the `StakeAccount` struct is not strictly needed — use `uint256` directly or store `lastDepositTimestamp` here.
    - Avoid code duplication between `_hasMetDepositAge()` and `_requireDepositAgeMet()`.
    - Avoid code duplication between `maxRedeem()` and `maxWithdraw()`.
    - Rename `getUserStakeBalance()` (it returns total asset value, not staked amount) to avoid a misleading name.
    - `setMinDepositAge()` emits an event even when the new age equals the stored `minDepositAge`.
  - Resolution:
    - (a) **Kept by decision**: `StakeAccount` remains a struct — it is the public return type of `getStakeAccount`, so collapsing it to a bare `uint256` is an ABI break for zero benefit.
    - (b) **Already resolved** by the SAP-1 refactor: `_hasMetDepositAge`/`_requireDepositAgeMet` no longer exist (replaced by tranche settling).
    - (c) `maxRedeem`, `maxWithdraw`, and `availableBalance` now share one `_availableMatureShares(owner)` helper (mature shares minus the rounded-up locked reservation).
    - (d) `getUserStakeBalance` renamed to `assetsOf` (the asset value of the user's whole share balance, `convertToAssets(balanceOf)`).
    - (e) `setMinDepositAge` returns early on a no-op (new age equals stored), so it neither writes nor emits.
    - Test: `test/audits/S3_CodeImprovements.t.sol`.

---

## Operational Considerations

- [x] Tighten third-party deposit documentation: resolved alongside SAP-3 — every `deposit`/`mint` now ages the receiver (the mint branch of `_update` records an immature tranche regardless of caller), and `docs/SapienVault.md` reflects this.
- [x] Pooled adapters need their own accounting: a shared adapter address can have all vault-level exits delayed by a self-deposit, and address-scoped slashing can socialize one pooled user's penalty unless the adapter tracks per-user ownership and slash attribution. Documented in `docs/SapienVault.md` → Operational considerations → "Pooled adapters must keep their own per-user accounting".
- [x] Raw ERC-4626 calls should not be slippage-blind: integrators should reject `previewDeposit == 0`, use min-share checks, and avoid depositing into a zero-supply/positive-assets state. Documented in `docs/SapienVault.md` → Integrator checklist item 5.
- [x] Document asymmetric stake lifecycle: `lockStake` is permissionless (once `minDepositAge` is met), but `unlockStake`/`slashStake` are gated to `ENGINE_ROLE`. Engine liveness (not just honesty) is part of the trust model. Documented in `docs/SapienVault.md` → Operational considerations → "Asymmetric, engine-dependent stake lifecycle".
- [x] Engine and admin keys are part of the security boundary: `ENGINE_ROLE` (slash/unlock) and `DEFAULT_ADMIN_ROLE` (pause, upgrade, role management, `minDepositAge`, ETH rescue) should be held behind multisig quorums and/or hardware wallets. Documented in `docs/SapienVault.md` → Operational considerations → "Privileged keys are part of the security boundary".
