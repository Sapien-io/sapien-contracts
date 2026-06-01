# SapienVault — Quantstamp Audit Findings TODO

Source: `audits/QS_SapienVault_Initial_Report.pdf` (Quantstamp, DRAFT)
Timeline: 2026-05-18 → 2026-05-20 · Commit: `#e9ecac2`
Total findings: 7 (1 High, 2 Medium, 1 Low, 3 Informational). SAP-1/SAP-3/SAP-6 **Resolved**, SAP-4 **Mitigated**, SAP-7 **Documented** by the tranche refactor; SAP-2/SAP-5 **Unresolved**.

## Summary

| ID | Description | Severity | Status |
|------|-------------|----------|--------|
| SAP-1 | Shares Transfer Griefing Vector | High | Resolved (per-stake tranche refactor) |
| SAP-2 | Partial Slashes Are Self-Redistributed Back to the Slashed Holder | Medium | Unresolved |
| SAP-3 | MEV: Protection Bypass via Delegate Deposits | Medium | Resolved (all mints age the receiver) |
| SAP-4 | MEV: Fresh Deposits Capture Slash Redistribution | Low | Mitigated (fresh shares immature in slash window) |
| SAP-5 | minDepositAge Is Not Initialized | Informational | Unresolved |
| SAP-6 | Global Token Age Requirement May Punish Active Users | Informational | Resolved (cooldown is per-tranche) |
| SAP-7 | MEV Guard May Break Composability | Informational | Documented (receive-side improved; same-tx deposit+forward still limited) |

---

## Findings

- [x] **SAP-1 — Shares Transfer Griefing Vector** · High · Resolved
  - File(s): `SapienVault.sol`, `Types.sol`
  - Problem: The MEV-protection cooldown applies globally to a user's entire token balance and is triggered by incoming share transfers, not just self-deposits. An attacker can repeatedly send dust shares so the recipient never passes the deposit-age check, locking that account out of staking, transferring, and redeeming/withdrawing.
  - Recommendation: Refactor the MEV protection to track individual stakes/tranches rather than a single global age on the full balance. Each stake enforces a minimum `stakeAmount`, a `startDate`, and optionally an earliest withdrawable `maturityDate`; mature stakes squash into an aggregated `stakedBalance`. This also lets users withdraw unused assets immediately.
  - Resolution: Replaced the per-user global `lastDepositTimestamp` with per-user share tranches `{shares, startTime}` plus an aggregated `matureShares` bucket (`_settle`/`_pushImmature`/`_matureSharesView`). The cooldown now binds to the specific shares that arrive; transfers move only matured shares and the recipient receives them as matured (age travels with the shares), so an inbound dust transfer can no longer freeze a victim. A per-user tranche cap (`MAX_IMMATURE_TRANCHES`) bounds maturation gas. Shipped as a UUPS upgrade with lazy per-user migration (`initializeV2`). Tests: `test/audits/SAP1_SharesTransferGriefing.t.sol`, `test/SapienVaultMigration.t.sol`.

- [ ] **SAP-2 — Partial Slashes Are Self-Redistributed Back to the Slashed Holder** · Medium · Unresolved
  - File(s): `src/SapienVault.sol`
  - Problem: `slashStake` reduces `lockedAmount` and burns `previewWithdraw(amount)` shares, but no SAPIEN leaves the vault. Because OZ's `totalAssets()` is the raw token balance (`ERC4626Upgradeable.sol:138-140`), the slashed value stays in the pool and lifts the exchange rate for all remaining shares — including those still held by the slashed user, who can redeem ~their full deposit.
  - Exploit scenario:
    - User deposits 1000 SAPIEN into an empty/attacker-dominated vault.
    - After `minDepositAge`, user locks 400 via `lockStake`.
    - Engine honestly calls `slashStake(user, 400e18)`.
    - Shares burn but 400 SAPIEN stays in `totalAssets()`.
    - User's remaining shares absorb the rate bump and redeem ~the full deposit.
  - Recommendation: Change slashing so the intended damage is the input parameter; the function should compute the dilution effect and burn up to that amount of shares from the user, if available.

- [x] **SAP-3 — MEV: Protection Bypass via Delegate Deposits** · Medium · Resolved
  - File(s): `src/SapienVault.sol`
  - Problem: `_deposit()` refreshes the deposit timestamp only when `caller == receiver` (`src/SapienVault.sol:119-123`), so a helper can mint shares to an aged receiver without resetting their cooldown. Minted shares enter via `_update(address(0), receiver, shares)`, which skips the wallet-to-wallet timestamp branch — letting users immediately use deposited tokens to lock stakes or grief via transfers.
  - Exploit scenario:
    - Malicious user sets up contract A as passthrough and owner of vault shares.
    - Deposits routed via custom contract B to circumvent the self-deposit check.
    - A immediately uses the tokens since A's `lastDepositTimestamp` is never updated.
    - Both contracts can be set up and executed atomically, enabling MEV exploits.
  - Recommendation: Ensure MEV protection holds equally for all balance-modifying vectors. Consider the SAP-1 staking refactor to avoid introducing a new griefing vector.
  - Resolution: Tranche creation moved into the `_update` mint branch (`from == 0`), which fires for every mint regardless of caller, so delegate/third-party deposits land as immature shares for the receiver. The `_deposit` override was removed. Test: `test/audits/SAP3_MevBypassViaDelegateDeposits.t.sol`.

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

- [ ] **SAP-5 — minDepositAge Is Not Initialized** · Informational · Unresolved
  - File(s): `SapienVault.sol`
  - Problem: `minDepositAge` is admin-configurable but not initialized at setup, so it defaults to 0 and the MEV protection is initially disabled.
  - Recommendation: Set `minDepositAge` to a constant or `initialize()` parameter, and emit a `MinDepositAgeUpdated` event.

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

- [ ] **S1 — Expose Explicit Cooldown State for Users and Integrators** · Unresolved
  - File(s): `src/SapienVault.sol`
  - Problem: `lastDepositTimestamp` drives cooldown enforcement but is only used internally (`_hasMetDepositAge` / `_requireDepositAgeMet`). The public surface does not expose the per-user timestamp or remaining cooldown, so when `maxWithdraw(owner) == 0` an integrator cannot distinguish paused, locked, in-cooldown, no-shares, or other caps.
  - Recommendation: Add cooldown read helpers, e.g.
    - `function lastDepositTimestamp(address user) external view returns (uint256);`
    - `function depositAgeStatus(address user) external view returns (bool hasMetAge, uint256 lastTimestamp, uint256 minAge, uint256 remaining);`
    - Emit both old and new values in `MinDepositAgeUpdated` for off-chain monitoring.

- [ ] **S2 — Improved Role Management** · Unresolved
  - File(s): `SapienVault.sol`
  - Recommendation: Switch from `AccessControlUpgradeable` to `AccessControlDefaultAdminRulesUpgradeable` for two-step admin transfers with time locks and strict single-admin enforcement. Also override/disable the ability to renounce ownership.

- [ ] **S3 — Code Improvements** · Unresolved
  - File(s): `SapienVault.sol`, `Types.sol`
  - Recommendations:
    - In `Types.sol`, the `StakeAccount` struct is not strictly needed — use `uint256` directly or store `lastDepositTimestamp` here.
    - Avoid code duplication between `_hasMetDepositAge()` and `_requireDepositAgeMet()`.
    - Avoid code duplication between `maxRedeem()` and `maxWithdraw()`.
    - Rename `getUserStakeBalance()` (it returns total asset value, not staked amount) to avoid a misleading name.
    - `setMinDepositAge()` emits an event even when the new age equals the stored `minDepositAge`.

---

## Operational Considerations

- [x] Tighten third-party deposit documentation: resolved alongside SAP-3 — every `deposit`/`mint` now ages the receiver (the mint branch of `_update` records an immature tranche regardless of caller), and `docs/SapienVault.md` reflects this.
- [ ] Pooled adapters need their own accounting: a shared adapter address can have all vault-level exits delayed by a self-deposit, and address-scoped slashing can socialize one pooled user's penalty unless the adapter tracks per-user ownership and slash attribution.
- [ ] Raw ERC-4626 calls should not be slippage-blind: integrators should reject `previewDeposit == 0`, use min-share checks, and avoid depositing into a zero-supply/positive-assets state.
- [ ] Document asymmetric stake lifecycle: `lockStake` is permissionless (once `minDepositAge` is met), but `unlockStake`/`slashStake` are gated to `ENGINE_ROLE`. Engine liveness (not just honesty) is part of the trust model.
- [ ] Engine and admin keys are part of the security boundary: `ENGINE_ROLE` (slash/unlock) and `DEFAULT_ADMIN_ROLE` (pause, upgrade, role management, `minDepositAge`, ETH rescue) should be held behind multisig quorums and/or hardware wallets.
