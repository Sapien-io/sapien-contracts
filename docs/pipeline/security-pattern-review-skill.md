Purpose: Find known vulnerability classes.

**v0.5 focus**: SapienCore (nonReentrant on value flows, libraries via DELEGATECALL), SapienVault (ENGINE_ROLE), ConsensusLib (pure math, no external calls). See `docs/security/AUDIT_SCOPE.md`, `src/`.

What it checks
	- Reentrancy (state update order, external calls to SapienVault and ERC-20 tokens)
	- Access control bypass
	- Missing onlyRole checks
	- Library DELEGATECALL safety (all libraries operate on SapienCore's ERC-7201 storage)
	- Flash-loan sensitivity (deposit -> lock -> commit -> reveal -> withdraw)
	- Incorrect msg.sender assumptions
	- ERC20 approval pitfalls (SafeERC20 usage)
	- Nonce-based re-validation state confusion

Inputs
	- Contract AST
	- Call graph
	- Modifier usage
	- External call sites

Output
	- Finding
	- Severity
	- Concrete exploit path (step-by-step)
	- Remediation suggestion
