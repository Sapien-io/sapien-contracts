Purpose: Identify waste and scaling issues.

**v0.5 focus**: `computeConsensus` loop over revealedValidators; `expireClaim` loop over claim.indices; reward/slash math. See `docs/v0.5-contracs.md` §7 Gas Comparison.

Checks
	•	Unnecessary SSTOREs
	•	Inefficient loops
	•	Storage vs memory misuse
	•	Packing opportunities
	•	Cold vs warm storage issues