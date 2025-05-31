// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {StakingVault} from "src/StakingVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract StakingVaultTest is Test {
    StakingVault public stakingVault;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    uint256 public constant MINIMUM_STAKE = 1000e18; // 1,000 SAPIEN
    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 public constant EARLY_WITHDRAWAL_PENALTY = 20; // 20%
    uint256 public constant MINIMUM_LOCKUP_INCREASE = 7 days;

    // Lock periods
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    // Base multipliers (with 2 decimal precision in basis points)
    uint256 public constant MULTIPLIER_30_DAYS = 10500; // 105.00%
    uint256 public constant MULTIPLIER_90_DAYS = 11000; // 110.00%
    uint256 public constant MULTIPLIER_180_DAYS = 12500; // 125.00%
    uint256 public constant MULTIPLIER_365_DAYS = 15000; // 150.00%

    // Updated events for new system
    event Staked(address indexed user, uint256 amount, uint256 effectiveMultiplier, uint256 lockUpPeriod);
    event AmountIncreased(
        address indexed user, uint256 additionalAmount, uint256 newTotalAmount, uint256 newEffectiveMultiplier
    );
    event LockupIncreased(
        address indexed user, uint256 additionalLockup, uint256 newEffectiveLockup, uint256 newEffectiveMultiplier
    );
    event UnstakingInitiated(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);
    event InstantUnstake(address indexed user, uint256 amount, uint256 penalty);
    event SapienTreasuryUpdated(address indexed newSapienTreasury);

    function setUp() public {
        // Deploy mock SAPIEN token
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        // Deploy StakingVault
        StakingVault stakingVaultImpl = new StakingVault();
        bytes memory initData =
            abi.encodeWithSelector(StakingVault.initialize.selector, address(sapienToken), admin, treasury);
        ERC1967Proxy stakingVaultProxy = new ERC1967Proxy(address(stakingVaultImpl), initData);
        stakingVault = StakingVault(address(stakingVaultProxy));

        // Mint tokens to users
        sapienToken.mint(user1, 100000e18);
        sapienToken.mint(user2, 100000e18);
        sapienToken.mint(user3, 100000e18);
    }

    // =============================================================================
    // INITIALIZATION TESTS
    // =============================================================================

    function test_Initialization() public view {
        assertEq(address(stakingVault.sapienToken()), address(sapienToken));
        assertEq(stakingVault.sapienTreasury(), treasury);
        assertEq(stakingVault.totalStaked(), 0);
        assertTrue(stakingVault.hasRole(stakingVault.DEFAULT_ADMIN_ROLE(), admin));
    }

    // =============================================================================
    // STAKING TESTS
    // =============================================================================

    function test_StakeMinimumAmount() public {
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);

        vm.expectEmit(true, false, false, true);
        emit Staked(user1, MINIMUM_STAKE, MULTIPLIER_30_DAYS, LOCK_30_DAYS);

        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        assertEq(stakingVault.totalStaked(), MINIMUM_STAKE);
        assertEq(sapienToken.balanceOf(address(stakingVault)), MINIMUM_STAKE);
        assertEq(sapienToken.balanceOf(user1), 100000e18 - MINIMUM_STAKE);
        assertTrue(stakingVault.hasActiveStake(user1));
    }

    function test_StakeAllLockPeriods() public {
        uint256[] memory lockPeriods = new uint256[](4);
        lockPeriods[0] = LOCK_30_DAYS;
        lockPeriods[1] = LOCK_90_DAYS;
        lockPeriods[2] = LOCK_180_DAYS;
        lockPeriods[3] = LOCK_365_DAYS;

        uint256[] memory expectedMultipliers = new uint256[](4);
        expectedMultipliers[0] = MULTIPLIER_30_DAYS;
        expectedMultipliers[1] = MULTIPLIER_90_DAYS;
        expectedMultipliers[2] = MULTIPLIER_180_DAYS;
        expectedMultipliers[3] = MULTIPLIER_365_DAYS;

        for (uint256 i = 0; i < lockPeriods.length; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            sapienToken.mint(user, MINIMUM_STAKE);

            vm.startPrank(user);
            sapienToken.approve(address(stakingVault), MINIMUM_STAKE);

            vm.expectEmit(true, false, false, true);
            emit Staked(user, MINIMUM_STAKE, expectedMultipliers[i], lockPeriods[i]);

            stakingVault.stake(MINIMUM_STAKE, lockPeriods[i]);
            vm.stopPrank();

            // Verify stake details
            (
                uint256 userTotalStaked,
                uint256 totalUnlocked,
                uint256 totalLocked,
                uint256 totalInCooldown,
                uint256 totalReadyForUnstake,
                uint256 effectiveMultiplier,
                uint256 effectiveLockUpPeriod,
                uint256 timeUntilUnlock
            ) = stakingVault.getUserStakingSummary(user);

            assertEq(userTotalStaked, MINIMUM_STAKE);
            assertEq(effectiveMultiplier, expectedMultipliers[i]);
            assertEq(effectiveLockUpPeriod, lockPeriods[i]);
            assertEq(totalLocked, MINIMUM_STAKE); // All should be locked initially
            assertEq(totalUnlocked, 0);
            assertEq(totalInCooldown, 0);
            assertEq(totalReadyForUnstake, 0);
            assertEq(timeUntilUnlock, lockPeriods[i]);
        }

        assertEq(stakingVault.totalStaked(), MINIMUM_STAKE * 4);
    }

    function test_StakeMultipleTimesAddsToSingleStake() public {
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE * 3);

        // First stake: 1000 tokens, 30 days
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);

        // Advance time a bit
        vm.warp(block.timestamp + 10 days);

        // Second stake: 2000 tokens, 90 days (should combine with existing)
        stakingVault.stake(MINIMUM_STAKE * 2, LOCK_90_DAYS);
        vm.stopPrank();

        // Should have single combined stake
        (uint256 userTotalStaked,,,,,, uint256 effectiveLockUpPeriod,) = stakingVault.getUserStakingSummary(user1);

        assertEq(userTotalStaked, MINIMUM_STAKE * 3);

        // Effective lockup should be weighted average: (30 * 1000 + 90 * 2000) / 3000 = 70 days
        uint256 expectedLockup = (LOCK_30_DAYS * MINIMUM_STAKE + LOCK_90_DAYS * MINIMUM_STAKE * 2) / (MINIMUM_STAKE * 3);
        assertEq(effectiveLockUpPeriod, expectedLockup);

        assertEq(stakingVault.totalStaked(), MINIMUM_STAKE * 3);
    }

    function test_RevertStakeBelowMinimum() public {
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE - 1);

        vm.expectRevert("Minimum 1,000 SAPIEN required");
        stakingVault.stake(MINIMUM_STAKE - 1, LOCK_30_DAYS);
        vm.stopPrank();
    }

    function test_RevertStakeInvalidLockPeriod() public {
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);

        vm.expectRevert("Invalid lock-up period");
        stakingVault.stake(MINIMUM_STAKE, 15 days); // Invalid period
        vm.stopPrank();
    }

    function test_RevertStakeWhenPaused() public {
        vm.prank(admin);
        stakingVault.pause();

        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);

        vm.expectRevert("EnforcedPause()");
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();
    }

    // =============================================================================
    // INCREASE AMOUNT TESTS
    // =============================================================================

    function test_IncreaseAmount() public {
        // Initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE * 3);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);

        // Advance time a bit
        vm.warp(block.timestamp + 5 days);

        // Increase amount
        vm.expectEmit(true, false, false, true);
        emit AmountIncreased(user1, MINIMUM_STAKE * 2, MINIMUM_STAKE * 3, MULTIPLIER_30_DAYS);

        stakingVault.increaseAmount(MINIMUM_STAKE * 2);
        vm.stopPrank();

        (uint256 userTotalStaked,,,,, uint256 effectiveMultiplier, uint256 effectiveLockUpPeriod,) =
            stakingVault.getUserStakingSummary(user1);

        assertEq(userTotalStaked, MINIMUM_STAKE * 3);
        assertEq(effectiveMultiplier, MULTIPLIER_30_DAYS); // Should stay same
        assertEq(effectiveLockUpPeriod, LOCK_30_DAYS); // Should stay same
        assertEq(stakingVault.totalStaked(), MINIMUM_STAKE * 3);
    }

    function test_RevertIncreaseAmountNoExistingStake() public {
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);

        vm.expectRevert("No existing stake found");
        stakingVault.increaseAmount(MINIMUM_STAKE);
        vm.stopPrank();
    }

    function test_RevertIncreaseAmountDuringCooldown() public {
        // Stake and unlock
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE * 2);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Initiate unstaking
        vm.prank(user1);
        stakingVault.initiateUnstake(MINIMUM_STAKE / 2);

        // Try to increase amount during cooldown
        vm.startPrank(user1);
        vm.expectRevert("Cannot increase during cooldown");
        stakingVault.increaseAmount(MINIMUM_STAKE);
        vm.stopPrank();
    }

    // =============================================================================
    // INCREASE LOCKUP TESTS
    // =============================================================================

    function test_IncreaseLockup() public {
        // Initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Advance time partially through lockup
        vm.warp(block.timestamp + 20 days);

        // Increase lockup by 60 days (should result in 70 days total from now: 10 remaining + 60 additional)
        vm.prank(user1);

        uint256 additionalLockup = 60 days;
        uint256 expectedNewLockup = 10 days + additionalLockup; // remaining + additional

        vm.expectEmit(true, false, false, false);
        emit LockupIncreased(user1, additionalLockup, expectedNewLockup, 0); // Don't check exact multiplier

        stakingVault.increaseLockup(additionalLockup);

        (,,,,,, uint256 effectiveLockUpPeriod, uint256 timeUntilUnlock) = stakingVault.getUserStakingSummary(user1);

        assertEq(effectiveLockUpPeriod, expectedNewLockup);
        assertEq(timeUntilUnlock, expectedNewLockup); // Should be reset to new period
    }

    function test_IncreaseLockupCapAt365Days() public {
        // Initial stake with 180 days
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_180_DAYS);
        vm.stopPrank();

        // Try to increase by 300 days (would exceed 365 day cap)
        vm.prank(user1);
        stakingVault.increaseLockup(300 days);

        (,,,,,, uint256 effectiveLockUpPeriod,) = stakingVault.getUserStakingSummary(user1);

        // Should be capped at 365 days
        assertEq(effectiveLockUpPeriod, LOCK_365_DAYS);
    }

    function test_RevertIncreaseLockupBelowMinimum() public {
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert("Minimum 7 days increase required");
        stakingVault.increaseLockup(6 days);
    }

    function test_RevertIncreaseLockupNoExistingStake() public {
        vm.prank(user1);
        vm.expectRevert("No existing stake found");
        stakingVault.increaseLockup(MINIMUM_LOCKUP_INCREASE);
    }

    // =============================================================================
    // UNSTAKING FLOW TESTS
    // =============================================================================

    function test_CompleteUnstakingFlow() public {
        // 1. Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // 2. Fast forward past lock period
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // 3. Initiate unstaking
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit UnstakingInitiated(user1, MINIMUM_STAKE);
        stakingVault.initiateUnstake(MINIMUM_STAKE);

        // Verify cooldown started
        (, /* totalUnlocked */, /* totalLocked */, uint256 totalInCooldown,,,,) =
            stakingVault.getUserStakingSummary(user1);
        assertEq(totalInCooldown, MINIMUM_STAKE);

        // 4. Fast forward past cooldown period
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // 5. Complete unstaking
        uint256 balanceBefore = sapienToken.balanceOf(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Unstaked(user1, MINIMUM_STAKE);
        stakingVault.unstake(MINIMUM_STAKE);

        // Verify tokens returned and stake cleaned up
        assertEq(sapienToken.balanceOf(user1), balanceBefore + MINIMUM_STAKE);
        assertEq(stakingVault.totalStaked(), 0);
        assertFalse(stakingVault.hasActiveStake(user1));
    }

    function test_PartialUnstaking() public {
        uint256 stakeAmount = MINIMUM_STAKE * 5;
        uint256 unstakeAmount = MINIMUM_STAKE * 2;

        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Fast forward past lock period
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Initiate partial unstaking
        vm.prank(user1);
        stakingVault.initiateUnstake(unstakeAmount);

        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // Complete partial unstaking
        uint256 balanceBefore = sapienToken.balanceOf(user1);

        vm.prank(user1);
        stakingVault.unstake(unstakeAmount);

        // Verify partial unstaking
        assertEq(sapienToken.balanceOf(user1), balanceBefore + unstakeAmount);
        assertEq(stakingVault.totalStaked(), stakeAmount - unstakeAmount);

        (uint256 userTotalStaked,,,,,,,) = stakingVault.getUserStakingSummary(user1);
        assertEq(userTotalStaked, stakeAmount - unstakeAmount);
        assertTrue(stakingVault.hasActiveStake(user1));
    }

    // =============================================================================
    // INSTANT UNSTAKING TESTS
    // =============================================================================

    function test_InstantUnstake() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Instant unstake while still locked
        uint256 expectedPenalty = (MINIMUM_STAKE * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 expectedPayout = MINIMUM_STAKE - expectedPenalty;

        uint256 userBalanceBefore = sapienToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit InstantUnstake(user1, expectedPayout, expectedPenalty);
        stakingVault.instantUnstake(MINIMUM_STAKE);

        // Verify penalty and payout
        assertEq(sapienToken.balanceOf(user1), userBalanceBefore + expectedPayout);
        assertEq(sapienToken.balanceOf(treasury), treasuryBalanceBefore + expectedPenalty);
        assertEq(stakingVault.totalStaked(), 0);
        assertFalse(stakingVault.hasActiveStake(user1));
    }

    function test_InstantUnstakePartial() public {
        uint256 stakeAmount = MINIMUM_STAKE * 5;
        uint256 instantUnstakeAmount = MINIMUM_STAKE * 2;

        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Partial instant unstake
        uint256 expectedPenalty = (instantUnstakeAmount * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 expectedPayout = instantUnstakeAmount - expectedPenalty;

        uint256 userBalanceBefore = sapienToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        vm.prank(user1);
        stakingVault.instantUnstake(instantUnstakeAmount);

        // Verify partial instant unstake
        assertEq(sapienToken.balanceOf(user1), userBalanceBefore + expectedPayout);
        assertEq(sapienToken.balanceOf(treasury), treasuryBalanceBefore + expectedPenalty);
        assertEq(stakingVault.totalStaked(), stakeAmount - instantUnstakeAmount);

        (uint256 userTotalStaked,,,,,,,) = stakingVault.getUserStakingSummary(user1);
        assertEq(userTotalStaked, stakeAmount - instantUnstakeAmount);
        assertTrue(stakingVault.hasActiveStake(user1));
    }

    function test_RevertInstantUnstakeAfterLockExpiry() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Fast forward past lock period
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Try instant unstake after lock expiry
        vm.prank(user1);
        vm.expectRevert("Lock period completed, use regular unstake");
        stakingVault.instantUnstake(MINIMUM_STAKE);
    }

    // =============================================================================
    // ERROR CONDITION TESTS
    // =============================================================================

    function test_RevertInitiateUnstakeBeforeLockExpiry() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Try to initiate unstake before lock expiry
        vm.prank(user1);
        vm.expectRevert("Stake is still locked");
        stakingVault.initiateUnstake(MINIMUM_STAKE);
    }

    function test_RevertUnstakeBeforeCooldown() public {
        // Stake and wait for lock expiry
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Initiate unstaking
        vm.prank(user1);
        stakingVault.initiateUnstake(MINIMUM_STAKE);

        // Try to unstake before cooldown completes
        vm.prank(user1);
        vm.expectRevert("Not ready for unstake");
        stakingVault.unstake(MINIMUM_STAKE);
    }

    function test_RevertUnstakeExceedsAmount() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Try to initiate unstake for more than staked
        vm.prank(user1);
        vm.expectRevert("Amount exceeds available balance");
        stakingVault.initiateUnstake(MINIMUM_STAKE + 1);
    }

    // =============================================================================
    // VIEW FUNCTION TESTS
    // =============================================================================

    function test_GetUserStakingSummary() public {
        uint256 stakeAmount = MINIMUM_STAKE * 4;

        // Create stake
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), stakeAmount);
        stakingVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Initially locked
        (
            uint256 userTotalStaked,
            uint256 totalUnlocked,
            uint256 totalLocked,
            uint256 totalInCooldown,
            uint256 totalReadyForUnstake,
            uint256 effectiveMultiplier,
            uint256 effectiveLockUpPeriod,
            uint256 timeUntilUnlock
        ) = stakingVault.getUserStakingSummary(user1);

        assertEq(userTotalStaked, stakeAmount);
        assertEq(totalLocked, stakeAmount);
        assertEq(totalUnlocked, 0);
        assertEq(totalInCooldown, 0);
        assertEq(totalReadyForUnstake, 0);
        assertEq(effectiveMultiplier, MULTIPLIER_30_DAYS);
        assertEq(effectiveLockUpPeriod, LOCK_30_DAYS);
        assertEq(timeUntilUnlock, LOCK_30_DAYS);

        // Fast forward to unlock
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Check unlocked state
        {
            (, uint256 unlocked, uint256 locked,,,,, uint256 timeLeft) = stakingVault.getUserStakingSummary(user1);
            assertEq(unlocked, stakeAmount);
            assertEq(locked, 0);
            assertEq(timeLeft, 0);
        }

        // Initiate unstaking for half
        vm.prank(user1);
        stakingVault.initiateUnstake(stakeAmount / 2);

        // Check cooldown state
        {
            (, uint256 unlocked, uint256 locked, uint256 inCooldown,,,,) = stakingVault.getUserStakingSummary(user1);
            assertEq(unlocked, stakeAmount / 2); // Half still unlocked and available
            assertEq(locked, 0);
            assertEq(inCooldown, stakeAmount / 2); // Half in cooldown
        }

        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // Check ready for unstake state
        {
            (, uint256 unlocked, uint256 locked, uint256 inCooldown, uint256 readyForUnstake,,,) =
                stakingVault.getUserStakingSummary(user1);
            assertEq(unlocked, stakeAmount / 2); // Half still unlocked and available
            assertEq(locked, 0);
            assertEq(inCooldown, stakeAmount / 2); // Half still in cooldown
            assertEq(readyForUnstake, stakeAmount / 2); // Half ready for unstake
        }
    }

    function test_GetUserStakeIds() public {
        // No stake initially
        assertFalse(stakingVault.hasActiveStake(user1));

        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Should have active stake
        assertTrue(stakingVault.hasActiveStake(user1));

        // Test getUserActiveStakes for compatibility
        (
            uint256[] memory stakeIds,
            uint256[] memory amounts,
            uint256[] memory multipliers,
            uint256[] memory lockUpPeriods
        ) = stakingVault.getUserActiveStakes(user1);

        assertEq(stakeIds.length, 1);
        assertEq(stakeIds[0], 1);
        assertEq(amounts[0], MINIMUM_STAKE);
        assertEq(multipliers[0], MULTIPLIER_30_DAYS);
        assertEq(lockUpPeriods[0], LOCK_30_DAYS);
    }

    function test_IsValidActiveStake() public {
        // No stake initially
        assertFalse(stakingVault.hasActiveStake(user1));

        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        assertTrue(stakingVault.hasActiveStake(user1));
        assertFalse(stakingVault.hasActiveStake(user2)); // Wrong user

        // Test getStakeDetails for specific stake ID
        (
            uint256 amount,
            uint256 lockUpPeriod,
            uint256 startTime,
            uint256 multiplier,
            uint256 cooldownStart,
            bool isActive
        ) = stakingVault.getStakeDetails(user1, 1);

        assertTrue(isActive);
        assertEq(amount, MINIMUM_STAKE);
        assertEq(lockUpPeriod, LOCK_30_DAYS);
        assertEq(multiplier, MULTIPLIER_30_DAYS);
        assertEq(cooldownStart, 0);
        assertGt(startTime, 0);

        // Test invalid stake ID
        (,,,,, bool invalidStakeActive) = stakingVault.getStakeDetails(user1, 2);
        assertFalse(invalidStakeActive);
    }

    function test_GetMultiplierForPeriod() public view {
        assertEq(stakingVault.getMultiplierForPeriod(LOCK_30_DAYS), MULTIPLIER_30_DAYS);
        assertEq(stakingVault.getMultiplierForPeriod(LOCK_90_DAYS), MULTIPLIER_90_DAYS);
        assertEq(stakingVault.getMultiplierForPeriod(LOCK_180_DAYS), MULTIPLIER_180_DAYS);
        assertEq(stakingVault.getMultiplierForPeriod(LOCK_365_DAYS), MULTIPLIER_365_DAYS);
    }

    function test_InterpolatedMultipliers() public {
        // Test that combining stakes with different lockup periods creates interpolated multipliers
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE * 3);

        // First stake: 1000 tokens for 30 days
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);

        // Advance time a bit
        vm.warp(block.timestamp + 5 days);

        // Second stake: 2000 tokens for 90 days (should create weighted average)
        stakingVault.stake(MINIMUM_STAKE * 2, LOCK_90_DAYS);
        vm.stopPrank();

        (,,,,, uint256 effectiveMultiplier, uint256 effectiveLockUpPeriod,) = stakingVault.getUserStakingSummary(user1);

        // The effective multiplier should be interpolated based on the weighted average lockup period
        // Expected lockup: (30 * 1000 + 90 * 2000) / 3000 = 70 days
        uint256 expectedLockup = (LOCK_30_DAYS * MINIMUM_STAKE + LOCK_90_DAYS * MINIMUM_STAKE * 2) / (MINIMUM_STAKE * 3);

        // The effective multiplier should be between 30-day and 90-day multipliers
        assertGt(effectiveMultiplier, MULTIPLIER_30_DAYS);
        assertLt(effectiveMultiplier, MULTIPLIER_90_DAYS);

        // Check that the effective lockup is approximately what we expect
        assertApproxEqAbs(effectiveLockUpPeriod, expectedLockup, 1 days);
    }

    // =============================================================================
    // ADMIN FUNCTION TESTS
    // =============================================================================

    function test_UpdateSapienTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit SapienTreasuryUpdated(newTreasury);
        stakingVault.updateSapienTreasury(newTreasury);

        assertEq(stakingVault.sapienTreasury(), newTreasury);
    }

    function test_RevertUpdateTreasuryZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert("Zero address not allowed");
        stakingVault.updateSapienTreasury(address(0));
    }

    function test_RevertUpdateTreasuryUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // AccessControl error
        stakingVault.updateSapienTreasury(makeAddr("newTreasury"));
    }

    function test_PauseUnpause() public {
        // Test pause
        vm.prank(admin);
        stakingVault.pause();

        // Test that staking is blocked when paused
        vm.startPrank(user1);
        sapienToken.approve(address(stakingVault), MINIMUM_STAKE);
        vm.expectRevert("EnforcedPause()");
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Test unpause
        vm.prank(admin);
        stakingVault.unpause();

        // Test that staking works after unpause
        vm.startPrank(user1);
        stakingVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();
    }

    function test_RevertPauseUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // AccessControl error
        stakingVault.pause();
    }
}
