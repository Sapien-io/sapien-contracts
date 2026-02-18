Purpose: Ensure the protocol never enters an invalid state.

**v0.5 invariants**: `vault.totalAssets() >= sum(contributorLock + validatorCapacity + inFlight)`; `projectEscrow >= sum(pendingRewards)` per project; `availableSlots + indices in pipeline = totalQuantity`. See `docs/v0.5-contracs.md`, `test/lifecycle/Lifecycle.t.sol`.

What it checks
	•	Conservation of value
	•	Supply invariants
	•	Balance monotonicity where expected
	•	Lock/unlock symmetry
	•	Mint/burn correctness
	•	Cross-contract invariant coherence

Example invariant:
 
    totalAssets >= totalSupply

Output
	•	Explicit invariants (human-readable)
	•	Functions that break or preserve them
	•	Missing invariant enforcement