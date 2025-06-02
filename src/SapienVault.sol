// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {
    IERC20,
    SafeERC20,
    Initializable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
} from "src/utils/Common.sol";

import {SafeCast} from "src/utils/SafeCast.sol";
import {Constants as Const} from "src/utils/Constants.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {IMultiplier} from "src/interfaces/IMultiplier.sol";

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

    /// @dev The Multiplier contract for calculating staking multipliers
    IMultiplier public multiplier;

    /// @dev Tracks the total amount of tokens staked in this contract.
    uint256 public totalStaked;

    /// @notice Mapping of user addresses to their aggregated stake data.
    mapping(address => UserStake) public userStakes;

    // -------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------

    /**
     * @notice Initializes the SapienVault contract.
     * @param token The IERC20 token contract for Sapien.
     * @param admin The address of the admin multisig.
     * @param newTreasury The address of the Rewards Safe multisig for penalty collection.
     */
    function initialize(address token, address admin, address newTreasury, address newMultiplierContract, address sapienQA)
        public
        initializer
    {
        if (token == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();
        if (newTreasury == address(0)) revert ZeroAddress();
        if (newMultiplierContract == address(0)) revert ZeroAddress();
        if (sapienQA == address(0)) revert ZeroAddress();

        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(Const.PAUSER_ROLE, admin);
        _grantRole(Const.SAPIEN_QA_ROLE, sapienQA);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);

        sapienToken = IERC20(token);
        multiplier = IMultiplier(newMultiplierContract);
        treasury = newTreasury;
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
     * @notice Updates the Safe address for penalty collection.
     * @param newTreasury The new Reward Safe address.
     */
    function setTreasury(address newTreasury) external onlyAdmin {
        if (newTreasury == address(0)) {
            revert ZeroAddress();
        }

        treasury = newTreasury;
        emit SapienTreasuryUpdated(newTreasury);
    }

    /**
     * @notice Sets the multiplier contract address.
     * @param newMultiplierContract The new Multiplier contract address.
     */
    function setMultiplierContract(address newMultiplierContract) external onlyAdmin {
        if (newMultiplierContract == address(0)) {
            revert ZeroAddress();
        }

        multiplier = IMultiplier(newMultiplierContract);
        emit MultiplierUpdated(0, 0); // Emit with zero values to indicate contract update
    }

    /**
     * @notice Emergency withdrawal function for admin use only in critical situations
     * @param token The token to withdraw (use address(0) for ETH)
     * @param to The address to withdraw to
     * @param amount The amount to withdraw
     * @dev This function should only be used in emergency situations where contract is compromised
     */
    function emergencyWithdraw(address token, address to, uint256 amount) external onlyAdmin whenPaused {
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
     * @notice getUserStakingSummary for comprehensive staking summary for a user's position
     * @dev This is the primary function for retrieving all relevant staking information
     * for a user in a single call. It aggregates data from multiple internal functions
     * to provide a complete picture of the user's staking status.
     *
     * RETURN VALUES EXPLAINED:
     * - userTotalStaked: Total tokens the user has staked (including locked and unlocked)
     * - totalUnlocked: Tokens that have completed lockup and can be queued for unstaking
     * - totalLocked: Tokens still in their lockup period that cannot be unstaked yet
     * - totalInCooldown: Tokens queued for unstaking but still in cooldown period
     * - totalReadyForUnstake: Tokens that completed cooldown and can be withdrawn immediately
     * - effectiveMultiplier: Current multiplier applied to this user's stake for rewards
     * - effectiveLockUpPeriod: Weighted average lockup period for the user's position
     * - timeUntilUnlock: Seconds remaining until the stake becomes unlocked (0 if already unlocked)
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
     *
     * @param user The address of the user to query
     * @return userTotalStaked Total amount staked by the user
     * @return totalUnlocked Amount available for unstaking initiation
     * @return totalLocked Amount still in lockup period
     * @return totalInCooldown Amount currently in unstaking cooldown
     * @return totalReadyForUnstake Amount ready for immediate withdrawal
     * @return effectiveMultiplier Current multiplier for rewards (basis points)
     * @return effectiveLockUpPeriod Weighted average lockup period (seconds)
     * @return timeUntilUnlock Time remaining until unlock (seconds, 0 if unlocked)
     */
    function getUserStakingSummary(address user)
        public
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
        )
    {
        UserStake memory userStake = userStakes[user];

        userTotalStaked = uint256(userStake.amount);
        totalUnlocked = getTotalUnlocked(user);
        totalLocked = getTotalLocked(user);
        totalInCooldown = getTotalInCooldown(user);
        totalReadyForUnstake = getTotalReadyForUnstake(user);
        effectiveMultiplier = uint256(userStake.effectiveMultiplier);
        effectiveLockUpPeriod = uint256(userStake.effectiveLockUpPeriod);

        if (userStake.hasStake) {
            uint256 unlockTime = uint256(userStake.weightedStartTime) + uint256(userStake.effectiveLockUpPeriod);
            timeUntilUnlock = block.timestamp >= unlockTime ? 0 : unlockTime - block.timestamp;
        }
    }

    // -------------------------------------------------------------
    // Multiplier Calculation Helpers
    // -------------------------------------------------------------

    /**
     * @notice calculateMultiplier for a stake position using the multiplier contract
     * @dev This is a core function that determines the reward multiplier applied to a user's stake.
     * The multiplier affects how much weight this stake carries in the reputation system and
     * potentially in reward distribution calculations.
     *
     * BUSINESS CONTEXT:
     * - Multipliers incentivize longer commitments and larger stakes
     * - They create a dynamic system where early adopters and committed stakers get higher rewards
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
     * @param effectiveLockup The weighted average lockup period for this position
     * @return uint256 calculated effective multiplier
     */
    function calculateMultiplier(uint256 amount, uint256 effectiveLockup) public view returns (uint256) {
        return multiplier.calculateMultiplier(amount, effectiveLockup);
    }

    /**
     * @notice Check if user has an active stake
     * @param user The user address
     * @return Whether the user has an active stake
     */
    function hasActiveStake(address user) external view returns (bool) {
        return userStakes[user].hasStake;
    }

    /**
     * @notice Returns the total amount of tokens staked by a user
     * @param user The address of the user to check
     * @return The total amount of tokens staked by the user
     */
    function getTotalStaked(address user) public view returns (uint256) {
        return uint256(userStakes[user].amount);
    }

    /**
     * @notice Returns the amount of tokens that are unlocked and available for unstaking
     * @dev This excludes tokens that are in cooldown
     * @param user The address of the user to check
     * @return The amount of unlocked tokens available for unstaking
     */
    function getTotalUnlocked(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (!_isUnlocked(userStake)) return 0;
        return uint256(userStake.amount) > uint256(userStake.cooldownAmount)
            ? uint256(userStake.amount) - uint256(userStake.cooldownAmount)
            : 0;
    }

    /**
     * @notice Returns the amount of tokens that are still locked and cannot be unstaked
     * @dev Returns 0 if tokens are unlocked or in cooldown
     * @param user The address of the user to check
     * @return The amount of tokens still locked
     */
    function getTotalLocked(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (_isUnlocked(userStake) || uint256(userStake.cooldownAmount) > 0) return 0;
        return uint256(userStake.amount);
    }

    /**
     * @notice Returns the amount of tokens that have completed cooldown and are ready to be unstaked
     * @dev Returns 0 if tokens are not ready for unstaking
     * @param user The address of the user to check
     * @return The amount of tokens ready for unstaking
     */
    function getTotalReadyForUnstake(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (!_isReadyForUnstake(userStake)) return 0;
        return uint256(userStake.cooldownAmount);
    }

    /**
     * @notice Returns the amount of tokens currently in cooldown period
     * @dev Returns 0 if user has no stake or is not in cooldown
     * @param user The address of the user to check
     * @return The amount of tokens in cooldown
     */
    function getTotalInCooldown(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        return (userStake.hasStake && uint256(userStake.cooldownStart) > 0) ? uint256(userStake.cooldownAmount) : 0;
    }

    // -------------------------------------------------------------
    //  Stake Management
    // -------------------------------------------------------------

    /**
     * @notice Stake a specified `amount` of tokens for a given `lockUpPeriod`.
     * @param amount The amount of tokens to stake.
     * @param lockUpPeriod The lock-up duration in seconds (30/90/180/365 days).
     */
    function stake(uint256 amount, uint256 lockUpPeriod) public whenNotPaused nonReentrant {
        // Validate caller is not zero address
        if (msg.sender == address(0)) {
            revert ZeroAddress();
        }

        // Validate inputs and user state
        _validateStakeInputs(amount, lockUpPeriod);

        UserStake storage userStake = userStakes[msg.sender];

        // Pre-validate state changes before token transfer
        _preValidateStakeOperation(userStake);

        // Transfer tokens only after all validations pass
        sapienToken.safeTransferFrom(msg.sender, address(this), amount);

        // Execute staking logic
        if (!userStake.hasStake) {
            _processFirstTimeStake(userStake, amount, lockUpPeriod);
        } else {
            _processCombineStake(userStake, amount, lockUpPeriod);
        }

        totalStaked += amount;
        emit Staked(msg.sender, amount, userStake.effectiveMultiplier, userStake.effectiveLockUpPeriod);
    }

    /**
     * @notice Increase the staked amount without changing lockup period.
     * @param additionalAmount The additional amount to stake.
     */
    function increaseAmount(uint256 additionalAmount) public whenNotPaused nonReentrant {
        // Validate inputs
        _validateIncreaseAmount(additionalAmount);

        UserStake storage userStake = userStakes[msg.sender];

        if (!userStake.hasStake) {
            revert NoStakeFound();
        }

        if (userStake.cooldownStart != 0) {
            revert CannotIncreaseStakeInCooldown();
        }

        // Validate weighted calculation won't overflow
        uint256 existingWeight = uint256(userStake.weightedStartTime) * uint256(userStake.amount);
        uint256 newWeight = block.timestamp * additionalAmount;
        if (existingWeight > type(uint256).max - newWeight) {
            revert StakeAmountTooLarge();
        }

        // Transfer tokens only after validation passes
        sapienToken.safeTransferFrom(msg.sender, address(this), additionalAmount);

        // Pre-validate before token transfer
        uint256 newTotalAmount = uint256(userStake.amount) + additionalAmount;

        // Calculate new weighted start time with precision handling
        uint256 newWeightedStartTime = _calculateWeightedStartTime(
            uint256(userStake.weightedStartTime), uint256(userStake.amount), additionalAmount, newTotalAmount
        );

        // Update state
        userStake.weightedStartTime = newWeightedStartTime.toUint64();
        userStake.amount = newTotalAmount.toUint128();
        userStake.lastUpdateTime = block.timestamp.toUint64();

        // Recalculate linear weighted multiplier based on new total amount
        userStake.effectiveMultiplier =
            calculateMultiplier(newTotalAmount, uint256(userStake.effectiveLockUpPeriod)).toUint32();

        totalStaked += additionalAmount;

        emit AmountIncreased(msg.sender, additionalAmount, newTotalAmount, userStake.effectiveMultiplier);
    }

    /**
     * @notice Increase the lockup period for existing stake.
     * @param additionalLockup The additional lockup time in seconds.
     */
    function increaseLockup(uint256 additionalLockup) public whenNotPaused nonReentrant {
        if (additionalLockup < Const.MINIMUM_LOCKUP_INCREASE) {
            revert MinimumLockupIncreaseRequired();
        }

        UserStake storage userStake = userStakes[msg.sender];
        if (!userStake.hasStake) {
            revert NoStakeFound();
        }
        if (userStake.cooldownStart != 0) {
            revert CannotIncreaseStakeInCooldown();
        }

        // Calculate remaining lockup time
        uint256 timeElapsed = block.timestamp - uint256(userStake.weightedStartTime);
        uint256 remainingLockup = uint256(userStake.effectiveLockUpPeriod) > timeElapsed
            ? uint256(userStake.effectiveLockUpPeriod) - timeElapsed
            : 0;

        // New effective lockup is remaining time plus additional lockup
        uint256 newEffectiveLockup = remainingLockup + additionalLockup;

        // Cap at maximum lockup period
        if (newEffectiveLockup > Const.LOCKUP_365_DAYS) {
            newEffectiveLockup = Const.LOCKUP_365_DAYS;
        }

        userStake.effectiveLockUpPeriod = newEffectiveLockup.toUint64();
        userStake.effectiveMultiplier = calculateMultiplier(uint256(userStake.amount), newEffectiveLockup).toUint32();

        // Reset the weighted start time to now since we're extending lockup
        userStake.weightedStartTime = block.timestamp.toUint64();
        userStake.lastUpdateTime = block.timestamp.toUint64();

        emit LockupIncreased(msg.sender, additionalLockup, newEffectiveLockup, userStake.effectiveMultiplier);
    }

    /**
     * @notice Initiates the cooldown for unstaking.
     * @param amount The amount intended for unstaking.
     */
    function initiateUnstake(uint256 amount) public whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();

        UserStake storage userStake = userStakes[msg.sender];

        if (!userStake.hasStake) {
            revert NoStakeFound();
        }

        if (!_isUnlocked(userStake)) {
            revert StakeStillLocked();
        }

        if (amount > uint256(userStake.amount) - uint256(userStake.cooldownAmount)) {
            revert AmountExceedsAvailableBalance();
        }

        // Set cooldown start time only if not already in cooldown
        if (uint256(userStake.cooldownStart) == 0) {
            userStake.cooldownStart = block.timestamp.toUint64();
        }

        uint256 newCooldownAmount = uint256(userStake.cooldownAmount) + amount;

        userStake.cooldownAmount = newCooldownAmount.toUint128();
        emit UnstakingInitiated(msg.sender, amount);
    }

    /**
     * @notice Completes the unstaking process after the cooldown period has passed.
     * @param amount The amount to unstake.
     */
    function unstake(uint256 amount) public whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();

        UserStake storage userStake = userStakes[msg.sender];

        if (!userStake.hasStake) {
            revert NoStakeFound();
        }

        if (!_isReadyForUnstake(userStake)) {
            revert NotReadyForUnstake();
        }

        if (amount > uint256(userStake.cooldownAmount)) {
            revert AmountExceedsCooldownAmount();
        }

        userStake.amount -= amount.toUint128();
        userStake.cooldownAmount -= amount.toUint128();
        totalStaked -= amount;

        // Clear cooldown if no more amount in cooldown
        if (uint256(userStake.cooldownAmount) == 0) {
            userStake.cooldownStart = 0;
        }

        // Complete state reset if stake is fully withdrawn
        if (uint256(userStake.amount) == 0) {
            _resetUserStake(userStake);
        }

        sapienToken.safeTransfer(msg.sender, amount);
        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice  Unstakes early a specified amount, incurring a penalty.
     * @param amount The amount to unstake instantly.
     */
    function earlyUnstake(uint256 amount) public whenNotPaused nonReentrant {
        if (amount == 0) revert InvalidAmount();

        UserStake storage userStake = userStakes[msg.sender];

        if (!userStake.hasStake) {
            revert NoStakeFound();
        }

        if (amount > uint256(userStake.amount) - uint256(userStake.cooldownAmount)) {
            revert AmountExceedsAvailableBalance();
        }

        // Add check to ensure instant unstake is only possible during lock period
        if (_isUnlocked(userStake)) {
            revert LockPeriodCompleted();
        }

        uint256 penalty = (amount * Const.EARLY_WITHDRAWAL_PENALTY) / 100;

        uint256 payout = amount - penalty;

        userStake.amount -= amount.toUint128();
        totalStaked -= amount;

        // Complete state reset if stake is fully withdrawn
        if (uint256(userStake.amount) == 0) {
            _resetUserStake(userStake);
        }

        sapienToken.safeTransfer(msg.sender, payout);

        if (penalty > 0) {
            sapienToken.safeTransfer(treasury, penalty);
        }

        emit EarlyUnstake(msg.sender, payout, penalty);
    }

    /**
     * @notice Validates stake inputs and basic constraints
     * @param amount The amount to stake
     * @param lockUpPeriod The lockup period
     */
    function _validateStakeInputs(uint256 amount, uint256 lockUpPeriod) private pure {
        if (amount < Const.MINIMUM_STAKE_AMOUNT) {
            revert MinimumStakeAmountRequired();
        }

        if (amount > 10_000_000 * Const.TOKEN_DECIMALS) {
            revert StakeAmountTooLarge();
        }

        if (!isValidLockUpPeriod(lockUpPeriod)) {
            revert InvalidLockupPeriod();
        }
    }

    /**
     * @notice Pre-validates state operations before token transfer
     * @param userStake The user's stake data
     */
    function _preValidateStakeOperation(UserStake storage userStake) private view {
        // Prevent staking while in cooldown
        if (userStake.hasStake && userStake.cooldownStart != 0) {
            revert CannotIncreaseStakeInCooldown();
        }
    }

    /**
     * @notice Processes first-time stake for a user
     * @param userStake The user's stake storage reference
     * @param amount The amount to stake
     * @param lockUpPeriod The lockup period
     */
    function _processFirstTimeStake(UserStake storage userStake, uint256 amount, uint256 lockUpPeriod) private {
        userStake.amount = amount.toUint128();
        userStake.weightedStartTime = block.timestamp.toUint64();
        userStake.effectiveLockUpPeriod = lockUpPeriod.toUint64();
        userStake.effectiveMultiplier = calculateMultiplier(amount, lockUpPeriod).toUint32();
        userStake.lastUpdateTime = block.timestamp.toUint64();
        userStake.hasStake = true;
    }

    /**
     * @notice Processes combining new stake with existing stake
     * @param userStake The user's stake storage reference
     * @param amount The amount to add
     * @param lockUpPeriod The new lockup period
     */
    function _processCombineStake(UserStake storage userStake, uint256 amount, uint256 lockUpPeriod) private {
        uint256 newTotalAmount = uint256(userStake.amount) + amount;

        // Calculate new weighted values
        WeightedValues memory newValues = _calculateWeightedValues(userStake, amount, lockUpPeriod, newTotalAmount);

        // Update stake with new values
        userStake.amount = newTotalAmount.toUint128();
        userStake.weightedStartTime = newValues.weightedStartTime.toUint64();
        userStake.effectiveLockUpPeriod = newValues.effectiveLockup.toUint64();
        userStake.effectiveMultiplier = calculateMultiplier(newTotalAmount, newValues.effectiveLockup).toUint32();
        userStake.lastUpdateTime = block.timestamp.toUint64();
    }

    /**
     * @notice Calculates weighted values when combining existing and new stakes
     * @dev Refactored into smaller functions for better auditability
     * @param userStake The current user stake storage reference
     * @param amount The new amount being added
     * @param lockUpPeriod The lockup period for the new amount
     * @param newTotalAmount The total amount after addition (existing + new)
     * @return newValues Struct containing the calculated weighted start time and lockup period
     */
    function _calculateWeightedValues(
        UserStake storage userStake,
        uint256 amount,
        uint256 lockUpPeriod,
        uint256 newTotalAmount
    ) private view returns (WeightedValues memory newValues) {
        // Input validation
        if (amount == 0) revert AmountMustBePositive();
        if (newTotalAmount == 0) revert TotalAmountMustBePositive();
        if (lockUpPeriod < Const.LOCKUP_30_DAYS || lockUpPeriod > Const.LOCKUP_365_DAYS) {
            revert InvalidLockupPeriod();
        }

        // Calculate weighted start time
        newValues.weightedStartTime = _calculateWeightedStartTimeValue(
            uint256(userStake.weightedStartTime), uint256(userStake.amount), amount, newTotalAmount
        );

        // Calculate weighted lockup period
        newValues.effectiveLockup = _calculateWeightedLockupPeriod(
            uint256(userStake.effectiveLockUpPeriod), uint256(userStake.amount), lockUpPeriod, amount, newTotalAmount
        );

        // Ensure lockup period doesn't exceed maximum
        if (newValues.effectiveLockup > Const.LOCKUP_365_DAYS) {
            newValues.effectiveLockup = Const.LOCKUP_365_DAYS;
        }
    }

    /**
     * @notice Calculates weighted start time for combining stakes
     * @dev Formula: (existingAmount * existingStartTime + newAmount * currentTime) / totalAmount
     * @param existingStartTime The current weighted start time
     * @param existingAmount The current stake amount
     * @param newAmount The new amount being added
     * @param totalAmount The total amount after addition
     * @return weightedStartTime The calculated weighted start time
     */
    function _calculateWeightedStartTimeValue(
        uint256 existingStartTime,
        uint256 existingAmount,
        uint256 newAmount,
        uint256 totalAmount
    ) private view returns (uint256 weightedStartTime) {
        // Check for overflow before multiplication
        if (existingAmount != 0 && existingStartTime > type(uint256).max / existingAmount) {
            revert WeightedCalculationOverflow();
        }
        if (newAmount != 0 && block.timestamp > type(uint256).max / newAmount) {
            revert WeightedCalculationOverflow();
        }

        uint256 existingWeight = existingStartTime * existingAmount;
        uint256 newWeight = block.timestamp * newAmount;

        // Check for overflow in addition
        if (existingWeight > type(uint256).max - newWeight) {
            revert WeightedCalculationOverflow();
        }

        uint256 totalWeight = existingWeight + newWeight;
        weightedStartTime = totalWeight / totalAmount;

        // Apply banker's rounding: round up if remainder > 50%
        uint256 remainder = totalWeight % totalAmount;
        if (remainder > totalAmount / 2) {
            weightedStartTime += 1;
        }
    }

    /**
     * @notice Calculates weighted lockup period for combining stakes
     * @dev Formula: (existingAmount * existingLockup + newAmount * newLockup) / totalAmount
     * @param existingLockupPeriod The current effective lockup period
     * @param existingAmount The current stake amount
     * @param newLockupPeriod The lockup period for the new amount
     * @param newAmount The new amount being added
     * @param totalAmount The total amount after addition
     * @return weightedLockup The calculated weighted lockup period
     */
    function _calculateWeightedLockupPeriod(
        uint256 existingLockupPeriod,
        uint256 existingAmount,
        uint256 newLockupPeriod,
        uint256 newAmount,
        uint256 totalAmount
    ) private pure returns (uint256 weightedLockup) {
        // Check for overflow before multiplication
        if (existingAmount != 0 && existingLockupPeriod > type(uint256).max / existingAmount) {
            revert LockupWeightCalculationOverflow();
        }
        if (newAmount != 0 && newLockupPeriod > type(uint256).max / newAmount) {
            revert LockupWeightCalculationOverflow();
        }

        uint256 existingLockupWeight = existingLockupPeriod * existingAmount;
        uint256 newLockupWeight = newLockupPeriod * newAmount;

        // Check for overflow in addition
        if (existingLockupWeight > type(uint256).max - newLockupWeight) {
            revert LockupWeightCalculationOverflow();
        }

        uint256 totalLockupWeight = existingLockupWeight + newLockupWeight;
        weightedLockup = totalLockupWeight / totalAmount;

        // Apply banker's rounding: round up if remainder > 50%
        uint256 remainder = totalLockupWeight % totalAmount;
        if (remainder > totalAmount / 2) {
            weightedLockup += 1;
        }
    }

    // -------------------------------------------------------------
    // Helper Functions
    // -------------------------------------------------------------

    function _isUnlocked(UserStake memory userStake) private view returns (bool) {
        return userStake.hasStake
            && block.timestamp >= uint256(userStake.weightedStartTime) + uint256(userStake.effectiveLockUpPeriod);
    }

    function _isReadyForUnstake(UserStake memory userStake) private view returns (bool) {
        return userStake.hasStake && uint256(userStake.cooldownStart) > 0
            && block.timestamp >= uint256(userStake.cooldownStart) + Const.COOLDOWN_PERIOD
            && uint256(userStake.cooldownAmount) > 0;
    }

    /**
     * @notice Validates if a lockup period is valid
     * @param lockUpPeriod The lockup period to validate
     * @return bool True if the lockup period is valid
     */
    function isValidLockUpPeriod(uint256 lockUpPeriod) public pure returns (bool) {
        return lockUpPeriod >= Const.LOCKUP_30_DAYS && lockUpPeriod <= Const.LOCKUP_365_DAYS;
    }

    /**
     * @notice Validates amount for increase operations
     * @param additionalAmount The amount to validate
     */
    function _validateIncreaseAmount(uint256 additionalAmount) private pure {
        if (additionalAmount == 0) {
            revert InvalidAmount();
        }

        // Prevent potential DOS attacks with extremely large stakes
        if (additionalAmount > 10_000_000 * Const.TOKEN_DECIMALS) {
            revert StakeAmountTooLarge();
        }
    }

    /**
     * @notice Calculates weighted start time with precision handling
     * @dev Refactored for consistency and better overflow protection
     * @param currentStartTime Current weighted start time
     * @param currentAmount Current stake amount
     * @param newAmount Additional amount being added
     * @param totalAmount Total amount after addition
     * @return newWeightedStartTime The calculated weighted start time
     */
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

        // Use the refactored helper function for consistency
        return _calculateWeightedStartTimeValue(currentStartTime, currentAmount, newAmount, totalAmount);
    }

    /**
     * @notice Resets user stake to zero state
     * @param userStake The user stake to reset
     */
    function _resetUserStake(UserStake storage userStake) private {
        userStake.hasStake = false;
        userStake.amount = 0;
        userStake.cooldownAmount = 0;
        userStake.weightedStartTime = 0;
        userStake.effectiveLockUpPeriod = 0;
        userStake.effectiveMultiplier = 0;
        userStake.lastUpdateTime = 0;
        userStake.cooldownStart = 0;
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

        // Emit event if penalty was reduced due to insufficient stake
        if (actualPenalty < penaltyAmount) {
            emit QAPenaltyPartial(userAddress, penaltyAmount, actualPenalty);
        }

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
        uint256 totalAvailable = uint256(userStake.amount) + uint256(userStake.cooldownAmount);
        return requestedPenalty > totalAvailable ? totalAvailable : requestedPenalty;
    }

    /**
     * @dev Apply penalty by reducing stake amounts in priority order (active stake first, then cooldown)
     */
    function _applyPenaltyToUserStake(UserStake storage userStake, uint256 penaltyAmount, address userAddress)
        internal
    {
        uint256 remainingPenalty = penaltyAmount;

        // Take from active stake first
        uint256 fromActiveStake = _reducePrimaryStake(userStake, remainingPenalty);
        remainingPenalty -= fromActiveStake;

        // Take from cooldown if needed
        uint256 fromCooldownStake = 0;
        if (remainingPenalty > 0) {
            fromCooldownStake = _reduceCooldownStake(userStake, remainingPenalty);
        }

        // Emit detailed breakdown of where penalty was taken from
        if (fromActiveStake > 0 || fromCooldownStake > 0) {
            emit QAStakeReduced(userAddress, fromActiveStake, fromCooldownStake);
        }
    }

    /**
     * @dev Reduce active stake amount and update total staked tracking
     */
    function _reducePrimaryStake(UserStake storage userStake, uint256 maxReduction)
        internal
        returns (uint256 actualReduction)
    {
        uint256 availableStake = uint256(userStake.amount);
        if (availableStake == 0) return 0;

        actualReduction = maxReduction > availableStake ? availableStake : maxReduction;
        userStake.amount = (availableStake - actualReduction).toUint128();
        totalStaked -= actualReduction;
    }

    /**
     * @dev Reduce cooldown stake amount
     */
    function _reduceCooldownStake(UserStake storage userStake, uint256 reductionAmount)
        internal
        returns (uint256 actualReduction)
    {
        uint256 availableCooldown = uint256(userStake.cooldownAmount);
        actualReduction = reductionAmount > availableCooldown ? availableCooldown : reductionAmount;
        userStake.cooldownAmount = (availableCooldown - actualReduction).toUint128();
    }

    /**
     * @dev Update user stake state after penalty application (reset if empty, recalculate multiplier if not)
     */
    function _updateUserStakeAfterPenalty(UserStake storage userStake, address userAddress) internal {
        bool _hasActiveStake = userStake.amount > 0;
        bool _hasCooldownStake = userStake.cooldownAmount > 0;

        if (!_hasActiveStake && !_hasCooldownStake) {
            _resetUserStake(userStake);
            emit QAUserStakeReset(userAddress);
            return;
        }

        // Recalculate multiplier for remaining active stake
        if (_hasActiveStake) {
            userStake.effectiveMultiplier = multiplier.calculateMultiplier(
                uint256(userStake.amount), uint256(userStake.effectiveLockUpPeriod)
            ).toUint32();
        }

        userStake.lastUpdateTime = block.timestamp.toUint64();
    }
}
