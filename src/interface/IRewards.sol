// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {ISharedTypes} from "./ISharedTypes.sol";

interface IRewards is ISharedTypes {
    // ============================================
    // EVENTS
    // ============================================

    event RewardsAllocated(bytes32 indexed projectId, address indexed token, uint256 amount);
    event RewardsDistributed(bytes32 indexed projectId, address indexed user, address indexed token, uint256 amount);
    event RewardsClaimed(address indexed user, bytes32 indexed projectId, address indexed token, uint256 amount);
    event CoreAddressUpdated(address indexed core);
    event OperatorFeeCollected(
        address indexed claimer, address indexed feeRecipient, address indexed token, uint256 amount
    );
    event MaxFeeBpsUpdated(uint256 newMaxFeeBps);

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

    function initialize(address _defaultAdmin) external;
    function setCore(address _core) external;
    function pause() external;
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

    function core() external view returns (address);
    function maxFeeBps() external view returns (uint256);
    function projectRewards(bytes32 projectId, address token) external view returns (uint256);

    function contributorRewards(address contributor, bytes32 projectId, address token) external view returns (uint256);
    function rewardsClaimed(address contributor, bytes32 projectId, address token) external view returns (uint256);

    function validatorRewards(address validator, bytes32 projectId, address token) external view returns (uint256);
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
