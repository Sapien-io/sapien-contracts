# Guide for Contributors

Contributors perform AI-related tasks and earn rewards based on the quality of their output as determined by human validator consensus.

## 1. Get Started

- **Stake SAPIEN**: You must have the minimum required stake in the `SapienVault` to claim tasks.
- **Build Reputation**: Your Proof of Quality (PoQ) score in `SapienTrust` determines your eligibility for high-value projects.

## 2. Claim Work Slots

Before you can submit work, you must "claim" capacity in a project. This prevents others from taking the slots while you are working.

Call `SapienCore.claimToContribute(projectId, quantity)`:
- `quantity`: Number of work units you commit to finishing.
- **Deadline**: Each claim has a deadline (defined by the project). If you don't submit work by the deadline, your claim expires and your stake may be slashed.

## 3. Submit Work

Perform the task using the tools provided by the Originator (e.g., CVAT for images). Once finished:

Call `SapienCore.contribute(projectId, claimId, contributionIndex, submissionHash)`:
- `submissionHash`: A unique hash or reference to your work (e.g., an IPFS CID).
- Use `batchContribute` to submit multiple items in a single transaction.

## 4. Finalization and Rewards

After you submit work, it will be reviewed by validators. Once enough reviews are gathered, the contribution is finalized.

- **If Accepted**: You will receive your reward tokens in the `Rewards` contract. You can withdraw them using `Rewards.claimRewards()` or `Rewards.claimAllRewards()`.
- **If Rejected**: If your contribution is rejected by the validator committee, your work index is released back to the project for others to attempt. Your reputation will decrease, and you may be penalized if your quality is consistently low.

## 📈 Improving Your Earnings

- **Focus on Quality**: Consistently high scores increase your `SapienTrust` reputation, giving you access to projects with higher rewards.
- **Validate Skills**: Successfully completing specialized tasks will validate those skills on your profile, making you eligible for niche projects.
- **Manage Deadlines**: Always release or finish claims before they expire to avoid unnecessary slashing.
