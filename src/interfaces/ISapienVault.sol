// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StakeAccount} from "src/Types.sol";

/// @title ISapienVault
/// @notice Interface for the SapienVault — the staking and escrow layer.
/// @dev Manages a single locked stake bucket per user.
///      lockStake is called by the owner; unlockStake and slashStake require ENGINE_ROLE.
interface ISapienVault {
    // ── Errors ─────────────────────────────────────────────────────────
    error InsufficientAvailableBalance(uint256 required, uint256 available);
    error InsufficientLockedAmount(uint256 required, uint256 locked);
    error TransferExceedsUnlockedShares();
    error DepositTooRecent(uint256 required, uint256 actual);
    error MinDepositAgeTooHigh(uint256 requested, uint256 max);
    error ZeroAmount();
    error ZeroAddress();
    error ZeroShareSlash();
    error EthTransferFailed();

    // ── Events ─────────────────────────────────────────────────────────
    event StakeLocked(address indexed user, uint256 amount);
    event StakeUnlocked(address indexed user, uint256 amount);
    event StakeSlashed(address indexed user, uint256 amount);
    event MinDepositAgeUpdated(uint256 newAge);
    event EthRescued(address indexed to, uint256 amount);

    // ── Stake Operations ───────────────────────────────────────────────

    /// @notice Lock stake from the caller's available balance.
    /// @dev Called by the owner directly. Enforces minimum stake age before
    ///      locking and then marks the specified asset amount as locked.
    ///      Any deposit or inbound share transfer resets this time-lock timer.
    /// @param amount Amount of tokens (asset terms) to lock.
    function lockStake(uint256 amount) external;

    /// @notice Unlock locked stake back to the user's available balance.
    /// @dev Called by the engine role only.
    /// @param user Address of the user.
    /// @param amount Amount of tokens (asset terms) to unlock.
    function unlockStake(address user, uint256 amount) external;

    /// @notice Slash locked stake (e.g., for being an outlier in consensus).
    /// @dev Called by the engine role only. Reduces locked stake and burns
    ///      corresponding vault shares.
    /// @param user Address of the user.
    /// @param amount Amount of tokens (asset terms) to slash.
    function slashStake(address user, uint256 amount) external;

    // ── Views ──────────────────────────────────────────────────────────

    /// @notice Retrieve the full stake account for a user.
    /// @param user Address of the user.
    /// @return The StakeAccount struct containing the locked amount.
    function getStakeAccount(address user) external view returns (StakeAccount memory);

    /// @notice Retrieve a user's available (unlocked) token balance.
    /// @param user Address of the user.
    /// @return The available balance.
    function availableBalance(address user) external view returns (uint256);

    /// @notice Retrieve the total staked amount for a user.
    /// @param user Address of the user.
    /// @return The total staked amount in asset terms.
    function getUserStakeBalance(address user) external view returns (uint256);

    /// @notice Verify that the vault's ERC-7201 storage location is correctly initialized.
    /// @return True if the storage slot matches the expected value.
    function verifyStorageLocation() external pure returns (bool);

    // ── Admin ──────────────────────────────────────────────────────────

    /// @notice Set minimum stake age required before lockStake, transfer, or withdraw.
    /// @dev Reverts if `age` is greater than MAX_MIN_DEPOSIT_AGE in the implementation.
    ///      This acts as an MEV front-running and flash-loan protection mechanism.
    /// @param age Required minimum age in seconds.
    function setMinDepositAge(uint256 age) external;

    /// @notice Read the configured minimum stake age for lockStake, transfer, or withdraw.
    /// @return Minimum age in seconds.
    function minDepositAge() external view returns (uint256);

    /// @notice Pause vault operations.
    /// @dev While paused, ERC-4626 max deposit/mint/withdraw/redeem are zero and
    ///      wallet-to-wallet share transfers are blocked.
    function pause() external;

    /// @notice Unpause vault operations.
    function unpause() external;

    /// @notice Rescue ETH that was sent to the vault (e.g. via the inherited
    ///         payable `upgradeToAndCall`) and forward it to `to`.
    /// @dev Admin-only. The vault's asset is ERC-20; it never holds ETH by design.
    ///      Provided so any accidentally-stuck ETH is recoverable.
    /// @param to Recipient of the rescued ETH.
    function rescueETH(address payable to) external;
}
