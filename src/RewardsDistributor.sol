// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {IStakingVault} from "src/interfaces/IStakingVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {AccessControlUpgradeable} from
    "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";

/// @title RewardsDistributor
/// @notice Manages reward distribution for staked tokens using multipliers and time-based calculations
contract RewardsDistributor is
    IRewardsDistributor,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    /// @dev The StakingVault contract interface
    IStakingVault public stakingVault;

    /// @dev The reward token (SAPIEN)
    IERC20 public rewardToken;

    /// @dev Total reward pool balance
    uint256 public rewardPool;

    /// @dev Base reward rate per second (scaled by 1e18)
    uint256 public baseRewardRate;

    /// @dev Mapping of user => stakeId => last claim timestamp
    mapping(address => mapping(uint256 => uint256)) public lastClaimTime;

    /// @dev Mapping of user => stakeId => total claimed rewards
    mapping(address => mapping(uint256 => uint256)) public totalClaimedRewards;

    /// @dev Role for managing rewards
    bytes32 public constant REWARDS_MANAGER_ROLE = keccak256("REWARDS_MANAGER_ROLE");

    /// @dev Role for pausing/unpausing the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @dev Mapping of owner addresses to whether they are authorized to upgrade
    mapping(address => bool) private _upgradeAuthorized;

    /// @dev Multiplier precision (10000 = 100.00%)
    uint256 private constant MULTIPLIER_PRECISION = 10000;

    /// @dev Seconds in a year for APY calculations
    uint256 private constant SECONDS_PER_YEAR = 365 days;

    // -------------------------------------------------------------
    // Initialization (UUPS)
    // -------------------------------------------------------------

    /**
     * @notice Initializes the RewardsDistributor contract
     * @param _stakingVault Address of the StakingVault contract
     * @param _rewardToken Address of the reward token (SAPIEN)
     * @param _admin Address of the admin multisig
     * @param _baseRewardRate Initial base reward rate per second
     */
    function initialize(address _stakingVault, address _rewardToken, address _admin, uint256 _baseRewardRate)
        public
        initializer
    {
        require(_stakingVault != address(0), "Zero address not allowed for staking vault");
        require(_rewardToken != address(0), "Zero address not allowed for reward token");
        require(_admin != address(0), "Zero address not allowed for admin");

        __Pausable_init();
        __AccessControl_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(REWARDS_MANAGER_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
        _revokeRole(DEFAULT_ADMIN_ROLE, msg.sender);

        stakingVault = IStakingVault(_stakingVault);
        rewardToken = IERC20(_rewardToken);
        baseRewardRate = _baseRewardRate;
    }

    /**
     * @notice Authorizes an upgrade of this contract to a new implementation (UUPS)
     * @param newImplementation The address of the new contract implementation
     */
    function authorizeUpgrade(address newImplementation) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _upgradeAuthorized[newImplementation] = true;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_upgradeAuthorized[newImplementation], "Upgrade not authorized");
        _upgradeAuthorized[newImplementation] = false;
    }

    // -------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------

    modifier onlyRewardsManager() {
        require(hasRole(REWARDS_MANAGER_ROLE, msg.sender), "Only rewards manager can perform this");
        _;
    }

    modifier onlyPauser() {
        require(hasRole(PAUSER_ROLE, msg.sender), "Only pauser can perform this");
        _;
    }

    // -------------------------------------------------------------
    // Core Reward Calculation Functions
    // -------------------------------------------------------------

    /**
     * @notice Calculate pending rewards for a specific stake
     * @param user The user address
     * @param stakeId The stake ID
     * @return pendingReward The amount of pending rewards
     */
    function calculatePendingRewards(address user, uint256 stakeId) public view returns (uint256 pendingReward) {
        // In the simplified system, only stakeId 1 is valid
        if (stakeId != 1 || !stakingVault.hasActiveStake(user)) {
            return 0;
        }

        // Get stake details from StakingVault
        (uint256 amount,, uint256 startTime, uint256 multiplier,, bool isActive) =
            stakingVault.getStakeDetails(user, stakeId);

        if (!isActive || amount == 0) {
            return 0;
        }

        // Calculate time elapsed since last claim (or stake start)
        uint256 lastClaim = lastClaimTime[user][stakeId];
        if (lastClaim == 0) {
            lastClaim = startTime;
        }

        uint256 timeElapsed = block.timestamp - lastClaim;
        if (timeElapsed == 0) {
            return 0;
        }

        // Calculate base reward: baseRewardRate * timeElapsed * stakedAmount
        uint256 baseReward = (baseRewardRate * timeElapsed * amount) / 1e18;

        // Apply multiplier: baseReward * multiplier / MULTIPLIER_PRECISION
        pendingReward = (baseReward * multiplier) / MULTIPLIER_PRECISION;
    }

    /**
     * @notice Calculate total pending rewards for all user stakes
     * @param user The user address
     * @return totalPending Total pending rewards across all stakes
     */
    function calculateUserTotalPendingRewards(address user) public view returns (uint256 totalPending) {
        // In simplified system, users have at most one stake with ID 1
        if (stakingVault.hasActiveStake(user)) {
            totalPending = calculatePendingRewards(user, 1);
        }
    }

    /**
     * @notice Calculate voting power for a user based on staked amounts and multipliers
     * @param user The user address
     * @return totalVotingPower Total voting power (stakedAmount × multiplier)
     */
    function calculateUserVotingPower(address user) public view returns (uint256 totalVotingPower) {
        (uint256[] memory stakeIds, uint256[] memory amounts, uint256[] memory multipliers,) =
            stakingVault.getUserActiveStakes(user);

        for (uint256 i = 0; i < stakeIds.length; i++) {
            // Voting power = stakedAmount * multiplier / MULTIPLIER_PRECISION
            totalVotingPower += (amounts[i] * multipliers[i]) / MULTIPLIER_PRECISION;
        }
    }

    /**
     * @notice Calculate estimated APY for a lock period
     * @param lockUpPeriod The lock-up period in seconds
     * @return apy The estimated APY (scaled by 100, e.g., 1500 = 15.00%)
     */
    function calculateEstimatedAPY(uint256 lockUpPeriod) public view returns (uint256 apy) {
        uint256 multiplier = stakingVault.getMultiplierForPeriod(lockUpPeriod);

        // APY = (baseRewardRate * SECONDS_PER_YEAR * multiplier) / MULTIPLIER_PRECISION
        // Then scale by 10000 to get percentage with 2 decimal places
        apy = (baseRewardRate * SECONDS_PER_YEAR * multiplier * 10000) / (MULTIPLIER_PRECISION * 1e18);
    }

    // -------------------------------------------------------------
    // Reward Claiming Functions
    // -------------------------------------------------------------

    /**
     * @notice Claim rewards for a specific stake
     * @param stakeId The stake ID to claim rewards for
     * @return rewardAmount The amount of rewards claimed
     */
    function claimRewards(uint256 stakeId) external whenNotPaused nonReentrant returns (uint256 rewardAmount) {
        require(stakeId == 1, "Invalid stake ID");
        require(stakingVault.hasActiveStake(msg.sender), "No active stake found");

        rewardAmount = calculatePendingRewards(msg.sender, stakeId);
        require(rewardAmount > 0, "No rewards to claim");
        require(rewardAmount <= rewardPool, "Insufficient reward pool");

        // Update claim tracking
        lastClaimTime[msg.sender][stakeId] = block.timestamp;
        totalClaimedRewards[msg.sender][stakeId] += rewardAmount;
        rewardPool -= rewardAmount;

        // Transfer rewards
        rewardToken.safeTransfer(msg.sender, rewardAmount);

        emit RewardsClaimed(msg.sender, stakeId, rewardAmount);
    }

    /**
     * @notice Claim rewards for all active stakes
     * @return totalRewards Total rewards claimed
     */
    function claimAllRewards() external whenNotPaused nonReentrant returns (uint256 totalRewards) {
        // In simplified system, users have at most one stake with ID 1
        if (stakingVault.hasActiveStake(msg.sender)) {
            uint256 rewardAmount = calculatePendingRewards(msg.sender, 1);
            if (rewardAmount > 0 && rewardAmount <= rewardPool) {
                // Update claim tracking
                lastClaimTime[msg.sender][1] = block.timestamp;
                totalClaimedRewards[msg.sender][1] += rewardAmount;
                rewardPool -= rewardAmount;
                totalRewards = rewardAmount;

                emit RewardsClaimed(msg.sender, 1, rewardAmount);
            }
        }

        if (totalRewards > 0) {
            rewardToken.safeTransfer(msg.sender, totalRewards);
        }
    }

    // -------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------

    /**
     * @notice Get comprehensive reward summary for a user
     * @param user The user address
     * @return summary Detailed reward information
     */
    function getUserRewardSummary(address user) external view returns (RewardSummary memory summary) {
        summary.totalPendingRewards = calculateUserTotalPendingRewards(user);
        summary.totalVotingPower = calculateUserVotingPower(user);

        // Calculate total claimed rewards and average APY
        if (stakingVault.hasActiveStake(user)) {
            summary.activeStakeCount = 1;
            summary.totalClaimedRewards = totalClaimedRewards[user][1];

            (uint256 amount,,, uint256 multiplier,, bool isActive) = stakingVault.getStakeDetails(user, 1);

            if (isActive && amount > 0) {
                // Calculate APY based on current multiplier
                summary.averageAPY =
                    (baseRewardRate * SECONDS_PER_YEAR * multiplier * 10000) / (MULTIPLIER_PRECISION * 1e18);
            }
        }
    }

    /**
     * @notice Get reward details for a specific stake
     * @param user The user address
     * @param stakeId The stake ID
     * @return details Detailed reward information for the stake
     */
    function getStakeRewardDetails(address user, uint256 stakeId)
        external
        view
        returns (StakeRewardDetails memory details)
    {
        details.pendingRewards = calculatePendingRewards(user, stakeId);
        details.claimedRewards = totalClaimedRewards[user][stakeId];
        details.lastClaim = lastClaimTime[user][stakeId];
        details.totalEarned = details.pendingRewards + details.claimedRewards;

        (uint256 amount, uint256 lockUpPeriod,, uint256 multiplier,, bool isActive) =
            stakingVault.getStakeDetails(user, stakeId);

        if (isActive) {
            details.estimatedAPY = calculateEstimatedAPY(lockUpPeriod);
            details.votingPower = (amount * multiplier) / MULTIPLIER_PRECISION;
        }
    }

    // -------------------------------------------------------------
    // Admin Functions
    // -------------------------------------------------------------

    /**
     * @notice Fund the reward pool
     * @param amount Amount to add to the reward pool
     */
    function fundRewardPool(uint256 amount) external onlyRewardsManager {
        require(amount > 0, "Amount must be greater than 0");

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        rewardPool += amount;

        emit RewardPoolFunded(amount);
    }

    /**
     * @notice Update the base reward rate
     * @param newRate New base reward rate per second
     */
    function updateBaseRewardRate(uint256 newRate) external onlyRewardsManager {
        uint256 oldRate = baseRewardRate;
        baseRewardRate = newRate;

        emit BaseRewardRateUpdated(oldRate, newRate);
    }

    /**
     * @notice Pause the contract
     */
    function pause() external onlyPauser {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyPauser {
        _unpause();
    }

    /**
     * @notice Emergency withdraw function for admin
     * @param amount Amount to withdraw from reward pool
     */
    function emergencyWithdraw(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(amount <= rewardPool, "Amount exceeds reward pool");

        rewardPool -= amount;
        rewardToken.safeTransfer(msg.sender, amount);
        emit EmergencyWithdraw(amount, rewardPool);
    }
}
