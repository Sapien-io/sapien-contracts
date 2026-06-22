# SapienVault V1 → V2 Upgrade Runbook (`instantUnstake`)

Step-by-step guide to ship the `SapienVault` upgrade that adds
`instantUnstake(uint256)`. Covers a local anvil fork rehearsal first, then the
real Base mainnet flow through the `TimelockController` + Safe multisigs.

For the general timelock mechanics see `notes/timelock-upgrade-guide.md`. This
doc is the concrete, addresses-included runbook for *this* upgrade.

## What changes

- New function `instantUnstake(uint256 amount)` — withdraws with **no lockup, no
  cooldown, no penalty**. Forces a full exit if the remainder would fall below
  `MINIMUM_STAKE_AMOUNT` (1 token).
- New event `InstantUnstaked(address indexed user, uint256 amount)`.
- `VAULT_VERSION` bumped `"1"` → `"2"` (`src/utils/Constants.sol`).
- **No storage layout changes** — only an appended function + event. Safe for a
  proxy upgrade.

## Base mainnet addresses (chain id 8453)

| Role | Address |
|------|---------|
| Vault proxy | `0x74b21FAdf654543B142De0bDC7a6A4a0c631e397` |
| Vault ProxyAdmin | `0x253053553e7105C5Bb39b38000EaA2aCdA95509E` |
| TimelockController | `0x20304CbD5D4674b430CdC360f9F7B19790D98257` (48h delay) |
| Proposer — Security Council Safe | `0x18D33278be0870A4907922dE65D6FbE27928580a` |
| Executor — Sapien Labs | `0x454149F78630A82fDcf5559384042A3BBD358FB2` |
| SAPIEN token | `0xC729777d0470F30612B1564Fd96E8Dd26f5814E3` |

Source of truth: `script/Contracts.sol` (`MainnetContracts`) and
`script/Actors.sol` (`MainnetActors`).

---

## Part A — Rehearse on a local anvil fork (do this first)

Validates the upgrade against real mainnet state before touching production.
Requires `BASE_MAINNET_RPC_URL` in `.env`.

### A1. Start the fork

```bash
set -a && source .env && set +a
anvil --fork-url "$BASE_MAINNET_RPC_URL" --port 8545 --chain-id 8453
```

Leave it running; use a second terminal for the rest. Export shared vars there:

```bash
export RPC=http://localhost:8545
export PROXY=0x74b21FAdf654543B142De0bDC7a6A4a0c631e397
export PADMIN=0x253053553e7105C5Bb39b38000EaA2aCdA95509E
export TL=0x20304CbD5D4674b430CdC360f9F7B19790D98257
export PROPOSER=0x18D33278be0870A4907922dE65D6FbE27928580a
export EXECUTOR=0x454149F78630A82fDcf5559384042A3BBD358FB2
export TOKEN=0xC729777d0470F30612B1564Fd96E8Dd26f5814E3
```

### A2. Capture pre-upgrade state

```bash
cast call $PROXY 'version()(string)' --rpc-url $RPC          # "1"
cast call $PROXY 'totalStaked()(uint256)' --rpc-url $RPC     # record this
cast call $TOKEN 'balanceOf(address)(uint256)' $PROXY --rpc-url $RPC  # == totalStaked
cast call $PADMIN 'owner()(address)' --rpc-url $RPC          # == $TL
cast call $TL 'getMinDelay()(uint256)' --rpc-url $RPC        # 172800
```

### A3. Deploy the new implementation

Uses anvil dev account 0 (funded on the fork).

```bash
forge create src/SapienVault.sol:SapienVault \
  --rpc-url $RPC \
  --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 \
  --broadcast
# copy "Deployed to:" into NEWIMPL
export NEWIMPL=<deployed_address>
cast call $NEWIMPL 'version()(string)' --rpc-url $RPC        # "2"
```

### A4. Drive the upgrade through the Timelock

```bash
SALT=0x696e7374616e742d756e7374616b652d76320000000000000000000000000000
ZERO=0x0000000000000000000000000000000000000000000000000000000000000000

# impersonate the Safe signers and fund them for gas
cast rpc anvil_autoImpersonateAccount true --rpc-url $RPC
cast rpc anvil_setBalance $PROPOSER 0xde0b6b3a7640000 --rpc-url $RPC
cast rpc anvil_setBalance $EXECUTOR 0xde0b6b3a7640000 --rpc-url $RPC

# the privileged call the timelock will make on the ProxyAdmin
UPG=$(cast calldata "upgradeAndCall(address,address,bytes)" $PROXY $NEWIMPL 0x)
OPID=$(cast call $TL "hashOperation(address,uint256,bytes,bytes32,bytes32)(bytes32)" \
  $PADMIN 0 $UPG $ZERO $SALT --rpc-url $RPC)

# schedule (proposer)
cast send $TL "schedule(address,uint256,bytes,bytes32,bytes32,uint256)" \
  $PADMIN 0 $UPG $ZERO $SALT 172800 --from $PROPOSER --unlocked --rpc-url $RPC
cast call $TL 'isOperationReady(bytes32)(bool)' $OPID --rpc-url $RPC   # false (delay not elapsed)

# warp past the 48h delay
cast rpc evm_increaseTime 172801 --rpc-url $RPC
cast rpc evm_mine --rpc-url $RPC
cast call $TL 'isOperationReady(bytes32)(bool)' $OPID --rpc-url $RPC   # true

# execute (executor)
cast send $TL "execute(address,uint256,bytes,bytes32,bytes32)" \
  $PADMIN 0 $UPG $ZERO $SALT --from $EXECUTOR --unlocked --rpc-url $RPC
cast call $TL 'isOperationDone(bytes32)(bool)' $OPID --rpc-url $RPC    # true
```

### A5. Verify the upgrade + state preservation

```bash
IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
cast storage $PROXY $IMPL_SLOT --rpc-url $RPC                 # right-padded $NEWIMPL
cast call $PROXY 'version()(string)' --rpc-url $RPC          # "2"
cast call $PROXY 'totalStaked()(uint256)' --rpc-url $RPC     # unchanged vs A2
cast call $TOKEN 'balanceOf(address)(uint256)' $PROXY --rpc-url $RPC  # unchanged vs A2
```

### A6. Smoke-test `instantUnstake`

Seed a staker (slot 0 = `_balances` on the SAPIEN token), stake locked, then exit
instantly while still locked.

```bash
export STAKER=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
export SKEY=0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
SIG='userStakes(address)(uint128,uint128,uint64,uint64,uint64,uint64,uint64,uint32,uint128)'

# give the staker 100 SAPIEN
cast rpc anvil_setStorageAt $TOKEN $(cast index address $STAKER 0) \
  0x0000000000000000000000000000000000000000000000056bc75e2d63100000 --rpc-url $RPC

# stake 100 with a 30-day lockup
cast send $TOKEN 'approve(address,uint256)' $PROXY 100000000000000000000 --private-key $SKEY --rpc-url $RPC
cast send $PROXY 'stake(uint256,uint256)' 100000000000000000000 2592000 --private-key $SKEY --rpc-url $RPC
cast call $PROXY 'getTotalUnlocked(address)(uint256)' $STAKER --rpc-url $RPC   # 0 => still locked

# instant exit while locked (no penalty, no cooldown)
cast send $PROXY 'instantUnstake(uint256)' 100000000000000000000 --private-key $SKEY --rpc-url $RPC
cast call $PROXY "$SIG" $STAKER --rpc-url $RPC | head -1                        # 0
cast call $TOKEN 'balanceOf(address)(uint256)' $STAKER --rpc-url $RPC           # 100e18 returned in full
```

Expected reverts (custom errors): `instantUnstake(0)` → `InvalidAmount()`
(`0x2c5211c6`); amount > stake → `AmountExceedsAvailableBalance()` (`0x7b2ce124`);
no stake → `NoStakeFound()` (`0x59be8f02`).

When done, stop anvil (Ctrl-C in its terminal).

---

## Part B — Production upgrade (Base mainnet)

Two-phase governance: Security Council Safe **schedules**, then after the 48h
delay Sapien Labs (executor) **executes**. Same `upgradeAndCall` payload as the
rehearsal.

### B1. Deploy the new implementation

```bash
export RPC_URL=<base_mainnet_rpc>
export ETHERSCAN_API_KEY=<basescan_api_key>
export ACCOUNT=<deployer_account_in_cast_wallet>
export CONTRACT=SapienVault

make deploy-contract     # forge create src/SapienVault.sol:SapienVault, verified
```

Record the deployed implementation address as `NEW_IMPLEMENTATION`. Sanity check
it is the V2 bytecode:

```bash
cast call <NEW_IMPLEMENTATION> 'version()(string)' --rpc-url $RPC_URL   # "2"
```

### B2. Generate the schedule + execute payloads

`script/Upgrader.s.sol` prints both transactions (contract type `0` = Vault). It
reads the live `minDelay` and derives a unique salt
(`keccak256(name, impl, block.timestamp)`).

```bash
forge script script/Upgrader.s.sol \
  --sig "generateUpgradePayload(uint8,address)" 0 <NEW_IMPLEMENTATION> \
  --rpc-url $RPC_URL
```

Save the output: the **Operation ID**, the **STEP 1 schedule** calldata, and the
**STEP 2 execute** calldata. Both target the TimelockController.

> The salt is timestamp-derived, so STEP 1 and STEP 2 must use the *same* salt.
> Capture the full script output in one run; don't regenerate between phases.

### B3. Phase 1 — Schedule (Security Council Safe)

In the Safe UI for `0x18D3…580a`, create a transaction:

- **To**: TimelockController `0x2030…8257`
- **Value**: `0`
- **Data**: the STEP 1 (schedule) calldata from B2

Collect signatures and execute the Safe tx. Confirm it's pending:

```bash
cast call $TL 'isOperationPending(bytes32)(bool)' <OPERATION_ID> --rpc-url $RPC_URL   # true
cast call $TL 'getTimestamp(bytes32)(uint256)'    <OPERATION_ID> --rpc-url $RPC_URL   # ready-at time
```

### B4. Wait the delay

48 hours (`172800s`). When elapsed:

```bash
cast call $TL 'isOperationReady(bytes32)(bool)' <OPERATION_ID> --rpc-url $RPC_URL     # true
```

### B5. Phase 2 — Execute (Sapien Labs executor)

From the executor `0x4541…FB2`, send a transaction:

- **To**: TimelockController `0x2030…8257`
- **Value**: `0`
- **Data**: the STEP 2 (execute) calldata from B2

If the executor is an EOA via `cast`:

```bash
cast send $TL <STEP2_EXECUTE_CALLDATA> --account $ACCOUNT --rpc-url $RPC_URL
```

Then confirm:

```bash
cast call $TL 'isOperationDone(bytes32)(bool)' <OPERATION_ID> --rpc-url $RPC_URL      # true
```

### B6. Post-upgrade verification

```bash
IMPL_SLOT=0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc
cast storage $PROXY $IMPL_SLOT --rpc-url $RPC_URL            # right-padded NEW_IMPLEMENTATION
cast call $PROXY 'version()(string)' --rpc-url $RPC_URL      # "2"
cast call $PROXY 'totalStaked()(uint256)' --rpc-url $RPC_URL # unchanged vs pre-upgrade
```

Verify the new implementation source on Basescan if `make deploy-contract` didn't
already (`--verify`).

---

## Verification checklist

- [ ] V2 impl deployed and verified; `version()` returns `"2"`
- [ ] Local fork rehearsal (Part A) passes end-to-end
- [ ] Schedule tx confirmed; `isOperationPending` = true
- [ ] 48h elapsed; `isOperationReady` = true
- [ ] Execute tx confirmed; `isOperationDone` = true
- [ ] Implementation slot points to NEW_IMPLEMENTATION
- [ ] `totalStaked` and vault token balance unchanged across the upgrade
- [ ] `instantUnstake` works for a real staker; bad inputs revert as expected

## Cancelling a scheduled operation

Before execution, a canceller (Security Council Safe) can abort:

```bash
forge script script/Upgrader.s.sol \
  --sig "generateCancelPayload(bytes32)" <OPERATION_ID> --rpc-url $RPC_URL
# submit the printed cancel calldata to the TimelockController from the canceller Safe
```

## Notes & gotchas

- `upgradeAndCall(proxy, impl, "")` is used with empty init data — there is **no**
  V2 reinitializer, so the third arg must be `0x`.
- Salt mismatch between schedule and execute → execute reverts as "operation not
  ready"/unknown. Use the exact salt from the schedule.
- The ProxyAdmin owner is the Timelock; only the Timelock can call
  `upgradeAndCall`. Direct calls from any Safe will revert.
- This is a transparent proxy (OZ v5): the upgrade goes through `ProxyAdmin`, not
  a UUPS `upgradeToAndCall` on the proxy itself.
