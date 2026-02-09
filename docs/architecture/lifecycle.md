# Protocol Lifecycle

This diagram illustrates the end-to-end lifecycle of a Sapien PoQ project, from creation to finalization and reward distribution.

## 🔄 End-to-End Sequence Diagram

```mermaid
sequenceDiagram
    autonumber
    actor O as Originator
    actor C as Contributor
    actor V as Validator
    participant SC as SapienCore
    participant VO as ValidationOracle
    participant ST as SapienTrust
    participant SV as SapienVault
    participant R as Rewards

    Note over O, R: Phase 1: Project Setup
    O->>SC: createProject(projectId, params, rewardConfig)
    SC->>VO: registerProject(projectId, ...)
    SC->>ST: updateReputation(originator, ...)
    O->>SC: fundProject(amount, quantity)
    Note over SC: Protocol fee deducted (default 1%)
    SC->>SC: Transfer fee to treasury
    SC->>R: allocateRewards(projectId, token, amountAfterFee)
    SC->>SC: Reward tokens transferred to escrow

    Note over O, R: Phase 2: Contribution
    C->>SC: claimToContribute(quantity)
    SC->>SV: lockStake(contributor, amount)
    SC-->>C: Returns claimId
    C->>SC: contribute(claimId, index, submissionHash)
    SC->>VO: enqueueValidation(projectId, index)

    Note over O, R: Phase 3: Validation (Commit-Reveal)
    V->>VO: setValidatorCapacity(amount)
    VO->>SV: lockStake(validator, amount)
    V->>VO: claimToValidate(projectId)
    VO-->>V: Assigns index from queue
    V->>VO: commitValidation(claimId, hash, stakeAmount)
    Note right of VO: Increments in-flight stake
    V->>VO: revealValidation(score, salt)
    Note right of VO: Decrements in-flight stake

    Note over O, R: Phase 4: Finalization
    Note over SC, VO: Triggered via finalizeContribution()
    SC->>VO: getConsensus(projectId, index)
    VO->>VO: Check consensus ready
    VO->>VO: Run Consensus Algorithm (weighted by stake & reputation)
    VO-->>SC: ConsensusReport (avg score, outliers)

    SC->>ST: updateReputation(contributor, success/failure)
    
    alt is Accepted (score >= 50%)
        SC->>R: distributeReward(contributor, amount)
        SC->>ST: validateSkill(contributor, skill)
        SC->>SV: unlockStake(contributor, amount) (if fully finalized)
    else is Rejected
        SC->>SC: Re-queue work index (index available for new claim)
        SC->>SC: Preserves contributor reward for next attempt
    end

    loop For each Outlier
        SC->>SV: slash(validator, amount)
        SC->>VO: handleValidatorSlash(validator, amount)
        SC->>ST: updateReputation(validator, penalty)
    end

    loop For each Accurate Validator
        SC->>R: distributeValidatorReward(validator, amount)
        SC->>ST: updateReputation(validator, success)
    end
```

## 🪜 Breakdown of Phases

### 1. Project Setup
Originators define the project parameters, including reward tokens, minimum stakes (for claiming and contributing), validator reward splits, and required skills. When funding the project, a protocol fee (default 1%) is automatically deducted and sent to the Sapien treasury. The remaining amount is moved into the `Rewards` contract escrow for distribution to contributors and validators.

### 2. Contribution
Contributors claim slots (`claimToContribute`), which locks their "skin in the game" stake in the `SapienVault`. They receive a set of reserved indices. When they submit their work (`contribute`), the submission is tracked and immediately enqueued in the `ValidationOracle` for validation.

### 3. Validation
Validators must first set their validation capacity (`setValidatorCapacity`), locking SAPIEN tokens in the vault. They then claim validation tasks (`claimToValidate`) from the queue. The process follows a Commit-Reveal scheme:
1.  **Commit**: Validators submit a hash of their score and salt. They can optionally "confidence stake" a variable amount of their capacity to increase their weight in consensus.
2.  **Reveal**: After the commit window, they reveal their score. This mechanism prevents copying ("mirroring") other validators.

### 4. Finalization
Once enough validations are received and revealed, `finalizeContribution` is called. The `ValidationOracle` calculates consensus using the project's selected algorithm (e.g., `CappedLinearConsensus`).
-   **Contributors**: Receive rewards if the average score is ≥ 50%. If rejected, the index is re-queued for another contributor.
-   **Validators**: Accurate validators earn rewards proportional to their weighted stake. Outliers (those too far from consensus) are slashed and suffer reputation penalties.

## ⚠️ Edge Cases & Timeouts

The system includes several mechanisms to handle expiration and non-performance:

```mermaid
sequenceDiagram
    autonumber
    actor U as Any User (Keeper)
    participant SC as SapienCore
    participant VO as ValidationOracle
    participant SV as SapienVault
    participant ST as SapienTrust

    Note over U, SC: Scenario 1: Contributor Claim Expired
    U->>SC: releaseExpiredClaim(claimId)
    SC->>SC: Check block.timestamp > claim.deadline
    SC->>SV: slash(contributor, amount)
    SC->>SV: unlockStake(contributor, remaining)
    SC->>SC: Mark claim as Expired

    Note over U, SC: Scenario 2: Reclaiming Unused Indices
    U->>SC: reclaimExpiredIndices(indices[])
    SC->>SC: Verify index deadline passed & not submitted
    SC->>SC: Free up indices for new claims

    Note over U, VO: Scenario 3: Validator Claim Expired (No Commit)
    U->>VO: cancelExpiredValidationClaim(claimId)
    VO->>VO: Check deadline & uncommitted count
    VO->>SV: slash(validator, uncommittedAmount)
    VO->>ST: updateReputation(validator, penalty)
    VO->>VO: Reduce validator capacity

    Note over U, VO: Scenario 4: Validator Reveal Expired (Ghost Validator)
    U->>VO: cancelExpiredCommitment(index, validator)
    VO->>VO: Check reveal deadline passed
    VO->>SV: slash(validator, committedAmount)
    VO->>ST: updateReputation(validator, penalty)
    VO->>VO: Reduce validator capacity
```

### 1. Contributor Claim Expiration
If a contributor reserves slots but fails to submit work before the deadline:
-   **Function**: `SapienCore.releaseExpiredClaim`
-   **Consequence**: The contributor is slashed (loss of stake) for the unfulfilled slots. Remaining stake is returned.

### 2. Index Reclamation
Indices reserved by expired claims are not automatically freed to save gas.
-   **Function**: `SapienCore.reclaimExpiredIndices`
-   **Consequence**: Makes the contribution indices available again for other contributors to claim.

### 3. Validator Claim Expiration (No Commit)
If a validator claims a task but fails to commit a score/hash:
-   **Function**: `ValidationOracle.cancelExpiredValidationClaim`
-   **Consequence**: The validator is slashed for the uncommitted validations.

### 4. Validator Reveal Expiration (Ghost Validator)
If a validator commits but fails to reveal their score (trying to hide a bad vote or save gas):
-   **Function**: `ValidationOracle.cancelExpiredCommitment`
-   **Consequence**: The validator is slashed for the full committed stake amount and suffers a reputation penalty.
