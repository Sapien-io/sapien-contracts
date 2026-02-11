# Release Blockers

The following issues MUST be resolved before deployment to mainnet.

## Critical Blockers (Protocol Failure)

### 1. [F-01] Storage Collision in SapienCore
- **Impact:** Upgrading the contract will corrupt all global configurations (deadlines, fees, consensus thresholds) because the `userActiveClaimedQuantity` mapping shifts their storage slots.
- **Action:** Move the mapping to the end of the state variables before the gap.

### 2. [F-03] Missing Role Grant Logic
- **Impact:** The protocol will be DOA (Dead On Arrival). `SapienCore` and `ValidationOracle` will revert on every interaction because they lack the `UPDATER_ROLE` on `SapienTrust`.
- **Action:** Add role grant logic to the deployment scripts or initialization functions.

## High Blockers (Financial/Security Risk)

### 3. [F-02] Oracle Trust Assumption
- **Impact:** The system is vulnerable to a single point of failure. If the oracle is compromised, malicious consensus results will lead to immediate theft of rewards and slashing of honest users.
- **Action:** Implement a challenge period or a secondary verification step for finalized contributions.

## Operational Blockers (Incentives/Usability)

### 4. [F-07] Validator Reward Rounding to Zero
- **Impact:** For projects using tokens with low decimals (e.g., USDC), validators will frequently receive 0 rewards for their work, leading to a collapse of the validation pool.
- **Action:** Implement higher precision math or a minimum reward floor.

---
*Note: All other findings in `risk_matrix.json` are considered non-blocking but should be addressed in subsequent sprints.*
