# Sapien PoQ Protocol v0.5 — Security Audit Report

**Audit Date:** February 24, 2026
**Protocol Version:** v0.5 (current working branch `v0.5`)
**Scope:** SapienCore.sol, SapienVault.sol, 7 libraries (OriginationLib, ContributionLib, ValidationLib, ConsensusLib, FinalizationLib, DisputeLib, ReputationLib), Types.sol, Constants.sol
**Method:** Manual line-by-line review, state-transition analysis, cross-function interaction modeling, economic path tracing, comparison against prior audit findings (2026-02-18, 2026-02-23)
**Reference:** `docs/pipeline/pipeline.md` severity rubric

---

## Executive Summary

This audit identifies **8 new findings** not covered by the 2026-02-23 report, plus verification of prior-fix status. Several previously-reported HIGH findings (validation claim slot cleanup, late-commit attack, upheld-dispute deadlock, cancelled-project escrow stranding) have been addressed in the current code. However, the fixes introduce new interaction patterns that create fresh attack surfaces.

| Severity | Count | Status |
|----------|-------|--------|
| CRITICAL | 1     | OPEN   |
| HIGH     | 3     | OPEN   |
| MEDIUM   | 3     | OPEN   |
| LOW      | 3     | OPEN   |
| INFO     | 2     | OPEN   |

### Prior Finding Status

| Prior ID | Title | Current Status |
|----------|-------|----------------|
| HIGH-01 (2023-02-23) | Validation claim expiry locks slots | **FIXED** — `cancelExpiredValidationClaim` now decrements `claimCount` and deletes commit |
| HIGH-02 (2023-02-23) | Late commit after claim expiry | **FIXED** — `commitValidation` now checks `vclaim.status` and `vclaim.deadline` |
| HIGH-03 (2023-02-23) | Upheld dispute deadlocks completion | **FIXED** — `upholdDispute` now decrements `pendingContributions` for accepted contributions |
| MEDIUM-01 (2023-02-23) | Cancelled project strands escrow | **FIXED** — `refundEscrow` now allows `ProjectStatus.Cancelled` |

---

## New Findings

---

### SEC-C-01: settleValidator Missing Challenge Period Enforcement [CRITICAL]

**Severity:** CRITICAL
**Likelihood:** HIGH
**Impact:** Dispute mechanism bypass; unrecoverable validator reward extraction
**Component:** FinalizationLib (`_settleValidatorFor`)

**Description:**
The interface documentation for `settleValidator` explicitly states "Must be called after the challenge period ends and no dispute is in progress." However, `_settleValidatorFor` enforces neither condition. A validator can settle in the same block as `computeConsensus`, extracting rewards before any dispute can be opened. If a dispute is subsequently upheld, the validator's rewards cannot be clawed back.

This contrasts with `releaseContributorReward`, which correctly enforces both the challenge period (`block.timestamp < contrib.challengeEndsAt`) and dispute status checks.

**Evidence:**

```solidity
// FinalizationLib.sol:55-72
function _settleValidatorFor(bytes32 projectId, uint256 index, uint256 nonce, address validator) internal {
    EngineStorage storage $ = _getStorage();
    ConsensusReport storage report = $.consensusReports[projectId][index][nonce];
    if (!report.computed) revert ISapienCore.ConsensusNotReady(0, 1);

    ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][validator];
    if (vc.settled) revert ISapienCore.AlreadySettled();
    if (vc.revealedAt == 0) revert ISapienCore.NotCommitted();
    vc.settled = true;
    // ^^^ No challenge period check, no dispute status check
    // Proceeds directly to reward distribution
```

**Exploit Scenario:**

1. Contribution reaches consensus (Accepted, `challengeEndsAt = block.timestamp + 1 day`)
2. In the same block, validator bot calls `settleValidator` — succeeds, rewards transferred to `pendingRewards`
3. During the challenge period, challenger opens a dispute with evidence of low-quality contribution
4. Operator upholds the dispute
5. Validator already extracted rewards from escrow; the escrow is reduced
6. Challenger's reward from `upholdDispute` may be short-changed because escrow was partially drained
7. Validator suffers no consequence — reputation was already updated positively at settlement

**Recommended Fix:**
Add the same guards used in `releaseContributorReward`:

```solidity
function _settleValidatorFor(bytes32 projectId, uint256 index, uint256 nonce, address validator) internal {
    EngineStorage storage $ = _getStorage();
    // ...existing checks...

    Contribution storage contrib = $.contributions[projectId][index];
    if (block.timestamp < contrib.challengeEndsAt) revert ISapienCore.ChallengeNotElapsed();

    Dispute storage dispute = $.disputes[projectId][index][nonce];
    if (dispute.status == DisputeStatus.Open) revert ISapienCore.DisputeInProgress();

    // ...rest of settlement logic...
}
```

---

### SEC-H-01: Escrow Insolvency via Upheld Disputes on Rejected Contributions [HIGH]

**Severity:** HIGH
**Likelihood:** MEDIUM
**Impact:** Permanent reward-release and settlement reverts for innocent participants
**Component:** DisputeLib (`upholdDispute`), FinalizationLib (`releaseContributorReward`, `_settleValidatorFor`), ValidationLib (`computeConsensus`)

**Description:**
When a contribution is rejected by consensus, the slot is recycled to the return stack and `availableSlots` is incremented. If a dispute is then upheld on that rejected contribution, up to the full `rewardRate` is paid from escrow as compensation to the contributor and challenger. When a new contributor claims the recycled slot and gets accepted, their reward release and validator settlements also deduct from escrow — but the `rewardRate` was calculated from the original `totalRewards / totalQuantity`, which doesn't account for escrow already drained by dispute compensation.

The reward release and validator settlement functions perform unchecked subtraction on `projectEscrow`, causing a revert (Solidity 0.8+ underflow) when escrow is insufficient. This permanently blocks the last participants from receiving their rewards.

**Evidence:**

```solidity
// DisputeLib.sol — upholdDispute pays compensation from escrow
} else if (contrib.status == ContributionStatus.Rejected) {
    uint256 maxPayout = contrib.rewardRate;
    uint256 challengerReward = (maxPayout * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;
    uint256 compensation = maxPayout - challengerReward;
    if (compensation > 0 && $.projectEscrow[projectId][rewardToken] >= compensation) {
        $.pendingRewards[contrib.contributor][rewardToken] += compensation;
        $.projectEscrow[projectId][rewardToken] -= compensation; // drains escrow
    }
    // ...challenger also paid from escrow
}

// FinalizationLib.sol — reward release does NOT check escrow sufficiency
$.projectEscrow[projectId][token] -= contributorShare; // reverts if escrow < contributorShare

// FinalizationLib.sol — validator settlement also unchecked
$.projectEscrow[projectId][proj.rewardToken] -= validatorShare; // same issue
```

**Numeric Example:**

- Project: `totalRewards = 100`, `totalQuantity = 10`, `rewardRate = 10`
- Slot 0: rejected by consensus, slot recycled
- Dispute upheld on slot 0: `10` paid from escrow (compensation + challenger share)
- Escrow now: `90`
- New contributor claims recycled slot 0, gets accepted: needs `10` from escrow
- Remaining 9 original slots accepted: need `90` from escrow
- Total needed: `100`, available: `90` — final settlements **revert**

**Recommended Fix:**
Either (a) adjust `rewardRate` accounting when escrow is drained by dispute compensation, (b) add escrow-sufficiency checks in `releaseContributorReward` and `_settleValidatorFor` with a fallback (partial payment or protocol-funded backstop), or (c) do not recycle rejected-and-disputed slots (treat the slot as fully consumed after dispute compensation).

---

### SEC-H-02: Claim Expiry Blocked When Rejected Contribution Indices Are Recycled [HIGH]

**Severity:** HIGH
**Likelihood:** MEDIUM
**Impact:** Permanent contributor stake locking; stranded Reserved slots
**Component:** ContributionLib (`expireClaim`), ValidationLib (`computeConsensus`)

**Description:**
When a contributor claims multiple slots (e.g., indices [A, B]) but only submits some (A), and A is subsequently rejected by consensus and recycled to a new contributor, the original claim can never be expired. `expireClaim` requires passing exactly `totalCount` indices, all of which must have `contrib.claimId == claimId`. But the recycled index A now belongs to a new claim (its `claimId` was overwritten in `claimToContribute`), causing the `IndexNotInClaim` revert.

The unsubmitted slot (B) remains permanently in `Reserved` status with the original contributor's locked stake, irrecoverable.

**Evidence:**

```solidity
// ContributionLib.sol:186 — enforces exact count
uint256 len = indices.length;
if (len != claim.totalCount) revert ISapienCore.InvalidIndex();

// ContributionLib.sol:193 — checks claimId ownership
if (contrib.claimId != claimId) revert ISapienCore.IndexNotInClaim();
// ^^^ Fails for index A after it was recycled to a new claim
```

**Scenario:**

1. Contributor claims slots [A, B] (totalCount = 2, submittedCount = 0)
2. Submits A → Pending (submittedCount = 1)
3. A is validated, rejected by consensus → slot A recycled
4. New contributor claims slot A → `contrib.claimId` for A is now a new claim
5. Old claim deadline expires
6. Anyone calls `expireClaim(oldClaimId, [A, B])` → reverts at A (`IndexNotInClaim`)
7. Slot B stays Reserved forever, contributor's stake for B locked permanently

**Recommended Fix:**
Modify `expireClaim` to accept a variable-length index array (not requiring exactly `totalCount`) and only process indices that still belong to the given `claimId`. Skip indices whose `claimId` was reassigned. Alternatively, track which indices were consumed by consensus rejection and exclude them from the expiry requirement.

---

### SEC-H-03: Immediate Escrow Drain After Project Cancellation [HIGH]

**Severity:** HIGH
**Likelihood:** MEDIUM
**Impact:** Stranded validator stakes and blocked settlements
**Component:** FinalizationLib (`refundEscrow`)

**Description:**
The fix for the cancelled-project escrow stranding issue (MEDIUM-01 from the 2023-02-23 report) allows `refundEscrow` to proceed for `ProjectStatus.Cancelled` without any delay. For `Completed` projects, a 30-day delay (`PROJECT_COMPLETION_DELAY`) is enforced. This asymmetry creates a race condition: when a project is cancelled while contributions are in-flight (pending validations, consensus, or settlements), the originator can immediately call `refundEscrow` and drain all escrow, leaving in-flight participants unable to settle or claim rewards.

**Evidence:**

```solidity
// FinalizationLib.sol:237-243
if (proj.status == ProjectStatus.Completed) {
    if (block.timestamp < proj.completedAt + C.PROJECT_COMPLETION_DELAY) {
        revert ISapienCore.ChallengeNotElapsed();
    }
} else if (proj.status != ProjectStatus.Cancelled) {
    revert ISapienCore.ProjectNotCompleted();
}
// ^^^ Cancelled status falls through with NO delay
```

**Scenario:**

1. Project is active with pending contributions and committed validators
2. Originator report is upheld (or operator calls `removeProject`) → `ProjectStatus.Cancelled`
3. Originator immediately calls `refundEscrow` → all escrow transferred out
4. Validators try to settle → `_settleValidatorFor` decrements `projectEscrow` → **underflow revert**
5. Contributors cannot release rewards either
6. Validator in-flight stakes remain locked with no recovery path

**Recommended Fix:**
Apply a delay to cancelled-project refunds similar to the completion delay, or implement a settlement grace period during which in-flight participants can settle before escrow is refunded. For operator-removed projects (TOS violation), consider routing escrow to treasury instead.

---

### SEC-M-01: removeProject on Active Projects Strands Participant Stakes [MEDIUM]

**Severity:** MEDIUM
**Likelihood:** LOW
**Impact:** Permanent stake locking for contributors and validators
**Component:** OriginationLib (`removeProject`), SapienCore

**Description:**
The `removeProject` function (OPERATOR_ROLE only) sets any non-cancelled project to `Cancelled` without handling in-flight contributions, validations, or validator commitments. Contributors with locked stakes for claimed slots have no mechanism to unlock their contributor locks on cancelled projects. Validators with committed (in-flight) stakes can only recover through `cancelExpiredCommitment`, which **slashes** their full stake — unfairly penalizing validators who acted correctly.

**Evidence:**

```solidity
// OriginationLib.sol:129-149 — no in-flight cleanup
function removeProject(bytes32 projectId) public {
    // ...
    proj.status = ProjectStatus.Cancelled;
    // ^^^ No handling of:
    //   - $.pendingContributions[projectId]
    //   - contributor locks for active claims
    //   - validator in-flight stakes
    //   - active disputes
}
```

**Recommended Fix:**
Add a winding-down mechanism for cancelled projects that unlocks contributor stakes, releases (rather than slashes) validator in-flight stakes, and resolves any open disputes.

---

### SEC-M-02: No Minimum Bounds on Admin-Configurable Deadlines [MEDIUM]

**Severity:** MEDIUM
**Likelihood:** LOW
**Impact:** Protocol rendered unusable or safety windows bypassed
**Component:** SapienCore (admin setters)

**Description:**
All admin-configurable deadline setters enforce maximum bounds but no minimum bounds. An admin (or compromised admin key) can set any deadline to 0:

- `setClaimDeadline(0)` — contributors must submit in the same block they claim
- `setChallengePeriod(0)` — disables the dispute window entirely
- `setCommitDeadline(0)` — validators must commit in same block
- `setRevealDeadline(0)` — validators must reveal in same block
- `setForceSettleDelay(0)` — force-settle available immediately

Setting `challengePeriod = 0` is particularly dangerous as it completely disables the dispute mechanism.

**Evidence:**

```solidity
// SapienCore.sol:466-469 — only max check, no min
function setChallengePeriod(uint256 period) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (period > C.MAX_CHALLENGE_PERIOD) revert DeadlineTooLong(period, C.MAX_CHALLENGE_PERIOD);
    _getStorage().challengePeriod = period;
    // ^^^ No minimum check — period = 0 effectively disables disputes
}
```

**Recommended Fix:**
Add minimum constants in `Constants.sol` and enforce them in setters. Suggested minimums: `challengePeriod >= 1 hours`, `forceSettleDelay >= 1 days`, `claimDeadline >= 1 hours`, `commitDeadline >= 1 hours`, `revealDeadline >= 1 hours`.

---

### SEC-M-03: No Project Status Validation in Settlement and Reward Flows [MEDIUM]

**Severity:** MEDIUM
**Likelihood:** MEDIUM
**Impact:** Wasted gas, confusing state transitions on dead projects
**Component:** FinalizationLib, ValidationLib

**Description:**
The settlement (`settleValidator`, `forceSettleValidator`), reward release (`releaseContributorReward`), and consensus computation (`computeConsensus`) functions do not verify the project status. After a project is cancelled, these operations can still proceed (until escrow is drained by `refundEscrow`). This creates a race condition where participants race to settle before the originator drains escrow, and leads to confusing state where reputation is updated and events are emitted for cancelled projects.

**Evidence:**

```solidity
// FinalizationLib.sol:55-123 — _settleValidatorFor
// No check: proj.status != ProjectStatus.Cancelled

// FinalizationLib.sol:126-161 — releaseContributorReward
// No check: proj.status != ProjectStatus.Cancelled

// ValidationLib.sol:269-340 — computeConsensus
// No check: proj.status != ProjectStatus.Cancelled
```

**Recommended Fix:**
Add project status checks at the entry of settlement, reward release, and consensus computation functions to revert on cancelled projects.

---

### SEC-L-01: Duplicate ProjectCancelled Event in escalateOriginatorReport [LOW]

**Severity:** LOW
**Likelihood:** HIGH (triggered on every escalation)
**Impact:** Off-chain indexer confusion, double-counted events
**Component:** SapienCore (`escalateOriginatorReport`), DisputeLib (`upholdOriginatorReport`)

**Description:**
`escalateOriginatorReport` calls `upholdOriginatorReport`, which emits `ProjectCancelled`. Then `escalateOriginatorReport` emits `ProjectCancelled` again. The event is fired twice for the same cancellation.

**Evidence:**

```solidity
// SapienCore.sol:359-372
function escalateOriginatorReport(bytes32 projectId) external ... {
    // ...
    DisputeLib.upholdOriginatorReport(projectId, false);
    // ^^^ upholdOriginatorReport emits ProjectCancelled internally

    emit OriginatorReportEscalated(projectId);
    emit ProjectCancelled(projectId); // ← duplicate emission
}

// DisputeLib.sol:207-208
proj.status = ProjectStatus.Cancelled;
emit ISapienCore.ProjectCancelled(projectId); // ← first emission
```

**Recommended Fix:**
Remove the duplicate `emit ProjectCancelled(projectId)` from `escalateOriginatorReport` in `SapienCore.sol`.

---

### SEC-L-02: Reputation oldScore Does Not Reflect Actual Pre-Update Value [LOW]

**Severity:** LOW
**Likelihood:** HIGH (triggered on every reputation update with decay)
**Impact:** Inaccurate ReputationUpdated event data
**Component:** ReputationLib (`update`)

**Description:**
In `ReputationLib.update`, `oldScore` is captured from `rep.score` before decay is applied. After decay + success/failure adjustment, the event compares the new score against the pre-decay value. If decay and a success bonus cancel out (e.g., decay = 10, success increase = 10), no event is emitted even though the internal state was updated (decay applied, `lastUpdated` changed, action counters incremented). Off-chain systems tracking reputation via events would miss intermediate state changes.

**Evidence:**

```solidity
// ReputationLib.sol:53-54
uint256 currentScore = rep.score;
uint256 oldScore = currentScore; // ← captures pre-decay score

// ReputationLib.sol:56-63
// Applies decay to currentScore...

// ReputationLib.sol:94-96
if (currentScore != oldScore) { // ← compares against pre-decay
    emit ISapienCore.ReputationUpdated(user, role, oldScore, currentScore);
}
```

**Recommended Fix:**
Capture `oldScore` after applying decay so the emitted event accurately reflects the actual score change from the update action.

---

### SEC-L-03: cancelExpiredCommitment Decrements claimCount Without Consistency Check [LOW]

**Severity:** LOW
**Likelihood:** LOW
**Impact:** Counter underflow revert in edge cases
**Component:** FinalizationLib (`cancelExpiredCommitment`)

**Description:**
`cancelExpiredCommitment` decrements `validationCounters.claimCount` unconditionally. While Solidity 0.8+ prevents underflow (it would revert), the function doesn't verify that the validator being cancelled was actually counted in `claimCount`. If `claimCount` was already decremented by `cancelExpiredValidationClaim` due to a race condition or if the counter was corrupted, this operation would revert unexpectedly, blocking the keeper path.

**Evidence:**

```solidity
// FinalizationLib.sol:204
$.validationCounters[projectId][index][nonce].claimCount--;
// ^^^ No check that claimCount > 0 or that this validator was counted
```

**Recommended Fix:**
Add a safety check: `if (counters.claimCount > 0) counters.claimCount--;` or verify the validator was counted before decrementing.

---

### SEC-I-01: UUPS Upgrade Without Timelock [INFO]

**Severity:** INFO
**Likelihood:** N/A
**Impact:** Centralization risk, instant malicious upgrade
**Component:** SapienCore (`_authorizeUpgrade`), SapienVault (`_authorizeUpgrade`)

**Description:**
Both `SapienCore` and `SapienVault` use `onlyRole(DEFAULT_ADMIN_ROLE)` for upgrade authorization with no timelock, multi-sig requirement, or governance delay. A compromised admin key can deploy a malicious implementation and upgrade both contracts instantly, extracting all escrowed funds and staked tokens.

This was noted in the 2026-02-23 report and remains unaddressed.

**Recommended Fix:**
Implement a timelock contract (e.g., OpenZeppelin `TimelockController`) as the admin, or add an upgrade delay pattern within `_authorizeUpgrade`.

---

### SEC-I-02: Combined Fee Configuration Can Extract >20% of Deposits [INFO]

**Severity:** INFO
**Likelihood:** LOW (requires admin action)
**Impact:** Excessive fee extraction
**Component:** SapienCore (fee configuration)

**Description:**
At maximum settings, fees applied during project funding are:
- Protocol fee: 10% of deposit → treasury
- Origination fee: 5% of post-protocol-fee amount → adapter

Combined: `1 - (0.90 × 0.95) = 14.5%` deducted before escrow.

Then during settlement:
- Contribution adapter fee: 5% of contributor share
- Validation adapter fee: 5% of validator share

Effective total extraction from the original deposit can exceed 19%.

While each fee has an individual cap, the absence of a combined cap means the admin can configure all fees to maximum simultaneously, creating a high rent-extraction scenario.

**Recommended Fix:**
Consider a combined fee cap or document the maximum aggregate fee extraction clearly for originators.

---

## Cross-Cutting Observations

### State Machine Gaps

The protocol's lifecycle state machine has several implicit transitions that are undocumented and untested:

1. **Accepted + Dispute Upheld → ???**: The contribution remains in `Accepted` status with `rewardReleased = false`. No explicit terminal state exists. The slot is not recycled, the escrow is partially drained, and the contribution is effectively abandoned.

2. **Cancelled project with in-flight work**: No defined wind-down procedure. Active claims, pending validations, and committed stakes have no clean resolution path.

3. **Rejected + Dispute Upheld + Slot Recycled + New Contribution**: The old and new contributions share the same index at different nonces, but escrow accounting doesn't track per-nonce budgets.

### Escrow Accounting Model

The current accounting model assumes `projectEscrow[projectId][token]` is a sufficient balance to cover all outstanding obligations. However, obligations can exceed the balance when disputes pay compensation from escrow for recycled slots. A per-slot budget tracking model or a "max dispersable" counter would prevent insolvency.

### Validator Incentive Asymmetry

Validators have a strong incentive to settle as early as possible (SEC-C-01) because there is no penalty for early settlement and rewards are locked in. This creates an implicit MEV opportunity where validator bots race to settle in the same block as `computeConsensus`, systematically bypassing the dispute protection window.

---

## Testing Recommendations

### Invariant Properties to Enforce

```
INV-1: projectEscrow[pid][token] >= Σ(unsettled validator shares) + Σ(unreleased contributor shares)
INV-2: ∀ settleValidator calls: block.timestamp >= contrib.challengeEndsAt
INV-3: ∀ cancelled projects: no new claims, validations, or consensus computations
INV-4: ∀ claims: expireClaim succeeds when deadline passes, regardless of recycled indices
INV-5: ∀ refundEscrow calls on cancelled projects: delay >= minimum settlement window
```

### Suggested PoC Tests

1. `test_settleValidatorDuringChallengePeriod` — settle immediately after consensus, then uphold dispute
2. `test_escrowInsolvencyViaDisputeRejectionRecycle` — rejected contribution dispute upheld, slot recycled, new contribution accepted, last reward release reverts
3. `test_claimExpiryBlockedByRejectedRecycle` — partial submission, one index rejected and recycled, expiry reverts
4. `test_cancelledProjectImmediateEscrowDrain` — cancel project with active validators, originator drains escrow, validators can't settle

---

## Fix Priority

### Pre-Launch Blockers

1. **SEC-C-01** — Add challenge period + dispute checks to `_settleValidatorFor`
2. **SEC-H-01** — Implement escrow budget tracking or prevent slot recycling after dispute compensation
3. **SEC-H-02** — Fix `expireClaim` to handle recycled indices
4. **SEC-H-03** — Add settlement delay for cancelled-project refunds

### Short Term

5. **SEC-M-01** — Implement wind-down logic for `removeProject` with active pipeline
6. **SEC-M-02** — Add minimum bounds to configurable deadlines
7. **SEC-M-03** — Add project status checks in settlement/finalization flows

### Maintenance

8. **SEC-L-01** — Remove duplicate event emission
9. **SEC-L-02** — Fix reputation event accuracy
10. **SEC-L-03** — Add counter safety check

---

*Generated by manual code review against `docs/pipeline/pipeline.md` methodology.*
*All findings are OPEN pending verification and fix implementation.*
