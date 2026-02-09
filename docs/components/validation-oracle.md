# Validation Oracle

The `ValidationOracle` is a stateless consensus engine that manages the validation process for Sapien PoQ. It implements a commit-reveal scheme to ensure validator independence and uses pluggable algorithms to calculate consensus.

## 📋 Responsibilities

- **Validation Management**: Handling claims to validate, commits, and reveals.
- **Consensus Calculation**: Delegating the mathematical calculation to external algorithm contracts.
- **Oracle Logic**: Recording the relationship between projects, contributions, and validators.

## 🛠️ Key Functions

### Validator Workflow

#### `setValidatorCapacity`
Before participating, validators must set their "validation capacity" by locking SAPIEN tokens in the `SapienVault`.
- This provides a pool of locked stake that covers multiple "in-flight" validations.
- Eliminates the need to lock/unlock stake for every individual commit, significantly reducing gas costs for active validators.

#### `claimToValidate`
Validators express interest in reviewing contributions for a specific project. 
- Requires `VALIDATOR_ROLE` and sufficient available capacity (Locked Stake - In-Flight Stake).
- Reserves slots from the `pendingQueue` for a fixed `CLAIM_DURATION` (default 1 hour).

#### `commitValidation` / `batchCommitValidations`
Validators submit a `commitHash` which is `keccak256(score, stakeAmount, salt)`. 
- This increases the validator's `inFlightStake`.
- Sybil protection prevents Originators and the original Contributor from validating the work.

#### `revealValidation` / `batchRevealValidations`
Validators reveal their `score` and `salt`. 
- The oracle verifies the reveal matches the commit.
- The `inFlightStake` is decreased (capacity is freed up for new claims).

#### `cancelExpiredValidationClaim` / `cancelExpiredCommitment`
Allows the system to penalize validators who block the pipeline:
- `cancelExpiredValidationClaim`: Slashes validators who claim slots but never commit.
- `cancelExpiredCommitment`: Slashes validators who commit but fail to reveal within the `revealDeadline`.

### Consensus Logic

#### `getConsensus`
Called by `SapienCore` to determine if a contribution is ready for finalization. It:
1. Verifies that the minimum number of reveals has been reached.
2. Checks if the reveal deadline has passed for any unrevealed commits.
3. Fetches the project's assigned `ConsensusAlgorithm`.
4. Returns the weighted average score, validator count, and a list of outliers to be slashed.

### Registry Functions

#### `registerAlgorithm`
(Admin only) Registers a new `IConsensusAlgorithm` implementation.

#### `setProjectAlgorithm`
Allows an Originator to choose which consensus algorithm (e.g., "Hybrid", "SqrtStake") to use for their project.

## ⚙️ Configurable Parameters

- **Reveal Deadline**: The time validators have to reveal their scores after committing (default is 3 days).
- **Claim Duration**: The time validators have to commit after claiming a slot (default is 1 hour).

## 🛡️ Security Features

- **Sybil Protection**: The protocol prevents a project's Originator or the contribution's Contributor from validating their own work.
- **Commit-Reveal**: Prevents "herding" behavior where validators simply copy the scores of others.
- **Stake Locking**: Validator stake is locked from the moment of commitment until reveal or expiration.
