# Sepolia collateral loop

On-chain half of lock → review → unlock or slash on **Base Sepolia**. The vault
does not score, quorum, or compute consensus. The off-chain PoQ engine (paired
ticket: poq-monorepo #1760) decides the outcome and writes `report.stake`. This
document is the observer checklist: Basescan Sepolia versus the amounts the
engine will put in that report.

Mainnet vault `0x60Bf63729f688287a450299962b36Cef0aFfaa42` and the 20% rewards
program are out of scope. Do not grant `ENGINE_ROLE` there with the scripts in
this repo (`script/GrantEngineRole.s.sol` refuses that address).

---

## Addresses (Base Sepolia, chain id 84532)

| Piece | Address |
|-------|---------|
| Vault (UUPS proxy, V2) | [`0x58E72Fa7fb92B100f2c652377465EEEe2642544C`](https://sepolia.basescan.org/address/0x58E72Fa7fb92B100f2c652377465EEEe2642544C) |
| SAPIEN | [`0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6`](https://sepolia.basescan.org/address/0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6) |
| Admin Safe (`DEFAULT_ADMIN_ROLE`) | `0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC` |

`ENGINE_ROLE` is granted to the **staging engine signer** via
`script/GrantEngineRole.s.sol` (Safe calldata). Set `SEPOLIA_ENGINE` to that
signer. After the Safe executes, `VERIFY_ONLY=true` confirms the role.

```bash
export BASE_SEPOLIA_RPC_URL=https://sepolia.base.org
export SEPOLIA_ENGINE=0x...   # staging engine signer

make grant-engine-sepolia-calldata   # print grantRole calldata for the Safe
# Safe UI: target = vault proxy, value 0, paste calldata, sign, execute
make grant-engine-sepolia-verify     # read-only hasRole check
```

---

## Loop

`minDepositAge` on the live Sepolia vault is `DEFAULT_MIN_DEPOSIT_AGE` (1 day).
A test vault may set it to `0`, in which case step 2 is a no-op.

1. **Deposit.** Validator `approve`s Sepolia SAPIEN and `deposit`s. Fresh shares
   are pending until they clear `minDepositAge`.
2. **Wait.** `skip(minDepositAge)` in tests; wall-clock on the live network.
3. **Lock.** Validator calls `lockStake(amount)` themselves (not the engine).
   Emits `StakeLocked(user, amount)`. `getStakeAccount(user).lockedAmount`
   increases by `amount`.
4. **Review** happens off-chain. The vault is not called and does not compute
   consensus. Record `lockedAmount` at this moment — that is
   `stake.stake_at_risk_wei`.
5. **Outcome** (engine, `ENGINE_ROLE` only):
   - **Accepted** → `unlockStake(user, amount)` → `StakeUnlocked`.
   - **Forced** → `slashStake(user, amount)` → `StakeSlashed` + `SharesSlashed`
     (shares burned; SAP-2 dilution-compensated).

Pause blocks lock, unlock, and slash. Admin can `revokeRole(ENGINE_ROLE, …)`
to neutralize a compromised signer; that does not unlock already-locked stake.

---

## `report.stake` (engine writes these; vault does not)

| Field | Accepted (`unlockStake`) | Forced (`slashStake`) | On-chain source |
|-------|--------------------------|-----------------------|-----------------|
| `stake.slashed_wei` | `"0"` | decimal string of the slashed **asset** amount | `0`, or `StakeSlashed.amount` (log topic `[2]`; the `amount` argument). This is intended net asset damage, not `convertToAssets(sharesBurned)`. |
| `stake.stake_at_risk_wei` | locked amount at review time | locked amount at review time | `getStakeAccount(user).lockedAmount` **before** unlock/slash |

`SharesSlashed.shares` is the burn quantity (larger than a naive
`convertToShares(amount)` — SAP-2). Indexers track it for share supply; the
report field `slashed_wei` stays in **assets**.

Event amounts are **indexed** (`topics[2]`), not in the log `data` payload.
See [SapienVault.md — Events](SapienVault.md#events).

---

## Observer checklist (Basescan Sepolia)

Open the vault on
[Basescan Sepolia](https://sepolia.basescan.org/address/0x58E72Fa7fb92B100f2c652377465EEEe2642544C#events)
and match:

| Step | Event | Read |
|------|-------|------|
| Lock | `StakeLocked` | `amount` == assets the validator locked |
| Unlock | `StakeUnlocked` | `amount` unlocked; `getStakeAccount.lockedAmount` dropped; report `slashed_wei = "0"`, `stake_at_risk_wei` = locked amount at review |
| Slash | `StakeSlashed` + `SharesSlashed` | `StakeSlashed.amount` == report `slashed_wei`; `SharesSlashed.shares > 0`; HTML report links the slash tx |

HTML report slash link (engine emits this; tests pin the helper):

```
https://sepolia.basescan.org/tx/<slashTxHash>
```

---

## Tests

| Suite | When it runs | What it proves |
|-------|--------------|----------------|
| `test/CollateralLoop.t.sol` | every `forge test` | deposit → wait default `minDepositAge` → lock; unlock → `slashed_wei = 0`; slash burns shares and sets `slashed_wei` to the asset amount; Basescan URL helper |
| `test/SapienVaultNoConsensus.t.sol` | every `forge test` | no `computeConsensus` / `score` / `quorum` functions on `SapienVault` or `ISapienVault`; mainnet deployment pins unchanged |
| `test/fork/SepoliaCollateralLoop.t.sol` | `make test-fork-sepolia-loop` (needs `BASE_SEPOLIA_RPC_URL`) | same loop against the live V2 proxy; fork-local `grantRole` so the loop runs before the Safe grant lands; if `SEPOLIA_ENGINE` is set, asserts that address already holds the role |

```bash
forge test --match-path test/CollateralLoop.t.sol
forge test --match-path test/SapienVaultNoConsensus.t.sol
make test-fork-sepolia-loop    # BASE_SEPOLIA_RPC_URL required
```

CI does not set a Sepolia RPC, so the fork suite skips there (same pattern as
`SepoliaUpgradeFork`).

---

## Out of scope

- Engine `report.stake` emission and HTML report rendering (poq-monorepo #1760).
- Attestation registry (issue #168).
- EAS, vault-app UI, mainnet vault / rewards.
