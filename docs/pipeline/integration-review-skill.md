# Integration Review Skill

Purpose: Ensure external protocols and tokens integrate safely with Sapien PoQ v0.5.

## Target Architecture (v0.5)

- **SapienCore**: Holds reward tokens in `projectEscrow`; transfers to treasury, adapters, participants via `claimReward`.
- **SapienVault**: ERC-4626 over SAPIEN (or configurable) asset token.
- **External call sites**: IERC20 transfer/transferFrom, ISapienVault stake operations (ENGINE_ROLE gated).

---

## Checks

### ERC-20 Token Assumptions

| Assumption | Risk | Test |
|------------|------|------|
| `transfer` returns bool | Some tokens return void | SafeERC20 used throughout |
| `transferFrom` reverts on failure | Fee-on-transfer tokens change amounts | Test with FeeOnTransferToken |
| No callback on transfer | Reentrancy | Hooks in some tokens (e.g. ERC777) |
| Standard decimals | Non-18 decimals in reward token | Reward rate / quantity math |
| Non-reverting | Blacklist, paused tokens | Edge case tests |

### SapienVault (ERC-4626)

| Assumption | Risk | Test |
|------------|------|------|
| deposit/withdraw/mint/redeem semantics | Share/asset rounding | Standard ERC-4626 tests |
| convertToShares / convertToAssets | Inflation attack | _decimalsOffset = 3 |
| Share burn on slash | Burns from user balance | _burnShares logic |
| maxWithdraw/maxRedeem | Locked amounts excluded | availableBalance override |
| maxDeposit/maxMint | Return 0 when paused | Paused state tests |
| Transfer guard | Locked shares cannot be transferred | _update override |

### SapienCore <-> SapienVault

| Assumption | Risk | Test |
|------------|------|------|
| ENGINE_ROLE exclusive | SapienVault only accepts SapienCore calls | Role checks |
| Lock/unlock/slash atomicity | Partial state on revert | ReentrancyGuardUpgradeable |
| Available balance = total - locks | Withdrawal guard correct | maxRedeem override |
| slashAndUnlockContributor | Batch operation correctness | Combined slash+unlock |

### Adapter and Treasury Addresses

| Assumption | Risk | Test |
|------------|------|------|
| adapter can receive tokens | Contract without receive | claimReward flow |
| treasury can receive tokens | Same | fundProject |
| address(0) adapter = no fee | Adapter fee skipped | Zero adapter path |

### ConsensusLib

| Assumption | Risk | Test |
|------------|------|------|
| Pure math, no external calls | Library is stateless | No I/O in library |
| DELEGATECALL from SapienCore | Library runs in SapienCore context | Storage access via ERC-7201 |
| Overflow protection | Variance calculation guards | Large stake/score inputs |

---

## Output

- **integration_risks.json**: Token behavior quirks, oracle edge cases, protocol incompatibilities.
- **Recommendations**: Whitelist/blacklist token types; document supported reward tokens; test mocks for fee-on-transfer.
