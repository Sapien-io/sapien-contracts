// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StakeAccount} from "src/Types.sol";

/// @title ISapienVault
/// @notice Interface for the SapienVault — the staking and escrow layer used by SapienCore.
/// @dev Manages three stake buckets per user: contributor locks, validator capacity, and
///      in-flight (committed) validator stakes. Only callable by the authorized SapienCore contract.
interface ISapienVault {
    // ── Errors ─────────────────────────────────────────────────────────
    error InsufficientAvailableBalance(uint256 required, uint256 available);
    error InsufficientContributorLock(uint256 required, uint256 locked);
    error InsufficientValidatorCapacity(uint256 required, uint256 capacity);
    error InsufficientInFlight(uint256 required, uint256 inFlight);
    error TransferExceedsUnlockedShares();
    error DepositTooRecent(uint256 required, uint256 actual);
    error MinDepositAgeTooHigh(uint256 requested, uint256 max);
    error ZeroAmount();
    error ZeroAddress();

    // ── Events ─────────────────────────────────────────────────────────
    event ContributorLocked(address indexed user, uint256 amount);
    event ContributorUnlocked(address indexed user, uint256 amount);
    event ContributorSlashed(address indexed user, uint256 amount);
    event ValidatorCapacityLocked(address indexed user, uint256 amount);
    event ValidatorCapacityUnlocked(address indexed user, uint256 amount);
    event StakeCommitted(address indexed user, uint256 amount);
    event CommitReleased(address indexed user, uint256 amount);
    event ValidatorSlashed(address indexed user, uint256 amount);
    event MinDepositAgeUpdated(uint256 newAge);

    // ── Contributor Stake ──────────────────────────────────────────────

    /// @notice Lock tokens from a contributor's available balance as collateral for claimed slots.
    /// @dev Called when a contributor claims contribution slots. The locked amount is
    ///      subject to slashing if the contributor fails to submit before the deadline.
    /// @param user Address of the contributor.
    /// @param amount Amount of tokens to lock.
    function lockContributor(address user, uint256 amount) external;

    /// @notice Unlock previously locked contributor tokens back to their available balance.
    /// @dev Called when a contributor successfully submits work or when slots are released.
    /// @param user Address of the contributor.
    /// @param amount Amount of tokens to unlock.
    function unlockContributor(address user, uint256 amount) external;

    /// @notice Slash a contributor's locked tokens (e.g., for failing to submit on time).
    /// @dev Slashed tokens are removed from the contributor's lock and sent to the treasury.
    /// @param user Address of the contributor.
    /// @param amount Amount of tokens to slash.
    function slashContributor(address user, uint256 amount) external;

    // ── Batch Contributor Operations ───────────────────────────────────

    /// @notice Atomically slash and unlock a contributor's locked tokens in a single call.
    /// @dev Used when a claim expires with partial submissions — unsubmitted slots are slashed
    ///      while submitted slots are unlocked. Saves gas compared to separate calls.
    /// @param user Address of the contributor.
    /// @param slashAmount Amount of tokens to slash.
    /// @param unlockAmount Amount of tokens to unlock.
    function slashAndUnlockContributor(address user, uint256 slashAmount, uint256 unlockAmount) external;

    // ── Validator Stake ────────────────────────────────────────────────

    /// @notice Lock tokens as validator capacity, enabling the user to commit validations.
    /// @dev Tokens move from the user's available balance to the validator capacity bucket.
    ///      Capacity is a prerequisite for committing validation stakes.
    /// @param user Address of the validator.
    /// @param amount Amount of tokens to lock as capacity.
    function lockValidatorCapacity(address user, uint256 amount) external;

    /// @notice Unlock tokens from validator capacity back to the user's available balance.
    /// @dev Only unlocks idle capacity — tokens currently committed to in-flight validations
    ///      cannot be unlocked until those validations are settled.
    /// @param user Address of the validator.
    /// @param amount Amount of tokens to unlock.
    function unlockValidatorCapacity(address user, uint256 amount) external;

    // ── Validator In-Flight (Commit → Reveal Cycle) ────────────────────

    /// @notice Move tokens from validator capacity to in-flight status when committing a score.
    /// @dev Called during the commit phase. In-flight tokens are at risk of slashing if the
    ///      validator is classified as an outlier during consensus.
    /// @param user Address of the validator.
    /// @param amount Amount of tokens to commit from capacity.
    function commitStake(address user, uint256 amount) external;

    /// @notice Release in-flight tokens back to validator capacity after settlement.
    /// @dev Called when a validator is settled as accurate (not an outlier). Returns the
    ///      committed stake to the capacity bucket.
    /// @param user Address of the validator.
    /// @param amount Amount of tokens to release.
    function releaseCommit(address user, uint256 amount) external;

    /// @notice Slash a validator's in-flight tokens (e.g., for being an outlier in consensus).
    /// @dev Slashed tokens are removed from in-flight balance and sent to the treasury.
    /// @param user Address of the validator.
    /// @param amount Amount of tokens to slash.
    function slashValidator(address user, uint256 amount) external;

    // ── Views ──────────────────────────────────────────────────────────

    /// @notice Retrieve the full stake account for a user.
    /// @param user Address of the user.
    /// @return The StakeAccount struct containing contributor lock, validator capacity, and in-flight balances.
    function getStakeAccount(address user) external view returns (StakeAccount memory);

    /// @notice Retrieve a user's available (unlocked, uncommitted) token balance.
    /// @param user Address of the user.
    /// @return The available balance.
    function availableBalance(address user) external view returns (uint256);

    /// @notice Retrieve the total staked amount across all buckets for a user.
    /// @param user Address of the user.
    /// @return The total staked amount (contributor lock + validator capacity + in-flight).
    function totalStaked(address user) external view returns (uint256);

    /// @notice Verify that the vault's ERC-7201 storage location is correctly initialized.
    /// @return True if the storage slot matches the expected value.
    function verifyStorageLocation() external pure returns (bool);
}
