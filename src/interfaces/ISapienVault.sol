// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

interface ISapienVault {
    // -------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------

    /**
     * @dev Struct holding simplified staking details for each user (single stake per user).
     * @dev Optimized for storage packing to reduce gas costs
     * @param amount Total staked amount (supports up to ~3.4 * 10^38 tokens)
     * @param cooldownAmount Amount in cooldown (supports up to ~3.4 * 10^38 tokens)
     * @param weightedStartTime Weighted average start time for unlocking (Unix timestamp)
     * @param effectiveLockUpPeriod Effective lockup period based on weighted average (seconds)
     * @param cooldownStart When cooldown was initiated (Unix timestamp, 0 = no cooldown)
     * @param lastUpdateTime Last time stake was modified (Unix timestamp)
     * @param effectiveMultiplier Calculated multiplier based on amount and lockup (basis points)
     * @param hasStake Whether user has any active stake
     */
    struct UserStake {
        uint128 amount; // 16 bytes - Total staked amount
        uint128 cooldownAmount; // 16 bytes - Amount in cooldown (slot 1)
        uint64 weightedStartTime; // 8 bytes - Weighted average start time
        uint64 effectiveLockUpPeriod; // 8 bytes - Effective lockup period
        uint64 cooldownStart; // 8 bytes - When cooldown was initiated (slot 2)
        uint64 lastUpdateTime; // 8 bytes - Last time stake was modified (slot 3)
        uint32 effectiveMultiplier; // 4 bytes - Calculated multiplier (slot 4)
        bool hasStake; // 1 byte - Whether user has any active stake (slot 4)
            // Total: 3 storage slots instead of 8, saving gas per user
    }

    /**
     * @notice Struct for weighted calculation results
     * @param weightedStartTime Weighted average start time for unlocking (Unix timestamp)
     * @param effectiveLockup Effective lockup period based on weighted average (seconds)
     */
    struct WeightedValues {
        uint256 weightedStartTime;
        uint256 effectiveLockup;
    }

    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    /**
     * @notice Emitted when a user stakes tokens.
     * @param user The user's address.
     * @param amount The amount staked.
     * @param effectiveMultiplier The effective multiplier for this stake.
     * @param lockUpPeriod The lock-up duration in seconds.
     */
    event Staked(address indexed user, uint256 amount, uint256 effectiveMultiplier, uint256 lockUpPeriod);

    /**
     * @notice Emitted when a user increases their stake amount.
     * @param user The user's address.
     * @param additionalAmount The additional amount staked.
     * @param newTotalAmount The new total staked amount.
     * @param newEffectiveMultiplier The new effective multiplier.
     */
    event AmountIncreased(
        address indexed user, uint256 additionalAmount, uint256 newTotalAmount, uint256 newEffectiveMultiplier
    );

    /**
     * @notice Emitted when a user increases their lockup period.
     * @param user The user's address.
     * @param additionalLockup The additional lockup time.
     * @param newEffectiveLockup The new effective lockup period.
     * @param newEffectiveMultiplier The new effective multiplier.
     */
    event LockupIncreased(
        address indexed user, uint256 additionalLockup, uint256 newEffectiveLockup, uint256 newEffectiveMultiplier
    );

    /**
     * @notice Emitted when a user initiates the unstaking process (starts cooldown).
     * @param user The user's address initiating unstake.
     * @param amount The amount to unstake.
     */
    event UnstakingInitiated(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user completes unstaking after the cooldown.
     * @param user The user's address.
     * @param amount The amount unstaked.
     */
    event Unstaked(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user performs an instant unstake (penalty applied).
     * @param user The user's address.
     * @param amount The amount actually received by the user (penalty deducted).
     * @param penalty The penalty amount sent to treasury.
     */
    event InstantUnstake(address indexed user, uint256 amount, uint256 penalty);

    /// @notice Emitted when the Treasury address is updated.
    event SapienTreasuryUpdated(address indexed newSapienTreasury);

    /// @notice Emitted when the multiplier is updated.
    event MultiplierUpdated(uint256 lockUpPeriod, uint256 multiplier);

    /// @notice Emitted when emergency withdrawal is performed.
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);

    // -------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------

    error NotAdmin();
    error NotPauser();
    error ZeroAddress();
    error MinimumStakeAmountRequired();
    error InvalidLockupPeriod();
    error InvalidAmount();
    error NoStakeFound();
    error CannotIncreaseStakeInCooldown();
    error StakeAmountTooLarge();
    error MinimumLockupIncreaseRequired();
    error StakeStillLocked();
    error AmountExceedsAvailableBalance();
    error NotReadyForUnstake();
    error AmountExceedsCooldownAmount();
    error LockPeriodCompleted();

    // -------------------------------------------------------------
    // Initialization Functions
    // -------------------------------------------------------------

    /**
     * @notice Initializes the SapienVault contract.
     * @param token The IERC20 token contract for Sapien.
     * @param admin The contract admin and owner.
     * @param treasury The address of the Treasury for penalty collection.
     * @param newMultiplierContract The address of the new multiplier contract.
     */
    function initialize(address token, address admin, address treasury, address newMultiplierContract) external;

    // -------------------------------------------------------------
    // Administrative Functions
    // -------------------------------------------------------------

    /**
     * @notice Pauses the contract, preventing certain actions (e.g., staking/unstaking).
     */
    function pause() external;

    /**
     * @notice Unpauses the contract, allowing staking/unstaking.
     */
    function unpause() external;

    /**
     * @notice Updates the treasury address for penalty collection.
     * @param newRewardSafe Rewards Safe Address.
     */
    function setRewardSafe(address newRewardSafe) external;

    // -------------------------------------------------------------
    // Staking Functions
    // -------------------------------------------------------------

    /**
     * @notice Stake a specified `amount` of tokens for a given `lockUpPeriod`.
     * @param amount The amount of tokens to stake.
     * @param lockUpPeriod The lock-up duration in seconds (30/90/180/365 days).
     */
    function stake(uint256 amount, uint256 lockUpPeriod) external;

    /**
     * @notice Increase the staked amount without changing lockup period.
     * @param additionalAmount The additional amount to stake.
     */
    function increaseAmount(uint256 additionalAmount) external;

    /**
     * @notice Increase the lockup period for existing stake.
     * @param additionalLockup The additional lockup time in seconds.
     */
    function increaseLockup(uint256 additionalLockup) external;

    /**
     * @notice Initiates the cooldown for unstaking.
     * @param amount The amount intended for unstaking.
     */
    function initiateUnstake(uint256 amount) external;

    /**
     * @notice Completes the unstaking process after the cooldown period has passed.
     * @param amount The amount to unstake.
     */
    function unstake(uint256 amount) external;

    /**
     * @notice Instantly unstakes a specified `amount`, incurring a penalty.
     * @param amount The amount to unstake instantly.
     */
    function instantUnstake(uint256 amount) external;

    // -------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------

    /**
     * @notice Returns the total amount of tokens staked in this contract.
     * @return The total staked amount.
     */
    function totalStaked() external view returns (uint256);

    /**
     * @notice Get total staked amount for a user.
     * @param user The user address.
     * @return The user's total staked amount.
     */
    function getTotalStaked(address user) external view returns (uint256);

    /**
     * @notice Get total unlocked amount for a user.
     * @param user The user address.
     * @return The user's total unlocked amount.
     */
    function getTotalUnlocked(address user) external view returns (uint256);

    /**
     * @notice Get total locked amount for a user.
     * @param user The user address.
     * @return The user's total locked amount.
     */
    function getTotalLocked(address user) external view returns (uint256);

    /**
     * @notice Get total amount ready for unstake for a user.
     * @param user The user address.
     * @return The user's total amount ready for unstake.
     */
    function getTotalReadyForUnstake(address user) external view returns (uint256);

    /**
     * @notice Get total amount in cooldown for a user.
     * @param user The user address.
     * @return The user's total amount in cooldown.
     */
    function getTotalInCooldown(address user) external view returns (uint256);

    /**
     * @notice Get user's staking summary.
     * @param user The user address.
     * @return userTotalStaked Total amount staked.
     * @return totalUnlocked Amount available for normal unstaking.
     * @return totalLocked Amount available for instant unstaking (with penalty).
     * @return totalInCooldown Amount currently in cooldown.
     * @return totalReadyForUnstake Amount ready to be unstaked.
     * @return effectiveMultiplier Current effective multiplier.
     * @return effectiveLockUpPeriod Current effective lockup period.
     * @return timeUntilUnlock Time remaining until unlock.
     */
    function getUserStakingSummary(address user)
        external
        view
        returns (
            uint256 userTotalStaked,
            uint256 totalUnlocked,
            uint256 totalLocked,
            uint256 totalInCooldown,
            uint256 totalReadyForUnstake,
            uint256 effectiveMultiplier,
            uint256 effectiveLockUpPeriod,
            uint256 timeUntilUnlock
        );

    /**
     * @notice Get multiplier for a specific lock-up period
     * @param lockUpPeriod The lock-up period in seconds
     * @return multiplier The multiplier for the period
     */
    function getMultiplierForPeriod(uint256 lockUpPeriod) external view returns (uint256 multiplier);

    // -------------------------------------------------------------
    // Additional Methods for RewardsDistributor Compatibility
    // -------------------------------------------------------------

    /**
     * @notice Get stake details for rewards calculation - adapted for single stake system
     * @param user The user address
     * @param stakeId The stake ID (should be 1 for compatibility)
     * @return amount The staked amount
     * @return lockUpPeriod The lock-up period
     * @return startTime The weighted start time
     * @return multiplier The effective multiplier
     * @return cooldownStart When cooldown was initiated
     * @return isActive Whether the stake is active
     */
    function getStakeDetails(address user, uint256 stakeId)
        external
        view
        returns (
            uint256 amount,
            uint256 lockUpPeriod,
            uint256 startTime,
            uint256 multiplier,
            uint256 cooldownStart,
            bool isActive
        );

    /**
     * @notice Get active stakes for a user - adapted for single stake system
     * @param user The user address
     * @return stakeIds Array of stake IDs (single element: [1])
     * @return amounts Array of amounts (single element: [user's total stake])
     * @return multipliers Array of multipliers (single element: [user's effective multiplier])
     * @return lockUpPeriods Array of lock periods (single element: [user's effective lockup])
     */
    function getUserActiveStakes(address user)
        external
        view
        returns (
            uint256[] memory stakeIds,
            uint256[] memory amounts,
            uint256[] memory multipliers,
            uint256[] memory lockUpPeriods
        );

    /**
     * @notice Check if user has an active stake
     * @param user The user address
     * @return Whether the user has an active stake
     */
    function hasActiveStake(address user) external view returns (bool);
}
