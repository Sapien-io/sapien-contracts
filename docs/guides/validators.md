# Guide for Validators

Validators provide the intelligence layer of the protocol—whether human or AI. By reaching consensus on the quality of work, validators secure the AI systems relying on Sapien.

## 1. Prerequisites

- **Stake SAPIEN**: High-weight validation requires significant stake.
- **Maintain Reputation**: Honest participation builds your validator PoQ score.

## 2. The Validation Process

Validation uses an efficient **Commit-Reveal** scheme. To maximize efficiency, validators manage their commitment using a "Capacity" system.

### Step 1: Set Your Capacity
Call `ValidationOracle.setValidatorCapacity(amount)`.
- This locks a total amount of SAPIEN in the vault that acts as a pool for all your active validations.
- You only need to do this once (or when you want to change your commitment level).

### Step 2: Claim Task Slots
Call `ValidationOracle.claimToValidate(projectId)`.
- Each call claims a single validation assignment from the project's pending queue.
- You have a limited time (default 1 hour) to submit your commit for this slot.
- You can have up to 3 active claims per project.

### Step 3: Commit Your Scores
Review the work via the validator interface and decide on a score (0-10000).
Call `ValidationOracle.commitValidation(projectId, claimId, contributionIndex, commitHash)` (or use `batchCommitValidations` for efficiency):
- `commitHash` is `keccak256(score, stakeAmount, salt)`.
- The `stakeAmount` is deducted from your available capacity.

### Step 4: Reveal Your Scores
After the project's reveal period begins:
Call `ValidationOracle.revealValidation(projectId, contributionIndex, score, salt)` (or use `batchRevealValidations`):
- If the reveal matches your commit, the `stakeAmount` is returned to your available capacity.

## 3. Rewards and Penalties

- **Alignment Reward**: If your score is within the consensus range (typically within 2 standard deviations of the weighted average), you earn a share of the validator reward pool. **Important:** Validators are paid only when the contribution is **accepted**. If the contribution is rejected (below quality threshold), validators receive no rewards even though outlier slashing still applies.
- **Outlier Slashing**: If your score is identified as an outlier, you will not receive rewards, your reputation will decrease, and a portion of your stake will be slashed. This applies whether the contribution is accepted or rejected.
- **Non-Reveal Penalty**: If you commit but fail to reveal your score before the deadline, your entire committed stake is slashed.

## 💡 Pro-Tips for Validators

- **Be Objective**: Base your score strictly on the Task Definition Spec (TDS) provided by the Originator.
- **Keep Secrets**: Never share your salt or score before the reveal phase to avoid being targeted by colluders.
- **Automate**: For high-volume projects, use a Validator Oracle (adapter) to streamline the commit-reveal process.
