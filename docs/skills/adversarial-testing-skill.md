# Adversarial Testing Skill

This skill guides the creation of adversarial test cases to challenge the Sapien V2 protocol's security assumptions. It combines the architectural lifecycle flow with rigorous security review methodologies to identify and verify vulnerabilities.

## Purpose

To systematically generate, document, and implement test cases that simulate malicious actor behavior, focusing on:
-   Economic attacks (draining funds, manipulating rewards)
-   DoS attacks (griefing, state locking)
-   Consensus manipulation (sybil attacks, collusion)
-   Edge case exploitation (timeouts, race conditions)

**Target**: `test/` directory (specifically for creating new `Security` or `Adversarial` test suites).

---

## 🦹 Adversarial Mindset

When using this skill, adopt the persona of a motivated attacker who:
1.  **Ignores "intended" usage**: Calls functions in unexpected orders.
2.  **Maximizes profit**: Seeks to extract more value than contributed/staked.
3.  **Minimizes cost**: Uses flash loans or minimal stake to grief others.
4.  **Exploits timing**: Manipulates block timestamps and transaction ordering.

---

## ⚔️ Attack Vectors by Phase

Based on `@docs/architecture/lifecycle.md`, test these specific vectors for each phase:

### Phase 1: Project Setup
-   **Malicious Originator**:
    -   Create project with `minStake = 0` or `validatorReward = 100%`.
    -   Fund project with malicious ERC20 tokens (reverting transfer, fee-on-transfer).
    -   Update parameters (e.g., `requiredSkill`) mid-lifecycle to grief users.
-   **Resource Exhaustion**:
    -   Spam `createProject` to bloat state (if cheap).

### Phase 2: Contribution
-   **Sybil Contributor**:
    -   Use multiple addresses to claim all slots (`claimToContribute`).
    -   Submit invalid work to block legitimate contributors.
-   **Front-running**:
    -   Front-run legitimate claims to steal reserved indices.
-   **State Locking**:
    -   Claim slots but never submit (`releaseExpiredClaim` testing).

### Phase 3: Validation (Commit-Reveal)
-   **Ghost Validator**:
    -   `claimToValidate` but never `commit` (DoS attack on queue).
    -   `commit` but never `reveal` (griefing consensus resolution).
-   **Mirroring Attack**:
    -   Wait for others to reveal, then try to copy their score (prevented by salt?).
-   **Stake Manipulation**:
    -   "1-wei Shield": Commit with minimal stake, reveal with massive stake (or vice versa) to game weighting/slashing.
    -   Flash loan staking to inflate weight temporarily.

### Phase 4: Finalization
-   **Consensus Manipulation**:
    -   Collusion: 51% of validators coordinate to approve bad work or reject good work.
    -   Lazy Validation: Validators submitting random scores to farm rewards without work.
-   **Reentrancy & Races**:
    -   Reenter `finalizeContribution` during reward distribution.
    -   Race condition between `finalizeContribution` and `claimToContribute` reusing indices.

---

## 🧪 Generating Test Cases

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

## 🔍 Specific Edge Cases to Probe

Referencing the "Edge Cases & Timeouts" section of the lifecycle docs:

1.  **Validator Timeout Griefing**:
    -   Simulate a validator who commits but waits until `deadline - 1 second` to reveal.
    -   Simulate a validator who never reveals. Test `cancelExpiredCommitment` logic:
        -   Does it correctly slash?
        -   Does it unblock the queue?
        -   Can it be front-run to save the validator?

2.  **Index Reclamation Loops**:
    -   Claim -> Expire -> Reclaim -> Claim again.
    -   Test for off-by-one errors in available index tracking.
    -   Ensure reclaimed indices don't overwrite active contributions.

3.  **Cross-Phase State Corruption**:
    -   Try to `contribute` to a finalized claim.
    -   Try to `reveal` for a slashed validator.

---

## 🛡️ Anti-Hallucination & Verification

From `@docs/skills/security-review.md`:

| Rationalization | Counter-Argument | Test Requirement |
|-----------------|------------------|------------------|
| "Modifiers prevent this" | Modifiers might be skipped or bugged | Test bypassing modifiers |
| "Economic cost is too high" | Flash loans exist | Test with infinite ETH/Tokens |
| "Timestamps protect us" | Validators control timestamps | Fuzz `warp` times |
| "Only Admin can do this" | Admin keys can be compromised | Test impact of rogue admin |

## Execution Instructions

1.  **Review Architecture**: Read `@docs/architecture/lifecycle.md` to understand the intended flow.
2.  **Select Vector**: Choose an attack vector from the list above.
3.  **Draft Test Plan**: Describe the step-by-step attack in plain English.
4.  **Implement Test**: Write the Foundry test in `test/adversarial/`.
5.  **Analyze Result**: If the test passes (attack succeeds), it's a vulnerability. If it fails (reverts), the protocol is secure against this specific attempt.
