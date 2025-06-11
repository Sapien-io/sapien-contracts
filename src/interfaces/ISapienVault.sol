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
            // Note: hasStake field removed - stake existence determined by amount > 0
            // This eliminates storage corruption and reduces gas costs
            // Total: 4 storage slots, with 4 bytes free in slot 4
    }

    struct WeightedValues {
        uint256 weightedStartTime;
        uint256 effectiveLockup;
    }

    struct UserStakingSummary {
        uint256 userTotalStaked; // Total amount staked by the user
        uint256 totalUnlocked; // Amount available for unstaking initiation
        uint256 totalLocked; // Amount still in lockup period
        uint256 totalInCooldown; // Amount currently in unstaking cooldown
        uint256 totalReadyForUnstake; // Amount ready for immediate withdrawal
        uint256 effectiveMultiplier; // Current multiplier for rewards (basis points)
        uint256 effectiveLockUpPeriod; // Weighted average lockup period (seconds)
        uint256 timeUntilUnlock; // Time remaining until unlock (seconds, 0 if unlocked)
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
    event EarlyUnstakeCooldownInitiated(address indexed user, uint256 cooldownStart);
    event SapienTreasuryUpdated(address indexed newSapienTreasury);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);
    event QAPenaltyProcessed(address indexed user, uint256 penaltyAmount, address indexed qaContract);
    event QAPenaltyPartial(address indexed user, uint256 requestedPenalty, uint256 actualPenalty);
    event QAStakeReduced(address indexed user, uint256 fromActiveStake, uint256 fromCooldownStake);
    event QACooldownAdjusted(address indexed user, uint256 adjustedAmount);
    event QAUserStakeReset(address indexed user);

    // -------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------

    error ZeroAddress();
    error MinimumStakeAmountRequired();
    error MinimumUnstakeAmountRequired();
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

    // Weighted calculation specific errors
    error AmountMustBePositive();
    error TotalAmountMustBePositive();
    error WeightedCalculationOverflow();
    error LockupWeightCalculationOverflow();

    // QA specific errors
    error UnauthorizedQAManager();
    error InsufficientStakeForPenalty();
    error InsufficientCooldownForPenalty();
    error EarlyUnstakeCooldownRequired();

    // -------------------------------------------------------------
    // Initialization Functions
    // -------------------------------------------------------------

    function initialize(address token, address admin, address pauseManager, address treasury, address sapienQA)
        external;

    // -------------------------------------------------------------
    // Administrative Functions
    // -------------------------------------------------------------

    function PAUSER_ROLE() external view returns (bytes32);
    function SAPIEN_QA_ROLE() external view returns (bytes32);
    function pause() external;
    function unpause() external;
    function setTreasury(address newTreasury) external;

    // -------------------------------------------------------------
    // Staking Functions
    // -------------------------------------------------------------

    function stake(uint256 amount, uint256 lockUpPeriod) external;
    function increaseAmount(uint256 additionalAmount) external;
    function increaseLockup(uint256 additionalLockup) external;
    function initiateUnstake(uint256 amount) external;
    function unstake(uint256 amount) external;
    function initiateEarlyUnstake(uint256 amount) external;
    function earlyUnstake(uint256 amount) external;

    // -------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------

    function totalStaked() external view returns (uint256);
    function getTotalStaked(address user) external view returns (uint256);
    function getTotalUnlocked(address user) external view returns (uint256);
    function getTotalLocked(address user) external view returns (uint256);
    function getTotalReadyForUnstake(address user) external view returns (uint256);
    function getTotalInCooldown(address user) external view returns (uint256);
    function getUserMultiplier(address user) external view returns (uint256);
    /**
     * @notice Returns the user's staking summary information as a struct
     * @param user The address of the user to query
     * @return summary The complete UserStakingSummary struct for the user
     */
    function getUserStakingSummary(address user) external view returns (UserStakingSummary memory summary);
    function getTimeUntilUnlock(address user) external view returns (uint256);
    function getUserLockupPeriod(address user) external view returns (uint256);
    function hasActiveStake(address user) external view returns (bool);

    // -------------------------------------------------------------
    // QA Functions
    // -------------------------------------------------------------

    function processQAPenalty(address userAddress, uint256 penaltyAmount) external returns (uint256 actualPenalty);
}
