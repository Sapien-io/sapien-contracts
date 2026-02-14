# Rewards Management

The `Rewards` contract handles the allocation, distribution, and claiming of reward tokens for projects on the Sapien platform. It maintains separate accounting for contributors and validators to ensure fair and transparent payouts.

## Validator Rewards on Acceptance Only

**Validators are paid only when a contribution is accepted.** When a contribution is rejected (consensus score below threshold), validators receive no rewards—even though they performed validation work. Outlier slashing still applies in both cases.

This design prevents reward pool drain: rejected tasks return to the pool and can be re-submitted on the same index. If validators were paid on rejection, they would be paid again when the slot is re-done and accepted, doubling the validation cost for a single accepted contribution. See [Validator Rewards on Rejection fix](../security/fixes/validator-rewards-on-rejection.md) for details.

When a contribution is rejected, the contributor's reward portion remains in the project pool and is available for the next contributor who submits on that index.

## 📋 Responsibilities

- **Reward Escrow**: Holding funds deposited by Originators until they are earned by participants.
- **Allocation**: Mapping reward pools to specific project IDs.
- **Distribution**: Recording the earnings for contributors and validators after successful consensus.
- **Claiming**: Allowing users to withdraw their earned rewards to their personal wallets.

## 🛠️ Key Functions

### Core Logic (OnlyCore)

These functions can only be called by the `SapienCore` contract:
- `allocateRewards`: Moves project funds into the rewards escrow during the `fundProject` flow.
- `distributeReward`: Assigns a reward amount to a specific contributor for a project after work is accepted.
- `distributeValidatorReward`: Assigns a reward amount to a specific validator based on their stake and accuracy after consensus.

### User Functions

#### `claimRewards` / `claimAllRewards`
Allows a contributor to withdraw their earned rewards. Both functions accept optional `feeRecipient` and `feeBps` parameters to enable dapp operators to collect a fee on claims (max governed by `maxFeeBps`, default 4%). `claimAllRewards` is a batch function that handles multiple projects in a single transaction, saving gas for active contributors.

#### `claimValidatorRewards` / `claimAllValidatorRewards`
Allows a validator to withdraw their earnings with the same optional fee parameters. `claimAllValidatorRewards` allows for batch claiming across multiple projects.

## 📊 View Functions

- `getAvailableRewards`: Check how much a contributor can currently withdraw.
- `getTotalRewardsEarned`: View the historical total of rewards earned by a user.
- `getRemainingProjectRewards`: See the current balance of the reward pool for a project.

## 🔐 Access Control

- **OnlyCore**: Critical distribution functions are restricted to the `SapienCore` address to prevent unauthorized payouts.
- **DEFAULT_ADMIN_ROLE**: Configuration of the core contract address and emergency pausing.
