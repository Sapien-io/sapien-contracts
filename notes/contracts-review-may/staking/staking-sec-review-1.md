Security Issues in SapienStaking Contract
| # | Issue | Severity | Description |
| --- | --- | --- | --- |
| 1 | Missing amount validation in instantUnstake | High | The instantUnstake function doesn't verify that amount <= info.amount, which could allow withdrawing more than what was staked. |
| 2 | Static Domain Separator | Medium | The domain separator is only set during initialization and won't update if the chain undergoes a fork, potentially causing signature verification issues post-fork. |
| 3 | Incorrect implementation of transferOwnership | Medium | The function emits OwnershipTransferred immediately instead of waiting for acceptance, breaking the Ownable2Step pattern. |
| 4 | Central point of failure | Medium | All staking operations require signatures from a single address (sapienAddress), creating a single point of failure. |
| 5 | No signature replay protection across contracts | Medium | The EIP-712 implementation doesn't include the contract address in the typed data structure, allowing potential signature reuse on other contracts. |
| 6 | No way to update sapienAddress | Medium | If the signer key is compromised, there's no way to update the signer address without a contract upgrade. |
| 7 | Missing validation for zero amount | Low | The initiateUnstake function doesn't check for amount > 0, potentially allowing initiating unstake for 0 tokens. |
| 8 | Missing stakeOrderId existence check | Low | The instantUnstake function assumes stakeOrderId exists for the user but doesn't check this explicitly. |
| 9 | Compiler version mismatch | Low | The contract specifies version 0.8.24 but is being compiled with 0.8.30, which could lead to unexpected behavior. |
| 10 | Unclear assembly usage | Low | The assembly code for accessing storage isn't well documented and could be difficult to audit. |
| 11 | Potential front-running vulnerability | Low | Signature-based operations could be front-run by malicious actors watching the mempool. |
| 12 | Missing event for cooldown cancellation | Info | When resetting cooldown in the unstake function for partial unstakes, no event is emitted to indicate this state change. |