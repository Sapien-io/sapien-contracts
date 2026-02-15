// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    ReentrancyGuardUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {ISapienVault} from "./interface/ISapienVault.sol";
import {IRewards} from "./interface/IRewards.sol";
import {ISapienTrust} from "./interface/ISapienTrust.sol";
import {IValidationOracle} from "./interface/IValidationOracle.sol";
import {ISapienCore} from "./interface/ISapienCore.sol";
import {
    ORIGINATOR_ROLE,
    CONTRIBUTOR_ROLE,
    VALIDATOR_ROLE,
    UNAUTHORIZED_NOT_PROJECT_ORIGINATOR,
    UNAUTHORIZED_ORIGINATOR_CANNOT_CONTRIBUTE,
    UNAUTHORIZED_NOT_CLAIM_OWNER,
    UNAUTHORIZED_NOT_INDEX_OWNER,
    UNAUTHORIZED_ARRAY_LENGTH_MISMATCH
} from "./interface/ISharedTypes.sol";
import {ConsensusLib} from "./libraries/ConsensusLib.sol";

/**
 * @title SapienCore
 * @author Sapien Team
 * @notice Central coordinator for projects, contributions, and rewards.
 * @dev Merges ProjectRegistry and ContributionManager.
 *      Hierarchy: Core -> Oracle -> Trust -> Vault.
 */
contract SapienCore is ISapienCore, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // Protocol fee configuration
    /// @notice Protocol fee in basis points (e.g., 100 = 1%)
    /// @dev Default is 100 (1%)

    /// @notice Maximum protocol fee (3% = 300 basis points)
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 300;

    /// @notice Maximum fee that a dapp operator can charge (2%)
    uint256 public constant MAX_ORGINATION_OPERATOR_FEE_BPS = 200;

    /// @notice Minimum consensus threshold (10% = 1000 basis points)
    /// @dev Prevents threshold being set too low which would approve everything
    uint256 public constant MIN_CONSENSUS_THRESHOLD = 1000;

    /// @notice Minimum reward per contribution slot (1e15 wei = 0.001 tokens with 18 decimals)
    /// @dev Prevents precision loss from rounding rewards to zero
    uint256 public constant MIN_REWARD_PER_SLOT = 1e15;

    /// @notice Maximum active claimed slots per user per project (Issue #6 fix)
    /// @dev Prevents slot starvation attacks where one user claims all slots
    uint256 public constant MAX_CLAIMS_PER_USER = 10;

    /// @notice Maximum items in a single batch operation (F-12 fix)
    /// @dev Prevents DoS via gas exhaustion from unbounded loops
    uint256 public constant MAX_BATCH_SIZE = 50;

    // ============================================
    // STATE VARIABLES (ERC-7201 namespaced storage)
    // ============================================

    /// @notice Storage layout for the SapienCore contract using ERC-7201 namespaced storage.
    /// @custom:storage-location erc7201:sapien.storage.SapienCore
    struct SapienCoreStorage {
        /// @notice The Sapien vault interface instance.
        ISapienVault vault;

        /// @notice The rewards contract interface instance.
        IRewards rewards;

        /// @notice The Sapien trust contract interface instance.
        ISapienTrust trust;

        /// @notice The validation oracle contract interface instance.
        IValidationOracle oracle;

        /// @notice Mapping from projectId to Project struct.
        mapping(bytes32 => Project) projects;

        /// @notice Mapping from projectId and claimId to Claim struct.
        mapping(bytes32 => mapping(uint256 => Claim)) claims;

        /// @notice Tracks the next claim ID for each projectId.
        mapping(bytes32 => uint256) nextClaimId;

        /// @notice Mapping from projectId and contributionId to Contribution struct.
        mapping(bytes32 => mapping(uint256 => Contribution)) contributions;

        /// @notice Mapping from projectId and indexReservationId to IndexReservation struct.
        mapping(bytes32 => mapping(uint256 => IndexReservation)) indexReservations;

        /// @notice Tracks available indices per project and index.
        mapping(bytes32 => mapping(uint256 => uint256)) availableIndices;

        /// @notice Stack top for available indices per project.
        mapping(bytes32 => uint256) stackTop;

        /// @notice Tracks availability of specific indices per project.
        mapping(bytes32 => mapping(uint256 => bool)) indexIsAvailable;

        /// @notice The period (in days) until a claim expires.
        uint256 claimDeadlineDays;

        /// @notice Basis points for protocol fee charged on funding.
        uint256 protocolFeeBasisPoints;

        /// @notice Address of the treasury where protocol fees are sent.
        address treasury;

        /// @notice Minimum proportion (in basis points) to reach consensus.
        uint256 consensusThreshold;

        /// @notice Challenge period (in seconds) after claims/validations.
        uint256 challengePeriod;

        /// @notice Tracks number of active claimed slots for a user per project.
        mapping(bytes32 => mapping(address => uint256)) userActiveClaimedQuantity;
    }

    /**
     * @notice Get the storage pointer for the SapienCore contract
     * @return $ The storage pointer
     */
    function _getSapienCoreStorage() private pure returns (SapienCoreStorage storage $) {
        bytes32 slot =
            keccak256(abi.encode(uint256(keccak256("sapien.storage.SapienCore")) - 1)) & ~bytes32(uint256(0xff));
        assembly {
            $.slot := slot
        }
    }

    // ============================================
    // INITIALIZER
    // ============================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the SapienCore contract
     * @dev Sets up the protocol contracts and initializes access control
     * @param vaultAddr Address of the SapienVault contract
     * @param rewardsAddr Address of the Rewards contract
     * @param trustAddr Address of the SapienTrust contract
     * @param oracleAddr Address of the ValidationOracle contract
     * @param admin Address to grant DEFAULT_ADMIN_ROLE
     */
    function initialize(address vaultAddr, address rewardsAddr, address trustAddr, address oracleAddr, address admin)
        public
        initializer
    {
        if (
            vaultAddr == address(0) || rewardsAddr == address(0) || trustAddr == address(0) || oracleAddr == address(0)
                || admin == address(0)
        ) {
            revert InvalidAddress();
        }

        __AccessControl_init();
        __ReentrancyGuard_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);

        SapienCoreStorage storage $ = _getSapienCoreStorage();
        $.vault = ISapienVault(vaultAddr);
        $.rewards = IRewards(rewardsAddr);
        $.trust = ISapienTrust(trustAddr);
        $.oracle = IValidationOracle(oracleAddr);
        $.claimDeadlineDays = 7;
        $.protocolFeeBasisPoints = 100; // Default 1%
        $.consensusThreshold = 5000; // Default 50%
        $.challengePeriod = 1 days; // Default 1 day
    }

    // ============================================
    // CONFIGURATION FUNCTIONS
    // ============================================

    /**
     * @notice Set the claim deadline in days for new projects
     * @dev Only callable by admin. Affects all projects created after this change.
     * @param _days Number of days contributors have to submit after claiming
     */
    function setClaimDeadlineDays(uint256 _days) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_days == 0) revert InvalidClaimDeadline(_days);
        _getSapienCoreStorage().claimDeadlineDays = _days;
    }

    /**
     * @notice Get the claim deadline in days
     * @return Number of days contributors have to submit after claiming
     */
    function getClaimDeadlineDays() external view returns (uint256) {
        return _getSapienCoreStorage().claimDeadlineDays;
    }

    /**
     * @notice Set the protocol fee basis points (e.g., 100 = 1%)
     * @param _feeBasisPoints The fee in basis points (max 300 = 3%)
     */
    function setProtocolFeeBasisPoints(uint256 _feeBasisPoints) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feeBasisPoints > MAX_PROTOCOL_FEE_BPS) revert ProtocolFeeTooHigh(_feeBasisPoints, MAX_PROTOCOL_FEE_BPS);
        _getSapienCoreStorage().protocolFeeBasisPoints = _feeBasisPoints;
        emit ProtocolFeeUpdated(_feeBasisPoints);
    }

    /**
     * @notice Set the treasury address to receive protocol fees
     * @param _treasury The treasury address
     */
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_treasury == address(0)) revert InvalidAddress();
        _getSapienCoreStorage().treasury = _treasury;
        emit TreasuryUpdated(_treasury);
    }

    /**
     * @notice Set the consensus threshold score (default 5000)
     * @param _threshold The minimum weighted average score to accept a contribution
     */
    function setConsensusThreshold(uint256 _threshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_threshold < MIN_CONSENSUS_THRESHOLD) {
            revert ConsensusThresholdOutOfRange(_threshold, MIN_CONSENSUS_THRESHOLD, 10000);
        }
        if (_threshold > 10000) {
            revert ConsensusThresholdOutOfRange(_threshold, MIN_CONSENSUS_THRESHOLD, 10000);
        }
        _getSapienCoreStorage().consensusThreshold = _threshold;
        emit ConsensusThresholdUpdated(_threshold);
    }

    /**
     * @notice Set the default challenge period for finalized contributions
     * @param _period The challenge period in seconds
     */
    function setChallengePeriod(uint256 _period) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_period == 0) revert InvalidChallengePeriod(_period);
        _getSapienCoreStorage().challengePeriod = _period;
        emit ChallengePeriodUpdated(_period);
    }

    // ============================================
    // PROJECT FUNCTIONS
    // ============================================

    /**
     * @notice Create a new project in the protocol
     * @param projectId Unique identifier for the project
     * @param rewardToken ERC20 token to be used for rewards
     * @param ipfsCid The original IPFS CID of the project spec document
     * @param minStakeToClaim Minimum stake required for a contributor to claim a slot
     * @param minStakeToContribute Minimum stake required for a contributor to participate (legacy)
     * @param numberOfValidations Exact number of validations required per contribution
     * @param validatorRewardBasisPoints Percentage of rewards allocated to validators (bps)
     * @param requiredSkill Specific skill that contributors will earn upon successful completion
     * @return The hashed projectId (bytes32)
     */
    function createProject(
        bytes32 projectId,
        address rewardToken,
        string calldata ipfsCid, // The original IPFS CID of the project spec document
        uint256 minStakeToClaim,
        uint256 minStakeToContribute,
        uint256 numberOfValidations,
        uint256 validatorRewardBasisPoints,
        string calldata requiredSkill
    ) external returns (bytes32) {
        Project storage p = _getSapienCoreStorage().projects[projectId];

        if (p.originator != address(0)) {
            revert ProjectAlreadyExists(projectId);
        }
        _getSapienCoreStorage().trust.hasEnoughStakeForRole(msg.sender, ORIGINATOR_ROLE);
        // Opus 4.6 L-3 fix: Prevent projects with zero-address reward token
        if (rewardToken == address(0)) revert InvalidAddress();
        if (validatorRewardBasisPoints > 2500) revert InvalidValidatorRewards();

        // Verify that projectId matches keccak256(ipfsCid)
        bytes32 expectedProjectId = keccak256(abi.encodePacked(ipfsCid));
        if (projectId != expectedProjectId) {
            revert InvalidProjectId();
        }

        p.projectId = projectId;
        p.originator = msg.sender;
        p.rewardToken = IERC20(rewardToken);

        // Initialize Config
        p.config.claimDeadlineDays = _getSapienCoreStorage().claimDeadlineDays;
        p.config.minStakeToClaim = minStakeToClaim;
        p.config.minStakeToContribute = minStakeToContribute;
        p.config.numberOfValidations = numberOfValidations == 0 ? 3 : numberOfValidations;
        p.config.validatorRewardBasisPoints = validatorRewardBasisPoints == 0 ? 1000 : validatorRewardBasisPoints;
        p.config.requiredSkill = requiredSkill;
        p.config.challengePeriod = _getSapienCoreStorage().challengePeriod;

        _registerProjectWithOracle(projectId, p.config.numberOfValidations, requiredSkill, msg.sender);

        _getSapienCoreStorage().trust.updateReputation(msg.sender, ORIGINATOR_ROLE, true, 0);

        emit ProjectCreated(
            p.projectId,
            p.originator,
            address(p.rewardToken),
            ipfsCid, // Emit the original IPFS CID so it can be retrieved from events
            p.config.claimDeadlineDays,
            p.config.minStakeToClaim,
            p.config.minStakeToContribute,
            p.config.numberOfValidations,
            p.config.validatorRewardBasisPoints,
            p.config.requiredSkill
        );

        return projectId;
    }

    /**
     * @notice Register a project with the ValidationOracle
     * @dev Register a project with the ValidationOracle
     * @param projectId Unique identifier for the project
     * @param numberOfValidations Exact number of validations required per contribution
     * @param requiredSkill Skill required for validators
     * @param originator Address of the project creator
     */
    function _registerProjectWithOracle(
        bytes32 projectId,
        uint256 numberOfValidations,
        string memory requiredSkill,
        address originator
    ) internal {
        _getSapienCoreStorage().oracle.registerProject(projectId, numberOfValidations, requiredSkill, originator);
    }

    /**
     * @notice Fund an existing project with rewards and contribution quantity
     * @param projectId Unique identifier for the project
     * @param rewardAmount Amount of reward tokens to add
     * @param quantity Number of contribution slots to add
     */
    function fundProject(bytes32 projectId, uint256 rewardAmount, uint256 quantity) external nonReentrant {
        _fundProject(projectId, rewardAmount, quantity, address(0), 0);
    }

    /**
     * @notice Fund an existing project with rewards and contribution quantity, including an operator fee
     * @param projectId Unique identifier for the project
     * @param rewardAmount Amount of reward tokens to add
     * @param quantity Number of contribution slots to add
     * @param operator Address of the dapp operator/interface
     * @param operatorFeeBps Fee in basis points (e.g. 100 = 1%) to pay to the operator
     */
    function fundProject(
        bytes32 projectId,
        uint256 rewardAmount,
        uint256 quantity,
        address operator,
        uint256 operatorFeeBps
    ) external nonReentrant {
        _fundProject(projectId, rewardAmount, quantity, operator, operatorFeeBps);
    }

    /**
     * @notice Internal helper to fund a project
     * @param projectId Unique identifier for the project
     * @param rewardAmount Amount of reward tokens to add
     * @param quantity Number of contribution slots to add
     * @param operator Address of the dapp operator/interface
     * @param operatorFeeBps Fee in basis points (e.g. 100 = 1%) to pay to the operator
     */
    function _fundProject(
        bytes32 projectId,
        uint256 rewardAmount,
        uint256 quantity,
        address operator,
        uint256 operatorFeeBps
    ) internal {
        Project storage project = _getSapienCoreStorage().projects[projectId];
        if (project.originator == address(0)) revert ProjectDoesNotExist(projectId);

        // FIX H-2: Access control - only originator can fund their project
        if (msg.sender != project.originator) revert Unauthorized(UNAUTHORIZED_NOT_PROJECT_ORIGINATOR);

        // FIX H-2: Prevent zero-cost dilution attacks
        // If adding quantity, must also add proportional rewards
        if (quantity > 0 && rewardAmount == 0) revert InvalidAmount();

        // Protocol Fee Logic - taken first from the original amount
        uint256 protocolFee = 0;
        uint256 amountAfterProtocolFee = rewardAmount;

        if (
            rewardAmount > 0 && _getSapienCoreStorage().protocolFeeBasisPoints > 0
                && _getSapienCoreStorage().treasury != address(0)
        ) {
            protocolFee = (rewardAmount * _getSapienCoreStorage().protocolFeeBasisPoints) / 10000;
            amountAfterProtocolFee = rewardAmount - protocolFee;

            // Transfer protocol fee to _getSapienCoreStorage().treasury
            project.rewardToken.safeTransferFrom(msg.sender, _getSapienCoreStorage().treasury, protocolFee);
            emit ProtocolFeeCollected(projectId, address(project.rewardToken), protocolFee);
        }

        // Operator Fee Logic - taken from remaining amount after protocol fee
        if (operatorFeeBps > MAX_ORGINATION_OPERATOR_FEE_BPS) revert InvalidAmount();

        uint256 operatorFee = 0;
        uint256 rewardAmountAfterFee = amountAfterProtocolFee;

        if (operator != address(0) && operatorFeeBps > 0 && amountAfterProtocolFee > 0) {
            operatorFee = (amountAfterProtocolFee * operatorFeeBps) / 10000;
            rewardAmountAfterFee = amountAfterProtocolFee - operatorFee;

            project.rewardToken.safeTransferFrom(msg.sender, operator, operatorFee);
            emit OperatorFeePaid(projectId, operator, operatorFee);
        }

        // Opus 4.6 L-2 fix: Anti-dilution check uses post-fee amount.
        // Previously used gross rewardAmount, which allowed effective dilution after fees.
        if (project.state.totalQuantityAvailable > 0 && quantity > 0) {
            if (
                rewardAmountAfterFee * project.state.totalQuantityAvailable
                    < project.state.totalRewardsAvailable * quantity
            ) {
                revert RewardDilutionNotAllowed();
            }
        }

        // Issue #4 fix: Check minimum reward per slot to prevent precision loss
        if (quantity > 0) {
            uint256 newTotalRewards = project.state.totalRewardsAvailable + rewardAmountAfterFee;
            uint256 newTotalQuantity = project.state.totalQuantityAvailable + quantity;
            // Calculate effective contributor reward (after validator share)
            uint256 contributorShare = newTotalRewards * (10000 - project.config.validatorRewardBasisPoints) / 10000;
            uint256 effectiveRewardPerSlot = contributorShare / newTotalQuantity;
            if (effectiveRewardPerSlot < MIN_REWARD_PER_SLOT) {
                revert RewardPerSlotTooLow(effectiveRewardPerSlot, MIN_REWARD_PER_SLOT);
            }
        }

        // Update project state with the reward amount after fee (actual amount available for rewards)
        project.state.totalRewardsAvailable += rewardAmountAfterFee;
        project.state.totalQuantityAvailable += quantity;

        // Transfer remaining amount to rewards contract
        // Issue #11 fix: Check actual balance for fee-on-transfer token compatibility
        if (rewardAmountAfterFee > 0) {
            uint256 balanceBefore = project.rewardToken.balanceOf(address(_getSapienCoreStorage().rewards));
            project.rewardToken
                .safeTransferFrom(msg.sender, address(_getSapienCoreStorage().rewards), rewardAmountAfterFee);
            uint256 balanceAfter = project.rewardToken.balanceOf(address(_getSapienCoreStorage().rewards));
            uint256 actualReceived = balanceAfter - balanceBefore;

            // Update totalRewardsAvailable to reflect actual received amount (not requested)
            if (actualReceived < rewardAmountAfterFee) {
                // Adjust for fee-on-transfer token
                project.state.totalRewardsAvailable -= (rewardAmountAfterFee - actualReceived);
            }

            _getSapienCoreStorage().rewards.allocateRewards(projectId, address(project.rewardToken), actualReceived);
        }

        emit ProjectFunded(projectId, rewardAmount, quantity, rewardAmountAfterFee);
    }

    /**
     * @notice Reclaim contribution slots that were claimed but not submitted by the deadline
     * @param projectId Unique identifier for the project
     * @param indices The indices within the project's contribution sequence to reclaim
     */
    function reclaimExpiredIndices(bytes32 projectId, uint256[] calldata indices) external nonReentrant {
        // F-12 fix: Prevent DoS via gas exhaustion from unbounded loops
        if (indices.length > MAX_BATCH_SIZE) revert BatchSizeTooLarge(indices.length, MAX_BATCH_SIZE);
        Project storage project = _getSapienCoreStorage().projects[projectId];
        for (uint256 i = 0; i < indices.length; ++i) {
            uint256 index = indices[i];
            IndexReservation storage reservation = _getSapienCoreStorage().indexReservations[projectId][index];

            if (reservation.claimant == address(0)) continue;
            if (block.timestamp <= reservation.deadline) continue;

            // If it was already submitted, it can't be reclaimed this way (must be finalized)
            if (_getSapienCoreStorage().contributions[projectId][index].submittedAt != 0) continue;

            address claimant = reservation.claimant;
            delete _getSapienCoreStorage().indexReservations[projectId][index];

            _addToAvailableIndices(projectId, index);
            --project.state.activeClaimedQuantity;
            if (_getSapienCoreStorage().userActiveClaimedQuantity[projectId][claimant] > 0) {
                --_getSapienCoreStorage().userActiveClaimedQuantity[projectId][claimant];
            }

            emit IndexReclaimed(projectId, index, claimant);
        }
    }

    // ============================================
    // CONTRIBUTION FUNCTIONS
    // ============================================

    /**
     * @notice Claim a number of contribution slots in a project
     * @param projectId Unique identifier for the project
     * @param quantity Number of slots to claim
     * @return claimId Unique identifier for the created claim
     */
    function claimToContribute(bytes32 projectId, uint256 quantity) external nonReentrant returns (uint256 claimId) {
        Project storage project = _getSapienCoreStorage().projects[projectId];
        _verifyClaimEligibility(projectId, quantity, project);

        // Issue #6 fix: Limit claims per user to prevent slot starvation
        uint256 userCurrentClaims = _getSapienCoreStorage().userActiveClaimedQuantity[projectId][msg.sender];
        if (userCurrentClaims + quantity > MAX_CLAIMS_PER_USER) {
            revert MaxClaimsPerUserExceeded(quantity, userCurrentClaims, MAX_CLAIMS_PER_USER);
        }

        // 2. Verify Stake
        if (project.config.minStakeToClaim > 0) {
            uint256 stake = _getSapienCoreStorage().vault.getStake(msg.sender);
            if (stake < project.config.minStakeToClaim) {
                revert InsufficientContributorStake(msg.sender, project.config.minStakeToClaim, stake);
            }
            _lockStakeForClaim(msg.sender, project.config.minStakeToClaim);
        }

        // 3. Record Claim
        claimId = _getSapienCoreStorage().nextClaimId[projectId]++;
        uint256 deadline = block.timestamp + (project.config.claimDeadlineDays * 1 days);

        _getSapienCoreStorage().claims[projectId][claimId] = Claim({
            contributor: msg.sender,
            quantity: quantity,
            claimedAt: block.timestamp,
            deadline: deadline,
            submittedCount: 0,
            finalizedCount: 0,
            status: ClaimStatus.Active
        });

        _assignIndices(projectId, quantity, claimId, deadline, project);

        project.state.activeClaimedQuantity += quantity;
        _getSapienCoreStorage().userActiveClaimedQuantity[projectId][msg.sender] += quantity;
        emit ClaimCreated(projectId, claimId, msg.sender, quantity, deadline);
    }

    /**
     * @notice Internal helper to verify if a user is eligible to claim slots
     * @dev Verify that a user is eligible to claim contribution slots
     * @param projectId Unique identifier for the project
     * @param quantity Number of slots to claim
     * @param project Storage reference to the project
     */
    function _verifyClaimEligibility(bytes32 projectId, uint256 quantity, Project storage project) internal view {
        if (project.originator == address(0)) revert ProjectDoesNotExist(projectId);
        if (quantity == 0) revert InvalidAmount();
        if (msg.sender == project.originator) revert Unauthorized(UNAUTHORIZED_ORIGINATOR_CANNOT_CONTRIBUTE);
        _getSapienCoreStorage().trust.hasEnoughStakeForRole(msg.sender, CONTRIBUTOR_ROLE);

        uint256 available = project.state.totalQuantityAvailable
            - (project.state.submittedQuantity + project.state.activeClaimedQuantity);
        if (quantity > available) revert InsufficientQuantityAvailable(projectId, quantity, available);
    }

    /**
     * @notice Internal helper to assign indices to a claim
     * @dev Assign contribution indices to a claim, reusing expired indices when available
     * @param projectId Unique identifier for the project
     * @param quantity Number of indices to assign
     * @param claimId Unique identifier for the claim
     * @param deadline Deadline timestamp for the indices
     * @param project Storage reference to the project
     */
    function _assignIndices(
        bytes32 projectId,
        uint256 quantity,
        uint256 claimId,
        uint256 deadline,
        Project storage project
    ) internal {
        for (uint256 i = 0; i < quantity; ++i) {
            uint256 assignedIndex;
            if (_getSapienCoreStorage().stackTop[projectId] > 0) {
                assignedIndex =
                    _getSapienCoreStorage().availableIndices[projectId][_getSapienCoreStorage().stackTop[projectId]];
                _getSapienCoreStorage().stackTop[projectId]--;
                _getSapienCoreStorage().indexIsAvailable[projectId][assignedIndex] = false; // No longer available
            } else {
                assignedIndex = project.state.nextContributionIndex;
                project.state.nextContributionIndex++;
            }
            _getSapienCoreStorage().indexReservations[projectId][assignedIndex] =
            // forge-lint: disable-next-line(unsafe-typecast)
            // casting to 'uint48' is safe because deadline is block.timestamp + claimDeadlineDays * 1 days,
            // which fits in uint48 (max ~8.9 million years)
            IndexReservation({claimant: msg.sender, deadline: uint48(deadline)});
            emit IndexAssigned(projectId, claimId, assignedIndex, msg.sender, deadline);
        }
    }

    function releaseExpiredClaim(bytes32 projectId, uint256 claimId) external nonReentrant {
        Project storage project = _getSapienCoreStorage().projects[projectId];
        Claim storage claim = _getSapienCoreStorage().claims[projectId][claimId];

        if (claim.status != ClaimStatus.Active) revert ClaimNotActive(claimId);
        if (block.timestamp <= claim.deadline) revert ClaimNotExpired(claimId, claim.deadline);

        // We don't automatically reclaim indices here because we don't store them in the claim.
        // Users or the system must call reclaimExpiredIndices for specific indices.

        claim.status = ClaimStatus.Expired;

        // Opus 4.6 L-1 fix: Decrement userActiveClaimedQuantity for unsubmitted slots.
        // Without this, the user's claim counter stays inflated after releaseExpiredClaim,
        // soft-locking them from new claims until reclaimExpiredIndices is called per-index.
        uint256 unsubmittedSlots = claim.quantity - claim.submittedCount;
        if (unsubmittedSlots > 0) {
            uint256 currentCount = _getSapienCoreStorage().userActiveClaimedQuantity[projectId][claim.contributor];
            if (currentCount >= unsubmittedSlots) {
                _getSapienCoreStorage().userActiveClaimedQuantity[projectId][claim.contributor] =
                    currentCount - unsubmittedSlots;
            } else {
                _getSapienCoreStorage().userActiveClaimedQuantity[projectId][claim.contributor] = 0;
            }
        }

        uint256 slashedAmount = 0;
        if (project.config.minStakeToClaim > 0) {
            uint256 locked = _getSapienCoreStorage().vault.getLockedStake(claim.contributor);
            slashedAmount = project.config.minStakeToClaim > locked ? locked : project.config.minStakeToClaim;
            if (slashedAmount > 0) {
                _unlockStakeForClaimExpired(claim.contributor, slashedAmount);
                _getSapienCoreStorage().vault.slash(claim.contributor, slashedAmount, projectId);
            }
        }

        emit ClaimExpired(projectId, claimId, claim.contributor, slashedAmount);
    }

    /**
     * @notice Submit a contribution for a specific slot in a claim
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param contributionIndex The index within the project's contribution sequence
     * @param submissionHash Hash of the submitted work (e.g. IPFS CID)
     */
    function contribute(bytes32 projectId, uint256 claimId, uint256 contributionIndex, bytes32 submissionHash)
        external
        nonReentrant
    {
        _contribute(projectId, claimId, contributionIndex, submissionHash);
    }

    /**
     * @notice Submit multiple contributions for a project in a single transaction
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param contributionIndices The indices within the project's contribution sequence
     * @param submissionHashes Hashes of the submitted work (e.g. IPFS CID)
     */
    function batchContribute(
        bytes32 projectId,
        uint256 claimId,
        uint256[] calldata contributionIndices,
        bytes32[] calldata submissionHashes
    ) external nonReentrant {
        if (contributionIndices.length != submissionHashes.length) {
            revert Unauthorized(UNAUTHORIZED_ARRAY_LENGTH_MISMATCH);
        }
        // F-12 fix: Prevent DoS via gas exhaustion from unbounded loops
        if (contributionIndices.length > MAX_BATCH_SIZE) {
            revert BatchSizeTooLarge(contributionIndices.length, MAX_BATCH_SIZE);
        }
        for (uint256 i = 0; i < contributionIndices.length; ++i) {
            _contribute(projectId, claimId, contributionIndices[i], submissionHashes[i]);
        }
    }

    function _contribute(bytes32 projectId, uint256 claimId, uint256 contributionIndex, bytes32 submissionHash)
        internal
    {
        Claim storage claim = _getSapienCoreStorage().claims[projectId][claimId];
        if (claim.contributor != msg.sender) revert Unauthorized(UNAUTHORIZED_NOT_CLAIM_OWNER);
        if (claim.status != ClaimStatus.Active) revert ClaimNotActive(claimId);
        if (block.timestamp > claim.deadline) revert ClaimAlreadyExpired(claimId, claim.deadline);

        // Verify assignment
        IndexReservation memory reservation = _getSapienCoreStorage().indexReservations[projectId][contributionIndex];
        if (reservation.claimant != msg.sender) revert Unauthorized(UNAUTHORIZED_NOT_INDEX_OWNER);
        if (block.timestamp > reservation.deadline) {
            revert ClaimAlreadyExpired(claimId, reservation.deadline);
        }

        if (_getSapienCoreStorage().contributions[projectId][contributionIndex].submittedAt != 0) {
            revert ContributionAlreadySubmitted(contributionIndex);
        }

        // F-11 fix: Snapshot the reward rate at submission time to prevent sandwiching attacks.
        // This locks the contributor's reward at the rate in effect when they submit, so
        // frontrunning/backrunning fundProject cannot manipulate their payout.
        uint256 rewardSnapshot = _calculateContributorReward(_getSapienCoreStorage().projects[projectId]);

        _getSapienCoreStorage().contributions[projectId][contributionIndex] = Contribution({
            projectId: projectId,
            contributor: msg.sender,
            claimId: claimId,
            contributionIndex: contributionIndex,
            submissionHash: submissionHash,
            submittedAt: block.timestamp,
            totalValidations: 0,
            averageScore: 0,
            challengeEndsAt: 0,
            status: ContributionStatus.Pending,
            rewardRateSnapshot: rewardSnapshot
        });

        // CEI Pattern: Effects (state changes) before Interactions (external calls)
        claim.submittedCount++;
        _getSapienCoreStorage().projects[projectId].state.submittedQuantity++;
        _getSapienCoreStorage().projects[projectId].state.activeClaimedQuantity--;
        // Issue #6 fix: Decrease user's active claim count
        if (_getSapienCoreStorage().userActiveClaimedQuantity[projectId][msg.sender] > 0) {
            _getSapienCoreStorage().userActiveClaimedQuantity[projectId][msg.sender]--;
        }

        if (claim.submittedCount == claim.quantity) {
            claim.status = ClaimStatus.Fulfilled;
            emit ClaimFulfilled(projectId, claimId, msg.sender);
        }

        // Interactions (external calls) after state changes
        _getSapienCoreStorage().oracle.setContributionContributor(projectId, contributionIndex, msg.sender);
        _getSapienCoreStorage().oracle.enqueueValidation(projectId, contributionIndex, block.timestamp);

        emit ContributionSubmitted(projectId, contributionIndex, msg.sender, claimId, submissionHash);
    }

    // ============================================
    // FINALIZATION FUNCTIONS
    // ============================================

    /**
     * @notice Finalize a contribution by calculating consensus and distributing rewards/slashing
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     */
    function finalizeContribution(bytes32 projectId, uint256 contributionIndex) external nonReentrant {
        _finalizeContribution(projectId, contributionIndex);
    }

    /**
     * @notice Finalize multiple contributions for a project in a single transaction
     * @param projectId Unique identifier for the project
     * @param contributionIndices The indices within the project's contribution sequence
     */
    function batchFinalizeContributions(bytes32 projectId, uint256[] calldata contributionIndices)
        external
        nonReentrant
    {
        // F-12 fix: Prevent DoS via gas exhaustion from unbounded loops
        if (contributionIndices.length > MAX_BATCH_SIZE) {
            revert BatchSizeTooLarge(contributionIndices.length, MAX_BATCH_SIZE);
        }
        for (uint256 i = 0; i < contributionIndices.length; ++i) {
            _finalizeContribution(projectId, contributionIndices[i]);
        }
    }

    function _finalizeContribution(bytes32 projectId, uint256 contributionIndex) internal {
        Contribution storage contrib = _getSapienCoreStorage().contributions[projectId][contributionIndex];
        if (contrib.submittedAt == 0) revert ContributionDoesNotExist(projectId, contributionIndex);
        if (contrib.status != ContributionStatus.Pending) revert AlreadyRewarded();

        Project storage project = _getSapienCoreStorage().projects[projectId];

        // 1. Get Consensus from Oracle
        ConsensusReport memory report = _fetchConsensus(projectId, contributionIndex);

        if (!report.isReady) revert ValidationNotReady(projectId, contributionIndex);

        // 2. Process Outcome
        bool accepted = report.weightedAverage >= _getSapienCoreStorage().consensusThreshold;

        // CEI Pattern: Effects (state changes) before Interactions (external calls)
        // Store contributor address, claimId, and submittedAt before potential deletion
        address contribContributor = contrib.contributor;
        uint256 contribClaimId = contrib.claimId;
        uint256 contributionSubmittedAt = contrib.submittedAt;

        ContributionStatus finalStatus;
        {
            finalStatus = accepted ? ContributionStatus.Validated : ContributionStatus.Rejected;
            contrib.status = finalStatus;
            contrib.averageScore = report.weightedAverage;
            contrib.totalValidations = report.validatorCount;
            if (accepted) {
                contrib.challengeEndsAt = block.timestamp + project.config.challengePeriod;
            }
        }

        // Handle state changes for claim unlock (must access claim before deletion)
        Claim storage claim = _getSapienCoreStorage().claims[projectId][contribClaimId];
        claim.finalizedCount++;
        bool shouldUnlockStake = claim.finalizedCount == claim.quantity;
        uint256 stakeToUnlock = shouldUnlockStake ? project.config.minStakeToClaim : 0;

        if (accepted) {
            // State changes for accepted contribution
            project.state.rewardedQuantity++;
        } else {
            // State changes for rejected contribution
            _addToAvailableIndices(projectId, contributionIndex);
            project.state.submittedQuantity--;

            // Calculate and track preserved rewards
            // When a contribution is rejected, the contributor reward portion remains
            // in projectRewards and becomes available for future contributions
            uint256 preservedReward = _calculateContributorReward(project);

            // Reset assignment and contribution record so it can be claimed/submitted again
            delete _getSapienCoreStorage().indexReservations[projectId][contributionIndex];
            delete _getSapienCoreStorage().contributions[projectId][contributionIndex];

            // Emit event for transparency - these rewards remain in projectRewards
            // and are automatically available for the next contributor
            if (preservedReward > 0) {
                emit ContributorRewardPreserved(
                    projectId, contributionIndex, address(project.rewardToken), preservedReward
                );
            }
        }

        // Interactions (external calls) after all state changes
        // 3. Update Contributor Reputation & Rewards/Slashing
        _getSapienCoreStorage().trust
            .updateReputation(contribContributor, CONTRIBUTOR_ROLE, accepted, report.weightedAverage);

        // 4. Handle Claim Unlock (external call for stake unlock)
        if (shouldUnlockStake && stakeToUnlock > 0) {
            _unlockStakeForClaimFinalized(contribContributor, stakeToUnlock);
        }

        if (accepted) {
            // Auto-validate skill if project has one required
            _validateSkillIfRequired(project, contribContributor);
            // Reward distribution is now deferred to claimContributionReward after challenge period
        } else {
            // Notify oracle to reset validation state for this index
            _getSapienCoreStorage().oracle.resetContributionState(projectId, contributionIndex);
        }

        // 5. Handle Validators (Slashing always; rewards only on acceptance)
        // F-08/M-1 fix: Don't pay validators on rejection. When rejected, the slot goes back
        // into the pool and will be re-done; paying validators twice would drain the reward
        // pool. Slashing outliers still applies in both accepted and rejected cases.
        _processValidators(
            projectId,
            contributionIndex,
            project,
            report.validatorsToSlash,
            report.slashAmounts,
            report.validatorWeights,
            accepted,
            contributionSubmittedAt
        );

        emit ConsensusReached(projectId, contributionIndex, report.weightedAverage, report.validatorCount);
        emit ContributionFinalized(
            projectId, contributionIndex, finalStatus, report.weightedAverage, contribContributor, contribClaimId
        );
    }

    /**
     * @notice Claim rewards for a validated contribution after the challenge period
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     */
    function claimContributionReward(bytes32 projectId, uint256 contributionIndex) external nonReentrant {
        Contribution storage contrib = _getSapienCoreStorage().contributions[projectId][contributionIndex];
        if (contrib.status != ContributionStatus.Validated) revert NotAvailableForClaim();
        if (block.timestamp <= contrib.challengeEndsAt) revert ChallengePeriodActive();

        Project storage project = _getSapienCoreStorage().projects[projectId];
        // F-11 fix: Use the snapshotted reward rate from submission time (prevents sandwiching).
        // Falls back to live calculation for contributions submitted before the snapshot was added.
        uint256 reward =
            contrib.rewardRateSnapshot > 0 ? contrib.rewardRateSnapshot : _calculateContributorReward(project);

        contrib.status = ContributionStatus.Rewarded;

        if (reward > 0) {
            _getSapienCoreStorage().rewards
                .distributeReward(projectId, contrib.contributor, address(project.rewardToken), reward);
        }

        emit ContributionRewarded(
            projectId, contributionIndex, contrib.contributor, reward, address(project.rewardToken)
        );
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    /**
     * @dev Lock stake for a claim
     * @param user Address of the user
     * @param amount Amount of stake to lock
     */
    function _lockStakeForClaim(address user, uint256 amount) internal {
        _getSapienCoreStorage().vault.lockStake(user, amount, "claim");
    }

    /**
     * @dev Unlock stake when a claim expires
     * @param user Address of the user
     * @param amount Amount of stake to unlock
     */
    function _unlockStakeForClaimExpired(address user, uint256 amount) internal {
        _getSapienCoreStorage().vault.unlockStake(user, amount, "claim_expired");
    }

    /**
     * @dev Unlock stake when a claim is finalized
     * @param user Address of the user
     * @param amount Amount of stake to unlock
     */
    function _unlockStakeForClaimFinalized(address user, uint256 amount) internal {
        _getSapienCoreStorage().vault.unlockStake(user, amount, "claim_finalized");
    }

    /**
     * @dev Validate a skill for a user if the project requires it
     * @param project Storage reference to the project
     * @param user Address of the user
     */
    function _validateSkillIfRequired(Project storage project, address user) internal {
        if (bytes(project.config.requiredSkill).length == 0) return;
        _getSapienCoreStorage().trust.validateSkill(user, project.config.requiredSkill);
    }

    /**
     * @notice Safely add an index to the available indices stack, preventing duplicates
     * @param projectId The project ID
     * @param index The contribution index to add
     */
    function _addToAvailableIndices(bytes32 projectId, uint256 index) internal {
        // Prevent duplicate entries in the available indices stack
        if (_getSapienCoreStorage().indexIsAvailable[projectId][index]) {
            return; // Index is already available, don't add again
        }

        _getSapienCoreStorage().stackTop[projectId]++;
        _getSapienCoreStorage().availableIndices[projectId][_getSapienCoreStorage().stackTop[projectId]] = index;
        _getSapienCoreStorage().indexIsAvailable[projectId][index] = true;
    }

    /**
     * @dev Fetch consensus report from the oracle
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @return report Consensus report with weighted average and slash information
     */
    function _fetchConsensus(bytes32 projectId, uint256 contributionIndex)
        internal
        view
        returns (ConsensusReport memory report)
    {
        return _getSapienCoreStorage().oracle.getConsensus(projectId, contributionIndex);
    }

    /**
     * @dev Fetch all validations for a contribution
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     * @return vals Array of validation structs
     */
    function _fetchValidations(bytes32 projectId, uint256 contributionIndex)
        internal
        view
        returns (Validation[] memory vals)
    {
        return _getSapienCoreStorage().oracle.getValidations(projectId, contributionIndex);
    }

    /**
     * @notice Calculate the reward for a single contribution in a project
     * @param project The project storage reference
     * @return rewardAmount The amount of reward tokens per contribution
     */
    function _calculateContributorReward(Project storage project) internal view returns (uint256) {
        if (project.state.totalQuantityAvailable == 0) return 0;
        return (project.state.totalRewardsAvailable * (10000 - project.config.validatorRewardBasisPoints))
            / (10000 * project.state.totalQuantityAvailable);
    }

    /**
     * @notice Process validator slashes and rewards after consensus is reached
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the finalized contribution
     * @param project The project storage reference
     * @param toSlash List of validators to be slashed
     * @param slashAmounts Corresponding slash amounts
     * @param consensusWeights Weights from consensus (for reward distribution)
     * @param accepted True if contribution was accepted; rewards only when true
     * @param contributionSubmittedAt When the contribution was submitted (filters out stale validations)
     */
    function _processValidators(
        bytes32 projectId,
        uint256 contributionIndex,
        Project storage project,
        address[] memory toSlash,
        uint256[] memory slashAmounts,
        uint256[] memory consensusWeights,
        bool accepted,
        uint256 contributionSubmittedAt
    ) internal {
        // 1. Slash Outliers (always, for both accepted and rejected)
        for (uint256 i = 0; i < toSlash.length; ++i) {
            if (slashAmounts[i] > 0) {
                _getSapienCoreStorage().vault.slash(toSlash[i], slashAmounts[i], projectId);
                _getSapienCoreStorage().oracle
                    .handleValidatorSlash(projectId, contributionIndex, toSlash[i], slashAmounts[i]);
                _getSapienCoreStorage().trust.updateReputation(toSlash[i], VALIDATOR_ROLE, false, 0);
            }
        }

        // 2. Distribute Rewards to Accurate Validators (only when contribution is accepted)
        if (accepted) {
            _distributeValidatorRewards(
                projectId, contributionIndex, project, toSlash, consensusWeights, contributionSubmittedAt
            );
        }
    }

    /**
     * @dev Distribute validator rewards proportionally based on consensus algorithm weights
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the finalized contribution
     * @param project Storage reference to the project
     * @param toSlash Array of validators to exclude from rewards
     * @param consensusWeights Weights from the consensus algorithm (parallel to validations array)
     * @param contributionSubmittedAt Filter validations to those from this submission (avoids paying
     *        validators from a prior rejected round when the same index is re-submitted)
     */
    function _distributeValidatorRewards(
        bytes32 projectId,
        uint256 contributionIndex,
        Project storage project,
        address[] memory toSlash,
        uint256[] memory consensusWeights,
        uint256 contributionSubmittedAt
    ) internal {
        Validation[] memory allVals = _fetchValidations(projectId, contributionIndex);

        // Filter to validations from the current submission only (matches _prepareValidationInputs).
        // After rejection+resubmit, the oracle retains old validations; we must not pay them.
        // Use > (not >=) so validations revealed in the same block as contribution submit are
        // excluded (reject-then-immediate-resubmit edge case).
        uint256 validCount = 0;
        for (uint256 i = 0; i < allVals.length; ++i) {
            if (allVals[i].submittedAt > contributionSubmittedAt) validCount++;
        }
        if (validCount == 0 || project.state.totalQuantityAvailable == 0) return;

        Validation[] memory vals = new Validation[](validCount);
        uint256 idx = 0;
        for (uint256 i = 0; i < allVals.length; ++i) {
            if (allVals[i].submittedAt > contributionSubmittedAt) {
                vals[idx] = allVals[i];
                idx++;
            }
        }

        // Use consensus weights when available (M-1 fix: ensures reward distribution
        // matches the same weight formula used by the consensus algorithm).
        // Falls back to ConsensusLib.calculateBaseWeight when weights are unavailable.
        bool useConsensusWeights = consensusWeights.length == vals.length;

        // Calculate total weight for accurate (non-outlier) validators
        uint256 totalAccurateWeight = 0;
        for (uint256 i = 0; i < vals.length; ++i) {
            if (!_isOutlier(vals[i].validator, toSlash)) {
                uint256 weight = useConsensusWeights
                    ? consensusWeights[i]
                    : ConsensusLib.calculateBaseWeight(
                        vals[i].stakeAmount,
                        _getSapienCoreStorage().trust.getTrustScore(vals[i].validator, VALIDATOR_ROLE)
                    );
                totalAccurateWeight += weight;
            }
        }

        // Prevent division by zero - if no accurate validators have weight, skip reward distribution
        if (totalAccurateWeight == 0) return;

        // Distribute rewards proportionally using consensus weights
        for (uint256 i = 0; i < vals.length; ++i) {
            if (!_isOutlier(vals[i].validator, toSlash)) {
                uint256 weight = useConsensusWeights
                    ? consensusWeights[i]
                    : ConsensusLib.calculateBaseWeight(
                        vals[i].stakeAmount,
                        _getSapienCoreStorage().trust.getTrustScore(vals[i].validator, VALIDATOR_ROLE)
                    );

                // Multiply before divide to avoid precision loss
                // Formula: (totalRewards * validatorBasisPoints * weight) / (10000 * totalQuantity * totalAccurateWeight)
                uint256 reward =
                    (project.state.totalRewardsAvailable * project.config.validatorRewardBasisPoints * weight)
                        / (10000 * project.state.totalQuantityAvailable * totalAccurateWeight);

                // Issue #7 fix: Ensure a minimum reward floor of 1 unit if math rounds to zero
                // This prevents validator pool collapse for low-decimal tokens or small weights.
                if (reward == 0 && weight > 0 && project.state.totalRewardsAvailable > 0) {
                    reward = 1;
                }

                if (reward > 0) {
                    _getSapienCoreStorage().rewards
                        .distributeValidatorReward(projectId, vals[i].validator, address(project.rewardToken), reward);
                }
                _getSapienCoreStorage().trust.updateReputation(vals[i].validator, VALIDATOR_ROLE, true, 0);
            }
        }
    }

    /**
     * @dev Check if a validator is in the outliers list
     * @param validator Address of the validator
     * @param outliers Array of outlier validator addresses
     * @return True if validator is an outlier
     */
    function _isOutlier(address validator, address[] memory outliers) internal pure returns (bool) {
        for (uint256 i = 0; i < outliers.length; ++i) {
            if (outliers[i] == validator) return true;
        }
        return false;
    }

    // ============================================
    // GETTER FUNCTIONS
    // ============================================

    /**
     * @notice Get project information
     * @param projectId Unique identifier for the project
     * @return Project struct containing configuration and state
     */
    function getProject(bytes32 projectId) external view returns (Project memory) {
        return _getSapienCoreStorage().projects[projectId];
    }

    /**
     * @notice Get claim information
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @return Claim struct containing claim details
     */
    function getClaim(bytes32 projectId, uint256 claimId) external view returns (Claim memory) {
        return _getSapienCoreStorage().claims[projectId][claimId];
    }

    /**
     * @notice Get contribution information
     * @param projectId Unique identifier for the project
     * @param index Contribution index within the project
     * @return Contribution struct containing contribution details
     */
    function getContribution(bytes32 projectId, uint256 index) external view returns (Contribution memory) {
        return _getSapienCoreStorage().contributions[projectId][index];
    }

    /**
     * @notice Get the next claim ID for a project
     * @param projectId Unique identifier for the project
     * @return Next claim ID that will be assigned
     */
    function getNextClaimId(bytes32 projectId) external view returns (uint256) {
        return _getSapienCoreStorage().nextClaimId[projectId];
    }

    /**
     * @notice Get the claimant address for a specific contribution index
     * @param projectId Unique identifier for the project
     * @param index Contribution index within the project
     * @return Address of the user who claimed this index
     */
    function getIndexToClaimant(bytes32 projectId, uint256 index) external view returns (address) {
        return _getSapienCoreStorage().indexReservations[projectId][index].claimant;
    }

    /**
     * @notice Get the deadline for a specific contribution index
     * @param projectId Unique identifier for the project
     * @param index Contribution index within the project
     * @return Deadline timestamp for submitting the contribution
     */
    function getIndexClaimDeadline(bytes32 projectId, uint256 index) external view returns (uint256) {
        return _getSapienCoreStorage().indexReservations[projectId][index].deadline;
    }

    /**
     * @notice Get the vault contract address
     * @return Address of the SapienVault contract
     */
    function getVault() external view returns (address) {
        return address(_getSapienCoreStorage().vault);
    }

    /**
     * @notice Get the rewards contract address
     * @return Address of the Rewards contract
     */
    function getRewards() external view returns (address) {
        return address(_getSapienCoreStorage().rewards);
    }

    /**
     * @notice Get the trust contract address
     * @return Address of the SapienTrust contract
     */
    function getTrust() external view returns (address) {
        return address(_getSapienCoreStorage().trust);
    }

    /**
     * @notice Get the oracle contract address
     * @return Address of the ValidationOracle contract
     */
    function getValidationOracle() external view returns (address) {
        return address(_getSapienCoreStorage().oracle);
    }

    // ============================================
    // VIEW GETTERS (match ISapienCore interface)
    // ============================================

    function protocolFeeBasisPoints() external view returns (uint256) {
        return _getSapienCoreStorage().protocolFeeBasisPoints;
    }

    function treasury() external view returns (address) {
        return _getSapienCoreStorage().treasury;
    }

    function consensusThreshold() external view returns (uint256) {
        return _getSapienCoreStorage().consensusThreshold;
    }

    function challengePeriod() external view returns (uint256) {
        return _getSapienCoreStorage().challengePeriod;
    }
}
