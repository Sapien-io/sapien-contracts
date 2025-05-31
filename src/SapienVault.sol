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

using SafeCast for uint256;

/// @title SapienVault - Sapien AI Staking Vault
/// @notice Sapien protocol reputation system with simplified single stake per user.
contract SapienVault is ISapienVault, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    /// @dev The Sapien token interface for staking/unstaking (IERC20).
    IERC20 public sapienToken;

    /// @dev Address of the Rewards Safe
    address public rewardSafe;

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
     * @param newRewardsSafe The address of the Rewards Safe multisig for penalty collection.
     */
    function initialize(address token, address admin, address newRewardsSafe) public initializer {
        if (token == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();
        if (newRewardsSafe == address(0)) revert ZeroAddress();

        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(Const.PAUSER_ROLE, admin);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);

        sapienToken = IERC20(token);
        rewardSafe = newRewardsSafe;
    }

    // -------------------------------------------------------------
    // Access Control Modifiers
    // -------------------------------------------------------------

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert NotAdmin();
        }
        _;
    }

    modifier onlyPauser() {
        if (!hasRole(Const.PAUSER_ROLE, msg.sender)) {
            revert NotPauser();
        }
        _;
    }

    // -------------------------------------------------------------
    // Role-Based Functions
    // -------------------------------------------------------------

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
     * @param newRewardSafe The new Reward Safe address.
     */
    function setRewardSafe(address newRewardSafe) external onlyAdmin {
        if (newRewardSafe == address(0)) {
            revert ZeroAddress();
        }

        rewardSafe = newRewardSafe;
        emit SapienTreasuryUpdated(newRewardSafe);
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
        uint256 baseMultiplier = _getMultiplierForPeriod(lockUpPeriod);

        // Pre-validate state changes before token transfer
        _preValidateStakeOperation(userStake, amount, lockUpPeriod);

        // Transfer tokens only after all validations pass
        sapienToken.safeTransferFrom(msg.sender, address(this), amount);

        // Execute staking logic
        if (!userStake.hasStake) {
            _processFirstTimeStake(userStake, amount, lockUpPeriod, baseMultiplier);
        } else {
            _processCombineStake(userStake, amount, lockUpPeriod);
        }

        totalStaked += amount;
        emit Staked(msg.sender, amount, userStake.effectiveMultiplier, userStake.effectiveLockUpPeriod);
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

        // Prevent potential DOS attacks with extremely large stakes
        if (amount > 10_000_000 * Const.TOKEN_DECIMALS) {
            revert StakeAmountTooLarge();
        }

        if (_getMultiplierForPeriod(lockUpPeriod) == 0) {
            revert InvalidLockupPeriod();
        }
    }

    /**
     * @notice Pre-validates state operations before token transfer
     * @param userStake The user's stake data
     * @param amount The amount to stake
     * @param lockUpPeriod The lockup period
     */
    function _preValidateStakeOperation(UserStake storage userStake, uint256 amount, uint256 lockUpPeriod)
        private
        view
    {
        // Prevent staking while in cooldown
        if (userStake.hasStake && userStake.cooldownStart != 0) {
            revert CannotIncreaseStakeInCooldown();
        }

        // For existing stakes, validate weighted calculations won't overflow
        if (userStake.hasStake) {
            _validateWeightedCalculations(userStake, amount, lockUpPeriod);
        }
    }

    /**
     * @notice Validates that weighted calculations won't overflow
     * @param userStake The user's current stake
     * @param amount The new amount to add
     * @param lockUpPeriod The new lockup period
     */
    function _validateWeightedCalculations(UserStake storage userStake, uint256 amount, uint256 lockUpPeriod)
        private
        view
    {
        uint256 newTotalAmount = uint256(userStake.amount) + amount;
        if (newTotalAmount > type(uint128).max) {
            revert StakeAmountTooLarge();
        }

        // Check weighted start time calculation overflow
        uint256 existingWeight = uint256(userStake.weightedStartTime) * uint256(userStake.amount);
        uint256 newWeight = block.timestamp * amount;
        if (existingWeight > type(uint256).max - newWeight) {
            revert StakeAmountTooLarge();
        }

        // Check weighted lockup calculation overflow
        uint256 existingLockupWeight = uint256(userStake.effectiveLockUpPeriod) * uint256(userStake.amount);
        uint256 newLockupWeight = lockUpPeriod * amount;
        if (existingLockupWeight > type(uint256).max - newLockupWeight) {
            revert StakeAmountTooLarge();
        }
    }

    /**
     * @notice Processes first-time stake for a user
     * @param userStake The user's stake storage reference
     * @param amount The amount to stake
     * @param lockUpPeriod The lockup period
     * @param baseMultiplier The calculated multiplier
     */
    function _processFirstTimeStake(
        UserStake storage userStake,
        uint256 amount,
        uint256 lockUpPeriod,
        uint256 baseMultiplier
    ) private {
        userStake.amount = amount.toUint128();
        userStake.weightedStartTime = block.timestamp.toUint64();
        userStake.effectiveLockUpPeriod = lockUpPeriod.toUint64();
        userStake.effectiveMultiplier = baseMultiplier.toUint32();
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
        userStake.effectiveMultiplier = _calculateEffectiveMultiplier(newValues.effectiveLockup).toUint32();
        userStake.lastUpdateTime = block.timestamp.toUint64();
    }

    /**
     * @notice Calculates weighted values with precision handling
     * @param userStake The current user stake
     * @param amount The new amount
     * @param lockUpPeriod The new lockup period
     * @param newTotalAmount The total amount after addition
     * @return newValues The calculated weighted values
     */
    function _calculateWeightedValues(
        UserStake storage userStake,
        uint256 amount,
        uint256 lockUpPeriod,
        uint256 newTotalAmount
    ) private view returns (WeightedValues memory newValues) {
        // Calculate weighted start time with precision handling
        uint256 existingWeight = uint256(userStake.weightedStartTime) * uint256(userStake.amount);
        uint256 newWeight = block.timestamp * amount;
        newValues.weightedStartTime = (existingWeight + newWeight) / newTotalAmount;

        // Apply precision rounding for start time
        uint256 startTimePrecision = (existingWeight + newWeight) % newTotalAmount;
        if (startTimePrecision > newTotalAmount / 2) {
            newValues.weightedStartTime += 1;
        }

        // Calculate weighted lockup period with precision handling
        uint256 existingLockupWeight = uint256(userStake.effectiveLockUpPeriod) * uint256(userStake.amount);
        uint256 newLockupWeight = lockUpPeriod * amount;
        newValues.effectiveLockup = (existingLockupWeight + newLockupWeight) / newTotalAmount;

        // Apply precision rounding for lockup
        uint256 lockupPrecision = (existingLockupWeight + newLockupWeight) % newTotalAmount;
        if (lockupPrecision > newTotalAmount / 2) {
            newValues.effectiveLockup += 1;
        }

        // Ensure lockup period doesn't exceed maximum
        if (newValues.effectiveLockup > Const.LOCKUP_365_DAYS) {
            newValues.effectiveLockup = Const.LOCKUP_365_DAYS;
        }
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

        // Pre-validate before token transfer
        uint256 newTotalAmount = uint256(userStake.amount) + additionalAmount;
        if (newTotalAmount > type(uint128).max) {
            revert StakeAmountTooLarge();
        }

        // Validate weighted calculation won't overflow
        uint256 existingWeight = uint256(userStake.weightedStartTime) * uint256(userStake.amount);
        uint256 newWeight = block.timestamp * additionalAmount;
        if (existingWeight > type(uint256).max - newWeight) {
            revert StakeAmountTooLarge();
        }

        // Transfer tokens only after validation passes
        sapienToken.safeTransferFrom(msg.sender, address(this), additionalAmount);

        // Calculate new weighted start time with precision handling
        uint256 newWeightedStartTime = _calculateWeightedStartTime(
            uint256(userStake.weightedStartTime), uint256(userStake.amount), additionalAmount, newTotalAmount
        );

        // Update state
        userStake.weightedStartTime = newWeightedStartTime.toUint64();
        userStake.amount = newTotalAmount.toUint128();
        userStake.lastUpdateTime = block.timestamp.toUint64();

        // Effective multiplier stays the same since lockup period doesn't change
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
        userStake.effectiveMultiplier = _calculateEffectiveMultiplier(newEffectiveLockup).toUint32();

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
        if (newCooldownAmount > type(uint128).max) {
            revert StakeAmountTooLarge();
        }

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
     * @notice Instantly unstakes a specified `amount`, incurring a penalty.
     * @param amount The amount to unstake instantly.
     */
    function instantUnstake(uint256 amount) public whenNotPaused nonReentrant {
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

        // Calculate penalty with bounds checking
        if (Const.EARLY_WITHDRAWAL_PENALTY > 100) {
            revert InvalidAmount(); // Prevent penalty > 100%
        }

        uint256 penalty = (amount * Const.EARLY_WITHDRAWAL_PENALTY) / 100;
        if (penalty >= amount) {
            revert InvalidAmount(); // Ensure payout is always positive
        }

        uint256 payout = amount - penalty;

        userStake.amount -= amount.toUint128();
        totalStaked -= amount;

        // Complete state reset if stake is fully withdrawn
        if (uint256(userStake.amount) == 0) {
            _resetUserStake(userStake);
        }

        sapienToken.safeTransfer(msg.sender, payout);
        if (penalty > 0) {
            sapienToken.safeTransfer(rewardSafe, penalty);
        }

        emit InstantUnstake(msg.sender, payout, penalty);
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
     * @notice Calculate effective multiplier based on lockup period using interpolation.
     * @param effectiveLockup The effective lockup period.
     * @return The calculated multiplier.
     */
    function _calculateEffectiveMultiplier(uint256 effectiveLockup) private pure returns (uint256) {
        if (effectiveLockup >= Const.LOCKUP_365_DAYS) {
            return Const.MAX_MULTIPLIER; // 15000 (1.50x)
        } else if (effectiveLockup >= Const.LOCKUP_180_DAYS) {
            // Linear interpolation between 180 days and 365 days
            uint256 denominator = Const.LOCKUP_365_DAYS - Const.LOCKUP_180_DAYS;
            if (denominator == 0) return Const.MULTIPLIER_180_DAYS; // Safety check

            uint256 ratio = (effectiveLockup - Const.LOCKUP_180_DAYS) * 10000 / denominator;
            return Const.MULTIPLIER_180_DAYS + ((Const.MAX_MULTIPLIER - Const.MULTIPLIER_180_DAYS) * ratio / 10000);
        } else if (effectiveLockup >= Const.LOCKUP_90_DAYS) {
            // Linear interpolation between 90 days and 180 days
            uint256 denominator = Const.LOCKUP_180_DAYS - Const.LOCKUP_90_DAYS;
            if (denominator == 0) return Const.MULTIPLIER_90_DAYS; // Safety check

            uint256 ratio = (effectiveLockup - Const.LOCKUP_90_DAYS) * 10000 / denominator;
            return Const.MULTIPLIER_90_DAYS + ((Const.MULTIPLIER_180_DAYS - Const.MULTIPLIER_90_DAYS) * ratio / 10000);
        } else if (effectiveLockup >= Const.LOCKUP_30_DAYS) {
            // Linear interpolation between 30 days and 90 days
            uint256 denominator = Const.LOCKUP_90_DAYS - Const.LOCKUP_30_DAYS;
            if (denominator == 0) return Const.MIN_MULTIPLIER; // Safety check

            uint256 ratio = (effectiveLockup - Const.LOCKUP_30_DAYS) * 10000 / denominator;
            return Const.MIN_MULTIPLIER + ((Const.MULTIPLIER_90_DAYS - Const.MIN_MULTIPLIER) * ratio / 10000);
        } else {
            // Less than 30 days, use base multiplier of 1.0x (10000)
            return Const.BASE_MULTIPLIER;
        }
    }

    /**
     * @notice Get base multiplier for a specific lock-up period
     * @param lockUpPeriod The lock-up period in seconds
     * @return multiplier The base multiplier for the period
     */
    function _getMultiplierForPeriod(uint256 lockUpPeriod) private pure returns (uint256 multiplier) {
        if (lockUpPeriod == Const.LOCKUP_30_DAYS) {
            return Const.MIN_MULTIPLIER; // 10500 (1.05x)
        } else if (lockUpPeriod == Const.LOCKUP_90_DAYS) {
            return Const.MULTIPLIER_90_DAYS; // 11000 (1.10x)
        } else if (lockUpPeriod == Const.LOCKUP_180_DAYS) {
            return Const.MULTIPLIER_180_DAYS; // 12500 (1.25x)
        } else if (lockUpPeriod == Const.LOCKUP_365_DAYS) {
            return Const.MAX_MULTIPLIER; // 15000 (1.50x)
        } else {
            return 0; // Invalid period
        }
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

        uint256 existingWeight = currentStartTime * currentAmount;
        uint256 newWeight = block.timestamp * newAmount;

        // Check for overflow
        if (existingWeight > type(uint256).max - newWeight) {
            revert StakeAmountTooLarge();
        }

        newWeightedStartTime = (existingWeight + newWeight) / totalAmount;

        // Apply precision rounding
        uint256 precision = (existingWeight + newWeight) % totalAmount;
        if (precision > totalAmount / 2) {
            newWeightedStartTime += 1;
        }
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
    // View Functions
    // -------------------------------------------------------------

    function getTotalStaked(address user) public view returns (uint256) {
        return uint256(userStakes[user].amount);
    }

    function getTotalUnlocked(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (!_isUnlocked(userStake)) return 0;
        return uint256(userStake.amount) > uint256(userStake.cooldownAmount)
            ? uint256(userStake.amount) - uint256(userStake.cooldownAmount)
            : 0;
    }

    function getTotalLocked(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (_isUnlocked(userStake) || uint256(userStake.cooldownAmount) > 0) return 0;
        return uint256(userStake.amount);
    }

    function getTotalReadyForUnstake(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (!_isReadyForUnstake(userStake)) return 0;
        return uint256(userStake.cooldownAmount);
    }

    function getTotalInCooldown(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        return (userStake.hasStake && uint256(userStake.cooldownStart) > 0) ? uint256(userStake.cooldownAmount) : 0;
    }

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

    /**
     * @notice Get base multiplier for a specific lock-up period
     * @param lockUpPeriod The lock-up period in seconds
     * @return multiplier The base multiplier for the period
     */
    function getMultiplierForPeriod(uint256 lockUpPeriod) external pure returns (uint256 multiplier) {
        return _getMultiplierForPeriod(lockUpPeriod);
    }

    /**
     * @notice Check if user has an active stake
     * @param user The user address
     * @return Whether the user has an active stake
     */
    function hasActiveStake(address user) external view returns (bool) {
        return userStakes[user].hasStake;
    }

    // -------------------------------------------------------------
    // Additional Methods for RewardsDistributor Compatibility
    // -------------------------------------------------------------

    /**
     * @notice Get stake details for rewards calculation - adapted for single stake system
     * @param user The user address
     * @param stakeId The stake ID (should be 1 for compatibility)
     * @return amount The staked amount
     * @param lockUpPeriod The lock-up period
     * @param startTime The weighted start time
     * @param multiplier The effective multiplier
     * @param cooldownStart When cooldown was initiated
     * @param isActive Whether the stake is active
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
        )
    {
        if (stakeId != 1) {
            return (0, 0, 0, 0, 0, false);
        }

        UserStake memory userStake = userStakes[user];
        return (
            uint256(userStake.amount),
            uint256(userStake.effectiveLockUpPeriod),
            uint256(userStake.weightedStartTime),
            uint256(userStake.effectiveMultiplier),
            uint256(userStake.cooldownStart),
            userStake.hasStake
        );
    }

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
        )
    {
        UserStake memory userStake = userStakes[user];

        if (!userStake.hasStake) {
            // Return empty arrays
            stakeIds = new uint256[](0);
            amounts = new uint256[](0);
            multipliers = new uint256[](0);
            lockUpPeriods = new uint256[](0);
        } else {
            // Return single-element arrays
            stakeIds = new uint256[](1);
            amounts = new uint256[](1);
            multipliers = new uint256[](1);
            lockUpPeriods = new uint256[](1);

            stakeIds[0] = 1;
            amounts[0] = uint256(userStake.amount);
            multipliers[0] = uint256(userStake.effectiveMultiplier);
            lockUpPeriods[0] = uint256(userStake.effectiveLockUpPeriod);
        }
    }
}
