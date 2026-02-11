# Sapien PoQ MEV & Economic Attacker Playbooks

This document outlines step-by-step attacker playbooks for the economic and MEV risks identified in the Sapien PoQ protocol analysis.

---

## Scenario 1: The Liveness Extortion (Reveal Griefing)

**Attacker Role:** Validator(s)
**Goal:** Block project progress or extort the project originator.

### Steps:
1. **Identify Target:** Find a high-value project or a project with a tight deadline.
2. **Claim Slots:** Call `claimToValidate` for multiple contributions as soon as they are enqueued.
3. **Commit:** Call `commitValidation` with a valid hash (e.g., scoring 5000) within the 1-hour `CLAIM_DURATION`.
4. **Hold:** Other honest validators reveal their scores.
5. **Withhold:** The attacker intentionally does NOT call `revealValidation`.
6. **Result:** Because `minValidations` might be met but some commits are still pending and not yet expired, `ValidationOracle._checkConsensusReady` returns `false`.
7. **Impact:** The `SapienCore.finalizeContribution` call will fail/noop until the `revealDeadline` (default 3 days) passes. The attacker can offer to "reveal for a fee" to unblock the project.

---

## Scenario 2: Validator Reward Frontrunning (The Reward Snatcher)

**Attacker Role:** Validator / Searcher
**Goal:** Capture a sudden increase in project rewards.

### Steps:
1. **Monitor Mempool:** Watch for a large `SapienCore.fundProject` transaction from a project originator.
2. **Analyze:** Check if the project has contributions ready for finalization.
3. **Execute:** 
    * **Action A (if dilution):** If `fundProject` adds quantity with minimal rewards, frontrun with `finalizeContribution` to capture rewards at the current (higher) rate.
    * **Action B (if top-up):** If `fundProject` adds rewards without quantity, backrun `fundProject` with `finalizeContribution` to capture rewards at the new (higher) rate.
4. **Result:** The attacker extracts more reward tokens than they would have in a fair ordering, at the expense of other participants.

---

## Scenario 3: Whale Queue Monopoly (The Slot Hog)

**Attacker Role:** Whale Validator
**Goal:** Prevent competition and ensure they are the only ones getting validator rewards.

### Steps:
1. **Set Capacity:** Call `setValidatorCapacity` with a massive amount of stake (e.g., 10,000x the minimum).
2. **Monitor Enqueues:** Watch for `enqueueValidation` events in `ValidationOracle`.
3. **Spam Claims:** Immediately call `claimToValidate` repeatedly in a loop. Since there is no per-user limit on validation claims, the attacker can fill the `pendingQueue` entirely.
4. **Result:** Honest validators see an empty queue (`getPendingValidationCount == 0`) and cannot participate.
5. **Impact:** The whale validator earns all `validatorRewardBasisPoints` for every contribution in the project, effectively "locking out" the community.

---

## Scenario 4: Strategic Outcome Manipulation

**Attacker Role:** Validator with external interest (e.g., the contributor's friend or rival).
**Goal:** Force a contribution to be accepted or rejected regardless of its quality.

### Steps:
1. **Claim & Commit:** Attacker claims a slot and commits a score.
2. **Observe:** Wait for honest validators to reveal their scores.
3. **Calculate:** The attacker calculates the current `weightedAverage` from revealed scores.
4. **Decide:**
    * If the attacker wants the contribution **Accepted** and their revealed score would help, they reveal.
    * If the attacker wants it **Rejected** and their revealed score would help, they reveal.
    * If revealing their *committed* score would hurt their goal, or if it would result in them being slashed as an outlier, they **withhold** the reveal.
5. **Outcome:** By choosing whether or not to reveal a *pre-committed* score, the validator still retains a binary "reveal/withhold" option to influence the final consensus average and the protocol outcome.

---

## Scenario 5: Rounding Dust "Theft" (Hypothetical)

**Attacker Role:** Opportunistic User
**Goal:** Drain the accumulated dust from the `Rewards` contract.

### Steps:
1. **Identify Dust:** Monitor `Rewards.projectRewards` for projects that are "finished" (all slots finalized/expired) but still have token balances.
2. **Trigger Distribution:** (Requires a vulnerability in how project state is checked). If an attacker can find a way to call `distributeReward` for a completed project (e.g., via a re-initialized project ID or a bug in `SapienCore`), they could potentially claim the accumulated rounding dust.
3. **Note:** Currently, this is difficult as `distributeReward` is `onlyCore`. However, the lack of a reclaim mechanism makes this dust an attractive target for any future logic bugs.
