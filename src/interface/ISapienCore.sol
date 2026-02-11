// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISharedTypes} from "./ISharedTypes.sol";

/**
 * @title ISapienCore
 * @notice Single Source of Truth for Sapien V2 protocol
 * @dev Combines Project management and Contribution lifecycle
 */
interface ISapienCore is ISharedTypes {
    // ============================================
    // EVENTS
    // ============================================

    event ProjectCreated(
        bytes32 indexed projectId,
        address indexed originator,
        address rewardToken,
        string ipfsCid, // The original IPFS CID of the project spec document
        uint256 claimDeadlineDays,
        uint256 minStakeToClaim,
        uint256 minStakeToContribute,
        uint256 minValidations,
        uint256 maxValidations,
        uint256 validatorRewardBasisPoints,
        string requiredSkill
    );
    event ProjectFunded(bytes32 indexed projectId, uint256 rewardAmount, uint256 quantity);
    event ClaimCreated(
        bytes32 indexed projectId, uint256 indexed claimId, address indexed contributor, uint256 quantity
    );
    event ClaimExpired(
        bytes32 indexed projectId, uint256 indexed claimId, address indexed contributor, uint256 slashedAmount
    );
    event IndexAssigned(bytes32 indexed projectId, uint256 indexed claimId, uint256 indexed index, address contributor);
    event IndexReclaimed(bytes32 indexed projectId, uint256 indexed index, address indexed contributor);
    event ContributionSubmitted(
        bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed contributor
    );
    event ContributionFinalized(
        bytes32 indexed projectId, uint256 indexed contributionIndex, ContributionStatus status, uint256 finalScore
    );
    event ContributorRewardPreserved(
        bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed token, uint256 amount
    );
    event MaxValidationsUpdated(uint256 maxValidations);
    event ProtocolFeeUpdated(uint256 feeBasisPoints);
    event TreasuryUpdated(address indexed treasury);
    event ProtocolFeeCollected(bytes32 indexed projectId, address indexed token, uint256 amount);
    event OperatorFeePaid(bytes32 indexed projectId, address indexed operator, uint256 amount);
    event ConsensusThresholdUpdated(uint256 threshold);
    event ChallengePeriodUpdated(uint256 period);
    event ContributionRewarded(
        bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed contributor, uint256 amount
    );

    // ============================================
    // ERRORS
    // ============================================

    error ProjectAlreadyExists(bytes32 projectId);
    error ProjectDoesNotExist(bytes32 projectId);
    error InvalidProjectId(); // projectId does not match keccak256(ipfsCid)
    error InvalidAddress();
    error InvalidAmount();
    error InsufficientContributorStake(address contributor, uint256 required, uint256 actual);
    error InsufficientQuantityAvailable(bytes32 projectId, uint256 requested, uint256 available);
    error ClaimNotExpired(uint256 claimId, uint256 deadline);
    error ContributionIndexOutOfRange(uint256 index, uint256 start, uint256 end);
    error ContributionAlreadySubmitted(uint256 index);
    error ContributionDoesNotExist(bytes32 projectId, uint256 index);
    error AlreadyRewarded();
    error MissingRequiredSkill(address user, string requiredSkill);
    error InvalidValidatorRewards();
    error InvalidConfiguration();
    error ProtocolFeeTooHigh(uint256 provided, uint256 max);
    error ConsensusThresholdOutOfRange(uint256 provided, uint256 min, uint256 max);
    error RewardDilutionNotAllowed();
    error RewardPerSlotTooLow(uint256 provided, uint256 minimum);
    error MaxClaimsPerUserExceeded(uint256 requested, uint256 current, uint256 max);
    error NotAvailableForClaim();
    error ChallengePeriodActive();

    // ============================================
    // PROJECT FUNCTIONS
    // ============================================

    /**
     * @notice Create a new project in the protocol
     * @param projectId Unique identifier for the project
     * @param rewardToken ERC20 token to be used for rewards
     * @param minStakeToClaim Minimum stake required for a contributor to claim a slot
     * @param minStakeToContribute Minimum stake required for a contributor to participate (legacy)
     * @param minValidations Minimum number of validations required to finalize a contribution
     * @param validatorRewardBasisPoints Percentage of rewards allocated to validators (bps)
     * @param requiredSkill Specific skill that contributors will earn upon successful completion
     * @return The hashed projectId (bytes32)
     */
    function createProject(
        bytes32 projectId,
        address rewardToken,
        string memory ipfsCid, // The original IPFS CID of the project spec document
        uint256 minStakeToClaim,
        uint256 minStakeToContribute,
        uint256 minValidations,
        uint256 validatorRewardBasisPoints,
        string memory requiredSkill
    ) external returns (bytes32);

    function setClaimDeadlineDays(uint256 _days) external;
    function setMaxValidations(uint256 _max) external;
    function getClaimDeadlineDays() external view returns (uint256);
    function getMaxValidations() external view returns (uint256);
    function setProtocolFeeBasisPoints(uint256 _feeBasisPoints) external;
    function setTreasury(address _treasury) external;
    function protocolFeeBasisPoints() external view returns (uint256);
    function treasury() external view returns (address);
    function setConsensusThreshold(uint256 _threshold) external;
    function consensusThreshold() external view returns (uint256);
    function setChallengePeriod(uint256 _period) external;
    function challengePeriod() external view returns (uint256);

    /**
     * @notice Fund an existing project with rewards and contribution quantity
     * @param projectId Unique identifier for the project
     * @param rewardAmount Amount of reward tokens to add
     * @param quantity Number of contribution slots to add
     */
    function fundProject(bytes32 projectId, uint256 rewardAmount, uint256 quantity) external;

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
    ) external;

    // ============================================
    // CONTRIBUTION FUNCTIONS
    // ============================================

    /**
     * @notice Claim a number of contribution slots in a project
     * @param projectId Unique identifier for the project
     * @param quantity Number of slots to claim
     * @return claimId Unique identifier for the created claim
     */
    function claimToContribute(bytes32 projectId, uint256 quantity) external returns (uint256 claimId);

    /**
     * @notice Release a claim that has passed its deadline
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     */
    function releaseExpiredClaim(bytes32 projectId, uint256 claimId) external;

    /**
     * @notice Reclaim contribution slots that were claimed but not submitted by the deadline
     * @param projectId Unique identifier for the project
     * @param indices The indices within the project's contribution sequence to reclaim
     */
    function reclaimExpiredIndices(bytes32 projectId, uint256[] calldata indices) external;

    /**
     * @notice Submit a contribution for a specific slot in a claim
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param contributionIndex The index within the project's contribution sequence
     * @param submissionHash Hash of the submitted work (e.g. IPFS CID)
     */
    function contribute(bytes32 projectId, uint256 claimId, uint256 contributionIndex, bytes32 submissionHash) external;

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
    ) external;

    // ============================================
    // FINALIZATION FUNCTIONS
    // ============================================

    /**
     * @notice Finalize a contribution by calculating consensus and distributing rewards/slashing
     * @param projectId Unique identifier for the project
     * @param contributionIndex The index within the project's contribution sequence
     */
    function finalizeContribution(bytes32 projectId, uint256 contributionIndex) external;

    /**
     * @notice Finalize multiple contributions for a project in a single transaction
     * @param projectId Unique identifier for the project
     * @param contributionIndices The indices within the project's contribution sequence
     */
    function batchFinalizeContributions(bytes32 projectId, uint256[] calldata contributionIndices) external;

    /**
     * @notice Claim rewards for a validated contribution after the challenge period
     * @param projectId Unique identifier for the project
     * @param contributionIndex Index of the contribution
     */
    function claimContributionReward(bytes32 projectId, uint256 contributionIndex) external;

    // ============================================
    // GETTER FUNCTIONS
    // ============================================

    function getProject(bytes32 projectId) external view returns (Project memory);

    function getClaim(bytes32 projectId, uint256 claimId) external view returns (Claim memory);

    function getContribution(bytes32 projectId, uint256 contributionIndex) external view returns (Contribution memory);

    function getNextClaimId(bytes32 projectId) external view returns (uint256);

    function getIndexToClaimant(bytes32 projectId, uint256 index) external view returns (address);

    function getIndexClaimDeadline(bytes32 projectId, uint256 index) external view returns (uint256);

    function getVault() external view returns (address);

    function getRewards() external view returns (address);

    function getTrust() external view returns (address);

    function getOracle() external view returns (address);
}
