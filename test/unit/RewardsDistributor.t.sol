// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {StakingVault} from "src/StakingVault.sol";
import {RewardsDistributor} from "src/RewardsDistributor.sol";
import {IRewardsDistributor} from "src/interfaces/IRewardsDistributor.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract RewardsDistributorTest is Test {
    StakingVault public stakingVault;
    RewardsDistributor public rewardsDistributor;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant BASE_REWARD_RATE = uint256(1e18) / uint256(365 days); // 1 SAPIEN per year per 1 SAPIEN staked
    uint256 public constant MINIMUM_STAKE = 1000e18; // 1,000 SAPIEN

    event RewardsClaimed(address indexed user, uint256 indexed stakeId, uint256 amount);
    event RewardPoolFunded(uint256 amount);
    event BaseRewardRateUpdated(uint256 oldRate, uint256 newRate);

    function setUp() public {
        // Deploy mock SAPIEN token
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        // Deploy StakingVault
        StakingVault stakingVaultImpl = new StakingVault();
        bytes memory stakingInitData =
            abi.encodeWithSelector(StakingVault.initialize.selector, address(sapienToken), admin, treasury);
        ERC1967Proxy stakingVaultProxy = new ERC1967Proxy(address(stakingVaultImpl), stakingInitData);
        stakingVault = StakingVault(address(stakingVaultProxy));

        // Deploy RewardsDistributor
        RewardsDistributor rewardsDistributorImpl = new RewardsDistributor();
        bytes memory rewardsInitData = abi.encodeWithSelector(
            RewardsDistributor.initialize.selector, address(stakingVault), address(sapienToken), admin, BASE_REWARD_RATE
        );
        ERC1967Proxy rewardsDistributorProxy = new ERC1967Proxy(address(rewardsDistributorImpl), rewardsInitData);
        rewardsDistributor = RewardsDistributor(address(rewardsDistributorProxy));

        // Mint tokens to users
        sapienToken.mint(user1, 10000e18);
        sapienToken.mint(user2, 10000e18);
        sapienToken.mint(admin, 1000000e18); // For funding reward pool

        // Fund reward pool
        vm.startPrank(admin);
        sapienToken.approve(address(rewardsDistributor), 1000000e18);
        rewardsDistributor.fundRewardPool(100000e18); // 100k SAPIEN for rewards
        vm.stopPrank();
    }

    function test_Initialization() public view {
        assertEq(address(rewardsDistributor.stakingVault()), address(stakingVault));
        assertEq(address(rewardsDistributor.rewardToken()), address(sapienToken));
        assertEq(rewardsDistributor.baseRewardRate(), BASE_REWARD_RATE);
        assertEq(rewardsDistributor.rewardPool(), 100000e18);
        assertTrue(rewardsDistributor.hasRole(rewardsDistributor.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_CalculateEstimatedAPY() public view {
        // Test APY calculations for different lock periods
        uint256 apy30 = rewardsDistributor.calculateEstimatedAPY(30 days);
        uint256 apy90 = rewardsDistributor.calculateEstimatedAPY(90 days);
        uint256 apy180 = rewardsDistributor.calculateEstimatedAPY(180 days);
        uint256 apy365 = rewardsDistributor.calculateEstimatedAPY(365 days);

        // APY should increase with longer lock periods due to multipliers
        assertGt(apy90, apy30);
        assertGt(apy180, apy90);
        assertGt(apy365, apy180);

        // Base APY (1x multiplier) should be around 100% (10000 basis points)
        // With 30-day multiplier of 1.05x, APY should be ~105%
        assertApproxEqRel(apy30, 10500, 0.01e18); // 1% tolerance
    }

    function test_StakeAndCalculateRewards() public {
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, 30 days);
        vm.stopPrank();

        // No rewards immediately after staking
        assertEq(rewardsDistributor.calculatePendingRewards(user1, 1), 0);

        // Fast forward 1 day
        vm.warp(block.timestamp + 1 days);

        // Calculate expected rewards
        uint256 expectedRewards = (BASE_REWARD_RATE * 1 days * MINIMUM_STAKE * 10500) / (1e18 * 10000);
        uint256 actualRewards = rewardsDistributor.calculatePendingRewards(user1, 1);

        assertApproxEqRel(actualRewards, expectedRewards, 0.001e18); // 0.1% tolerance
    }

    function test_ClaimRewards() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, 30 days);
        vm.stopPrank();

        // Fast forward 7 days
        vm.warp(block.timestamp + 7 days);

        uint256 pendingRewards = rewardsDistributor.calculatePendingRewards(user1, 1);
        assertGt(pendingRewards, 0);

        uint256 balanceBefore = sapienToken.balanceOf(user1);

        // Claim rewards
        vm.prank(user1);
        vm.expectEmit(true, true, false, true);
        emit RewardsClaimed(user1, 1, pendingRewards);
        uint256 claimedAmount = rewardsDistributor.claimRewards(1);

        assertEq(claimedAmount, pendingRewards);
        assertEq(sapienToken.balanceOf(user1), balanceBefore + pendingRewards);
        assertEq(rewardsDistributor.calculatePendingRewards(user1, 1), 0);
    }

    function test_ClaimAllRewards() public {
        // Create single stake (new system only allows one stake per user)
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, 30 days);
        vm.stopPrank();

        // Fast forward 10 days
        vm.warp(block.timestamp + 10 days);

        uint256 totalPending = rewardsDistributor.calculateUserTotalPendingRewards(user1);
        assertGt(totalPending, 0);

        uint256 balanceBefore = sapienToken.balanceOf(user1);

        // Claim all rewards
        vm.prank(user1);
        uint256 totalClaimed = rewardsDistributor.claimAllRewards();

        assertEq(totalClaimed, totalPending);
        assertEq(sapienToken.balanceOf(user1), balanceBefore + totalPending);
        assertEq(rewardsDistributor.calculateUserTotalPendingRewards(user1), 0);
    }

    function test_VotingPowerCalculation() public {
        // Stake with a specific multiplier
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, 365 days); // 1.50x multiplier
        vm.stopPrank();

        uint256 votingPower = rewardsDistributor.calculateUserVotingPower(user1);

        // Expected: 1000 * 1.50 = 1500 SAPIEN voting power
        uint256 expectedVotingPower = MINIMUM_STAKE * 15000 / 10000;
        assertEq(votingPower, expectedVotingPower);
    }

    function test_GetUserRewardSummary() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, 30 days);
        vm.stopPrank();

        // Fast forward and claim some rewards
        vm.warp(block.timestamp + 5 days);
        vm.prank(user1);
        rewardsDistributor.claimRewards(1);

        // Fast forward more
        vm.warp(block.timestamp + 5 days);

        IRewardsDistributor.RewardSummary memory summary = rewardsDistributor.getUserRewardSummary(user1);

        assertEq(summary.activeStakeCount, 1);
        assertGt(summary.totalPendingRewards, 0);
        assertGt(summary.totalClaimedRewards, 0);
        assertGt(summary.totalVotingPower, 0);
        assertGt(summary.averageAPY, 0);
    }

    function test_GetStakeRewardDetails() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, 180 days);
        vm.stopPrank();

        // Fast forward
        vm.warp(block.timestamp + 3 days);

        IRewardsDistributor.StakeRewardDetails memory details = rewardsDistributor.getStakeRewardDetails(user1, 1);

        assertGt(details.pendingRewards, 0);
        assertEq(details.claimedRewards, 0);
        assertEq(details.lastClaim, 0);
        assertGt(details.estimatedAPY, 0);
        assertGt(details.votingPower, 0);
        assertEq(details.totalEarned, details.pendingRewards);
    }

    function test_FundRewardPool() public {
        uint256 initialPool = rewardsDistributor.rewardPool();
        uint256 fundAmount = 50000e18;

        vm.startPrank(admin);
        sapienToken.approve(address(rewardsDistributor), fundAmount);

        vm.expectEmit(false, false, false, true);
        emit RewardPoolFunded(fundAmount);
        rewardsDistributor.fundRewardPool(fundAmount);
        vm.stopPrank();

        assertEq(rewardsDistributor.rewardPool(), initialPool + fundAmount);
    }

    function test_UpdateBaseRewardRate() public {
        uint256 oldRate = rewardsDistributor.baseRewardRate();
        uint256 newRate = oldRate * 2;

        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit BaseRewardRateUpdated(oldRate, newRate);
        rewardsDistributor.updateBaseRewardRate(newRate);

        assertEq(rewardsDistributor.baseRewardRate(), newRate);
    }

    function test_InsufficientRewardPool() public {
        // Get the reward pool amount first
        uint256 poolAmount = rewardsDistributor.rewardPool();

        // Drain the reward pool
        vm.prank(admin);
        rewardsDistributor.emergencyWithdraw(poolAmount);

        // Stake and try to claim
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, 30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        vm.prank(user1);
        vm.expectRevert("Insufficient reward pool");
        rewardsDistributor.claimRewards(1);
    }

    function test_UnauthorizedAccess() public {
        // Test unauthorized funding
        vm.prank(user1);
        vm.expectRevert("Only rewards manager can perform this");
        rewardsDistributor.fundRewardPool(1000e18);

        // Test unauthorized rate update
        vm.prank(user1);
        vm.expectRevert("Only rewards manager can perform this");
        rewardsDistributor.updateBaseRewardRate(1e18);

        // Test unauthorized emergency withdraw - now uses OpenZeppelin AccessControl
        vm.prank(user1);
        vm.expectRevert(); // Just expect any revert - the specific error format may vary
        rewardsDistributor.emergencyWithdraw(1000e18);
    }

    function test_PauseUnpause() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, 30 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        // Pause contract
        vm.prank(admin);
        rewardsDistributor.pause();

        // Try to claim while paused
        vm.prank(user1);
        vm.expectRevert("EnforcedPause()");
        rewardsDistributor.claimRewards(1);

        // Unpause and claim
        vm.prank(admin);
        rewardsDistributor.unpause();

        vm.prank(user1);
        rewardsDistributor.claimRewards(1); // Should work now
    }

    function test_MultipleUsersRewards() public {
        // Both users stake
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, 30 days);
        vm.stopPrank();

        vm.startPrank(user2);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE * 2);
        stakingVault.stake(MINIMUM_STAKE * 2, 90 days);
        vm.stopPrank();

        vm.warp(block.timestamp + 7 days);

        // User2 should have more rewards due to higher stake and multiplier
        uint256 rewards1 = rewardsDistributor.calculatePendingRewards(user1, 1);
        uint256 rewards2 = rewardsDistributor.calculatePendingRewards(user2, 1);

        assertGt(rewards2, rewards1);

        // Both should be able to claim independently
        vm.prank(user1);
        rewardsDistributor.claimRewards(1);

        vm.prank(user2);
        rewardsDistributor.claimRewards(1);
    }

    function test_AdminCanPause() public {
        // Test that admin can call pause (which also uses onlyPauser, but admin has that role too)
        vm.prank(admin);
        rewardsDistributor.pause();

        // Test that admin can unpause
        vm.prank(admin);
        rewardsDistributor.unpause();
    }

    function test_AdminCanAuthorizeUpgrade() public {
        // Test that admin can call authorizeUpgrade (which uses onlyRole(DEFAULT_ADMIN_ROLE))
        vm.prank(admin);
        rewardsDistributor.authorizeUpgrade(address(0x123));
    }
}
