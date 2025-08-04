// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

interface ISapienVault {
    // -------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------

    struct UserStake {
        uint128 amount; // 16 bytes - Total staked amount
        uint128 cooldownAmount; // 16 bytes - Amount in cooldown (slot 1)
        uint64 weightedStartTime; // 8 bytes - Weighted average start time
        uint64 effectiveLockUpPeriod; // 8 bytes - Effective lockup period
        uint64 cooldownStart; // 8 bytes - When cooldown was initiated (slot 2)
        uint64 lastUpdateTime; // 8 bytes - Last time stake was modified (slot 3)
        uint64 earlyUnstakeCooldownStart; // 8 bytes - When early unstake cooldown was initiated (slot 4)
        uint32 effectiveMultiplier; // 4 bytes - Calculated multiplier (slot 4)
        uint128 earlyUnstakeCooldownAmount; // 16 bytes - Amount requested for early unstake (slot 5)
    }

    struct UserStakingSummary {
        uint256 userTotalStaked; // Total amount staked by the user
        uint256 effectiveMultiplier; // Current multiplier for rewards (basis points)
        uint256 effectiveLockUpPeriod; // Lockup period (seconds)
        uint256 totalLocked; // Amount still in lockup period
        uint256 totalUnlocked; // Amount available for unstaking initiation
        uint256 timeUntilUnlock; // Time remaining until unlock (seconds, 0 if unlocked)
        uint256 totalReadyForUnstake; // Amount ready for immediate withdrawal
        uint256 timeUntilUnstake; // Time remaining until cooldown unstake (seconds, 0 if not in cooldown)
        uint256 totalInCooldown; // Amount currently in unstaking cooldown
        uint256 timeUntilEarlyUnstake; // Time remaining until early unstake (seconds, 0 if not in cooldown)
        uint256 totalInEarlyCooldown; // Amount requested for early unstake (slot 5)
    }

    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    event Staked(address indexed user, uint256 amount, uint256 effectiveMultiplier, uint256 lockUpPeriod);
    event AmountIncreased(
        address indexed user, uint256 additionalAmount, uint256 newTotalAmount, uint256 newEffectiveMultiplier
    );
    event LockupIncreased(
        address indexed user, uint256 additionalLockup, uint256 newEffectiveLockup, uint256 newEffectiveMultiplier
    );
    event UnstakingInitiated(address indexed user, uint256 cooldownStart, uint256 cooldownAmount);
    event Unstaked(address indexed user, uint256 amount);
    event EarlyUnstake(address indexed user, uint256 amount, uint256 penalty);
    event EarlyUnstakeCooldownInitiated(address indexed user, uint256 cooldownStart, uint256 amount);
    event SapienTreasuryUpdated(address indexed newSapienTreasury);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);
    event QAPenaltyProcessed(address indexed user, uint256 penaltyAmount, address indexed qaContract);
    event QAStakeReduced(address indexed user, uint256 fromActiveStake, uint256 fromCooldownStake);
    event QACooldownAdjusted(address indexed user, uint256 adjustedAmount);
    event QAUserStakeReset(address indexed user);
    event MaximumStakeAmountUpdated(uint256 oldMaximumStakeAmount, uint256 newMaximumStakeAmount);
    event UserStakeUpdated(address indexed user, UserStake userStake);
    event UserStakeReset(address indexed user, UserStake userStake);
    // -------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------

    error ZeroAddress();
    error MinimumStakeAmountRequired();
    error MinimumUnstakeAmountRequired();
    error InvalidLockupPeriod();

    error InvalidAmount();
    error NoStakeFound();
    error ExistingStakeFound(); // Users with existing stakes must use increaseAmount() or increaseLockup()
    error CannotIncreaseStakeInCooldown();
    error StakeAmountTooLarge();
    error MinimumLockupIncreaseRequired();
    error StakeStillLocked();
    error AmountExceedsAvailableBalance();
    error NotReadyForUnstake();
    error AmountExceedsCooldownAmount();
    error LockPeriodCompleted();
    error RemainingStakeBelowMinimum();
    error EarlyUnstakeCooldownActive();
    error StakeInCooldown();
    error InvalidRecipient();
    error InsufficientSurplusForEmergencyWithdraw(uint256 surplus, uint256 amount);
    
    // QA specific errors

    error InsufficientStakeForPenalty();
    error EarlyUnstakeCooldownRequired();

    error AmountExceedsEarlyUnstakeRequest();

    // -------------------------------------------------------------
    // Initialization Functions
    // -------------------------------------------------------------

    function initialize(address token, address admin, address pauseManager, address treasury, address sapienQA)
        external;

    function version() external view returns (string memory);
    // -------------------------------------------------------------
    // Administrative Functions
    // -------------------------------------------------------------

    function PAUSER_ROLE() external view returns (bytes32);
    function SAPIEN_QA_ROLE() external view returns (bytes32);
    function pause() external;
    function unpause() external;
    function setTreasury(address newTreasury) external;
    function setMaximumStakeAmount(uint256 newMaximumStakeAmount) external;

    // -------------------------------------------------------------
    // Staking Functions
    // -------------------------------------------------------------

    function stake(uint256 amount, uint256 lockUpPeriod) external;
    function increaseAmount(uint256 additionalAmount) external;
    function increaseLockup(uint256 additionalLockup) external;
    function increaseStake(uint256 additionalAmount, uint256 additionalLockup) external;
    function initiateUnstake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function initiateEarlyUnstake(uint256 amount) external;
    function earlyUnstake(uint256 amount) external;

    // -------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------

    function totalStaked() external view returns (uint256);
    function maximumStakeAmount() external view returns (uint256);
    function getTotalStaked(address user) external view returns (uint256);
    function getTotalUnlocked(address user) external view returns (uint256);
    function getTotalLocked(address user) external view returns (uint256);
    function getTotalReadyForUnstake(address user) external view returns (uint256);
    function getTotalInCooldown(address user) external view returns (uint256);
    function getUserMultiplier(address user) external view returns (uint256);
    function getEarlyUnstakeCooldownAmount(address user) external view returns (uint256);
    function getTimeUntilEarlyUnstake(address user) external view returns (uint256);
    function getTimeUntilUnstake(address user) external view returns (uint256);

    function getUserStake(address user) external view returns (UserStake memory);
    function getUserStakingSummary(address user) external view returns (UserStakingSummary memory summary);
    function getTimeUntilUnlock(address user) external view returns (uint256);
    function getUserLockupPeriod(address user) external view returns (uint256);

    function isEarlyUnstakeReady(address user) external view returns (bool);
    function hasActiveStake(address user) external view returns (bool);
    function calculateMultiplier(uint256 amount, uint256 effectiveLockup) external view returns (uint256);

    // -------------------------------------------------------------
    // QA Functions
    // -------------------------------------------------------------

    function processQAPenalty(address userAddress, uint256 penaltyAmount) external returns (uint256 actualPenalty);
}
