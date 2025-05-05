// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/**
 * @title IPoolAdapter
 * @notice Interface for pool adapters that handle LP token deposits and withdrawals
 */
interface IPoolAdapter {
    /**
     * @notice Deposits LP tokens into the pool
     * @param user The address of the user depositing LP tokens
     * @param amount The amount of LP tokens to deposit
     * @return success True if the deposit was successful
     */
    function depositLP(address user, uint256 amount) external returns (bool);

    /**
     * @notice Withdraws LP tokens from the pool
     * @param user The address of the user withdrawing LP tokens
     * @param amount The amount of LP tokens to withdraw
     * @return success True if the withdrawal was successful
     */
    function withdrawLP(address user, uint256 amount) external returns (bool);
} 