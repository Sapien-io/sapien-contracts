Purpose: Generate "human-unlikely" test scenarios.

**v0.5 examples**: Zero availableSlots; numberOfValidations = 1 (single validator); dispute bond = 0 (min 1 wei enforced); rejection overturn with insufficient escrow; originator report when originatorStakeRequirement = 0; tiered slashing at exact sigma boundaries (1.5, 2, 3, 5); forceSettleValidator edge timing; validation claim expiry vs commit deadline interaction.

Examples:
	- Zero liquidity
	- Extreme config bounds (max fee BPS, max deadlines)
	- Back-to-back calls in same block
	- Partial execution failure
	- Nonce confusion across re-validation cycles
	- Uninitialized state access
	- Single validator consensus (no standard deviation)
