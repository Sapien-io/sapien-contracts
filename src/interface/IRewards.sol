// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ISharedTypes} from "./ISharedTypes.sol";

/**
 * @title IRewards
 * @author Sapien Team
 * @notice Interface for the Rewards contract that handles allocation and distribution of rewards
 */
interface IRewards is ISharedTypes {
    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when rewards are allocated to a project
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @param amount The amount of rewards allocated
     */
    event RewardsAllocated(bytes32 indexed projectId, address indexed token, uint256 indexed amount);

    /**
     * @notice Emitted when rewards are distributed to a user
     * @param projectId Unique identifier for the project
     * @param user The address receiving rewards
     * @param token The reward token address
     * @param amount The amount of rewards distributed
     */
    event RewardsDistributed(bytes32 indexed projectId, address indexed user, address indexed token, uint256 amount);

    /**
     * @notice Emitted when a user claims their accumulated rewards
     * @param user The address claiming rewards
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @param amount The amount of rewards claimed
     */
    event RewardsClaimed(address indexed user, bytes32 indexed projectId, address indexed token, uint256 amount);

    /**
     * @notice Emitted when the core contract address is updated
     * @param core The new core contract address
     */
    event CoreAddressUpdated(address indexed core);

    /**
     * @notice Emitted when an operator fee is collected during a claim
     * @param claimer The address making the claim
     * @param feeRecipient The address receiving the fee
     * @param token The token address
     * @param amount The amount of fee collected
     */
    event OperatorFeeCollected(
        address indexed claimer, address indexed feeRecipient, address indexed token, uint256 amount
    );

    /**
     * @notice Emitted when the maximum allowed fee basis points is updated
     * @param newMaxFeeBps The new maximum fee in basis points
     */
    event MaxFeeBpsUpdated(uint256 indexed newMaxFeeBps);

    /**
     * @notice Emitted when dust (unallocated tokens) is swept from the contract
     * @param token The token address
     * @param to The recipient address
     * @param amount The amount swept
     */
    event DustSwept(address indexed token, address indexed to, uint256 indexed amount);

    // ============================================
    // ERRORS
    // ============================================

    error OnlyCore();
    error NoRewardsToClaim();
    error TransferFailed();
    error CoreAlreadySet();
    error InvalidAmount();
    error InsufficientProjectRewards(bytes32 projectId, address token, uint256 required, uint256 available);
    error InvalidAddress();
    error InvalidFeeRecipient();
    error FeeBpsTooHigh(uint256 provided, uint256 max);
    error InvalidFeeBps();

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Initialize the Rewards contract
     * @param _defaultAdmin The address of the default admin
     */
    function initialize(address _defaultAdmin) external;

    /**
     * @notice Set the core contract address
     * @param _core The address of the SapienCore contract
     */
    function setCore(address _core) external;

    /**
     * @notice Pause the contract
     */
    function pause() external;

    /**
     * @notice Unpause the contract
     */
    function unpause() external;

    /**
     * @notice Emergency withdrawal of stuck tokens
     * @dev Can only be called by admin when paused
     * @param token The token address to withdraw
     * @param to The recipient address
     * @param amount The amount to withdraw
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external;

    /**
     * @notice Sweep accumulated dust (rounding remainders) from the contract
     * @dev Does NOT require pausing. Only sweeps unallocated surplus.
     * @param token The token address to sweep
     * @param to The recipient address for swept dust
     */
    function sweepDust(address token, address to) external;

    /**
     * @notice Set the maximum allowed operator fee in basis points
     * @dev Can only be called by admin
     * @param _maxFeeBps The new maximum fee in basis points (e.g., 1000 = 10%)
     */
    function setMaxFeeBps(uint256 _maxFeeBps) external;

    // ============================================
    // CORE FUNCTIONS
    // ============================================

    /**
     * @notice Allocate rewards for a project (called during funding)
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @param amount The amount of rewards to allocate
     */
    function allocateRewards(bytes32 projectId, address token, uint256 amount) external;

    /**
     * @notice Distribute rewards to a contributor (called when contribution is validated)
     * @param projectId Unique identifier for the project
     * @param contributor The address to receive rewards
     * @param token The reward token address
     * @param amount The amount of rewards to distribute
     */
    function distributeReward(bytes32 projectId, address contributor, address token, uint256 amount) external;

    /**
     * @notice Distribute rewards to a validator (called when consensus is reached)
     * @param projectId Unique identifier for the project
     * @param validator The address to receive rewards
     * @param token The reward token address
     * @param amount The amount of rewards to distribute
     */
    function distributeValidatorReward(bytes32 projectId, address validator, address token, uint256 amount) external;

    // ============================================
    // CONTRIBUTOR FUNCTIONS
    // ============================================

    /**
     * @notice Claim accumulated rewards for a specific project and token
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @param feeRecipient Address to receive operator fee (use address(0) for no fee)
     * @param feeBps Fee in basis points (e.g., 100 = 1%, use 0 for no fee)
     */
    function claimRewards(bytes32 projectId, address token, address feeRecipient, uint256 feeBps) external;

    /**
     * @notice Claim all accumulated rewards across multiple projects for a specific token
     * @param token The reward token address
     * @param projectIds Array of project identifiers to claim from
     * @param feeRecipient Address to receive operator fee (use address(0) for no fee)
     * @param feeBps Fee in basis points (e.g., 100 = 1%, use 0 for no fee)
     */
    function claimAllRewards(address token, bytes32[] calldata projectIds, address feeRecipient, uint256 feeBps)
        external;

    // ============================================
    // VALIDATOR FUNCTIONS
    // ============================================

    /**
     * @notice Claim accumulated validator rewards for a specific project and token
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @param feeRecipient Address to receive operator fee (use address(0) for no fee)
     * @param feeBps Fee in basis points (e.g., 100 = 1%, use 0 for no fee)
     */
    function claimValidatorRewards(bytes32 projectId, address token, address feeRecipient, uint256 feeBps) external;

    /**
     * @notice Claim all accumulated validator rewards across multiple projects for a specific token
     * @param token The reward token address
     * @param projectIds Array of project identifiers to claim from
     * @param feeRecipient Address to receive operator fee (use address(0) for no fee)
     * @param feeBps Fee in basis points (e.g., 100 = 1%, use 0 for no fee)
     */
    function claimAllValidatorRewards(
        address token,
        bytes32[] calldata projectIds,
        address feeRecipient,
        uint256 feeBps
    ) external;

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get the core contract address
     * @return The address of the SapienCore contract
     */
    function core() external view returns (address);

    /**
     * @notice Get the maximum allowed fee basis points
     * @return The maximum fee in basis points
     */
    function maxFeeBps() external view returns (uint256);

    /**
     * @notice Get the rewards allocated to a project for a specific token
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @return The amount of rewards allocated
     */
    function projectRewards(bytes32 projectId, address token) external view returns (uint256);

    /**
     * @notice Get the rewards earned by a contributor for a specific project and token
     * @param contributor Address of the contributor
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @return The amount of rewards earned
     */
    function contributorRewards(address contributor, bytes32 projectId, address token) external view returns (uint256);

    /**
     * @notice Get the rewards claimed by a contributor for a specific project and token
     * @param contributor Address of the contributor
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @return The amount of rewards claimed
     */
    function rewardsClaimed(address contributor, bytes32 projectId, address token) external view returns (uint256);

    /**
     * @notice Get the rewards earned by a validator for a specific project and token
     * @param validator Address of the validator
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @return The amount of rewards earned
     */
    function validatorRewards(address validator, bytes32 projectId, address token) external view returns (uint256);

    /**
     * @notice Get the rewards claimed by a validator for a specific project and token
     * @param validator Address of the validator
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @return The amount of rewards claimed
     */
    function validatorRewardsClaimed(address validator, bytes32 projectId, address token)
        external
        view
        returns (uint256);

    /**
     * @notice Get available rewards for a contributor for a specific project and token
     * @param contributor Address of the contributor
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @return Amount of unclaimed rewards
     */
    function getAvailableRewards(address contributor, bytes32 projectId, address token) external view returns (uint256);

    /**
     * @notice Get total rewards earned by a contributor for a specific project and token
     * @param contributor Address of the contributor
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @return Total amount of rewards earned
     */
    function getTotalRewardsEarned(address contributor, bytes32 projectId, address token)
        external
        view
        returns (uint256);

    /**
     * @notice Get available rewards for a validator for a specific project and token
     * @param validator Address of the validator
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @return Amount of unclaimed validator rewards
     */
    function getAvailableValidatorRewards(address validator, bytes32 projectId, address token)
        external
        view
        returns (uint256);

    /**
     * @notice Get total rewards earned by a validator for a specific project and token
     * @param validator Address of the validator
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @return Total amount of validator rewards earned
     */
    function getTotalValidatorRewardsEarned(address validator, bytes32 projectId, address token)
        external
        view
        returns (uint256);

    /**
     * @notice Get remaining rewards allocated to a project for a specific token
     * @param projectId Unique identifier for the project
     * @param token The reward token address
     * @return Remaining amount of project rewards
     */
    function getRemainingProjectRewards(bytes32 projectId, address token) external view returns (uint256);
}
