# SapienVault

ERC-4626 vault for SAPIEN token staking with typed lock categories. Holds user funds and implements contributor locks, validator capacity and share-burn slashing. Slashing burns shares, redistributing underlying assets to all remaining stakers.

### Base mainnet

**Sapien Vault**:    `0x60Bf63729f688287a450299962b36Cef0aFfaa42`
**Sapien Token**:    `0xC729777d0470F30612B1564Fd96E8Dd26f5814E3`
**USDC**:            `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`

### Base sepolia

**Sapien Vault**:    `0x58E72Fa7fb92B100f2c652377465EEEe2642544C`
**Sapien Token**:    `0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6`
**USDC**:            `0x4d4394119CF096FbdbbD3Efb00d204c891C6Cd05`

## Documentation

Full vault design, roles, ERC-4626 behavior, locking/slashing, and integration notes: **[docs/SapienVault.md](docs/SapienVault.md)**.

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
