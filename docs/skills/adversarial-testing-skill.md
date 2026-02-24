# Adversarial Testing Skill

This skill guides the creation of adversarial test cases to challenge the Sapien PoQ v0.5 protocol's security assumptions. It combines the v0.5 architectural lifecycle flow with rigorous security review methodologies to identify and verify vulnerabilities.

## Purpose

To systematically generate, document, and implement test cases that simulate malicious actor behavior, focusing on:
- Economic attacks (draining funds, manipulating rewards)
- DoS attacks (griefing, state locking)
- Consensus manipulation (sybil attacks, collusion)
- Edge case exploitation (timeouts, race conditions)

**Target**: `test/` directory (specifically for creating new `Security` or `Adversarial` test suites).

---

## Adversarial Mindset

When using this skill, adopt the persona of a motivated attacker who:
1. **Ignores "intended" usage**: Calls functions in unexpected orders.
2. **Maximizes profit**: Seeks to extract more value than contributed/staked.
3. **Minimizes cost**: Uses flash loans or minimal stake to grief others.
4. **Exploits timing**: Manipulates block timestamps and transaction ordering.

---

## Attack Vectors by Phase

Based on v0.5 lifecycle (SapienCore + SapienVault + 7 libraries), test these specific vectors for each phase:

### Phase 1: Project Setup
- **Malicious Originator**:
  - Create project with `minStakeToClaim = 0` or `validatorRewardBps = 2500` (max).
  - Fund project with malicious ERC20 tokens (reverting transfer, fee-on-transfer).
  - Attempt to update parameters mid-lifecycle (v0.5 has no in-lifecycle param changes).
- **Resource Exhaustion**:
  - Spam `createProject` to bloat state (if cheap).

### Phase 2: Contribution
- **Sybil Contributor**:
  - Use multiple addresses to claim all slots (`claimToContribute`).
  - Submit invalid work to block legitimate contributors.
- **Front-running**:
  - Front-run legitimate claims to steal reserved indices.
- **State Locking**:
  - Claim slots but never submit -- `expireClaim` returns indices and slashes contributor.

### Phase 3: Validation (Commit-Reveal)
- **Ghost Validator**:
  - `commitValidation` but never `revealValidation` -- test `cancelExpiredCommitment` slashing.
  - Verify consensus unblocking.
- **Validation Claim Griefing**:
  - `claimToValidate` but never commit -- test `cancelExpiredValidationClaim`.
- **Mirroring Attack**:
  - Wait for others to reveal, then try to copy their score (prevented by commit deadline and salt).
- **Stake Manipulation**:
  - Committed stake is stored in `ValidatorCommit.stakedAmount` -- verify no mismatch exploit.
  - Flash loan staking to inflate weight temporarily.

### Phase 4: Finalization
- **Consensus Manipulation**:
  - Collusion: 51% of validators coordinate to approve bad work or reject good work.
  - Lazy Validation: Validators submitting random scores to farm rewards without work.
  - Tiered slashing edge: scores at exact sigma boundaries.
- **Reentrancy and Races**:
  - Reenter `claimReward` or `releaseContributorReward`.
  - Race condition between `computeConsensus` and `openDispute`.
  - `ReentrancyGuardUpgradeable` is used -- verify coverage.

### Phase 5: Disputes and Originator Reports
- **Dispute Gaming**:
  - Open dispute, escalate before operator resolves -- auto-uphold after 7 days.
  - Challenge own acceptance (blocked -- `CannotDisputeOwnContribution`).
  - Cross-nonce dispute poisoning (prevented -- disputes keyed by consensus nonce).
- **Originator Report**:
  - Report own project (blocked -- reverts).
  - Spam reports (one active at a time).
  - Escalation griefing after resolution deadline.

---

## Generating Test Cases

Use this template to generate Foundry test cases for identified vectors:

```solidity
// Title: [Attack Name]
// Severity: [Critical/High/Medium]
// Description: [How the attack works]

function test_Adversarial_[AttackName]() public {
    // 1. Setup: Create project, fund, etc.
    
    // 2. Attack: Simulate malicious actor actions
    vm.startPrank(attacker);
    // ... actions ...
    vm.stopPrank();

    // 3. Assert: Verify the attack succeeded (or failed as expected)
    // assertEq(victimBalance, 0); 
    // assertTrue(protocolPaused);
}
```

## Specific Edge Cases to Probe

1. **Validator Timeout Griefing**:
   - Simulate a validator who commits but waits until deadline to reveal.
   - Simulate a validator who never reveals. Test `cancelExpiredCommitment` logic:
     - Does it correctly slash?
     - Does it unblock consensus?
     - Can it be front-run to save the validator?

2. **Index Reclamation**:
   - Claim -> Expire -> Re-claim same indices.
   - Test for off-by-one errors in returnStack / returnStackTop.
   - Ensure reclaimed indices don't overwrite active contributions.

3. **Cross-Phase State Corruption**:
   - Try to `contribute` to a finalized claim.
   - Try to `reveal` for a slashed validator.
   - Try to `settleValidator` before `computeConsensus`.
   - Try to `releaseContributorReward` before challenge period ends.

4. **Nonce-Based Re-Validation**:
   - After rejection and nonce increment, stale validators attempt settlement.
   - New validators commit/reveal on the new nonce for the same index.

---

## Anti-Hallucination and Verification

| Rationalization | Counter-Argument | Test Requirement |
|-----------------|------------------|------------------|
| "Modifiers prevent this" | Modifiers might be skipped or bugged | Test bypassing modifiers |
| "Economic cost is too high" | Flash loans exist | Test with infinite ETH/Tokens |
| "Timestamps protect us" | Keeper controls warp | Fuzz `warp` times |
| "Only Admin can do this" | Admin keys can be compromised | Test impact of rogue admin |

## Execution Instructions

1. **Review Architecture**: Read source code in `src/` to understand the intended flow.
2. **Select Vector**: Choose an attack vector from the list above.
3. **Draft Test Plan**: Describe the step-by-step attack in plain English.
4. **Implement Test**: Write the Foundry test in `test/adversarial/`.
5. **Analyze Result**: If the test passes (attack succeeds), it's a vulnerability. If it fails (reverts), the protocol is secure against this specific attempt.
