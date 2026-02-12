// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISharedTypes} from "./ISharedTypes.sol";

/**
 * @title ISapienCore
 * @notice Single Source of Truth for Sapien V2 protocol
 * @dev Combines Project management and Contribution lifecycle
 */
/**
 * @title ISapienCore
 * @author Sapien Team
 * @notice Single Source of Truth for Sapien V2 protocol
 * @dev Combines Project management and Contribution lifecycle
 */
interface ISapienCore is ISharedTypes {
    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when a new project is created
     * @param projectId Unique identifier for the project
     * @param originator The address that created the project
     * @param rewardToken The ERC20 token used for rewards
     * @param ipfsCid The IPFS CID of the project specification
     * @param claimDeadlineDays Days until a claim expires
     * @param minStakeToClaim Minimum stake required to claim a slot
     * @param minStakeToContribute Minimum stake required to contribute
     * @param numberOfValidations Number of validations required per contribution
     * @param validatorRewardBasisPoints Percentage of rewards allocated to validators
     * @param requiredSkill The skill associated with this project
     */
    event ProjectCreated(
        bytes32 indexed projectId,
        address indexed originator,
        address indexed rewardToken,
        string ipfsCid,
        uint256 claimDeadlineDays,
        uint256 minStakeToClaim,
        uint256 minStakeToContribute,
        uint256 numberOfValidations,
        uint256 validatorRewardBasisPoints,
        string requiredSkill
    );

    /**
     * @notice Emitted when a project is funded
     * @param projectId Unique identifier for the project
     * @param rewardAmount Total reward amount added
     * @param quantity Number of contribution slots added
     * @param rewardAmountAfterFee Reward amount remaining after protocol fees
     */
    event ProjectFunded(
        bytes32 indexed projectId, uint256 indexed rewardAmount, uint256 indexed quantity, uint256 rewardAmountAfterFee
    );

    /**
     * @notice Emitted when a contributor claims slots
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the created claim
     * @param contributor Address of the contributor
     * @param quantity Number of slots claimed
     * @param deadline Timestamp when the claim expires
     */
    event ClaimCreated(
        bytes32 indexed projectId,
        uint256 indexed claimId,
        address indexed contributor,
        uint256 quantity,
        uint256 deadline
    );

    /**
     * @notice Emitted when a claim is fully fulfilled
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param contributor Address of the contributor
     */
    event ClaimFulfilled(bytes32 indexed projectId, uint256 indexed claimId, address indexed contributor);

    /**
     * @notice Emitted when a claim expires and is processed
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param contributor Address of the contributor
     * @param slashedAmount Amount of stake slashed from the contributor
     */
    event ClaimExpired(
        bytes32 indexed projectId, uint256 indexed claimId, address indexed contributor, uint256 slashedAmount
    );

    /**
     * @notice Emitted when an individual contribution index is assigned to a contributor
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @param index The contribution index
     * @param contributor Address of the contributor
     * @param deadline Timestamp when the assignment expires
     */
    event IndexAssigned(
        bytes32 indexed projectId, uint256 indexed claimId, uint256 indexed index, address contributor, uint256 deadline
    );

    /**
     * @notice Emitted when an individual contribution index is reclaimed
     * @param projectId Unique identifier for the project
     * @param index The contribution index
     * @param contributor Address of the contributor who lost the index
     */
    event IndexReclaimed(bytes32 indexed projectId, uint256 indexed index, address indexed contributor);

    /**
     * @notice Emitted when a contribution is submitted
     * @param projectId Unique identifier for the project
     * @param contributionIndex The contribution index
     * @param contributor Address of the contributor
     * @param claimId Unique identifier for the claim
     * @param submissionHash Hash of the submitted work
     */
    event ContributionSubmitted(
        bytes32 indexed projectId,
        uint256 indexed contributionIndex,
        address indexed contributor,
        uint256 claimId,
        bytes32 submissionHash
    );

    /**
     * @notice Emitted when a contribution is finalized
     * @param projectId Unique identifier for the project
     * @param contributionIndex The contribution index
     * @param status Final status of the contribution
     * @param finalScore Final score assigned by consensus
     * @param contributor Address of the contributor
     * @param claimId Unique identifier for the claim
     */
    event ContributionFinalized(
        bytes32 indexed projectId,
        uint256 indexed contributionIndex,
        ContributionStatus status,
        uint256 finalScore,
        address contributor,
        uint256 claimId
    );

    /**
     * @notice Emitted when a contributor reward is preserved for later claim
     * @param projectId Unique identifier for the project
     * @param contributionIndex The contribution index
     * @param token The reward token address
     * @param amount Amount of reward preserved
     */
    event ContributorRewardPreserved(
        bytes32 indexed projectId, uint256 indexed contributionIndex, address indexed token, uint256 amount
    );

    /**
     * @notice Emitted when the protocol fee is updated
     * @param feeBasisPoints New fee in basis points
     */
    event ProtocolFeeUpdated(uint256 indexed feeBasisPoints);

    /**
     * @notice Emitted when the treasury address is updated
     * @param treasury New treasury address
     */
    event TreasuryUpdated(address indexed treasury);

    /**
     * @notice Emitted when a protocol fee is collected
     * @param projectId Unique identifier for the project
     * @param token The token address
     * @param amount Amount collected
     */
    event ProtocolFeeCollected(bytes32 indexed projectId, address indexed token, uint256 indexed amount);

    /**
     * @notice Emitted when an operator fee is paid
     * @param projectId Unique identifier for the project
     * @param operator The operator address
     * @param amount Amount paid
     */
    event OperatorFeePaid(bytes32 indexed projectId, address indexed operator, uint256 indexed amount);

    /**
     * @notice Emitted when the consensus threshold is updated
     * @param threshold New consensus threshold
     */
    event ConsensusThresholdUpdated(uint256 indexed threshold);

    /**
     * @notice Emitted when the challenge period is updated
     * @param period New challenge period in seconds
     */
    event ChallengePeriodUpdated(uint256 indexed period);

    /**
     * @notice Emitted when a contribution is rewarded
     * @param projectId Unique identifier for the project
     * @param contributionIndex The contribution index
     * @param contributor Address of the contributor
     * @param amount Amount rewarded
     * @param token Reward token address
     */
    event ContributionRewarded(
        bytes32 indexed projectId,
        uint256 indexed contributionIndex,
        address indexed contributor,
        uint256 amount,
        address token
    );

    /**
     * @notice Emitted when consensus is reached for a contribution
     * @param projectId Unique identifier for the project
     * @param contributionIndex The contribution index
     * @param weightedAverage The final consensus score
     * @param validatorCount Number of validators that participated
     */
    event ConsensusReached(
        bytes32 indexed projectId,
        uint256 indexed contributionIndex,
        uint256 indexed weightedAverage,
        uint256 validatorCount
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
    error BatchSizeTooLarge(uint256 provided, uint256 max);
    error InvalidClaimDeadline(uint256 provided);
    error InvalidChallengePeriod(uint256 provided);
    error ValidationNotReady(bytes32 projectId, uint256 contributionIndex);

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
        string calldata ipfsCid,
        uint256 minStakeToClaim,
        uint256 minStakeToContribute,
        uint256 numberOfValidations,
        uint256 validatorRewardBasisPoints,
        string calldata requiredSkill
    ) external returns (bytes32);

    /**
     * @notice Set the number of days until a claim expires
     * @param _days Number of days
     */
    function setClaimDeadlineDays(uint256 _days) external;

    /**
     * @notice Get the number of days until a claim expires
     * @return Number of days
     */
    function getClaimDeadlineDays() external view returns (uint256);

    /**
     * @notice Set the protocol fee in basis points
     * @param _feeBasisPoints Fee in basis points
     */
    function setProtocolFeeBasisPoints(uint256 _feeBasisPoints) external;

    /**
     * @notice Set the treasury address for protocol fees
     * @param _treasury Treasury address
     */
    function setTreasury(address _treasury) external;

    /**
     * @notice Get the protocol fee in basis points
     * @return Fee in basis points
     */
    function protocolFeeBasisPoints() external view returns (uint256);

    /**
     * @notice Get the treasury address for protocol fees
     * @return Treasury address
     */
    function treasury() external view returns (address);

    /**
     * @notice Set the consensus threshold (0-10000)
     * @param _threshold Threshold value
     */
    function setConsensusThreshold(uint256 _threshold) external;

    /**
     * @notice Get the consensus threshold
     * @return Threshold value
     */
    function consensusThreshold() external view returns (uint256);

    /**
     * @notice Set the challenge period in seconds
     * @param _period Period in seconds
     */
    function setChallengePeriod(uint256 _period) external;

    /**
     * @notice Get the challenge period in seconds
     * @return Period in seconds
     */
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

    /**
     * @notice Get project information
     * @param projectId Unique identifier for the project
     * @return Project struct containing configuration and state
     */
    function getProject(bytes32 projectId) external view returns (Project memory);

    /**
     * @notice Get claim information
     * @param projectId Unique identifier for the project
     * @param claimId Unique identifier for the claim
     * @return Claim struct containing contributor and status info
     */
    function getClaim(bytes32 projectId, uint256 claimId) external view returns (Claim memory);

    /**
     * @notice Get contribution information
     * @param projectId Unique identifier for the project
     * @param contributionIndex The contribution index
     * @return Contribution struct containing submission and consensus info
     */
    function getContribution(bytes32 projectId, uint256 contributionIndex) external view returns (Contribution memory);

    /**
     * @notice Get the next available claim ID for a project
     * @param projectId Unique identifier for the project
     * @return The next claim ID
     */
    function getNextClaimId(bytes32 projectId) external view returns (uint256);

    /**
     * @notice Get the claimant for a specific index
     * @param projectId Unique identifier for the project
     * @param index The contribution index
     * @return The address of the claimant
     */
    function getIndexToClaimant(bytes32 projectId, uint256 index) external view returns (address);

    /**
     * @notice Get the claim deadline for a specific index
     * @param projectId Unique identifier for the project
     * @param index The contribution index
     * @return The expiration timestamp
     */
    function getIndexClaimDeadline(bytes32 projectId, uint256 index) external view returns (uint256);

    /**
     * @notice Get the address of the SapienVault contract
     * @return The SapienVault address
     */
    function getVault() external view returns (address);

    /**
     * @notice Get the address of the IRewards contract
     * @return The IRewards address
     */
    function getRewards() external view returns (address);

    /**
     * @notice Get the address of the ISapienTrust contract
     * @return The ISapienTrust address
     */
    function getTrust() external view returns (address);

    /**
     * @notice Get the address of the IValidationOracle contract
     * @return The IValidationOracle address
     */
    function getValidationOracle() external view returns (address);
}
