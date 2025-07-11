// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/**
 * @file SapienVault.sol
 * @notice Sapien AI Staking Vault & Reputation System
 * @dev This contract implements a collateral staking mechanism that forms the backbone of the
 *      Sapien AI reputation system.
 *
 * KEY FEATURES:
 * - Flexible staking with lockup periods (30, 90, 180, 365 days) for higher multipliers
 * - Dynamic multiplier system based on both stake amount and commitment duration
 * - Two-phase unstaking: lockup expiration → cooldown period → withdrawal
 * - Early unstaking with penalties (20%) and cooldown protection against QA penalties
 * - Quality Assurance (QA) integration for stake penalties based on contribution quality
 * - Weighted averaging when combining stakes to prevent lockup period gaming
 * - Single stake per user design for simplified reputation calculations
 *
 * STAKING STATES:
 * 1. LOCKED: Tokens in lockup period (cannot initiate unstaking)
 * 2. UNLOCKED: Lockup completed, can initiate unstaking (moves to cooldown)
 * 3. COOLDOWN: Unstaking initiated, waiting for cooldown period completion
 * 4. READY: Cooldown completed, can execute final withdrawal
 *
 * REPUTATION SYSTEM:
 * - Higher stake amounts and longer lockups result in higher reputation multipliers
 * - Multipliers range from 1.05x (30 days) to 1.50x (365 days + high amounts)
 * - QA system can reduce stakes for poor quality contributions
 * - Reputation affects reward distribution and platform privileges
 *
 * SECURITY:
 * - Cooldown periods prevent immediate unstaking to avoid QA penalty gaming
 * - Weighted averaging prevents users from reducing effective lockup periods
 * - Emergency functions for critical security situations
 * - Role-based access control for administrative functions
 */
import {
    IERC20,
    SafeERC20,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
} from "src/utils/Common.sol";

import {SafeCast} from "src/utils/SafeCast.sol";
import {Constants as Const} from "src/utils/Constants.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";

using SafeCast for uint256;
using SafeERC20 for IERC20;

/// @title SapienVault - Sapien AI Staking Vault
/// @notice Sapien protocol reputation system with simplified single stake per user.
contract SapienVault is ISapienVault, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    /// @dev The Sapien token interface for staking/unstaking (IERC20).
    IERC20 public sapienToken;

    /// @dev Address of the Rewards Treasury
    address public treasury;

    /// @dev Tracks the total amount of tokens staked in this contract.
    uint256 public totalStaked;

    /// @notice Mapping of user addresses to their aggregated stake data.
    mapping(address => UserStake) public userStakes;

    /// @notice Maximum amount that can be staked in a single operation (configurable)
    uint256 public maximumStakeAmount;

    // -------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // -------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------

    /// @notice Returns the version of the contract
    function version() public pure returns (string memory) {
        return Const.VAULT_VERSION;
    }

    /**
     * @notice Initializes the SapienVault contract.
     * @param token The IERC20 token contract for Sapien.
     * @param admin The address of the admin multisig.
     * @param pauser The address of the pause manager multisig.
     * @param newTreasury The address of the treasury multisig for penalty collection.
     * @param sapienQA The address of the SapienQA contract.
     */
    function initialize(address token, address admin, address pauser, address newTreasury, address sapienQA)
        public
        initializer
    {
        if (token == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();
        if (pauser == address(0)) revert ZeroAddress();
        if (newTreasury == address(0)) revert ZeroAddress();
        if (sapienQA == address(0)) revert ZeroAddress();

        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(Const.PAUSER_ROLE, pauser);
        _grantRole(Const.SAPIEN_QA_ROLE, sapienQA);

        sapienToken = IERC20(token);
        treasury = newTreasury;
        maximumStakeAmount = Const.MAXIMUM_STAKE_AMOUNT; // Start at maximum from constants
    }

    // -------------------------------------------------------------
    // Access Control Modifiers
    // -------------------------------------------------------------

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, DEFAULT_ADMIN_ROLE);
        }
        _;
    }

    modifier onlyPauser() {
        if (!hasRole(Const.PAUSER_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, Const.PAUSER_ROLE);
        }
        _;
    }

    modifier onlySapienQA() {
        if (!hasRole(Const.SAPIEN_QA_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, Const.SAPIEN_QA_ROLE);
        }
        _;
    }

    // -------------------------------------------------------------
    // Role-Based Functions
    // -------------------------------------------------------------

    /**
     * @notice Returns the pauser role identifier
     * @return bytes32 The keccak256 hash of "PAUSER_ROLE"
     */
    function PAUSER_ROLE() external pure returns (bytes32) {
        return Const.PAUSER_ROLE;
    }

    /**
     * @notice Returns the Sapien QA role identifier
     * @return bytes32 The keccak256 hash of "SAPIEN_QA_ROLE"
     */
    function SAPIEN_QA_ROLE() external pure returns (bytes32) {
        return Const.SAPIEN_QA_ROLE;
    }

    /**
     * @notice Pauses the contract, preventing certain actions (e.g., staking/unstaking).
     */
    function pause() external onlyPauser {
        _pause();
    }

    /**
     * @notice Unpauses the contract, allowing staking/unstaking.
     */
    function unpause() external onlyPauser {
        _unpause();
    }

    /**
     * @notice Updates the treasury address for penalty collection.
     * @param newTreasury The new treasury address.
     */
    function setTreasury(address newTreasury) external onlyAdmin {
        if (newTreasury == address(0)) {
            revert ZeroAddress();
        }

        treasury = newTreasury;
        emit SapienTreasuryUpdated(newTreasury);
    }

    /**
     * @notice Updates the maximum stake amount for individual staking operations.
     * @param newMaximumStakeAmount The new maximum stake amount.
     */
    function setMaximumStakeAmount(uint256 newMaximumStakeAmount) external onlyAdmin {
        if (newMaximumStakeAmount == 0) {
            revert InvalidAmount();
        }

        uint256 oldMaximumStakeAmount = maximumStakeAmount;
        maximumStakeAmount = newMaximumStakeAmount;
        emit MaximumStakeAmountUpdated(oldMaximumStakeAmount, newMaximumStakeAmount);
    }

    /**
     * @notice Emergency withdrawal function for admin use only in critical situations
     * @param token The token to withdraw (use address(0) for ETH)
     * @param to The address to withdraw to
     * @param amount The amount to withdraw
     * @dev This function should only be used in emergency situations where contract is compromised
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyAdmin whenPaused nonReentrant {
        if (to == address(0)) revert ZeroAddress();

        if (token == address(0)) {
            // Withdraw ETH
            (bool success,) = to.call{value: amount}("");
            if (!success) revert InvalidAmount();
        } else {
            // Withdraw ERC20 token
            IERC20(token).safeTransfer(to, amount);
        }

        emit EmergencyWithdraw(token, to, amount);
    }

    // -------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------

    /**
     * @notice Retrieves comprehensive staking summary for a user's position
     * @dev This is the primary function for retrieving all relevant staking information
     * for a user in a single call. It aggregates data from multiple internal functions
     * to provide a complete picture of the user's staking status.
     * @param user The address of the user to query
     * @return summary The complete UserStakingSummary struct containing all staking information
     *
     * RETURN VALUES EXPLAINED:
     * - userTotalStaked: Total tokens the user has staked (including locked and unlocked)
     * - totalUnlocked: Tokens that have completed lockup and can be queued for unstaking
     * - totalLocked: Tokens still in their lockup period that cannot be unstaked yet
     * - totalInCooldown: Tokens queued for unstaking but still in cooldown period
     * - totalReadyForUnstake: Tokens that completed cooldown and can be withdrawn immediately
     * - effectiveMultiplier: Current multiplier applied to this user's stake for rewards
     * - effectiveLockUpPeriod: Lockup period for the user's position
     * - timeUntilUnlock: Seconds remaining until the stake becomes unlocked (0 if already unlocked)
     * - timeUntilEarlyUnstake: Seconds remaining until early unstake is ready (0 if not in cooldown)
     * - earlyUnstakeCooldownAmount: Amount requested for early unstake (slot 5)
     *
     * STAKING STATES:
     * 1. LOCKED: Tokens in lockup period (cannot initiate unstaking)
     * 2. UNLOCKED: Lockup completed, can initiate unstaking (moves to cooldown)
     * 3. COOLDOWN: Unstaking initiated, waiting for cooldown period completion
     * 4. READY: Cooldown completed, can execute final withdrawal
     *
     * USAGE EXAMPLES:
     * - Frontend dashboards: Display complete user staking status
     * - DeFi integrations: Check available liquidity before transactions
     * - Rewards calculations: Use effectiveMultiplier for accurate reward computation
     * - Unstaking flows: Guide users through unlock → cooldown → withdrawal process
     *
     * IMPORTANT NOTES:
     * - All amounts are in token base units (typically 18 decimals)
     * - Multiplier is in basis points (10000 = 1.0x multiplier)
     * - Time values are in seconds since Unix epoch
     * - Returns zeros for users with no active stake
     */
    function getUserStakingSummary(address user) public view returns (ISapienVault.UserStakingSummary memory summary) {
        UserStake memory userStake = userStakes[user];
        if (userStake.amount > 0) {
            summary.userTotalStaked = userStake.amount;
            summary.totalUnlocked = getTotalUnlocked(user);
            summary.totalLocked = getTotalLocked(user);
            summary.totalInCooldown = getTotalInCooldown(user);
            summary.totalReadyForUnstake = getTotalReadyForUnstake(user);
            summary.effectiveMultiplier = userStake.effectiveMultiplier;
            summary.effectiveLockUpPeriod = userStake.effectiveLockUpPeriod;
            summary.timeUntilUnlock = getTimeUntilUnlock(user);
            summary.timeUntilEarlyUnstake = getTimeUntilEarlyUnstake(user);
            summary.earlyUnstakeCooldownAmount = getEarlyUnstakeCooldownAmount(user);
        } else {
            summary.userTotalStaked = 0;
            summary.totalUnlocked = 0;
            summary.totalLocked = 0;
            summary.totalInCooldown = 0;
            summary.totalReadyForUnstake = 0;
            summary.effectiveMultiplier = 0;
        }
    }

    /**
     * @notice Returns the raw stake data for a user
     * @dev This function provides direct access to the user's stake data structure
     * without any additional calculations or transformations.
     *
     * USAGE CONTEXT:
     * - Direct access to raw stake data for internal contract operations
     * - Debugging and monitoring of stake positions
     * - Integration with other contracts that need raw stake data
     *
     * RETURN VALUES:
     * - amount: Total tokens staked by the user
     * - effectiveMultiplier: Current multiplier applied to the stake
     * - effectiveLockUpPeriod: Lockup period
     * - lockupEndTime: Timestamp when the lockup period ends
     * - cooldownEndTime: Timestamp when the cooldown period ends
     *
     * IMPORTANT NOTES:
     * - Returns empty struct for users with no stake
     * - All time values are Unix timestamps
     * - Multiplier is in basis points (10000 = 1.0x)
     *
     * @param user The address of the user to query
     * @return UserStake struct containing the user's stake data
     */
    function getUserStake(address user) public view returns (UserStake memory) {
        return userStakes[user];
    }

    // -------------------------------------------------------------
    // Multiplier Calculation Helpers
    // -------------------------------------------------------------

    /**
     * @notice Calculates the multiplier for a stake position
     * @dev This is a core function that determines the reward multiplier applied to a user's stake.
     * The multiplier affects how much weight this stake carries in the reputation system and
     * potentially in reward distribution calculations.
     *
     * BUSINESS CONTEXT:
     * - Multipliers incentivize longer commitments and larger stakes
     * - The system balances individual commitment (amount + lockup)
     *
     * MULTIPLIER FACTORS:
     * - Stake Amount: Larger stakes may receive multiplier bonuses
     * - Lockup Period: Longer commitments receive higher multipliers
     *
     * PRECISION & SCALING:
     * - Multipliers are returned in basis points (10000 = 1.0x)
     *
     * @param amount The total staked amount for this position
     * @param effectiveLockup The lockup period for this position
     * @return uint256 calculated effective multiplier
     */
    function calculateMultiplier(uint256 amount, uint256 effectiveLockup) public pure returns (uint256) {
        // Clamp inputs to valid ranges
        uint256 maxTokens = Const.MAXIMUM_STAKE_AMOUNT;

        if (amount > maxTokens) {
            amount = maxTokens;
        }

        if (effectiveLockup > Const.LOCKUP_365_DAYS) {
            effectiveLockup = Const.LOCKUP_365_DAYS;
        }

        // Calculate bonus with single division to minimize precision loss
        uint256 bonus = (effectiveLockup * amount * Const.MAX_BONUS) / (Const.LOCKUP_365_DAYS * maxTokens);

        return Const.BASE_MULTIPLIER + bonus;
    }

    /**
     * @notice Checks if a user has an active stake
     * @param user The address of the user to check
     * @return hasStake true if the user has an active stake, false otherwise
     */
    function hasActiveStake(address user) external view returns (bool hasStake) {
        if (user == address(0)) return false;
        return userStakes[user].amount > 0;
    }

    /**
     * @notice Returns the total amount of tokens staked by a user
     * @param user The address of the user to check
     * @return userTotalStaked The total amount of tokens staked by the user
     */
    function getTotalStaked(address user) public view returns (uint256 userTotalStaked) {
        return userStakes[user].amount;
    }

    /**
     * @notice Returns the amount of tokens that are unlocked and available for unstaking
     * @dev This excludes tokens that are in cooldown
     * @param user The address of the user to check
     * @return totalUnlocked The amount of unlocked tokens available for unstaking
     */
    function getTotalUnlocked(address user) public view returns (uint256 totalUnlocked) {
        UserStake storage userStake = userStakes[user];
        if (!_isUnlocked(userStake)) return 0;

        // Ensure we never return negative values due to inconsistency
        if (userStake.amount <= userStake.cooldownAmount) return 0;

        return userStake.amount - userStake.cooldownAmount;
    }

    /**
     * @notice Returns the amount of tokens that are still locked and cannot be unstaked
     * @dev Returns 0 if tokens are unlocked or in cooldown
     * @param user The address of the user to check
     * @return totalLocked amount of tokens still locked
     */
    function getTotalLocked(address user) public view returns (uint256 totalLocked) {
        UserStake storage userStake = userStakes[user];
        if (_isUnlocked(userStake) || userStake.cooldownAmount > 0) return 0;
        return userStake.amount;
    }

    /**
     * @notice Returns the amount of tokens that have completed cooldown and are ready to be unstaked
     * @dev Returns 0 if tokens are not ready for unstaking
     * @param user The address of the user to check
     * @return totalReadyForUnstake amount of tokens ready for unstaking
     */
    function getTotalReadyForUnstake(address user) public view returns (uint256 totalReadyForUnstake) {
        UserStake storage userStake = userStakes[user];
        if (!_isReadyForUnstake(userStake)) return 0;
        return userStake.cooldownAmount;
    }

    /**
     * @notice Returns the amount of tokens currently in cooldown period
     * @dev Returns 0 if user has no stake or is not in cooldown
     * @param user The address of the user to check
     * @return totalInCooldown amount of tokens in cooldown
     */
    function getTotalInCooldown(address user) public view returns (uint256 totalInCooldown) {
        UserStake memory userStake = userStakes[user];
        if (userStake.amount == 0 || userStake.cooldownStart == 0) return 0;

        // Ensure cooldown amount doesn't exceed total amount
        return userStake.cooldownAmount > userStake.amount ? userStake.amount : userStake.cooldownAmount;
    }

    /**
     * @notice Get the effective multiplier for a user's stake
     * @param user The address of the user to query
     * @return effectiveMultiplier effective multiplier for the user's stake (basis points)
     */
    function getUserMultiplier(address user) public view returns (uint256 effectiveMultiplier) {
        return userStakes[user].effectiveMultiplier;
    }

    /**
     * @notice Get the effective lockup period for a user's stake
     * @param user The address of the user to query
     * @return effectiveLockUpPeriod effective lockup period for the user's stake (seconds)
     */
    function getUserLockupPeriod(address user) public view returns (uint256 effectiveLockUpPeriod) {
        return userStakes[user].effectiveLockUpPeriod;
    }

    /**
     * @notice Get the time until a user's stake is unlocked
     * @param user The address of the user to query
     * @return timeUntilUnlock time until the user's stake is unlocked (seconds)
     */
    function getTimeUntilUnlock(address user) public view returns (uint256 timeUntilUnlock) {
        UserStake memory userStake = userStakes[user];
        if (userStake.amount == 0) return 0;
        uint256 unlockTime = userStake.weightedStartTime + userStake.effectiveLockUpPeriod;
        return block.timestamp >= unlockTime ? 0 : unlockTime - block.timestamp;
    }

    /**
     * @notice Get the amount requested for early unstake
     * @param user The address of the user to query
     * @return amount The amount requested for early unstake
     */
    function getEarlyUnstakeCooldownAmount(address user) public view returns (uint256 amount) {
        return userStakes[user].earlyUnstakeCooldownAmount;
    }

    /**
     * @notice Check if user's early unstake cooldown has completed
     * @param user The address of the user to query
     * @return ready True if early unstake is ready, false otherwise
     */
    function isEarlyUnstakeReady(address user) public view returns (bool ready) {
        UserStake memory userStake = userStakes[user];
        return userStake.earlyUnstakeCooldownStart > 0
            && block.timestamp >= userStake.earlyUnstakeCooldownStart + Const.COOLDOWN_PERIOD;
    }

    /**
     * @notice Validates if a lockup period is valid
     * @param lockUpPeriod The lockup period to validate
     * @return bool True if the lockup period is valid
     */
    function isValidLockUpPeriod(uint256 lockUpPeriod) public pure returns (bool) {
        return lockUpPeriod >= Const.MINIMUM_LOCKUP_INCREASE && lockUpPeriod <= Const.LOCKUP_365_DAYS;
    }

    /**
     * @notice Get the time remaining until early unstake is ready
     * @param user The address of the user to query
     * @return timeUntilEarlyUnstake time remaining until early unstake is ready (seconds)
     */
    function getTimeUntilEarlyUnstake(address user) public view returns (uint256 timeUntilEarlyUnstake) {
        UserStake memory userStake = userStakes[user];
        if (userStake.earlyUnstakeCooldownStart == 0) return 0;
        uint256 cooldownEndTime = userStake.earlyUnstakeCooldownStart + Const.COOLDOWN_PERIOD;
        return block.timestamp >= cooldownEndTime ? 0 : cooldownEndTime - block.timestamp;
    }

    // -------------------------------------------------------------
    //  Stake Management
    // -------------------------------------------------------------

    /**
     * @notice Get the amount requested for unstake.
     * @dev This can only be called if the users does not have an active stake.
     * @notice Stake a specified `amount` of tokens for a given `lockUpPeriod`.
     * @param amount The amount of tokens to stake.
     * @param lockUpPeriod The lock-up duration in seconds (30/90/180/365 days).
     */
    function stake(uint256 amount, uint256 lockUpPeriod) public whenNotPaused nonReentrant {
        UserStake storage userStake = userStakes[msg.sender];

        _validateStakeInputs(amount, lockUpPeriod, userStake);

        sapienToken.safeTransferFrom(msg.sender, address(this), amount);

        _processFirstTimeStake(userStake, amount, lockUpPeriod);

        totalStaked += amount;
        emit Staked(msg.sender, amount, userStake.effectiveMultiplier, userStake.effectiveLockUpPeriod);
    }

    /**
     * @notice Increases the staked amount while maintaining the existing lockup period and weighted start time.
     * @param additionalAmount The additional amount to stake.
     */
    function increaseAmount(uint256 additionalAmount) public whenNotPaused nonReentrant {
        UserStake storage userStake = userStakes[msg.sender];

        _validateIncreaseAmount(additionalAmount, userStake);

        // Use standardized expired stake handling
        uint256 newWeightedStartTime =
            _calculateStandardizedWeightedStartTime(userStake, additionalAmount, userStake.amount + additionalAmount);

        sapienToken.safeTransferFrom(msg.sender, address(this), additionalAmount);

        uint256 newTotalAmount = userStake.amount + additionalAmount;

        // Update state
        userStake.weightedStartTime = newWeightedStartTime.toUint64();
        userStake.amount = newTotalAmount.toUint128();
        userStake.lastUpdateTime = block.timestamp.toUint64();

        // Recalculate linear weighted multiplier based on new total amount
        userStake.effectiveMultiplier = calculateMultiplier(newTotalAmount, userStake.effectiveLockUpPeriod).toUint32();

        totalStaked += additionalAmount;

        emit AmountIncreased(msg.sender, additionalAmount, newTotalAmount, userStake.effectiveMultiplier);
    }

    /**
     * @notice Increase the lockup period for existing stake.
     * @param additionalLockup The additional lockup time in seconds.
     */
    function increaseLockup(uint256 additionalLockup) public whenNotPaused nonReentrant {
        UserStake storage userStake = userStakes[msg.sender];

        _validateIncreaseLockup(additionalLockup, userStake);

        // Handle expired vs active stakes
        uint256 newEffectiveLockup;

        if (_isUnlocked(userStake)) {
            newEffectiveLockup = additionalLockup;
            userStake.weightedStartTime = block.timestamp.toUint64();
        } else {
            // combine the remaining lockup time with the additional lockup
            uint256 timeElapsed = block.timestamp - userStake.weightedStartTime;
            uint256 remainingLockup =
                userStake.effectiveLockUpPeriod > timeElapsed ? userStake.effectiveLockUpPeriod - timeElapsed : 0;

            newEffectiveLockup = remainingLockup + additionalLockup;
            // Note: Extending lockup resets the timer - the new lockup period starts from now
            userStake.weightedStartTime = block.timestamp.toUint64();
        }

        if (newEffectiveLockup > Const.LOCKUP_365_DAYS) {
            newEffectiveLockup = Const.LOCKUP_365_DAYS;
        }

        userStake.effectiveLockUpPeriod = newEffectiveLockup.toUint64();
        userStake.effectiveMultiplier = calculateMultiplier(userStake.amount, newEffectiveLockup).toUint32();
        userStake.lastUpdateTime = block.timestamp.toUint64();

        emit LockupIncreased(msg.sender, additionalLockup, newEffectiveLockup, userStake.effectiveMultiplier);
    }

    /**
     * @notice Increases both the staked amount and lockup period in a single transaction.
     * @param additionalAmount The additional amount to stake.
     * @param additionalLockup The additional lockup time in seconds.
     * @dev This function simply calls increaseAmount and increaseLockup in sequence for better UX.
     */
    function increaseStake(uint256 additionalAmount, uint256 additionalLockup) external {
        increaseAmount(additionalAmount);
        increaseLockup(additionalLockup);
    }

    /**
     * @notice Initiates the cooldown for unstaking.
     * @param amount The amount intended for unstaking.
     */
    function initiateUnstake(uint256 amount) public whenNotPaused nonReentrant {
        UserStake storage userStake = userStakes[msg.sender];

        _validateInitiateUnstakeInputs(amount, userStake);

        uint256 cooldownAmount = userStake.cooldownAmount;
        uint256 newCooldownAmount = cooldownAmount + amount;

        userStake.cooldownStart = block.timestamp.toUint64();
        userStake.cooldownAmount = newCooldownAmount.toUint128();

        emit UnstakingInitiated(msg.sender, block.timestamp.toUint64(), newCooldownAmount);
    }

    /**
     * @notice Completes the unstaking process after the cooldown period has passed.
     * @param amount The amount to unstake.
     */
    function unstake(uint256 amount) external whenNotPaused nonReentrant {
        UserStake storage userStake = userStakes[msg.sender];

        _validateUnstakeInputs(amount, userStake);

        uint256 newUserStakeAmount = userStake.amount - amount;

        if (newUserStakeAmount > 0 && newUserStakeAmount < Const.MINIMUM_STAKE_AMOUNT) {
            // Force complete unstaking
            amount = userStake.amount;
            newUserStakeAmount = 0;
        }

        userStake.amount = newUserStakeAmount.toUint128();
        totalStaked -= amount;

        _updateUserStakeAfterUnstake(userStake, amount, newUserStakeAmount);

        sapienToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Initiates early unstake cooldown for a specified amount.
     * @param amount The amount to initiate early unstake for.
     * @dev This function starts the cooldown period required before earlyUnstake can be called.
     *      This prevents users from avoiding QA penalties by immediately unstaking.
     */
    function initiateEarlyUnstake(uint256 amount) external whenNotPaused nonReentrant {
        UserStake storage userStake = userStakes[msg.sender];

        _validateInitiateEarlyUnstakeInputs(amount, userStake);

        // Set early unstake cooldown start time AND amount
        userStake.earlyUnstakeCooldownStart = block.timestamp.toUint64();
        userStake.earlyUnstakeCooldownAmount = amount.toUint128();

        emit EarlyUnstakeCooldownInitiated(msg.sender, block.timestamp, amount);
    }

    /**
     * @notice  Unstakes early a specified amount, incurring a penalty.
     * @param amount The amount to unstake instantly.
     * @dev Now requires a cooldown period to prevent QA penalty avoidance.
     */
    function earlyUnstake(uint256 amount) external whenNotPaused nonReentrant {
        UserStake storage userStake = userStakes[msg.sender];

        _validateEarlyUnstakeInputs(amount, userStake);

        uint256 newUserStakeAmount = userStake.amount - amount;

        if (newUserStakeAmount > 0 && newUserStakeAmount < Const.MINIMUM_STAKE_AMOUNT) {
            // Force complete unstaking
            amount = userStake.amount;
            newUserStakeAmount = 0;
        }

        uint256 penalty = (amount * Const.EARLY_WITHDRAWAL_PENALTY) / Const.BASIS_POINTS;
        uint256 payout = amount - penalty;

        totalStaked -= amount;

        _updateUserStakeAfterUnstake(userStake, amount, newUserStakeAmount);

        sapienToken.safeTransfer(msg.sender, payout);
        sapienToken.safeTransfer(treasury, penalty);

        emit EarlyUnstake(msg.sender, payout, penalty);
    }

    function _validateInitiateUnstakeInputs(uint256 amount, UserStake storage userStake) private view {
        if (amount == 0) revert InvalidAmount();
        if (userStake.amount == 0) revert NoStakeFound();
        if (!_isUnlocked(userStake)) revert StakeStillLocked();
        if (amount > userStake.amount - userStake.cooldownAmount) revert AmountExceedsAvailableBalance();
    }

    function _validateStakeInputs(uint256 amount, uint256 lockUpPeriod, UserStake memory userStake) private view {
        if (amount < Const.MINIMUM_STAKE_AMOUNT) revert MinimumStakeAmountRequired();
        if (userStake.amount > 0) revert ExistingStakeFound();
        if (amount > maximumStakeAmount) revert StakeAmountTooLarge();
        if (!isValidLockUpPeriod(lockUpPeriod)) revert InvalidLockupPeriod();
    }

    function _validateUnstakeInputs(uint256 amount, UserStake storage userStake) private view {
        if (amount == 0) revert InvalidAmount();
        if (userStake.amount == 0) revert NoStakeFound();
        if (!_isReadyForUnstake(userStake)) revert NotReadyForUnstake();
        if (amount > userStake.cooldownAmount) revert AmountExceedsCooldownAmount();
    }

    function _validateInitiateEarlyUnstakeInputs(uint256 amount, UserStake storage userStake) private view {
        if (amount == 0) revert InvalidAmount();
        if (amount < Const.MINIMUM_UNSTAKE_AMOUNT) revert MinimumUnstakeAmountRequired();
        if (userStake.amount == 0) revert NoStakeFound();
        if (amount > userStake.amount - userStake.cooldownAmount) revert AmountExceedsAvailableBalance();
        if (_isUnlocked(userStake)) revert LockPeriodCompleted();
        if (userStake.earlyUnstakeCooldownStart != 0) revert EarlyUnstakeCooldownActive();
    }

    function _validateEarlyUnstakeInputs(uint256 amount, UserStake storage userStake) private view {
        if (userStake.amount == 0) revert NoStakeFound();
        if (_isUnlocked(userStake)) revert LockPeriodCompleted();
        if (userStake.earlyUnstakeCooldownStart == 0) revert EarlyUnstakeCooldownRequired();
        if (amount > userStake.earlyUnstakeCooldownAmount) revert AmountExceedsEarlyUnstakeRequest();

        if (block.timestamp < userStake.earlyUnstakeCooldownStart + Const.COOLDOWN_PERIOD) {
            revert EarlyUnstakeCooldownRequired();
        }
    }

    function _validateIncreaseLockup(uint256 additionalLockup, UserStake storage userStake) private view {
        if (userStake.amount == 0) revert NoStakeFound();
        if (additionalLockup < Const.MINIMUM_LOCKUP_INCREASE) revert MinimumLockupIncreaseRequired();

        if (userStake.cooldownStart != 0 || userStake.earlyUnstakeCooldownStart != 0) {
            revert CannotIncreaseStakeInCooldown();
        }
    }

    function _validateIncreaseAmount(uint256 additionalAmount, UserStake storage userStake) private view {
        if (additionalAmount == 0) revert InvalidAmount();
        if (additionalAmount > maximumStakeAmount) revert StakeAmountTooLarge();
        if (userStake.amount == 0) revert NoStakeFound();

        if (userStake.cooldownStart != 0 || userStake.earlyUnstakeCooldownStart != 0) {
            revert CannotIncreaseStakeInCooldown();
        }
    }

    function _updateUserStakeAfterUnstake(UserStake storage userStake, uint256 amount, uint256 newUserStakeAmount)
        private
    {
        if (newUserStakeAmount == 0) {
            _resetUserStake(userStake);
            return;
        }

        userStake.amount = newUserStakeAmount.toUint128();
        userStake.lastUpdateTime = block.timestamp.toUint64();
        userStake.effectiveMultiplier =
            calculateMultiplier(newUserStakeAmount, userStake.effectiveLockUpPeriod).toUint32();

        // handle early unstake cooldown
        if (userStake.earlyUnstakeCooldownAmount > 0) {
            if (amount >= userStake.earlyUnstakeCooldownAmount) {
                userStake.earlyUnstakeCooldownAmount = 0;
                userStake.earlyUnstakeCooldownStart = 0;
            } else {
                userStake.earlyUnstakeCooldownAmount -= amount.toUint128();
            }
        }

        // Handle normal cooldown
        if (userStake.cooldownAmount > 0) {
            if (amount >= userStake.cooldownAmount) {
                userStake.cooldownAmount = 0;
                userStake.cooldownStart = 0;
            } else {
                userStake.cooldownAmount -= amount.toUint128();
            }
        }

        emit UserStakeUpdated(msg.sender, userStake);
    }

    function _processFirstTimeStake(UserStake storage userStake, uint256 amount, uint256 lockUpPeriod) private {
        userStake.amount = amount.toUint128();
        userStake.weightedStartTime = block.timestamp.toUint64();
        userStake.effectiveLockUpPeriod = lockUpPeriod.toUint64();
        userStake.effectiveMultiplier = calculateMultiplier(amount, lockUpPeriod).toUint32();
        userStake.lastUpdateTime = block.timestamp.toUint64();

        emit UserStakeUpdated(msg.sender, userStake);
    }

    function _calculateWeightedStartTime(
        uint256 currentStartTime,
        uint256 currentAmount,
        uint256 newAmount,
        uint256 totalAmount
    ) private view returns (uint256 newWeightedStartTime) {
        // Prevent dust attacks with very small amounts
        if (newAmount < Const.MINIMUM_STAKE_AMOUNT / 100) {
            revert InvalidAmount();
        }

        uint256 existingWeight = currentStartTime * currentAmount;
        uint256 newWeight = block.timestamp * newAmount;

        uint256 totalWeight = existingWeight + newWeight;
        newWeightedStartTime = totalWeight / totalAmount;

        // Apply banker's rounding: round up if remainder > 50%
        uint256 remainder = totalWeight % totalAmount;
        if (remainder > totalAmount / 2) {
            newWeightedStartTime += 1;
        }
    }

    // -------------------------------------------------------------
    // Helper Functions
    // -------------------------------------------------------------

    function _isUnlocked(UserStake storage userStake) private view returns (bool) {
        return userStake.amount > 0 && block.timestamp >= userStake.weightedStartTime + userStake.effectiveLockUpPeriod;
    }

    function _isReadyForUnstake(UserStake storage userStake) private view returns (bool) {
        return userStake.amount > 0 && userStake.cooldownStart > 0
            && block.timestamp >= userStake.cooldownStart + Const.COOLDOWN_PERIOD && userStake.cooldownAmount > 0;
    }

    function _resetUserStake(UserStake storage userStake) private {
        delete userStake.amount;
        delete userStake.cooldownAmount;
        delete userStake.weightedStartTime;
        delete userStake.effectiveLockUpPeriod;
        delete userStake.effectiveMultiplier;
        delete userStake.lastUpdateTime;
        delete userStake.cooldownStart;
        delete userStake.earlyUnstakeCooldownStart;
        delete userStake.earlyUnstakeCooldownAmount;

        emit UserStakeReset(msg.sender, userStake);
    }

    function _calculateStandardizedWeightedStartTime(
        UserStake storage userStake,
        uint256 newAmount,
        uint256 totalAmount
    ) private view returns (uint256 newWeightedStartTime) {
        // If stake is expired/unlocked, reset to current timestamp
        if (_isUnlocked(userStake)) {
            return block.timestamp;
        }

        // Calculate weighted start time for active stakes
        return _calculateWeightedStartTime(userStake.weightedStartTime, userStake.amount, newAmount, totalAmount);
    }

    // -------------------------------------------------------------
    // QA Functions
    // -------------------------------------------------------------

    /**
     * @notice Process a QA penalty by transferring user's percentage of stake to Rewards Treasury
     * @param userAddress The user being penalized
     * @param penaltyAmount The amount to transfer as penalty
     * @return actualPenalty The actual amount processed (may be less than requested if insufficient stake)
     * @dev Can only be called by SapienQA contract
     */
    function processQAPenalty(address userAddress, uint256 penaltyAmount)
        external
        nonReentrant
        whenNotPaused
        onlySapienQA
        returns (uint256 actualPenalty)
    {
        if (userAddress == address(0)) revert ZeroAddress();
        if (penaltyAmount == 0) revert InvalidAmount();

        UserStake storage userStake = userStakes[userAddress];

        // Calculate how much penalty can actually be applied
        actualPenalty = _calculateApplicablePenalty(userStake, penaltyAmount);
        if (actualPenalty == 0) revert InsufficientStakeForPenalty();

        // Apply the penalty to user's stakes
        _applyPenaltyToUserStake(userStake, actualPenalty, userAddress);

        // Update user stake state after penalty
        _updateUserStakeAfterPenalty(userStake, userAddress);

        // Transfer penalty to treasury
        sapienToken.safeTransfer(treasury, actualPenalty);

        emit QAPenaltyProcessed(userAddress, actualPenalty, msg.sender);
    }

    /**
     * @dev Calculate the maximum penalty that can be applied given available stake
     */
    function _calculateApplicablePenalty(UserStake storage userStake, uint256 requestedPenalty)
        internal
        view
        returns (uint256)
    {
        // Only use amount as the maximum penalty, since cooldownAmount is already counted within amount
        uint256 totalAvailable = userStake.amount;
        return requestedPenalty > totalAvailable ? totalAvailable : requestedPenalty;
    }

    /**
     * @dev Apply penalty by reducing stake amounts while maintaining consistency
     */
    function _applyPenaltyToUserStake(UserStake storage userStake, uint256 penaltyAmount, address userAddress)
        internal
    {
        uint256 originalCooldownAmount = userStake.cooldownAmount;

        // Apply penalty using enhanced primary stake reduction
        // This function now handles both primary stake reduction AND cooldown consistency
        uint256 fromActiveStake = _reducePrimaryStake(userStake, penaltyAmount);

        // CONSISTENCY CHECK: Log any cooldown adjustments for transparency
        uint256 cooldownReduction = originalCooldownAmount - userStake.cooldownAmount;
        if (cooldownReduction > 0) {
            emit QACooldownAdjusted(userAddress, cooldownReduction);
        }

        // Emit detailed breakdown - fromCooldownStake is always 0 since _reducePrimaryStake handles everything
        emit QAStakeReduced(userAddress, fromActiveStake, 0);
    }

    /**
     * @dev Reduce active stake amount and update total staked tracking
     */
    function _reducePrimaryStake(UserStake storage userStake, uint256 maxReduction)
        internal
        returns (uint256 actualReduction)
    {
        uint256 availableStake = userStake.amount;
        if (availableStake == 0) return 0;

        actualReduction = maxReduction > availableStake ? availableStake : maxReduction;
        uint256 newAmount = availableStake - actualReduction;

        userStake.amount = newAmount.toUint128();
        totalStaked -= actualReduction;

        // Ensure cooldown amount never exceeds remaining stake
        if (userStake.cooldownAmount > newAmount) {
            userStake.cooldownAmount = newAmount.toUint128();

            // Clear cooldown start if no cooldown amount remains
            if (newAmount == 0) {
                userStake.cooldownStart = 0;
            }
        }

        // SECURITY FIX: Handle early unstake cooldown amount when QA penalty reduces stake
        if (userStake.earlyUnstakeCooldownAmount > 0) {
            if (userStake.earlyUnstakeCooldownAmount > newAmount) {
                // Reduce to available amount
                userStake.earlyUnstakeCooldownAmount = newAmount.toUint128();
            }

            // Cancel early unstake cooldown if the cooldown amount falls below minimum
            if (userStake.earlyUnstakeCooldownAmount < Const.MINIMUM_UNSTAKE_AMOUNT) {
                userStake.earlyUnstakeCooldownStart = 0;
                userStake.earlyUnstakeCooldownAmount = 0;
            }
        }
    }

    /**
     * @dev Update user stake state after penalty application (reset if empty, recalculate multiplier if not)
     */
    function _updateUserStakeAfterPenalty(UserStake storage userStake, address userAddress) internal {
        bool _hasActiveStake = userStake.amount > 0;
        bool _hasCooldownStake = userStake.cooldownAmount > 0;

        // If no stake remaining, reset completely
        if (!_hasActiveStake && !_hasCooldownStake) {
            _resetUserStake(userStake);
            emit QAUserStakeReset(userAddress);
            return;
        }

        // Recalculate multiplier for remaining active stake
        if (_hasActiveStake) {
            if (userStake.amount >= Const.MINIMUM_STAKE_AMOUNT) {
                // Normal case: use calculated multiplier
                userStake.effectiveMultiplier =
                    calculateMultiplier(userStake.amount, userStake.effectiveLockUpPeriod).toUint32();
            } else {
                // Below minimum stake due to penalty: use base multiplier (1x)
                userStake.effectiveMultiplier = Const.BASE_MULTIPLIER.toUint32();
            }
        }

        userStake.lastUpdateTime = block.timestamp.toUint64();
    }
}
