# AGENTS.md

## Learned User Preferences

- Operate as a Solidity security engineer aiming for a secure, world-class contract and test suite.
- Triage audit/review findings one at a time with explicit per-finding accept/reject decisions ("do this" / "do not do this") before implementing; only build the accepted items.
- Prefer the simplest fix that fully resolves a finding (e.g. a minimum-stake check) first, and only escalate to a larger data-model change when the simple fix is insufficient (e.g. SAP1 ultimately moved to the Quantstamp per-deposit tranche accounting model).
- When implementing from a plan file, follow it exactly, never edit the plan file itself, and use pre-created todos instead of recreating them.
- Import OpenZeppelin via full lib paths (`lib/openzeppelin-contracts/contracts/...` and `lib/openzeppelin-contracts-upgradeable/contracts/...`), not `@openzeppelin` remappings.
- Validate changes with `forge build` and `forge test`; treat Cursor's unresolved `@openzeppelin` import lint errors as false positives since the linter ignores `foundry.toml` remappings.
- After a fix, review whether it introduces new issues and confirm which related fixes belong in the same commit before committing.
- Persist durable learnings to memory when asked ("save to brain").

## Learned Workspace Facts

- `ENGINE_ROLE` is held by an off-chain server that performs PoQ (proof-of-quality) validation; the vault is an asset-locking mechanism used to slash low-quality contributions.
- `SapienVault` is an ERC-4626 tokenized vault (`ERC4626Upgradeable`, shares named "Sapien PoQ Vault" / symbol `vSAPIEN`) with constructor inflation-attack mitigation; users hold transferable vSAPIEN shares that stay subject to transfer, withdraw, lock, pause, and slashing constraints.
- The Vault is custodial (deposited assets sit in the vault contract) and its design is evaluated against Canadian securities law, FINTRAC, and RPAA; a non-custodial/client-controlled vault is considered more favorable for that analysis.
- Stake locking is opt-in: users must explicitly call `lockStake` to participate in validation, never automatically; deposit/withdraw are open and permissionless.
- Audit findings are extracted from the Quantstamp PDF into `test/audits/QS_SapienVault_Initial_Report_Findings.md` as a todo list, with one Foundry test per finding in `test/audits/` over a shared `AuditBase.t.sol` fixture, each proving the finding is valid.
- Test suite: `test/SapienVault.t.sol` (unit), plus `test/SapienVaultHandler.t.sol` and `test/SapienVaultInvariant.t.sol` for invariants (`foundry.toml`: invariant `runs = 1024`, `depth = 50`). Contract docs live in `docs/SapienVault.md`, linked from the README.
- Security reviews use a standard toolchain: Slither, Aderyn, Mythril, Halmos, Forge (test/coverage/fuzz), Solhint, Surya, plus Trail of Bits reference guides and manual review (the `agent-security-review` skill).
- Deployed on Base mainnet (Vault `0x60Bf63729f688287a450299962b36Cef0aFfaa42`, Sapien Token `0xC729777d0470F30612B1564Fd96E8Dd26f5814E3`, USDC `0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913`) and Base Sepolia (Vault proxy `0x58E72Fa7fb92B100f2c652377465EEEe2642544C`, Token `0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6`, USDC `0x4d4394119CF096FbdbbD3Efb00d204c891C6Cd05`). Sepolia V2 is a UUPS implementation swap on that same proxy.
- `via_ir = false`: under via-IR, solc's per-contract output depends on the whole compilation unit, so the pruned standard-JSON `forge --verify` submits never matches the deployed bytecode (solc#14829). Legacy codegen makes plain `--verify` work and keeps Basescan showing only `src/` + OpenZeppelin. Cost: ~1 KB larger runtime; `forge coverage` no longer needs `--ir-minimum`.
- Dependencies are OpenZeppelin v5.3.0 (both repos) and forge-std v1.9.7, per the committed submodules and `foundry.lock`. The OZ 5.5.0 bump is a **breaking migration**, deferred: it removes `ReentrancyGuardUpgradeable` (now stateless/untranspiled), so the non-upgradeable `ReentrancyGuard` must be inherited instead — moving its flag out of ERC-7201 namespaced storage into regular slot 0 of the live proxies (slots 0-2 verified zero on both, so feasible) — and it changes `ERC4626.maxWithdraw` to `previewRedeem(maxRedeem(owner))`, which would route `super.maxWithdraw()` through the vault's own capped `maxRedeem` and alter SAP-1/SAP-6 rounding.
