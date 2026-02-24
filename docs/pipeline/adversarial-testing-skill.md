# Adversarial Testing Skill

This skill guides the creation of adversarial test cases to challenge the Sapien PoQ v0.5 protocol's security assumptions. It combines the v0.5 architectural lifecycle flow with rigorous security review methodologies to identify and verify vulnerabilities.

## Purpose

To systematically generate, document, and implement test cases that simulate malicious actor behavior, focusing on:
- Economic attacks (draining funds, manipulating rewards)
- DoS attacks (griefing, state locking)
- Consensus manipulation (sybil attacks, collusion)
- Edge case exploitation (timeouts, race conditions)

**Target**: `test/` directory (specifically `test/lifecycle/` and new `Security` or `Adversarial` test suites).

**Architecture Reference**: Sapien PoQ v0.5 -- SapienCore + SapienVault + 7 libraries (OriginationLib, ContributionLib, ValidationLib, ConsensusLib, FinalizationLib, DisputeLib, ReputationLib).

---

## Adversarial Mindset

When using this skill, adopt the persona of a motivated attacker who:
1. **Ignores "intended" usage**: Calls functions in unexpected orders.
2. **Maximizes profit**: Seeks to extract more value than contributed/staked.
3. **Minimizes cost**: Uses flash loans or minimal stake to grief others.
4. **Exploits timing**: Manipulates block timestamps and transaction ordering.

---

## Attack Vectors by Phase

Based on v0.5 lifecycle, test these vectors for each phase:

### Phase 1: Project Setup
- **Malicious Originator**:
  - Create project with `minStakeToClaim = 0` or `validatorRewardBps = 2500` (max).
  - Fund with malicious ERC20 (reverting transfer, fee-on-transfer).
  - Attempt to update parameters mid-lifecycle (v0.5 has no in-lifecycle param changes).
- **Resource Exhaustion**:
  - Spam `createProject` to bloat state (if cheap).

### Phase 2: Contribution
- **Sybil Contributor**:
  - Multiple addresses claim all slots via `claimToContribute`.
  - Submit invalid work (hashes) to block legitimate contributors.
- **Front-running**:
  - Front-run legitimate claims to steal reserved indices.
- **State Locking**:
  - Claim slots but never submit -- `expireClaim` should return indices and slash.
  - Verify expiry returns indices atomically (no zombie indices).

### Phase 3: Validation (Commit-Reveal)
- **Ghost Validator**:
  - `commitValidation` but never `revealValidation` -- test `cancelExpiredCommitment` slashing.
  - Verify consensus unblocking (other validators can still reach `numberOfValidations`).
- **Validation Claim Griefing**:
  - `claimToValidate` but never commit -- test `cancelExpiredValidationClaim`.
- **Mirroring Attack**:
  - Wait for others to reveal, then try to copy their score (prevented by salt in commit hash and commit deadline).
- **Stake Manipulation**:
  - Commit hash is `keccak256(abi.encodePacked(score, salt))` -- stake amount is separate.
  - Committed stake is stored in `ValidatorCommit.stakedAmount` and used for weighting/slashing -- verify no mismatch exploit.
  - Flash loan staking to inflate weight temporarily (deposit -> lock capacity -> commit -> reveal -> withdraw).

### Phase 4: Finalization
- **Consensus Manipulation**:
  - Collusion: 51%+ of validators coordinate to approve bad work or reject good work.
  - Lazy validation: Random scores to farm rewards without work.
  - Tiered slashing edge: score exactly at 1.5 sigma boundary.
- **Reentrancy and Races**:
  - Reenter during `claimReward` or `releaseContributorReward`.
  - Race between `computeConsensus` and `openDispute` during challenge period.
  - `ReentrancyGuardUpgradeable` is used -- verify coverage.
- **Force Settlement**:
  - `forceSettleValidator` after `forceSettleDelay` -- can it be used to grief validators?

### Phase 5: Disputes and Originator Reports
- **Dispute Gaming**:
  - Open dispute, escalate before operator resolves -- auto-uphold mechanics.
  - Challenge own acceptance (blocked -- `CannotDisputeOwnContribution`).
  - Rejected contributor disputes -- compensation flow.
  - Cross-nonce dispute poisoning (prevented -- disputes keyed by consensus nonce).
- **Originator Report**:
  - Report own project (blocked -- `NotProjectOriginator` revert).
  - Spam reports (one active at a time).
  - Escalation griefing after 7-day resolution deadline.
  - Reporter reward from escrow when originator has locked stake.

---

## Generating Test Cases

Use this template for Foundry test cases:

```solidity
// Title: [Attack Name]
// Severity: [Critical/High/Medium]
// Description: [How the attack works]

function test_Adversarial_[AttackName]() public {
    // 1. Setup: _setupProject, _claimAndSubmit, etc.

    // 2. Attack: Simulate malicious actor actions
    vm.startPrank(attacker);
    // ... actions ...
    vm.stopPrank();

    // 3. Assert: Verify attack succeeded (vulnerability) or failed (secure)
    // assertEq(victimBalance, 0); 
    // assertTrue(protocolPaused);
}
```

---

## Specific Edge Cases to Probe

Referencing v0.5 edge cases and timeouts:

1. **Validator Timeout Griefing**:
   - Validator commits but waits until deadline to reveal (or never reveals).
   - Test `cancelExpiredCommitment`: correct slash, unblock consensus?
   - Can it be front-run to save the validator?

2. **Index Reclamation**:
   - Claim -> Expire -> Re-claim same indices.
   - Off-by-one errors in `returnStack` / `returnStackTop`.
   - Rejected contributions: nonce increment, index return -- ensure no overlap with new claim.

3. **Cross-Phase State Corruption**:
   - `contribute` to finalized/rejected index.
   - `reveal` for slashed validator.
   - `settleValidator` before `computeConsensus`.
   - `releaseContributorReward` before challenge period or with open dispute.

4. **Phased Finalization Order**:
   - `settleValidator` without `computeConsensus` (reverts).
   - Double `computeConsensus` (reverts `ConsensusAlreadyComputed`).
   - Double `settleValidator` (reverts `AlreadySettled`).

5. **Nonce-Based Re-Validation**:
   - After rejection and nonce increment, stale validators attempt to settle with old nonce.
   - New validators commit/reveal on the new nonce for the same index.

---

## Anti-Hallucination and Verification

| Rationalization | Counter-Argument | Test Requirement |
|-----------------|------------------|------------------|
| "Modifiers prevent this" | Modifiers might be skipped or bugged | Test bypassing modifiers |
| "Economic cost is too high" | Flash loans exist | Test with infinite ETH/Tokens |
| "Timestamps protect us" | Keeper controls warp | Fuzz `warp` times |
| "Only Admin can do this" | Admin keys can be compromised | Test impact of rogue admin |

---

## Execution Instructions

1. **Review Architecture**: Read source code in `src/` for intended flow.
2. **Select Vector**: Choose an attack vector from the list above.
3. **Draft Test Plan**: Describe the step-by-step attack in plain English.
4. **Implement Test**: Write the Foundry test in `test/lifecycle/` or `test/adversarial/`.
5. **Analyze Result**: If the test passes (attack succeeds), it's a vulnerability. If it fails (reverts), the protocol is secure against this specific attempt.
