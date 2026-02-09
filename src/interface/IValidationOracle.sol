// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISharedTypes} from "./ISharedTypes.sol";
import {IConsensusAlgorithm} from "./IConsensusAlgorithm.sol";

/**
 * @title IValidationOracle
 * @notice Stateless consensus oracle for Sapien V2
 * @dev Manages the commit-reveal process and consensus calculations
 */
interface IValidationOracle is ISharedTypes {
    // Structs for State Grouping
    struct ProjectSettings {
        bytes32 algorithm;
        uint256 maxValidations;
        uint256 minValidations;
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

    event ValidationClaimed(
        bytes32 indexed projectId, uint256 indexed claimId, address indexed validator, uint256 deadline
    );
    event ValidationCommitted(
        bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed validator, bytes32 commitHash
    );
    event ValidationRevealed(
        bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed validator, uint256 score
    );
    event ConsensusReached(
        bytes32 indexed projectId, uint256 indexed contributionIndex, uint256 weightedAverage, uint256 validatorCount
    );
    event AlgorithmRegistered(string name, address implementation);
    event ProjectStateChange(
        bytes32 indexed projectId,
        bytes32 algorithm,
        uint256 maxValidations,
        uint256 minValidations,
        uint256 revealDeadline,
        string requiredSkill,
        address originator,
        uint256 nextValidationClaimId,
        uint256 queueHead,
        uint256 queueTail,
        uint256 minValidatorReputation
    );
    event ContributionContributorUpdated(bytes32 indexed projectId, uint256 contributionIndex, address contributor);
    event RevealDeadlineUpdated(uint256 newDeadline);
    event IndexAssignedToValidator(
        bytes32 indexed projectId, uint256 indexed claimId, uint256 indexed index, address validator
    );
    event ValidatorCapacityUpdated(address indexed validator, uint256 newCapacity);
    event ValidatorSlashedForExpiredClaim(
        bytes32 indexed projectId, uint256 indexed claimId, address indexed validator, uint256 slashAmount
    );

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
     * @param maxValidations Maximum validations allowed for this project's contributions
     * @param requiredSkill Specific skill required for validators
     * @param originator Address of the project creator
     */
    function registerProject(
        bytes32 projectId,
        uint256 maxValidations,
        uint256 minValidations,
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
     * @notice Set the maximum validations allowed for a project
     * @param projectId Unique identifier for the project
     * @param maxValidations Maximum number of validators allowed per contribution
     */
    function setProjectMaxValidations(bytes32 projectId, uint256 maxValidations) external;

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
