# Guide for Originators

As an Originator, you use the Sapien protocol to verify the quality of AI datasets or agent behaviors across the full lifecycle—from training data curation to real-time agent supervision. This guide walks you through creating and funding your first project.

## 1. Prerequisites

- **SAPIEN Tokens**: You must have SAPIEN tokens staked in the `SapienVault` to meet the minimum stake requirement for the `ORIGINATOR_ROLE`.
- **Reward Tokens**: You need the ERC20 tokens (e.g., USDC, USDT) that you plan to use for rewards.

## 2. Create a Project

To create a project, call `SapienCore.createProject()` with the following parameters:

- `projectId`: A unique `bytes32` hash identifying the project.
- `rewardToken`: Address of your chosen reward token.
- `minStakeToClaim`: Minimum SAPIEN stake required for a contributor to claim a slot.
- `minStakeToContribute`: (Legacy) Minimum stake required to participate.
- `minValidations`: The minimum number of reviewers needed per contribution.
- `validatorRewardBasisPoints`: Percentage of the total pool for validators (default 1000 = 10%). **Capped at 2500 (25%)**.
- `requiredSkill`: (Optional) A skill contributors must have or will earn upon successful completion.

## 3. Fund Your Project

Once the project is created, you must add funds and define the quantity of work units:

Call `SapienCore.fundProject(projectId, rewardAmount, quantity)`:
- `rewardAmount`: Total amount of reward tokens to deposit.
- `quantity`: The total number of contributions you want verified.

**Protocol Fee**: A protocol fee (default 1%) is automatically deducted from your funding amount and sent to the Sapien treasury. The remaining amount is allocated to your project's reward pool.

**Example**: If you fund with 1000 USDC:
- Protocol fee (1%): 10 USDC → Sent to Sapien treasury
- Project rewards: 990 USDC → Allocated to your project

*Note: The protocol will automatically calculate the per-task reward based on `totalRewards / quantity`, where `totalRewards` is the amount after the protocol fee deduction.*

## 4. Choose a Consensus Algorithm

By default, projects use the protocol-wide default algorithm. You can choose a specific one for your project:

Call `ValidationOracle.setProjectAlgorithm(projectId, "Hybrid")`.
- Available options: `"Linear"`, `"Capped"`, `"Sqrt"`, `"Hybrid"`.

## 5. Integrate Your Tools

To connect your existing AI pipeline to Sapien:
- **Submit Work**: Use a **Contributor Oracle** to call `SapienCore.contribute()` whenever new work is ready for validation.
- **Consume Signals**: Monitor the `ContributionFinalized` events or query `SapienCore.contributions()` to get the verified quality scores.

## 🎯 Best Practices

- **Clear TDS**: Ensure your Task Definition Spec (provided to contributors/validators via the oracle interface) is clear and objective. You may specify requirements for participant types (e.g., human-only or AI-preferred) within the TDS.
- **Incentivize Validators**: Setting `validatorRewardBasisPoints` too low may lead to slow validation times.
- **Monitor Outliers**: If many validators are being slashed, your quality criteria might be too subjective or your instructions unclear.
