Purpose: Catch “code is correct, economics are broken” bugs.

**v0.5 focus**: Reward rate snapshot at submission (anti-sandwich); adapter fees at fund/contribute/validate; phased finalization (no atomic multi-validator loop). See `docs/v0.5-contracs.md` §4.4, §4.9.

What it checks
	•	Sandwichable flows
	•	MEV extraction vectors
	•	Rounding bias
	•	Asymmetric incentives
	•	Griefing attacks
	•	Free options
	•	Time-based manipulation (TWAP abuse)
