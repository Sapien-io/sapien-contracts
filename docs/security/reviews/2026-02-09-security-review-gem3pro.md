# Security Review Report

**Date**: 2026-02-09
**Target**: `src/` (Sapien V2 Protocol)
**Reviewer**: AI Assistant (Cursor)

## Executive Summary

A comprehensive security review was performed on the Sapien V2 protocol contracts. The review focused on the core logic in `SapienCore`, `ValidationOracle`, `SapienVault`, `SapienTrust`, and `Rewards`.

The protocol follows best practices such as the Checks-Effects-Interactions (CEI) pattern, usage of `ReentrancyGuard`, and Access Control. Previous known issues (marked as fixes in comments) were verified to be correctly implemented.

No Critical or High severity vulnerabilities were identified. A few Low/Informational findings are documented below.

## Findings

### [LOW] Potential Gas Intensity in `cancelExpiredCommitment`

**Location**: `ValidationOracle.sol:935`

**Description**:
The `cancelExpiredCommitment` function iterates over `validationCommits[projectId][contributionIndex]`. The number of iterations is determined by the number of validators who have committed to a contribution.

**Impact**:
While `maxValidations` is currently capped at 100 (enforced by `SapienCore` and `ValidationOracle`), effectively bounding this loop, future upgrades or misconfiguration could increase this limit. If the array becomes too large, this function could hit the block gas limit, preventing the clearing of expired commits and potentially stalling the queue for that contribution.

**Recommendation**:
Ensure `maxValidations` remains strictly bounded. Consider implementing a way to process slashings in batches if `maxValidations` is ever increased significantly.

### [INFORMATIONAL] Liveness Dependency on Keepers

**Location**: `ValidationOracle.sol`

**Description**:
If a validator commits but fails to reveal within the deadline, the validation slot remains occupied and the contribution cannot reach consensus until `cancelExpiredCommitment` is called. The protocol does not automatically slash expired validators; it requires an external transaction.

**Impact**:
Contributions could be "stuck" in a pending state if no one calls `cancelExpiredCommitment`. While anyone can call this function, there is no direct on-chain incentive (bounty) for a third party to do so, other than the contributor wanting their submission processed.

**Recommendation**:
Document this dependency clearly. Consider adding a small tip/bounty mechanism for the caller of `cancelExpiredCommitment` to incentivize keepers to clean up stuck states, or rely on the contributor's self-interest.

### [INFORMATIONAL] Protocol Fee Reset in Initializer

**Location**: `SapienCore.sol:142`

**Description**:
The `initialize` function sets `protocolFeeBasisPoints` to 100 (1%). The `MAX_PROTOCOL_FEE_BPS` constant is 300 (3%).

**Impact**:
This is standard for upgradeable contracts, but it's worth noting that `protocolFeeBasisPoints` is hardcoded in the initializer. If the logic were different (e.g. if this were a constructor in a non-upgradeable contract), it might be less flexible. In the proxy pattern, this only executes once.

**Recommendation**:
Ensure that any future re-initializers (for upgrades) do not accidentally reset fee parameters if they are intended to be persistent.

## Scope Checked

- [x] `SapienCore.sol`: Project management, contribution flow, funding.
- [x] `ValidationOracle.sol`: Validator selection, commit-reveal, consensus trigger.
- [x] `SapienVault.sol`: Staking, locking, slashing.
- [x] `SapienTrust.sol`: Reputation management, role checks.
- [x] `Rewards.sol`: Reward allocation and distribution.
- [x] `ConsensusLib.sol`: Math and outlier detection logic.

## Conclusion

The codebase appears robust. Key security properties (Sybil resistance, stake locking, reentrancy protection) are implemented correctly. The "Low" finding regarding gas limits is currently mitigated by the `maxValidations` cap.
