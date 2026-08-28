# Documentation

- **[SapienVault](SapienVault.md)** — architecture, roles, ERC-4626 behavior, locking/slashing, `minDepositAge`, pause, upgrades, errors, and integration notes.
- **[Sepolia collateral loop](SepoliaCollateralLoop.md)** — lock → review → unlock or slash on Base Sepolia; `report.stake` field mapping and Basescan observer checklist. Mainnet vault/rewards are out of scope.
- **[AttestationRegistry](AttestationRegistry.md)** — M4 proof-report hang-point (separate contract). `attestation.registry` is `{chain, address, tx}`, not `"onchain"`.

For build, test, deploy commands, and chain addresses, see the root [README](../README.md).
