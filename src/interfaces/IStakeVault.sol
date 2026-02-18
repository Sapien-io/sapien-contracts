// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {StakeAccount} from "src/Types.sol";

/// @title IStakeVault
/// @notice Interface for the StakeVault contract used by QualityEngine
interface IStakeVault {
    // ── Contributor stake ──────────────────────────────────────────────
    function lockContributor(address user, uint256 amount) external;
    function unlockContributor(address user, uint256 amount) external;
    function slashContributor(address user, uint256 amount) external;

    // ── Batch contributor operations ───────────────────────────────────
    function slashAndUnlockContributor(address user, uint256 slashAmount, uint256 unlockAmount) external;

    // ── Validator stake ────────────────────────────────────────────────
    function lockValidatorCapacity(address user, uint256 amount) external;
    function unlockValidatorCapacity(address user, uint256 amount) external;

    // ── Validator in-flight (commit → reveal cycle) ────────────────────
    function commitStake(address user, uint256 amount) external;
    function releaseCommit(address user, uint256 amount) external;
    function slashValidator(address user, uint256 amount) external;

    // ── Views ──────────────────────────────────────────────────────────
    function getStakeAccount(address user) external view returns (StakeAccount memory);
    function availableBalance(address user) external view returns (uint256);
    function totalStaked(address user) external view returns (uint256);
    function verifyStorageLocation() external pure returns (bool);
}
