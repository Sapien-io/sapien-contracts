// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {StakeAccount} from "src/Types.sol";

/// @title ISapienVault
/// @author Sapien
/// @notice Interface for the SapienVault — the staking and escrow layer.
/// @dev Manages a single locked stake bucket per user.
///      lockStake is called by the owner; unlockStake and slashStake require ENGINE_ROLE.
interface ISapienVault {
    // ── Errors ─────────────────────────────────────────────────────────
    error InsufficientAvailableBalance(uint256 required, uint256 available);
    error InsufficientLockedAmount(uint256 required, uint256 locked);
    error TransferExceedsUnlockedShares();
    error MinDepositAgeTooHigh(uint256 requested, uint256 max);
    error BelowMinTrancheSize(uint256 assets, uint256 minSize);
    error ZeroAmount();
    error ZeroAddress();
    error ZeroShareSlash();
    error EthTransferFailed();

    // ── Events ─────────────────────────────────────────────────────────

    /// @notice Emitted when a user moves stake from available to locked.
    /// @param user Address whose stake was locked.
    /// @param amount Asset-denominated amount that became locked.
    event StakeLocked(address indexed user, uint256 indexed amount);

    /// @notice Emitted when the engine returns locked stake to available balance.
    /// @param user Address whose stake was unlocked.
    /// @param amount Asset-denominated amount that was unlocked.
    event StakeUnlocked(address indexed user, uint256 indexed amount);

    /// @notice Emitted when the engine slashes locked stake (shares are burned).
    /// @param user Address whose stake was slashed.
    /// @param amount Asset-denominated intended net damage applied to the user.
    event StakeSlashed(address indexed user, uint256 indexed amount);

    /// @notice Emitted alongside `StakeSlashed` with the exact share quantity
    ///         burned. Burned shares exceed the naive `amount`-equivalent because
    ///         the burn is sized to defeat exchange-rate dilution recapture (SAP-2).
    /// @param user Address whose shares were burned.
    /// @param shares Number of vault shares burned by the slash.
    event SharesSlashed(address indexed user, uint256 indexed shares);

    /// @notice Emitted when the admin updates the minimum deposit-age timer.
    /// @param newAge New minimum deposit age, in seconds.
    event MinDepositAgeUpdated(uint256 indexed newAge);

    /// @notice Emitted when the admin updates the minimum immature-tranche size.
    /// @param newSize New minimum tranche size, in asset terms.
    event MinTrancheSizeUpdated(uint256 indexed newSize);

    /// @notice Emitted when admin rescues stuck ETH from the proxy.
    /// @param to Recipient of the rescued ETH.
    /// @param amount Wei amount transferred.
    event EthRescued(address indexed to, uint256 indexed amount);

    // ── Stake Operations ───────────────────────────────────────────────

    /// @notice Lock stake from the caller's available balance.
    /// @dev Called by the owner directly. Only shares that have cleared
    ///      `minDepositAge` (matured) and are not already locked can be locked.
    ///      Recently-deposited (immature) shares are excluded until they age;
    ///      already-matured shares are unaffected by later deposits/transfers.
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

    /// @notice Shares held by `user` that have cleared `minDepositAge` and are
    ///         therefore actionable (lockable / withdrawable / transferable),
    ///         before subtracting any locked reservation.
    /// @param user Address of the user.
    /// @return Matured share amount.
    function maturedShares(address user) external view returns (uint256);

    /// @notice Shares held by `user` that are still inside the `minDepositAge`
    ///         cooldown window. `maturedShares + pendingShares == balanceOf`.
    /// @param user Address of the user.
    /// @return Immature share amount.
    function pendingShares(address user) external view returns (uint256);

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

    /// @notice Set the minimum asset amount for a new immature tranche.
    /// @dev Only enforced when `minDepositAge > 0`. Deposits/mints that would
    ///      record fewer asset-equivalent shares revert. Zero disables the check.
    /// @param size Minimum tranche size, in asset terms.
    function setMinTrancheSize(uint256 size) external;

    /// @notice Read the configured minimum immature-tranche size.
    /// @return Minimum tranche size, in asset terms (0 = disabled).
    function minTrancheSize() external view returns (uint256);

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
