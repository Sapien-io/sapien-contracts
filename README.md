# SapienVault

ERC-4626 vault for SAPIEN token staking with typed lock categories. Holds user funds and implements contributor locks, validator capacity and share-burn slashing. Slashing burns shares, redistributing underlying assets to all remaining stakers.

| Network | Sapien Vault | Sapien Token | USDC |
|---------|--------------|--------------|------|
| Base mainnet | `0x60Bf63729f688287a450299962b36Cef0aFfaa42` | `0xC729777d0470F30612B1564Fd96E8Dd26f5814E3` | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Base Sepolia | `0x58E72Fa7fb92B100f2c652377465EEEe2642544C` | `0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6` | `0x4d4394119CF096FbdbbD3Efb00d204c891C6Cd05` |

## Documentation

Full vault design, roles, ERC-4626 behavior, locking/slashing, and integration notes: **[docs/SapienVault.md](docs/SapienVault.md)**.

## Roles & trust assumptions

The vault concentrates several privileged actions in two roles. Operators
holding either role are explicitly trusted; deploy-time policy SHOULD assign
both to a multisig and route admin actions through a timelock.

| Role | Holder (recommended) | Privileged actions |
|------|---------------------|--------------------|
| `DEFAULT_ADMIN_ROLE` | Multisig behind a `TimelockController` | `setMinDepositAge`, `pause` / `unpause`, `rescueETH`, `_authorizeUpgrade` (UUPS), `grantRole` / `revokeRole` |
| `ENGINE_ROLE` | Multisig or attestation-validated key | `unlockStake`, `slashStake` (burns user shares — irreversible) |

Trust assumptions:

- The admin can deploy a malicious implementation via UUPS at any time. There
  is no on-chain timelock at the contract level; users rely on whatever
  governance wraps `DEFAULT_ADMIN_ROLE`.
- The engine can slash any user up to their `lockedAmount`. Slashes are
  pause-gated (SEC-M-03): pressing pause halts both `unlockStake` and
  `slashStake`. To stop a compromised engine permanently, admin must
  `revokeRole(ENGINE_ROLE, …)`.
- Deposits made on behalf of a third party (caller != receiver) do NOT reset
  the receiver's MEV deposit-age timer (SEC-M-01). Wallet-to-wallet share
  transfers DO reset the recipient's timer; this is a known griefing trade-off
  preferred over the alternative of allowing instant lock bypass via sybil
  share transfers.
- Asset is assumed to be a non-fee, non-rebasing ERC-20 (USDC on Base in
  production deployments). Slashing math assumes a stable asset/share map.

## Build & test

```bash
forge build
forge test
make coverage   # Coverage report
make lint      # Lint
```

## Deploy

### Base Sepolia

```bash
make deploy-sepolia-dry  # Simulate
make deploy-sepolia      # Deploy + verify
```

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity ^0.8.30
