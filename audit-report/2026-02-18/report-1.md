# Sapien PoQ v0.5 — Security & Usability Audit Report

## Audit Information

| Field | Value |
|-------|-------|
| **Protocol** | Sapien PoQ (Proof-of-Quality) v0.5 |
| **Audit Date** | February 18, 2026 |
| **Scope** | All contracts in `src/` — QualityEngine, StakeVault, ConsensusLib, and libraries (ContributionLib, ValidationLib, FinalizationLib, DisputeLib, OriginationLib, ReputationLib), interfaces, Types.sol, Constants.sol |
| **Methodology** | Manual review guided by `docs-b/skills/` pipeline: security-review, adversarial-testing, security-pattern-review, trust-surface-review, invariant-review, asymmetry-review, edge-case-review |
| **Commit** | `HEAD` (v0.5 branch) |
| **Companion Report** | `REPORT.md` (follow-up from Feb 16 audit, same directory) |

---

## Executive Summary

This report captures **new** security and usability findings discovered through a full-protocol review of the v0.5 codebase using the skills pipeline. These findings are **in addition to** the issues tracked in the companion `REPORT.md`.

### Results

| Severity | Count |
|----------|-------|
| **CRITICAL** | 2 |
| **HIGH** | 4 |
| **MEDIUM** | 7 |
| **LOW** | 4 |
| **USABILITY** | 5 |
| **Total** | 22 |

**Release Blockers**: SEC-C-01 (index poisoning), SEC-C-02 (ReentrancyGuard), SEC-H-01 (escrow drain via project completion), SEC-H-03 (dispute grief loop)

---

## Critical Findings

### SEC-C-01: Dispute state persists across nonces — poisons recycled indices

**Location**: `DisputeLib.sol`, `FinalizationLib.sol`, `ContributionLib.sol`

**Description**

`$.disputes[projectId][index]` is keyed by `(projectId, index)` **without** the submission nonce. When a contribution is rejected, the nonce increments and the index returns to the available pool. However, any dispute opened against the rejected contribution persists at the same `(projectId, index)` key. A new contribution at that index inherits the stale dispute state.

`releaseContributorReward` blocks on both `Open` and `Upheld` dispute status:

```solidity
// FinalizationLib.sol:105-107
Dispute storage dispute = $.disputes[projectId][index];
if (dispute.status == DisputeStatus.Open) revert IQualityEngine.DisputeInProgress();
if (dispute.status == DisputeStatus.Upheld) revert IQualityEngine.DisputeInProgress();
```

The same `$.contributions[projectId][index]` mapping is also overwritten by the new contribution, meaning `upholdDispute` operates on the wrong contribution data when resolved.

**Proof of Concept**

1. Contributor A submits at index 5 → validators reject → `submissionNonce++`, index returned to pool
2. During the 1-day challenge period, anyone opens a dispute on the rejection (`contrib.status == Rejected` passes the guard)
3. Index 5 is reclaimed by Contributor B, who submits new work
4. The dispute is upheld (or escalated after 7 days) → `dispute.status = DisputeStatus.Upheld`
5. Contributor B's work passes consensus, challenge period elapses
6. `releaseContributorReward(projectId, 5)` **permanently reverts** — `dispute.status == Upheld`
7. Contributor B can never claim their reward for index 5

**Impact**

- **Permanent reward lockout** for innocent contributors at recycled indices
- **Weaponizable**: An attacker can intentionally submit bad work, get rejected, dispute the rejection, and poison the index for all future contributors
- Cost to attacker: one dispute bond (default 10% of rewardRate, minimum 1 wei)

**Recommendation**

Option A — Key disputes by nonce:
```solidity
// In EngineStorage:
mapping(bytes32 => mapping(uint256 => mapping(uint256 => Dispute))) disputes;
// keyed: projectId => index => nonce => Dispute
```

Option B — Clear dispute state on nonce increment:
```solidity
// In computeConsensus rejection branch, before incrementing nonce:
delete $.disputes[projectId][index];
$.submissionNonce[projectId][index]++;
```

Option C (minimal) — Check nonce match in `releaseContributorReward`:
```solidity
uint256 currentNonce = contrib.consensusNonce;
Dispute storage dispute = $.disputes[projectId][index];
// Only respect dispute if it was opened during the current nonce's lifecycle
if (dispute.openedAt > 0 && dispute.openedAt >= contrib.submittedAt) {
    if (dispute.status == DisputeStatus.Open) revert IQualityEngine.DisputeInProgress();
    if (dispute.status == DisputeStatus.Upheld) revert IQualityEngine.DisputeInProgress();
}
```

---

### SEC-C-02: Non-upgradeable ReentrancyGuard in UUPS proxy contract

**Location**: `QualityEngine.sol:6`, `:42`

**Description**

QualityEngine imports the non-upgradeable `ReentrancyGuard` from `@openzeppelin/contracts/utils/ReentrancyGuard.sol` instead of `ReentrancyGuardUpgradeable` from the upgradeable package.

```solidity
// QualityEngine.sol:6
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
```

The non-upgradeable version stores `_status` in a plain storage variable at a compiler-assigned slot position. In an upgradeable proxy context:

1. The constructor sets `_status = NOT_ENTERED (1)` on the **implementation contract**, not the proxy
2. The proxy's `_status` starts as `0` (uninitialized)
3. This currently works by coincidence: `0 != ENTERED (2)`, so the modifier allows entry
4. After the first guarded call, `_status` is set to `1` (NOT_ENTERED) on the proxy, normalizing behavior

The danger is **future upgrades**:
- All other base contracts (AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable) use ERC-7201 namespaced storage at computed high slots
- `ReentrancyGuard._status` sits at a low slot determined by Solidity's storage layout rules
- Any change to inheritance order or addition of base contracts with plain storage variables in a future upgrade could shift `_status` to a different slot, silently breaking reentrancy protection

**Impact**

- **Current**: Functional by coincidence; no immediate exploit
- **Future**: Any inheritance change in an upgrade silently disables reentrancy guards on all value-flow functions (`fundProject`, `claimToContribute`, `commitValidation`, `revealValidation`, `computeConsensus`, `settleValidator`, `releaseContributorReward`, `claimReward`, all dispute functions)
- **Severity**: Critical because failure is silent and affects all protected entry points

**Recommendation**

Replace with the upgradeable variant:

```solidity
import {ReentrancyGuardUpgradeable} from
    "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
```

Update the initializer:
```solidity
function initialize(...) external initializer {
    __AccessControl_init();
    __Pausable_init();
    __ReentrancyGuard_init(); // Add this
    // ...
}
```

This uses ERC-7201 namespaced storage, immune to slot-shift issues across upgrades.

---

## High Findings

### SEC-H-01: Premature project completion allows originator to drain escrow

**Location**: `FinalizationLib.sol:completeProject()`, `refundEscrow()`

**Description**

`completeProject` requires only that the caller is the originator and the project is `Active` or `Funded`. There is no check that all contribution indices have been finalized (validated, settled, and rewards released).

```solidity
// FinalizationLib.sol:182-200
function completeProject(bytes32 projectId) public {
    // ...
    if (proj.originator != msg.sender) revert IQualityEngine.NotProjectOriginator();
    if (proj.status != ProjectStatus.Active && proj.status != ProjectStatus.Funded) {
        revert IQualityEngine.ProjectNotActive();
    }
    proj.status = ProjectStatus.Completed;
    proj.completedAt = uint64(block.timestamp);
    // ... unlocks originator stake, no other checks
}
```

After 30 days (`PROJECT_COMPLETION_DELAY`), the originator calls `refundEscrow` to withdraw the entire remaining project escrow:

```solidity
// FinalizationLib.sol:203-220
function refundEscrow(bytes32 projectId) public {
    // ...
    uint256 remaining = $.projectEscrow[projectId][token];
    if (remaining == 0) revert IQualityEngine.ZeroAmount();
    $.projectEscrow[projectId][token] = 0;
    IERC20(token).safeTransfer(proj.originator, remaining);
}
```

**Exploit Scenario**

1. Originator funds project with 10,000 tokens, 10 contribution slots
2. Contributors submit and validators evaluate — 8 accepted, 2 pending
3. Originator calls `completeProject()` — project marked Completed
4. 30 days pass. No one notices (or validators haven't settled yet)
5. Originator calls `refundEscrow()` — withdraws all remaining escrow
6. `settleValidator` for any unsettled validator reverts: `$.projectEscrow -= reward` underflows
7. Validators' in-flight stake is permanently locked (only `settleValidator` releases it, which now reverts)

**Impact**

- Originator can rug validators by completing early and refunding after grace period
- Validators lose earned rewards and have permanently locked in-flight stake
- 30-day window is protection but insufficient if validators delay settlement

**Recommendation**

Option A — Track finalized indices:
```solidity
if (proj.availableSlots + proj.finalizedCount < proj.totalQuantity) {
    revert IQualityEngine.ProjectHasActivePipeline();
}
```

Option B — Prevent refund while pending rewards exist:
```solidity
// In refundEscrow, calculate minimum escrow needed for pending rewards
// and only allow withdrawal of the excess
```

---

### SEC-H-02: No force-settle mechanism — validator in-flight stake permanently lockable

**Location**: `FinalizationLib.sol:settleValidator()`

**Description**

`settleValidator` uses `msg.sender` to look up the validator's commit, meaning only the validator themselves can settle:

```solidity
// FinalizationLib.sol:46
ValidatorCommit storage vc = $.validatorCommits[projectId][index][nonce][msg.sender];
```

There is no keeper function to force-settle a validator after a timeout. Unlike `cancelExpiredCommitment` (which handles ghost commits), there is no equivalent for revealed-but-unsettled validators.

**Impact**

- **Outlier avoidance**: An outlier validator can avoid the slash burn by never calling `settleValidator`. Their in-flight stake stays locked (they lose access) but is not burned — the protocol loses the disincentive mechanism.
- **Key loss**: An honest validator who loses their key has permanently frozen funds with no recovery path.
- **Protocol leakage**: Unslashed outlier stakes represent a systemic leak in the security model.

**Recommendation**

Add a permissionless force-settle function:

```solidity
function forceSettleValidator(
    bytes32 projectId, uint256 index, uint256 nonce, address validator
) external whenNotPaused nonReentrant {
    // Enforce timeout (e.g., 30 days post-consensus)
    ConsensusReport storage report = $.consensusReports[projectId][index][nonce];
    if (!report.computed) revert;
    // ... require sufficient time has passed ...

    // Execute same settlement logic as settleValidator, but for `validator` instead of msg.sender
}
```

---

### SEC-H-03: Repeated dispute griefing via challenge window reset

**Location**: `DisputeLib.sol:openDispute()`, `rejectDispute()`

**Description**

When a dispute is rejected, `rejectDispute` sets the challenge end to `block.timestamp`:

```solidity
// DisputeLib.sol:118-119
if (contrib.status == ContributionStatus.Accepted) {
    contrib.challengeEndsAt = uint64(block.timestamp);
}
```

And sets `dispute.status = DisputeStatus.Rejected`. Since `openDispute` only blocks on `DisputeStatus.Open`:

```solidity
// DisputeLib.sol:49
if (dispute.status == DisputeStatus.Open) revert IQualityEngine.DisputeAlreadyOpen();
```

A new dispute can be opened immediately (same block, since `block.timestamp > challengeEndsAt` is false when equal). The new dispute extends `challengeEndsAt` by another `DISPUTE_RESOLUTION_DEADLINE` (7 days):

```solidity
// DisputeLib.sol:65-67
if (contrib.status == ContributionStatus.Accepted) {
    contrib.challengeEndsAt = uint64(block.timestamp + C.DISPUTE_RESOLUTION_DEADLINE);
}
```

**Exploit Scenario**

1. Contribution accepted, 1-day challenge period starts
2. Attacker opens dispute, posts bond (10% of rewardRate)
3. Operator rejects dispute → attacker's bond slashed, `challengeEndsAt = now`
4. Same block: different attacker address opens new dispute → extends challenge by 7 days
5. Repeat indefinitely

Each iteration costs the attacker `rewardRate * disputeBondBps / BPS` (slashed bond). At default 10% bond, an attacker pays 10% of the reward per 7-day delay. For a 100-token reward, 10 tokens delays payout by 7 days, indefinitely.

**Impact**

- Contributor rewards can be delayed indefinitely at moderate cost
- Creates uncertainty for contributors, discouraging participation
- Bond slashing provides some cost but may be insufficient for high-value contributions

**Recommendation**

Option A — Limit to one dispute per (projectId, index, nonce):
```solidity
mapping(bytes32 => mapping(uint256 => mapping(uint256 => Dispute))) disputes;
```

Option B — After a rejected dispute, do not allow reopening:
```solidity
if (dispute.status == DisputeStatus.Rejected) revert IQualityEngine.DisputeAlreadyClosed();
```

Option C — Escalating bond: each subsequent dispute on the same contribution requires 2x the previous bond.

---

### SEC-H-04: Overturned rejection payouts exceed per-index escrow budget

**Location**: `DisputeLib.sol:upholdDispute()`, rejected contribution branch

**Description**

When a rejected contribution's dispute is upheld, the contributor receives the **full** `rewardRate` as compensation (not just the contributor share), and the challenger receives an additional 20%:

```solidity
// DisputeLib.sol:91-104
} else if (contrib.status == ContributionStatus.Rejected) {
    uint256 compensation = contrib.rewardRate;  // Full per-index rate
    if (compensation > 0 && $.projectEscrow[projectId][rewardToken] >= compensation) {
        $.pendingRewards[contrib.contributor][rewardToken] += compensation;
        $.projectEscrow[projectId][rewardToken] -= compensation;
        // ...
    }
    uint256 challengerReward = (contrib.rewardRate * C.DISPUTE_CHALLENGER_REWARD_BPS) / C.BPS;
    if (challengerReward > 0 && $.projectEscrow[projectId][rewardToken] >= challengerReward) {
        $.pendingRewards[dispute.challenger][rewardToken] += challengerReward;
        $.projectEscrow[projectId][rewardToken] -= challengerReward;
    }
}
```

Total deduction per overturned rejection: `rewardRate + (rewardRate * 2000 / 10000) = 1.2 * rewardRate`.

But the per-index escrow budget is `rewardRate = totalRewards / totalQuantity`. Each overturned rejection consumes 120% of its budget, drawing from other indices' allocation.

**Impact**

- Multiple overturned rejections can deplete escrow below what's needed for other indices
- `settleValidator` for other indices reverts on `projectEscrow -= reward` underflow
- `releaseContributorReward` for other indices similarly blocked

**Scenario**: Project with 10 slots, 10000 tokens total. If 3 rejections are overturned: `3 * 1200 = 3600` deducted. Remaining: 6400 for 7 accepted indices (budget: 7000). Last validators to settle may get reverts.

**Recommendation**

Cap overturned-rejection payouts to the per-index budget:
```solidity
uint256 maxPayout = contrib.rewardRate;
uint256 compensation = (maxPayout * (C.BPS - C.DISPUTE_CHALLENGER_REWARD_BPS)) / C.BPS;
uint256 challengerReward = maxPayout - compensation;
```

Or fund challenger rewards from a separate dispute pool, not from project escrow.

---

## Medium Findings

### SEC-M-01: StakeVault ERC4626 functions not pausable

**Location**: `StakeVault.sol`

**Description**

StakeVault inherits `PausableUpgradeable` but the ERC4626 `deposit`, `withdraw`, `redeem`, and `mint` functions inherited from `ERC4626Upgradeable` have no pause guard. The `whenNotPaused` modifier is only present on ENGINE_ROLE stake operations (called via QualityEngine).

During an emergency, users can front-run a pause by withdrawing all unlocked stake before the pause transaction is mined.

**Recommendation**

Override `maxDeposit` and `maxMint` to return 0 when paused:
```solidity
function maxDeposit(address) public view override returns (uint256) {
    return paused() ? 0 : type(uint256).max;
}
function maxMint(address) public view override returns (uint256) {
    return paused() ? 0 : type(uint256).max;
}
```

---

### SEC-M-02: Missing events for critical admin setters

**Location**: `QualityEngine.sol:380-388`

**Description**

`setConsensusAlgorithm` and `setTreasury` modify critical protocol parameters without emitting events:

```solidity
// QualityEngine.sol:380-383
function setConsensusAlgorithm(address algorithm) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (algorithm == address(0)) revert ZeroAddress();
    _getStorage().consensusAlgorithm = algorithm;
    // No event emitted
}

// QualityEngine.sol:385-388
function setTreasury(address treasury_) external onlyRole(DEFAULT_ADMIN_ROLE) {
    if (treasury_ == address(0)) revert ZeroAddress();
    _getStorage().treasury = treasury_;
    // No event emitted
}
```

**Impact**

- A compromised admin could silently redirect the treasury or swap the consensus algorithm
- Off-chain monitoring tools have no way to detect these changes
- Inconsistent with other admin setters that all emit events

**Recommendation**

Add events:
```solidity
event ConsensusAlgorithmUpdated(address indexed newAlgorithm);
event TreasuryUpdated(address indexed newTreasury);
```

---

### SEC-M-03: Contributions accepted to cancelled projects

**Location**: `ContributionLib.sol:contribute()`

**Description**

`contribute` validates the claim (claimant match, active status, deadline) but does **not** check the project's status. If a project is cancelled via `upholdOriginatorReport`, contributors with existing active claims can still submit work:

```solidity
// ContributionLib.sol:129-167
function contribute(uint256 claimId, uint256 index, bytes32 submissionHash) public {
    // Checks: claimant == msg.sender, claim.status == Active, deadline not passed
    // Does NOT check: project.status
    // ...
}
```

Submitted contributions to cancelled projects can never be validated, leaving the contributor's stake locked.

**Recommendation**

Add project status check:
```solidity
Project storage proj = $.projects[claim.projectId];
if (proj.status == ProjectStatus.Cancelled || proj.status == ProjectStatus.Completed) {
    revert IQualityEngine.ProjectNotActive();
}
```

---

### SEC-M-04: No reveal deadline enforcement

**Location**: `ValidationLib.sol:revealValidation()`

**Description**

`revealValidation` does not check that the reveal occurs within the expected window (`commitTimestamp + REVEAL_DEADLINE`). A validator can delay their reveal indefinitely. The only recourse is `cancelExpiredCommitment`, but there is a race condition: if the validator front-runs the cancel with a reveal, the cancel fails (`vc.revealedAt != 0`).

This enables strategic timing: a validator can observe other validators' reveals and only reveal if their score is close to the emerging consensus.

**Recommendation**

```solidity
if (block.timestamp > vc.commitTimestamp + C.COMMIT_DEADLINE + C.REVEAL_DEADLINE) {
    revert IQualityEngine.RevealWindowClosed();
}
```

---

### SEC-M-05: Error name reuse across unrelated contexts

**Location**: `QualityEngine.sol` admin functions, `FinalizationLib.sol`

**Description**

Several error types are reused for unrelated validation failures:

| Error | Used For |
|-------|----------|
| `AdapterFeeTooHigh` | Protocol fee, origination fee, contribution fee, validation fee, decay rate, originator report bond |
| `ClaimDeadlineNotPassed` | Claim expiry AND commitment cancellation |
| `ChallengeNotElapsed` | Challenge period AND refund delay |

**Impact**

- Users and monitoring systems cannot distinguish failure reasons from error selectors
- Debugging requires tracing the exact call path to determine which parameter failed

**Recommendation**

Use specific errors per context.

---

### SEC-M-06: `verifyStorageLocation` uses incorrect hash length

**Location**: `StakeVault.sol:56-68`

**Description**

The verification function passes the wrong byte length to `keccak256`:

```solidity
// StakeVault.sol:59
let namespaceHash := keccak256("sapien.storage.StakeVault", 30)
```

The string `"sapien.storage.StakeVault"` is 25 bytes, but the length parameter is 30. This hashes the 25-byte string plus 5 bytes of adjacent memory garbage. The function will produce an incorrect hash and either always return `false` or match the hardcoded constant only by coincidence.

The actual storage slot derivation (the hardcoded `0x0745d8...` constant) is presumably computed correctly off-chain. This bug only affects the view-only verification function, not runtime behavior.

**Recommendation**

Fix the length:
```solidity
let namespaceHash := keccak256("sapien.storage.StakeVault", 25)
```

Or compute in high-level Solidity: `bytes32 namespaceHash = keccak256("sapien.storage.StakeVault");`

---

### SEC-M-07: No admin setters for `minClaimAmount` and `claimCooldown`

**Location**: `QualityEngine.sol` (admin functions), `Types.sol:79-81`

**Description**

`EngineStorage` declares `minClaimAmount` (uint64) and `claimCooldown` (uint64), and `FinalizationLib.claimReward()` enforces them. However, there are no admin setter functions anywhere in QualityEngine to configure these values after initialization. They default to 0 (disabled) and cannot be changed without a full contract upgrade.

**Recommendation**

Add admin setters with appropriate bounds:
```solidity
function setMinClaimAmount(uint64 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _getStorage().minClaimAmount = amount;
}

function setClaimCooldown(uint64 cooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
    _getStorage().claimCooldown = cooldown;
}
```

---

## Low Findings

### SEC-L-01: `createProject` silently ignores `config.originator`

**Location**: `OriginationLib.sol:createProject()`

The `Project calldata config` struct includes an `originator` field, but the function unconditionally sets `proj.originator = msg.sender`, silently discarding whatever value the caller provided in `config.originator`. Users may expect `config.originator` to be respected.

**Recommendation**: Document this behavior in NatSpec, or validate that `config.originator == address(0) || config.originator == msg.sender`.

---

### SEC-L-02: Redundant zero-check after zero-revert

**Location**: `ValidationLib.sol:88-99`

```solidity
if (stakeAmount == 0) revert IQualityEngine.InsufficientStake(1, 0);
// ... minimum stake checks ...
if (stakeAmount > 0) {   // Dead code — stakeAmount is guaranteed > 0 here
    $.vault.commitStake(msg.sender, stakeAmount);
}
```

The `if (stakeAmount > 0)` guard is unreachable dead code since `stakeAmount == 0` already reverts above.

**Recommendation**: Remove the redundant guard.

---

### SEC-L-03: No validation on dispute/report `evidenceHash`

**Location**: `DisputeLib.sol:openDispute()`, `reportOriginator()`

Both functions accept `bytes32 evidenceHash` without checking for `bytes32(0)`. An empty evidence hash makes off-chain dispute resolution more difficult and could indicate a bot-driven griefing dispute.

**Recommendation**: Add `if (evidenceHash == bytes32(0)) revert InvalidEvidenceHash();`

---

### SEC-L-04: No batch operations for settlement or reward claims

**Location**: `FinalizationLib.sol:settleValidator()`, `claimReward()`

Validators must call `settleValidator` once per `(projectId, index, nonce)` tuple. Contributors must call `claimReward` once per token address. In a protocol with many active projects, this requires many individual transactions with significant cumulative gas cost.

**Recommendation**: Add batch variants:
```solidity
function batchSettleValidator(bytes32[] calldata projectIds, uint256[] calldata indices, uint256[] calldata nonces) external;
function batchClaimRewards(address[] calldata tokens) external;
```

---

## Usability Findings

### SEC-U-01: No voluntary claim cancellation

A contributor who claims indices but realizes they cannot complete the work has no mechanism to voluntarily release them before the 7-day deadline. They must wait for expiry and accept the full slash penalty. A `cancelClaim` function with a reduced penalty (e.g., 50% of slash) would improve UX and return indices to the pool faster.

---

### SEC-U-02: Complex multi-step lifecycle requires 8+ transactions

The full happy path requires at minimum 8 separate transactions across multiple actors:

1. `createProject` (originator)
2. `fundProject` (originator)
3. `claimToContribute` (contributor)
4. `contribute` (contributor)
5. `commitValidation` (validator, N times)
6. `revealValidation` (validator, N times)
7. `computeConsensus` (keeper/anyone)
8. `settleValidator` (each validator)
9. `releaseContributorReward` (anyone)
10. `claimReward` (contributor + validators)

This is expensive and error-prone. Consider multicall wrappers or phased batch operations for common sequences.

---

### SEC-U-03: No view functions for index availability

There is no view function to query which indices are currently available for claiming (from either the return stack or the sequential range). Users must parse `ClaimCreated` / `ClaimExpired` events or call `getIndexState` for every possible index to determine claimable slots.

**Recommendation**: Add `getAvailableIndices(bytes32 projectId) external view returns (uint256[] memory)` or at minimum expose the range and stack state.

---

### SEC-U-04: No timeout for stuck pending contributions

If all validators commit but none reveal (and none are cancelled via `cancelExpiredCommitment`), a contribution sits in `Pending`/`Submitted` status forever. There is no keeper function to timeout a contribution and return the index when validators collectively fail.

The contributor's stake remains locked. The only partial mitigation is `cancelExpiredCommitment` for individual ghost validators, but if the required `numberOfValidations` can never be reached, the contribution is permanently stuck.

**Recommendation**: Add a contribution timeout (e.g., 30 days after submission) that returns the index and unlocks the contributor's stake.

---

### SEC-U-05: Per-token reward claiming

`claimReward(address token)` requires a separate transaction per reward token. A user participating in projects with different reward tokens must track each token address and call `claimReward` individually. See SEC-L-04 for the batch alternative.

---

## Summary Risk Matrix

| ID | Severity | Title | Release Blocker |
|----|----------|-------|:---------------:|
| SEC-C-01 | CRITICAL | Dispute state poisons recycled indices across nonces | Yes |
| SEC-C-02 | CRITICAL | Non-upgradeable ReentrancyGuard in upgradeable contract | Yes |
| SEC-H-01 | HIGH | Premature project completion drains escrow from validators | Yes |
| SEC-H-02 | HIGH | No force-settle for validators — permanent stake lock | No |
| SEC-H-03 | HIGH | Repeated dispute griefing via challenge window reset | Yes |
| SEC-H-04 | HIGH | Overturned rejection payouts exceed per-index budget | No |
| SEC-M-01 | MEDIUM | StakeVault ERC4626 functions not pausable | No |
| SEC-M-02 | MEDIUM | Missing events for consensus algorithm and treasury changes | No |
| SEC-M-03 | MEDIUM | Contributions accepted to cancelled projects | No |
| SEC-M-04 | MEDIUM | No reveal deadline enforcement | No |
| SEC-M-05 | MEDIUM | Error name reuse across unrelated contexts | No |
| SEC-M-06 | MEDIUM | `verifyStorageLocation` uses wrong hash length | No |
| SEC-M-07 | MEDIUM | No setters for `minClaimAmount`/`claimCooldown` | No |
| SEC-L-01 | LOW | `createProject` silently ignores config.originator | No |
| SEC-L-02 | LOW | Redundant zero-check dead code | No |
| SEC-L-03 | LOW | No validation on evidence hash | No |
| SEC-L-04 | LOW | No batch operations for settlement/claims | No |
| SEC-U-01 | USABILITY | No voluntary claim cancellation | No |
| SEC-U-02 | USABILITY | 8+ transaction lifecycle | No |
| SEC-U-03 | USABILITY | No view functions for index availability | No |
| SEC-U-04 | USABILITY | No timeout for stuck pending contributions | No |
| SEC-U-05 | USABILITY | Per-token reward claiming | No |

---

## Remediation Priority

### Phase 1: Release Blockers (estimated 5 dev-days)

| ID | Fix | Effort |
|----|-----|--------|
| SEC-C-01 | Key disputes by nonce, or clear on nonce increment | 2 days |
| SEC-C-02 | Swap to `ReentrancyGuardUpgradeable` | 0.5 days |
| SEC-H-01 | Add finalization check to `completeProject` | 1 day |
| SEC-H-03 | Limit one dispute per nonce or block reopening after rejection | 1.5 days |

### Phase 2: High Priority (estimated 4 dev-days)

| ID | Fix | Effort |
|----|-----|--------|
| SEC-H-02 | Add `forceSettleValidator` keeper function | 1.5 days |
| SEC-H-04 | Cap overturned rejection payout to per-index budget | 1 day |
| SEC-M-04 | Add reveal deadline enforcement | 0.5 days |
| SEC-M-07 | Add `minClaimAmount`/`claimCooldown` setters | 0.5 days |
| SEC-M-02 | Add missing events | 0.5 days |

### Phase 3: Medium/Low/UX (estimated 4 dev-days)

| ID | Fix | Effort |
|----|-----|--------|
| SEC-M-01 | Override `maxDeposit`/`maxMint` with pause check | 0.5 days |
| SEC-M-03 | Add project status check in `contribute` | 0.5 days |
| SEC-M-06 | Fix hash length in `verifyStorageLocation` | 0.25 days |
| SEC-L-04 | Add batch settle/claim functions | 1 day |
| SEC-U-01 | Add voluntary claim cancellation | 1 day |
| SEC-U-03 | Add index availability view functions | 0.5 days |

---

## Cross-Reference with REPORT.md

Some findings in this document overlap with or extend issues in the companion `REPORT.md`:

| This Report | REPORT.md | Relationship |
|-------------|-----------|--------------|
| SEC-C-01 | — | New finding (not previously identified) |
| SEC-C-02 | — | New finding (not previously identified) |
| SEC-H-01 | — | New finding (not previously identified) |
| SEC-H-02 | — | New finding (not previously identified) |
| SEC-H-03 | RISK-015 | Extends: RISK-015 identified cheap griefing; this details the infinite loop |
| SEC-H-04 | RISK-005 | Extends: RISK-005 noted escrow underflow; this identifies the 120% payout cause |
| SEC-M-04 | NEW-002 / RISK-009 | Duplicate: same reveal deadline issue, unified recommendation |

---

*This report was generated on February 18, 2026. All findings are based on manual code review of `src/` guided by the docs-b/skills/ security pipeline.*
