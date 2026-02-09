// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {ISharedTypes} from "./ISharedTypes.sol";

/**
 * @title ISapienVault
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

    event Slashed(
        address indexed user, uint256 sharesSlashed, uint256 assetsSlashed, address indexed slasher, bytes32 projectId
    );
    event StakeLocked(address indexed user, uint256 amount, address indexed locker, string reason);
    event StakeUnlocked(address indexed user, uint256 amount, address indexed locker, string reason);

    // ============================================
    // CORE VAULT FUNCTIONS
    // ============================================

    function getStake(address user) external view returns (uint256);
    function totalStaked() external view returns (uint256);

    // ============================================
    // LOCKING FUNCTIONS
    // ============================================

    function lockStake(address user, uint256 amount, string calldata reason) external;
    function unlockStake(address user, uint256 amount, string calldata reason) external;
    function getAvailableStake(address user) external view returns (uint256);
    function getLockedStake(address user) external view returns (uint256);

    // ============================================
    // SLASHING FUNCTIONS
    // ============================================

    function slash(address user, uint256 amount, bytes32 projectId) external returns (uint256);

    // ============================================
    // PAUSABLE FUNCTIONS
    // ============================================

    function pause() external;
    function unpause() external;

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    function stakingToken() external view returns (IERC20);
}
