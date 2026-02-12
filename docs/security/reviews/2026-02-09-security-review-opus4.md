# Security Review Report

**Date**: 2026-02-09
**Target**: `src/` (Sapien V2 Protocol — all 17 `.sol` files)
**Reviewer**: AI Security Review (Claude Opus 4.6)
**Methodology**: Function-by-function analysis following the Solidity Security Review skill (Phase 1-3)
**Solidity Version**: ^0.8.30

---

## Executive Summary

A systematic security review was performed on the entire Sapien V2 protocol. The review covered all core contracts (`SapienCore`, `ValidationOracle`, `SapienVault`, `SapienTrust`, `Rewards`), the `ConsensusLib` library, all four consensus algorithm implementations, and all interfaces.

The protocol demonstrates strong security fundamentals: CEI pattern adherence, `ReentrancyGuard` usage, `AccessControl` roles, `SafeERC20`, ERC-4626 inflation protection, and commit-reveal integrity. Many previously identified issues (annotated as "Issue #N fix" in comments) are correctly resolved.

However, this review identified **2 Medium**, **5 Low**, and **6 Informational** findings. The two Medium findings involve a **reward pool depletion vector** from double-paying validator rewards on rejected-then-resubmitted contributions, and an **incomplete deadline snapshot fix** that allows originators to prematurely expire validator commitments.

### Findings Summary

| Severity | Count | Description |
|----------|-------|-------------|
| Critical | 0 | — |
| High | 0 | — |
| Medium | 2 | Reward pool depletion; incomplete reveal deadline snapshot |
| Low | 5 | Claim counter drift; missing zero-checks; deposit pause gap; anti-dilution fee mismatch; core re-assignment |
| Informational | 6 | Gas, style, and design observations |

---

## Findings

---

### [MEDIUM] M-1: Double Validator Reward Payout on Rejected-Then-Accepted Contributions

**Location**: `SapienCore.sol:_finalizeContribution():726-733` and `_distributeValidatorRewards()`

**Description**: When a contribution is finalized, `_processValidators()` is called **unconditionally** — regardless of whether the contribution was accepted or rejected. This means validators who participated in a rejected contribution still receive their proportional reward from the project's reward pool. When the same contribution index is later re-submitted by a new contributor, re-validated, and accepted, a second batch of validators is also paid from the same pool.

The validator reward per finalization is approximately:

```
validatorPayout ≈ totalRewardsAvailable × validatorBps / (10000 × totalQuantityAvailable)
```

For a project with `totalRewardsAvailable = 1000`, `validatorBps = 1000` (10%), and `totalQuantityAvailable = 10`:
- Each finalization pays ~10 in validator rewards
- 10 accepted contributions consume 900 (contributor) + 100 (validator) = 1000 ✓
- But if 2 contributions were rejected first: 2 × 10 = 20 extra validator rewards
- Total attempted payout: 900 + 120 = 1020 > 1000 funded

**Impact**: The project's reward pool (`projectRewards` in `Rewards.sol`) is drained faster than intended. Later `distributeReward` or `distributeValidatorReward` calls revert with `InsufficientProjectRewards`, permanently blocking finalization of remaining contributions. This effectively DoS's project completion.

**Attack Scenario**: A malicious contributor deliberately submits low-quality work to cause rejections. Each rejection still pays validator rewards, draining the pool. The contributor's cost is only the staking requirement (not slashed on rejection — only on claim expiry). After enough rejections, the project cannot pay future contributors or validators.

**Proof of Concept**:
```
1. Originator creates project: 1000 tokens, 10 slots, 10% validator rewards
2. Attacker claims and submits garbage for 3 slots (gets rejected)
3. Each rejection: validators paid ~10 tokens = 30 tokens drained for validator rewards
4. Legitimate contributors submit and get accepted for all 10 slots
5. 10 accepted: 900 (contributor) + 100 (validator) attempted = 1000
6. But pool is only 1000 - 30 = 970 after rejection payouts
7. Last 3 finalizations revert: InsufficientProjectRewards
```

**Recommendation**: Skip validator reward distribution for rejected contributions, or deduct rejected-contribution validator rewards from the validator reward budget (not the general pool):

```solidity
// In _finalizeContribution, only process validator rewards for accepted contributions:
if (accepted) {
    _processValidators(projectId, contributionIndex, project, report.validatorsToSlash, report.slashAmounts, report.validatorWeights);
} else {
    // Only slash outliers on rejection, don't distribute rewards
    _slashOutlierValidators(projectId, contributionIndex, report.validatorsToSlash, report.slashAmounts);
}
```

Alternatively, track a separate "validator reward budget used" counter and cap total validator payouts at `totalRewardsAvailable × validatorBps / 10000`.

---

### [MEDIUM] M-2: Incomplete Reveal Deadline Snapshot — Premature Commit Expiry

**Location**: `ValidationOracle.sol:_isCommitExpired():665-677`, `_checkConsensusReady():740-771`, `_appendExpiredSlashes():689-729`, `cancelExpiredCommitment():926-978`

**Description**: The M-2 fix (commit `revealDeadlineSnapshot`) was correctly applied to `_revealValidation()` (line 566), ensuring validators can reveal within the deadline that was in effect when they committed. However, the expiry/consensus logic uses the **current project-level** `revealDeadline` instead of the per-commit snapshot:

- `_isCommitExpired()` receives `deadline` from caller, which is always `settings.revealDeadline` (current)
- `_checkConsensusReady()` uses `settings.revealDeadline` (line 759)
- `_appendExpiredSlashes()` uses `settings.revealDeadline` (line 698)
- `cancelExpiredCommitment()` uses `settings.revealDeadline` (line 932)

This creates an inconsistency: a validator's reveal window uses the snapshot (correct), but the system considers the commit "expired" based on the current deadline (incorrect).

**Impact**: An originator can:
1. Set `revealDeadline` to 3 days
2. Wait for validators to commit (their snapshot = 3 days)
3. Call `setProjectRevealDeadline(projectId, 1 hours)` (minimum allowed)
4. `getConsensus` now considers those commits expired → slashes validators
5. `cancelExpiredCommitment` can also be called to slash and burn validators' capacity
6. Validators lose staked tokens despite not violating their committed deadline

The minimum deadline check in `setProjectRevealDeadline` (Issue #2 fix) was intended to prevent this, but MIN_REVEAL_DEADLINE (1 hour) is much shorter than the default (3 days), leaving a wide exploitation window.

**Proof of Concept**:
```
1. Project created with default revealDeadline = 3 days
2. Validator commits at T=0 (snapshot = 3 days)
3. Originator calls setProjectRevealDeadline(projectId, 3600) at T=1 hour
4. At T=2 hours: cancelExpiredCommitment succeeds (2h > 1h deadline)
5. Validator is slashed despite having 3 days to reveal per their snapshot
```

**Recommendation**: Use `commit.revealDeadlineSnapshot` consistently in all expiry checks:

```solidity
function _isCommitExpired(ValidationCommit memory commit, uint256 submittedAt, uint256 /* unused */)
    internal view returns (bool)
{
    if (commit.committedAt < submittedAt || commit.revealed) return false;

    // Use per-commit snapshot instead of current project deadline
    uint256 deadline = commit.revealDeadlineSnapshot;
    if (deadline == 0) deadline = revealDeadline; // Fallback for legacy
    return block.timestamp > commit.committedAt + deadline;
}
```

Apply the same pattern in `cancelExpiredCommitment` (line 937) and `_checkConsensusReady` (line 759-765).

---

### [LOW] L-1: `userActiveClaimedQuantity` Not Decremented in `releaseExpiredClaim`

**Location**: `SapienCore.sol:releaseExpiredClaim():529-552`

**Description**: When `releaseExpiredClaim` is called, the claim is marked `Expired` and the contributor's locked stake is slashed. However, `userActiveClaimedQuantity[projectId][contributor]` is **not** decremented. It is only decremented per-index in `reclaimExpiredIndices` (line 425-427) and `_contribute` (line 611-613).

**Impact**: After `releaseExpiredClaim`, the user's active claim counter remains inflated. The user cannot create new claims because the `MAX_CLAIMS_PER_USER` check (line 443) will fail until `reclaimExpiredIndices` is called for each individual index. This creates a soft-lock requiring external action (anyone calling `reclaimExpiredIndices`) to restore the user's ability to participate.

**Recommendation**: Decrement `userActiveClaimedQuantity` in `releaseExpiredClaim` by the unsubmitted quantity:

```solidity
uint256 unsubmittedSlots = claim.quantity - claim.submittedCount;
if (userActiveClaimedQuantity[projectId][claim.contributor] >= unsubmittedSlots) {
    userActiveClaimedQuantity[projectId][claim.contributor] -= unsubmittedSlots;
}
```

---

### [LOW] L-2: Anti-Dilution Check Uses Pre-Fee Amount

**Location**: `SapienCore.sol:_fundProject():338-342`

**Description**: The anti-dilution check compares reward rates using `rewardAmount` (the gross amount before protocol and operator fees are deducted):

```solidity
if (rewardAmount * project.state.totalQuantityAvailable < project.state.totalRewardsAvailable * quantity) {
    revert("Cannot dilute reward rate");
}
```

However, `project.state.totalRewardsAvailable` is updated with `rewardAmountAfterFee` (post-fee). This means the check permits funding that appears non-dilutive based on the gross amount but actually dilutes the reward rate after fees are taken.

**Impact**: With a combined 3% (protocol + operator) fee, the effective reward per slot can decrease by up to 3% while passing the anti-dilution check. For example, with existing rate of 100 tokens/slot: new funding at exactly 100/slot passes the check, but the effective rate becomes ~97/slot after fees.

**Recommendation**: Use `rewardAmountAfterFee` in the anti-dilution check, or perform the check after fee calculation:

```solidity
if (rewardAmountAfterFee * project.state.totalQuantityAvailable < project.state.totalRewardsAvailable * quantity) {
    revert("Cannot dilute reward rate");
}
```

---

### [LOW] L-3: Missing Input Validation in `claimToContribute` and `createProject`

**Location**: `SapienCore.sol:claimToContribute():437`, `createProject():222`

**Description**:
1. `claimToContribute` does not validate `quantity > 0`. Calling with `quantity=0` creates a claim with no indices that can never transition to `Fulfilled`. The claim consumes a `claimId` slot, emits a misleading `ClaimCreated` event with quantity 0, and the locked stake (if any) cannot be unlocked via normal finalization flow.

2. `createProject` does not validate `rewardToken != address(0)`. A project created with zero-address reward token is permanently broken — funding attempts will revert at the `safeTransferFrom` call.

**Impact**: State pollution and wasted gas. No direct fund loss, but creates orphaned state that can never be cleaned up.

**Recommendation**: Add input validation:

```solidity
// In claimToContribute:
if (quantity == 0) revert InvalidAmount();

// In createProject:
if (rewardToken == address(0)) revert InvalidAddress();
```

---

### [LOW] L-4: `deposit` and `mint` Not Paused in SapienVault

**Location**: `SapienVault.sol` (inherited ERC4626 functions)

**Description**: The `SapienVault` applies `whenNotPaused` to `transfer`, `transferFrom`, `withdraw`, and `redeem`, but the `deposit` and `mint` functions inherited from `ERC4626Upgradeable` are not gated by the pause modifier.

**Impact**: During an emergency pause, users can deposit tokens into the vault but cannot withdraw. Tokens deposited during a pause become trapped until unpausing. This is particularly concerning if the pause was triggered due to a vulnerability — deposits during this window could increase the attack surface.

**Recommendation**: Override `deposit` and `mint` to add `whenNotPaused`:

```solidity
function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256) {
    return super.deposit(assets, receiver);
}

function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256) {
    return super.mint(shares, receiver);
}
```

---

### [LOW] L-5: `Rewards.setCore` Allows Unrestricted Core Re-Assignment

**Location**: `Rewards.sol:setCore():114-119`

**Description**: The `IRewards` interface defines `error CoreAlreadySet()`, suggesting core should only be set once. However, the implementation allows the admin to re-set the core address at any time with no restriction. The `onlyCore` modifier gates `allocateRewards`, `distributeReward`, and `distributeValidatorReward` — all functions that move tokens between accounting buckets.

**Impact**: If the admin key is compromised, the attacker can set `core` to a malicious contract that calls `distributeReward` to credit arbitrary amounts to any address, then claim those rewards. Unlike other admin actions (pause, fee changes), this enables direct theft of all allocated project rewards.

**Recommendation**: Implement a timelock or one-time-set pattern:

```solidity
function setCore(address _core) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (_core == address(0)) revert InvalidAddress();
    if (core != address(0)) revert CoreAlreadySet();
    core = _core;
    emit CoreAddressUpdated(_core);
}
```

Or use a two-step ownership transfer pattern with a timelock.

---

### [INFORMATIONAL] I-1: `createProject` Visibility

**Location**: `SapienCore.sol:222`

`createProject` is marked `public` but is not called internally. Using `external` saves a small amount of gas by avoiding the ABI encoding of `memory` parameters.

---

### [INFORMATIONAL] I-2: HybridConsensus Missing Reputation Floor

**Location**: `HybridConsensus.sol:66`

`HybridConsensus._calculateInitialWeights` computes `repWeight = (sqrtStake * reputation) / 10000` without applying `ConsensusLib.MIN_REPUTATION_FLOOR`. For very small stakes, this can round to zero weight. While `SapienTrust` enforces `MIN_REPUTATION = 500`, the consensus algorithm doesn't validate this, unlike `CappedLinearConsensus` which uses `calculateBaseWeight` with a floor.

---

### [INFORMATIONAL] I-3: Monotonically Growing Queue Indices

**Location**: `ValidationOracle.sol:pendingQueue`, `queueHead`, `queueTail`

Queue indices only increase. Previous `pendingQueue` storage slots (before `queueHead`) are never deleted. Over the lifetime of a high-volume project, this accumulates unbounded storage that is never reclaimed. In practice, storage costs are paid at write time on Base L2, so this is mainly a storage hygiene concern.

---

### [INFORMATIONAL] I-4: Daily Reputation Gain Limit Shared Across Roles

**Location**: `SapienTrust.sol:dailyReputationGain`, `lastGainUpdateDay`

`dailyReputationGain` and `lastGainUpdateDay` are per-user, not per-user-per-role. A user active as both `CONTRIBUTOR` and `VALIDATOR` in the same day shares a single `MAX_DAILY_GAIN = 100` (1%) cap across both roles. This may inadvertently throttle multi-role participants. Consider making the tracking per-user-per-role if independent reputation growth is desired.

---

### [INFORMATIONAL] I-5: Keeper Incentive Gap for Expired Commitment Cleanup

**Location**: `ValidationOracle.sol:cancelExpiredCommitment()`, `cancelExpiredValidationClaim()`

These functions can be called by anyone to clean up expired validator commitments, which is critical for protocol liveness. However, there is no on-chain incentive (bounty/tip) for callers. The protocol relies on altruistic actors or the affected contributor to trigger cleanup. A small bounty from the slashed amount would strengthen liveness guarantees.

---

### [INFORMATIONAL] I-6: Validator Can Receive Duplicate Queue Assignments

**Location**: `ValidationOracle.sol:claimToValidate():175-238`

The validation queue creates `numberOfValidations` entries per contribution index. A validator calling `claimToValidate` multiple times may be assigned the same `contributionIndex` multiple times if it appears consecutively in the queue. While `assignment.hasCommitted` prevents double-commits, the duplicate assignment wastes a queue slot that another validator could have used. Consider adding a check to skip indices the validator is already assigned to.

---

## Scope Verified

- [x] `SapienCore.sol` — Project management, contribution lifecycle, funding, finalization
- [x] `ValidationOracle.sol` — Validator assignment, commit-reveal, consensus trigger, capacity management
- [x] `SapienVault.sol` — ERC-4626 staking, locking, slashing, transfer restrictions
- [x] `SapienTrust.sol` — Reputation decay, skill validation, role-based stake checks
- [x] `Rewards.sol` — Reward allocation, distribution, claiming, operator fees
- [x] `ConsensusLib.sol` — Weighted average, std dev, outlier detection, weight capping, sqrt
- [x] `CappedLinearConsensus.sol` — Stake × reputation with 30% cap
- [x] `HybridConsensus.sol` — sqrt(stake) × reputation with 30% cap
- [x] `LinearStakeConsensus.sol` — Linear stake weighting
- [x] `SqrtStakeConsensus.sol` — Square root stake weighting
- [x] All 7 interface files (`ISharedTypes`, `ISapienCore`, `ISapienTrust`, `ISapienVault`, `IRewards`, `IValidationOracle`, `IConsensusAlgorithm`)

### Cross-Contract Interactions Verified

- [x] Core → Oracle: `registerProject`, `enqueueValidation`, `setContributionContributor`, `resetContributionState`, `handleValidatorSlash`, `getConsensus`, `getValidations`
- [x] Core → Trust: `hasEnoughStakeForRole`, `updateReputation`, `validateSkill`, `getTrustScore`
- [x] Core → Vault: `getStake`, `lockStake`, `unlockStake`, `slash`, `getLockedStake`
- [x] Core → Rewards: `allocateRewards`, `distributeReward`, `distributeValidatorReward`
- [x] Oracle → Trust: `hasEnoughStakeForRole`, `hasRequiredStake`, `getTrustScore`, `hasValidatedSkill`, `roleMinStake`, `minStakeRequired`, `updateReputation`
- [x] Oracle → Vault: `lockStake`, `unlockStake`, `slash`, `getAvailableStake`, `getLockedStake`

### Security Properties Verified

| Property | Status | Notes |
|----------|--------|-------|
| Reentrancy protection | ✅ Pass | `nonReentrant` on all state-mutating entry points with external calls |
| Access control | ✅ Pass | Role-based (ORIGINATOR, CONTRIBUTOR, VALIDATOR, CORE, ADMIN, LOCKER, SLASHER, PAUSER, UPDATER) |
| CEI pattern | ✅ Pass | Effects before interactions throughout |
| ERC-4626 inflation attack | ✅ Pass | `_decimalsOffset() = 3` |
| Commit-reveal integrity | ✅ Pass | Hash includes committed stake amount (prevents 1-Wei Shield Attack) |
| SafeERC20 usage | ✅ Pass | All ERC-20 transfers use SafeERC20 |
| Fee-on-transfer compatibility | ✅ Pass | Balance-before/after check in `_fundProject` |
| Sybil separation | ✅ Pass | Originator ≠ Contributor ≠ Validator enforced |
| Upgrade safety | ✅ Pass | `_disableInitializers()` in constructors, storage gaps present |
| Overflow protection | ✅ Pass | Solidity 0.8.30 built-in checks; minimal `unchecked` usage (loop counters only) |

---

## Conclusion

The Sapien V2 protocol demonstrates mature security practices with many previously identified issues already addressed. The two Medium findings (M-1: validator reward pool depletion, M-2: incomplete deadline snapshot) represent real economic risks that should be addressed before mainnet deployment. M-1 is the higher priority — it enables a low-cost griefing attack that can permanently prevent project completion. M-2 requires originator collusion but breaks a security guarantee the protocol explicitly aims to provide.

### Priority Fixes

1. **M-1** (Highest): Skip validator reward distribution on rejected contributions, or implement a validator reward budget cap
2. **M-2** (High): Use `commit.revealDeadlineSnapshot` in all expiry checks for consistency with the reveal logic
3. **L-1** (Medium): Fix `userActiveClaimedQuantity` tracking in `releaseExpiredClaim`
4. **L-4** (Medium): Pause deposits during emergency to prevent token trapping
5. **L-2, L-3, L-5** (Lower): Input validation and access control hardening
