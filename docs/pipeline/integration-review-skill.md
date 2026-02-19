# Integration Review Skill

Purpose: Ensure external protocols and tokens integrate safely with Sapien PoQ v0.5.

## Target Architecture (v0.5)

- **QualityEngine**: Holds reward tokens in `projectEscrow`; transfers to treasury, adapters, participants.
- **StakeVault**: ERC-4626 over SAPIEN (or configurable) asset token.
- **External call sites**: IERC20 transfer/transferFrom, IStakeVault stake operations.

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

### StakeVault (ERC-4626)

| Assumption | Risk | Test |
|------------|------|------|
| deposit/withdraw/mint/redeem semantics | Share/asset rounding | Standard ERC-4626 tests |
| convertToShares / convertToAssets | Inflation attack | _decimalsOffset = 3 |
| Share burn on slash | Burns from user balance | _burnShares logic |
| maxWithdraw/maxRedeem | Locked amounts excluded | availableBalance override |

### QualityEngine ↔ StakeVault

| Assumption | Risk | Test |
|------------|------|------|
| ENGINE_ROLE exclusive | Vault only accepts Engine calls | Role checks |
| Lock/unlock/slash atomicity | Partial state on revert | ReentrancyGuard |
| Available balance = total - locks | Withdrawal guard correct | maxRedeem override |

### Adapter & Treasury Addresses

| Assumption | Risk | Test |
|------------|------|------|
| adapter can receive tokens | Contract without receive | claimReward flow |
| treasury can receive tokens | Same | fundProject |
| address(0) adapter = no fee | Adapter fee skipped | Zero adapter path |

### ConsensusLib

| Assumption | Risk | Test |
|------------|------|------|
| Pure math, no external calls | Library is stateless | No I/O in library |
| Delegatecall from Engine | Library runs in Engine context | Storage access via Engine |
| IConsensusAlgorithm (optional) | Pluggable algorithm | Currently unused in src |

---

## Output

- **integration_risks.json**: Token behavior quirks, oracle edge cases, protocol incompatibilities.
- **Recommendations**: Whitelist/blacklist token types; document supported reward tokens; test mocks for fee-on-transfer.
