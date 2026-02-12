// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ISharedTypes} from "./ISharedTypes.sol";

/**
 * @title ISapienVault
 * @author Sapien Team
 * @notice Interface for the Sapien staking vault with slashing capability (Upgradeable)
 * @dev Defines additional slashing and locking functionality beyond ERC-4626 standard
 */
interface ISapienVault is ISharedTypes {
    // ============================================
    // CUSTOM ERRORS
    // ============================================

    error InvalidAddress();
    error InsufficientUnlockedStake(address user, uint256 required, uint256 available);
    error InsufficientLockedStake(address user, uint256 required, uint256 available);
    error ZeroAmount();
    error NoSharesToSlash(address user);

    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when a user's stake is slashed
     * @param user Address of the user being slashed
     * @param sharesSlashed Number of vault shares slashed
     * @param assetsSlashed Number of underlying assets slashed
     * @param slasher Address of the entity performing the slash
     * @param projectId Project associated with the slash
     */
    event Slashed(
        address indexed user, uint256 sharesSlashed, uint256 indexed assetsSlashed, address slasher, bytes32 indexed projectId
    );

    /**
     * @notice Emitted when stake is locked for a user
     * @param user Address of the user
     * @param amount Amount of stake locked
     * @param locker Address of the entity locking the stake
     * @param reason Human-readable reason for the lock
     */
    event StakeLocked(address indexed user, uint256 indexed amount, address indexed locker, string reason);

    /**
     * @notice Emitted when stake is unlocked for a user
     * @param user Address of the user
     * @param amount Amount of stake unlocked
     * @param locker Address of the entity unlocking the stake
     * @param reason Human-readable reason for the unlock
     */
    event StakeUnlocked(address indexed user, uint256 indexed amount, address indexed locker, string reason);

    // ============================================
    // CORE VAULT FUNCTIONS
    // ============================================

    /**
     * @notice Get the total stake (locked + unlocked) for a user
     * @param user Address of the user
     * @return Total stake amount
     */
    function getStake(address user) external view returns (uint256);

    /**
     * @notice Get the total assets staked in the vault
     * @return Total staked assets
     */
    function totalStaked() external view returns (uint256);

    // ============================================
    // LOCKING FUNCTIONS
    // ============================================

    /**
     * @notice Lock a portion of a user's stake
     * @param user Address of the user
     * @param amount Amount to lock
     * @param reason Reason for locking
     */
    function lockStake(address user, uint256 amount, string calldata reason) external;

    /**
     * @notice Unlock a portion of a user's stake
     * @param user Address of the user
     * @param amount Amount to unlock
     * @param reason Reason for unlocking
     */
    function unlockStake(address user, uint256 amount, string calldata reason) external;

    /**
     * @notice Get the available (unlocked) stake for a user
     * @param user Address of the user
     * @return The available stake amount
     */
    function getAvailableStake(address user) external view returns (uint256);

    /**
     * @notice Get the locked stake for a user
     * @param user Address of the user
     * @return The locked stake amount
     */
    function getLockedStake(address user) external view returns (uint256);

    // ============================================
    // SLASHING FUNCTIONS
    // ============================================

    /**
     * @notice Slash a user's stake
     * @param user Address of the user to slash
     * @param amount Amount to slash
     * @param projectId Project associated with the slash
     * @return assetsSlashed Actual amount of assets slashed
     */
    function slash(address user, uint256 amount, bytes32 projectId) external returns (uint256 assetsSlashed);

    // ============================================
    // PAUSABLE FUNCTIONS
    // ============================================

    /**
     * @notice Pause the vault
     */
    function pause() external;

    /**
     * @notice Unpause the vault
     */
    function unpause() external;

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /**
     * @notice Get the staking token address
     * @return The IERC20 staking token
     */
    function stakingToken() external view returns (IERC20);
}
