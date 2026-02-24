# Lifecycle Findings (v0.5)

Date: 2026-02-23

This report summarizes lifecycle and liveness findings identified through
end-to-end and edge-case testing in `test/lifecycle/Lifecycle.t.sol`.

## Executive Summary

- Exhaustive lifecycle tests now cover happy paths and adversarial paths.
- Multiple high-impact liveness issues are reproducible today.
- Dedicated reproduction tests exist in `LifecycleKnownIssuesTest` and PoC files.

## Findings

## [HIGH] Validation claim expiry can lock validator slots

- **Flow**: Validation claim timeout and cleanup
- **Impact**: New validators can be blocked from claiming, consensus can stall, and contributions can remain pending indefinitely.
- **Reproduction tests**:
  - `test/lifecycle/Lifecycle.t.sol` -> `test_issue_validationClaimExpiryLocksValidatorSlots`
  - `test/findings/2026-02-23/POC_001_ValidationClaimExpirySlotLock.t.sol`
- **Recommendation**:
  - On `cancelExpiredValidationClaim`, release uncommitted reservations and decrement corresponding claim counters.

## [HIGH] Late commit allowed after validation claim expiry

- **Flow**: Commit-reveal timing
- **Impact**: A validator can claim early, wait for honest reveals, then commit/reveal after claim expiry (last-look advantage), weakening anti-herding guarantees.
- **Reproduction tests**:
  - `test/lifecycle/Lifecycle.t.sol` -> `test_issue_lateCommitAllowedAfterValidationClaimExpiry`
  - `test/findings/2026-02-23/POC_002_LateCommitAfterValidationClaimExpiry.t.sol`
- **Recommendation**:
  - In `commitValidation`, enforce active claim status and claim deadline checks.

## [HIGH] Upheld disputes can deadlock project completion

- **Flow**: Accepted contribution dispute path
- **Impact**: `releaseContributorReward` remains blocked and `pendingContributions` may never decrement, causing `completeProject` to revert indefinitely.
- **Reproduction tests**:
  - `test/lifecycle/Lifecycle.t.sol` -> `test_issue_upheldDisputeCanDeadlockProjectCompletion`
  - `test/findings/2026-02-23/POC_003_UpheldDisputeDeadlock.t.sol`
- **Recommendation**:
  - Add a terminal upheld-dispute state transition that allows lifecycle progress and decrements in-flight pipeline accounting.

## [MEDIUM] Cancelled projects can strand escrow

- **Flow**: Cancellation and refund
- **Impact**: Escrow remains inaccessible when project status is `Cancelled` because refund path requires `Completed`.
- **Reproduction tests**:
  - `test/lifecycle/Lifecycle.t.sol` -> `test_issue_cancelledProjectEscrowStranding`
  - `test/findings/2026-02-23/POC_004_CancelledProjectEscrowStranding.t.sol`
- **Recommendation**:
  - Add explicit escrow settlement policy/path for cancelled projects.

## [LOW] Commit-hash encoding mismatch (docs vs implementation)

- **Flow**: Validator integration / commit hash generation
- **Impact**: Integrations using `uint256` score packing can fail reveal verification.
- **Reproduction tests**:
  - `test/lifecycle/Lifecycle.t.sol` -> `test_issue_uint256CommitHashEncodingMismatch`
  - `test/findings/2026-02-23/POC_005_CommitHashEncodingMismatch.t.sol`
- **Recommendation**:
  - Align interface/docs/SDK helpers with onchain hash packing and score type.

## Additional Coverage Added

Exhaustive workflow tests were added for:

- Validation claim expiry (no-commit and partial-commit paths)
- Reveal failure and keeper recovery via `cancelExpiredCommitment`
- Reveal window expiry revert behavior
- Force-settle path after delay
- Batch commit/reveal multi-index workflow
- Full closure path (`releaseContributorReward` -> `completeProject` -> `refundEscrow`)

## Related Documents

- `docs/security/lifecycle-flow-issues.md`
- `docs/architecture/lifecycle.md` (optimization recommendations)
