// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/// @title IMultiplier - Interface for Sapien AI Staking Multiplier Calculator
/// @notice Interface for handling all multiplier calculations for the Sapien staking system
interface IMultiplier {
    // -------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------

    error InvalidStakeAmount();
    error InvalidLockupPeriod();

    // -------------------------------------------------------------
    // Core Multiplier Functions
    // -------------------------------------------------------------

    /**
     * @notice Calculate multiplier combining base lockup multiplier with amount factor
     * @param amount The staked amount
     * @param lockUpPeriod The effective lockup period
     * @return uint256 calculated multiplier
     */
    function calculateMultiplier(uint256 amount, uint256 lockUpPeriod) external pure returns (uint256);

    /**
     * @notice Validates that a lockup period is supported
     * @param lockUpPeriod The lockup period to validate
     * @return isValid Whether the lockup period is valid
     */
    function isValidLockupPeriod(uint256 lockUpPeriod) external pure returns (bool isValid);
}
