Purpose: Ensure the protocol never enters an invalid state.

**v0.5 invariants**: `vault.totalAssets() >= sum(contributorLock + validatorCapacity + inFlight)` per user; `projectEscrow >= sum(pendingRewards)` per project; `availableSlots + indices in pipeline = totalQuantity` per project; `pendingContributions` tracks in-flight count accurately. See `src/` and `docs/security/AUDIT_SCOPE.md`.

What it checks
	- Conservation of value (escrow, stake, rewards)
	- Supply invariants (vault shares vs assets)
	- Balance monotonicity where expected
	- Lock/unlock symmetry (contributorLock, validatorCapacity, inFlight)
	- Mint/burn correctness (SapienVault slashing)
	- Cross-contract invariant coherence (SapienCore <-> SapienVault)
	- Nonce consistency (submissionNonce, consensusNonce, dispute nonce)

Example invariant:

    vault.totalAssets() >= sum(all user locks)

Output
	- Explicit invariants (human-readable)
	- Functions that break or preserve them
	- Missing invariant enforcement
