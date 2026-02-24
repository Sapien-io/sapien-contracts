# Lifecycle Flow Issues (v0.5)

Date: 2026-02-23

This document tracked lifecycle and liveness issues found while expanding
`test/lifecycle/Lifecycle.t.sol` with end-to-end edge-path coverage.

Status update: all five issues below are now fixed in the current codebase and
covered by regression tests.

## Scope and Evidence

- Contracts reviewed: `SapienCore`, `ContributionLib`, `ValidationLib`, `DisputeLib`, `FinalizationLib`.
- Reproduction tests:
  - `LifecycleKnownIssuesTest` in `test/lifecycle/Lifecycle.t.sol`
  - Existing PoCs in `test/findings/2026-02-23/`

## Fixed Issues

### 1) Validation claim expiry slot lock

- Severity: High
- Flow: Validation claim expiration
- Reproduction: `test_issue_validationClaimExpiryLocksValidatorSlots`
- Impact:
  - Expired validation claims do not free claim occupancy for new validators.
  - Contributions can remain pending with no path to fresh validators.
  - Consensus and downstream completion can be blocked.
- Fix:
  - `cancelExpiredValidationClaim` now releases uncommitted reservations and
    decrements `claimCount` for released slots.
- Validation:
  - `testFIX_expiredValidationClaimsReleaseSlots`
  - `test_issue_validationClaimExpiryLocksValidatorSlots` (now verifies fixed behavior)

### 2) Late commit after validation claim expiry

- Severity: High
- Flow: Commit-reveal timing
- Reproduction: `test_issue_lateCommitAllowedAfterValidationClaimExpiry`
- Impact:
  - Validators can reserve early, wait for others to reveal, then commit/reveal
    after their validation claim has already expired.
  - This weakens anti-herding guarantees and gives a strategic last-look edge.
- Fix:
  - `commitValidation` now requires the associated validation claim to be
    `Active` and within deadline.
- Validation:
  - `testFIX_cannotCommitAfterValidationClaimExpiry`
  - `test_issue_lateCommitAllowedAfterValidationClaimExpiry` (now verifies fixed behavior)

### 3) Upheld disputes deadlocking completion

- Severity: High
- Flow: Accepted contribution dispute path
- Reproduction: `test_issue_upheldDisputeCanDeadlockProjectCompletion`
- Impact:
  - `releaseContributorReward` remains blocked after upheld dispute.
  - `pendingContributions` can stay non-zero.
  - `completeProject` can remain permanently blocked.
- Fix:
  - Upheld disputes on accepted contributions now close pipeline accounting by
    decrementing `pendingContributions`.
- Validation:
  - `testFIX_upheldDisputeOnAcceptedContributionDoesNotDeadlockCompletion`
  - `test_issue_upheldDisputeCanDeadlockProjectCompletion` (now verifies fixed behavior)

### 4) Cancelled-project escrow stranding

- Severity: Medium
- Flow: Project cancellation and escrow settlement
- Reproduction: `test_issue_cancelledProjectEscrowStranding`
- Impact:
  - Cancelled projects do not satisfy `refundEscrow` preconditions.
  - Escrow can remain inaccessible after cancellation.
- Fix:
  - `refundEscrow` now allows `Cancelled` projects (while retaining delay for
    `Completed` projects).
- Validation:
  - `testFIX_cancelledFundedProjectCanRefundEscrow`
  - `test_issue_cancelledProjectEscrowStranding` (now verifies fixed behavior)

### 5) Commit-hash encoding mismatch

- Severity: Low
- Flow: Commit hash integration
- Reproduction: `test_issue_uint256CommitHashEncodingMismatch`
- Impact:
  - Integrations using `uint256` score packing can fail reveal verification.
  - Validator UX and client compatibility are degraded.
- Fix:
  - Reveal verification now uses `keccak256(abi.encodePacked(score, salt))`
    with canonical `uint256` score packing.
- Validation:
  - `testFIX_uint256PackedCommitHashRevealsSuccessfully`
  - `test_issue_uint256CommitHashEncodingMismatch` (now verifies fixed behavior)

## Verification Summary

- `forge test --match-path test/findings/2026-02-23/fixes/FIX_2026_02_23_ExpectedBehavior.t.sol -vv`
  - Result: 5 passed, 0 failed
- `forge test --match-path test/lifecycle/Lifecycle.t.sol -vv`
  - Result: 76 passed, 0 failed
