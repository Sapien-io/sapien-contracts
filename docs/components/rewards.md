# FinalizationLib (formerly Rewards)

> **v0.5 change**: The standalone `Rewards` contract has been replaced by `FinalizationLib`, a library that operates on `SapienCore`'s ERC-7201 namespaced storage via `DELEGATECALL`. Reward accounting is now embedded in the core storage as `projectEscrow` and `pendingRewards` mappings.

`FinalizationLib` handles validator settlement, contributor reward release, reward claiming, expired commitment cleanup, project completion, and escrow refunds.

## Reward Flow

```
Originator funds project
  → Protocol fee → Treasury
  → Origination adapter fee → Adapter (optional)
  → Remaining → projectEscrow[projectId][token]

Consensus reached (Accepted)
  → settleValidator: validator reward → pendingRewards[validator][token]
  → releaseContributorReward: contributor reward → pendingRewards[contributor][token]
  → claimReward: pendingRewards → user's wallet
```

## Validator Settlement

### `settleValidator(bytes32 projectId, uint256 index, uint256 nonce)`

Called by the validator after consensus is computed. Behavior depends on outlier classification:

**Outlier validators:**
- Slash amount deducted from committed stake (capped at committed amount)
- Remaining stake returned to validator capacity
- Reputation decreased

**Accurate validators:**
- Full committed stake returned to validator capacity
- Reward calculated as: `(totalRewards × validatorRewardBps × weight) / (BPS × totalQuantity × totalAccurateWeight)`
- If a validation adapter is set, the validation fee is deducted from the reward
- Net reward added to `pendingRewards`
- Reputation increased

### `forceSettleValidator(projectId, index, nonce, validator)`

Permissionless. Anyone can force-settle a validator after the `forceSettleDelay` elapses past their reveal timestamp. Prevents validators from blocking reward distribution.

## Contributor Rewards

### `releaseContributorReward(bytes32 projectId, uint256 index)`

Releases the contributor's share to their pending balance. Requirements:

1. Contribution status is `Accepted`
2. Challenge period has elapsed
3. No active or upheld dispute
4. Reward not already released

**Reward calculation:**
```
contributorShare = rewardRate × (BPS - validatorRewardBps) / BPS
```

If a contribution adapter is set, the contribution fee is deducted from the reward before crediting the contributor.

Decrements the project's `pendingContributions` counter.

## Reward Claiming

### `claimReward(address token)`

Transfers the caller's full `pendingRewards` balance for the given token to their wallet.

**Protections:**
- `minClaimAmount`: Minimum reward balance required to claim (prevents dust claims)
- `claimCooldown`: Minimum time between successive claims per user

## Expired Commitment Cleanup

### `cancelExpiredCommitment(bytes32 projectId, uint256 index, address validator)`

Permissionless keeper function. Targets validators who committed but failed to reveal within the combined commit + reveal deadline. The validator's committed stake is fully slashed and their reputation is penalized.

## Project Completion

### `completeProject(bytes32 projectId)`

Called by the originator to mark a project as completed. Requirements:

- Caller is the project originator
- Project is `Active` or `Funded`
- No pending contributions in the pipeline (`pendingContributions == 0`)

Transitions the project to `Completed` status and unlocks the originator's locked stake.

### `refundEscrow(bytes32 projectId)`

Called by the originator after `PROJECT_COMPLETION_DELAY` (30 days) to claim any remaining tokens in the project escrow. This grace period allows time for any final disputes to be processed.

## Escrow Accounting

| Mapping | Purpose |
|---------|---------|
| `projectEscrow[projectId][token]` | Tracks unallocated reward tokens per project |
| `pendingRewards[user][token]` | Tracks earned but unclaimed rewards per user |

Rewards are moved from `projectEscrow` → `pendingRewards` during settlement and reward release. Users withdraw from `pendingRewards` via `claimReward`.

## Adapter Fee Deductions

Adapter fees are deducted at the point of reward distribution (not at contribution/validation time):

| Fee Type | Deducted From | When |
|----------|---------------|------|
| Origination fee | Funding amount (after protocol fee) | `fundProject` |
| Contribution fee | Contributor's reward share | `releaseContributorReward` |
| Validation fee | Validator's reward share | `settleValidator` |

Fee rates are configured globally via `SapienCore.setOriginationFee()`, `setContributionFee()`, `setValidationFee()`.
