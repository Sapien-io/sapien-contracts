# SapienVault

ERC-4626 vault for SAPIEN token staking with typed lock categories. Holds user funds and implements contributor locks, validator capacity and share-burn slashing. Slashing burns shares, redistributing underlying assets to all remaining stakers.

| Network | Sapien Vault | Attestation Registry (M4) | Sapien Token | USDC |
|---------|--------------|---------------------------|--------------|------|
| Base mainnet | `0x60Bf63729f688287a450299962b36Cef0aFfaa42` | — | `0xC729777d0470F30612B1564Fd96E8Dd26f5814E3` | `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913` |
| Base Sepolia | `0x58E72Fa7fb92B100f2c652377465EEEe2642544C` | `0x10F1DF5aE4D1A8Aa2d9350F64eA744Fb413d2809` | `0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6` | `0x4d4394119CF096FbdbbD3Efb00d204c891C6Cd05` |

## Documentation

Full vault design, roles, ERC-4626 behavior, locking/slashing, and integration notes: **[docs/SapienVault.md](docs/SapienVault.md)**.

Sepolia lock → review → unlock or slash (Basescan vs `report.stake`): **[docs/SepoliaCollateralLoop.md](docs/SepoliaCollateralLoop.md)**.

M4 proof-report hang-point (separate contract; vault address unchanged): **[docs/AttestationRegistry.md](docs/AttestationRegistry.md)**. `attestation.registry` is `{chain, address, tx}`, not the string `"onchain"`.

Sapien token MiCA whitepaper: **[docs/Sapien_Token_White_Paper_MiCA_v1.pdf](docs/Sapien_Token_White_Paper_MiCA_v1.pdf)**.

## Roles & trust assumptions

The vault concentrates several privileged actions in two roles. Operators
holding either role are explicitly trusted; deploy-time policy SHOULD assign
both to a multisig and route admin actions through a timelock.

| Role | Holder | Privileged actions |
|------|---------------------|--------------------|
| `DEFAULT_ADMIN_ROLE` | Multisig behind a `TimelockController` | `setMinDepositAge`, `pause` / `unpause`, `rescueETH`, `_authorizeUpgrade` (UUPS), `grantRole` / `revokeRole` |
| `ENGINE_ROLE` | Smart Account | `unlockStake`, `slashStake` (burns user shares — irreversible) |

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

make deploy-registry-sepolia-dry  # Predict CREATE2 attestation registry
make deploy-registry-sepolia      # Deploy registry + write deployments/base-sepolia.json
```

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Solidity ^0.8.36
