Design Issues in SapienStaking Contract
| # | Issue | Category | Description |
| --- | --- | --- | --- |
| 1 | Centralized signature authority | Architecture | The contract relies on a single signer address (sapienAddress) for all operations. This creates a central point of failure and trust concern. |
| 2 | No mechanism to update signer address | Flexibility | There's no function to update the sapienAddress if it becomes compromised, requiring a full contract upgrade. |
| 3 | No actual rewards distribution | Functionality | While the contract tracks multipliers for different staking periods, there's no mechanism to actually distribute rewards based on these multipliers. |
| 4 | Limited stake customization | User Experience | Users can only stake for predefined periods (30/90/180/365 days) with fixed multipliers, limiting flexibility. |
| 5 | Lack of composability | DeFi Integration | The contract doesn't provide hooks or interfaces for integration with other DeFi protocols or composability features. |
| 6 | Double verification of order uniqueness | Code Design | Order uniqueness is verified both in public functions and again in the verifyOrder function, creating redundancy. |
| 7 | Immutable penalty percentage | Adaptability | The 20% early withdrawal penalty is hardcoded and cannot be adjusted based on market conditions or governance decisions. |
| 8 | Static domain separator | Protocol Safety | The domain separator is set only at initialization and doesn't update if the chain ID changes (e.g., during a fork). |
| 9 | No emergency withdrawal mechanism | Safety | Users cannot withdraw funds in case of emergency without going through the regular process. |
| 10 | Unclear reward mechanism relationship | Documentation | The contract tracks multipliers but doesn't explain how these will translate to actual rewards. |
| 11 | Non-standard naming conventions | Code Style | Public state variables like gnosisSafe use underscore prefix typically reserved for private variables. |
| 12 | No batch operations | Scalability | Users must initiate separate transactions for each stake/unstake operation, increasing gas costs for users with multiple positions. |
| 13 | Lack of events for cooldown state changes | Observability | When a partial unstake resets a cooldown, no event is emitted to notify off-chain systems of this state change. |
| 14 | No way to cancel unstaking | User Experience | Once unstaking is initiated, there's no way to cancel it and return to regular staking status. |
| 15 | Redundant isActive flag | Code Design | The isActive flag is redundant since a position's active status can be determined by checking if amount > 0. |
| 16 | No consideration for fee-on-transfer tokens | Token Compatibility | The contract assumes standard ERC20 behavior and doesn't account for tokens that may implement transfer fees. |
| 17 | Fixed cooldown period | Adaptability | The 2-day cooldown period is hardcoded and cannot be adjusted based on market conditions or governance decisions. |
| 18 | Unclear purpose of multipliers | Business Logic | The multipliers are tracked but it's unclear how they're utilized in the broader system context. |
| 19 | No timelock for critical changes | Governance | Critical operations like pausing have no timelock, allowing immediate changes that could affect users. |
| 20 | Inconsistent MINIMUM_STAKE enforcement | User Experience | The initiateUnstake function doesn't enforce the MINIMUM_STAKE requirement, creating inconsistency in the user experience. |