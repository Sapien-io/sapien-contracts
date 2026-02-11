// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {
    ReentrancyGuardUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {ISapienVault} from "./interface/ISapienVault.sol";
import {IRewards} from "./interface/IRewards.sol";
import {ISapienTrust} from "./interface/ISapienTrust.sol";
import {IValidationOracle} from "./interface/IValidationOracle.sol";
import {ISapienCore} from "./interface/ISapienCore.sol";
import {
    ORIGINATOR_ROLE,
    CONTRIBUTOR_ROLE,
    VALIDATOR_ROLE,
    UPDATER_ROLE,
    UNAUTHORIZED_MISSING_ORIGINATOR_ROLE,
    UNAUTHORIZED_MISSING_CONTRIBUTOR_ROLE,
    UNAUTHORIZED_NOT_PROJECT_ORIGINATOR,
    UNAUTHORIZED_ORIGINATOR_CANNOT_CONTRIBUTE,
    UNAUTHORIZED_NOT_CLAIM_OWNER,
    UNAUTHORIZED_NOT_INDEX_OWNER,
    UNAUTHORIZED_ARRAY_LENGTH_MISMATCH
} from "./interface/ISharedTypes.sol";
import {ConsensusLib} from "./libraries/ConsensusLib.sol";

/**
 * @title SapienCore
 * @notice Central coordinator for projects, contributions, and rewards.
 * @dev Merges ProjectRegistry and ContributionManager.
 *      Hierarchy: Core -> Oracle -> Trust -> Vault.
 */
contract SapienCore is ISapienCore, Initializable, AccessControlUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // ============================================
    // STATE VARIABLES
    // ============================================

    ISapienVault internal _vault;
    IRewards internal _rewards;
    ISapienTrust internal _trust;
    IValidationOracle internal _oracle;

    mapping(bytes32 => Project) internal projects;
    mapping(bytes32 => mapping(uint256 => Claim)) internal claims;
    mapping(bytes32 => uint256) internal nextClaimId;
    mapping(bytes32 => mapping(uint256 => Contribution)) internal contributions;
    mapping(bytes32 => mapping(uint256 => IndexReservation)) internal indexReservations;

    // Index management for re-queuing
    mapping(bytes32 => mapping(uint256 => uint256)) internal availableIndices;
    mapping(bytes32 => uint256) internal stackTop;
    mapping(bytes32 => mapping(uint256 => bool)) internal indexIsAvailable;

    uint256 internal _claimDeadlineDays;
    uint256 internal _maxValidations;

    // Protocol fee configuration
    /// @notice Protocol fee in basis points (e.g., 100 = 1%)
    /// @dev Default is 100 (1%)
    uint256 public protocolFeeBasisPoints; // Default 100 = 1%

    /// @notice Maximum protocol fee (3% = 300 basis points)
    uint256 public constant MAX_PROTOCOL_FEE_BPS = 300;

    /// @notice Maximum fee that a dapp operator can charge (2%)
    uint256 public constant MAX_OPERATOR_FEE_BPS = 200;

    /// @notice Minimum consensus threshold (10% = 1000 basis points)
    /// @dev Prevents threshold being set too low which would approve everything
    uint256 public constant MIN_CONSENSUS_THRESHOLD = 1000;

    /// @notice Minimum reward per contribution slot (1e15 wei = 0.001 tokens with 18 decimals)
    /// @dev Prevents precision loss from rounding rewards to zero
    uint256 public constant MIN_REWARD_PER_SLOT = 1e15;

    /// @notice Maximum active claimed slots per user per project (Issue #6 fix)
    /// @dev Prevents slot starvation attacks where one user claims all slots
    uint256 public constant MAX_CLAIMS_PER_USER = 10;

    /// @notice Treasury address to receive protocol fees
    address public treasury; // Address to receive protocol fees

    /// @notice Minimum score required for a contribution to be accepted (default 5000)
    uint256 public consensusThreshold;

    /// @notice Default challenge period for finalized contributions (default 1 day)
    uint256 public challengePeriod;

    /// @notice Track active claimed slots per user per project (Issue #6 fix)
    /// @dev projectId => user => activeClaimedQuantity
    mapping(bytes32 => mapping(address => uint256)) internal userActiveClaimedQuantity;

    // Storage gap for future upgrades
    // forge-lint: disable-next-line(mixed-case-variable)
    // __gap follows OpenZeppelin upgradeable contract pattern
    uint256[30] private __gap;

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

        _vault = ISapienVault(vaultAddr);
        _rewards = IRewards(rewardsAddr);
        _trust = ISapienTrust(trustAddr);
        _oracle = IValidationOracle(oracleAddr);

        _claimDeadlineDays = 7;
        _maxValidations = 10;
        protocolFeeBasisPoints = 100; // Default 1%
        consensusThreshold = 5000; // Default 50%
        challengePeriod = 1 days; // Default 1 day
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
        _claimDeadlineDays = _days;
    }

    /**
     * @notice Set the maximum number of validations allowed per contribution
     * @dev Only callable by admin. Maximum value is 100.
     * @param _max Maximum number of validations (max 100)
     */
    function setMaxValidations(uint256 _max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_max > 100) revert MaxValidationsExceeded(_max, 100);
        _maxValidations = _max;
        emit ISapienCore.MaxValidationsUpdated(_max);
    }

    /**
     * @notice Get the claim deadline in days
     * @return Number of days contributors have to submit after claiming
     */
    function getClaimDeadlineDays() external view returns (uint256) {
        return _claimDeadlineDays;
    }

    /**
     * @notice Get the maximum number of validations allowed per contribution
     * @return Maximum number of validations
     */
    function getMaxValidations() external view returns (uint256) {
        return _maxValidations;
    }

    /**
     * @notice Set the protocol fee basis points (e.g., 100 = 1%)
     * @param _feeBasisPoints The fee in basis points (max 300 = 3%)
     */
    function setProtocolFeeBasisPoints(uint256 _feeBasisPoints) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_feeBasisPoints > MAX_PROTOCOL_FEE_BPS) revert ProtocolFeeTooHigh(_feeBasisPoints, MAX_PROTOCOL_FEE_BPS);
        protocolFeeBasisPoints = _feeBasisPoints;
        emit ProtocolFeeUpdated(_feeBasisPoints);
    }

    /**
     * @notice Set the treasury address to receive protocol fees
     * @param _treasury The treasury address
     */
    function setTreasury(address _treasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_treasury == address(0)) revert InvalidAddress();
        treasury = _treasury;
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
        consensusThreshold = _threshold;
        emit ConsensusThresholdUpdated(_threshold);
    }

    /**
     * @notice Set the default challenge period for finalized contributions
     * @param _period The challenge period in seconds
     */
    function setChallengePeriod(uint256 _period) external onlyRole(DEFAULT_ADMIN_ROLE) {
        challengePeriod = _period;
        emit ChallengePeriodUpdated(_period);
    }

    // ============================================
    // PROJECT FUNCTIONS
    // ============================================

    function createProject(
        bytes32 projectId,
        address rewardToken,
        string memory ipfsCid, // The original IPFS CID of the project spec document
        uint256 minStakeToClaim,
        uint256 minStakeToContribute,
        uint256 minValidations,
        uint256 validatorRewardBasisPoints,
        string memory requiredSkill
    ) external returns (bytes32) {
        Project storage p = projects[projectId];

        if (p.originator != address(0)) {
            revert ProjectAlreadyExists(projectId);
        }
        _trust.hasEnoughStake(msg.sender, ORIGINATOR_ROLE);
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
        p.config.claimDeadlineDays = _claimDeadlineDays;
        p.config.minStakeToClaim = minStakeToClaim;
        p.config.minStakeToContribute = minStakeToContribute;
        p.config.minValidations = minValidations == 0 ? 3 : minValidations;
        p.config.maxValidations = _maxValidations;
        // Issue #7 fix: Ensure minValidations doesn't exceed maxValidations
        if (p.config.minValidations > p.config.maxValidations) {
            revert InvalidConfiguration();
        }
        p.config.validatorRewardBasisPoints = validatorRewardBasisPoints == 0 ? 1000 : validatorRewardBasisPoints;
        p.config.requiredSkill = requiredSkill;
        p.config.challengePeriod = challengePeriod;

        _registerProjectWithOracle(
            projectId, p.config.maxValidations, p.config.minValidations, requiredSkill, msg.sender
        );

        _trust.updateReputation(msg.sender, ORIGINATOR_ROLE, true, 0);

        emit ProjectCreated(
            p.projectId,
            p.originator,
            address(p.rewardToken),
            ipfsCid, // Emit the original IPFS CID so it can be retrieved from events
            p.config.claimDeadlineDays,
            p.config.minStakeToClaim,
            p.config.minStakeToContribute,
            p.config.minValidations,
            p.config.maxValidations,
            p.config.validatorRewardBasisPoints,
            p.config.requiredSkill
        );

        return projectId;
    }

    /**
     * @dev Register a project with the ValidationOracle
     * @param projectId Unique identifier for the project
     * @param maxValidations Maximum validations allowed for this project
     * @param minValidations Minimum validations required for consensus
     * @param requiredSkill Skill required for validators
     * @param originator Address of the project creator
     */
    function _registerProjectWithOracle(
        bytes32 projectId,
        uint256 maxValidations,
        uint256 minValidations,
        string memory requiredSkill,
        address originator
    ) internal {
        _oracle.registerProject(projectId, maxValidations, minValidations, requiredSkill, originator);
    }

    function fundProject(bytes32 projectId, uint256 rewardAmount, uint256 quantity) external nonReentrant {
        _fundProject(projectId, rewardAmount, quantity, address(0), 0);
    }

    function fundProject(
        bytes32 projectId,
        uint256 rewardAmount,
        uint256 quantity,
        address operator,
        uint256 operatorFeeBps
    ) external nonReentrant {
        _fundProject(projectId, rewardAmount, quantity, operator, operatorFeeBps);
    }

    function _fundProject(
        bytes32 projectId,
        uint256 rewardAmount,
        uint256 quantity,
        address operator,
        uint256 operatorFeeBps
    ) internal {
        Project storage project = projects[projectId];
        if (project.originator == address(0)) revert ProjectDoesNotExist(projectId);

        // FIX H-2: Access control - only originator can fund their project
        if (msg.sender != project.originator) revert Unauthorized(UNAUTHORIZED_NOT_PROJECT_ORIGINATOR);

        // FIX H-2: Prevent zero-cost dilution attacks
        // If adding quantity, must also add proportional rewards
        if (quantity > 0 && rewardAmount == 0) revert InvalidAmount();

        // Protocol Fee Logic - taken first from the original amount
        uint256 protocolFee = 0;
        uint256 amountAfterProtocolFee = rewardAmount;

        if (rewardAmount > 0 && protocolFeeBasisPoints > 0 && treasury != address(0)) {
            protocolFee = (rewardAmount * protocolFeeBasisPoints) / 10000;
            amountAfterProtocolFee = rewardAmount - protocolFee;

            // Transfer protocol fee to treasury
            project.rewardToken.safeTransferFrom(msg.sender, treasury, protocolFee);
            emit ProtocolFeeCollected(projectId, address(project.rewardToken), protocolFee);
        }

        // Operator Fee Logic - taken from remaining amount after protocol fee
        if (operatorFeeBps > MAX_OPERATOR_FEE_BPS) revert InvalidAmount();

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
            uint256 balanceBefore = project.rewardToken.balanceOf(address(_rewards));
            project.rewardToken.safeTransferFrom(msg.sender, address(_rewards), rewardAmountAfterFee);
            uint256 balanceAfter = project.rewardToken.balanceOf(address(_rewards));
            uint256 actualReceived = balanceAfter - balanceBefore;

            // Update totalRewardsAvailable to reflect actual received amount (not requested)
            if (actualReceived < rewardAmountAfterFee) {
                // Adjust for fee-on-transfer token
                project.state.totalRewardsAvailable -= (rewardAmountAfterFee - actualReceived);
            }

            _rewards.allocateRewards(projectId, address(project.rewardToken), actualReceived);
        }

        emit ProjectFunded(projectId, rewardAmount, quantity);
    }

    function reclaimExpiredIndices(bytes32 projectId, uint256[] calldata indices) external nonReentrant {
        Project storage project = projects[projectId];
        for (uint256 i = 0; i < indices.length; i++) {
            uint256 index = indices[i];
            IndexReservation storage reservation = indexReservations[projectId][index];

            if (reservation.claimant == address(0)) continue;
            if (block.timestamp <= reservation.deadline) continue;

            // If it was already submitted, it can't be reclaimed this way (must be finalized)
            if (contributions[projectId][index].submittedAt != 0) continue;

            address claimant = reservation.claimant;
            delete indexReservations[projectId][index];

            _addToAvailableIndices(projectId, index);
            project.state.activeClaimedQuantity--;
            // Issue #6 fix: Decrease user's active claim count
            if (userActiveClaimedQuantity[projectId][claimant] > 0) {
                userActiveClaimedQuantity[projectId][claimant]--;
            }

            emit IndexReclaimed(projectId, index, claimant);
        }
    }

    // ============================================
    // CONTRIBUTION FUNCTIONS
    // ============================================

    function claimToContribute(bytes32 projectId, uint256 quantity) external nonReentrant returns (uint256 claimId) {
        Project storage project = projects[projectId];
        _verifyClaimEligibility(projectId, quantity, project);

        // Issue #6 fix: Limit claims per user to prevent slot starvation
        uint256 userCurrentClaims = userActiveClaimedQuantity[projectId][msg.sender];
        if (userCurrentClaims + quantity > MAX_CLAIMS_PER_USER) {
            revert MaxClaimsPerUserExceeded(quantity, userCurrentClaims, MAX_CLAIMS_PER_USER);
        }

        // 2. Verify Stake
        if (project.config.minStakeToClaim > 0) {
            uint256 stake = _vault.getStake(msg.sender);
            if (stake < project.config.minStakeToClaim) {
                revert InsufficientContributorStake(msg.sender, project.config.minStakeToClaim, stake);
            }
            _lockStakeForClaim(msg.sender, project.config.minStakeToClaim);
        }

        // 3. Record Claim
        claimId = nextClaimId[projectId]++;
        uint256 deadline = block.timestamp + (project.config.claimDeadlineDays * 1 days);

        claims[projectId][claimId] = Claim({
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
        userActiveClaimedQuantity[projectId][msg.sender] += quantity;
        emit ClaimCreated(projectId, claimId, msg.sender, quantity);
    }

    /**
     * @dev Verify that a user is eligible to claim contribution slots
     * @param projectId Unique identifier for the project
     * @param quantity Number of slots to claim
     * @param project Storage reference to the project
     */
    function _verifyClaimEligibility(bytes32 projectId, uint256 quantity, Project storage project) internal view {
        if (project.originator == address(0)) revert ProjectDoesNotExist(projectId);
        // Opus 4.6 L-3 fix: Prevent zero-quantity claims that create orphaned state
        if (quantity == 0) revert InvalidAmount();
        if (msg.sender == project.originator) revert Unauthorized(UNAUTHORIZED_ORIGINATOR_CANNOT_CONTRIBUTE);
        _trust.hasEnoughStake(msg.sender, CONTRIBUTOR_ROLE);

        uint256 available = project.state.totalQuantityAvailable
            - (project.state.submittedQuantity + project.state.activeClaimedQuantity);
        if (quantity > available) revert InsufficientQuantityAvailable(projectId, quantity, available);
    }

    /**
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
        for (uint256 i = 0; i < quantity; i++) {
            uint256 assignedIndex;
            if (stackTop[projectId] > 0) {
                assignedIndex = availableIndices[projectId][stackTop[projectId]];
                stackTop[projectId]--;
                indexIsAvailable[projectId][assignedIndex] = false; // No longer available
            } else {
                assignedIndex = project.state.nextContributionIndex;
                project.state.nextContributionIndex++;
            }
            indexReservations[projectId][assignedIndex] =
            // forge-lint: disable-next-line(unsafe-typecast)
            // casting to 'uint48' is safe because deadline is block.timestamp + claimDeadlineDays * 1 days,
            // which fits in uint48 (max ~8.9 million years)
            IndexReservation({claimant: msg.sender, deadline: uint48(deadline)});
            emit IndexAssigned(projectId, claimId, assignedIndex, msg.sender);
        }
    }

    function releaseExpiredClaim(bytes32 projectId, uint256 claimId) external nonReentrant {
        Project storage project = projects[projectId];
        Claim storage claim = claims[projectId][claimId];

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
            uint256 currentCount = userActiveClaimedQuantity[projectId][claim.contributor];
            if (currentCount >= unsubmittedSlots) {
                userActiveClaimedQuantity[projectId][claim.contributor] = currentCount - unsubmittedSlots;
            } else {
                userActiveClaimedQuantity[projectId][claim.contributor] = 0;
            }
        }

        uint256 slashedAmount = 0;
        if (project.config.minStakeToClaim > 0) {
            uint256 locked = _vault.getLockedStake(claim.contributor);
            slashedAmount = project.config.minStakeToClaim > locked ? locked : project.config.minStakeToClaim;
            if (slashedAmount > 0) {
                _unlockStakeForClaimExpired(claim.contributor, slashedAmount);
                _vault.slash(claim.contributor, slashedAmount, projectId);
            }
        }

        emit ClaimExpired(projectId, claimId, claim.contributor, slashedAmount);
    }

    function contribute(bytes32 projectId, uint256 claimId, uint256 contributionIndex, bytes32 submissionHash)
        external
        nonReentrant
    {
        _contribute(projectId, claimId, contributionIndex, submissionHash);
    }

    function batchContribute(
        bytes32 projectId,
        uint256 claimId,
        uint256[] calldata contributionIndices,
        bytes32[] calldata submissionHashes
    ) external nonReentrant {
        if (contributionIndices.length != submissionHashes.length) {
            revert Unauthorized(UNAUTHORIZED_ARRAY_LENGTH_MISMATCH);
        }
        for (uint256 i = 0; i < contributionIndices.length; i++) {
            _contribute(projectId, claimId, contributionIndices[i], submissionHashes[i]);
        }
    }

    function _contribute(bytes32 projectId, uint256 claimId, uint256 contributionIndex, bytes32 submissionHash)
        internal
    {
        Claim storage claim = claims[projectId][claimId];
        if (claim.contributor != msg.sender) revert Unauthorized(UNAUTHORIZED_NOT_CLAIM_OWNER);
        if (claim.status != ClaimStatus.Active) revert ClaimNotActive(claimId);
        if (block.timestamp > claim.deadline) revert ClaimAlreadyExpired(claimId, claim.deadline);

        // Verify assignment
        IndexReservation memory reservation = indexReservations[projectId][contributionIndex];
        if (reservation.claimant != msg.sender) revert Unauthorized(UNAUTHORIZED_NOT_INDEX_OWNER);
        if (block.timestamp > reservation.deadline) {
            revert ClaimAlreadyExpired(claimId, reservation.deadline);
        }

        if (contributions[projectId][contributionIndex].submittedAt != 0) {
            revert ContributionAlreadySubmitted(contributionIndex);
        }

        contributions[projectId][contributionIndex] = Contribution({
            projectId: projectId,
            contributor: msg.sender,
            claimId: claimId,
            contributionIndex: contributionIndex,
            submissionHash: submissionHash,
            submittedAt: block.timestamp,
            totalValidations: 0,
            averageScore: 0,
            challengeEndsAt: 0,
            status: ContributionStatus.Pending
        });

        // CEI Pattern: Effects (state changes) before Interactions (external calls)
        claim.submittedCount++;
        projects[projectId].state.submittedQuantity++;
        projects[projectId].state.activeClaimedQuantity--;
        // Issue #6 fix: Decrease user's active claim count
        if (userActiveClaimedQuantity[projectId][msg.sender] > 0) {
            userActiveClaimedQuantity[projectId][msg.sender]--;
        }

        if (claim.submittedCount == claim.quantity) {
            claim.status = ClaimStatus.Fulfilled;
        }

        // Interactions (external calls) after state changes
        _oracle.setContributionContributor(projectId, contributionIndex, msg.sender);
        _oracle.enqueueValidation(projectId, contributionIndex, block.timestamp);

        emit ContributionSubmitted(projectId, contributionIndex, msg.sender);
    }

    // ============================================
    // FINALIZATION FUNCTIONS
    // ============================================

    function finalizeContribution(bytes32 projectId, uint256 contributionIndex) external nonReentrant {
        _finalizeContribution(projectId, contributionIndex);
    }

    function batchFinalizeContributions(bytes32 projectId, uint256[] calldata contributionIndices)
        external
        nonReentrant
    {
        for (uint256 i = 0; i < contributionIndices.length; i++) {
            _finalizeContribution(projectId, contributionIndices[i]);
        }
    }

    function _finalizeContribution(bytes32 projectId, uint256 contributionIndex) internal {
        Contribution storage contrib = contributions[projectId][contributionIndex];
        if (contrib.submittedAt == 0) revert ContributionDoesNotExist(projectId, contributionIndex);
        if (contrib.status != ContributionStatus.Pending) revert AlreadyRewarded();

        Project storage project = projects[projectId];

        // 1. Get Consensus from Oracle
        ConsensusReport memory report = _fetchConsensus(projectId, contributionIndex);

        if (!report.isReady) return;

        // 2. Process Outcome
        bool accepted = report.weightedAverage >= consensusThreshold;

        // CEI Pattern: Effects (state changes) before Interactions (external calls)
        // Store contributor address and claimId before potential deletion
        address contribContributor = contrib.contributor;
        uint256 contribClaimId = contrib.claimId;

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
        Claim storage claim = claims[projectId][contribClaimId];
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
            delete indexReservations[projectId][contributionIndex];
            delete contributions[projectId][contributionIndex];

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
        _trust.updateReputation(contribContributor, CONTRIBUTOR_ROLE, accepted, report.weightedAverage);

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
            _oracle.resetContributionState(projectId, contributionIndex);
        }

        // 5. Handle Validators (Rewards & Slashing)
        _processValidators(
            projectId,
            contributionIndex,
            project,
            report.validatorsToSlash,
            report.slashAmounts,
            report.validatorWeights
        );

        emit ContributionFinalized(projectId, contributionIndex, finalStatus, report.weightedAverage);
    }

    /**
     * @notice Claim rewards for a validated contribution after the challenge period
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     */
    function claimContributionReward(bytes32 projectId, uint256 contributionIndex) external nonReentrant {
        Contribution storage contrib = contributions[projectId][contributionIndex];
        if (contrib.status != ContributionStatus.Validated) revert NotAvailableForClaim();
        if (block.timestamp <= contrib.challengeEndsAt) revert ChallengePeriodActive();

        Project storage project = projects[projectId];
        uint256 reward = _calculateContributorReward(project);

        contrib.status = ContributionStatus.Rewarded;

        if (reward > 0) {
            _rewards.distributeReward(projectId, contrib.contributor, address(project.rewardToken), reward);
        }

        emit ContributionRewarded(projectId, contributionIndex, contrib.contributor, reward);
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
        _vault.lockStake(user, amount, "claim");
    }

    /**
     * @dev Unlock stake when a claim expires
     * @param user Address of the user
     * @param amount Amount of stake to unlock
     */
    function _unlockStakeForClaimExpired(address user, uint256 amount) internal {
        _vault.unlockStake(user, amount, "claim_expired");
    }

    /**
     * @dev Unlock stake when a claim is finalized
     * @param user Address of the user
     * @param amount Amount of stake to unlock
     */
    function _unlockStakeForClaimFinalized(address user, uint256 amount) internal {
        _vault.unlockStake(user, amount, "claim_finalized");
    }

    /**
     * @dev Validate a skill for a user if the project requires it
     * @param project Storage reference to the project
     * @param user Address of the user
     */
    function _validateSkillIfRequired(Project storage project, address user) internal {
        if (bytes(project.config.requiredSkill).length == 0) return;
        _trust.validateSkill(user, project.config.requiredSkill);
    }

    /**
     * @notice Safely add an index to the available indices stack, preventing duplicates
     * @param projectId The project ID
     * @param index The contribution index to add
     */
    function _addToAvailableIndices(bytes32 projectId, uint256 index) internal {
        // Prevent duplicate entries in the available indices stack
        if (indexIsAvailable[projectId][index]) {
            return; // Index is already available, don't add again
        }

        stackTop[projectId]++;
        availableIndices[projectId][stackTop[projectId]] = index;
        indexIsAvailable[projectId][index] = true;
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
        return _oracle.getConsensus(projectId, contributionIndex);
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
        return _oracle.getValidations(projectId, contributionIndex);
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
     * @notice Process validator rewards and slashes after consensus is reached
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the finalized contribution
     * @param project The project storage reference
     * @param toSlash List of validators to be slashed
     * @param slashAmounts Corresponding slash amounts
     */
    function _processValidators(
        bytes32 projectId,
        uint256 contributionIndex,
        Project storage project,
        address[] memory toSlash,
        uint256[] memory slashAmounts,
        uint256[] memory consensusWeights
    ) internal {
        // 1. Slash Outliers
        for (uint256 i = 0; i < toSlash.length; i++) {
            if (slashAmounts[i] > 0) {
                _vault.slash(toSlash[i], slashAmounts[i], projectId);
                _oracle.handleValidatorSlash(projectId, contributionIndex, toSlash[i], slashAmounts[i]);
                _trust.updateReputation(toSlash[i], VALIDATOR_ROLE, false, 0);
            }
        }

        // 2. Distribute Rewards to Accurate Validators (using consensus weights for proportional fairness)
        _distributeValidatorRewards(projectId, contributionIndex, project, toSlash, consensusWeights);
    }

    /**
     * @dev Distribute validator rewards proportionally based on consensus algorithm weights
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the finalized contribution
     * @param project Storage reference to the project
     * @param toSlash Array of validators to exclude from rewards
     * @param consensusWeights Weights from the consensus algorithm (parallel to validations array)
     */
    function _distributeValidatorRewards(
        bytes32 projectId,
        uint256 contributionIndex,
        Project storage project,
        address[] memory toSlash,
        uint256[] memory consensusWeights
    ) internal {
        Validation[] memory vals = _fetchValidations(projectId, contributionIndex);

        if (vals.length == 0 || project.state.totalQuantityAvailable == 0) return;

        // Use consensus weights when available (M-1 fix: ensures reward distribution
        // matches the same weight formula used by the consensus algorithm).
        // Falls back to ConsensusLib.calculateBaseWeight when weights are unavailable.
        bool useConsensusWeights = consensusWeights.length == vals.length;

        // Calculate total weight for accurate (non-outlier) validators
        uint256 totalAccurateWeight = 0;
        for (uint256 i = 0; i < vals.length; i++) {
            if (!_isOutlier(vals[i].validator, toSlash)) {
                uint256 weight = useConsensusWeights
                    ? consensusWeights[i]
                    : ConsensusLib.calculateBaseWeight(
                        vals[i].stakeAmount, _trust.getTrustScore(vals[i].validator, VALIDATOR_ROLE)
                    );
                totalAccurateWeight += weight;
            }
        }

        // Prevent division by zero - if no accurate validators have weight, skip reward distribution
        if (totalAccurateWeight == 0) return;

        // Distribute rewards proportionally using consensus weights
        for (uint256 i = 0; i < vals.length; i++) {
            if (!_isOutlier(vals[i].validator, toSlash)) {
                uint256 weight = useConsensusWeights
                    ? consensusWeights[i]
                    : ConsensusLib.calculateBaseWeight(
                        vals[i].stakeAmount, _trust.getTrustScore(vals[i].validator, VALIDATOR_ROLE)
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
                    _rewards.distributeValidatorReward(
                        projectId, vals[i].validator, address(project.rewardToken), reward
                    );
                }
                _trust.updateReputation(vals[i].validator, VALIDATOR_ROLE, true, 0);
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
        for (uint256 i = 0; i < outliers.length; i++) {
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
        return projects[projectId];
    }

    /**
     * @notice Get claim information
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @return Claim struct containing claim details
     */
    function getClaim(bytes32 projectId, uint256 claimId) external view returns (Claim memory) {
        return claims[projectId][claimId];
    }

    /**
     * @notice Get contribution information
     * @param projectId Unique identifier for the project
     * @param index Contribution index within the project
     * @return Contribution struct containing contribution details
     */
    function getContribution(bytes32 projectId, uint256 index) external view returns (Contribution memory) {
        return contributions[projectId][index];
    }

    /**
     * @notice Get the next claim ID for a project
     * @param projectId Unique identifier for the project
     * @return Next claim ID that will be assigned
     */
    function getNextClaimId(bytes32 projectId) external view returns (uint256) {
        return nextClaimId[projectId];
    }

    /**
     * @notice Get the claimant address for a specific contribution index
     * @param projectId Unique identifier for the project
     * @param index Contribution index within the project
     * @return Address of the user who claimed this index
     */
    function getIndexToClaimant(bytes32 projectId, uint256 index) external view returns (address) {
        return indexReservations[projectId][index].claimant;
    }

    /**
     * @notice Get the deadline for a specific contribution index
     * @param projectId Unique identifier for the project
     * @param index Contribution index within the project
     * @return Deadline timestamp for submitting the contribution
     */
    function getIndexClaimDeadline(bytes32 projectId, uint256 index) external view returns (uint256) {
        return indexReservations[projectId][index].deadline;
    }

    /**
     * @notice Get the vault contract address
     * @return Address of the SapienVault contract
     */
    function getVault() external view returns (address) {
        return address(_vault);
    }

    /**
     * @notice Get the rewards contract address
     * @return Address of the Rewards contract
     */
    function getRewards() external view returns (address) {
        return address(_rewards);
    }

    /**
     * @notice Get the trust contract address
     * @return Address of the SapienTrust contract
     */
    function getTrust() external view returns (address) {
        return address(_trust);
    }

    /**
     * @notice Get the oracle contract address
     * @return Address of the ValidationOracle contract
     */
    function getOracle() external view returns (address) {
        return address(_oracle);
    }
}
