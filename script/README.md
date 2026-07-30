# Scripts

Foundry scripts for deploying and upgrading `SapienVault`. The vault is a UUPS
(ERC-1967) proxy: the proxy address is permanent, and an upgrade swaps the
implementation behind it. Only `DEFAULT_ADMIN_ROLE` can authorize an upgrade
(`_authorizeUpgrade`).

| Script | Purpose |
|--------|---------|
| `DeployBase.s.sol` | **Canonical** first-time deploy of impl + proxy (`initialize`); env-driven (`SAPIEN_TOKEN`, `ADMIN`) |
| `DeployBaseSepolia.s.sol` | Base Sepolia deploy (hardcoded testnet token + dev Safe) |
| `UpgradeVault.s.sol` | Upgrade a live proxy to a new implementation (`upgradeToAndCall` + `initializeV2`), with post-upgrade verification |
| `archive/DeployBaseMainnet.s.sol` | **Archived, reverts on run** — original mainnet deploy with hardcoded admin; the vault is already live (SEC-3) |

Live addresses are in the repo [README](../README.md). Design and upgrade
background: [docs/SapienVault.md](../docs/SapienVault.md#upgrades).

---

## Upgrading a live vault

### Prerequisites

- The current implementation on-chain is **V1** (the global-timer build). This
  upgrade installs the SAP-1 tranche model **and** the S2 role-management rules
  in one step via `initializeV2(admin)`.
- The proxy's `DEFAULT_ADMIN_ROLE` is held by the governance Safe.

### Environment variables

| Var | Required | Meaning |
|-----|----------|---------|
| `VAULT_PROXY` | yes | The ERC-1967 proxy to upgrade |
| `VAULT_ADMIN` | yes | The **current** `DEFAULT_ADMIN_ROLE` holder (Safe). Must already hold the role — `initializeV2` reverts otherwise, so the upgrade calldata cannot install a new admin |
| `BASE_MAINNET_RPC_URL` / `BASE_SEPOLIA_RPC_URL` | yes | Network RPC |
| `DEPLOYER` | yes (Sepolia) | Cast wallet account name used to deploy the new implementation |
| `EXECUTE` | no | `true` to broadcast the upgrade directly (broadcaster must hold the admin role) |
| `VERIFY_ONLY` | no | `true` for read-only post-upgrade verification |

```bash
export VAULT_PROXY=0x...      # proxy address
export VAULT_ADMIN=0x...      # current admin / Safe
export BASE_SEPOLIA_RPC_URL=https://...
export DEPLOYER=sepolia_deployer
```

### Recommended flow (admin is a Safe)

The admin is a multisig, so the script does **not** execute the upgrade. It
deploys the new implementation, verifies it on the explorer, and prints the
`upgradeToAndCall` calldata for the Safe to submit.

```bash
# 1. Deploy the new impl (+ Basescan verification) and print the Safe calldata
make upgrade-sepolia-calldata
```

This prints:

- `New implementation:` — the freshly deployed implementation address.
- `upgradeToAndCall calldata` — submit this from the Safe with **target = the
  proxy** (`VAULT_PROXY`), value `0`.

```bash
# 2. In the Safe UI: new transaction → contract interaction → target = VAULT_PROXY,
#    paste the calldata, collect signatures, execute.

# 3. Confirm the upgrade landed (read-only; no admin key needed).
make upgrade-sepolia-verify
```

Verification asserts: the ERC-7201 storage slot matches (`verifyStorageLocation`),
`defaultAdmin()` / `owner()` equal `VAULT_ADMIN`, and `minDepositAge() > 0`
(SAP-5 seeded). It reverts the script on any mismatch.

### Direct execution (admin is an EOA / test net)

If the broadcasting account holds the admin role:

```bash
make upgrade-sepolia-execute       # or: make upgrade-base-execute
```

Sepolia has the same three targets: `upgrade-sepolia-calldata`,
`upgrade-sepolia-execute`, `upgrade-sepolia-verify`.

> Running the script by hand instead of via `make`:
> ```bash
> # deploy impl + print calldata
> forge script script/UpgradeVault.s.sol:UpgradeVault --rpc-url $BASE_SEPOLIA_RPC_URL --account $DEPLOYER --broadcast --verify
> # execute
> EXECUTE=true forge script script/UpgradeVault.s.sol:UpgradeVault --rpc-url $BASE_SEPOLIA_RPC_URL --account $DEPLOYER --broadcast --verify
> # verify only
> VERIFY_ONLY=true forge script script/UpgradeVault.s.sol:UpgradeVault --rpc-url $BASE_SEPOLIA_RPC_URL
> ```

---

## What `initializeV2(admin)` does

`reinitializer(2)`, idempotent, no batch migration:

- **Role rules (S2):** seeds the `AccessControlDefaultAdminRules` storage
  (`defaultAdmin`, transfer delay) to `admin`. The V1 vault granted the admin
  role through plain `AccessControl`, so this is required for `defaultAdmin()` /
  `owner()` and the single-admin invariant to be consistent.
- **MEV guard (SAP-5):** if `minDepositAge` was never configured on V1, seeds
  `DEFAULT_MIN_DEPOSIT_AGE` (1 day). An existing admin value is preserved.
- **Tranche model (SAP-1):** each user's pre-upgrade balance and age migrate
  **lazily** the first time their account is touched after the upgrade — no
  batch migration call is needed.

## Breaking changes in this upgrade

Update indexers/integrators before executing:

- **ABI rename:** `getUserStakeBalance(address)` → `assetsOf(address)`.
- **Event signature:** `MinDepositAgeUpdated(uint256)` →
  `MinDepositAgeUpdated(uint256 oldAge, uint256 newAge)`; only emitted on a change.
- **Admin role:** transfers are now two-step + time-locked
  (`beginDefaultAdminTransfer` / `acceptDefaultAdminTransfer`); renouncing
  `DEFAULT_ADMIN_ROLE` is disabled (`DefaultAdminRenounceDisabled`).

## Explorer verification

The deploy and upgrade targets pass `--verify`, which submits a standard-JSON
input pruned to the target contract's own imports. Three config requirements make
that reproduce the deployed bytecode:

- **`via_ir = false`** in `foundry.toml`. Under via-IR, solc's output for a
  contract depends on every other file in the compilation unit — `forge script`
  compiles the whole project (src + OpenZeppelin + forge-std + scripts + tests),
  so the explorer's recompile of the pruned input differs from what was deployed
  and reports

  ```
  Fail - Unable to verify. Compiled contract deployment bytecode does NOT match
  the transaction deployment bytecode.
  ```

  even though the metadata hash matches. Sourcify names this
  `extra_file_input_bug`
  ([argotorg/sourcify#618](https://github.com/argotorg/sourcify/issues/618),
  [ethereum/solidity#14829](https://github.com/ethereum/solidity/issues/14829)).
  Legacy codegen is per-contract, so the pruned input verifies as-is — and
  Basescan lists only `src/` + OpenZeppelin.
- **`evm_version` is pinned.** Foundry defaults to `osaka`, which Base has not
  activated; targeting it risks unsupported opcodes and is not reproducible by
  explorers.
- **`[etherscan]` uses API V2** (`api.etherscan.io/v2/api?chainid=…`). The old
  per-chain `api*.basescan.org` V1 endpoints are decommissioned, and the
  `chainid` must be in the URL query string. One `ETHERSCAN_API_KEY` covers
  Basescan.

To verify an implementation deployed earlier, use the same commit and build
settings it was deployed from:

```bash
export ETHERSCAN_API_KEY=...
forge verify-contract <impl> src/SapienVault.sol:SapienVault \
  --chain-id 84532 --watch
```

---

## Safety notes

- Always validate the new implementation with upgrade tooling (e.g. OpenZeppelin
  Upgrades storage-layout checks) before broadcasting.
- Never point the proxy at an unverified implementation; run
  `make upgrade-*-verify` after every upgrade.
- The implementation's constructor calls `_disableInitializers()`; never call
  `initialize` on the implementation directly.
