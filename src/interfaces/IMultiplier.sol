// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/// @title IMultiplier - Interface for Sapien AI Staking Multiplier Calculator
/// @notice Interface for handling all multiplier calculations for the Sapien staking system
interface IMultiplier {
    error InvalidStakeAmount();
    error InvalidLockupPeriod();

    function calculateMultiplier(uint256 amount, uint256 lockUpPeriod) external pure returns (uint256);
    function isValidLockupPeriod(uint256 lockUpPeriod) external pure returns (bool isValid);
}
