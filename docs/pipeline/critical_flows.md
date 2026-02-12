# Critical Protocol Flows

## 1. Project Setup
- **Action**: An **Originator** calls `createProject` in `SapienCore`.
- **Details**: Defines project parameters: `rewardToken`, `minStakeToClaim`, `numberOfValidations`, `requiredSkill`, and an IPFS CID for the project specification.
- **Side Effect**: The project is registered in `ValidationOracle` with its consensus settings.
- **Funding**: Originator calls `fundProject` to deposit rewards. Protocol and operator fees are deducted at this stage.

## 2. Work Submission
- **Claiming**: A **Contributor** calls `claimToContribute` in `SapienCore`. This locks their stake and assigns specific contribution indices.
- **Submission**: The contributor performs work off-chain and calls `contribute` or `batchContribute`, providing a `submissionHash` of their work.
- **Enqueueing**: `SapienCore` automatically calls `enqueueValidation` in `ValidationOracle`, which creates exactly `numberOfValidations` validation slots in a pending queue.

## 3. Validation Process
- **Claiming**: A **Validator** calls `claimToValidate` in `ValidationOracle` to take a slot from the pending queue. This requires sufficient "capacity" (locked stake in `SapienVault`).
- **Commit**: Validator calls `commitValidation`, providing a hash of their score and salt.
- **Reveal**: Once the commit is recorded, the validator calls `revealValidation` with the actual score (0-10000) and salt. The `inFlightStake` is released back to their capacity upon reveal.

## 4. Consensus & Finalization
- **Trigger**: Anyone can call `finalizeContribution` in `SapienCore` once `numberOfValidations` have been revealed and all active commits are either revealed or expired.
- **Consensus**: `SapienCore` fetches a `ConsensusReport` from `ValidationOracle`. The report includes the weighted average score and a list of outlier validators.
- **Outcome**:
    - **Accepted**: If `weightedAverage >= consensusThreshold`. Contributor receives rewards; reputation increases.
    - **Rejected**: If below threshold. Contribution is deleted, and the slot is re-queued for a new contributor. Reputation decreases.
- **Validator Settlement**: Accurate validators receive a portion of the `validatorRewardBasisPoints` from the project rewards **only when the contribution is accepted**. On rejection, no validator rewards are distributed (pool unchanged); outliers are still slashed. See [Validator Rewards on Rejection fix](../security/fixes/validator-rewards-on-rejection.md).

## 5. Slashing & Expiry
- **Claim Expiry**: If a contributor or validator fails to fulfill their claim by the deadline, their claim can be canceled/released, resulting in a stake slash.
- **Outlier Slashing**: Validators whose scores are significantly different from the consensus (as determined by the algorithm) are slashed.
- **Stake Release**: Locked stake is only released back to "available" status after successful completion or expiration (if not slashed).
