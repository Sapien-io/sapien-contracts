# Solidity Security Review

Comprehensive security review skill for Solidity smart contracts in the `src/` folder (Sapien PoQ v0.5).

## Purpose

This skill guides a systematic security review of Solidity smart contracts. When active, the assistant will:

- Perform **function-by-function** security analysis
- Identify common vulnerability patterns and attack vectors
- Analyze access control, state management, and external interactions
- Track invariants, assumptions, and trust boundaries
- Generate a structured security report with findings

**Target**: All contracts in `src/` directory.

**Architecture**: Sapien PoQ v0.5 -- SapienCore + SapienVault + 7 libraries (OriginationLib, ContributionLib, ValidationLib, ConsensusLib, FinalizationLib, DisputeLib, ReputationLib).

---

## Review Methodology

### Phase 1: Architecture Understanding

Before hunting for vulnerabilities, build context:

1. **Contract Relationships**
   - SapienCore: AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable; delegates to 7 libraries via DELEGATECALL
   - SapienVault: ERC4626Upgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable
   - Libraries: operate on SapienCore's ERC-7201 namespaced storage
   - External dependency: SapienCore -> SapienVault (ENGINE_ROLE gated)

2. **State Variable Mapping**
   - ERC-7201 namespaced storage for both contracts
   - EngineStorage (SapienCore): projects, claims, indexRange, returnStack, contributions, validatorCommits, consensusReports, reputation, pendingRewards, projectEscrow, disputes, originatorReports, configurable deadlines
   - SapienVaultStorage: accounts mapping (contributorLock, validatorCapacity, inFlight)
   - State invariants that must hold across all operations

3. **Actor Identification**
   - Originators (create projects, fund reward pools)
   - Contributors (claim slots, submit work)
   - Validators (lock capacity, commit/reveal scores)
   - Admin (DEFAULT_ADMIN_ROLE: fees, deadlines, pause, upgrade)
   - Operator (OPERATOR_ROLE: resolve disputes/reports, remove projects)
   - Adapters (receive fees on origination, contribution, validation)
   - Treasury (receives protocol fees)
   - Keepers (permissionless: expiry, consensus, settlement, escalation)

4. **Entry Points**
   - Public/external functions on SapienCore
   - SapienVault: deposit, withdraw, mint, redeem (ERC-4626); stake operations (ENGINE_ROLE only)
   - Initializers on both contracts

---

### Phase 2: Vulnerability Analysis

For each contract, systematically check:

#### Access Control
- [ ] Function visibility (public vs external vs internal)
- [ ] ENGINE_ROLE: only SapienCore can call SapienVault stake ops
- [ ] OPERATOR_ROLE: resolveDispute, resolveOriginatorReport, removeProject
- [ ] DEFAULT_ADMIN_ROLE: fee/deadline config, pause, upgrade
- [ ] Upgradeability access control (UUPS _authorizeUpgrade)

#### Reentrancy
- [ ] External calls before state changes
- [ ] ReentrancyGuardUpgradeable on SapienCore
- [ ] Cross-function reentrancy via SapienVault callbacks (none expected)
- [ ] Read-only reentrancy (view functions)

#### Arithmetic
- [ ] Overflow/underflow (Solidity 0.8.x built-in checks)
- [ ] Division by zero (totalWeight, totalAccurateWeight in ConsensusLib)
- [ ] Precision loss in consensus calculations (1e18 PRECISION)
- [ ] Rounding direction in fee deductions and reward distribution
- [ ] Overflow protection in ConsensusLib variance computation

#### Input Validation
- [ ] Zero address checks (admin, vault, treasury)
- [ ] Zero amount checks (stake ops, fund amounts)
- [ ] Score bounds (0-10,000)
- [ ] Config bounds (fee caps, deadline caps, numberOfValidations)

#### State Management
- [ ] Initialization (_disableInitializers, initializer modifier)
- [ ] ERC-7201 storage slot collisions
- [ ] Nonce consistency (submissionNonce, consensusNonce)
- [ ] Event emission for state changes

#### External Interactions
- [ ] SafeERC20 for all ERC-20 transfers
- [ ] SapienVault calls (ENGINE_ROLE gated, trusted)
- [ ] Library DELEGATECALL safety

#### Gas and DoS
- [ ] Unbounded loops (bounded by numberOfValidations max 10, MAX_CLAIM_QUANTITY 20)
- [ ] Block gas limit issues
- [ ] Griefing vectors (dispute escalation, ghost validators)
- [ ] Failed transfer handling

#### Upgradeability
- [ ] ERC-7201 storage layout compatibility
- [ ] Initializer protection
- [ ] UUPS upgrade authorization
- [ ] Library upgrade path (new implementation required)

#### Protocol-Specific (ERC-4626)
- [ ] Share/asset calculation edge cases
- [ ] Inflation attack mitigation (_decimalsOffset = 3)
- [ ] Transfer guard (locked shares)
- [ ] Withdrawal guard (locked amounts excluded from maxRedeem/maxWithdraw)
- [ ] Paused state (all ERC-4626 operations return 0)

#### Dispute System
- [ ] Bond sufficiency and slashing
- [ ] Challenger reward calculation
- [ ] Auto-escalation timing
- [ ] Cross-nonce dispute isolation
- [ ] Originator report lifecycle

---

### Phase 3: Cross-Contract Analysis

After individual contract review:

1. **Call Flow Tracing**
   - Map SapienCore -> SapienVault calls (lock, unlock, slash, commit, release)
   - Map SapienCore -> ERC-20 token transfers
   - Verify no callbacks from SapienVault to SapienCore

2. **Invariant Verification**
   - projectEscrow >= sum(pendingRewards) per project
   - vault.totalAssets() >= sum(all user locks)
   - availableSlots + indices in pipeline = totalQuantity per project

3. **Attack Scenario Modeling**
   - Flash loan stake inflation
   - Consensus collusion (51%+ validators)
   - Dispute escalation griefing
   - Ghost validator DoS
   - Nonce confusion across re-validation cycles

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

- [ ] SapienCore: all lifecycle + dispute + admin functions
- [ ] SapienVault: all lock/unlock/slash + ERC-4626 overrides + transfer/withdrawal guards
- [ ] All 7 libraries analyzed
- [ ] Cross-contract interactions mapped (SapienCore <-> SapienVault)
- [ ] Upgradeability safety verified (ERC-7201, UUPS)
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

- **Slither** -- `slither src/`
- **Foundry tests** -- `forge test`
- **Fuzz tests** -- Review `test/` coverage
- **Solhint** -- `.solhint.json` if present
