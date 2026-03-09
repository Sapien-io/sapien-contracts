# Sapien PoQ Protocol — Quantstamp Audit Report (Initial)

**Date:** 2026-02-25 through 2026-03-06
**Commit:** `#505c56a`
**Status:** DRAFT — All findings unresolved
**Total Findings:** 43 (7 High, 21 Medium, 11 Low, 1 Undetermined, 3 Informational) + 11 Suggestions

---

## Findings by File

### `src/libraries/ValidationLib.sol` — 19 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-2 | Vault's Deposit-Age Protections Bypassed via Share Transfer and Reset via Dust Deposits | High |
| POQ-3 | Not Storing Contributions per Nonce Enables Cross-Nonce Reward Theft and Dispute Corruption | High |
| POQ-4 | Cancellation Paths Do Not Unwind Active Pipeline, Permanently Stranding Validator Funds | High |
| POQ-5 | `expireClaim()` Double-Accounting Permanently Blocks Consensus and Traps Validator Stakes | High |
| POQ-6 | Missing Reveal Phase Lower Bound Enables Early Score Disclosure | High |
| POQ-8 | Reputation System Can Be Systematically Farmed via Self-Contained Cycles | Medium |
| POQ-10 | `numberOfValidations = 1` Collapses All Anti-Collusion Guarantees | Medium |
| POQ-12 | Unbounded Loops in `removeProject()` and `claimToValidate()` Create Gas-Based Liveness DoS | Medium |
| POQ-14 | Non-Outlier Validators Gain Positive Reputation on Upheld Disputes | Medium |
| POQ-19 | Validator Non-Reveal Indefinitely Stalls Consensus and Blocks Project Completion | Medium |
| POQ-20 | Validation Claim Slot Exhaustion | Medium |
| POQ-23 | Originator Can Claim Validation Slots for Their Own Project | Medium |
| POQ-25 | Commit-Reveal Hash Lacks Validator Binding, Enabling Score Replay | Medium |
| POQ-28 | Admin Timing Parameter Changes Retroactively Affect in-Flight Commitments | Medium |
| POQ-29 | Commit-Hash Encoding Drift Between Documentation and Contracts Causes Slash Exposure | Low |
| POQ-30 | Admin Changes to `minValidationStake` Penalize Validators Committed Mid-Claim | Low |
| POQ-32 | Deadline Naming Confusion Grants Validators an Unintended Extended Reveal Window | Low |
| POQ-43 | Enum Type Confusion Allows Emission of `ValidationClaimExpired()` Events | Undetermined |
| S8 | `computeConsensus()` allows execution on non-Active projects | Suggestion |

### `src/libraries/FinalizationLib.sol` — 14 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-1 | Originator Can Complete Projects While Contributors Hold Active Reserved Claims | High |
| POQ-3 | Not Storing Contributions per Nonce Enables Cross-Nonce Reward Theft and Dispute Corruption | High |
| POQ-4 | Cancellation Paths Do Not Unwind Active Pipeline, Permanently Stranding Validator Funds | High |
| POQ-7 | Reported Originator Reclaims Escrow After Project Cancellation, Depriving Contributors of Rewards | High |
| POQ-9 | Profitable Self-Dispute Collusion Cycle Extracts Escrow at Zero Net Cost | Medium |
| POQ-13 | Upheld Dispute Does Not Restore Slot Lifecycle or Pay Challenger Consistently | Medium |
| POQ-14 | Non-Outlier Validators Gain Positive Reputation on Upheld Disputes | Medium |
| POQ-15 | Escrow Settlement Is Order-Dependent and Late Claimants Receive Reduced Payouts or Nothing | Medium |
| POQ-16 | `completeProject()` Missing Originator Report Check Enables Slash Evasion | Medium |
| POQ-19 | Validator Non-Reveal Indefinitely Stalls Consensus and Blocks Project Completion | Medium |
| POQ-22 | `minClaimAmount` Is Token-Agnostic and Cannot Encode Absolute Value | Medium |
| POQ-24 | New Submission Round Starts Before Prior Nonce Challenge Period Expires | Medium |
| POQ-32 | Deadline Naming Confusion Grants Validators an Unintended Extended Reveal Window | Low |
| S9 | `ContributionAdapterFeePaid` event emitted at reward settlement, not claim creation | Suggestion |

### `src/libraries/DisputeLib.sol` — 10 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-3 | Not Storing Contributions per Nonce Enables Cross-Nonce Reward Theft and Dispute Corruption | High |
| POQ-4 | Cancellation Paths Do Not Unwind Active Pipeline, Permanently Stranding Validator Funds | High |
| POQ-7 | Reported Originator Reclaims Escrow After Project Cancellation, Depriving Contributors of Rewards | High |
| POQ-9 | Profitable Self-Dispute Collusion Cycle Extracts Escrow at Zero Net Cost | Medium |
| POQ-13 | Upheld Dispute Does Not Restore Slot Lifecycle or Pay Challenger Consistently | Medium |
| POQ-18 | Index Recycling Destroys Prior Dispute Window and Enables Stale-Nonce Disputes | Medium |
| POQ-21 | Disputes Can Be Opened and Processed on Cancelled Projects | Medium |
| POQ-33 | Disputes and Originator Reports Can Be Front-Run for Profit | Low |
| POQ-37 | Missing Input Validations on Project and Administrative Parameters | Low |
| S10 | `OriginatorReportResolved` event not emitted in `upholdOriginatorReport()` | Suggestion |

### `src/libraries/ContributionLib.sol` — 9 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-1 | Originator Can Complete Projects While Contributors Hold Active Reserved Claims | High |
| POQ-5 | `expireClaim()` Double-Accounting Permanently Blocks Consensus and Traps Validator Stakes | High |
| POQ-8 | Reputation System Can Be Systematically Farmed via Self-Contained Cycles | Medium |
| POQ-16 | `completeProject()` Missing Originator Report Check Enables Slash Evasion | Medium |
| POQ-17 | `removeProject()` / `expireClaim()` Write-Write Conflict Permanently Reverts Claim Expiry | Medium |
| POQ-18 | Index Recycling Destroys Prior Dispute Window and Enables Stale-Nonce Disputes | Medium |
| POQ-19 | Validator Non-Reveal Indefinitely Stalls Consensus and Blocks Project Completion | Medium |
| POQ-26 | Deterministic PRNG on L2 Enables Selective Validator Assignment | Medium |
| POQ-37 | Missing Input Validations on Project and Administrative Parameters | Low |

### `src/libraries/OriginationLib.sol` — 9 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-4 | Cancellation Paths Do Not Unwind Active Pipeline, Permanently Stranding Validator Funds | High |
| POQ-7 | Reported Originator Reclaims Escrow After Project Cancellation, Depriving Contributors of Rewards | High |
| POQ-8 | Reputation System Can Be Systematically Farmed via Self-Contained Cycles | Medium |
| POQ-12 | Unbounded Loops in `removeProject()` and `claimToValidate()` Create Gas-Based Liveness DoS | Medium |
| POQ-17 | `removeProject()` / `expireClaim()` Write-Write Conflict Permanently Reverts Claim Expiry | Medium |
| POQ-31 | Custom Reward Tokens Can Bypass Reward Payments and Trick Protocol Participants | Low |
| POQ-37 | Missing Input Validations on Project and Administrative Parameters | Low |
| POQ-40 | Multiple `fundProject()` Calls with Different Adapters Silently Overwrite Prior Adapter | Informational |
| S4 | `removeProject()` natspec implies unfunded-only restriction not in code | Suggestion |

### `src/SapienCore.sol` — 9 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-3 | Not Storing Contributions per Nonce Enables Cross-Nonce Reward Theft and Dispute Corruption | High |
| POQ-6 | Missing Reveal Phase Lower Bound Enables Early Score Disclosure | High |
| POQ-11 | Protocol Pausability Creates Slash and Reputation Exposure for Honest Participants | Medium |
| POQ-28 | Admin Timing Parameter Changes Retroactively Affect in-Flight Commitments | Medium |
| POQ-30 | Admin Changes to `minValidationStake` Penalize Validators Committed Mid-Claim | Low |
| POQ-36 | `ORIGINATOR` Role Key Can Collide with a Registered Skill Name | Low |
| POQ-37 | Missing Input Validations on Project and Administrative Parameters | Low |
| POQ-42 | Storage Variables Not Initialised in `initialize()` | Informational |
| S2 | `AdapterFeeTooHigh` error reused for unrelated validation checks | Suggestion |

### `src/libraries/ReputationLib.sol` — 7 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-8 | Reputation System Can Be Systematically Farmed via Self-Contained Cycles | Medium |
| POQ-14 | Non-Outlier Validators Gain Positive Reputation on Upheld Disputes | Medium |
| POQ-24 | New Submission Round Starts Before Prior Nonce Challenge Period Expires | Medium |
| POQ-27 | Asymmetric Reputation Rollback on Dispute Settlement | Medium |
| POQ-34 | `dailyGain` Tracking Inaccurate for Users Near the Reputation Cap | Low |
| POQ-39 | Reputation Decay Timing Allows Day-Boundary Manipulation | Low |
| S1 | `ReputationUpdated` event emits post-decay score as `oldScore` | Suggestion |

### `src/SapienVault.sol` — 3 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-2 | Vault's Deposit-Age Protections Bypassed via Share Transfer and Reset via Dust Deposits | High |
| POQ-38 | Small Slash Amounts at High Share Prices Round Down to 0 | Low |
| S3 | Natspec states slashed tokens sent to treasury but code burns them | Suggestion |

### `src/libraries/ConsensusLib.sol` — 3 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-9 | Profitable Self-Dispute Collusion Cycle Extracts Escrow at Zero Net Cost | Medium |
| POQ-35 | Overflow Handler in `ConsensusLib` Is Unreachable Under Solidity 0.8+ | Low |
| S7 | Comment/code mismatch in `ConsensusLib.calculate()` | Suggestion |

### `src/Constants.sol` — 3 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-10 | `numberOfValidations = 1` Collapses All Anti-Collusion Guarantees | Medium |
| POQ-32 | Deadline Naming Confusion Grants Validators an Unintended Extended Reveal Window | Low |
| POQ-41 | Hardcoded `VALIDATION_CLAIM_DEADLINE` Cannot Be Tuned without a Contract Upgrade | Informational |

### `src/interfaces/ISapienCore.sol` — 3 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-32 | Deadline Naming Confusion Grants Validators an Unintended Extended Reveal Window | Low |
| S4 | `removeProject()` natspec implies unfunded-only restriction not in code | Suggestion |
| S9 | `ContributionAdapterFeePaid` event emitted at reward settlement, not claim creation | Suggestion |

### `src/Types.sol` — 2 findings

| ID | Title | Severity |
|----|-------|----------|
| POQ-3 | Not Storing Contributions per Nonce Enables Cross-Nonce Reward Theft and Dispute Corruption | High |
| POQ-43 | Enum Type Confusion Allows Emission of `ValidationClaimExpired()` Events | Undetermined |

### `src/interfaces/ISapienVault.sol` — 1 finding

| ID | Title | Severity |
|----|-------|----------|
| S3 | Natspec states slashed tokens sent to treasury but code burns them | Suggestion |

---

## High Severity

### POQ-1 — Originator Can Complete Projects While Contributors Hold Active Reserved Claims
**Files:** `src/libraries/FinalizationLib.sol`, `src/libraries/ContributionLib.sol`

`completeProject()` requires only `pendingContributions == 0`, but `pendingContributions` is incremented at `contribute()` (submission) not at `claimToContribute()` (reservation). An originator can call `completeProject()` while contributors have locked stake and reserved slots. After completion, `contribute()` reverts with `ProjectNotActive`. When the claim deadline passes, `expireClaim()` slashes contributors who were unable to submit.

**Recommendation:** Check `proj.availableSlots == proj.totalQuantity` in `completeProject()`, or verify no `Claim` structs in `Active` status reference the project.

---

### POQ-2 — Vault's Deposit-Age Protections Bypassed via Share Transfer and Reset via Dust Deposits
**Files:** `src/SapienVault.sol`, `src/libraries/ValidationLib.sol`

**Sub-issue A — Transfer bypass:** `_update()` transfers shares but does not set `lastDepositTimestamp` for the receiver. A user can deposit, transfer shares to a fresh address, and immediately lock validator capacity, bypassing `minDepositAge`.

**Sub-issue B — Dust deposit griefing:** `_deposit()` unconditionally sets `lastDepositTimestamp[receiver] = block.timestamp` for any amount. An attacker calls `vault.deposit(1, victim)` to reset the victim's timestamp, blocking `lockValidatorCapacity()` for up to 7 days.

**Recommendation:**
- Set `lastDepositTimestamp[to] = block.timestamp` inside `_update()` for transfers.
- Treat `depositTs == 0` as "never deposited" (fail the check, don't bypass it).
- Update `lastDepositTimestamp` only when `msg.sender == receiver`, or require a minimum deposit amount.

---

### POQ-3 — Not Storing Contributions per Nonce Enables Cross-Nonce Reward Theft and Dispute Corruption
**Files:** `src/libraries/FinalizationLib.sol`, `src/libraries/DisputeLib.sol`, `src/libraries/ValidationLib.sol`, `src/SapienCore.sol`, `src/Types.sol`

The `contributions` mapping is keyed by `(projectId, index)` without a nonce dimension, while `consensusReports`, `disputes`, and `validatorCommits` include a nonce. When `computeConsensus()` rejects a contribution and recycles the index, the `Contribution` struct is overwritten by the next round's data.

**Sub-issue A — Reward theft:** A non-outlier validator from a rejected nonce-N round calls `settleValidator(projectId, index, N)`. It reads the old consensus report but the current (nonce-N+1) contribution data, passing all guards and receiving rewards.

**Sub-issue B — Dispute corruption:** `resolveDispute()` reads `contrib.consensusNonce` from the overwritten struct, looking up `disputes[projectId][index][N+1]` (empty). The original dispute at nonce N is permanently unreachable and the challenger's bond is stranded.

**Recommendation:**
- Add a nonce consistency check in `_settleValidatorFor()`: require supplied nonce equals `contrib.consensusNonce`.
- Pass nonce as an explicit parameter in `resolveDispute()` and `escalateDispute()`.
- Add a nonce dimension to the `contributions` mapping.
- Block index recycling while prior-round disputes or unsettled validators remain outstanding.

---

### POQ-4 — Cancellation Paths Do Not Unwind Active Pipeline, Permanently Stranding Validator Funds
**Files:** `src/libraries/OriginationLib.sol`, `src/libraries/DisputeLib.sol`, `src/libraries/FinalizationLib.sol`, `src/libraries/ValidationLib.sol`

When a project is cancelled via `removeProject()` or `upholdOriginatorReport()`, neither function releases validator in-flight stakes. The wind-down loop only handles contributor locks. After cancellation, all validator recovery paths revert: `_settleValidatorFor()` → `ProjectNotActive`, `forceSettleValidator()` → `ConsensusNotReady`/`ProjectNotActive`, `cancelExpiredCommitment()` → `AlreadyRevealed`. Additionally, `claimToValidate()` has no project status check, allowing new validators to enter a cancelled project.

**Recommendation:**
- Both cancellation paths must iterate over committed validators and call `releaseCommit()` for each in-flight stake.
- Add a project status guard to `claimToValidate()`, `commitValidation()`, and `revealValidation()`.

---

### POQ-5 — `expireClaim()` Double-Accounting Permanently Blocks Consensus and Traps Validator Stakes
**Files:** `src/libraries/ContributionLib.sol`, `src/libraries/ValidationLib.sol`

When `expireClaim()` processes a claim containing both `Pending` and `Reserved` contributions, it depletes the contributor lock for `Pending` slots but leaves their status as `Pending`. When `computeConsensus()` later runs on those slots and rejects, the slash reverts with `InsufficientContributorLock` because the lock was already depleted. This permanently blocks consensus and traps validator `inFlight` stakes.

**Recommendation:** `expireClaim()` should transition `Pending` contributions to a terminal state and decrement `pendingContributions`. Alternatively, `computeConsensus()` should verify lock sufficiency before slashing.

---

### POQ-6 — Missing Reveal Phase Lower Bound Enables Early Score Disclosure
**Files:** `src/SapienCore.sol`, `src/libraries/ValidationLib.sol`

`revealValidation()` enforces only an upper bound on reveal timing with no lower bound requiring the commit phase to complete. A validator can commit and reveal in the same block. The `ValidationRevealed` event exposes the score, allowing later validators to copy it and submit matching commits, collapsing the scheme into plaintext voting.

**Recommendation:** Add a reveal-phase gate: `require(block.timestamp >= vc.commitTimestamp + $.commitDeadline, "CommitPhaseActive")`.

---

### POQ-7 — Reported Originator Reclaims Escrow After Project Cancellation, Depriving Contributors of Rewards
**Files:** `src/libraries/FinalizationLib.sol`, `src/libraries/DisputeLib.sol`, `src/libraries/OriginationLib.sol`

After cancellation via `upholdOriginatorReport()` or `removeProject()`, contributors with `Accepted` work cannot call `releaseContributorReward()` (reverts on `Cancelled` projects). However, `refundEscrow()` explicitly permits `Cancelled` status. After 30 days, the punished originator drains all remaining escrow including earned contributor rewards.

**Recommendation:** Pre-compute and pre-distribute owed contributor rewards into `pendingRewards` as part of the cancellation flow, before setting `Cancelled`.

---

## Medium Severity

### POQ-8 — Reputation System Can Be Systematically Farmed via Self-Contained Cycles
**Files:** `OriginationLib.sol`, `ContributionLib.sol`, `ValidationLib.sol`, `ReputationLib.sol`

**Path 1:** Single account calls `createProject()`, `fundProject()`, `completeProject()` in one block with zero contributions — gets originator reputation.
**Path 2:** Sybil accounts cycle through create → fund → contribute → validate → consensus in one block using worthless reward tokens, `numberOfValidations = 1`, and temporary stake lockups.

**Recommendation:** Whitelist reward tokens; require at least one accepted contribution for completion; minimum `numberOfValidations` of 3; prevent originator from being their own validator.

---

### POQ-9 — Profitable Self-Dispute Collusion Cycle Extracts Escrow at Zero Net Cost
**Files:** `src/libraries/FinalizationLib.sol`, `src/libraries/ConsensusLib.sol`, `src/libraries/DisputeLib.sol`

N Sybil validators claim all slots, submit identical scores (zero std dev → no outlier slashing), a Sybil disputer opens a dispute, waits 7 days for permissionless `escalateDispute()` auto-uphold, receives bond back + 20% of `rewardRate`. All validators get stake returned and positive reputation despite overturned consensus.

**Recommendation:** Validators with overturned consensus should receive negative reputation. Require operator/multi-sig for dispute escalation.

---

### POQ-10 — `numberOfValidations = 1` Collapses All Anti-Collusion Guarantees
**Files:** `ValidationLib.sol`, `Constants.sol`

With `numberOfValidations = 1`: std dev is always zero, outlier detection cannot trigger, a single validator can sweep all slots atomically. Reward is independent of stake amount.

**Recommendation:** Set minimum `numberOfValidations` of 3 at the protocol level.

---

### POQ-11 — Protocol Pausability Creates Slash and Reputation Exposure for Honest Participants
**Files:** `SapienCore.sol`

While paused, all actions are blocked but internal timers continue. A 1-hour pause makes contributor claims slashable; a 2-hour pause makes validator commitments fully slashable.

**Recommendation:** Track cumulative paused duration and subtract from all deadline calculations.

---

### POQ-12 — Unbounded Loops in `removeProject()` and `claimToValidate()` Create Gas-Based Liveness DoS
**Files:** `src/libraries/OriginationLib.sol`, `src/libraries/ValidationLib.sol`

`removeProject()` iterates over all `totalQuantity` contributions with no cap. `claimToValidate()` scans the entire `pendingIndices` array. Testing confirms `removeProject()` exceeds 30M gas for large projects.

**Recommendation:** Implement paginated processing; add a hard cap on `totalQuantity`; use indexed queue or cursor-based iteration.

---

### POQ-13 — Upheld Dispute Does Not Restore Slot Lifecycle or Pay Challenger Consistently
**Files:** `src/libraries/DisputeLib.sol`, `src/libraries/FinalizationLib.sol`

**Sub-issue A:** `upholdDispute()` on an `Accepted` contribution decrements `pendingContributions` but does not change status, increment `availableSlots`, push to `returnStack`, or increment `submissionNonce`. The slot is permanently consumed.

**Sub-issue B:** For `Rejected` contributions, contributor compensation is paid first, and if escrow is insufficient for both compensation and challenger reward, the challenger is silently skipped.

**Recommendation:** Transition contribution to terminal state; increment `availableSlots`; push to `returnStack`. For payouts, check total required atomically or implement pro-rata allocation.

---

### POQ-14 — Non-Outlier Validators Gain Positive Reputation on Upheld Disputes
**Files:** `src/libraries/FinalizationLib.sol`, `src/libraries/ReputationLib.sol`, `src/libraries/ValidationLib.sol`

`ReputationLib.update(validator, skill, true, 0)` is placed outside the dispute-status conditional block. Validators who were demonstrably incorrect still receive +10 reputation when their consensus is overturned by a dispute. This creates a compounding feedback loop on consensus weight.

**Recommendation:** Move the positive reputation update inside the accepted-and-not-upheld conditional. Apply reputation updates only after the challenge period expires.

---

### POQ-15 — Escrow Settlement Is Order-Dependent and Late Claimants Receive Reduced Payouts or Nothing
**Files:** `src/libraries/FinalizationLib.sol`

Payouts are capped to current `projectEscrow` without reserving funds for future claimants. `releaseContributorReward()` sets `rewardReleased = true` before computing the (possibly capped) payout, making claims one-shot. Early settlers drain escrow; late settlers get partial or zero payouts. Originator can also call `refundEscrow()` before all settlements.

**Recommendation:** Snapshot liabilities at consensus time and reserve amounts. Implement pro-rata allocation. Block `refundEscrow()` until all settlements complete.

---

### POQ-16 — `completeProject()` Missing Originator Report Check Enables Slash Evasion
**Files:** `src/libraries/ContributionLib.sol`, `src/libraries/FinalizationLib.sol`

`completeProject()` releases `originatorLockedStake` without checking for an open `OriginatorReport`. An originator can front-run `resolveOriginatorReport()` by calling `completeProject()` first, zeroing the stake so the uphold slash is a no-op.

**Recommendation:** Add `if ($.originatorReports[projectId].status == OriginatorReportStatus.Open) revert DisputeInProgress();` to `completeProject()`.

---

### POQ-17 — `removeProject()` / `expireClaim()` Write-Write Conflict Permanently Reverts Claim Expiry
**Files:** `src/libraries/OriginationLib.sol`, `src/libraries/ContributionLib.sol`

`removeProject()` zeros `claimId` on all contributions but does not cancel the parent `Claim` struct. When `expireClaim()` later iterates, `contrib.claimId != claimId` causes all indices to be skipped, triggering an `InvalidIndex` revert. The `Claim` remains `Active` indefinitely.

**Recommendation:** In `removeProject()`'s wind-down loop, set `claim.status = ClaimStatus.Expired` before wiping contribution data.

---

### POQ-18 — Index Recycling Destroys Prior Dispute Window and Enables Stale-Nonce Disputes
**Files:** `src/libraries/ContributionLib.sol`, `src/libraries/DisputeLib.sol`

**Sub-issue A:** When `contribute()` is called on a recycled slot, `challengeEndsAt` is set to 0. Prior round's dispute window is silently closed even if the deadline hasn't elapsed.

**Sub-issue B:** Between `claimToContribute()` and `contribute()`, stale `challengeEndsAt` from the prior round allows a dispute to be opened at the old nonce. After recycling, this dispute becomes permanently unresolvable and the challenger's bond is locked.

**Recommendation:** Snapshot `challengeEndsAt` and `consensusNonce` per-nonce in `ConsensusReport`. Clear stale fields in `claimToContribute()`. Block re-contribution while prior challenge window is open.

---

### POQ-19 — Validator Non-Reveal Indefinitely Stalls Consensus and Blocks Project Completion
**Files:** `src/libraries/ValidationLib.sol`, `src/libraries/ContributionLib.sol`, `src/libraries/FinalizationLib.sol`

`computeConsensus()` requires `revealCount >= numberOfValidations`. One non-revealing validator stalls consensus for `commitDeadline + revealDeadline` (default 2 days). Even without adversarial intent, if validators never reach quorum, `pendingContributions` is never decremented and `completeProject()` permanently fails. No protocol-level timeout forces resolution.

**Recommendation:** Require meaningful collateral at `claimToValidate()`. Add a contribution-level timeout. Allow consensus computation with a minimum threshold (e.g., 2/3 of validators) once the reveal deadline expires.

---

### POQ-20 — Validation Claim Slot Exhaustion
**Files:** `src/libraries/ValidationLib.sol`

`claimToValidate()` requires zero economic stake at claim time. N Sybil addresses can exhaust all validation slots, blocking consensus. After `VALIDATION_CLAIM_DEADLINE` (1 hour), expired claims are cancellable but the attacker can immediately re-claim.

**Recommendation:** Require a small refundable deposit at `claimToValidate()` time, slashed on expiry. Implement cooldown or address-level throttle for repeat offenders.

---

### POQ-21 — Disputes Can Be Opened and Processed on Cancelled Projects
**Files:** `src/libraries/DisputeLib.sol`

`openDispute()` does not check project status. Disputes on cancelled projects pay challenger rewards from `projectEscrow`, reducing the originator's refund.

**Recommendation:** Add `if (proj.status == ProjectStatus.Cancelled) revert ProjectNotActive();` to `openDispute()`.

---

### POQ-22 — `minClaimAmount` Is Token-Agnostic and Cannot Encode Absolute Value
**Files:** `src/libraries/FinalizationLib.sol`

`minClaimAmount` is a single `uint256` applied to all `rewardToken` addresses. 1e18 blocks WBTC claims while accepting any amount of a 6-decimal token.

**Recommendation:** Define `minClaimAmount` as `mapping(address => uint256)` per reward token.

---

### POQ-23 — Originator Can Claim Validation Slots for Their Own Project
**Files:** `src/libraries/ValidationLib.sol`

`claimToValidate()` prevents validators from being assigned to their own contributions but not originators from validating their own project.

**Recommendation:** Add `require(proj.originator != msg.sender, "OriginatorCannotValidate")`.

---

### POQ-24 — New Submission Round Starts Before Prior Nonce Challenge Period Expires
**Files:** `src/libraries/FinalizationLib.sol`, `src/libraries/ReputationLib.sol`

When `computeConsensus()` rejects a contribution, it immediately recycles the slot. A new contributor can submit while a dispute on the prior round is still open.

**Recommendation:** Delay index recycling until `challengeEndsAt` has elapsed, or block new submissions while a prior-nonce dispute is open.

---

### POQ-25 — Commit-Reveal Hash Lacks Validator Binding, Enabling Score Replay
**Files:** `src/libraries/ValidationLib.sol`

Commit hash is `keccak256(abi.encodePacked(score, salt))` without `msg.sender`. Any validator can copy a revealed `(score, salt)` pair from another validator's on-chain reveal transaction.

**Recommendation:** Include `msg.sender` in the preimage: `commitHash = keccak256(abi.encodePacked(validator, score, salt))`.

---

### POQ-26 — Deterministic PRNG on L2 Enables Selective Validator Assignment
**Files:** `src/libraries/ContributionLib.sol`

`claimToValidate()` seeds its Fisher-Yates shuffle with `block.prevrandao`. On Base (L2), `prevrandao` is constant across all L2 blocks within the same epoch. A validator can time their call or use conditional reverts to cherry-pick favorable assignments.

**Recommendation:** Increase PRNG entropy (commitment-based seed, validator address, block hash). Require minimum eligible pool depth.

---

### POQ-27 — Asymmetric Reputation Rollback on Dispute Settlement
**Files:** `src/libraries/ReputationLib.sol`

Reputation updates are applied before the challenge period ends. Intermediate decay makes rollback imprecise. Contributors with upheld disputes can receive net positive reputation from ultimately rejected work.

**Recommendation:** Apply reputation updates only after challenge period expires. If updates must occur earlier, store exact deltas for precise rollback.

---

### POQ-28 — Admin Timing Parameter Changes Retroactively Affect in-Flight Commitments
**Files:** `src/SapienCore.sol`, `src/libraries/ValidationLib.sol`

`commitDeadline` and `revealDeadline` are read from global storage at check time. Reducing them retroactively closes windows for validators who committed under the prior values. `cancelExpiredCommitment()` then slashes 100% of their stake.

**Recommendation:** Snapshot `commitDeadline + revealDeadline` per commitment at `commitValidation()` time, or apply a timelock to deadline reductions.

---

## Low Severity

### POQ-29 — Commit-Hash Encoding Drift Between Documentation and Contracts Causes Slash Exposure

Documentation specifies `keccak256(abi.encodePacked(uint16(score), salt))` but the contract uses `uint256(score)`. A validator following docs commits an unmatchable hash and gets 100% slashed on expiry.

**Recommendation:** Correct `docs/architecture/lifecycle.md` to `uint256(score)`. Provide an on-chain `computeCommitHash()` helper.

---

### POQ-30 — Admin Changes to `minValidationStake` Penalize Validators Committed Mid-Claim
**Files:** `src/libraries/ValidationLib.sol`, `src/SapienCore.sol`

`setMinValidationStake()` applies immediately. A validator who claimed under a lower value may be unable to commit, leading to slashing and reputation penalties.

**Recommendation:** Snapshot `minValidationStake` per claim at `claimToValidate()` time, or apply a timelock.

---

### POQ-31 — Custom Reward Tokens Can Bypass Reward Payments and Trick Protocol Participants
**Files:** `OriginationLib.sol`

`createProject()` allows arbitrary reward token addresses (worthless, fee-on-transfer, rebasing, or malicious contracts).

**Recommendation:** Employ a whitelist of vetted reward tokens.

---

### POQ-32 — Deadline Naming Confusion Grants Validators an Unintended Extended Reveal Window
**Files:** `src/interfaces/ISapienCore.sol`, `src/Constants.sol`, `src/libraries/ValidationLib.sol`, `src/libraries/FinalizationLib.sol`

`commitDeadline` is added to the reveal window check (`commitTimestamp + commitDeadline + revealDeadline`), doubling the intended reveal window.

**Recommendation:** Reveal window check should reference `vc.commitTimestamp + $.revealDeadline` only.

---

### POQ-33 — Disputes and Originator Reports Can Be Front-Run for Profit
**Files:** `src/libraries/DisputeLib.sol`

`openDispute()` and `reportOriginator()` don't bind `evidenceHash`/`evidenceCid` to `msg.sender`, exposing them to MEV front-running.

**Recommendation:** Implement a commit-reveal scheme binding the preimage to `msg.sender`.

---

### POQ-34 — `dailyGain` Tracking Inaccurate for Users Near the Reputation Cap
**Files:** `src/libraries/ReputationLib.sol`

When `currentScore` is near `MAX_REPUTATION`, the actual gain is capped but `dailyGain` accumulates the full uncapped value, over-representing the change.

**Recommendation:** Accumulate into `dailyGain` only the actual increase amount.

---

### POQ-35 — Overflow Handler in `ConsensusLib` Is Unreachable Under Solidity 0.8+
**Files:** `src/libraries/ConsensusLib.sol`

Post-multiplication overflow guard is dead code — Solidity 0.8+ reverts on overflow before reaching the conditional.

**Recommendation:** Use `Math.mulDiv()` or place multiplication in `unchecked {}` with bounds checking.

---

### POQ-36 — `ORIGINATOR` Role Key Can Collide with a Registered Skill Name
**Files:** `src/SapienCore.sol`

`registerSkill()` doesn't check for collision with `keccak256("ORIGINATOR")`. Registering a skill named `"ORIGINATOR"` would break reputation separation.

**Recommendation:** Guard `registerSkill()` against reserved system identifiers.

---

### POQ-37 — Missing Input Validations on Project and Administrative Parameters
**Files:** `src/libraries/OriginationLib.sol`, `src/libraries/ContributionLib.sol`, `src/libraries/DisputeLib.sol`, `src/SapienCore.sol`

Various parameters across `createProject()`, `fundProject()`, `contribute()`, `openDispute()`, `registerSkill()`, and admin setters accept any value without validation.

**Recommendation:** Add relevant input validation checks.

---

### POQ-38 — Small Slash Amounts at High Share Prices Round Down to 0
**Files:** `src/SapienVault.sol`

When share-to-asset ratio is high, `convertToShares(assetAmount)` rounds to 0. `_burnShares` skips the burn but the lock bucket is already decremented — a "fake slash" with no economic penalty.

**Recommendation:** Require `shares > 0` and revert if the slash would have no effect, or track locks in share-denominated terms.

---

### POQ-39 — Reputation Decay Timing Allows Day-Boundary Manipulation
**Files:** `src/libraries/ReputationLib.sol`

Decay uses `elapsed / 1 days` (integer division), creating discrete daily steps. Users can avoid a day's decay by timing transactions just before the boundary.

**Recommendation:** Use finer time intervals or continuous fractional decay.

---

## Undetermined Severity

### POQ-43 — Enum Type Confusion Allows Emission of `ValidationClaimExpired()` Events
**Files:** `ValidationLib.sol`, `Types.sol`

`ProjectStatus`, `ClaimStatus`, and `ValidationClaimStatus` enums start with non-placeholder values (`Created`, `Active`, `Active`). `cancelExpiredValidationClaim()` on an unused `claimId` proceeds to set status and emit events on uninitialized data. Off-chain impact is undetermined.

**Recommendation:** Add `Empty`/`Unused` as the first entry in the listed enums.

---

## Informational

### POQ-40 — Multiple `fundProject()` Calls with Different Adapters Silently Overwrite Prior Adapter
**Files:** `src/libraries/OriginationLib.sol`

Each call with a different `adapter` overwrites `originationAdapter[projectId]`. Prior adapter address becomes unretrievable.

**Recommendation:** Prevent adapter changes after first funding, or maintain a history.

---

### POQ-41 — Hardcoded `VALIDATION_CLAIM_DEADLINE` Cannot Be Tuned without a Contract Upgrade

`VALIDATION_CLAIM_DEADLINE = 1 hours` is a compile-time constant, unlike all other configurable deadlines.

**Recommendation:** Convert to a configurable storage variable with bounds (e.g., 30 min – 24 hours).

---

### POQ-42 — Storage Variables Not Initialised in `initialize()`
**Files:** `src/SapienCore.sol`

`minValidationStake`, `minClaimAmount`, and `claimCooldown` remain zero until explicitly configured, allowing exploitation during the deployment-to-configuration window.

**Recommendation:** Set safe non-zero defaults in `initialize()`.

---

## Auditor Suggestions

| ID | Description | Files |
|----|-------------|-------|
| S1 | `ReputationUpdated` event emits post-decay score as `oldScore` | `ReputationLib.sol` |
| S2 | `AdapterFeeTooHigh` error reused for unrelated validation checks | `SapienCore.sol` |
| S3 | Natspec states slashed tokens sent to treasury but code burns them | `ISapienVault.sol`, `SapienVault.sol` |
| S4 | `removeProject()` natspec implies unfunded-only restriction not in code | `ISapienCore.sol`, `OriginationLib.sol` |
| S5 | `fundProject()` natspec says transition to `Active` but code transitions to `Funded` | — |
| S6 | `resolveDispute()` natspec incorrectly describes a new validation round | — |
| S7 | Comment/code mismatch in `ConsensusLib.calculate()` | `ConsensusLib.sol` |
| S8 | `computeConsensus()` allows execution on non-Active projects | `ValidationLib.sol` |
| S9 | `ContributionAdapterFeePaid` event emitted at reward settlement, not claim creation | `ISapienCore.sol`, `FinalizationLib.sol` |
| S10 | `OriginatorReportResolved` event not emitted in `upholdOriginatorReport()` | `DisputeLib.sol` |
| S11 | Unlocked pragma (`^0.8.30`) and misc best-practice violations | Multiple files |
