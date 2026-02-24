Purpose: Identify waste and scaling issues.

**v0.5 focus**: `computeConsensus` loop over revealedValidators (bounded by numberOfValidations, max 10); `expireClaim` loop over claim indices (bounded by MAX_CLAIM_QUANTITY, max 20); reward/slash math in FinalizationLib; batch operations in ValidationLib and ContributionLib. See `src/` and `docs/security/AUDIT_SCOPE.md`.

Checks
	- Unnecessary SSTOREs
	- Inefficient loops
	- Storage vs memory misuse
	- Packing opportunities (e.g. EngineStorage struct ordering)
	- Cold vs warm storage issues
	- ERC-7201 storage access patterns
