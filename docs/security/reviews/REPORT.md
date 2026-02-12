# Sapien PoQ Protocol Audit Report

## 1. Executive Summary

The audit of the Sapien PoQ (Proof of Quality) protocol focused on the security, upgradeability, and economic incentives of the core smart contracts. The most significant finding is a **CRITICAL** storage layout shift in `SapienCore.sol`, which would result in the corruption of all protocol-wide configuration variables (e.g., claim deadlines, fee basis points, treasury address) if the contract is upgraded.

Furthermore, several **MEDIUM** severity economic risks were identified. These include potential rounding-to-zero errors in validator rewards, which could disincentivize participation, and liveness griefing scenarios where malicious validators can delay project finalization.

The protocol currently relies heavily on a centralized `DEFAULT_ADMIN_ROLE`, which has the power to upgrade contracts, pause the protocol, and perform emergency withdrawals of reward tokens. While the "Proof of Quality" mechanism decentralizes the validation process, the governance and emergency controls remain concentrated.

### Risk Rating
- **Upgradeability Risk**: CRITICAL
- **Economic Risk**: MEDIUM
- **Centralization Risk**: HIGH (8/10)

---

## 2. Scope

The following contracts were included in the audit:
- `SapienCore.sol`: Central coordinator for projects and contributions.
- `ValidationOracle.sol`: Manages consensus and validation logic.
- `SapienVault.sol`: Handles user stakes and reputation.
- `Rewards.sol`: Manages reward distribution and claims.
- `SapienTrust.sol`: Manages trust and relationship data.
- `consensus/*.sol`: Pluggable consensus algorithms.

---

## 3. Severity Definitions

| Severity | Description |
| :--- | :--- |
| **CRITICAL** | Direct risk of fund loss, protocol-wide corruption, or permanent denial of service. |
| **MEDIUM** | Significant impact on protocol functionality or incentives, but requires specific conditions or is not immediately fatal. |
| **LOW** | Minor issues, optimization opportunities, or deviations from best practices. |

---

## 4. Summary of Findings

| ID | Title | Severity | Category | Status |
| :--- | :--- | :--- | :--- | :--- |
| C-01 | Storage Layout Shift in `SapienCore.sol` | CRITICAL | Upgradeability | Fixed |
| M-01 | Validator Rewards Rounding to Zero | MEDIUM | Economic | Fixed |
| M-02 | Liveness Griefing via Reveal Delay | MEDIUM | Economic | Fixed |
| M-03 | Validator Queue Monopoly by Whales | MEDIUM | Economic | Fixed |
| M-04 | Reward Rate Manipulation (Sandwiching) | MEDIUM | Economic | Fixed |
| M-05 | Storage Gap Inconsistency in `ValidationOracle.sol` | MEDIUM | Upgradeability | Fixed |
| L-01 | Missing Pause Protection on Admin Functions | LOW | Security | — |
| L-02 | Emergency Withdrawal Risk in `Rewards.sol` | LOW | Security | — |
| L-03 | Unbounded Loops in Batch Functions | LOW | DoS | Fixed |
| L-04 | Strategic Non-Reveal to Evade Slashing | LOW | Game Theory | — |
| L-05 | Reputation Incentive Decoupling | LOW | Game Theory | — |
| L-06 | Unreclaimable Reward Dust | LOW | Economic | — |
| L-07 | Redundant Storage Gap in `SapienVault.sol` | LOW | Upgradeability | — |

---

## 5. Detailed Findings

### [C-01] Storage Layout Shift in `SapienCore.sol`
**Severity**: CRITICAL
**File**: `src/SapienCore.sol`

**Description**:
The mapping `userActiveClaimedQuantity` was inserted into the middle of the state variable list (line 63). In upgradeable contracts (using the Transparent Proxy pattern), adding new variables in the middle of existing ones shifts the storage slots of all subsequent variables.

**Impact**:
When the contract is upgraded, existing values for `_claimDeadlineDays`, `_maxValidations` [Note: since refactored to per-project `numberOfValidations`], `protocolFeeBasisPoints`, `treasury`, and `consensusThreshold` will be read from incorrect slots. This leads to protocol-wide configuration corruption, potentially setting the treasury to a zero address, breaking fee logic, or making consensus impossible to reach.

**Recommendation**:
Move `userActiveClaimedQuantity` to the end of the state variable list, just before the `__gap` array, and decrement the gap size by 1 (from 32 to 31).

---

### [M-01] Validator Rewards Rounding to Zero
**Severity**: MEDIUM
**File**: `src/SapienCore.sol`

**Description**:
In `_distributeValidatorRewards`, the reward calculation `(totalRewards * validatorBasisPoints * weight) / (10000 * totalQuantity * totalAccurateWeight)` can round to zero if the denominator is larger than the numerator. This is likely when using `SqrtStakeConsensus` (small weights) or projects with large `totalQuantityAvailable` and low-decimal tokens (e.g., USDC).

**Impact**:
Validators receive zero rewards for their work, breaking the protocol's incentive loop and potentially leading to a lack of validators for certain projects.

**Recommendation**:
Implement a minimum reward check or increase precision by multiplying the numerator by a factor (e.g., `1e18`) before division and scaling back at the final claim step.

---

### [M-02] Liveness Griefing via Reveal Delay
**Severity**: MEDIUM
**File**: `src/ValidationOracle.sol`

**Description**:
Consensus is only "ready" when `numberOfValidations` is met AND all pending commits have either revealed or expired. A malicious validator can commit and then intentionally withhold their reveal, forcing the protocol to wait for the full `revealDeadline` (default 3 days) before consensus can be finalized.

**Impact**:
Stalling contributor rewards and project progress for days, potentially damaging the reputation and utility of the Sapien protocol.

**Recommendation**:
Allow consensus to be finalized once `numberOfValidations` are met if a "super-majority" of reveals are already present, even before the deadline.

---

### [M-03] Validator Queue Monopoly by Whales
**Severity**: MEDIUM
**File**: `src/ValidationOracle.sol`

**Description**:
While contributors are limited by `MAX_CLAIMS_PER_USER`, validators are only limited by their capacity (locked stake). A whale can set a high capacity and claim all validation slots for a project, preventing others from participating.

**Impact**:
Centralization of validation power and potential manipulation of consensus outcomes.

**Recommendation**:
Implement a per-user limit on active validation claims, similar to the contributor limit.

---

### [M-04] Reward Rate Manipulation (Sandwiching)
**Severity**: MEDIUM
**File**: `src/SapienCore.sol`

**Description**:
The reward per contribution is calculated at finalization using the *current* `totalRewardsAvailable`. Since `fundProject` can be called at any time, users can frontrun or backrun `finalizeContribution` to manipulate the reward rate.

**Impact**:
Value extraction from the protocol or dilution of other users' rewards.

**Recommendation**:
Snapshot the reward rate or total rewards at the time of claim/contribution, rather than at finalization.

---

### [M-05] Storage Gap Inconsistency in `ValidationOracle.sol`
**Severity**: MEDIUM
**File**: `src/ValidationOracle.sol`

**Description**:
The storage gap `__gap` was increased to 37, changing the total reserved slots for the contract. This inconsistency can lead to storage collisions in future upgrades if inheriting contracts expect a fixed size.

**Recommendation**:
Adhere to a strict total slot count (e.g., 50) and adjust the gap size precisely when adding/removing variables.

---

## 6. Recommendations Summary

1.  **Fix Storage Layout**: Immediately move the `userActiveClaimedQuantity` mapping in `SapienCore.sol` to the end of the storage layout before deployment/upgrade.
2.  **Harden Incentives**: Address the validator reward rounding issue to ensure all participants are fairly compensated.
3.  **Governance Decentralization**: Transition `DEFAULT_ADMIN_ROLE` to a multi-sig and implement timelocks for critical parameter changes and upgrades.
4.  **Griefing Mitigations**: Implement limits on validator claims and allow for faster finalization once a sufficient number of reveals are present.
