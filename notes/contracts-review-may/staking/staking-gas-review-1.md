Gas Optimization Recommendations for SapienStaking Contract
| # | Optimization | Impact | Description |
| --- | --- | --- | --- |
| 1 | Replace multiple if-statements with a mapping | Medium | The calculateMultiplier function uses sequential if-statements. Convert this to a mapping of lockUpPeriod => multiplier for gas savings. |
| 2 | Cache storage values in local variables | Medium | In functions like unstake and instantUnstake, repeatedly accessing info struct fields consumes extra gas. Cache these values in local variables. |
| 3 | Use custom errors instead of string errors | Medium | Replace all require statements with custom errors (e.g., error InsufficientStake();) to save deployment and runtime gas. |
| 4 | Optimize verifyOrder function | Medium | The function performs unnecessary checks (like order uniqueness) that are already checked in the calling functions. Remove this redundancy. |
| 5 | Combine similar require statements | Low | Multiple require statements checking the same variable can be combined with && to save gas. |
| 6 | Make _gnosisSafe private instead of public | Low | The address is only needed internally. Making it private will save gas by not auto-generating a getter function. |
| 7 | Remove redundant validation checks | Low | The verifyOrder function duplicates checks for usedOrders[orderId] that are already done in the calling functions. |
| 8 | Avoid unnecessary storage | Low | The isActive boolean in the StakingInfo struct is redundant and can be derived from amount > 0. |
| 9 | Optimize EIP-712 domain separator | Low | Precalculate and hardcode parts of the domain separator that don't change (e.g., keccak256 of static strings). |
| 10 | Use uint8 for EARLY_WITHDRAWAL_PENALTY | Low | Since the value is 20%, it fits in uint8, which uses less storage than uint256. |
| 11 | Pack struct fields | Low | Rearrange the StakingInfo struct fields to pack more values into the same storage slot (e.g., place bool isActive with other smaller fields). |
| 12 | Use unchecked blocks for arithmetic | Low | Operations like info.amount -= amount are protected by require statements, so they can be placed in unchecked blocks to save gas on overflow checks. |
| 13 | Consolidate token transfers | Low | In instantUnstake, combine the two transfers into a single one to the user and another to the safe to save one ERC20 transfer operation. |
| 14 | Pre-increment instead of post-increment | Low | Using ++i instead of i++ is more gas-efficient. Check increments throughout the contract. |
| 15 | Avoid unnecessary SLOAD operations | Medium | Store _gnosisSafe in a local variable in transferOwnership to avoid multiple storage reads. |