# Sapien v0.5 Security/Functionality Findings

**Date**: 2026-02-23  
**Scope**: `src/` contracts and libraries, reviewed using the checklists in `docs/skills/`  
**Method**: manual function-by-function review, lifecycle/state-transition analysis, and adversarial path modeling

---

## [HIGH] Expired validation claims do not release validation slots (permanent consensus DoS)

**Location**: `src/libraries/ValidationLib.sol` (`claimToValidate`, `cancelExpiredValidationClaim`)

**Description**:  
`claimToValidate` marks `vc.claimed = true` and increments `validationCounters.claimCount`.  
When `cancelExpiredValidationClaim` is called, the claim is only marked `Expired`; it does not clear `claimed` flags or decrement `claimCount` for uncommitted indices.

This leaves validation capacity logically consumed forever for that `(projectId, index, nonce)`.

**Impact**:  
An attacker can reserve all validator slots and let claims expire, permanently preventing new validators from claiming and preventing `computeConsensus`. The contribution remains stuck in `Pending`, and project completion can be blocked.

**Proof of Concept**:
1. Create/fund project with `numberOfValidations = N`.
2. Submit one contribution (status `Pending`).
3. Use N attacker addresses to call `claimToValidate` for the same index (no stake required at claim time).
4. Wait past `VALIDATION_CLAIM_DEADLINE`; call `cancelExpiredValidationClaim` for each claim.
5. New `claimToValidate` calls now revert because `claimCount` is still `N`, while `revealCount` is below `N`.
6. `computeConsensus` cannot be reached.

**Recommendation**:  
On expired-claim cancellation, iterate the claim indices and:
- clear `validatorCommits[...].claimed` for uncommitted entries,
- clear `validationClaimId`,
- decrement `validationCounters.claimCount` for each released index.

Also consider adding an explicit cleanup function for stale reservations.

---

## [HIGH] Commit phase deadline is unenforced for claimed validators (late-commit last-look attack)

**Location**: `src/libraries/ValidationLib.sol` (`commitValidation`, `cancelExpiredValidationClaim`)

**Description**:  
`commitValidation` only checks `vc.claimed` and `vc.commitHash == 0`. It does not verify that the associated validation claim is still `Active` or before its deadline.

Because of this, a validator can:
- claim early,
- wait until other validators reveal scores,
- commit and reveal afterward with full information.

Even if the claim was already marked `Expired`, commit is still possible because expiry does not invalidate `vc.claimed`.

**Impact**:  
Commit-reveal anti-herding guarantees are weakened. Attackers gain a "last look" advantage and can strategically shape consensus/outlier outcomes after observing honest reveals.

**Proof of Concept**:
1. Attacker calls `claimToValidate` and does nothing.
2. Honest validators commit and reveal.
3. Validation claim expires and is cancelled.
4. Attacker still calls `commitValidation` successfully (deadline/status not enforced).
5. Attacker immediately calls `revealValidation` with a strategic score.

**Recommendation**:  
In `commitValidation`, require:
- `validationClaimId != 0`,
- `validationClaims[validationClaimId].status == Active`,
- `block.timestamp <= validationClaims[validationClaimId].deadline`.

Additionally, enforce a contribution-level commit cutoff (anchored to submission time or first-commit time) so each validator cannot create a personal rolling commit/reveal window.

---

## [HIGH] Upheld disputes on accepted contributions deadlock project finalization

**Location**: `src/libraries/DisputeLib.sol` (`upholdDispute`), `src/libraries/FinalizationLib.sol` (`releaseContributorReward`, `completeProject`)

**Description**:  
For accepted contributions, `upholdDispute` marks dispute status as `Upheld` and adjusts rewards/reputation, but does not transition the contribution out of the active pipeline.

`releaseContributorReward` permanently reverts when dispute status is `Upheld`, and `pendingContributions` is never decremented in this path.

`completeProject` requires `pendingContributions == 0`, so the project can become permanently non-completable.

**Impact**:  
A single upheld dispute on an accepted contribution can block project completion and escrow refund forever.

**Proof of Concept**:
1. Contribution reaches `Accepted`.
2. Open dispute.
3. Resolve dispute as upheld (or escalate after resolution deadline).
4. `releaseContributorReward` now always reverts (`DisputeInProgress` due `Upheld`).
5. `pendingContributions` stays non-zero, so `completeProject` always reverts (`ProjectHasActivePipeline`).

**Recommendation**:  
Define a terminal post-upheld path for accepted contributions. For example:
- transition to `Rejected`,
- decrement `pendingContributions`,
- increment `submissionNonce`,
- recycle index for re-validation,
- or mark contribution fully finalized with explicit no-reward settlement.

Any path must ensure lifecycle progress toward `pendingContributions == 0`.

---

## [MEDIUM] Cancelling funded projects can strand escrow permanently

**Location**: `src/libraries/OriginationLib.sol` (`removeProject`), `src/libraries/DisputeLib.sol` (`upholdOriginatorReport`), `src/libraries/FinalizationLib.sol` (`refundEscrow`)

**Description**:  
Project cancellation paths set `ProjectStatus.Cancelled`, but escrow refund requires `ProjectStatus.Completed`. There is no cancellation-specific escrow exit path.

As a result, funded/cancelled projects can trap escrow indefinitely.

**Impact**:  
Originator funds can become irrecoverable if a project is removed/cancelled after funding.

**Proof of Concept**:
1. Originator funds a project (escrow > 0).
2. Operator calls `removeProject` (or originator report is upheld).
3. Project status is `Cancelled`.
4. `refundEscrow` reverts because project is not `Completed`.
5. No alternative withdrawal path exists.

**Recommendation**:  
Add a cancellation settlement path for escrow (policy-dependent):
- refund to originator,
- send to treasury,
- or split by governance decision.

Implement explicit logic and events for cancelled-project fund disposition.

---

## [LOW] Commit-hash encoding in implementation differs from interface guidance

**Location**: `src/interfaces/ISapienCore.sol` (`commitValidation` docs), `src/libraries/ValidationLib.sol` (`revealValidation`)

**Description**:  
Interface guidance says commit hash should be `keccak256(abi.encodePacked(score, salt))`, but implementation verifies a 34-byte packed payload (`uint16 score` + `bytes32 salt`) via assembly.

If integrators follow interface docs with a 32-byte `uint256 score`, reveals will fail.

**Impact**:  
Client/integration failures and confusing validator UX.

**Recommendation**:  
Make interface/spec and implementation consistent:
- either verify `abi.encodePacked(uint256 score, bytes32 salt)`,
- or explicitly document and enforce `uint16 score` packing everywhere.

---

## Notes

- PoC tests added for each finding in `test/findings/2026-02-23/`:
  - `POC_001_ValidationClaimExpirySlotLock.t.sol`
  - `POC_002_LateCommitAfterValidationClaimExpiry.t.sol`
  - `POC_003_UpheldDisputeDeadlock.t.sol`
  - `POC_004_CancelledProjectEscrowStranding.t.sol`
  - `POC_005_CommitHashEncodingMismatch.t.sol`
- Fix-expectation (TDD) suite added in `test/findings/2026-02-23/fixes/FIX_2026_02_23_ExpectedBehavior.t.sol`.
- Findings focus on exploitable state-transition and liveness failures, per `docs/skills/security-review-skill.md`, `docs/skills/lifecycle-testing-skill.md`, and `docs/skills/adversarial-testing-skill.md`.
- Existing known findings/tests were not treated as fixed unless behavior is enforced by current code paths.
