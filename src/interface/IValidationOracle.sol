// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISharedTypes} from "./ISharedTypes.sol";
import {IConsensusAlgorithm} from "./IConsensusAlgorithm.sol";

/**
 * @title IValidationOracle
 * @author Sapien Team
 * @notice Stateless consensus oracle for Sapien V2
 * @dev Manages the commit-reveal process and consensus calculations
 */
interface IValidationOracle is ISharedTypes {
    // Structs for State Grouping
    struct ProjectSettings {
        bytes32 algorithm;
        uint256 numberOfValidations;
        uint256 revealDeadline;
        string requiredSkill;
        address originator;
        uint256 nextValidationClaimId;
        uint256 queueHead;
        uint256 queueTail;
        uint256 minValidatorReputation; // Minimum reputation required for validators (0 = no requirement)
    }

    struct ContributionState {
        uint256 submittedAt;
        address contributor;
        uint256 activeClaimCount;
        uint256 submissionNonce; // F-05: Incremented on each re-queue to invalidate stale commits
    }

    struct ValidatorState {
        uint256 capacity;
        uint256 inFlightStake;
    }

    struct AssignmentState {
        uint256 deadline;
        bool hasCommitted;
        uint256 committedStake;
    }

    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when a validator claims a validation slot
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param validator Address of the validator
     * @param deadline Timestamp when the claim expires
     */
    event ValidationClaimed(
        bytes32 indexed projectId, uint256 indexed claimId, address indexed validator, uint256 deadline
    );

    /**
     * @notice Emitted when a validator commits a validation score hash
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution being validated
     * @param validator Address of the validator
     * @param commitHash keccak256(score, stakeAmount, salt)
     * @param stakeAmount Amount staked for this validation
     */
    event ValidationCommitted(
        bytes32 indexed projectId,
        uint256 indexed contributionIndex,
        address indexed validator,
        bytes32 commitHash,
        uint256 stakeAmount
    );

    /**
     * @notice Emitted when a validator reveals their score
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @param validator Address of the validator
     * @param score The revealed score
     * @param stakeAmount Amount staked for this validation
     */
    event ValidationRevealed(
        bytes32 indexed projectId,
        uint256 indexed contributionIndex,
        address indexed validator,
        uint256 score,
        uint256 stakeAmount
    );

    /**
     * @notice Emitted when a new consensus algorithm is registered
     * @param name Name of the algorithm
     * @param implementation Address of the algorithm contract
     */
    event AlgorithmRegistered(string name, address indexed implementation);

    /**
     * @notice Emitted when a project's settings are updated
     * @param projectId Unique identifier for the project
     * @param algorithm Current algorithm identifier
     * @param numberOfValidations Number of validations required
     * @param revealDeadline Time allowed for reveal
     * @param requiredSkill Skill required for validators
     * @param originator Address of the project creator
     * @param nextValidationClaimId Next claim ID to be issued
     * @param queueHead Current head of the pending queue
     * @param queueTail Current tail of the pending queue
     * @param minValidatorReputation Minimum reputation requirement
     */
    event ProjectStateChange(
        bytes32 indexed projectId,
        bytes32 indexed algorithm,
        uint256 numberOfValidations,
        uint256 revealDeadline,
        string requiredSkill,
        address indexed originator,
        uint256 nextValidationClaimId,
        uint256 queueHead,
        uint256 queueTail,
        uint256 minValidatorReputation
    );

    /**
     * @notice Emitted when the contributor for a contribution is updated
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @param contributor Address of the contributor
     */
    event ContributionContributorUpdated(
        bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed contributor
    );
    /**
     * @notice Emitted when the reveal deadline is updated globally
     * @param newDeadline New global reveal deadline
     */
    event RevealDeadlineUpdated(uint256 indexed newDeadline);

    /**
     * @notice Emitted when a specific index is assigned to a validator
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param index The contribution index
     * @param validator Address of the validator
     * @param deadline Timestamp when the assignment expires
     */
    event IndexAssignedToValidator(
        bytes32 indexed projectId, uint256 indexed claimId, uint256 indexed index, address validator, uint256 deadline
    );

    /**
     * @notice Emitted when a validator's capacity is updated
     * @param validator Address of the validator
     * @param oldCapacity Previous capacity
     * @param newCapacity New capacity
     */
    event ValidatorCapacityUpdated(address indexed validator, uint256 indexed oldCapacity, uint256 indexed newCapacity);

    /**
     * @notice Emitted when a validator is slashed for an expired claim
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param validator Address of the validator
     * @param slashAmount Amount slashed
     */
    event ValidatorSlashedForExpiredClaim(
        bytes32 indexed projectId, uint256 indexed claimId, address indexed validator, uint256 slashAmount
    );

    /**
     * @notice Emitted when an expired commitment is cancelled and slashed
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @param validator Address of the validator
     * @param slashAmount Amount slashed
     */
    event ExpiredCommitmentCancelled(
        bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed validator, uint256 slashAmount
    );

    /**
     * @notice Emitted when a validation claim expires
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param validator Address of the validator
     */
    event ValidationClaimExpired(bytes32 indexed projectId, uint256 indexed claimId, address indexed validator);

    // ============================================
    // ERRORS
    // ============================================

    error InvalidAddress();
    error InvalidDeadline();
    error AlreadyCommitted(address validator);
    error NoUnrevealedCommit();
    error InvalidCommitHash();
    error InvalidStakeAmount();
    error AlreadyClaimed(address validator);
    error ClaimExpired();
    error NoClaimAvailable();
    error MissingRequiredSkill(address user, string requiredSkill);
    error InsufficientValidatorReputation(address validator, uint256 required, uint256 actual);
    error StakeBelowMinimum(uint256 provided, uint256 minimum);
    error StakeExceedsCapacity(uint256 provided, uint256 available);
    error BatchSizeTooLarge(uint256 provided, uint256 max);
    error MaxValidatorClaimsPerProjectExceeded(address validator, bytes32 projectId, uint256 max);
    error InvalidNumberOfValidations(uint256 provided);
    error ReputationOutOfRange(uint256 provided, uint256 max);
    error ProjectNotRegistered(bytes32 projectId);
    error CapacityUnchanged(uint256 current);

    // ============================================
    // CORE FUNCTIONS
    // ============================================

    /**
     * @notice Claim a single validation slot in a project
     * @dev Option B: Validators can only claim one slot at a time to prevent queue slot starvation
     * @param projectId Unique identifier for the project
     * @return claimId Unique identifier for the created validation claim
     */
    function claimToValidate(bytes32 projectId) external returns (uint256 claimId);

    /**
     * @notice Enqueue a contribution index for validation (called by SapienCore on submission)
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index of the submitted contribution
     * @param submittedAt The timestamp when the contribution was submitted
     */
    function enqueueValidation(bytes32 projectId, uint256 contributionIndex, uint256 submittedAt) external;

    /**
     * @notice Get the number of validations currently pending in the queue
     * @param projectId Unique identifier for the project
     * @return count Number of pending validation slots
     */
    function getPendingValidationCount(bytes32 projectId) external view returns (uint256);

    /**
     * @notice Check if a specific validator is assigned to a specific contribution index
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index of the contribution
     * @param validator Address of the validator
     * @return isAssigned True if assigned and not expired
     */
    function isValidatorAssigned(bytes32 projectId, uint256 contributionIndex, address validator)
        external
        view
        returns (bool);

    /**
     * @notice Cancel a validation claim that has passed its deadline
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     */
    function cancelExpiredValidationClaim(bytes32 projectId, uint256 claimId) external;

    /**
     * @notice Commit a validation score hash with minimum stake (backward compatible)
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the validation claim
     * @param contributionIndex The index within the project's contribution sequence
     * @param commitHash keccak256(score, stakeAmount, salt) - stakeAmount will be minimum required
     */
    function commitValidation(bytes32 projectId, uint256 claimId, uint256 contributionIndex, bytes32 commitHash)
        external;

    /**
     * @notice Commit a validation score hash with variable stake amount (confidence-based)
     * @dev Validators can stake more to signal higher confidence in their score
     *      Higher stake = more weight in consensus, more reward if accurate, more slash if outlier
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the validation claim
     * @param contributionIndex The index within the project's contribution sequence
     * @param stakeAmount Amount to stake for this validation (must be >= minimum, <= capacity)
     * @param commitHash keccak256(score, stakeAmount, salt)
     */
    function commitValidationWithStake(
        bytes32 projectId,
        uint256 claimId,
        uint256 contributionIndex,
        uint256 stakeAmount,
        bytes32 commitHash
    ) external;

    /**
     * @notice Commit multiple validation score hashes with minimum stake (backward compatible)
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the validation claim
     * @param contributionIndices The indices within the project's contribution sequence
     * @param commitHashes Array of keccak256(score, stakeAmount, salt)
     */
    function batchCommitValidations(
        bytes32 projectId,
        uint256 claimId,
        uint256[] calldata contributionIndices,
        bytes32[] calldata commitHashes
    ) external;

    /**
     * @notice Commit multiple validation score hashes with variable stake amounts
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the validation claim
     * @param contributionIndices The indices within the project's contribution sequence
     * @param stakeAmounts Array of stake amounts for each validation
     * @param commitHashes Array of keccak256(score, stakeAmount, salt)
     */
    function batchCommitValidationsWithStake(
        bytes32 projectId,
        uint256 claimId,
        uint256[] calldata contributionIndices,
        uint256[] calldata stakeAmounts,
        bytes32[] calldata commitHashes
    ) external;

    /**
     * @notice Reveal a committed validation score
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @param score The validation score (0-10000)
     * @param salt The salt used in the commit
     */
    function revealValidation(bytes32 projectId, uint256 contributionIndex, uint256 score, bytes32 salt) external;

    /**
     * @notice Reveal multiple committed validation scores
     * @param projectId Unique identifier for the project
     * @param contributionIndices The indices within the project's contribution sequence
     * @param scores The validation scores (0-10000)
     * @param salts The salts used in the commits
     */
    function batchRevealValidations(
        bytes32 projectId,
        uint256[] calldata contributionIndices,
        uint256[] calldata scores,
        bytes32[] calldata salts
    ) external;

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Calculate consensus for a contribution
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @return report Final consensus report containing average, count, and slashes
     */
    function getConsensus(bytes32 projectId, uint256 contributionIndex)
        external
        view
        returns (ConsensusReport memory report);

    /**
     * @notice Get the consensus algorithm implementation for a project
     * @param projectId Unique identifier for the project
     * @return The consensus algorithm contract
     */
    function getAlgorithm(bytes32 projectId) external view returns (IConsensusAlgorithm);

    /**
     * @notice Get all revealed validations for a contribution
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @return Array of revealed validation structs
     */
    function getValidations(bytes32 projectId, uint256 contributionIndex) external view returns (Validation[] memory);

    // ============================================
    // REGISTRY FUNCTIONS
    // ============================================

    /**
     * @notice Register a new project and its configuration
     * @param projectId Unique identifier for the project
     * @param numberOfValidations Exact number of validations required per contribution
     * @param requiredSkill Specific skill required for validators
     * @param originator Address of the project creator
     */
    function registerProject(
        bytes32 projectId,
        uint256 numberOfValidations,
        string calldata requiredSkill,
        address originator
    ) external;

    /**
     * @notice Register a new consensus algorithm implementation
     * @param name Name of the algorithm (e.g., "LinearStake", "SqrtStake")
     * @param implementation Address of the algorithm contract implementing IConsensusAlgorithm
     */
    function registerAlgorithm(string calldata name, address implementation) external;

    /**
     * @notice Set the consensus algorithm for a project
     * @param projectId Unique identifier for the project
     * @param algorithmName Registered name of the consensus algorithm
     */
    function setProjectAlgorithm(bytes32 projectId, string calldata algorithmName) external;

    /**
     * @notice Set the number of validations required for a project
     * @param projectId Unique identifier for the project
     * @param numberOfValidations Exact number of validations required per contribution
     */
    function setProjectNumberOfValidations(bytes32 projectId, uint256 numberOfValidations) external;

    /**
     * @notice Set the required skill for a project
     * @param projectId Unique identifier for the project
     * @param requiredSkill Name of the required skill
     */
    function setProjectRequiredSkill(bytes32 projectId, string calldata requiredSkill) external;

    /**
     * @notice Set the specific reveal deadline for a project
     * @param projectId Unique identifier for the project
     * @param revealDeadline Time in seconds validators have to reveal their scores
     */
    function setProjectRevealDeadline(bytes32 projectId, uint256 revealDeadline) external;

    /**
     * @notice Set the originator address for a project
     * @param projectId Unique identifier for the project
     * @param originator Address of the project creator
     */
    function setProjectOriginator(bytes32 projectId, address originator) external;

    /**
     * @notice Set the minimum validator reputation required to validate contributions in a project
     * @dev Higher reputation requirements create "premium" validation tiers for high-value projects
     * @param projectId Unique identifier for the project
     * @param minReputation Minimum reputation score (0-10000, where 5000 is default)
     */
    function setProjectMinValidatorReputation(bytes32 projectId, uint256 minReputation) external;

    /**
     * @notice Record the contributor of a specific contribution
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @param contributor Address of the worker who submitted the contribution
     */
    function setContributionContributor(bytes32 projectId, uint256 contributionIndex, address contributor) external;

    /**
     * @notice Cancel an expired commitment and slash the validator
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @param validator Address of the validator to be slashed
     */
    function cancelExpiredCommitment(bytes32 projectId, uint256 contributionIndex, address validator) external;

    /**
     * @notice Set the global default reveal deadline
     * @param _newDeadline Default time in seconds for reveal period
     */
    function setRevealDeadline(uint256 _newDeadline) external;

    /**
     * @notice Set the maximum validation capacity for the caller
     * @param amount The total amount of SAPIEN to lock for validation capacity
     */
    function setValidatorCapacity(uint256 amount) external;

    /**
     * @notice Get the available validation capacity for a validator
     * @param validator The validator address
     * @return available The amount of capacity available for new validations
     */
    function getAvailableCapacity(address validator) external view returns (uint256);

    /**
     * @notice Get the default algorithm identifier
     * @return The default algorithm bytes32 identifier
     */
    function defaultAlgorithm() external view returns (bytes32);

    /**
     * @notice Get validation commits for a contribution
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @return Array of validation commits
     */
    function getValidationCommits(bytes32 projectId, uint256 contributionIndex)
        external
        view
        returns (ValidationCommit[] memory);

    /**
     * @notice Handle slashing of a validator after consensus (called by SapienCore)
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @param validator The validator being slashed
     * @param slashAmount The amount being slashed
     */
    function handleValidatorSlash(bytes32 projectId, uint256 contributionIndex, address validator, uint256 slashAmount)
        external;

    /**
     * @notice Reset the state of a contribution (called by SapienCore on rejection/re-queue)
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     */
    function resetContributionState(bytes32 projectId, uint256 contributionIndex) external;
}
