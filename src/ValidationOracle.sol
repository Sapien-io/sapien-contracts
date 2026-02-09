// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {IValidationOracle} from "./interface/IValidationOracle.sol";
import {ISapienTrust} from "./interface/ISapienTrust.sol";
import {ISapienVault} from "./interface/ISapienVault.sol";
import {IConsensusAlgorithm} from "./interface/IConsensusAlgorithm.sol";
import {
    VALIDATOR_ROLE,
    SAPIEN_CORE_ROLE,
    UNAUTHORIZED_MISSING_VALIDATOR_ROLE,
    UNAUTHORIZED_MISSING_CORE_ROLE,
    UNAUTHORIZED_NOT_PROJECT_ORIGINATOR,
    UNAUTHORIZED_NOT_CLAIM_OWNER,
    UNAUTHORIZED_NO_ASSIGNMENT,
    UNAUTHORIZED_INSUFFICIENT_STAKE,
    UNAUTHORIZED_INSUFFICIENT_AVAILABLE_STAKE,
    UNAUTHORIZED_CANNOT_REDUCE_BELOW_INFLIGHT,
    UNAUTHORIZED_ORIGINATOR_CANNOT_VALIDATE,
    UNAUTHORIZED_CONTRIBUTOR_CANNOT_VALIDATE,
    UNAUTHORIZED_ARRAY_LENGTH_MISMATCH,
    UNAUTHORIZED_CLAIM_NOT_EXPIRED
} from "./interface/ISharedTypes.sol";

/**
 * @title ValidationOracle
 * @notice Stateless consensus oracle for Sapien V2
 * @dev Manages commit-reveal validation and pluggable consensus algorithms.
 *      Hierarchy: Oracle -> Trust -> Vault. No dependency on SapienCore.
 */
contract ValidationOracle is IValidationOracle, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    // ============================================
    // STATE VARIABLES
    // ============================================

    /// @notice The SapienTrust contract for reputation and role checks
    ISapienTrust public trust;

    /// @notice The SapienVault contract for staking operations
    ISapienVault public vault;

    /// @notice Global default reveal deadline in seconds (time validators have to reveal after commit)
    uint256 public revealDeadline;

    /// @notice Duration for validation claim deadline (1 hour)
    uint256 public constant CLAIM_DURATION = 1 hours;

    /// @notice Minimum reveal deadline to prevent malicious deadline shortening attacks
    uint256 public constant MIN_REVEAL_DEADLINE = 1 hours;

    // Algorithm Registry
    /// @notice Mapping from algorithm name hash to algorithm implementation address
    /// @dev algorithmNameHash => implementation address
    mapping(bytes32 => address) public algorithms;

    /// @notice Default algorithm identifier used when project doesn't specify one
    bytes32 public defaultAlgorithm;

    // Consolidated State Mappings
    /// @notice Project-specific settings and configuration
    /// @dev projectId => ProjectSettings struct
    mapping(bytes32 => ProjectSettings) public projectSettings;

    /// @notice Contribution state tracking
    /// @dev projectId => contributionIndex => ContributionState struct
    mapping(bytes32 => mapping(uint256 => ContributionState)) public contributionStates;

    /// @notice Validator state including capacity and in-flight stake
    /// @dev validator => ValidatorState struct
    mapping(address => ValidatorState) public validatorStates;

    /// @notice Assignment state for validators assigned to contributions
    /// @dev projectId => contributionIndex => validator => AssignmentState struct
    mapping(bytes32 => mapping(uint256 => mapping(address => AssignmentState))) private assignments;

    /// @notice Queue of pending validation slots (FIFO)
    /// @dev projectId => queueIndex => contributionIndex
    mapping(bytes32 => mapping(uint256 => uint256)) public pendingQueue;

    // Validation Storage (kept separate as they are the core data)
    /// @notice Validation claims by validators
    /// @dev projectId => claimId => ValidationClaim struct
    mapping(bytes32 => mapping(uint256 => ValidationClaim)) public validationClaims;

    /// @notice Validation commits (internal - use getValidationCommits() to access)
    /// @dev projectId => contributionIndex => ValidationCommit[] array
    mapping(bytes32 => mapping(uint256 => ValidationCommit[])) internal validationCommits;

    /// @notice Revealed validations for contributions
    /// @dev projectId => contributionIndex => Validation[] array
    mapping(bytes32 => mapping(uint256 => Validation[])) public validations;

    // Storage gap for future upgrades
    uint256[25] private __gap;

    // ============================================
    // INITIALIZER
    // ============================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the ValidationOracle contract
     * @dev Sets up protocol contracts and default algorithm
     * @param _trust Address of the SapienTrust contract
     * @param _vault Address of the SapienVault contract
     * @param _defaultAlgorithmName Name of the default consensus algorithm
     * @param _admin Address to grant DEFAULT_ADMIN_ROLE
     */
    function initialize(address _trust, address _vault, string memory _defaultAlgorithmName, address _admin)
        public
        initializer
    {
        if (_trust == address(0) || _vault == address(0) || _admin == address(0)) revert InvalidAddress();

        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        trust = ISapienTrust(_trust);
        vault = ISapienVault(_vault);
        defaultAlgorithm = keccak256(abi.encodePacked(_defaultAlgorithmName));
        revealDeadline = 3 days; // Default to 3 days
    }

    // ============================================
    // VALIDATOR FUNCTIONS
    // ============================================

    function enqueueValidation(bytes32 projectId, uint256 contributionIndex, uint256 submittedAt) external {
        if (!hasRole(SAPIEN_CORE_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_MISSING_CORE_ROLE);
        }

        // Clear previous state for this index to prevent inconsistency on re-queue
        delete validationCommits[projectId][contributionIndex];
        delete validations[projectId][contributionIndex];

        ContributionState storage cState = contributionStates[projectId][contributionIndex];
        cState.submittedAt = submittedAt;
        cState.activeClaimCount = 0;

        // TODO: Investigate the relationship between minValidations and maxValidations.
        // Currently, maxValidations determines how many queue slots are created per contribution.
        // If maxValidations > minValidations, sequential validator claims may all be assigned to
        // the same contribution index instead of being distributed across indices. Consider:
        // 1. Enforcing maxValidations == minValidations at project creation
        // 2. Using minValidations instead of maxValidations for queue slot creation
        // 3. Implementing a more sophisticated queue assignment algorithm
        uint256 max = _getMaxValidators(projectId);
        ProjectSettings storage settings = projectSettings[projectId];
        for (uint256 i = 0; i < max; i++) {
            pendingQueue[projectId][settings.queueTail] = contributionIndex;
            settings.queueTail++;
        }
    }

    /**
     * @notice Claim a single validation slot in a project
     * @dev Validators can only claim one slot at a time to prevent queue slot starvation
     *      This ensures fair distribution and prevents validators from hoarding queue slots
     * @param projectId Unique identifier for the project
     * @return claimId Unique identifier for the created validation claim
     */
    function claimToValidate(bytes32 projectId) external returns (uint256 claimId) {
        if (!trust.hasValidRole(msg.sender, VALIDATOR_ROLE)) revert Unauthorized(UNAUTHORIZED_MISSING_VALIDATOR_ROLE);
        if (!trust.hasRequiredStake(msg.sender)) revert Unauthorized(UNAUTHORIZED_INSUFFICIENT_STAKE);

        uint256 requiredStake = _getRequiredValidatorStake(projectId);
        ValidatorState storage vState = validatorStates[msg.sender];

        // Calculate available capacity (accounting for in-flight stake)
        uint256 availableCapacity = vState.capacity > vState.inFlightStake ? vState.capacity - vState.inFlightStake : 0;

        // Ensure validator has sufficient available capacity for one validation
        if (availableCapacity < requiredStake) {
            revert InsufficientCapacity();
        }

        // Check for required skill
        ProjectSettings storage settings = projectSettings[projectId];
        string memory requiredSkill = settings.requiredSkill;
        if (bytes(requiredSkill).length > 0) {
            if (!trust.hasValidatedSkill(msg.sender, requiredSkill)) {
                revert MissingRequiredSkill(msg.sender, requiredSkill);
            }
        }

        // Check for minimum reputation requirement (eligibility tier)
        if (settings.minValidatorReputation > 0) {
            uint256 validatorRep = trust.getTrustScore(msg.sender, VALIDATOR_ROLE);
            if (validatorRep < settings.minValidatorReputation) {
                revert InsufficientValidatorReputation(msg.sender, settings.minValidatorReputation, validatorRep);
            }
        }

        // Check queue availability
        uint256 available = settings.queueTail - settings.queueHead;
        if (available == 0) revert CapacityReached();

        claimId = settings.nextValidationClaimId++;
        uint256 deadline = block.timestamp + CLAIM_DURATION;

        // Option B: Always claim exactly 1 slot
        uint256 quantity = 1;

        // Assign single index from queue
        uint256 index = pendingQueue[projectId][settings.queueHead];
        settings.queueHead++;

        validationClaims[projectId][claimId] = ValidationClaim({
            validator: msg.sender,
            quantity: quantity,
            contributionIndex: index, // Fix: Store the contribution index
            claimedAt: block.timestamp,
            deadline: deadline,
            committedCount: 0,
            status: ClaimStatus.Active
        });

        AssignmentState storage assignment = assignments[projectId][index][msg.sender];
        assignment.deadline = deadline;
        assignment.hasCommitted = false;
        assignment.committedStake = 0;

        emit IndexAssignedToValidator(projectId, claimId, index, msg.sender);
        emit ValidationClaimed(projectId, claimId, msg.sender, deadline);
    }

    /**
     * @notice Set the maximum validation capacity for the caller
     * @dev Locks the specified amount in the vault to enable validation without per-commit locks
     * @param amount The total amount of SAPIEN to lock for validation capacity
     */
    function setValidatorCapacity(uint256 amount) external nonReentrant {
        if (!trust.hasValidRole(msg.sender, VALIDATOR_ROLE)) revert Unauthorized(UNAUTHORIZED_MISSING_VALIDATOR_ROLE);

        ValidatorState storage vState = validatorStates[msg.sender];
        uint256 currentCapacity = vState.capacity;
        if (amount == currentCapacity) return;

        // CEI Pattern: Effects (state changes) before Interactions (external calls)
        vState.capacity = amount;

        // Interactions (external calls) after state changes
        if (amount > currentCapacity) {
            uint256 diff = amount - currentCapacity;
            // Check that validator has enough available stake to lock
            uint256 availableStake = vault.getAvailableStake(msg.sender);
            if (diff > availableStake) revert Unauthorized(UNAUTHORIZED_INSUFFICIENT_AVAILABLE_STAKE);
            vault.lockStake(msg.sender, diff, "increase_capacity");
        } else {
            // Check if reducing capacity below in-flight stake
            if (amount < vState.inFlightStake) revert Unauthorized(UNAUTHORIZED_CANNOT_REDUCE_BELOW_INFLIGHT);
            uint256 diff = currentCapacity - amount;
            vault.unlockStake(msg.sender, diff, "decrease_capacity");
        }
        emit ValidatorCapacityUpdated(msg.sender, amount);
    }

    /**
     * @notice Get the number of validations currently pending in the queue
     * @param projectId Unique identifier for the project
     * @return count Number of pending validation slots
     */
    function getPendingValidationCount(bytes32 projectId) external view returns (uint256) {
        ProjectSettings storage settings = projectSettings[projectId];
        return settings.queueTail - settings.queueHead;
    }

    /**
     * @notice Get the available validation capacity for a validator
     * @param validator The validator address
     * @return available The amount of capacity available for new validations
     */
    function getAvailableCapacity(address validator) external view returns (uint256) {
        ValidatorState storage vState = validatorStates[validator];
        uint256 capacity = vState.capacity;
        uint256 inFlight = vState.inFlightStake;
        return capacity > inFlight ? capacity - inFlight : 0;
    }

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
        returns (bool)
    {
        uint256 deadline = assignments[projectId][contributionIndex][validator].deadline;
        return deadline > 0 && block.timestamp <= deadline;
    }

    /**
     * @notice Cancel a validation claim that has passed its deadline
     * @dev Can be called by anyone after the claim deadline has passed, or by the validator themselves at any time.
     *      Slashes the validator for any uncommitted validations (quantity - committedCount) and reduces their capacity.
     *      Updates validator reputation negatively for not fulfilling obligations.
     *      Follows CEI pattern: state changes before external calls.
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the validation claim to cancel
     * @custom:reverts NoClaimAvailable If the claim is not in Active status
     * @custom:reverts Unauthorized If called before deadline by someone other than the validator
     * @custom:emits ValidatorSlashedForExpiredClaim If there are uncommitted validations to slash
     */
    // TODO: Should there be a reward for the wallet that calls this?
    function cancelExpiredValidationClaim(bytes32 projectId, uint256 claimId) external nonReentrant {
        ValidationClaim storage claim = validationClaims[projectId][claimId];
        if (claim.status != ClaimStatus.Active) revert NoClaimAvailable();

        if (block.timestamp <= claim.deadline && msg.sender != claim.validator) {
            revert Unauthorized(UNAUTHORIZED_CLAIM_NOT_EXPIRED);
        }

        // Slash validator for uncommitted validations
        uint256 uncommittedCount = claim.quantity - claim.committedCount;

        // Mark claim as expired before external calls (CEI pattern)
        claim.status = ClaimStatus.Expired;

        if (uncommittedCount > 0) {
            uint256 stakePerValidation = _getRequiredValidatorStake(projectId);
            uint256 totalSlashAmount = uncommittedCount * stakePerValidation;

            ValidatorState storage vState = validatorStates[claim.validator];

            // CEI Pattern: Effects (state changes) before Interactions (external calls)
            // Reduce capacity by the slashed amount
            if (vState.capacity >= totalSlashAmount) {
                vState.capacity -= totalSlashAmount;
            } else {
                vState.capacity = 0;
            }

            // Re-queue the contribution index (Liveness Fix)
            ProjectSettings storage settings = projectSettings[projectId];
            pendingQueue[projectId][settings.queueTail] = claim.contributionIndex;
            settings.queueTail++;

            // Interactions (external calls) after state changes
            // Slash from vault (stake is already locked)
            vault.slash(claim.validator, totalSlashAmount, projectId);

            // Update reputation for not fulfilling obligations
            trust.updateReputation(claim.validator, VALIDATOR_ROLE, false, 0);

            emit ValidatorSlashedForExpiredClaim(projectId, claimId, claim.validator, totalSlashAmount);
        }
    }

    /**
     * @notice Commit a validation score hash with minimum stake (backward compatible)
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the validation claim
     * @param contributionIndex The index within the project's contribution sequence
     * @param commitHash keccak256(score, stakeAmount, salt)
     */
    function commitValidation(bytes32 projectId, uint256 claimId, uint256 contributionIndex, bytes32 commitHash)
        external
    {
        uint256 minStake = _getRequiredValidatorStake(projectId);
        _commitValidationWithStake(projectId, claimId, contributionIndex, minStake, commitHash);
    }

    /**
     * @notice Commit a validation score hash with variable stake amount (confidence-based)
     * @dev Validators can stake more to signal higher confidence in their score
     *      Higher stake = more weight in consensus, more reward if accurate, more slash if outlier
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the validation claim
     * @param contributionIndex The index within the project's contribution sequence
     * @param stakeAmount Amount to stake for this validation (must be >= minimum, <= available capacity)
     * @param commitHash keccak256(score, stakeAmount, salt)
     */
    function commitValidationWithStake(
        bytes32 projectId,
        uint256 claimId,
        uint256 contributionIndex,
        uint256 stakeAmount,
        bytes32 commitHash
    ) external {
        _commitValidationWithStake(projectId, claimId, contributionIndex, stakeAmount, commitHash);
    }

    /**
     * @notice Commit multiple validation score hashes with minimum stake (backward compatible)
     */
    function batchCommitValidations(
        bytes32 projectId,
        uint256 claimId,
        uint256[] calldata contributionIndices,
        bytes32[] calldata commitHashes
    ) external {
        if (contributionIndices.length != commitHashes.length) {
            revert Unauthorized(UNAUTHORIZED_ARRAY_LENGTH_MISMATCH);
        }
        uint256 minStake = _getRequiredValidatorStake(projectId);
        for (uint256 i = 0; i < contributionIndices.length; i++) {
            _commitValidationWithStake(projectId, claimId, contributionIndices[i], minStake, commitHashes[i]);
        }
    }

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
    ) external {
        if (contributionIndices.length != commitHashes.length || contributionIndices.length != stakeAmounts.length) {
            revert Unauthorized(UNAUTHORIZED_ARRAY_LENGTH_MISMATCH);
        }
        for (uint256 i = 0; i < contributionIndices.length; i++) {
            _commitValidationWithStake(projectId, claimId, contributionIndices[i], stakeAmounts[i], commitHashes[i]);
        }
    }

    /**
     * @dev Internal function to commit a validation score hash with specified stake amount
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the validation claim
     * @param contributionIndex The index within the project's contribution sequence
     * @param stakeAmount Amount to stake for this validation
     * @param commitHash keccak256(score, stakeAmount, salt)
     */
    function _commitValidationWithStake(
        bytes32 projectId,
        uint256 claimId,
        uint256 contributionIndex,
        uint256 stakeAmount,
        bytes32 commitHash
    ) internal {
        ValidationClaim storage claim = validationClaims[projectId][claimId];
        if (claim.validator != msg.sender) revert Unauthorized(UNAUTHORIZED_NOT_CLAIM_OWNER);
        if (claim.status != ClaimStatus.Active) revert ClaimNotActive(claimId);
        if (block.timestamp > claim.deadline) revert ClaimAlreadyExpired(claimId, claim.deadline);

        // Verify assignment
        AssignmentState storage assignment = assignments[projectId][contributionIndex][msg.sender];
        if (assignment.deadline == 0) revert Unauthorized(UNAUTHORIZED_NO_ASSIGNMENT);
        if (block.timestamp > assignment.deadline) {
            revert ClaimAlreadyExpired(claimId, assignment.deadline);
        }

        // 1. Verify Validator Role & Stake
        if (!trust.hasValidRole(msg.sender, VALIDATOR_ROLE)) revert Unauthorized(UNAUTHORIZED_MISSING_VALIDATOR_ROLE);
        if (!trust.hasRequiredStake(msg.sender)) revert Unauthorized(UNAUTHORIZED_INSUFFICIENT_STAKE);

        // Sybil Protection: Originator and Contributor cannot validate
        ProjectSettings storage settings = projectSettings[projectId];
        if (msg.sender == settings.originator) revert Unauthorized(UNAUTHORIZED_ORIGINATOR_CANNOT_VALIDATE);
        if (msg.sender == contributionStates[projectId][contributionIndex].contributor) {
            revert Unauthorized(UNAUTHORIZED_CONTRIBUTOR_CANNOT_VALIDATE);
        }

        // 2. Prevent Duplicate Commits (for this attempt)
        if (assignment.hasCommitted) revert AlreadyCommitted(msg.sender);

        // 3. Validate stake amount
        uint256 minStake = _getRequiredValidatorStake(projectId);
        if (stakeAmount < minStake) {
            revert StakeBelowMinimum(stakeAmount, minStake);
        }

        // 4. Check Capacity - validator must have enough available capacity for this stake
        ValidatorState storage vState = validatorStates[msg.sender];
        uint256 availableCapacity = vState.capacity > vState.inFlightStake ? vState.capacity - vState.inFlightStake : 0;
        if (stakeAmount > availableCapacity) {
            revert StakeExceedsCapacity(stakeAmount, availableCapacity);
        }

        // 5. Record Commit and update in-flight stake
        assignment.hasCommitted = true;
        assignment.committedStake = stakeAmount;
        vState.inFlightStake += stakeAmount;
        contributionStates[projectId][contributionIndex].activeClaimCount++;
        claim.committedCount++;

        if (claim.committedCount == claim.quantity) {
            claim.status = ClaimStatus.Fulfilled;
        }

        // Snapshot the reveal deadline at commit time to prevent retroactive shortening (M-2 fix)
        uint256 deadlineSnapshot = settings.revealDeadline;
        if (deadlineSnapshot == 0) deadlineSnapshot = revealDeadline;

        validationCommits[projectId][contributionIndex].push(
            ValidationCommit({
                validator: msg.sender,
                commitHash: commitHash,
                committedAt: block.timestamp,
                revealDeadlineSnapshot: deadlineSnapshot,
                revealed: false
            })
        );

        emit ValidationCommitted(projectId, contributionIndex, msg.sender, commitHash);
    }

    function revealValidation(bytes32 projectId, uint256 contributionIndex, uint256 score, bytes32 salt) external {
        _revealValidation(projectId, contributionIndex, score, salt);
    }

    function batchRevealValidations(
        bytes32 projectId,
        uint256[] calldata contributionIndices,
        uint256[] calldata scores,
        bytes32[] calldata salts
    ) external {
        if (contributionIndices.length != scores.length || contributionIndices.length != salts.length) {
            revert Unauthorized(UNAUTHORIZED_ARRAY_LENGTH_MISMATCH);
        }
        for (uint256 i = 0; i < contributionIndices.length; i++) {
            _revealValidation(projectId, contributionIndices[i], scores[i], salts[i]);
        }
    }

    /**
     * @dev Internal function to reveal a committed validation score
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @param score The validation score (0-10000)
     * @param salt The salt used in the commit
     */
    function _revealValidation(bytes32 projectId, uint256 contributionIndex, uint256 score, bytes32 salt) internal {
        ValidationCommit[] storage commits = validationCommits[projectId][contributionIndex];

        // Find validator's commit
        uint256 commitIndex = type(uint256).max;
        for (uint256 i = 0; i < commits.length; i++) {
            if (commits[i].validator == msg.sender && !commits[i].revealed) {
                commitIndex = i;
                break;
            }
        }
        if (commitIndex == type(uint256).max) revert NoUnrevealedCommit();

        ValidationCommit storage commit = commits[commitIndex];

        // 1. Verify Deadline using the snapshot stored at commit time (M-2 fix)
        // This prevents retroactive deadline shortening attacks where an originator
        // changes the deadline after validators have already committed.
        uint256 deadline = commit.revealDeadlineSnapshot;
        // Fallback for legacy commits that may not have a snapshot
        if (deadline == 0) {
            ProjectSettings storage settings = projectSettings[projectId];
            deadline = settings.revealDeadline;
            if (deadline == 0) deadline = revealDeadline;
        }
        if (block.timestamp > commit.committedAt + deadline) {
            revert("Reveal deadline passed");
        }

        AssignmentState storage assignment = assignments[projectId][contributionIndex][msg.sender];
        uint256 stakeAmount = assignment.committedStake;

        // 2. Verify Commit Hash
        if (commit.commitHash != keccak256(abi.encodePacked(score, stakeAmount, salt))) revert InvalidCommitHash();

        // 3. Validate Score (fail-fast to prevent permanent DoS)
        // Score must be <= 10000 (0-100%). This validation prevents invalid scores from being
        // stored, which would cause consensus calculation to revert and permanently block finalization.
        if (score > 10000) revert IConsensusAlgorithm.InvalidScore(score);

        // 4. Release in-flight stake (capacity remains locked, but this validation is no longer "in flight")
        ValidatorState storage vState = validatorStates[msg.sender];
        if (vState.inFlightStake < stakeAmount) {
            revert InvalidStakeAmount(); // Underflow protection
        }
        vState.inFlightStake -= stakeAmount;

        // 5. Record Validation
        commit.revealed = true;
        validations[projectId][contributionIndex].push(
            Validation({
                projectId: projectId,
                validator: msg.sender,
                contributionIndex: contributionIndex,
                score: score,
                stakeAmount: stakeAmount,
                submittedAt: block.timestamp,
                rewarded: false,
                slashed: false
            })
        );

        emit ValidationRevealed(projectId, contributionIndex, msg.sender, score);
    }

    // ============================================
    // VIEW FUNCTIONS (CONSENSUS)
    // ============================================

    function getConsensus(bytes32 projectId, uint256 contributionIndex)
        external
        view
        returns (ConsensusReport memory report)
    {
        uint256 submittedAt = contributionStates[projectId][contributionIndex].submittedAt;
        if (submittedAt == 0) return report;

        uint256 minValidations = projectSettings[projectId].minValidations;
        (bool ready, uint256 validCount) =
            _checkConsensusReady(projectId, contributionIndex, minValidations, submittedAt);
        if (!ready) {
            report.validatorCount = validCount;
            return report;
        }

        // Get algorithm
        IConsensusAlgorithm algo = getAlgorithm(projectId);

        // Prepare inputs (O(validCount))
        IConsensusAlgorithm.ValidationInput[] memory inputs =
            _prepareValidationInputs(projectId, contributionIndex, submittedAt, validCount);

        // Calculate
        IConsensusAlgorithm.ConsensusResult memory result = algo.calculateConsensus(inputs);

        // Add expired commits to slash list
        (address[] memory allSlash, uint256[] memory allAmounts) = _appendExpiredSlashes(
            projectId, contributionIndex, submittedAt, result.validatorsToSlash, result.slashAmounts
        );

        return ConsensusReport({
            weightedAverage: result.weightedAverage,
            validatorCount: validCount,
            isReady: true,
            validatorsToSlash: allSlash,
            slashAmounts: allAmounts,
            validatorWeights: result.validatorWeights
        });
    }

    /**
     * @dev Check if a validation commit is expired
     * @param commit The validation commit to check
     * @param submittedAt Timestamp when the contribution was submitted
     * @param deadline Reveal deadline in seconds
     * @return true if the commit is expired and should be slashed
     */
    function _isCommitExpired(ValidationCommit memory commit, uint256 submittedAt, uint256 deadline)
        internal
        view
        returns (bool)
    {
        // Only check commits that were made after submission and haven't been revealed
        if (commit.committedAt < submittedAt || commit.revealed) {
            return false;
        }

        uint256 commitDeadline = commit.committedAt + deadline;
        return block.timestamp > commitDeadline;
    }

    /**
     * @dev Append expired commits to the slash list
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @param submittedAt Timestamp when the contribution was submitted
     * @param outliers Array of outlier validators from consensus algorithm
     * @param outlierAmounts Corresponding slash amounts for outliers
     * @return toSlash Combined array of validators to slash
     * @return slashAmounts Combined array of slash amounts
     */
    function _appendExpiredSlashes(
        bytes32 projectId,
        uint256 contributionIndex,
        uint256 submittedAt,
        address[] memory outliers,
        uint256[] memory outlierAmounts
    ) internal view returns (address[] memory toSlash, uint256[] memory slashAmounts) {
        ValidationCommit[] storage commits = validationCommits[projectId][contributionIndex];
        ProjectSettings storage settings = projectSettings[projectId];
        uint256 deadline = settings.revealDeadline;
        if (deadline == 0) deadline = revealDeadline;

        // Count expired
        uint256 expiredCount = 0;
        for (uint256 i = 0; i < commits.length; i++) {
            if (_isCommitExpired(commits[i], submittedAt, deadline)) {
                expiredCount++;
            }
        }

        if (expiredCount == 0) return (outliers, outlierAmounts);

        // Merge
        uint256 total = outliers.length + expiredCount;
        toSlash = new address[](total);
        slashAmounts = new uint256[](total);

        for (uint256 i = 0; i < outliers.length; i++) {
            toSlash[i] = outliers[i];
            slashAmounts[i] = outlierAmounts[i];
        }

        uint256 idx = outliers.length;
        for (uint256 i = 0; i < commits.length; i++) {
            if (_isCommitExpired(commits[i], submittedAt, deadline)) {
                toSlash[idx] = commits[i].validator;
                slashAmounts[idx] = assignments[projectId][contributionIndex][commits[i].validator].committedStake;
                idx++;
            }
        }
    }

    /**
     * @dev Check if consensus is ready (enough validations and all commits revealed or expired)
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @param minValidations Minimum validations required
     * @param submittedAt Timestamp when the contribution was submitted
     * @return bool True if consensus is ready
     * @return uint256 Number of valid validations
     */
    function _checkConsensusReady(
        bytes32 projectId,
        uint256 contributionIndex,
        uint256 minValidations,
        uint256 submittedAt
    ) internal view returns (bool, uint256) {
        Validation[] storage allVals = validations[projectId][contributionIndex];

        uint256 validCount = 0;
        for (uint256 i = 0; i < allVals.length; i++) {
            if (allVals[i].submittedAt >= submittedAt) {
                validCount++;
            }
        }

        if (validCount < minValidations) return (false, validCount);

        ValidationCommit[] storage commits = validationCommits[projectId][contributionIndex];
        ProjectSettings storage settings = projectSettings[projectId];
        uint256 deadline = settings.revealDeadline;
        if (deadline == 0) deadline = revealDeadline;

        for (uint256 i = 0; i < commits.length; i++) {
            if (commits[i].committedAt >= submittedAt && !commits[i].revealed) {
                // Check if commit is NOT expired (still within deadline)
                if (!_isCommitExpired(commits[i], submittedAt, deadline)) {
                    return (false, validCount);
                }
            }
        }
        return (true, validCount);
    }

    /**
     * @dev Prepare validation inputs for consensus algorithm
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @param submittedAt Timestamp when the contribution was submitted
     * @param validCount Number of valid validations
     * @return Array of ValidationInput structs for consensus calculation
     */
    function _prepareValidationInputs(
        bytes32 projectId,
        uint256 contributionIndex,
        uint256 submittedAt,
        uint256 validCount
    ) internal view returns (IConsensusAlgorithm.ValidationInput[] memory) {
        Validation[] storage allVals = validations[projectId][contributionIndex];
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](validCount);
        uint256 inputIdx = 0;
        for (uint256 i = 0; i < allVals.length; i++) {
            if (allVals[i].submittedAt >= submittedAt) {
                inputs[inputIdx] = IConsensusAlgorithm.ValidationInput({
                    validator: allVals[i].validator,
                    score: allVals[i].score,
                    stakeAmount: allVals[i].stakeAmount,
                    reputation: trust.getTrustScore(allVals[i].validator, VALIDATOR_ROLE)
                });
                inputIdx++;
            }
        }
        return inputs;
    }

    function getValidations(bytes32 projectId, uint256 contributionIndex) external view returns (Validation[] memory) {
        return validations[projectId][contributionIndex];
    }

    function getValidationCommits(bytes32 projectId, uint256 contributionIndex)
        external
        view
        returns (ValidationCommit[] memory)
    {
        return validationCommits[projectId][contributionIndex];
    }

    function getAlgorithm(bytes32 projectId) public view returns (IConsensusAlgorithm) {
        bytes32 algoName = projectSettings[projectId].algorithm;
        if (algoName == bytes32(0)) algoName = defaultAlgorithm;

        address impl = algorithms[algoName];
        if (impl == address(0)) revert InvalidAddress();

        return IConsensusAlgorithm(impl);
    }

    // ============================================
    // REGISTRY FUNCTIONS
    // ============================================

    function registerProject(
        bytes32 projectId,
        uint256 maxValidations,
        uint256 minValidations,
        string calldata requiredSkill,
        address originator
    ) external {
        if (!hasRole(SAPIEN_CORE_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_MISSING_CORE_ROLE);
        }
        ProjectSettings storage settings = projectSettings[projectId];
        settings.maxValidations = maxValidations;
        settings.minValidations = minValidations;
        settings.requiredSkill = requiredSkill;
        settings.originator = originator;

        _emitProjectStateChange(projectId);
    }

    function registerAlgorithm(string calldata name, address implementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (implementation == address(0)) revert InvalidAddress();
        algorithms[keccak256(abi.encodePacked(name))] = implementation;
        emit AlgorithmRegistered(name, implementation);
    }

    function setProjectAlgorithm(bytes32 projectId, string calldata algorithmName) external {
        ProjectSettings storage settings = projectSettings[projectId];
        if (msg.sender != settings.originator && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_NOT_PROJECT_ORIGINATOR);
        }

        settings.algorithm = keccak256(abi.encodePacked(algorithmName));
        _emitProjectStateChange(projectId);
    }

    function setProjectMaxValidations(bytes32 projectId, uint256 maxValidations) external {
        if (!hasRole(SAPIEN_CORE_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_MISSING_CORE_ROLE);
        }
        if (maxValidations > 100) revert("Max validations cannot exceed 100");
        projectSettings[projectId].maxValidations = maxValidations;
        _emitProjectStateChange(projectId);
    }

    function setProjectRequiredSkill(bytes32 projectId, string calldata requiredSkill) external {
        if (!hasRole(SAPIEN_CORE_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_MISSING_CORE_ROLE);
        }
        projectSettings[projectId].requiredSkill = requiredSkill;
        _emitProjectStateChange(projectId);
    }

    function setProjectRevealDeadline(bytes32 projectId, uint256 deadline) external {
        ProjectSettings storage settings = projectSettings[projectId];
        if (msg.sender != settings.originator && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_NOT_PROJECT_ORIGINATOR);
        }
        // Prevent malicious deadline shortening attacks (Issue #2 fix)
        if (deadline < MIN_REVEAL_DEADLINE) revert InvalidDeadline();
        settings.revealDeadline = deadline;
        _emitProjectStateChange(projectId);
    }

    function setProjectOriginator(bytes32 projectId, address originator) external {
        if (!hasRole(SAPIEN_CORE_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_MISSING_CORE_ROLE);
        }
        projectSettings[projectId].originator = originator;
        _emitProjectStateChange(projectId);
    }

    /**
     * @notice Set the minimum validator reputation required to validate contributions in a project
     * @dev Higher reputation requirements create "premium" validation tiers for high-value projects
     *      Validators must have built trust through accurate validations to access these projects
     * @param projectId Unique identifier for the project
     * @param minReputation Minimum reputation score (0-10000, where 5000 is default, 0 = no requirement)
     */
    function setProjectMinValidatorReputation(bytes32 projectId, uint256 minReputation) external {
        ProjectSettings storage settings = projectSettings[projectId];
        if (msg.sender != settings.originator && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_NOT_PROJECT_ORIGINATOR);
        }
        if (minReputation > 10000) revert("Min reputation cannot exceed 10000");
        settings.minValidatorReputation = minReputation;
        _emitProjectStateChange(projectId);
    }

    function setContributionContributor(bytes32 projectId, uint256 contributionIndex, address contributor) external {
        if (!hasRole(SAPIEN_CORE_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_MISSING_CORE_ROLE);
        }
        contributionStates[projectId][contributionIndex].contributor = contributor;
        emit ContributionContributorUpdated(projectId, contributionIndex, contributor);
    }

    function cancelExpiredCommitment(bytes32 projectId, uint256 contributionIndex, address validator)
        external
        nonReentrant
    {
        ValidationCommit[] storage commits = validationCommits[projectId][contributionIndex];
        ProjectSettings storage settings = projectSettings[projectId];
        uint256 deadline = settings.revealDeadline;
        if (deadline == 0) deadline = revealDeadline;

        for (uint256 i = 0; i < commits.length; i++) {
            if (commits[i].validator == validator && !commits[i].revealed) {
                if (block.timestamp > commits[i].committedAt + deadline) {
                    AssignmentState storage assignment = assignments[projectId][contributionIndex][validator];
                    uint256 stake = assignment.committedStake;

                    // Release in-flight stake tracking
                    ValidatorState storage vState = validatorStates[validator];
                    if (vState.inFlightStake < stake) {
                        revert InvalidStakeAmount(); // Underflow protection
                    }
                    vState.inFlightStake -= stake;

                    // Reduce capacity by the slashed amount
                    if (vState.capacity >= stake) {
                        vState.capacity -= stake;
                    } else {
                        vState.capacity = 0;
                    }

                    // Mark as revealed BEFORE external calls to prevent double processing (CEI pattern)
                    commits[i].revealed = true;

                    // Decrement active claim count BEFORE external calls (CEI pattern)
                    if (contributionStates[projectId][contributionIndex].activeClaimCount > 0) {
                        contributionStates[projectId][contributionIndex].activeClaimCount--;
                    }

                    // Re-queue the contribution index (Liveness Fix)
                    pendingQueue[projectId][settings.queueTail] = contributionIndex;
                    settings.queueTail++;

                    // External calls after all state changes (CEI pattern)
                    // Slash from the validator's capacity (stake is already locked in vault)
                    vault.slash(validator, stake, projectId);

                    // Update reputation for not fulfilling obligations (consistent with cancelExpiredValidationClaim)
                    trust.updateReputation(validator, VALIDATOR_ROLE, false, 0);
                    return;
                }
            }
        }
        revert NoUnrevealedCommit();
    }

    /**
     * @notice Reset the state of a contribution (called by SapienCore on rejection/re-queue)
     * @dev Clears contribution metadata to allow for re-submission and re-validation
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     */
    function resetContributionState(bytes32 projectId, uint256 contributionIndex) external {
        if (!hasRole(SAPIEN_CORE_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_MISSING_CORE_ROLE);
        }

        // Clear assignments' committed status for all who committed
        ValidationCommit[] storage commits = validationCommits[projectId][contributionIndex];
        for (uint256 i = 0; i < commits.length; i++) {
            assignments[projectId][contributionIndex][commits[i].validator].hasCommitted = false;
        }

        // Clear contribution state
        delete contributionStates[projectId][contributionIndex];

        // Clear commits and validations
        delete validationCommits[projectId][contributionIndex];
        delete validations[projectId][contributionIndex];
    }

    function setRevealDeadline(uint256 _newDeadline) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newDeadline < MIN_REVEAL_DEADLINE) revert InvalidDeadline();
        revealDeadline = _newDeadline;
        emit RevealDeadlineUpdated(_newDeadline);
    }

    /**
     * @notice Handle slashing of a validator after consensus (called by SapienCore)
     * @dev Reduces the validator's capacity by the slash amount and syncs with vault's locked stake
     * @param validator The validator being slashed
     * @param slashAmount The amount being slashed
     */
    function handleValidatorSlash(bytes32 projectId, uint256 contributionIndex, address validator, uint256 slashAmount)
        external
    {
        if (!hasRole(SAPIEN_CORE_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_MISSING_CORE_ROLE);
        }

        if (slashAmount == 0) return;

        ValidatorState storage vState = validatorStates[validator];

        // If they had an unrevealed commit for this index, it was just slashed
        // We must reduce inFlightStake
        ValidationCommit[] storage commits = validationCommits[projectId][contributionIndex];
        for (uint256 i = 0; i < commits.length; i++) {
            if (commits[i].validator == validator && !commits[i].revealed) {
                commits[i].revealed = true; // Mark as processed
                if (vState.inFlightStake >= slashAmount) {
                    vState.inFlightStake -= slashAmount;
                }
                break;
            }
        }

        // Reduce capacity by the slashed amount
        if (vState.capacity >= slashAmount) {
            vState.capacity -= slashAmount;
        } else {
            vState.capacity = 0;
        }

        // Sync capacity with vault's actual locked stake (vault may have adjusted lockedStake after slash)
        uint256 vaultLockedStake = vault.getLockedStake(validator);
        if (vState.capacity > vaultLockedStake) {
            vState.capacity = vaultLockedStake;
        }

        // Also reduce in-flight stake if it exceeds capacity (shouldn't happen, but safety check)
        if (vState.inFlightStake > vState.capacity) {
            vState.inFlightStake = vState.capacity;
        }
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    /**
     * @dev Get the required stake for a validator in a project
     * @return required Minimum amount of tokens required to validate
     */
    function _getRequiredValidatorStake(bytes32) internal view returns (uint256) {
        uint256 required = trust.roleMinStake(VALIDATOR_ROLE);
        if (required == 0) required = trust.minStakeRequired();
        return required;
    }

    /**
     * @dev Get the maximum allowed validators for a project
     * @param projectId Unique identifier for the project
     * @return max Number of validators allowed per contribution (defaults to 10 if not set)
     */
    function _getMaxValidators(bytes32 projectId) internal view returns (uint256) {
        uint256 max = projectSettings[projectId].maxValidations;
        return max == 0 ? 10 : max;
    }

    /**
     * @dev Emit the complete ProjectSettings state for a project
     * @param projectId Unique identifier for the project
     */
    function _emitProjectStateChange(bytes32 projectId) internal {
        ProjectSettings storage settings = projectSettings[projectId];
        emit ProjectStateChange(
            projectId,
            settings.algorithm,
            settings.maxValidations,
            settings.minValidations,
            settings.revealDeadline,
            settings.requiredSkill,
            settings.originator,
            settings.nextValidationClaimId,
            settings.queueHead,
            settings.queueTail,
            settings.minValidatorReputation
        );
    }
}
