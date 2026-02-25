# Guide for Originators

As an Originator, you use the Sapien protocol to verify the quality of AI datasets or agent behaviors. This guide walks you through creating, funding, managing, and completing a project.

## 1. Prerequisites

- **SAPIEN Tokens**: You must have SAPIEN tokens deposited in the `SapienVault`. When you fund a project, the protocol locks a per-slot originator stake as collateral. This stake is returned when the project completes.
- **Reward Tokens**: You need the ERC-20 tokens (e.g., USDC) that you plan to use for contributor and validator rewards.

## 2. Create a Project

Call `SapienCore.createProject()` with the following parameters:

- `projectId` (`bytes32`): A unique identifier for the project (generated off-chain).
- `metadataCid` (`string`): An IPFS CID pointing to your project metadata document (Task Definition Spec, instructions, etc.).
- `config` (`Project`): A configuration struct containing:

| Field | Type | Description |
|-------|------|-------------|
| `rewardToken` | `address` | Address of the ERC-20 reward token |
| `minStakeToClaim` | `uint256` | Minimum SAPIEN stake required for a contributor to claim slots |
| `minValidationStake` | `uint256` | Minimum stake per validation commit |
| `requiredSkill` | `bytes32` | Registered skill hash (required) — all reputation accrues against this key |
| `consensusThreshold` | `uint256` | Score threshold in basis points for acceptance (e.g., 7000 = 70%) |
| `validatorRewardBps` | `uint256` | Percentage of reward pool for validators (max 2500 = 25%) |
| `numberOfValidations` | `uint256` | Minimum number of validators per contribution |
| `minValidatorReputation` | `uint256` | Minimum reputation score for validators |

```solidity
core.createProject(projectId, "bafybeigdyrzt...", Project({
    originator: address(0),   // set automatically by the contract
    rewardToken: usdcAddress,
    totalRewards: 0,          // set during fundProject
    totalQuantity: 0,         // set during fundProject
    availableSlots: 0,        // managed by the contract
    minStakeToClaim: 100e18,
    minValidationStake: 50e18,
    requiredSkill: keccak256("DATA_ANNOTATION"),
    consensusThreshold: 7000,
    validatorRewardBps: 1000,
    numberOfValidations: 3,
    minValidatorReputation: 0,
    status: ProjectStatus.Created, // set by the contract
    activatedAt: 0,                // set by the contract
    completedAt: 0                 // set by the contract
}));
```

## 3. Fund Your Project

Once the project is created, fund it and specify the number of contribution slots:

```solidity
core.fundProject(projectId, rewardAmount, quantity, adapter);
```

- `rewardAmount`: Total reward tokens to deposit (before fees).
- `quantity`: Number of contribution slots to create.
- `adapter`: Address of an origination adapter to receive an adapter fee, or `address(0)` for none.

**Fee Deductions**: When funding, the following are deducted from your deposit:

1. **Protocol fee** (default 10%, max 10%) is sent to the Sapien treasury.
2. **Origination adapter fee** (default 4%, max 5%) is sent to the adapter address if one is specified.
3. **Originator stake** is locked per slot from your vault balance.

The remaining amount after fees becomes the project's reward pool. The per-contribution reward rate is calculated as `remainingRewards / quantity`.

**Example**: Funding with 1000 USDC (10% protocol fee, 4% adapter fee):
- Protocol fee: 100 USDC to treasury
- Adapter fee: 36.00 USDC to adapter
- Reward pool: 864.00 USDC across all contribution slots

**Token Approval**: You must approve `SapienCore` to spend the reward token before calling `fundProject`.

## 4. Monitor Your Project

After funding, your project is active and contributors can begin claiming slots.

- **Query project state**: Call `SapienCore.getProject(projectId)` to check `availableSlots`, `totalQuantity`, and `status`.
- **Watch events**: Listen for `ClaimCreated`, `ContributionSubmitted`, and `ConsensusReached` events filtered by your `projectId`.
- **Check contributions**: Call `SapienCore.getContribution(projectId, index)` to inspect individual contribution status, score, and contributor address.

## 5. Dispute Awareness

After consensus is computed for a contribution, there is a challenge period (default 1 day) during which validators can open disputes. As an originator, you should be aware of:

- **Dispute resolution**: An operator resolves disputes. If upheld, the contribution enters a new validation round.
- **Originator reports**: Community members can report originators for misconduct by calling `reportOriginator`. If upheld, the project is cancelled and your originator stake is slashed.
- **Escalation**: Unresolved disputes or originator reports are automatically escalated if the resolution deadline (7 days) passes.

## 6. Complete Your Project

When all contribution slots have been processed:

```solidity
core.completeProject(projectId);
```

This transitions the project to `Completed` status and unlocks your originator stake. The project must have no contributions in the active pipeline (pending validation or settlement).

### Refund Remaining Escrow

After project completion, any unused reward tokens in escrow can be refunded. There is a mandatory 30-day grace period after completion before the refund is available:

```solidity
core.refundEscrow(projectId);
```

The refunded amount is added to your pending rewards balance, which you can withdraw via `claimReward(tokenAddress)`.

## Best Practices

- **Clear metadata**: Ensure your Task Definition Spec (referenced via `metadataCid`) is clear, objective, and detailed. Ambiguous instructions lead to high validator disagreement and slashing.
- **Appropriate validator rewards**: Setting `validatorRewardBps` too low may discourage validators. The default 10% (1000 bps) works well for most projects.
- **Skill selection**: Every project must specify a registered skill (e.g., `keccak256("DATA_ANNOTATION")`). Contributor and validator reputation accrues against this skill, so participants build domain-specific track records. Set `minValidatorReputation` above the default (5000) to restrict validation to experienced participants in that skill.
- **Monitor consensus outcomes**: If many validators are being slashed, your quality criteria may be too subjective or your instructions unclear.
- **Choose adapters wisely**: Adapters (frontends/dapps) facilitate participation. The origination adapter fee is paid from your funding amount.
