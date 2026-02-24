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

**Architecture Reference**: Sapien PoQ v0.5 -- SapienCore, SapienVault, 7 libraries (OriginationLib, ContributionLib, ValidationLib, ConsensusLib, FinalizationLib, DisputeLib, ReputationLib), Types.sol, Constants.sol, interfaces.

---

## v0.5 Contract Topology

| Contract/Library | Role | Key Dependencies |
|------------------|------|-----------------|
| `SapienCore` | Core protocol (projects, claims, contributions, validations, consensus, reputation, rewards, disputes) | ISapienVault, all 7 libraries via DELEGATECALL |
| `SapienVault` | ERC-4626 vault with typed locks (contributor, validator capacity, in-flight) | IERC20, StakeAccount |
| `OriginationLib` | Project creation, funding, removal | EngineStorage, ISapienVault |
| `ContributionLib` | Claim-to-contribute, submission, expiry | EngineStorage, ISapienVault |
| `ValidationLib` | Commit-reveal lifecycle, consensus computation | EngineStorage, ISapienVault, ConsensusLib |
| `ConsensusLib` | Pure math: sqrt(stake) x reputation weighting, outlier detection, tiered slashing | ValidationInput, ConsensusResult |
| `FinalizationLib` | Validator settlement, reward release, escrow management | EngineStorage, ISapienVault, ReputationLib |
| `DisputeLib` | Dispute bonds, originator reports, escalation | EngineStorage, ISapienVault, ReputationLib |
| `ReputationLib` | Per-role reputation scoring with time-based decay | EngineStorage, Constants |

**Trust boundary**: SapienCore holds ENGINE_ROLE on SapienVault; Core calls Vault for stake ops only. All libraries run via DELEGATECALL in Core's storage context.

---

## Review Methodology

### Phase 1: Architecture Understanding

Before hunting for vulnerabilities, build context:

1. **Contract Relationships**
   - SapienCore: AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable
   - SapienVault: ERC4626Upgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable
   - Libraries: DELEGATECALL from SapienCore, operate on EngineStorage via ERC-7201

2. **State Variable Mapping**
   - ERC-7201 namespaced storage: `sapien.storage.SapienCore`, `sapien.storage.StakeVault`
   - EngineStorage: projects, claims, indexRange, returnStack, contributions, validatorCommits, revealedValidators, validationCounters, consensusReports, validatorConsensus, reputation, pendingRewards, projectEscrow, disputes, originatorReports, originatorLockedStake, pendingContributions, configurable deadlines, validation claims
   - SapienVaultStorage: accounts (contributorLock, validatorCapacity, inFlight)

3. **Actor Identification**
   - Originator, Contributor, Validator, Admin, Operator
   - Adapters (origination, contribution, validation) -- receive fees
   - Treasury -- protocol fees
   - Keeper -- permissionless: expireClaim, computeConsensus, cancelExpiredCommitment, cancelExpiredValidationClaim, escalateDispute, escalateOriginatorReport, forceSettleValidator, completeProject, refundEscrow

4. **Entry Points**
   - Public/external: createProject, fundProject, claimToContribute, contribute, batchContribute, expireClaim, lockValidatorCapacity, unlockValidatorCapacity, claimToValidate, commitValidation, batchCommitValidations, revealValidation, batchRevealValidations, computeConsensus, settleValidator, forceSettleValidator, releaseContributorReward, claimReward, openDispute, resolveDispute, escalateDispute, reportOriginator, resolveOriginatorReport, escalateOriginatorReport, cancelExpiredCommitment, cancelExpiredValidationClaim, completeProject, refundEscrow
   - Admin: setProtocolFee, setOriginationFee, setContributionFee, setValidationFee, setDecayRate, setDisputeBondBps, setOriginatorStakeRequirement, setOriginatorReportBondBps, setMinValidationStake, setTreasury, setMinClaimAmount, setClaimCooldown, setClaimDeadline, setChallengePeriod, setCommitDeadline, setRevealDeadline, setForceSettleDelay, pause, unpause
   - Operator: resolveDispute, resolveOriginatorReport, removeProject

---

### Phase 2: Vulnerability Analysis

For each contract, systematically check:

#### Access Control
- [ ] ENGINE_ROLE: only SapienCore can call SapienVault stake ops
- [ ] OPERATOR_ROLE: resolveDispute, resolveOriginatorReport, removeProject
- [ ] DEFAULT_ADMIN_ROLE: fee/deadline config, pause, upgrade
- [ ] No tx.origin usage

#### Reentrancy
- [ ] nonReentrant on fundProject, claimToContribute, expireClaim, commitValidation, batchCommitValidations, revealValidation, batchRevealValidations, computeConsensus, settleValidator, forceSettleValidator, releaseContributorReward, claimReward, openDispute, resolveDispute, escalateDispute, reportOriginator, resolveOriginatorReport, escalateOriginatorReport, cancelExpiredCommitment, cancelExpiredValidationClaim, completeProject, refundEscrow, claimToValidate, removeProject
- [ ] External calls: SapienVault (trusted), token transfer (SafeERC20), treasury/adapter

#### Arithmetic
- [ ] Overflow/underflow (Solidity 0.8.x)
- [ ] Division by zero (totalWeight, totalAccurateWeight)
- [ ] Precision: ConsensusLib PRECISION (1e18), BPS (10,000)
- [ ] Rounding: reward distribution, fee deductions
- [ ] Overflow protection in ConsensusLib variance calculation

#### Input Validation
- [ ] Zero address: admin, vault, treasury
- [ ] Zero amount: stake ops, fund amounts
- [ ] Score bounds: 0-10,000
- [ ] Config bounds: consensusThreshold, validatorRewardBps, fee caps, deadline caps

#### State Management
- [ ] Initialization: _disableInitializers, initializer modifier
- [ ] Storage: ERC-7201 namespaces avoid collision
- [ ] Nonce: submissionNonce invalidates stale validation data on rejection
- [ ] Consensus nonce: disputes keyed by nonce to prevent cross-nonce poisoning
- [ ] Event emission for state changes

#### External Interactions
- [ ] SafeERC20 for all token transfers
- [ ] Libraries: DELEGATECALL, operate on Core's storage -- no external calls during consensus
- [ ] SapienVault: ENGINE_ROLE gated

#### Gas and DoS
- [ ] Loops: revealedValidators length bounded by numberOfValidations (max 10)
- [ ] Index stack: O(1) push/pop
- [ ] Batch operations: bounded by MAX_CLAIM_QUANTITY (20)
- [ ] No unbounded iteration over all users

#### Upgradeability
- [ ] UUPS: _authorizeUpgrade onlyRole(DEFAULT_ADMIN_ROLE)
- [ ] Storage layout: ERC-7201 per contract
- [ ] No __gap needed (namespaced storage isolates)
- [ ] Library upgrades: libraries linked at deploy time; new library = new SapienCore implementation

#### Protocol-Specific
- [ ] ERC-4626: SapienVault _decimalsOffset = 3 (inflation attack mitigation)
- [ ] Commit-reveal: keccak256(score, salt); committed stake stored in ValidatorCommit.stakedAmount
- [ ] Tiered slashing: 1.5sigma->10%, 2sigma->25%, 3sigma->50%, 5sigma->100%
- [ ] Dispute bond: from challenger's contributor lock; rewards from project escrow
- [ ] Originator stake: slash path when report upheld
- [ ] Transfer guard: _update override blocks share transfers breaching locked amounts
- [ ] Withdrawal guard: maxRedeem/maxWithdraw exclude locked amounts
- [ ] Paused vault: maxDeposit/maxMint/maxRedeem/maxWithdraw return 0

---

### Phase 3: Cross-Contract Analysis

1. **Call Flow Tracing**
   - SapienCore -> SapienVault: lockContributor, unlockContributor, slashContributor, slashAndUnlockContributor, lockValidatorCapacity, unlockValidatorCapacity, commitStake, releaseCommit, slashValidator
   - SapienCore -> Token: transferFrom (fund), transfer (claimReward, treasury, adapter)
   - No SapienCore <- external callback

2. **Invariant Verification**
   - projectEscrow >= sum(pendingRewards for that project)
   - vault.totalAssets() >= sum(user locks across all accounts)
   - availableSlots + indices in claims/submitted = totalQuantity per project
   - pendingContributions tracks in-flight contribution count per project

3. **Attack Scenario Modeling**
   - Flash loan stake inflation
   - Consensus collusion (51%+ validators)
   - Dispute escalation griefing
   - Originator report escalation
   - Ghost validator DoS (commit without reveal)
   - Nonce confusion across re-validation cycles

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

- [ ] SapienCore: all lifecycle + dispute + admin functions
- [ ] SapienVault: all lock/unlock/slash + ERC-4626 overrides + transfer/withdrawal guards
- [ ] All 7 libraries: OriginationLib, ContributionLib, ValidationLib, ConsensusLib, FinalizationLib, DisputeLib, ReputationLib
- [ ] ConsensusLib: outlier tiers, slash computation, overflow protection
- [ ] Cross-contract: SapienCore <-> SapienVault trust boundary
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

- **Slither** -- `slither src/`
- **Foundry tests** -- `forge test`
- **Fuzz tests** -- Review `test/` coverage
- **Solhint** -- `.solhint.json` if present
