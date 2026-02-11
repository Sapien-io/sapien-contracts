Purpose: Find known vulnerability classes.

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
