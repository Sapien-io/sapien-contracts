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
    UNAUTHORIZED_MISSING_CORE_ROLE,
    UNAUTHORIZED_NOT_PROJECT_ORIGINATOR,
    UNAUTHORIZED_NOT_CLAIM_OWNER,
    UNAUTHORIZED_NO_ASSIGNMENT,
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

    function _getValidationOracleStorage() private pure returns (ValidationOracleStorage storage $) {
        bytes32 slot =
            keccak256(abi.encode(uint256(keccak256("sapien.storage.ValidationOracle")) - 1)) & ~bytes32(uint256(0xff));
        assembly {
            $.slot := slot
        }
    }

    /// @notice Duration for validation claim deadline (1 hour)
    uint256 public constant CLAIM_DURATION = 1 hours;

    /// @notice Minimum reveal deadline to prevent malicious deadline shortening attacks
    uint256 public constant MIN_REVEAL_DEADLINE = 1 hours;

    /// @notice Maximum items in a single batch operation (F-12 fix)
    /// @dev Prevents DoS via gas exhaustion from unbounded loops
    uint256 public constant MAX_BATCH_SIZE = 50;

    /// @notice Maximum active validation claims per validator per project (F-10 fix)
    /// @dev Prevents a single validator from monopolizing the validation queue
    uint256 public constant MAX_ACTIVE_VALIDATOR_CLAIMS_PER_PROJECT = 3;

    // ============================================
    // MODIFIERS
    // ============================================

    modifier onlyCoreOrAdmin() {
        if (!hasRole(SAPIEN_CORE_ROLE, msg.sender) && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_MISSING_CORE_ROLE);
        }
        _;
    }

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

        ValidationOracleStorage storage $ = _getValidationOracleStorage();
        $.trust = ISapienTrust(_trust);
        $.vault = ISapienVault(_vault);
        $.defaultAlgorithm = keccak256(abi.encodePacked(_defaultAlgorithmName));
        $.revealDeadline = 3 days; // Default to 3 days
    }

    // ============================================
    // VALIDATOR FUNCTIONS
    // ============================================

    /**
     * @notice Enqueue a contribution index for validation
     * @dev Called by SapienCore on submission. Creates queue slots for validators.
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index of the submitted contribution
     * @param submittedAt The timestamp when the contribution was submitted
     */
    function enqueueValidation(bytes32 projectId, uint256 contributionIndex, uint256 submittedAt)
        external
        onlyCoreOrAdmin
    {
        ValidationOracleStorage storage $ = _getValidationOracleStorage();
        ContributionState storage cState = $.contributionStates[projectId][contributionIndex];

        // F-05/F-08 fix: Increment nonce to invalidate stale commits/validations from previous
        // submission cycles. This replaces expensive array deletions with O(1) nonce-based filtering.
        ++cState.submissionNonce;
        cState.submittedAt = submittedAt;
        cState.activeClaimCount = 0;

        uint256 numValidations = $.projectSettings[projectId].numberOfValidations;
        if (numValidations == 0) numValidations = 3; // Default fallback
        ProjectSettings storage settings = $.projectSettings[projectId];
        for (uint256 i = 0; i < numValidations; ++i) {
            $.pendingQueue[projectId][settings.queueTail] = contributionIndex;
            ++settings.queueTail;
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
        ValidationOracleStorage storage $ = _getValidationOracleStorage();
        $.trust.hasEnoughStakeForRole(msg.sender, VALIDATOR_ROLE);

        uint256 requiredStake = _getRequiredValidatorStake(projectId);
        ValidatorState storage vState = $.validatorStates[msg.sender];

        // Calculate available capacity (accounting for in-flight stake)
        uint256 availableCapacity = vState.capacity > vState.inFlightStake ? vState.capacity - vState.inFlightStake : 0;

        // Ensure validator has sufficient available capacity for one validation
        if (availableCapacity < requiredStake) {
            revert InsufficientCapacity();
        }

        // Check for required skill
        ProjectSettings storage settings = $.projectSettings[projectId];
        string memory requiredSkill = settings.requiredSkill;
        if (bytes(requiredSkill).length > 0) {
            if (!$.trust.hasValidatedSkill(msg.sender, requiredSkill)) {
                revert MissingRequiredSkill(msg.sender, requiredSkill);
            }
        }

        // Check for minimum reputation requirement (eligibility tier)
        if (settings.minValidatorReputation > 0) {
            uint256 validatorRep = $.trust.getTrustScore(msg.sender, VALIDATOR_ROLE);
            if (validatorRep < settings.minValidatorReputation) {
                revert InsufficientValidatorReputation(msg.sender, settings.minValidatorReputation, validatorRep);
            }
        }

        // F-10 fix: Enforce per-validator claim limit to prevent queue monopolization
        if ($.validatorActiveClaimsPerProject[projectId][msg.sender] >= MAX_ACTIVE_VALIDATOR_CLAIMS_PER_PROJECT) {
            revert MaxValidatorClaimsPerProjectExceeded(msg.sender, projectId, MAX_ACTIVE_VALIDATOR_CLAIMS_PER_PROJECT);
        }

        // Check queue availability - revert if all numberOfValidations slots have been claimed
        uint256 available = settings.queueTail - settings.queueHead;
        if (available == 0) revert AllValidationsClaimed(projectId);

        // F-10: Increment active claim count
        ++$.validatorActiveClaimsPerProject[projectId][msg.sender];

        claimId = settings.nextValidationClaimId;
        ++settings.nextValidationClaimId;
        uint256 deadline = block.timestamp + CLAIM_DURATION;

        // Option B: Always claim exactly 1 slot
        uint256 quantity = 1;

        // Assign single index from queue
        uint256 index = $.pendingQueue[projectId][settings.queueHead];
        ++settings.queueHead;

        _getValidationOracleStorage().validationClaims[projectId][claimId] = ValidationClaim({
            validator: msg.sender,
            quantity: quantity,
            contributionIndex: index, // Fix: Store the contribution index
            claimedAt: block.timestamp,
            deadline: deadline,
            committedCount: 0,
            status: ClaimStatus.Active
        });

        AssignmentState storage assignment = _getValidationOracleStorage().assignments[projectId][index][msg.sender];
        assignment.deadline = deadline;
        assignment.hasCommitted = false;
        assignment.committedStake = 0;

        emit IndexAssignedToValidator(projectId, claimId, index, msg.sender, deadline);
        emit ValidationClaimed(projectId, claimId, msg.sender, deadline);
    }

    /**
     * @notice Set the maximum validation capacity for the caller
     * @dev Locks the specified amount in the vault to enable validation without per-commit locks
     * @param amount The total amount of SAPIEN to lock for validation capacity
     */
    function setValidatorCapacity(uint256 amount) external nonReentrant {
        _getValidationOracleStorage().trust.hasEnoughStakeForRole(msg.sender, VALIDATOR_ROLE);

        ValidatorState storage vState = _getValidationOracleStorage().validatorStates[msg.sender];
        uint256 currentCapacity = vState.capacity;
        if (amount == currentCapacity) revert CapacityUnchanged(currentCapacity);

        // CEI Pattern: Effects (state changes) before Interactions (external calls)
        vState.capacity = amount;

        // Interactions (external calls) after state changes
        if (amount > currentCapacity) {
            uint256 diff = amount - currentCapacity;
            // Check that validator has enough available stake to lock
            uint256 availableStake = _getValidationOracleStorage().vault.getAvailableStake(msg.sender);
            if (diff > availableStake) revert Unauthorized(UNAUTHORIZED_INSUFFICIENT_AVAILABLE_STAKE);
            _getValidationOracleStorage().vault.lockStake(msg.sender, diff, "increase_capacity");
        } else {
            // Check if reducing capacity below in-flight stake
            if (amount < vState.inFlightStake) revert Unauthorized(UNAUTHORIZED_CANNOT_REDUCE_BELOW_INFLIGHT);
            uint256 diff = currentCapacity - amount;
            _getValidationOracleStorage().vault.unlockStake(msg.sender, diff, "decrease_capacity");
        }
        emit ValidatorCapacityUpdated(msg.sender, currentCapacity, amount);
    }

    /**
     * @notice Get the number of validations currently pending in the queue
     * @param projectId Unique identifier for the project
     * @return count Number of pending validation slots
     */
    function getPendingValidationCount(bytes32 projectId) external view returns (uint256) {
        ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
        return settings.queueTail - settings.queueHead;
    }

    /**
     * @notice Get the available validation capacity for a validator
     * @param validator The validator address
     * @return available The amount of capacity available for new validations
     */
    function getAvailableCapacity(address validator) external view returns (uint256) {
        ValidatorState storage vState = _getValidationOracleStorage().validatorStates[validator];
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
        uint256 deadline = _getValidationOracleStorage().assignments[projectId][contributionIndex][validator].deadline;
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
    /**
     * @notice Cancel a validation claim that has passed its deadline
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     */
    function cancelExpiredValidationClaim(bytes32 projectId, uint256 claimId) external nonReentrant {
        ValidationClaim storage claim = _getValidationOracleStorage().validationClaims[projectId][claimId];
        if (claim.status != ClaimStatus.Active) revert NoClaimAvailable();

        if (block.timestamp <= claim.deadline && msg.sender != claim.validator) {
            revert Unauthorized(UNAUTHORIZED_CLAIM_NOT_EXPIRED);
        }

        // Slash validator for uncommitted validations
        uint256 uncommittedCount = claim.quantity - claim.committedCount;

        // Mark claim as expired before external calls (CEI pattern)
        claim.status = ClaimStatus.Expired;

        // F-10: Release claim slot on expiry
        if (_getValidationOracleStorage().validatorActiveClaimsPerProject[projectId][claim.validator] > 0) {
            --_getValidationOracleStorage().validatorActiveClaimsPerProject[projectId][claim.validator];
        }

        if (uncommittedCount > 0) {
            uint256 stakePerValidation = _getRequiredValidatorStake(projectId);
            uint256 totalSlashAmount = uncommittedCount * stakePerValidation;

            ValidatorState storage vState = _getValidationOracleStorage().validatorStates[claim.validator];

            // CEI Pattern: Effects (state changes) before Interactions (external calls)
            // Reduce capacity by the slashed amount
            if (vState.capacity >= totalSlashAmount) {
                vState.capacity -= totalSlashAmount;
            } else {
                vState.capacity = 0;
            }

            // Re-queue the contribution index (Liveness Fix)
            ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
            _getValidationOracleStorage().pendingQueue[projectId][settings.queueTail] = claim.contributionIndex;
            ++settings.queueTail;

            // Interactions (external calls) after state changes
            // Slash from vault (stake is already locked)
            _getValidationOracleStorage().vault.slash(claim.validator, totalSlashAmount, projectId);

            // Update reputation for not fulfilling obligations
            _getValidationOracleStorage().trust.updateReputation(claim.validator, VALIDATOR_ROLE, false, 0);

            emit ValidatorSlashedForExpiredClaim(projectId, claimId, claim.validator, totalSlashAmount);
        }

        emit ValidationClaimExpired(projectId, claimId, claim.validator);
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
        // TODO: revert with error when Capicity is insufficient
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
    ) external {
        if (contributionIndices.length != commitHashes.length) {
            revert Unauthorized(UNAUTHORIZED_ARRAY_LENGTH_MISMATCH);
        }
        // F-12 fix: Prevent DoS via gas exhaustion from unbounded loops
        if (contributionIndices.length > MAX_BATCH_SIZE) {
            revert BatchSizeTooLarge(contributionIndices.length, MAX_BATCH_SIZE);
        }
        uint256 minStake = _getRequiredValidatorStake(projectId);
        for (uint256 i = 0; i < contributionIndices.length; ++i) {
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
        // F-12 fix: Prevent DoS via gas exhaustion from unbounded loops
        if (contributionIndices.length > MAX_BATCH_SIZE) {
            revert BatchSizeTooLarge(contributionIndices.length, MAX_BATCH_SIZE);
        }
        for (uint256 i = 0; i < contributionIndices.length; ++i) {
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
    /**
     * @notice Internal helper to commit a validation
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param contributionIndex Index of the contribution
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
        ValidationClaim storage claim = _getValidationOracleStorage().validationClaims[projectId][claimId];
        if (claim.validator != msg.sender) revert Unauthorized(UNAUTHORIZED_NOT_CLAIM_OWNER);
        if (claim.status != ClaimStatus.Active) revert ClaimNotActive(claimId);
        if (block.timestamp > claim.deadline) revert ClaimAlreadyExpired(claimId, claim.deadline);

        // Verify assignment
        AssignmentState storage assignment =
            _getValidationOracleStorage().assignments[projectId][contributionIndex][msg.sender];
        if (assignment.deadline == 0) revert Unauthorized(UNAUTHORIZED_NO_ASSIGNMENT);
        if (block.timestamp > assignment.deadline) {
            revert ClaimAlreadyExpired(claimId, assignment.deadline);
        }

        // 1. Verify Validator Role & Stake
        _getValidationOracleStorage().trust.hasEnoughStakeForRole(msg.sender, VALIDATOR_ROLE);

        // Sybil Protection: Originator and Contributor cannot validate
        ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
        if (msg.sender == settings.originator) revert Unauthorized(UNAUTHORIZED_ORIGINATOR_CANNOT_VALIDATE);
        if (msg.sender == _getValidationOracleStorage().contributionStates[projectId][contributionIndex].contributor) {
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
        ValidatorState storage vState = _getValidationOracleStorage().validatorStates[msg.sender];
        uint256 availableCapacity = vState.capacity > vState.inFlightStake ? vState.capacity - vState.inFlightStake : 0;
        if (stakeAmount > availableCapacity) {
            revert StakeExceedsCapacity(stakeAmount, availableCapacity);
        }

        // 5. Record Commit and update in-flight stake
        assignment.hasCommitted = true;
        assignment.committedStake = stakeAmount;
        vState.inFlightStake += stakeAmount;
        ++_getValidationOracleStorage().contributionStates[projectId][contributionIndex].activeClaimCount;
        ++claim.committedCount;

        if (claim.committedCount == claim.quantity) {
            claim.status = ClaimStatus.Fulfilled;
            // F-10: Release claim slot when fulfilled (validator has committed all assigned work)
            if (_getValidationOracleStorage().validatorActiveClaimsPerProject[projectId][claim.validator] > 0) {
                --_getValidationOracleStorage().validatorActiveClaimsPerProject[projectId][claim.validator];
            }
        }

        // Snapshot the reveal deadline at commit time to prevent retroactive shortening (M-2 fix)
        uint256 deadlineSnapshot = settings.revealDeadline;
        if (deadlineSnapshot == 0) deadlineSnapshot = _getValidationOracleStorage().revealDeadline;

        _getValidationOracleStorage()
        .validationCommits[projectId][contributionIndex].push(
            ValidationCommit({
                validator: msg.sender,
                commitHash: commitHash,
                committedAt: uint64(block.timestamp),
                revealDeadlineSnapshot: uint64(deadlineSnapshot),
                revealed: false,
                nonce: uint64(
                    _getValidationOracleStorage().contributionStates[projectId][contributionIndex].submissionNonce
                ) // F-05: tie commit to submission version
            })
        );

        emit ValidationCommitted(projectId, contributionIndex, msg.sender, commitHash, stakeAmount);
    }

    /**
     * @notice Reveal a committed validation score
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @param score The validation score (0-10000)
     * @param salt The salt used in the commit
     */
    function revealValidation(bytes32 projectId, uint256 contributionIndex, uint256 score, bytes32 salt) external {
        _revealValidation(projectId, contributionIndex, score, salt);
    }

    /**
     * @notice Reveal multiple committed validation scores in batch
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
    ) external {
        if (contributionIndices.length != scores.length || contributionIndices.length != salts.length) {
            revert Unauthorized(UNAUTHORIZED_ARRAY_LENGTH_MISMATCH);
        }
        // F-12 fix: Prevent DoS via gas exhaustion from unbounded loops
        if (contributionIndices.length > MAX_BATCH_SIZE) {
            revert BatchSizeTooLarge(contributionIndices.length, MAX_BATCH_SIZE);
        }
        for (uint256 i = 0; i < contributionIndices.length; ++i) {
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
    /**
     * @notice Internal helper to reveal a validation
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @param score Revealed score
     * @param salt Salt used in commit
     */
    function _revealValidation(bytes32 projectId, uint256 contributionIndex, uint256 score, bytes32 salt) internal {
        ValidationCommit[] storage commits =
            _getValidationOracleStorage().validationCommits[projectId][contributionIndex];
        uint256 currentNonce =
            _getValidationOracleStorage().contributionStates[projectId][contributionIndex].submissionNonce;

        // Find validator's commit (F-05: only match commits from current submission nonce)
        uint256 commitIndex = type(uint256).max;
        for (uint256 i = 0; i < commits.length; ++i) {
            if (commits[i].validator == msg.sender && !commits[i].revealed && commits[i].nonce == currentNonce) {
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
            ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
            deadline = settings.revealDeadline;
            if (deadline == 0) deadline = _getValidationOracleStorage().revealDeadline;
        }
        if (block.timestamp > commit.committedAt + deadline) {
            revert RevealDeadlinePassed(deadline, block.timestamp - commit.committedAt);
        }

        AssignmentState storage assignment =
            _getValidationOracleStorage().assignments[projectId][contributionIndex][msg.sender];
        uint256 stakeAmount = assignment.committedStake;

        // 2. Verify Commit Hash
        if (commit.commitHash != keccak256(abi.encodePacked(score, stakeAmount, salt))) revert InvalidCommitHash();

        // 3. Validate Score (fail-fast to prevent permanent DoS)
        // Score must be <= 10000 (0-100%). This validation prevents invalid scores from being
        // stored, which would cause consensus calculation to revert and permanently block finalization.
        if (score > 10000) revert IConsensusAlgorithm.InvalidScore(score);

        // 4. Release in-flight stake (capacity remains locked, but this validation is no longer "in flight")
        ValidatorState storage vState = _getValidationOracleStorage().validatorStates[msg.sender];
        if (vState.inFlightStake < stakeAmount) {
            revert InvalidStakeAmount(); // Underflow protection
        }
        vState.inFlightStake -= stakeAmount;

        // 5. Record Validation
        commit.revealed = true;
        _getValidationOracleStorage()
        .validations[projectId][contributionIndex].push(
            Validation({
                projectId: projectId,
                validator: msg.sender,
                contributionIndex: contributionIndex,
                score: uint16(score),
                stakeAmount: stakeAmount,
                submittedAt: uint64(block.timestamp),
                rewarded: false,
                slashed: false
            })
        );

        emit ValidationRevealed(projectId, contributionIndex, msg.sender, score, stakeAmount);
    }

    // ============================================
    // VIEW FUNCTIONS (CONSENSUS)
    // ============================================

    /**
     * @notice Calculate consensus for a contribution
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @return report Final consensus report
     */
    function getConsensus(bytes32 projectId, uint256 contributionIndex)
        external
        view
        returns (ConsensusReport memory report)
    {
        uint256 submittedAt = _getValidationOracleStorage().contributionStates[projectId][contributionIndex].submittedAt;
        if (submittedAt == 0) return report;

        uint256 numberOfValidations = _getValidationOracleStorage().projectSettings[projectId].numberOfValidations;
        (bool ready, uint256 validCount) =
            _checkConsensusReady(projectId, contributionIndex, numberOfValidations, submittedAt);
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
     * @notice Check if a validation commit is expired
     * @dev Check if a validation commit is expired
     * @param commit The validation commit to check
     * @param submittedAt Timestamp when the contribution was submitted
     * @param fallbackDeadline Fallback reveal deadline for legacy commits without a snapshot
     * @param currentNonce Current submission nonce
     * @return true if the commit is expired and should be slashed
     */
    function _isCommitExpired(
        ValidationCommit memory commit,
        uint256 submittedAt,
        uint256 fallbackDeadline,
        uint256 currentNonce
    ) internal view returns (bool) {
        // F-05: Only check commits from the current submission nonce
        if (commit.nonce != currentNonce) return false;
        // Only check commits that were made after submission and haven't been revealed
        if (commit.committedAt < submittedAt || commit.revealed) {
            return false;
        }

        // Opus 4.6 M-2 fix: Use per-commit snapshot instead of current project deadline.
        // This prevents originators from retroactively shortening the deadline to
        // prematurely expire validator commitments.
        uint256 deadline = commit.revealDeadlineSnapshot;
        if (deadline == 0) deadline = fallbackDeadline; // Fallback for legacy commits

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
        ValidationCommit[] storage commits =
            _getValidationOracleStorage().validationCommits[projectId][contributionIndex];
        ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
        uint256 deadline = settings.revealDeadline;
        if (deadline == 0) deadline = _getValidationOracleStorage().revealDeadline;
        uint256 currentNonce =
            _getValidationOracleStorage().contributionStates[projectId][contributionIndex].submissionNonce;

        // Count expired (F-05: only current-nonce commits)
        uint256 expiredCount = 0;
        for (uint256 i = 0; i < commits.length; ++i) {
            if (_isCommitExpired(commits[i], submittedAt, deadline, currentNonce)) {
                ++expiredCount;
            }
        }

        if (expiredCount == 0) return (outliers, outlierAmounts);

        // Merge
        uint256 total = outliers.length + expiredCount;
        toSlash = new address[](total);
        slashAmounts = new uint256[](total);

        for (uint256 i = 0; i < outliers.length; ++i) {
            toSlash[i] = outliers[i];
            slashAmounts[i] = outlierAmounts[i];
        }

        uint256 idx = outliers.length;
        for (uint256 i = 0; i < commits.length; ++i) {
            if (_isCommitExpired(commits[i], submittedAt, deadline, currentNonce)) {
                toSlash[idx] = commits[i].validator;
                slashAmounts[idx] =
                _getValidationOracleStorage()
                .assignments[projectId][contributionIndex][commits[i].validator].committedStake;
                ++idx;
            }
        }
    }

    /**
     * @dev Check if consensus is ready (all required validations have been revealed)
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     * @param numberOfValidations Exact number of validations required
     * @param submittedAt Timestamp when the contribution was submitted
     * @return bool True if consensus is ready
     * @return uint256 Number of valid validations
     */
    function _checkConsensusReady(
        bytes32 projectId,
        uint256 contributionIndex,
        uint256 numberOfValidations,
        uint256 submittedAt
    ) internal view returns (bool, uint256) {
        Validation[] storage allVals = _getValidationOracleStorage().validations[projectId][contributionIndex];

        // F-05: Validations are inherently filtered by submittedAt (stale reveals from old nonces
        // have submittedAt < current submittedAt). Nonce filtering is enforced at commit/reveal time.
        uint256 validCount = 0;
        for (uint256 i = 0; i < allVals.length; ++i) {
            if (allVals[i].submittedAt >= submittedAt) {
                ++validCount;
            }
        }

        if (validCount < numberOfValidations) return (false, validCount);

        // Consensus is ready once the exact numberOfValidations threshold is met.
        // Unrevealed commits are still tracked and their validators are slashed
        // via _appendExpiredSlashes when applicable.
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
        Validation[] storage allVals = _getValidationOracleStorage().validations[projectId][contributionIndex];
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](validCount);
        uint256 inputIdx = 0;
        for (uint256 i = 0; i < allVals.length; ++i) {
            if (allVals[i].submittedAt >= submittedAt) {
                inputs[inputIdx] = IConsensusAlgorithm.ValidationInput({
                    validator: allVals[i].validator,
                    score: allVals[i].score,
                    stakeAmount: allVals[i].stakeAmount,
                    reputation: _getValidationOracleStorage().trust.getTrustScore(allVals[i].validator, VALIDATOR_ROLE)
                });
                ++inputIdx;
            }
        }
        return inputs;
    }

    /**
     * @notice Get all revealed validations for a contribution
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @return Array of revealed validation structs
     */
    function getValidations(bytes32 projectId, uint256 contributionIndex) external view returns (Validation[] memory) {
        return _getValidationOracleStorage().validations[projectId][contributionIndex];
    }

    /**
     * @notice Get all validation commits for a contribution
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @return Array of validation commit structs
     */
    function getValidationCommits(bytes32 projectId, uint256 contributionIndex)
        external
        view
        returns (ValidationCommit[] memory)
    {
        return _getValidationOracleStorage().validationCommits[projectId][contributionIndex];
    }

    /**
     * @notice Get a specific validation claim
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @return ValidationClaim struct
     */
    function getValidationClaim(bytes32 projectId, uint256 claimId) external view returns (ValidationClaim memory) {
        return _getValidationOracleStorage().validationClaims[projectId][claimId];
    }

    /**
     * @notice Get the consensus algorithm implementation for a project
     * @param projectId Unique identifier for the project
     * @return IConsensusAlgorithm implementation
     */
    function getAlgorithm(bytes32 projectId) public view returns (IConsensusAlgorithm) {
        bytes32 algoName = _getValidationOracleStorage().projectSettings[projectId].algorithm;
        if (algoName == bytes32(0)) algoName = _getValidationOracleStorage().defaultAlgorithm;

        address impl = _getValidationOracleStorage().algorithms[algoName];
        if (impl == address(0)) revert InvalidAddress();

        return IConsensusAlgorithm(impl);
    }

    // ============================================
    // REGISTRY FUNCTIONS
    // ============================================

    /**
     * @notice Register a new project and its configuration
     * @param projectId Unique identifier for the project
     * @param numberOfValidations Number of validations required
     * @param requiredSkill Required skill for validators
     * @param originator Project creator address
     */
    function registerProject(
        bytes32 projectId,
        uint256 numberOfValidations,
        string calldata requiredSkill,
        address originator
    ) external onlyCoreOrAdmin {
        if (originator == address(0)) revert InvalidAddress();
        if (numberOfValidations == 0) revert InvalidNumberOfValidations(numberOfValidations);

        ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
        settings.numberOfValidations = numberOfValidations;
        settings.requiredSkill = requiredSkill;
        settings.originator = originator;

        _emitProjectStateChange(projectId);
    }

    /**
     * @notice Register a new consensus algorithm implementation
     * @param name Human-readable name of the algorithm
     * @param implementation Implementation contract address
     */
    function registerAlgorithm(string calldata name, address implementation) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (implementation == address(0)) revert InvalidAddress();
        _getValidationOracleStorage().algorithms[keccak256(abi.encodePacked(name))] = implementation;
        emit AlgorithmRegistered(name, implementation);
    }

    /**
     * @notice Set the consensus algorithm for a project
     * @param projectId Unique identifier for the project
     * @param algorithmName Name of the algorithm to use
     */
    function setProjectAlgorithm(bytes32 projectId, string calldata algorithmName) external {
        ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
        if (settings.originator == address(0)) revert ProjectNotRegistered(projectId);
        if (msg.sender != settings.originator && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_NOT_PROJECT_ORIGINATOR);
        }

        settings.algorithm = keccak256(abi.encodePacked(algorithmName));
        _emitProjectStateChange(projectId);
    }

    /**
     * @notice Set the number of validations required for a project
     * @param projectId Unique identifier for the project
     * @param numberOfValidations Number of validations required
     */
    function setProjectNumberOfValidations(bytes32 projectId, uint256 numberOfValidations) external onlyCoreOrAdmin {
        if (numberOfValidations == 0) revert InvalidNumberOfValidations(numberOfValidations);
        if (_getValidationOracleStorage().projectSettings[projectId].originator == address(0)) {
            revert ProjectNotRegistered(projectId);
        }
        _getValidationOracleStorage().projectSettings[projectId].numberOfValidations = numberOfValidations;
        _emitProjectStateChange(projectId);
    }

    /**
     * @notice Set the required skill for a project
     * @param projectId Unique identifier for the project
     * @param requiredSkill Name of the required skill
     */
    function setProjectRequiredSkill(bytes32 projectId, string calldata requiredSkill) external onlyCoreOrAdmin {
        if (_getValidationOracleStorage().projectSettings[projectId].originator == address(0)) {
            revert ProjectNotRegistered(projectId);
        }
        _getValidationOracleStorage().projectSettings[projectId].requiredSkill = requiredSkill;
        _emitProjectStateChange(projectId);
    }

    /**
     * @notice Set the reveal deadline for a project
     * @param projectId Unique identifier for the project
     * @param deadline Reveal deadline in seconds
     */
    function setProjectRevealDeadline(bytes32 projectId, uint256 deadline) external {
        ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
        if (settings.originator == address(0)) revert ProjectNotRegistered(projectId);
        if (msg.sender != settings.originator && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_NOT_PROJECT_ORIGINATOR);
        }
        // Prevent malicious deadline shortening attacks (Issue #2 fix)
        if (deadline < MIN_REVEAL_DEADLINE) revert InvalidDeadline();
        settings.revealDeadline = deadline;
        _emitProjectStateChange(projectId);
    }

    function setProjectOriginator(bytes32 projectId, address originator) external onlyCoreOrAdmin {
        if (originator == address(0)) revert InvalidAddress();
        if (_getValidationOracleStorage().projectSettings[projectId].originator == address(0)) {
            revert ProjectNotRegistered(projectId);
        }
        _getValidationOracleStorage().projectSettings[projectId].originator = originator;
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
        ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
        if (settings.originator == address(0)) revert ProjectNotRegistered(projectId);
        if (msg.sender != settings.originator && !hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert Unauthorized(UNAUTHORIZED_NOT_PROJECT_ORIGINATOR);
        }
        if (minReputation > 10000) revert ReputationOutOfRange(minReputation, 10000);
        settings.minValidatorReputation = minReputation;
        _emitProjectStateChange(projectId);
    }

    /**
     * @notice Set the contributor for a specific contribution index
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index within project
     * @param contributor Address of the contributor
     */
    function setContributionContributor(bytes32 projectId, uint256 contributionIndex, address contributor)
        external
        onlyCoreOrAdmin
    {
        if (contributor == address(0)) revert InvalidAddress();
        _getValidationOracleStorage().contributionStates[projectId][contributionIndex].contributor = contributor;
        emit ContributionContributorUpdated(projectId, contributionIndex, contributor);
    }

    /**
     * @notice Cancel an expired commitment and slash the validator
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @param validator Validator address to cancel
     */
    function cancelExpiredCommitment(bytes32 projectId, uint256 contributionIndex, address validator)
        external
        nonReentrant
    {
        ValidationCommit[] storage commits =
            _getValidationOracleStorage().validationCommits[projectId][contributionIndex];
        ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
        uint256 currentNonce =
            _getValidationOracleStorage().contributionStates[projectId][contributionIndex].submissionNonce;

        for (uint256 i = 0; i < commits.length; ++i) {
            // F-05: Only process commits from the current submission nonce
            if (commits[i].validator == validator && !commits[i].revealed && commits[i].nonce == currentNonce) {
                // Opus 4.6 M-2 fix: Use per-commit snapshot for expiry check,
                // consistent with _revealValidation. Fallback for legacy commits.
                uint256 deadline = commits[i].revealDeadlineSnapshot;
                if (deadline == 0) {
                    deadline = settings.revealDeadline;
                    if (deadline == 0) deadline = _getValidationOracleStorage().revealDeadline;
                }

                if (block.timestamp > commits[i].committedAt + deadline) {
                    AssignmentState storage assignment =
                        _getValidationOracleStorage().assignments[projectId][contributionIndex][validator];
                    uint256 stake = assignment.committedStake;

                    // Release in-flight stake tracking
                    ValidatorState storage vState = _getValidationOracleStorage().validatorStates[validator];
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
                    if (
                        _getValidationOracleStorage().contributionStates[projectId][contributionIndex].activeClaimCount
                            > 0
                    ) {
                        --_getValidationOracleStorage()
                        .contributionStates[projectId][contributionIndex].activeClaimCount;
                    }

                    // Re-queue the contribution index (Liveness Fix)
                    _getValidationOracleStorage().pendingQueue[projectId][settings.queueTail] = contributionIndex;
                    ++settings.queueTail;

                    // External calls after all state changes (CEI pattern)
                    // Slash from the validator's capacity (stake is already locked in vault)
                    _getValidationOracleStorage().vault.slash(validator, stake, projectId);

                    // Update reputation for not fulfilling obligations (consistent with cancelExpiredValidationClaim)
                    _getValidationOracleStorage().trust.updateReputation(validator, VALIDATOR_ROLE, false, 0);

                    emit ExpiredCommitmentCancelled(projectId, contributionIndex, validator, stake);
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
    function resetContributionState(bytes32 projectId, uint256 contributionIndex) external onlyCoreOrAdmin {
        ContributionState storage cState =
            _getValidationOracleStorage().contributionStates[projectId][contributionIndex];
        uint256 currentNonce = cState.submissionNonce;

        // F-05/F-08 fix: Only clear assignments for current-nonce commits (avoids iterating stale data)
        ValidationCommit[] storage commits =
            _getValidationOracleStorage().validationCommits[projectId][contributionIndex];
        for (uint256 i = 0; i < commits.length; ++i) {
            if (commits[i].nonce == currentNonce) {
                _getValidationOracleStorage()
                .assignments[projectId][contributionIndex][commits[i].validator].hasCommitted = false;
            }
        }

        // F-08 fix: Don't delete arrays — nonce-based invalidation handles stale data.
        // The next enqueueValidation call will increment the nonce, making all current
        // commits/validations stale. This saves gas compared to zeroing array elements.
        // Reset contribution state fields (preserving submissionNonce for next cycle)
        cState.submittedAt = 0;
        cState.contributor = address(0);
        cState.activeClaimCount = 0;
        // Note: submissionNonce is preserved — it will be incremented by the next enqueueValidation
    }

    /**
     * @notice Set the global default reveal deadline
     * @param _newDeadline Deadline in seconds
     */
    function setRevealDeadline(uint256 _newDeadline) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_newDeadline < MIN_REVEAL_DEADLINE) revert InvalidDeadline();
        _getValidationOracleStorage().revealDeadline = _newDeadline;
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
        onlyCoreOrAdmin
    {
        if (slashAmount == 0) return;

        ValidatorState storage vState = _getValidationOracleStorage().validatorStates[validator];

        // If they had an unrevealed commit for this index, it was just slashed
        // We must reduce inFlightStake
        ValidationCommit[] storage commits =
            _getValidationOracleStorage().validationCommits[projectId][contributionIndex];
        for (uint256 i = 0; i < commits.length; ++i) {
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
        uint256 vaultLockedStake = _getValidationOracleStorage().vault.getLockedStake(validator);
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
    /**
     * @notice Internal helper to get required validator stake for a project
     * @return Required stake amount
     */
    function _getRequiredValidatorStake(
        bytes32 /* projectId */
    )
        internal
        view
        returns (uint256)
    {
        uint256 required = _getValidationOracleStorage().trust.roleMinStake(VALIDATOR_ROLE);
        if (required == 0) required = _getValidationOracleStorage().trust.minStakeRequired();
        return required;
    }

    /**
     * @dev Emit the complete ProjectSettings state for a project
     * @param projectId Unique identifier for the project
     */
    /**
     * @notice Internal helper to emit ProjectStateChange event
     * @param projectId Unique identifier for the project
     */
    function _emitProjectStateChange(bytes32 projectId) internal {
        ProjectSettings storage settings = _getValidationOracleStorage().projectSettings[projectId];
        emit ProjectStateChange(
            projectId,
            settings.algorithm,
            settings.numberOfValidations,
            settings.revealDeadline,
            settings.requiredSkill,
            settings.originator,
            settings.nextValidationClaimId,
            settings.queueHead,
            settings.queueTail,
            settings.minValidatorReputation
        );
    }

    // ============================================
    // VIEW GETTERS (match IValidationOracle interface)
    // ============================================

    /**
     * @notice Get the trust contract instance
     * @return The ISapienTrust contract
     */
    function trust() external view returns (ISapienTrust) {
        return _getValidationOracleStorage().trust;
    }

    /**
     * @notice Get the vault contract instance
     * @return The ISapienVault contract
     */
    function vault() external view returns (ISapienVault) {
        return _getValidationOracleStorage().vault;
    }

    /**
     * @notice Get the default reveal deadline
     * @return The reveal deadline in seconds
     */
    function revealDeadline() external view returns (uint256) {
        return _getValidationOracleStorage().revealDeadline;
    }

    /**
     * @notice Get the default algorithm name hash
     * @return The keccak256 hash of the default algorithm name
     */
    function defaultAlgorithm() external view returns (bytes32) {
        return _getValidationOracleStorage().defaultAlgorithm;
    }

    /**
     * @notice Get the address of a registered algorithm
     * @param algoName The keccak256 hash of the algorithm name
     * @return The address of the algorithm contract
     */
    function algorithms(bytes32 algoName) external view returns (address) {
        return _getValidationOracleStorage().algorithms[algoName];
    }

    /**
     * @notice Get project-specific settings
     * @param projectId The project identifier
     * @return algorithm The algorithm name hash
     * @return numberOfValidations Required validations per contribution
     * @return projectRevealDeadline Custom reveal deadline
     * @return requiredSkill Skill name required for validators
     * @return originator Project creator address
     * @return nextValidationClaimId ID for next validation claim
     * @return queueHead Current head of validation queue
     * @return queueTail Current tail of validation queue
     * @return minValidatorReputation Minimum reputation required to validate
     */
    function projectSettings(bytes32 projectId)
        external
        view
        returns (
            bytes32 algorithm,
            uint256 numberOfValidations,
            uint256 projectRevealDeadline,
            string memory requiredSkill,
            address originator,
            uint256 nextValidationClaimId,
            uint256 queueHead,
            uint256 queueTail,
            uint256 minValidatorReputation
        )
    {
        ProjectSettings storage s = _getValidationOracleStorage().projectSettings[projectId];
        return (
            s.algorithm,
            s.numberOfValidations,
            s.revealDeadline,
            s.requiredSkill,
            s.originator,
            s.nextValidationClaimId,
            s.queueHead,
            s.queueTail,
            s.minValidatorReputation
        );
    }

    /**
     * @notice Get the state of a contribution
     * @param projectId The project identifier
     * @param contributionIndex The index of the contribution
     * @return submittedAt Timestamp of submission
     * @return contributor Address of the contributor
     * @return activeClaimCount Number of active validation claims
     * @return submissionNonce Current submission nonce
     */
    function contributionStates(bytes32 projectId, uint256 contributionIndex)
        external
        view
        returns (uint256 submittedAt, address contributor, uint256 activeClaimCount, uint256 submissionNonce)
    {
        ContributionState storage cs = _getValidationOracleStorage().contributionStates[projectId][contributionIndex];
        return (cs.submittedAt, cs.contributor, cs.activeClaimCount, cs.submissionNonce);
    }

    /**
     * @notice Get the state of a validator
     * @param validator The validator address
     * @return capacity Total validation capacity
     * @return inFlightStake Currently active stake in validations
     */
    function validatorStates(address validator) external view returns (uint256 capacity, uint256 inFlightStake) {
        ValidatorState storage vs = _getValidationOracleStorage().validatorStates[validator];
        return (vs.capacity, vs.inFlightStake);
    }

    /**
     * @notice Get an entry from the pending validation queue
     * @param projectId The project identifier
     * @param queueIndex The index in the queue
     * @return The contribution index at that queue position
     */
    function pendingQueue(bytes32 projectId, uint256 queueIndex) external view returns (uint256) {
        return _getValidationOracleStorage().pendingQueue[projectId][queueIndex];
    }

    /**
     * @notice Get a validation claim's details
     * @param projectId The project identifier
     * @param claimId The claim identifier
     * @return validator Address of the validator
     * @return quantity Number of slots claimed
     * @return contributionIndex Index being validated
     * @return claimedAt Timestamp of claim
     * @return deadline Expiry timestamp
     * @return committedCount Number of slots committed
     * @return status Current status of the claim
     */
    function validationClaims(bytes32 projectId, uint256 claimId)
        external
        view
        returns (
            address validator,
            uint256 quantity,
            uint256 contributionIndex,
            uint256 claimedAt,
            uint256 deadline,
            uint256 committedCount,
            ClaimStatus status
        )
    {
        ValidationClaim storage vc = _getValidationOracleStorage().validationClaims[projectId][claimId];
        return
            (vc.validator, vc.quantity, vc.contributionIndex, vc.claimedAt, vc.deadline, vc.committedCount, vc.status);
    }

    /**
     * @notice Get all revealed validations for a contribution
     * @param projectId The project identifier
     * @param contributionIndex The index of the contribution
     * @return Array of revealed validation records
     */
    function validations(bytes32 projectId, uint256 contributionIndex) external view returns (Validation[] memory) {
        return _getValidationOracleStorage().validations[projectId][contributionIndex];
    }
}
