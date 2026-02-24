Purpose: Catch "code is correct, economics are broken" bugs.

**v0.5 focus**: Reward rate snapshot at submission (anti-sandwich); adapter fees at fund/contribute/validate (OriginationLib, ContributionLib, ValidationLib); phased finalization -- computeConsensus, settleValidator, releaseContributorReward (no atomic multi-validator loop); dispute bond economics; tiered slashing incentive alignment. See `src/` and `docs/security/AUDIT_SCOPE.md`.

What it checks
	- Sandwichable flows (fundProject, claimToContribute, commitValidation)
	- MEV extraction vectors (front-running claims, transaction ordering)
	- Rounding bias (fee deductions, reward distribution, slashing)
	- Asymmetric incentives (dispute bond vs challenger reward)
	- Griefing attacks (dispute escalation, originator reports, ghost validators)
	- Free options (commit without reveal, claim without contribute)
	- Time-based manipulation (challenge period, force settle delay)
