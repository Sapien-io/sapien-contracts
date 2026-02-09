# Solidity Security Review

Comprehensive security review skill for Solidity smart contracts in the `src/` folder.

## Purpose

This skill guides a systematic security review of Solidity smart contracts. When active, the assistant will:

- Perform **function-by-function** security analysis
- Identify common vulnerability patterns and attack vectors
- Analyze access control, state management, and external interactions
- Track invariants, assumptions, and trust boundaries
- Generate a structured security report with findings

**Target**: All contracts in `src/` directory.

---

## Review Methodology

### Phase 1: Architecture Understanding

Before hunting for vulnerabilities, build context:

1. **Contract Relationships**
   - Inheritance hierarchy (Chamber inherits Board, Wallet, ERC4626Upgradeable)
   - External dependencies (OpenZeppelin contracts)
   - Inter-contract calls and trust assumptions

2. **State Variable Mapping**
   - Storage layout for upgradeable contracts
   - Access patterns (who reads/writes each variable)
   - State invariants that must hold

3. **Actor Identification**
   - Users (depositors, delegators)
   - Board members (NFT holders with delegated power)
   - Owners/Admins (upgrade authority)
   - External contracts (ERC20, ERC721, ProxyAdmin)

4. **Entry Points**
   - Public/external functions
   - Fallback/receive functions
   - Initializers

---

### Phase 2: Vulnerability Analysis

For each contract, systematically check:

#### Access Control
- [ ] Function visibility (public vs external vs internal)
- [ ] Modifier usage and correctness
- [ ] Role-based access control implementation
- [ ] Owner/admin privilege scope
- [ ] Upgradeability access control

#### Reentrancy
- [ ] External calls before state changes
- [ ] ReentrancyGuard usage
- [ ] Cross-function reentrancy
- [ ] Read-only reentrancy (view functions)

#### Arithmetic
- [ ] Overflow/underflow (Solidity 0.8.x built-in checks)
- [ ] Division by zero
- [ ] Precision loss in calculations
- [ ] Rounding direction (favor protocol or user)

#### Input Validation
- [ ] Zero address checks
- [ ] Zero amount checks
- [ ] Array bounds and length limits
- [ ] Untrusted calldata handling

#### State Management
- [ ] Initialization (initializer modifier, _disableInitializers)
- [ ] Storage slot collisions in upgrades
- [ ] State consistency across functions
- [ ] Event emission for state changes

#### External Interactions
- [ ] Return value handling (ERC20 transfer)
- [ ] Low-level call safety (.call, .delegatecall)
- [ ] Callback attack vectors
- [ ] Oracle/price manipulation

#### Gas & DoS
- [ ] Unbounded loops
- [ ] Block gas limit issues
- [ ] Griefing vectors
- [ ] Failed transfer handling

#### Upgradeability
- [ ] Storage layout compatibility
- [ ] Initializer protection
- [ ] Implementation slot security
- [ ] Upgrade authorization

#### Protocol-Specific (ERC4626)
- [ ] Share/asset calculation edge cases
- [ ] Donation attacks
- [ ] First depositor front-running
- [ ] Vault inflation attacks

#### Governance-Specific
- [ ] Vote manipulation
- [ ] Delegation edge cases
- [ ] Quorum/threshold bypasses
- [ ] Flash loan governance attacks

---

### Phase 3: Cross-Contract Analysis

After individual contract review:

1. **Call Flow Tracing**
   - Map all external calls between contracts
   - Identify assumption mismatches
   - Check trust boundary violations

2. **Invariant Verification**
   - Global state invariants
   - Balance consistency (shares vs assets)
   - Delegation totals match individual delegations

3. **Attack Scenario Modeling**
   - Compose multiple functions for attacks
   - Consider malicious actors at each role
   - Time-based attack vectors (front-running, sandwich)

---

## Output Format

### Finding Template

For each finding, document:

```markdown
## [SEVERITY] Title

**Location**: `Contract.sol:function():line`

**Description**: Clear explanation of the vulnerability

**Impact**: What can an attacker achieve? What's at risk?

**Proof of Concept**: Step-by-step attack scenario or code

**Recommendation**: Specific fix with code example
```

### Severity Levels

| Severity | Criteria |
|----------|----------|
| **CRITICAL** | Direct loss of funds, contract takeover, upgrade hijack |
| **HIGH** | Significant fund loss, governance manipulation, DoS of critical functions |
| **MEDIUM** | Limited fund loss, privilege escalation, state corruption |
| **LOW** | Minor issues, gas inefficiencies, code quality |
| **INFORMATIONAL** | Best practices, documentation, optimization suggestions |

---

## Review Checklist

Before concluding the review:

- [ ] All contracts in `src/` analyzed
- [ ] All public/external functions reviewed
- [ ] Cross-contract interactions mapped
- [ ] Upgradeability safety verified
- [ ] Known attack patterns checked
- [ ] Findings documented with severity
- [ ] Recommendations provided for each finding

---

## Anti-Hallucination Rules

| Rationalization | Why It's Wrong | Required Action |
|-----------------|----------------|-----------------|
| "This looks fine" | Surface-level review misses bugs | Trace execution paths completely |
| "OpenZeppelin is safe" | Integration bugs exist | Verify correct usage and inheritance |
| "Solidity 0.8.x handles overflows" | Casting and unchecked blocks exist | Check all arithmetic operations |
| "It's upgradeable so it can be fixed" | Exploits happen before upgrades | Treat current code as final |
| "No one would do that" | Attackers are creative | Assume adversarial behavior |
| "Gas costs prevent attacks" | Flash loans eliminate capital requirements | Consider economic attacks |

---

## Execution

When invoked, perform the review in this order:

1. **Read all source files** in `src/`
2. **Build architecture understanding** (Phase 1)
3. **Analyze each contract** systematically (Phase 2)
4. **Cross-contract analysis** (Phase 3)
5. **Generate findings report** with severity and recommendations
6. **Summarize** overall security posture and priority fixes

---

## Related Tools

Consider using in conjunction with:
- **Slither** - Static analysis (`slither src/`)
- **Foundry tests** - `forge test`
- **Solhint** - Linting (`.solhint.json` exists)
- **Fuzz tests** - Review `test/fuzz/` coverage
