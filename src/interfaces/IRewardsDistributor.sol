// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

interface IRewardsDistributor {
    // -------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------

    struct RewardSummary {
        uint256 totalPendingRewards;
        uint256 totalClaimedRewards;
        uint256 totalVotingPower;
        uint256 averageAPY;
        uint256 activeStakeCount;
    }

    struct StakeRewardDetails {
        uint256 pendingRewards;
        uint256 claimedRewards;
        uint256 lastClaim;
        uint256 estimatedAPY;
        uint256 votingPower;
        uint256 totalEarned;
    }

    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    event RewardsClaimed(address indexed user, uint256 indexed stakeId, uint256 amount);
    event RewardPoolFunded(uint256 amount);
    event BaseRewardRateUpdated(uint256 oldRate, uint256 newRate);
    event EmergencyWithdraw(uint256 amount, uint256 rewardPool);

    // -------------------------------------------------------------
    // Core Functions
    // -------------------------------------------------------------

    /**
     * @notice Calculate pending rewards for a specific stake
     * @param user The user address
     * @param stakeId The stake ID
     * @return pendingReward The amount of pending rewards
     */
    function calculatePendingRewards(address user, uint256 stakeId) external view returns (uint256 pendingReward);

    /**
     * @notice Calculate total pending rewards for all user stakes
     * @param user The user address
     * @return totalPending Total pending rewards across all stakes
     */
    function calculateUserTotalPendingRewards(address user) external view returns (uint256 totalPending);

    /**
     * @notice Calculate voting power for a user based on staked amounts and multipliers
     * @param user The user address
     * @return totalVotingPower Total voting power (stakedAmount × multiplier)
     */
    function calculateUserVotingPower(address user) external view returns (uint256 totalVotingPower);

    /**
     * @notice Calculate estimated APY for a lock period
     * @param lockUpPeriod The lock-up period in seconds
     * @return apy The estimated APY (scaled by 100, e.g., 1500 = 15.00%)
     */
    function calculateEstimatedAPY(uint256 lockUpPeriod) external view returns (uint256 apy);

    /**
     * @notice Claim rewards for a specific stake
     * @param stakeId The stake ID to claim rewards for
     * @return rewardAmount The amount of rewards claimed
     */
    function claimRewards(uint256 stakeId) external returns (uint256 rewardAmount);

    /**
     * @notice Claim rewards for all active stakes
     * @return totalRewards Total rewards claimed
     */
    function claimAllRewards() external returns (uint256 totalRewards);

    /**
     * @notice Get comprehensive reward summary for a user
     * @param user The user address
     * @return summary Detailed reward information
     */
    function getUserRewardSummary(address user) external view returns (RewardSummary memory summary);

    /**
     * @notice Get reward details for a specific stake
     * @param user The user address
     * @param stakeId The stake ID
     * @return details Detailed reward information for the stake
     */
    function getStakeRewardDetails(address user, uint256 stakeId)
        external
        view
        returns (StakeRewardDetails memory details);

    // -------------------------------------------------------------
    // Admin Functions
    // -------------------------------------------------------------

    /**
     * @notice Fund the reward pool
     * @param amount Amount to add to the reward pool
     */
    function fundRewardPool(uint256 amount) external;

    /**
     * @notice Update the base reward rate
     * @param newRate New base reward rate per second
     */
    function updateBaseRewardRate(uint256 newRate) external;

    /**
     * @notice Get current reward pool balance
     * @return balance Current reward pool balance
     */
    function rewardPool() external view returns (uint256 balance);

    /**
     * @notice Get current base reward rate
     * @return rate Current base reward rate per second
     */
    function baseRewardRate() external view returns (uint256 rate);
}
