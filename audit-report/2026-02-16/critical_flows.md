# Sapien PoQ v0.5 — Critical User Flows

## 1. Project Setup Flow

**Actors**: Originator (via Smart Account + session key)

**Preconditions**:
- Originator holds sufficient reward tokens
- Originator has deposited stake in vault (if originatorStakeRequirement > 0)

**Critical Steps**:
1. `createProject(projectId, config)` — Validates config, stores Project struct
2. `fundProject(projectId, amount, quantity, adapter)` — Transfers tokens, deducts fees, initializes indices
3. **Security Checks**: Fee calculations, token transfer success, index stack initialization

**Failure Points**:
- Fee-on-transfer tokens cause accounting errors
- Insufficient originator stake for requirement
- Invalid project configuration parameters

**Protection Requirements**:
- Atomic fee deduction and escrow credit
- Proper index allocation (no duplicates, no gaps)
- Adapter fee crediting to correct address

## 2. Claim & Contribute Flow

**Actors**: Contributor (via Smart Account + session key)

**Preconditions**:
- Active funded project
- Contributor has sufficient stake for minStakeToClaim * quantity
- Contributor meets skill/reputation requirements

**Critical Steps**:
1. `claimToContribute(projectId, quantity, adapter)` — Reserves indices, locks stake, records adapter
2. `contribute(claimId, index, submissionHash)` — Submits work for specific index
3. **Security Checks**: Index ownership, deadline compliance, stake availability

**Failure Points**:
- Race conditions in index allocation
- Contributor stake locking failures
- Expired claims not properly cleaned up

**Protection Requirements**:
- Exclusive index assignment (deterministic, no conflicts)
- Atomic stake locking with claim creation
- Proper expiry handling with index reclamation

## 3. Validation Commit-Reveal Flow

**Actors**: Validator (commit via session key, reveal via passkey)

**Preconditions**:
- Contribution submitted and pending
- Validator has set capacity and meets requirements
- Within validation windows

**Critical Steps**:
1. `setValidatorCapacity(amount)` — Locks stake for validation capacity
2. `commitValidation(projectId, index, commitHash, stakeAmount)` — Blind commitment with stake
3. `revealValidation(projectId, index, score, salt)` — Reveals score, releases stake
4. **Security Checks**: Commit hash verification, stake amount validation, window timing

**Failure Points**:
- Server sees scores during commit (breaks commit-reveal)
- Zero-stake validations (free manipulation)
- Ghost validators (commit but don't reveal)
- bytes32(0) hash bypasses duplicate protection

**Protection Requirements**:
- Session key scoping (server cannot access commit/reveal)
- Minimum stake enforcement
- Proper nonce isolation for re-submissions
- Duplicate commit prevention

## 4. Consensus Computation Flow

**Actors**: Anyone (permissionless keeper, typically server)

**Preconditions**:
- Sufficient reveals collected (revealCount >= numberOfValidations)
- Within appropriate timing windows
- Not already computed for current nonce

**Critical Steps**:
1. `computeConsensus(projectId, index)` — Calls ConsensusLib, stores results
2. **ConsensusLib.calculate()**: Weighted average, outlier detection, slash amounts
3. **Decision Logic**: Accept/reject based on consensusThreshold, update reputation
4. **Security Checks**: Sufficient participation, proper weight calculations, outlier detection

**Failure Points**:
- ConsensusLib produces incorrect results
- Storage collisions across nonces
- Reputation updates fail or overflow

**Protection Requirements**:
- Consensus algorithm correctness
- Proper nonce keying
- Atomic state transitions
- Reputation bounds enforcement

## 5. Validator Settlement Flow

**Actors**: Validator (permissionless, incentivized)

**Preconditions**:
- Consensus computed for current nonce
- Validator participated and not already settled
- Within settlement window

**Critical Steps**:
1. `settleValidator(projectId, index)` — Claims outcome, handles slashing/rewards
2. **If outlier**: Slash stake via vault, negative reputation update
3. **If accurate**: Calculate reward, deduct adapter fee, credit pendingRewards
4. **Security Checks**: Settlement state, reward calculations, stake availability

**Failure Points**:
- Stale nonce data causes incorrect settlement
- Escrow insolvency (validator rewards not properly accounted)
- Adapter fee miscalculation
- Share transfer bypass of locks

**Protection Requirements**:
- Nonce-keyed settlement tracking
- Proper escrow accounting (validator rewards carved from total)
- Atomic slashing operations
- Adapter fee deduction from escrow

## 6. Contributor Reward Release Flow

**Actors**: Contributor (permissionless after challenge period)

**Preconditions**:
- Consensus reached (accepted contribution)
- Challenge period elapsed
- Not already released

**Critical Steps**:
1. `releaseContributorReward(projectId, index)` — Credits reward to pendingRewards
2. **Fee Deduction**: Adapter fee deducted, credited to adapter
3. **Security Checks**: Challenge elapsed, not already released, escrow sufficiency

**Failure Points**:
- Premature release (during challenge)
- Double release
- Escrow underflow
- Adapter fee miscalculation

**Protection Requirements**:
- Challenge period enforcement
- Single-release guarantee
- Proper fee waterfall (adapter → contributor)
- Escrow conservation

## 7. Reward Claiming Flow

**Actors**: Any participant (universal claim function)

**Preconditions**:
- Positive balance in pendingRewards[caller][token]

**Critical Steps**:
1. `claimReward(token)` — Transfers tokens, zeros balance
2. **Security Checks**: Balance verification, transfer success

**Failure Points**:
- Reentrancy during transfer
- Blacklisted recipient addresses
- Fee-on-transfer token issues

**Protection Requirements**:
- Reentrancy protection
- Balance validation before transfer
- Proper event emission

## 8. Dispute Resolution Flow

**Actors**: Challenger (via passkey), Operator (resolution), Anyone (escalation)

**Preconditions**:
- Consensus computed
- Within challenge window
- Sufficient bond stake

**Critical Steps**:
1. `openDispute(projectId, index, evidenceHash)` — Locks bond, extends challenge
2. `resolveDispute(projectId, index, upheld)` — Operator decision, handles outcomes
3. `escalateDispute()` — Auto-uphold if operator fails to act
4. **Security Checks**: Bond calculation, evidence provision, timing windows

**Failure Points**:
- Frivolous disputes (insufficient bond deterrence)
- Operator censorship (no escalation path)
- Escrow underflow during resolution
- Serial dispute spam

**Protection Requirements**:
- Bonded commitment
- Auto-escalation mechanism
- Escrow safety guards
- Dispute window management

## 9. Originator Accountability Flow

**Actors**: Reporter (via passkey), Operator (resolution), Anyone (escalation)

**Preconditions**:
- Active project
- Evidence of originator misconduct
- Sufficient reporter bond

**Critical Steps**:
1. `reportOriginator(projectId, evidenceHash)` — Locks bond, pauses claiming
2. `resolveOriginatorReport(projectId, upheld)` — Operator decision, potential slashing
3. `escalateOriginatorReport()` — Auto-uphold if operator fails
4. **Security Checks**: Bond validation, project state, evidence handling

**Failure Points**:
- Insufficient originator stake requirement
- Weak misconduct detection
- Reporter bond slashing without cause
- Project cancellation without proper cleanup

**Protection Requirements**:
- Bonded reporting
- Clear misconduct criteria
- Proper stake slashing
- Project state cleanup

## 10. Project Completion Flow

**Actors**: Originator or anyone (permissionless after all settlements)

**Preconditions**:
- All contributions settled
- All disputes resolved
- Escrow reconciliation needed

**Critical Steps**:
1. `completeProject(projectId)` — Marks completed, refunds remaining escrow
2. **Stake Unlocking**: Release originator locked stake
3. **Escrow Reconciliation**: Return dust to originator
4. **Security Checks**: All indices finalized, no active disputes

**Failure Points**:
- Premature completion (active settlements)
- Escrow dust not returned
- Originator stake permanently locked
- Incomplete state cleanup

**Protection Requirements**:
- Complete settlement verification
- Proper escrow accounting
- Stake unlocking
- Event emission for indexing

## Flow Dependencies & Ordering

**Sequential Dependencies**:
- Project setup → Claim & contribute → Validation → Consensus → Settlement/Reward release
- Settlement must complete before reward claiming
- Challenge period must elapse before contributor reward release

**Parallel Execution**:
- Multiple validators can settle simultaneously
- Multiple contributors can release rewards in parallel
- Consensus computation is independent per index

**Failure Containment**:
- Individual contribution failures don't block project progress
- Validator failures don't prevent consensus (minimum thresholds)
- Dispute failures have escalation paths
- Escrow insolvency protections prevent cascading failures