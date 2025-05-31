Security Issues in SapienToken Contract
| # | Issue | Severity | Description |
| --- | --- | --- | --- |
| 1 | Debug import in production code | Medium | The contract imports hardhat/console.sol, which should not be present in production code as it increases contract size and could expose debugging information. |
| 2 | Single point of failure for initial token distribution | High | All tokens are initially minted to the deployer (msg.sender) who is then expected to forward them to a multisig, creating a temporary centralization risk. |
| 3 | No check for total supply overflow | Medium | The calculation of expectedSupply by adding all allocations doesn't verify that the sum doesn't overflow. While unlikely with current values, it's a potential issue. |
| 4 | Naming convention violation for public variables | Low | The variable _gnosisSafe uses an underscore prefix despite being public, which contradicts Solidity naming conventions and may cause confusion. |
| 5 | Missing zero check for _authorizeUpgrade | Medium | The _authorizeUpgrade function doesn't verify that newImplementation is not the zero address before performing operations on it. |
| 6 | Unchecked arithmetic in vesting calculations | Medium | The calculation of vesting periods and amounts doesn't use SafeMath or unchecked blocks appropriately, potentially leading to issues if extreme values are used. |
| 7 | No timelock for critical vesting changes | Medium | The updateVestingSchedule function allows immediate changes to vesting parameters without a timelock, which could lead to sudden changes in vesting terms. |
| 8 | Inconsistent validation in updateVestingSchedule | Low | Validation for start > block.timestamp is enforced for all schedules, but this could prevent recovering from a misconfiguration of past dates. |
| 9 | Hard-coded vesting durations | Medium | All vesting durations are hard-coded to 48 months with no provision for future changes to this parameter except through contract upgrades. |
| 10 | Missing event emission for important state changes | Low | Some state changes (like tokens being minted during initialization) don't emit specific events, reducing off-chain observability. |
| 11 | No validation for enum bounds | Medium | The contract doesn't validate that the allocationType parameter is within the valid enum range, potentially allowing out-of-bounds access. |
| 12 | Compiler version mismatch | Low | The contract specifies Solidity 0.8.24, which may not match the compiler version used for deployment, leading to potential issues. |
| 13 | Implicit conversion from days to seconds | Low | The use of days as a time unit assumes 1 day = 86400 seconds, which doesn't account for daylight saving time or leap seconds. |
| 14 | Potential frontrunning of reward contract changes | Medium | The two-step rewards contract change process could be frontrun between steps if the timespan between the two transactions is long. |
| 15 | No token recovery mechanism | Medium | There's no mechanism to recover tokens accidentally sent to the contract, potentially leading to permanent loss of tokens. |
| 16 | Domain separation for upgrades | Medium | The authorizeUpgrade and _authorizeUpgrade functions handle the same behavior but are separated, potentially leading to desynchronization if one is modified without the other. |
| 17 | Lack of input validation for allocation types | Medium | The updateVestingSchedule function only checks if amount > 0 to validate an allocation type exists, which might not be sufficient in all cases. |
| 18 | No maximum limit for vesting amounts | Low | There's no upper bound check for vesting amounts, potentially allowing excessive amounts to be set. |
| 19 | Missing check for zero duration | Medium | When schedule.duration == 0, all tokens become immediately releasable, which could be an issue if duration is accidentally set to zero. |
| 20 | Console.sol import creates contract size concerns | Low | The import of the Hardhat Console library increases contract size, potentially causing the contract to approach size limits if additional features are added. |