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

**Architecture Reference**: `docs/v0.5-contracs.md` — QualityEngine, StakeVault, ConsensusLib, Types, interfaces.

---

## v0.5 Contract Topology

| Contract | Role | Key Dependencies |
|----------|------|-----------------|
| `QualityEngine` | Core protocol (projects, claims, contributions, validations, consensus, reputation, rewards, disputes) | IStakeVault, ConsensusLib, Types |
| `StakeVault` | ERC-4626 vault with typed locks (contributor, validator, in-flight) | IERC20, StakeAccount |
| `ConsensusLib` | Pure library for weighted average, stddev, outlier detection, tiered slash | ValidationInput, ConsensusResult |

**Trust boundary**: QualityEngine holds ENGINE_ROLE on StakeVault; Engine calls vault for stake ops only.

---

## Review Methodology

### Phase 1: Architecture Understanding

Before hunting for vulnerabilities, build context:

1. **Contract Relationships**
   - QualityEngine: AccessControl, Pausable, ReentrancyGuard, UUPS
   - StakeVault: ERC4626Upgradeable, AccessControl, Pausable, UUPS
   - ConsensusLib: internal pure functions, delegatecall from Engine

2. **State Variable Mapping**
   - ERC-7201 namespaced storage: `sapien.storage.QualityEngine`, `sapien.storage.StakeVault`
   - EngineStorage: projects, claims, indexStates, contributions, validation state, consensus reports, reputation, rewards, disputes
   - StakeVaultStorage: accounts (contributorLock, validatorCapacity, inFlight)

3. **Actor Identification**
   - Originator, Contributor, Validator, Admin, Operator
   - Adapters (origination, contribution, validation) — receive fees
   - Treasury — protocol fees
   - Keeper — permissionless: expireClaim, computeConsensus, cancelExpiredCommitment, escalateDispute

4. **Entry Points**
   - Public/external: createProject, fundProject, claimToContribute, contribute, expireClaim, setValidatorCapacity, commitValidation, revealValidation, computeConsensus, settleValidator, releaseContributorReward, claimReward, openDispute, resolveDispute, escalateDispute, reportOriginator, resolveOriginatorReport, escalateOriginatorReport, cancelExpiredCommitment
   - Admin: setProtocolFee, setOriginationFee, setContributionFee, setValidationFee, setDecayRate, setDisputeBondBps, setOriginatorStakeRequirement, setOriginatorReportBondBps, setConsensusAlgorithm, setTreasury, pause, unpause

---

### Phase 2: Vulnerability Analysis

For each contract, systematically check:

#### Access Control
- [ ] ENGINE_ROLE: only Engine can call vault stake ops
- [ ] OPERATOR_ROLE: resolveDispute, resolveOriginatorReport
- [ ] DEFAULT_ADMIN_ROLE: fee config, pause, upgrade
- [ ] No tx.origin (ERC-4337 Smart Account native)

#### Reentrancy
- [ ] nonReentrant on fundProject, claimToContribute, contribute, expireClaim, commitValidation, revealValidation, computeConsensus, settleValidator, releaseContributorReward, claimReward, openDispute, resolveDispute, escalateDispute, reportOriginator, resolveOriginatorReport, escalateOriginatorReport, cancelExpiredCommitment
- [ ] External calls: vault (trusted), token transfer (SafeERC20), treasury/adapter

#### Arithmetic
- [ ] Overflow/underflow (Solidity 0.8.x)
- [ ] Division by zero (totalWeight, totalAccurateWeight)
- [ ] Precision: ConsensusLib PRECISION (1e18), BPS (10000)
- [ ] Rounding: reward distribution, fee deductions

#### Input Validation
- [ ] Zero address: admin, vault, treasury, consensusAlgorithm
- [ ] Zero amount: stake ops, fund amounts
- [ ] Score bounds: 0–10000
- [ ] Config bounds: consensusThreshold, validatorRewardBps

#### State Management
- [ ] Initialization: _disableInitializers, initializer modifier
- [ ] Storage: ERC-7201 namespaces avoid collision
- [ ] Nonce: submissionNonce invalidates stale validation data on rejection
- [ ] Event emission for state changes

#### External Interactions
- [ ] SafeERC20 for all token transfers
- [ ] ConsensusLib: internal delegatecall, no external calls during consensus
- [ ] IConsensusAlgorithm: staticcall target (pluggable, currently unused in src)

#### Gas & DoS
- [ ] Loops: revealedValidators length bounded by numberOfValidations
- [ ] Index stack: O(1) push/pop
- [ ] No unbounded iteration over all users

#### Upgradeability
- [ ] UUPS: _authorizeUpgrade onlyRole(DEFAULT_ADMIN_ROLE)
- [ ] Storage layout: ERC-7201 per contract
- [ ] No __gap (namespaced storage isolates)

#### Protocol-Specific
- [ ] ERC-4626: StakeVault _decimalsOffset (inflation attack mitigation)
- [ ] Commit-reveal: keccak256(score, salt), committedStakes stored separately
- [ ] Dispute bond: sufficient escrow for overturned rejections
- [ ] Originator stake: slash path when report upheld

---

### Phase 3: Cross-Contract Analysis

1. **Call Flow Tracing**
   - Engine → Vault: lockContributor, unlockContributor, slashContributor, lockValidatorCapacity, unlockValidatorCapacity, commitStake, releaseCommit, slashValidator
   - Engine → Token: transferFrom (fund), transfer (claimReward, treasury, adapter)
   - No Engine ← external callback

2. **Invariant Verification**
   - projectEscrow >= sum(pendingRewards for that project)
   - vault.totalAssets() >= sum(user locks)
   - availableSlots + indices in claims/submitted = totalQuantity per project

3. **Attack Scenario Modeling**
   - Flash loan stake inflation
   - Consensus collusion (51%+ validators)
   - Dispute escalation griefing
   - Originator report escalation

---

## Output Format

### Finding Template

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

- [ ] QualityEngine: all lifecycle + dispute + admin functions
- [ ] StakeVault: all lock/unlock/slash + ERC-4626 overrides
- [ ] ConsensusLib: outlier tiers, slash computation
- [ ] Cross-contract: Engine ↔ Vault trust boundary
- [ ] Upgradeability: ERC-7201 storage safety
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

- **Slither** — `slither src/`
- **Foundry tests** — `forge test`
- **Fuzz tests** — Review `test/` coverage
- **Solhint** — `.solhint.json` if present
