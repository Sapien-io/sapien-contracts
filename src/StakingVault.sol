// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {IStakingVault} from "src/interfaces/IStakingVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/// @title StakingVault - Sapien AI Staking Vault
/// @notice Sapien protocol reputation system with simplified single stake per user.
contract StakingVault is
    IStakingVault,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    /// @dev The Sapien token interface for staking/unstaking (IERC20).
    IERC20 public sapienToken;

    /// @dev Address of the Sapien Treasury
    address public sapienTreasury;

    /// @dev Tracks the total amount of tokens staked in this contract.
    uint256 public totalStaked;

    /// @notice Mapping of user addresses to their aggregated stake data.
    mapping(address => UserStake) public userStakes;

    /// @dev Minimum multiplier (1.05x at 30 days) - basis points: 10000 = 1.0x
    uint256 private constant MIN_MULTIPLIER = 10500;

    /// @dev Maximum multiplier (1.50x at 365 days) - basis points: 10000 = 1.0x
    uint256 private constant MAX_MULTIPLIER = 15000;

    /// @dev Multiplier for 90 days lockup period - basis points: 10000 = 1.0x
    uint256 private constant MULTIPLIER_90_DAYS = 11000;

    /// @dev Multiplier for 180 days lockup period - basis points: 10000 = 1.0x
    uint256 private constant MULTIPLIER_180_DAYS = 12500;

    /// @dev The cooldown period before a user can finalize their unstake.
    uint256 private constant COOLDOWN_PERIOD = 2 days;

    /// @dev Penalty percentage for instant unstake (e.g., 20 means 20%).
    uint256 private constant EARLY_WITHDRAWAL_PENALTY = 20;

    /// @dev Constant for the token's decimal representation (e.g., 10^18 for 18 decimal tokens).
    uint256 private constant TOKEN_DECIMALS = 10 ** 18;

    /// @dev Minimum stake amount (1,000 SAPIEN)
    uint256 public constant MINIMUM_STAKE = 1000 * TOKEN_DECIMALS;

    /// @dev Minimum lockup increase (7 days)
    uint256 public constant MINIMUM_LOCKUP_INCREASE = 7 days;

    /// @dev Role for pausing/unpausing the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Mapping of owner addresses to whether they are authorized to upgrade.
    mapping(address => bool) private _upgradeAuthorized;

    // -------------------------------------------------------------
    // Initialization (UUPS)
    // -------------------------------------------------------------

    /**
     * @notice Initializes the StakingVault contract.
     * @param token The IERC20 token contract for Sapien.
     * @param admin The address of the admin multisig.
     * @param treasury The address of the Treasury multisig for penalty collection.
     */
    function initialize(address token, address admin, address treasury) public initializer {
        require(token != address(0), "Zero address not allowed for token");
        require(admin != address(0), "Zero address not allowed for Admin");
        require(treasury != address(0), "Zero address not allowed for Treasury");

        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);

        sapienToken = IERC20(token);
        sapienTreasury = treasury;
    }

    // -------------------------------------------------------------
    // Access Control Modifiers
    // -------------------------------------------------------------

    modifier onlyAdmin() {
        require(hasRole(DEFAULT_ADMIN_ROLE, msg.sender), "Only admin can perform this");
        _;
    }

    modifier onlyPauser() {
        require(hasRole(PAUSER_ROLE, msg.sender), "Only pauser can perform this");
        _;
    }

    // -------------------------------------------------------------
    // Role-Based Functions
    // -------------------------------------------------------------

    /**
     * @notice Authorizes an upgrade of this contract to a new implementation (UUPS).
     * @param newImplementation The address of the new contract implementation.
     */
    function authorizeUpgrade(address newImplementation) public onlyAdmin {
        _upgradeAuthorized[newImplementation] = true;
        emit UpgradeAuthorized(newImplementation);
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyAdmin {
        require(_upgradeAuthorized[newImplementation], "TwoTierAccessControl: upgrade not authorized by admin");
        // Reset authorization after use to prevent re-use
        _upgradeAuthorized[newImplementation] = false;
    }

    /**
     * @notice Updates the base multiplier for a given lock-up period.
     * @dev This function is deprecated as multipliers are now constants.
     */
    function updateMultiplier(uint256, /* lockUpPeriod */ uint256 /* multiplier */ ) external view onlyAdmin {
        revert("Multipliers are now constants and cannot be updated");
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
     * @notice Updates the Treasury address for penalty collection.
     * @param newSapienTreasury The new Treasury address.
     */
    function updateSapienTreasury(address newSapienTreasury) external onlyAdmin {
        require(newSapienTreasury != address(0), "Zero address not allowed");
        sapienTreasury = newSapienTreasury;
        emit SapienTreasuryUpdated(newSapienTreasury);
    }

    // -------------------------------------------------------------
    // Simplified Stake Management
    // -------------------------------------------------------------

    /**
     * @notice Stake a specified `amount` of tokens for a given `lockUpPeriod`.
     * @param amount The amount of tokens to stake.
     * @param lockUpPeriod The lock-up duration in seconds (30/90/180/365 days).
     */
    function stake(uint256 amount, uint256 lockUpPeriod) public whenNotPaused nonReentrant {
        require(amount >= MINIMUM_STAKE, "Minimum 1,000 SAPIEN required");

        uint256 baseMultiplier = _getMultiplierForPeriod(lockUpPeriod);
        require(baseMultiplier > 0, "Invalid lock-up period");

        UserStake storage userStake = userStakes[msg.sender];

        SafeERC20.safeTransferFrom(sapienToken, msg.sender, address(this), amount);

        if (!userStake.hasStake) {
            // First stake for this user
            userStake.amount = amount;
            userStake.weightedStartTime = block.timestamp;
            userStake.effectiveLockUpPeriod = lockUpPeriod;
            userStake.effectiveMultiplier = baseMultiplier;
            userStake.lastUpdateTime = block.timestamp;
            userStake.hasStake = true;
        } else {
            // Combine with existing stake using weighted averages
            uint256 newTotalAmount = userStake.amount + amount;

            // Calculate new weighted start time
            userStake.weightedStartTime =
                (userStake.weightedStartTime * userStake.amount + block.timestamp * amount) / newTotalAmount;

            // Calculate new effective lockup period (weighted by amount)
            userStake.effectiveLockUpPeriod =
                (userStake.effectiveLockUpPeriod * userStake.amount + lockUpPeriod * amount) / newTotalAmount;

            // Update amount
            userStake.amount = newTotalAmount;

            // Recalculate effective multiplier
            userStake.effectiveMultiplier = _calculateEffectiveMultiplier(userStake.effectiveLockUpPeriod);

            userStake.lastUpdateTime = block.timestamp;
        }

        totalStaked += amount;

        emit Staked(msg.sender, amount, userStake.effectiveMultiplier, userStake.effectiveLockUpPeriod);
    }

    /**
     * @notice Increase the staked amount without changing lockup period.
     * @param additionalAmount The additional amount to stake.
     */
    function increaseAmount(uint256 additionalAmount) public whenNotPaused nonReentrant {
        require(additionalAmount > 0, "Amount must be greater than 0");

        UserStake storage userStake = userStakes[msg.sender];
        require(userStake.hasStake, "No existing stake found");
        require(userStake.cooldownStart == 0, "Cannot increase during cooldown");

        SafeERC20.safeTransferFrom(sapienToken, msg.sender, address(this), additionalAmount);

        uint256 newTotalAmount = userStake.amount + additionalAmount;

        // When increasing amount, we maintain the current effective lockup period
        // but recalculate the weighted start time
        userStake.weightedStartTime =
            (userStake.weightedStartTime * userStake.amount + block.timestamp * additionalAmount) / newTotalAmount;
        userStake.amount = newTotalAmount;
        userStake.lastUpdateTime = block.timestamp;

        // Effective multiplier stays the same since lockup period doesn't change

        totalStaked += additionalAmount;

        emit AmountIncreased(msg.sender, additionalAmount, newTotalAmount, userStake.effectiveMultiplier);
    }

    /**
     * @notice Increase the lockup period for existing stake.
     * @param additionalLockup The additional lockup time in seconds.
     */
    function increaseLockup(uint256 additionalLockup) public whenNotPaused nonReentrant {
        require(additionalLockup >= MINIMUM_LOCKUP_INCREASE, "Minimum 7 days increase required");

        UserStake storage userStake = userStakes[msg.sender];
        require(userStake.hasStake, "No existing stake found");
        require(userStake.cooldownStart == 0, "Cannot increase during cooldown");

        // Calculate remaining lockup time
        uint256 timeElapsed = block.timestamp - userStake.weightedStartTime;
        uint256 remainingLockup =
            userStake.effectiveLockUpPeriod > timeElapsed ? userStake.effectiveLockUpPeriod - timeElapsed : 0;

        // New effective lockup is remaining time plus additional lockup
        uint256 newEffectiveLockup = remainingLockup + additionalLockup;

        // Cap at maximum lockup period
        if (newEffectiveLockup > 365 days) {
            newEffectiveLockup = 365 days;
        }

        userStake.effectiveLockUpPeriod = newEffectiveLockup;
        userStake.effectiveMultiplier = _calculateEffectiveMultiplier(newEffectiveLockup);

        // Reset the weighted start time to now since we're extending lockup
        userStake.weightedStartTime = block.timestamp;
        userStake.lastUpdateTime = block.timestamp;

        emit LockupIncreased(msg.sender, additionalLockup, newEffectiveLockup, userStake.effectiveMultiplier);
    }

    /**
     * @notice Initiates the cooldown for unstaking.
     * @param amount The amount intended for unstaking.
     */
    function initiateUnstake(uint256 amount) public whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than 0");

        UserStake storage userStake = userStakes[msg.sender];
        require(userStake.hasStake, "No stake found");
        require(_isUnlocked(userStake), "Stake is still locked");
        require(amount <= userStake.amount - userStake.cooldownAmount, "Amount exceeds available balance");

        if (userStake.cooldownStart == 0) {
            userStake.cooldownStart = block.timestamp;
        }

        userStake.cooldownAmount += amount;

        emit UnstakingInitiated(msg.sender, amount);
    }

    /**
     * @notice Completes the unstaking process after the cooldown period has passed.
     * @param amount The amount to unstake.
     */
    function unstake(uint256 amount) public whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than 0");

        UserStake storage userStake = userStakes[msg.sender];
        require(userStake.hasStake, "No stake found");
        require(_isReadyForUnstake(userStake), "Not ready for unstake");
        require(amount <= userStake.cooldownAmount, "Amount exceeds cooldown amount");

        userStake.amount -= amount;
        userStake.cooldownAmount -= amount;
        totalStaked -= amount;

        if (userStake.cooldownAmount == 0) {
            userStake.cooldownStart = 0;
        }

        if (userStake.amount == 0) {
            userStake.hasStake = false;
        }

        SafeERC20.safeTransfer(sapienToken, msg.sender, amount);

        emit Unstaked(msg.sender, amount);
    }

    /**
     * @notice Instantly unstakes a specified `amount`, incurring a penalty.
     * @param amount The amount to unstake instantly.
     */
    function instantUnstake(uint256 amount) public whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than 0");

        UserStake storage userStake = userStakes[msg.sender];
        require(userStake.hasStake, "No stake found");
        require(amount <= userStake.amount - userStake.cooldownAmount, "Amount exceeds available balance");

        // Add check to ensure instant unstake is only possible during lock period
        require(!_isUnlocked(userStake), "Lock period completed, use regular unstake");

        uint256 penalty = (amount * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 payout = amount - penalty;

        userStake.amount -= amount;
        totalStaked -= amount;

        if (userStake.amount == 0) {
            userStake.hasStake = false;
        }

        SafeERC20.safeTransfer(sapienToken, msg.sender, payout);
        if (penalty > 0) {
            SafeERC20.safeTransfer(sapienToken, sapienTreasury, penalty);
        }

        emit InstantUnstake(msg.sender, payout, penalty);
    }

    // -------------------------------------------------------------
    // Helper Functions
    // -------------------------------------------------------------

    function _isUnlocked(UserStake memory userStake) private view returns (bool) {
        return userStake.hasStake && block.timestamp >= userStake.weightedStartTime + userStake.effectiveLockUpPeriod;
    }

    function _isReadyForUnstake(UserStake memory userStake) private view returns (bool) {
        return userStake.hasStake && userStake.cooldownStart > 0
            && block.timestamp >= userStake.cooldownStart + COOLDOWN_PERIOD && userStake.cooldownAmount > 0;
    }

    /**
     * @notice Calculate effective multiplier based on lockup period using interpolation.
     * @param effectiveLockup The effective lockup period.
     * @return The calculated multiplier.
     */
    function _calculateEffectiveMultiplier(uint256 effectiveLockup) private pure returns (uint256) {
        if (effectiveLockup >= 365 days) {
            return MAX_MULTIPLIER; // 15000 (1.50x)
        } else if (effectiveLockup >= 180 days) {
            // Linear interpolation between 180 days and 365 days
            uint256 ratio = (effectiveLockup - 180 days) * 10000 / (365 days - 180 days);
            return MULTIPLIER_180_DAYS + ((MAX_MULTIPLIER - MULTIPLIER_180_DAYS) * ratio / 10000);
        } else if (effectiveLockup >= 90 days) {
            // Linear interpolation between 90 days and 180 days
            uint256 ratio = (effectiveLockup - 90 days) * 10000 / (180 days - 90 days);
            return MULTIPLIER_90_DAYS + ((MULTIPLIER_180_DAYS - MULTIPLIER_90_DAYS) * ratio / 10000);
        } else if (effectiveLockup >= 30 days) {
            // Linear interpolation between 30 days and 90 days
            uint256 ratio = (effectiveLockup - 30 days) * 10000 / (90 days - 30 days);
            return MIN_MULTIPLIER + ((MULTIPLIER_90_DAYS - MIN_MULTIPLIER) * ratio / 10000);
        } else {
            // Less than 30 days, use base multiplier of 1.0x (10000)
            return 10000;
        }
    }

    /**
     * @notice Get base multiplier for a specific lock-up period
     * @param lockUpPeriod The lock-up period in seconds
     * @return multiplier The base multiplier for the period
     */
    function _getMultiplierForPeriod(uint256 lockUpPeriod) private pure returns (uint256 multiplier) {
        if (lockUpPeriod == 30 days) {
            return MIN_MULTIPLIER; // 10500 (1.05x)
        } else if (lockUpPeriod == 90 days) {
            return MULTIPLIER_90_DAYS; // 11000 (1.10x)
        } else if (lockUpPeriod == 180 days) {
            return MULTIPLIER_180_DAYS; // 12500 (1.25x)
        } else if (lockUpPeriod == 365 days) {
            return MAX_MULTIPLIER; // 15000 (1.50x)
        } else {
            return 0; // Invalid period
        }
    }

    // -------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------

    function getTotalStaked(address user) public view returns (uint256) {
        return userStakes[user].amount;
    }

    function getTotalUnlocked(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (!_isUnlocked(userStake)) return 0;
        return userStake.amount > userStake.cooldownAmount ? userStake.amount - userStake.cooldownAmount : 0;
    }

    function getTotalLocked(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (_isUnlocked(userStake) || userStake.cooldownAmount > 0) return 0;
        return userStake.amount;
    }

    function getTotalReadyForUnstake(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        if (!_isReadyForUnstake(userStake)) return 0;
        return userStake.cooldownAmount;
    }

    function getTotalInCooldown(address user) public view returns (uint256) {
        UserStake memory userStake = userStakes[user];
        return (userStake.hasStake && userStake.cooldownStart > 0) ? userStake.cooldownAmount : 0;
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

        userTotalStaked = userStake.amount;
        totalUnlocked = getTotalUnlocked(user);
        totalLocked = getTotalLocked(user);
        totalInCooldown = getTotalInCooldown(user);
        totalReadyForUnstake = getTotalReadyForUnstake(user);
        effectiveMultiplier = userStake.effectiveMultiplier;
        effectiveLockUpPeriod = userStake.effectiveLockUpPeriod;

        if (userStake.hasStake) {
            uint256 unlockTime = userStake.weightedStartTime + userStake.effectiveLockUpPeriod;
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
        )
    {
        if (stakeId != 1) {
            return (0, 0, 0, 0, 0, false);
        }

        UserStake memory userStake = userStakes[user];
        return (
            userStake.amount,
            userStake.effectiveLockUpPeriod,
            userStake.weightedStartTime,
            userStake.effectiveMultiplier,
            userStake.cooldownStart,
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
            amounts[0] = userStake.amount;
            multipliers[0] = userStake.effectiveMultiplier;
            lockUpPeriods[0] = userStake.effectiveLockUpPeriod;
        }
    }
}
