// SPDX-License-Identifier: MIT

pragma solidity ^0.8.30;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {
    ReentrancyGuardUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {IRewards} from "./interface/IRewards.sol";

/**
 * @title Rewards
 * @author Sapien Team
 * @notice Upgradeable reward distribution contract for the Sapien protocol
 * @dev Uses transparent proxy pattern for upgradeability
 */
contract Rewards is IRewards, Initializable, AccessControlUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    // ============================================
    // STATE VARIABLES (ERC-7201 namespaced storage)
    // ============================================

    /// @custom:storage-location erc7201:sapien.storage.Rewards
    struct RewardsStorage {
        address core;
        mapping(bytes32 => mapping(address => uint256)) projectRewards;
        mapping(address => mapping(bytes32 => mapping(address => uint256))) contributorRewards;
        mapping(address => mapping(bytes32 => mapping(address => uint256))) rewardsClaimed;
        mapping(address => mapping(bytes32 => mapping(address => uint256))) validatorRewards;
        mapping(address => mapping(bytes32 => mapping(address => uint256))) validatorRewardsClaimed;
        mapping(address => uint256) totalAllocated;
        uint256 maxFeeBps;
    }

    function _getRewardsStorage() private pure returns (RewardsStorage storage $) {
        bytes32 slot = keccak256(abi.encode(uint256(keccak256("sapien.storage.Rewards")) - 1)) & ~bytes32(uint256(0xff));
        assembly {
            $.slot := slot
        }
    }

    /// @notice Default max operator fee (4% = 400 bps)
    uint256 public constant DEFAULT_MAX_FEE_BPS = 400;

    /// @notice Hard cap for maximum fee (100% = 10000 bps, for safety validation)
    uint256 public constant MAX_FEE_BPS_CAP = 10000;

    // ============================================
    // MODIFIERS
    // ============================================

    modifier onlyCore() {
        _onlyCore();
        _;
    }

    function _onlyCore() internal view {
        if (msg.sender != _getRewardsStorage().core) {
            revert OnlyCore();
        }
    }

    // ============================================
    // CONSTRUCTOR & INITIALIZER
    // ============================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the Rewards contract
     * @param _defaultAdmin The address to grant DEFAULT_ADMIN_ROLE
     */
    function initialize(address _defaultAdmin) public initializer {
        if (_defaultAdmin == address(0)) revert InvalidAddress();

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);

        // Set default max operator fee to 4%
        _getRewardsStorage().maxFeeBps = DEFAULT_MAX_FEE_BPS;
    }

    /**
     * @notice Set the SapienCore address
     * @param _core The SapienCore contract address
     */
    function setCore(address _core) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_core == address(0)) {
            revert InvalidAddress();
        }
        // Opus 4.6 L-5 fix: Enforce one-time-set to prevent compromised admin
        // from redirecting core to a malicious contract that drains project rewards.
        RewardsStorage storage $ = _getRewardsStorage();
        if ($.core != address(0)) {
            revert CoreAlreadySet();
        }
        $.core = _core;
        emit CoreAddressUpdated(_core);
    }

    /**
     * @notice Set the maximum allowed operator fee in basis points
     * @param _maxFeeBps The new maximum fee in basis points (e.g., 1000 = 10%)
     */
    function setMaxFeeBps(uint256 _maxFeeBps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_maxFeeBps > MAX_FEE_BPS_CAP) {
            revert InvalidFeeBps();
        }
        _getRewardsStorage().maxFeeBps = _maxFeeBps;
        emit MaxFeeBpsUpdated(_maxFeeBps);
    }

    // ============================================
    // PAUSABLE FUNCTIONS
    // ============================================

    /**
     * @notice Pause the contract (emergency use)
     * @dev Can only be called by admin. Prevents all non-view functions from executing.
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Can only be called by admin. Restores normal contract functionality.
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal of stuck tokens
     * @dev Can only be called by admin when paused
     * @param token The token address to withdraw
     * @param to The recipient address
     * @param amount The amount to withdraw
     */
    function emergencyWithdraw(address token, address to, uint256 amount)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        whenPaused
    {
        if (to == address(0)) revert InvalidAddress();
        if (amount == 0) revert InvalidAmount();

        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 allocated = _getRewardsStorage().totalAllocated[token];
        uint256 available = balance > allocated ? balance - allocated : 0;

        if (amount > available) revert InsufficientProjectRewards(bytes32(0), token, amount, available);

        IERC20(token).safeTransfer(to, amount);
    }

    /**
     * @notice Sweep accumulated dust (rounding remainders) from the contract (F-13 fix)
     * @dev Unlike emergencyWithdraw, this does NOT require pausing. Only sweeps unallocated surplus.
     *      Dust accumulates from rounding in reward calculations and fee splits.
     * @param token The token address to sweep
     * @param to The recipient address for swept dust
     */
    function sweepDust(address token, address to) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (to == address(0)) revert InvalidAddress();

        uint256 balance = IERC20(token).balanceOf(address(this));
        uint256 allocated = _getRewardsStorage().totalAllocated[token];
        uint256 dust = balance > allocated ? balance - allocated : 0;

        if (dust == 0) revert InvalidAmount();

        IERC20(token).safeTransfer(to, dust);
        emit DustSwept(token, to, dust);
    }

    // ============================================
    // PROJECT REGISTRY FUNCTIONS
    // ============================================

    /**
     * @notice Allocate rewards for a project (called by SapienCore during funding)
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @param amount The amount of rewards to allocate
     */
    function allocateRewards(bytes32 projectId, address token, uint256 amount) external onlyCore whenNotPaused {
        if (amount == 0) revert InvalidAmount();
        if (token == address(0)) revert InvalidAddress();
        RewardsStorage storage $ = _getRewardsStorage();
        $.projectRewards[projectId][token] += amount;
        $.totalAllocated[token] += amount;
        emit RewardsAllocated(projectId, token, amount);
    }

    /**
     * @notice Distribute rewards to a contributor (called by SapienCore when contribution is validated)
     * @param projectId The project identifier (hashed CID)
     * @param contributor The address to receive rewards
     * @param token The reward token address
     * @param amount The amount of rewards to distribute
     */
    function distributeReward(bytes32 projectId, address contributor, address token, uint256 amount)
        external
        onlyCore
        whenNotPaused
    {
        _distribute(projectId, contributor, token, amount, false);
    }

    /**
     * @notice Distribute rewards to a validator (called by SapienCore when consensus is reached)
     * @param projectId The project identifier (hashed CID)
     * @param validator The address to receive rewards
     * @param token The reward token address
     * @param amount The amount of rewards to distribute
     */
    function distributeValidatorReward(bytes32 projectId, address validator, address token, uint256 amount)
        external
        onlyCore
        whenNotPaused
    {
        _distribute(projectId, validator, token, amount, true);
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    /**
     * @notice Internal helper to distribute rewards to either a contributor or validator
     * @dev Internal helper to distribute rewards to either a contributor or validator
     * @param projectId The project identifier (hashed CID)
     * @param user The address to receive rewards (contributor or validator)
     * @param token The reward token address
     * @param amount The amount of rewards to distribute
     * @param isValidator True if distributing to validator, false if contributor
     */
    function _distribute(bytes32 projectId, address user, address token, uint256 amount, bool isValidator) internal {
        if (amount == 0) {
            revert InvalidAmount();
        }

        RewardsStorage storage $ = _getRewardsStorage();
        uint256 available = $.projectRewards[projectId][token];
        if (available < amount) {
            revert InsufficientProjectRewards(projectId, token, amount, available);
        }

        $.projectRewards[projectId][token] -= amount;
        if (isValidator) {
            $.validatorRewards[user][projectId][token] += amount;
        } else {
            $.contributorRewards[user][projectId][token] += amount;
        }

        emit RewardsDistributed(projectId, user, token, amount);
    }

    /**
     * @notice Internal helper to validate fee parameters
     * @dev Internal helper to validate fee parameters
     * @param feeRecipient The address to receive the fee
     * @param feeBps The fee in basis points
     */
    function _validateFeeParams(address feeRecipient, uint256 feeBps) internal view {
        uint256 maxBps = _getRewardsStorage().maxFeeBps;
        if (feeBps > maxBps) {
            revert FeeBpsTooHigh(feeBps, maxBps);
        }
        if (feeBps > 0 && feeRecipient == address(0)) {
            revert InvalidFeeRecipient();
        }
    }

    /**
     * @notice Internal helper to transfer rewards with optional operator fee
     * @dev Internal helper to transfer rewards with optional operator fee
     * @param token The reward token address
     * @param recipient The primary recipient (claimer)
     * @param amount The total amount to transfer
     * @param feeRecipient The operator fee recipient
     * @param feeBps The fee in basis points
     */
    function _transferWithFee(address token, address recipient, uint256 amount, address feeRecipient, uint256 feeBps)
        internal
    {
        // Calculate fee and net amounts (multiply before divide for precision)
        uint256 feeAmount = (amount * feeBps) / 10000;
        uint256 netAmount = amount - feeAmount;

        // Transfer net rewards to claimer
        IERC20(token).safeTransfer(recipient, netAmount);

        // Transfer fee to operator (if applicable)
        if (feeAmount > 0) {
            IERC20(token).safeTransfer(feeRecipient, feeAmount);
            emit OperatorFeeCollected(recipient, feeRecipient, token, feeAmount);
        }
    }

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
    function claimRewards(bytes32 projectId, address token, address feeRecipient, uint256 feeBps)
        external
        nonReentrant
        whenNotPaused
    {
        // Validate fee parameters
        _validateFeeParams(feeRecipient, feeBps);

        RewardsStorage storage $ = _getRewardsStorage();
        uint256 availableRewards =
            $.contributorRewards[msg.sender][projectId][token] - $.rewardsClaimed[msg.sender][projectId][token];

        if (availableRewards == 0) {
            revert NoRewardsToClaim();
        }

        // Update state BEFORE transfers (CEI pattern)
        $.rewardsClaimed[msg.sender][projectId][token] += availableRewards;
        $.totalAllocated[token] -= availableRewards;

        // Transfer with optional fee
        _transferWithFee(token, msg.sender, availableRewards, feeRecipient, feeBps);

        emit RewardsClaimed(msg.sender, projectId, token, availableRewards);
    }

    /**
     * @notice Claim all accumulated rewards across all projects for a specific token
     * @param token The reward token address
     * @param projectIds Array of project identifiers (hashed CIDs) to claim from
     * @param feeRecipient Address to receive operator fee (use address(0) for no fee)
     * @param feeBps Fee in basis points (e.g., 100 = 1%, use 0 for no fee)
     */
    function claimAllRewards(address token, bytes32[] calldata projectIds, address feeRecipient, uint256 feeBps)
        external
        nonReentrant
        whenNotPaused
    {
        // Validate fee parameters
        _validateFeeParams(feeRecipient, feeBps);

        uint256 totalRewards = 0;

        RewardsStorage storage $ = _getRewardsStorage();
        for (uint256 i = 0; i < projectIds.length; ++i) {
            bytes32 projectId = projectIds[i];
            uint256 availableRewards =
                $.contributorRewards[msg.sender][projectId][token] - $.rewardsClaimed[msg.sender][projectId][token];

            if (availableRewards > 0) {
                $.rewardsClaimed[msg.sender][projectId][token] += availableRewards;
                totalRewards += availableRewards;
                $.totalAllocated[token] -= availableRewards;
                emit RewardsClaimed(msg.sender, projectId, token, availableRewards);
            }
        }

        if (totalRewards == 0) {
            revert NoRewardsToClaim();
        }

        // Transfer with optional fee
        _transferWithFee(token, msg.sender, totalRewards, feeRecipient, feeBps);
    }

    // ============================================
    // VALIDATOR FUNCTIONS
    // ============================================

    /**
     * @notice Claim accumulated rewards for a specific project and token as a validator
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @param feeRecipient Address to receive operator fee (use address(0) for no fee)
     * @param feeBps Fee in basis points (e.g., 100 = 1%, use 0 for no fee)
     */
    function claimValidatorRewards(bytes32 projectId, address token, address feeRecipient, uint256 feeBps)
        external
        nonReentrant
        whenNotPaused
    {
        // Validate fee parameters
        _validateFeeParams(feeRecipient, feeBps);

        RewardsStorage storage $ = _getRewardsStorage();
        uint256 availableRewards =
            $.validatorRewards[msg.sender][projectId][token] - $.validatorRewardsClaimed[msg.sender][projectId][token];

        if (availableRewards == 0) {
            revert NoRewardsToClaim();
        }

        // Update state BEFORE transfers (CEI pattern)
        $.validatorRewardsClaimed[msg.sender][projectId][token] += availableRewards;
        $.totalAllocated[token] -= availableRewards;

        // Transfer with optional fee
        _transferWithFee(token, msg.sender, availableRewards, feeRecipient, feeBps);

        emit RewardsClaimed(msg.sender, projectId, token, availableRewards);
    }

    /**
     * @notice Claim all accumulated validator rewards across all projects for a specific token
     * @param token The reward token address
     * @param projectIds Array of project identifiers (hashed CIDs) to claim from
     * @param feeRecipient Address to receive operator fee (use address(0) for no fee)
     * @param feeBps Fee in basis points (e.g., 100 = 1%, use 0 for no fee)
     */
    function claimAllValidatorRewards(
        address token,
        bytes32[] calldata projectIds,
        address feeRecipient,
        uint256 feeBps
    ) external nonReentrant whenNotPaused {
        // Validate fee parameters
        _validateFeeParams(feeRecipient, feeBps);

        uint256 totalRewards = 0;

        RewardsStorage storage $ = _getRewardsStorage();
        for (uint256 i = 0; i < projectIds.length; ++i) {
            bytes32 projectId = projectIds[i];
            uint256 availableRewards = $.validatorRewards[msg.sender][projectId][token]
                - $.validatorRewardsClaimed[msg.sender][projectId][token];

            if (availableRewards > 0) {
                $.validatorRewardsClaimed[msg.sender][projectId][token] += availableRewards;
                totalRewards += availableRewards;
                $.totalAllocated[token] -= availableRewards;
                emit RewardsClaimed(msg.sender, projectId, token, availableRewards);
            }
        }

        if (totalRewards == 0) {
            revert NoRewardsToClaim();
        }

        // Transfer with optional fee
        _transferWithFee(token, msg.sender, totalRewards, feeRecipient, feeBps);
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get available rewards for a contributor for a specific project and token
     * @param contributor The contributor address
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @return The amount of unclaimed rewards
     */
    function getAvailableRewards(address contributor, bytes32 projectId, address token)
        external
        view
        returns (uint256)
    {
        RewardsStorage storage $ = _getRewardsStorage();
        return $.contributorRewards[contributor][projectId][token] - $.rewardsClaimed[contributor][projectId][token];
    }

    /**
     * @notice Get total rewards earned by a contributor for a specific project and token
     * @param contributor The contributor address
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @return The total amount of rewards earned
     */
    function getTotalRewardsEarned(address contributor, bytes32 projectId, address token)
        external
        view
        returns (uint256)
    {
        return _getRewardsStorage().contributorRewards[contributor][projectId][token];
    }

    /**
     * @notice Get available rewards for a validator for a specific project and token
     * @param validator The validator address
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @return The amount of unclaimed validator rewards
     */
    function getAvailableValidatorRewards(address validator, bytes32 projectId, address token)
        external
        view
        returns (uint256)
    {
        RewardsStorage storage $ = _getRewardsStorage();
        return $.validatorRewards[validator][projectId][token] - $.validatorRewardsClaimed[validator][projectId][token];
    }

    /**
     * @notice Get total rewards earned by a validator for a specific project and token
     * @param validator The validator address
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @return The total amount of validator rewards earned
     */
    function getTotalValidatorRewardsEarned(address validator, bytes32 projectId, address token)
        external
        view
        returns (uint256)
    {
        return _getRewardsStorage().validatorRewards[validator][projectId][token];
    }

    /**
     * @notice Get remaining rewards allocated to a project
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @return The amount of remaining project rewards
     */
    function getRemainingProjectRewards(bytes32 projectId, address token) external view returns (uint256) {
        return _getRewardsStorage().projectRewards[projectId][token];
    }

    // ============================================
    // PUBLIC GETTERS (match IRewards interface)
    // ============================================

    /**
     * @notice Get the SapienCore address
     * @return The address of the SapienCore contract
     */
    function core() external view returns (address) {
        return _getRewardsStorage().core;
    }

    /**
     * @notice Get the maximum allowed operator fee in basis points
     * @return The maximum fee in basis points
     */
    function maxFeeBps() external view returns (uint256) {
        return _getRewardsStorage().maxFeeBps;
    }

    /**
     * @notice Get rewards allocated to a project for a specific token
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @return The amount of rewards allocated to the project
     */
    function projectRewards(bytes32 projectId, address token) external view returns (uint256) {
        return _getRewardsStorage().projectRewards[projectId][token];
    }

    /**
     * @notice Get total rewards earned by a contributor for a specific project and token
     * @param contributor The contributor address
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @return The total amount of rewards earned
     */
    function contributorRewards(address contributor, bytes32 projectId, address token) external view returns (uint256) {
        return _getRewardsStorage().contributorRewards[contributor][projectId][token];
    }

    /**
     * @notice Get rewards claimed by a contributor for a specific project and token
     * @param contributor The contributor address
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @return The amount of rewards claimed
     */
    function rewardsClaimed(address contributor, bytes32 projectId, address token) external view returns (uint256) {
        return _getRewardsStorage().rewardsClaimed[contributor][projectId][token];
    }

    /**
     * @notice Get total rewards earned by a validator for a specific project and token
     * @param validator The validator address
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @return The total amount of validator rewards earned
     */
    function validatorRewards(address validator, bytes32 projectId, address token) external view returns (uint256) {
        return _getRewardsStorage().validatorRewards[validator][projectId][token];
    }

    /**
     * @notice Get validator rewards claimed for a specific project and token
     * @param validator The validator address
     * @param projectId The project identifier (hashed CID)
     * @param token The reward token address
     * @return The amount of validator rewards claimed
     */
    function validatorRewardsClaimed(address validator, bytes32 projectId, address token)
        external
        view
        returns (uint256)
    {
        return _getRewardsStorage().validatorRewardsClaimed[validator][projectId][token];
    }

    /**
     * @notice Get total rewards allocated for a specific token across all projects
     * @param token The reward token address
     * @return The total amount allocated
     */
    function totalAllocated(address token) external view returns (uint256) {
        return _getRewardsStorage().totalAllocated[token];
    }
}
