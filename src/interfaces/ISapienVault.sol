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
        bool hasStake; // 1 byte - Whether user has any active stake (slot 4)
            // Total: 4 storage slots, added early unstake cooldown tracking
    }

    struct WeightedValues {
        uint256 weightedStartTime;
        uint256 effectiveLockup;
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
    event MultiplierUpdated(uint256 lockUpPeriod, uint256 multiplier);
    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);
    event QAPenaltyProcessed(address indexed user, uint256 amount, address qaContract);
    event QAPenaltyPartial(address indexed user, uint256 requestedAmount, uint256 actualAmount);
    event QAStakeReduced(address indexed user, uint256 fromActiveStake, uint256 fromCooldownStake);
    event QAUserStakeReset(address indexed user);

    // -------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------

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

    function initialize(address token, address admin, address treasury, address newMultiplierContract, address sapienQA)
        external;

    // -------------------------------------------------------------
    // Administrative Functions
    // -------------------------------------------------------------

    function PAUSER_ROLE() external view returns (bytes32);
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

    function hasActiveStake(address user) external view returns (bool);

    // -------------------------------------------------------------
    // QA Functions
    // -------------------------------------------------------------

    function processQAPenalty(address userAddress, uint256 penaltyAmount) external returns (uint256 actualPenalty);
}
