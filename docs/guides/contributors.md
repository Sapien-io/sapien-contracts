# Guide for Contributors

Contributors perform AI-related tasks and earn rewards based on the quality of their output as determined by human validator consensus.

## 1. Prerequisites

- **Stake SAPIEN**: You must have SAPIEN tokens deposited in the `SapienVault`. Each project defines a `minStakeToClaim` threshold — your available stake must meet this requirement before claiming slots.
- **Reputation**: Your on-chain reputation is tracked per skill (e.g., `DATA_ANNOTATION`, `BOUNDING_BOX`). New users start at 5,000 for any skill they haven't worked on. Good work increases your skill-specific reputation; rejected contributions decrease it.

## 2. Claim Contribution Slots

Before submitting work, you must claim slots in a project. This reserves the contribution indices and locks your stake as collateral.

```solidity
(uint256 claimId, uint256[] memory indices) = core.claimToContribute(
    projectId,
    quantity,  // number of slots to claim (max 20)
    adapter    // adapter address for contribution fee, or address(0)
);
```

- `adapter`: Address of the contribution adapter facilitating the claim (e.g., the frontend/dapp). The adapter receives a fee (default 3%, max 5%) from the contribution reward when it is eventually released.
- Returns a `claimId` and the array of slot `indices` assigned to you.
- **Deadline**: You must submit work before the claim deadline (default 1 day from claim creation). If you miss the deadline, anyone can call `expireClaim` and your stake for unsubmitted slots will be slashed.

## 3. Submit Work

Perform the task using the tools specified in the project's metadata. Once finished, submit your work for each claimed index:

```solidity
core.contribute(claimId, index, submissionHash, dataCid);
```

- `claimId`: Your claim identifier (returned by `claimToContribute`).
- `index`: The specific contribution slot index (must be part of your claim).
- `submissionHash`: `keccak256` hash of your submission content for integrity verification.
- `dataCid`: IPFS CID pointing to the contribution data.

### Batch Submission

Submit multiple contributions in a single transaction:

```solidity
core.batchContribute(claimId, indices, submissionHashes, dataCids);
```

All arrays must have the same length. Each entry maps to a single contribution slot.

## 4. Validation and Consensus

After you submit work, validators review it using a commit-reveal scheme:

1. Validators commit sealed scores for your contribution.
2. Validators reveal their scores after the commit deadline.
3. `computeConsensus` is called to calculate the stake-weighted average score.
4. Your contribution is marked **Accepted** or **Rejected** based on the project's consensus threshold.

You do not need to take any action during this phase — it is driven by validators and permissionless finalization calls.

## 5. Claiming Rewards

The reward flow is multi-step:

1. **Consensus**: `computeConsensus(projectId, index)` computes the weighted average and classifies outlier validators.
2. **Challenge period**: A waiting period (default 1 day) after consensus, during which disputes can be opened.
3. **Release**: After the challenge period ends with no active dispute, anyone can call `releaseContributorReward(projectId, index)` to move your reward from project escrow to your pending balance.
4. **Withdraw**: Call `claimReward(tokenAddress)` on `SapienCore` to withdraw your full pending balance for that token.

```solidity
// After challenge period ends (permissionless — anyone can call)
core.releaseContributorReward(projectId, index);

// Withdraw your accumulated rewards
core.claimReward(usdcAddress);
```

### Claim Protection

The protocol enforces two safeguards on reward withdrawals:

- **Minimum claim amount**: Your pending balance must meet the minimum threshold (configurable by admin).
- **Cooldown period**: You must wait for the cooldown to expire between successive `claimReward` calls.

### If Rejected

If your contribution is rejected by consensus, the slot is released back to the project pool for others to attempt. Your reputation decreases, but your stake is not slashed for a rejection — only for missed deadlines.

## 6. Expired Claims

If you fail to submit work before the claim deadline, anyone can expire your claim:

```solidity
core.expireClaim(claimId, unsubmittedIndices);
```

This releases the unsubmitted slots back to the project and slashes your locked stake for those slots. Slots you did submit before the deadline are unaffected.

## Improving Your Earnings

- **Focus on quality**: Consistently high consensus scores increase your skill-specific reputation. Higher reputation in a skill makes you eligible for projects with stricter `minValidatorReputation` thresholds and gives validators working alongside you more confidence in the quality bar.
- **Manage deadlines**: Always submit or release claims before they expire to avoid stake slashing.
- **Batch submissions**: Use `batchContribute` to submit multiple contributions in a single transaction, saving gas.
- **Choose adapters carefully**: The adapter you specify during `claimToContribute` receives a fee from your contribution reward. Some adapters may provide better tooling in exchange for this fee.
