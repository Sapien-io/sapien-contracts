# Contract Upgrades

Both **SapienCore** and **SapienVault** are deployed behind ERC-1967 proxies using the UUPS upgrade pattern. The `upgradeToAndCall` function is gated by `DEFAULT_ADMIN_ROLE`, which is held by a [Safe multisig](https://app.safe.global).

Upgrading is a two-step process:

1. **Deploy** the new implementation contract (any funded EOA).
2. **Execute** the upgrade transaction through the Safe.

## Prerequisites

- Foundry toolchain installed (`forge`, `cast`)
- A keystore account imported: `cast wallet import deployer --interactive`
- Environment variables:
  - `RPC_URL` — Base Sepolia RPC endpoint
  - `ACCOUNT` — keystore account name (e.g. `deployer`)
  - `BASESCAN_API_KEY` — for contract verification on Basescan

## Addresses

| Contract | Proxy | Source |
|---|---|---|
| SapienCore | `0xDFFEc0D8F9DF05bf3DecbdFefD650779D6481077` | `deployments/base-sepolia.json` |
| SapienVault | `0xf0E3C676b277Ce31C2E72Cd473684FA4C8866029` | `deployments/base-sepolia.json` |
| Safe (admin) | `0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC` | |

## Step 1 — Deploy the new implementation

Make your changes in `src/SapienCore.sol` or `src/SapienVault.sol`, then deploy:

```bash
# Dry-run first (no broadcast)
make upgrade-core-dry RPC_URL=$BASE_SEPOLIA_RPC_URL ACCOUNT=deployer

# Deploy for real
make upgrade-core RPC_URL=$BASE_SEPOLIA_RPC_URL ACCOUNT=deployer
```

Replace `upgrade-core` with `upgrade-vault` for vault upgrades.

The script will:
- Deploy the new implementation from the latest source in `src/`
- Print the old and new implementation addresses
- Output the exact calldata for the Safe transaction
- Update `deployments/base-sepolia.json` with the new implementation address

Example output:

```
=== SapienCore Upgrade ===
Proxy:               0xDFFEc0D8F9DF05bf3DecbdFefD650779D6481077
Old implementation:  0x5800578781440999EF366f19607DBC1451952EFB
New implementation:  0x1234...abcd

============================================================
  SAFE TRANSACTION - paste into app.safe.global
============================================================

  To:     0xDFFEc0D8F9DF05bf3DecbdFefD650779D6481077
  Value:  0
  Data:   0x4f1ef286000000000000...

============================================================
```

## Step 2 — Execute via Safe

1. Go to [app.safe.global](https://app.safe.global) and open the Safe at `0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC`.
2. Click **New transaction > Transaction Builder**.
3. Fill in the fields from the script output:
   - **To**: the proxy address
   - **Value**: `0`
   - **Data**: the hex calldata
4. Submit, collect the required signer approvals, and execute.

## Migration data (optional)

If the new implementation includes a `reinitializer` function that should run atomically with the upgrade, encode it and pass it via the `MIGRATION_DATA` env var:

```bash
MIGRATION_DATA=$(cast abi-encode "initializeV2()") \
  make upgrade-core RPC_URL=$BASE_SEPOLIA_RPC_URL ACCOUNT=deployer
```

This gets embedded into the `upgradeToAndCall` calldata so the reinitializer runs in the same transaction as the upgrade.

## Verifying state preservation (fork test)

Before deploying or proposing anything, simulate the upgrade against live on-chain state:

```bash
make upgrade-test RPC_URL=$BASE_SEPOLIA_RPC_URL
```

This forks Base Sepolia at the current block and runs `test/fork/SepoliaForkUpgrade.t.sol`, which:

1. Snapshots all live state (config, roles, balances, pause flag, etc.)
2. Deploys a new implementation from the latest `src/` code
3. Simulates `upgradeToAndCall` as the Safe admin
4. Asserts every field matches the pre-upgrade snapshot

**Tests included:**

| Test | Verifies |
|---|---|
| `test_coreUpgrade_preservesAllState` | Treasury, vault ref, timing params, fee BPS, admin role, pause flag |
| `test_coreUpgrade_preservesProjectState` | Project data + escrow for a specific project |
| `test_coreUpgrade_functionalAfterUpgrade` | View calls still work post-upgrade |
| `test_vaultUpgrade_preservesAllState` | Asset, totalAssets, totalSupply, minDepositAge, roles, pause flag |
| `test_vaultUpgrade_preservesStakerBalance` | Shares, available balance, stake lock fields |
| `test_vaultUpgrade_depositsWorkAfter` | Fresh deposits succeed post-upgrade |
| `test_dualUpgrade_bothPreserveState` | Both contracts upgraded in sequence, all state intact |

To verify a specific project or staker, pass their identifiers as env vars:

```bash
PROJECT_ID=0xabc123... STAKER=0x1234... \
  make upgrade-test RPC_URL=$BASE_SEPOLIA_RPC_URL
```

## How it works

```
         EOA (deployer)                   Safe multisig
              |                                |
  1. Deploy new implementation                 |
     (SapienCore or SapienVault)               |
              |                                |
  2. Script prints calldata  ──────────>  3. Propose tx in Safe UI
                                               |
                                          4. Signers approve
                                               |
                                          5. Execute: proxy.upgradeToAndCall(newImpl, data)
                                               |
                                          6. ERC-1967 slot updated
```

- The proxy address never changes. All state (storage) lives in the proxy.
- ERC-7201 namespaced storage ensures no slot collisions between versions.
- The constructor in each implementation calls `_disableInitializers()` to prevent direct initialization of the implementation contract.
