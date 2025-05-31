Functional Correctness Review of SapienStaking Contract
| # | Issue | Severity | Description |
| --- | --- | --- | --- |
| 1 | Missing amount validation in instantUnstake | Critical | The instantUnstake function doesn't verify that amount <= info.amount, allowing users to withdraw more than they've staked. |
| 2 | Missing zero amount check in initiateUnstake | Medium | Users can initiate unstaking with 0 tokens, which creates unnecessary state changes and events. |
| 3 | Inconsistent minimum stake enforcement | Medium | Unlike stake() and unstake(), the initiateUnstake() function doesn't enforce the MINIMUM_STAKE requirement. |
| 4 | Improper transferOwnership implementation | Medium | The function incorrectly emits OwnershipTransferred without following the two-step process properly. |
| 5 | Double verification of orderId uniqueness | Low | The verifyOrder function redundantly checks for order uniqueness which is already checked in the calling functions. |
| 6 | Duplicate lock period check in unstake | Low | The unstake function checks if the lock period is completed, but this was already checked during initiateUnstake. |
| 7 | No stakeOrderId existence validation | Low | In functions like instantUnstake, there's no check if the stakeOrderId exists for the user. |
| 8 | Missing require for amount > 0 | Low | Multiple functions don't verify that amount > 0, potentially allowing meaningless transactions. |
| 9 | No clean reset of StakingInfo | Low | When a position is fully unstaked, not all fields of StakingInfo are reset to default values. |
| 10 | Redundant check in calculateMultiplier | Low | The function has multiple checks but the lockUpPeriod is already validated in stake(), making the revert unreachable. |
| 11 | Missing event for cooldown state reset | Info | When a partial unstake resets the cooldown state, no event is emitted to indicate this change. |
| 12 | Lack of withdrawal and rewards mechanism | Info | While multipliers are tracked, there's no mechanism to use these multipliers for rewards distribution. |
| 13 | Unimplemented staking rewards | Info | Despite tracking multipliers, there's no functionality to distribute rewards based on these multipliers. |
| 14 | Domain separator not updatable | Info | If the chain ID changes (e.g., due to a fork), the domain separator won't be updated, requiring a contract upgrade. |
| 15 | No maximum limit on stake amount | Info | The contract doesn't implement a maximum stake amount, potentially allowing excessive concentration of funds. |