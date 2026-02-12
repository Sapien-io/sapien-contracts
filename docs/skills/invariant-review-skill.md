Purpose: Ensure the protocol never enters an invalid state.

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