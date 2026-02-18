# Sapien PoQ v0.5 — Permissions & Trust Risk Analysis

## Executive Summary

This analysis reveals critical centralization risks in the Sapien PoQ protocol, with the DEFAULT_ADMIN_ROLE holding god-like powers that can result in complete protocol failure or total fund theft. Multiple critical vulnerabilities (STATIC-001 through STATIC-003) prevent basic protocol functionality, while the trust model relies on unrealistic assumptions about benevolent administration.

**Key Findings:**
- **DEFAULT_ADMIN_ROLE** can execute complete rug pulls via pause, parameter changes, or upgrades
- **OPERATOR_ROLE** can steal project escrows through dispute manipulation
- **ENGINE_ROLE** compromise affects all user stakes ($STAKE_TVL)
- Known critical bugs enable stake lock bypass and consensus manipulation

## Role Capabilities & Trust Analysis

### DEFAULT_ADMIN_ROLE (Deployer/Super Admin)

**Capabilities:**
- **Protocol Parameters:** Set all fees (protocol, origination, contribution, validation), decay rates, dispute bonds, stake requirements
- **Treasury Control:** Change treasury address to redirect all fee collection
- **Consensus Control:** Set consensus algorithm contract (pluggable but currently hardcoded)
- **Emergency Controls:** Pause/unpause entire protocol, upgrade contracts via UUPS
- **Role Management:** Grant/revoke all roles including OPERATOR_ROLE and ENGINE_ROLE
- **Economic Manipulation:** Set infinite fees, disable slashing, change reward distributions

**Trust Level:** CRITICAL — Single trusted party controls everything

**Blast Radius (Compromise Impact):**
- **Immediate:** Can pause protocol indefinitely, halting all user operations
- **Funds at Risk:** All project escrows ($PROJECT_TVL), accumulated fees, future deposits
- **Consensus Integrity:** Can install malicious consensus algorithm to manipulate all outcomes
- **Recovery:** Impossible — controls pause, upgrades, and parameter changes
- **Worst Case Scenario:** Complete rug pull of entire TVL + permanent protocol shutdown

**Attack Vectors:**
- Private key compromise via phishing/social engineering
- Supply chain attack on deployment infrastructure
- Malicious deployment by compromised deployer
- Governance capture through role revocation

### OPERATOR_ROLE (Dispute Resolver)

**Capabilities:**
- **Dispute Resolution:** Decide uphold/reject disputes, redistribute project escrows
- **Originator Accountability:** Resolve misconduct reports, slash originator stakes
- **Subjective Decision Making:** Evaluate off-chain evidence for dispute outcomes

**Trust Level:** HIGH — Requires subjective judgment calls

**Blast Radius (Compromise Impact):**
- **Immediate:** Can delay resolutions but auto-escalation provides backstop
- **Funds at Risk:** Individual project escrows ($PROJECT_VALUE), originator stake pools
- **Consensus Integrity:** Can override consensus outcomes for disputed contributions
- **Recovery:** Auto-escalation after timeout, but timing can be gamed
- **Worst Case Scenario:** Systematic theft of disputed funds, protection racket for malicious originators

**Attack Vectors:**
- Bribery from disputing parties
- Evidence tampering or censorship
- Timing manipulation of resolution deadlines
- Collusion with originators or challengers

### ENGINE_ROLE (QualityEngine Contract)

**Capabilities:**
- **Stake Management:** Lock/unlock/slash contributor stakes, validator capacity, in-flight stakes
- **Settlement Execution:** Process consensus outcomes, distribute rewards, execute slashing
- **State Transitions:** Move stakes between locked states according to protocol rules

**Trust Level:** CRITICAL — Contract-level trust required for all staking operations

**Blast Radius (Compromise Impact):**
- **Immediate:** All staking operations fail (contributions, validations, settlements)
- **Funds at Risk:** All user stakes ($STAKE_TVL), inability to unlock legitimate stakes
- **Consensus Integrity:** Cannot settle validators, breaking reward distribution
- **Recovery:** Requires contract upgrade (controlled by admin)
- **Worst Case Scenario:** Arbitrary slashing of user funds, permanent stake locks, protocol paralysis

**Attack Vectors:**
- Smart contract vulnerabilities (reentrancy, overflows, logic bugs)
- Malicious upgrades by compromised admin
- Delegatecall exploits in ConsensusLib
- External call manipulation in adapters

## Public Attack Surface & Economic Gates

### Permissionless Functions (High Risk)
- **Consensus Computation:** `computeConsensus()` — Can be censored by keepers
- **Validator Settlement:** `settleValidator()` — Race conditions, escrow underflows
- **Reward Release:** `releaseContributorReward()` — Timing attacks, double-release prevention
- **Expired Operations:** `cancelExpiredCommitment()`, `escalateDispute()` — Griefing vectors

### Economic Access Controls
- **Stake Requirements:** Minimum stake for participation (bypassable via STATIC-001)
- **Bond Requirements:** Dispute/originator report bonds (insufficient deterrence)
- **Reputation Gates:** Minimum reputation for validation (decay manipulation)
- **Timing Constraints:** Deadline-based operations (front-running, censorship)

### Known Vulnerabilities Enabling Attacks
- **STATIC-001:** ERC4626 share transfer bypass — Complete stake lock bypass
- **STATIC-002:** Missing ENGINE_ROLE grant — Protocol non-functional
- **STATIC-003:** Settlement blockage on rejection — Validator stake locks
- **STATIC-004:** Zero-stake validation — Consensus manipulation
- **STATIC-005:** Escrow underflow — Validator reward theft

## Privilege Escalation Paths

### Primary Escalation Chains

1. **Public → ENGINE_ROLE → Full Control**
   ```
   Public User → Exploit QualityEngine Vulnerability → ENGINE_ROLE Access → Arbitrarily Slash All Stakes → Economic Dominance
   ```

2. **OPERATOR_ROLE → Financial Leverage → Admin Pressure**
   ```
   Dispute Resolver → Manipulate High-Value Disputes → Extract Concessions → Social Engineering → Admin Compromise
   ```

3. **Admin Compromise → Complete Control**
   ```
   DEFAULT_ADMIN_ROLE → Pause Protocol → Change Treasury → Upgrade Contracts → Total Fund Extraction
   ```

### Attack Vector Taxonomy

**Smart Contract Attacks:**
- Reentrancy in token operations (fundProject, claimReward, dispute settlement)
- Arithmetic overflows in consensus calculations (score * weight * PRECISION)
- Storage collisions in validator consensus mapping
- ERC4626 implementation flaws (share transfer bypass)

**Economic Attacks:**
- Zero-stake Sybil attacks on consensus
- Griefing via expired claims and ghost validations
- Adapter-based censorship and selective failures
- Reputation manipulation through repeated operations

**Operational Attacks:**
- Keeper censorship of permissionless functions
- Timing attacks on deadline-dependent operations
- Front-running of settlement operations
- State desync from concurrent operations

## Trust Assumptions & Violation Potential

### Core Trust Assumptions (All Violable)

1. **Admin Benevolence:** "DEFAULT_ADMIN_ROLE holders act benevolently"
   - **Violation Risk:** HIGH — Single points of failure, no multisig requirements
   - **Impact:** Complete protocol compromise

2. **Operator Fairness:** "OPERATOR_ROLE resolves disputes fairly within time bounds"
   - **Violation Risk:** HIGH — Subjective decisions, no appeal mechanisms
   - **Impact:** Fund theft via fraudulent resolutions

3. **Contract Security:** "QualityEngine and StakeVault operate correctly"
   - **Violation Risk:** CRITICAL — Multiple known vulnerabilities (STATIC-001-012)
   - **Impact:** Protocol non-functional or fund compromise

4. **Infrastructure Trust:** "ERC4337 stack (EntryPoint, Bundler, Paymaster) operates correctly"
   - **Violation Risk:** MEDIUM — External dependencies on third-party infrastructure
   - **Impact:** Censorship, frontrunning, gas manipulation

5. **Participant Honesty:** "Validators score based on quality, not collusion"
   - **Violation Risk:** HIGH — Economic incentives for collusion, zero-stake bypass
   - **Impact:** Consensus manipulation, reward theft

### Trust Boundary Violations

**Internal Boundaries:**
- Access control bypass via ERC4626 share transfers
- Cross-contract calls without proper validation
- Storage isolation failures in delegatecall operations

**External Boundaries:**
- Adapter contracts can manipulate token transfers
- Consensus algorithm can be compromised
- ERC20 tokens may have unexpected behavior (fee-on-transfer)

## Worst-Case Scenarios by Role

### DEFAULT_ADMIN_ROLE Compromise
1. Pause entire protocol
2. Change treasury to attacker address
3. Set infinite adapter fees
4. Upgrade contracts to backdoored versions
5. **Result:** 100% fund loss for all users, permanent protocol death

### OPERATOR_ROLE Compromise
1. Identify high-value projects with active disputes
2. Resolve disputes in favor of colluding parties
3. Reject legitimate originator misconduct reports
4. **Result:** Theft of disputed escrows, protection for malicious actors

### ENGINE_ROLE Compromise
1. Arbitrarily slash high-value stakes
2. Unlock stakes without permission
3. Prevent legitimate settlements
4. **Result:** Stake theft, protocol paralysis, user fund loss

### Public Attack Surface Exploitation
1. Use STATIC-001 to bypass all stake locks
2. Deploy zero-stake validation Sybil attack
3. Exploit escrow underflows in settlements
4. **Result:** Complete economic security breakdown, consensus manipulation

## Recommendations

### Immediate (Blocker Issues)
1. **Fix STATIC-001-003:** Critical bugs prevent basic functionality
2. **Implement Multisig:** Replace single admin with multisig + timelocks
3. **Add Circuit Breakers:** Emergency pause with user withdrawal windows

### Medium-term (Security Hardening)
1. **Reduce Admin Powers:** Separate parameter control from emergency controls
2. **Operator Accountability:** Evidence requirements, appeal mechanisms, reputation penalties
3. **Contract Security:** Comprehensive audit, formal verification of consensus logic

### Long-term (Decentralization)
1. **Progressive Decentralization:** Token-based governance with guardrails
2. **Operator Decentralization:** Community dispute resolution mechanisms
3. **Multi-sig Requirements:** All critical operations require multiple approvals

**Overall Risk Assessment:** CRITICAL — Protocol currently undeployable due to fundamental trust and security issues.