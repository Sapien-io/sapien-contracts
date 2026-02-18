Purpose: Find known vulnerability classes.

**v0.5 focus**: QualityEngine (nonReentrant on value flows), StakeVault (ENGINE_ROLE), ConsensusLib (delegatecall, no external calls). See `docs/v0.5-contracs.md`, `src/`.

What it checks
	•	Reentrancy (state update order, external calls)
	•	Access control bypass
	•	Missing onlyOwner / role checks
	•	Unsafe delegatecall
	•	Oracle manipulation vectors
	•	Flash-loan sensitivity
	•	Incorrect msg.sender assumptions
	•	ERC20 approval pitfalls

Inputs
	•	Contract AST
	•	Call graph
	•	Modifier usage
	•	External call sites

Output
	•	Finding
	•	Severity
	•	Concrete exploit path (step-by-step)
	•	Remediation suggestion
