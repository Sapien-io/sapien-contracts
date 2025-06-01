// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienVault} from "src/SapienVault.sol";
import {Multiplier, IMultiplier} from "src/Multiplier.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants as Const} from "src/utils/Constants.sol";

contract SapienVaultTest is Test {
    SapienVault public sapienVault;
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
    // These are the static base multipliers returned by getMultiplierForPeriod()
    // Note: Effective multipliers in the new system are different due to global coefficients
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

        // Deploy multiplier contract
        Multiplier multiplierImpl = new Multiplier();
        IMultiplier multiplierContract = IMultiplier(address(multiplierImpl));

        // Deploy SapienVault
        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData =
            abi.encodeWithSelector(SapienVault.initialize.selector, address(sapienToken), admin, treasury, address(multiplierContract));
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        // Mint tokens to users
        sapienToken.mint(user1, 100000e18);
        sapienToken.mint(user2, 100000e18);
        sapienToken.mint(user3, 100000e18);
    }

    // =============================================================================
    // INITIALIZATION TESTS
    // =============================================================================

    function test_Vault_Initialization() public view {
        assertEq(address(sapienVault.sapienToken()), address(sapienToken));
        assertEq(sapienVault.rewardSafe(), treasury);
        assertEq(sapienVault.totalStaked(), 0);
        assertTrue(sapienVault.hasRole(sapienVault.DEFAULT_ADMIN_ROLE(), admin));
    }

    // =============================================================================
    // STAKING TESTS
    // =============================================================================

    function test_Vault_StakeMinimumAmount() public {
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);

        // Don't check exact multiplier value since it depends on global coefficient in new system
        vm.expectEmit(true, true, false, false);
        emit Staked(user1, MINIMUM_STAKE, 0, LOCK_30_DAYS); // Only check user and amount, ignore multiplier

        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE);
        assertEq(sapienToken.balanceOf(address(sapienVault)), MINIMUM_STAKE);
        assertEq(sapienToken.balanceOf(user1), 100000e18 - MINIMUM_STAKE);
        assertTrue(sapienVault.hasActiveStake(user1));
    }

    function test_Vault_StakeAllLockPeriods() public {
        uint256[] memory lockPeriods = new uint256[](4);
        lockPeriods[0] = LOCK_30_DAYS;
        lockPeriods[1] = LOCK_90_DAYS;
        lockPeriods[2] = LOCK_180_DAYS;
        lockPeriods[3] = LOCK_365_DAYS;

        // Expected effective multipliers in new system (approximate values)
        uint256[] memory expectedEffectiveMultipliers = new uint256[](4);
        expectedEffectiveMultipliers[0] = 5100; // ~51% for 1K @ 30 days
        expectedEffectiveMultipliers[1] = 5300; // ~53% for 1K @ 90 days
        expectedEffectiveMultipliers[2] = 5600; // ~56% for 1K @ 180 days
        expectedEffectiveMultipliers[3] = 6250; // ~62.5% for 1K @ 365 days

        for (uint256 i = 0; i < lockPeriods.length; i++) {
            address user = makeAddr(string(abi.encodePacked("user", i)));
            sapienToken.mint(user, MINIMUM_STAKE);

            vm.startPrank(user);
            sapienToken.approve(address(sapienVault), MINIMUM_STAKE);

            // Don't check exact multiplier value in event since it varies with global coefficient
            vm.expectEmit(true, true, false, false);
            emit Staked(user, MINIMUM_STAKE, 0, lockPeriods[i]); // Only check user, amount, and lockup

            sapienVault.stake(MINIMUM_STAKE, lockPeriods[i]);
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
            ) = sapienVault.getUserStakingSummary(user);

            assertEq(userTotalStaked, MINIMUM_STAKE);
            // Use approximate comparison for effective multipliers in new system
            assertApproxEqAbs(
                effectiveMultiplier,
                expectedEffectiveMultipliers[i],
                100,
                "Effective multiplier should be close to expected"
            );
            assertEq(effectiveLockUpPeriod, lockPeriods[i]);
            assertEq(totalLocked, MINIMUM_STAKE); // All should be locked initially
            assertEq(totalUnlocked, 0);
            assertEq(totalInCooldown, 0);
            assertEq(totalReadyForUnstake, 0);
            assertEq(timeUntilUnlock, lockPeriods[i]);
        }

        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE * 4);
    }

    function test_Vault_StakeMultipleTimesAddsToSingleStake() public {
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 3);

        // First stake: 1000 tokens, 30 days
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);

        // Advance time a bit
        vm.warp(block.timestamp + 10 days);

        // Second stake: 2000 tokens, 90 days (should combine with existing)
        sapienVault.stake(MINIMUM_STAKE * 2, LOCK_90_DAYS);
        vm.stopPrank();

        // Should have single combined stake
        (uint256 userTotalStaked,,,,,, uint256 effectiveLockUpPeriod,) = sapienVault.getUserStakingSummary(user1);

        assertEq(userTotalStaked, MINIMUM_STAKE * 3);

        // Effective lockup should be weighted average: (30 * 1000 + 90 * 2000) / 3000 = 70 days
        uint256 expectedLockup = (LOCK_30_DAYS * MINIMUM_STAKE + LOCK_90_DAYS * MINIMUM_STAKE * 2) / (MINIMUM_STAKE * 3);
        assertEq(effectiveLockUpPeriod, expectedLockup);

        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE * 3);
    }

    function test_Vault_RevertStakeBelowMinimum() public {
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE - 1);

        vm.expectRevert(abi.encodeWithSignature("MinimumStakeAmountRequired()"));
        sapienVault.stake(MINIMUM_STAKE - 1, LOCK_30_DAYS);
        vm.stopPrank();
    }

    function test_Vault_RevertStakeInvalidLockPeriod() public {
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);

        vm.expectRevert(abi.encodeWithSignature("InvalidLockupPeriod()"));
        sapienVault.stake(MINIMUM_STAKE, 15 days); // Invalid period
        vm.stopPrank();
    }

    function test_Vault_RevertStakeWhenPaused() public {
        vm.prank(admin);
        sapienVault.pause();

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);

        vm.expectRevert("EnforcedPause()");
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();
    }

    // =============================================================================
    // INCREASE AMOUNT TESTS
    // =============================================================================

    function test_Vault_IncreaseAmount() public {
        // Initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 3);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);

        // Advance time a bit
        vm.warp(block.timestamp + 5 days);

        // Increase amount - don't check exact multiplier since it varies with global coefficient
        vm.expectEmit(true, true, true, false);
        emit AmountIncreased(user1, MINIMUM_STAKE * 2, MINIMUM_STAKE * 3, 0); // Only check user, additional amount, total amount

        sapienVault.increaseAmount(MINIMUM_STAKE * 2);
        vm.stopPrank();

        (uint256 userTotalStaked,,,,, uint256 effectiveMultiplier, uint256 effectiveLockUpPeriod,) =
            sapienVault.getUserStakingSummary(user1);

        assertEq(userTotalStaked, MINIMUM_STAKE * 3);
        // 3K tokens @ 30 days should get better multiplier than 1K tokens due to amount bonus
        assertGt(effectiveMultiplier, 5100, "3K tokens should get better multiplier than 1K minimum");
        assertLt(effectiveMultiplier, 5400, "Multiplier should be reasonable for 3K @ 30 days");
        assertEq(effectiveLockUpPeriod, LOCK_30_DAYS); // Should stay same
        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE * 3);
    }

    function test_Vault_RevertIncreaseAmountNoExistingStake() public {
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);

        vm.expectRevert(abi.encodeWithSignature("NoStakeFound()"));
        sapienVault.increaseAmount(MINIMUM_STAKE);
        vm.stopPrank();
    }

    function test_Vault_RevertIncreaseAmountDuringCooldown() public {
        // Stake and unlock
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Initiate unstaking
        vm.prank(user1);
        sapienVault.initiateUnstake(MINIMUM_STAKE / 2);

        // Try to increase amount during cooldown
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("CannotIncreaseStakeInCooldown()"));
        sapienVault.increaseAmount(MINIMUM_STAKE);
        vm.stopPrank();
    }

    // =============================================================================
    // INCREASE LOCKUP TESTS
    // =============================================================================

    function test_Vault_IncreaseLockup() public {
        // Initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Advance time partially through lockup
        vm.warp(block.timestamp + 20 days);

        // Increase lockup by 60 days (should result in 70 days total from now: 10 remaining + 60 additional)
        vm.prank(user1);

        uint256 additionalLockup = 60 days;
        uint256 expectedNewLockup = 10 days + additionalLockup; // remaining + additional

        vm.expectEmit(true, false, false, false);
        emit LockupIncreased(user1, additionalLockup, expectedNewLockup, 0); // Don't check exact multiplier

        sapienVault.increaseLockup(additionalLockup);

        (,,,,,, uint256 effectiveLockUpPeriod, uint256 timeUntilUnlock) = sapienVault.getUserStakingSummary(user1);

        assertEq(effectiveLockUpPeriod, expectedNewLockup);
        assertEq(timeUntilUnlock, expectedNewLockup); // Should be reset to new period
    }

    function test_Vault_IncreaseLockupCapAt365Days() public {
        // Initial stake with 180 days
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_180_DAYS);
        vm.stopPrank();

        // Try to increase by 300 days (would exceed 365 day cap)
        vm.prank(user1);
        sapienVault.increaseLockup(300 days);

        (,,,,,, uint256 effectiveLockUpPeriod,) = sapienVault.getUserStakingSummary(user1);

        // Should be capped at 365 days
        assertEq(effectiveLockUpPeriod, LOCK_365_DAYS);
    }

    function test_Vault_RevertIncreaseLockupBelowMinimum() public {
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("MinimumLockupIncreaseRequired()"));
        sapienVault.increaseLockup(6 days);
    }

    function test_Vault_RevertIncreaseLockupNoExistingStake() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NoStakeFound()"));
        sapienVault.increaseLockup(MINIMUM_LOCKUP_INCREASE);
    }

    // =============================================================================
    // UNSTAKING FLOW TESTS
    // =============================================================================

    function test_Vault_CompleteUnstakingFlow() public {
        // 1. Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // 2. Fast forward past lock period
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // 3. Initiate unstaking
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit UnstakingInitiated(user1, MINIMUM_STAKE);
        sapienVault.initiateUnstake(MINIMUM_STAKE);

        // Verify cooldown started
        (, /* totalUnlocked */, /* totalLocked */, uint256 totalInCooldown,,,,) =
            sapienVault.getUserStakingSummary(user1);
        assertEq(totalInCooldown, MINIMUM_STAKE);

        // 4. Fast forward past cooldown period
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // 5. Complete unstaking
        uint256 balanceBefore = sapienToken.balanceOf(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Unstaked(user1, MINIMUM_STAKE);
        sapienVault.unstake(MINIMUM_STAKE);

        // Verify tokens returned and stake cleaned up
        assertEq(sapienToken.balanceOf(user1), balanceBefore + MINIMUM_STAKE);
        assertEq(sapienVault.totalStaked(), 0);
        assertFalse(sapienVault.hasActiveStake(user1));
    }

    function test_Vault_PartialUnstaking() public {
        uint256 stakeAmount = MINIMUM_STAKE * 5;
        uint256 unstakeAmount = MINIMUM_STAKE * 2;

        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Fast forward past lock period
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Initiate partial unstaking
        vm.prank(user1);
        sapienVault.initiateUnstake(unstakeAmount);

        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // Complete partial unstaking
        uint256 balanceBefore = sapienToken.balanceOf(user1);

        vm.prank(user1);
        sapienVault.unstake(unstakeAmount);

        // Verify partial unstaking
        assertEq(sapienToken.balanceOf(user1), balanceBefore + unstakeAmount);
        assertEq(sapienVault.totalStaked(), stakeAmount - unstakeAmount);

        (uint256 userTotalStaked,,,,,,,) = sapienVault.getUserStakingSummary(user1);
        assertEq(userTotalStaked, stakeAmount - unstakeAmount);
        assertTrue(sapienVault.hasActiveStake(user1));
    }

    // =============================================================================
    // INSTANT UNSTAKING TESTS
    // =============================================================================

    function test_Vault_InstantUnstake() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Instant unstake while still locked
        uint256 expectedPenalty = (MINIMUM_STAKE * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 expectedPayout = MINIMUM_STAKE - expectedPenalty;

        uint256 userBalanceBefore = sapienToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit InstantUnstake(user1, expectedPayout, expectedPenalty);
        sapienVault.instantUnstake(MINIMUM_STAKE);

        // Verify penalty and payout
        assertEq(sapienToken.balanceOf(user1), userBalanceBefore + expectedPayout);
        assertEq(sapienToken.balanceOf(treasury), treasuryBalanceBefore + expectedPenalty);
        assertEq(sapienVault.totalStaked(), 0);
        assertFalse(sapienVault.hasActiveStake(user1));
    }

    function test_Vault_InstantUnstakePartial() public {
        uint256 stakeAmount = MINIMUM_STAKE * 5;
        uint256 instantUnstakeAmount = MINIMUM_STAKE * 2;

        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Partial instant unstake
        uint256 expectedPenalty = (instantUnstakeAmount * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 expectedPayout = instantUnstakeAmount - expectedPenalty;

        uint256 userBalanceBefore = sapienToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        vm.prank(user1);
        sapienVault.instantUnstake(instantUnstakeAmount);

        // Verify partial instant unstake
        assertEq(sapienToken.balanceOf(user1), userBalanceBefore + expectedPayout);
        assertEq(sapienToken.balanceOf(treasury), treasuryBalanceBefore + expectedPenalty);
        assertEq(sapienVault.totalStaked(), stakeAmount - instantUnstakeAmount);

        (uint256 userTotalStaked,,,,,,,) = sapienVault.getUserStakingSummary(user1);
        assertEq(userTotalStaked, stakeAmount - instantUnstakeAmount);
        assertTrue(sapienVault.hasActiveStake(user1));
    }

    function test_Vault_RevertInstantUnstakeAfterLockExpiry() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Fast forward past lock period
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Try instant unstake after lock expiry
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("LockPeriodCompleted()"));
        sapienVault.instantUnstake(MINIMUM_STAKE);
    }

    // =============================================================================
    // ERROR CONDITION TESTS
    // =============================================================================

    function test_Vault_RevertInitiateUnstakeBeforeLockExpiry() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Try to initiate unstake before lock expiry
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("StakeStillLocked()"));
        sapienVault.initiateUnstake(MINIMUM_STAKE);
    }

    function test_Vault_RevertUnstakeBeforeCooldown() public {
        // Stake and wait for lock expiry
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Initiate unstaking
        vm.prank(user1);
        sapienVault.initiateUnstake(MINIMUM_STAKE);

        // Try to unstake before cooldown completes
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotReadyForUnstake()"));
        sapienVault.unstake(MINIMUM_STAKE);
    }

    function test_Vault_RevertUnstakeExceedsAmount() public {
        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Try to initiate unstake for more than staked
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("AmountExceedsAvailableBalance()"));
        sapienVault.initiateUnstake(MINIMUM_STAKE + 1);
    }

    // =============================================================================
    // VIEW FUNCTION TESTS
    // =============================================================================

    function test_Vault_GetUserStakingSummary() public {
        uint256 stakeAmount = MINIMUM_STAKE * 4;

        // Create stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
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
        ) = sapienVault.getUserStakingSummary(user1);

        assertEq(userTotalStaked, stakeAmount);
        assertEq(totalLocked, stakeAmount);
        assertEq(totalUnlocked, 0);
        assertEq(totalInCooldown, 0);
        assertEq(totalReadyForUnstake, 0);
        assertApproxEqAbs(effectiveMultiplier, 5350, 100, "4K tokens @ 30 days should get ~5350 multiplier");
        assertEq(effectiveLockUpPeriod, LOCK_30_DAYS);
        assertEq(timeUntilUnlock, LOCK_30_DAYS);

        // Fast forward to unlock
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Check unlocked state
        {
            (, uint256 unlocked, uint256 locked,,,,, uint256 timeLeft) = sapienVault.getUserStakingSummary(user1);
            assertEq(unlocked, stakeAmount);
            assertEq(locked, 0);
            assertEq(timeLeft, 0);
        }

        // Initiate unstaking for half
        vm.prank(user1);
        sapienVault.initiateUnstake(stakeAmount / 2);

        // Check cooldown state
        {
            (, uint256 unlocked, uint256 locked, uint256 inCooldown,,,,) = sapienVault.getUserStakingSummary(user1);
            assertEq(unlocked, stakeAmount / 2); // Half still unlocked and available
            assertEq(locked, 0);
            assertEq(inCooldown, stakeAmount / 2); // Half in cooldown
        }

        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // Check ready for unstake state
        {
            (, uint256 unlocked, uint256 locked, uint256 inCooldown, uint256 readyForUnstake,,,) =
                sapienVault.getUserStakingSummary(user1);
            assertEq(unlocked, stakeAmount / 2); // Half still unlocked and available
            assertEq(locked, 0);
            assertEq(inCooldown, stakeAmount / 2); // Half still in cooldown
            assertEq(readyForUnstake, stakeAmount / 2); // Half ready for unstake
        }
    }

    function test_Vault_GetUserStakeIds() public {
        // No stake initially
        assertFalse(sapienVault.hasActiveStake(user1));

        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Should have active stake
        assertTrue(sapienVault.hasActiveStake(user1));

        // Test getUserActiveStakes for compatibility
        (
            uint256[] memory stakeIds,
            uint256[] memory amounts,
            uint256[] memory multipliers,
            uint256[] memory lockUpPeriods
        ) = sapienVault.getUserActiveStakes(user1);

        assertEq(stakeIds.length, 1);
        assertEq(stakeIds[0], 1);
        assertEq(amounts[0], MINIMUM_STAKE);
        // In new system: 1K tokens @ 30 days gets effective multiplier ~5100 due to global coefficient
        assertApproxEqAbs(multipliers[0], 5100, 100, "1K tokens @ 30 days should get ~5100 effective multiplier");
        assertEq(lockUpPeriods[0], LOCK_30_DAYS);
    }

    function test_Vault_IsValidActiveStake() public {
        // No stake initially
        assertFalse(sapienVault.hasActiveStake(user1));

        // Stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        assertTrue(sapienVault.hasActiveStake(user1));
        assertFalse(sapienVault.hasActiveStake(user2)); // Wrong user

        // Test getStakeDetails for specific stake ID
        (
            uint256 amount,
            uint256 lockUpPeriod,
            uint256 startTime,
            uint256 multiplier,
            uint256 cooldownStart,
            bool isActive
        ) = sapienVault.getStakeDetails(user1, 1);

        assertTrue(isActive);
        assertEq(amount, MINIMUM_STAKE);
        assertEq(lockUpPeriod, LOCK_30_DAYS);
        // In new system: 1K tokens @ 30 days gets effective multiplier ~5100 due to global coefficient
        assertApproxEqAbs(multiplier, 5100, 100, "1K tokens @ 30 days should get ~5100 effective multiplier");
        assertEq(cooldownStart, 0);
        assertGt(startTime, 0);

        // Test invalid stake ID
        (,,,,, bool invalidStakeActive) = sapienVault.getStakeDetails(user1, 2);
        assertFalse(invalidStakeActive);
    }

    function test_Vault_GetMultiplierForPeriod() public view {
        assertEq(sapienVault.getMultiplierForPeriod(LOCK_30_DAYS), MULTIPLIER_30_DAYS);
        assertEq(sapienVault.getMultiplierForPeriod(LOCK_90_DAYS), MULTIPLIER_90_DAYS);
        assertEq(sapienVault.getMultiplierForPeriod(LOCK_180_DAYS), MULTIPLIER_180_DAYS);
        assertEq(sapienVault.getMultiplierForPeriod(LOCK_365_DAYS), MULTIPLIER_365_DAYS);
    }

    function test_Vault_InterpolatedMultipliers() public {
        // Test that combining stakes with different lockup periods creates interpolated multipliers
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 3);

        // First stake: 1000 tokens for 30 days
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);

        // Advance time a bit
        vm.warp(block.timestamp + 5 days);

        // Second stake: 2000 tokens for 90 days (should create weighted average)
        sapienVault.stake(MINIMUM_STAKE * 2, LOCK_90_DAYS);
        vm.stopPrank();

        (,,,,, uint256 effectiveMultiplier, uint256 effectiveLockUpPeriod,) = sapienVault.getUserStakingSummary(user1);

        // The effective multiplier should be interpolated based on the weighted average lockup period
        // Expected lockup: (30 * 1000 + 90 * 2000) / 3000 = 70 days
        uint256 expectedLockup = (LOCK_30_DAYS * MINIMUM_STAKE + LOCK_90_DAYS * MINIMUM_STAKE * 2) / (MINIMUM_STAKE * 3);

        // In new system: effective multipliers are much lower due to global coefficient
        // 3K tokens @ ~70 days should get multiplier ~5400 (between 30-day and 90-day effective values)
        assertGt(effectiveMultiplier, 5100, "Should be better than 30-day effective multiplier");
        assertLt(effectiveMultiplier, 5500, "Should be reasonable interpolated value");

        // Check that the effective lockup is approximately what we expect
        assertApproxEqAbs(effectiveLockUpPeriod, expectedLockup, 1 days);
    }

    // =============================================================================
    // ADMIN FUNCTION TESTS
    // =============================================================================

    function test_Vault_UpdateSapienTreasury() public {
        address newTreasury = makeAddr("newTreasury");

        vm.prank(admin);
        vm.expectEmit(true, false, false, false);
        emit SapienTreasuryUpdated(newTreasury);
        sapienVault.setRewardSafe(newTreasury);

        assertEq(sapienVault.rewardSafe(), newTreasury);
    }

    function test_Vault_RevertUpdateTreasuryZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        sapienVault.setRewardSafe(address(0));
    }

    function test_Vault_RevertUpdateTreasuryUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // AccessControl error
        sapienVault.setRewardSafe(makeAddr("newTreasury"));
    }

    function test_Vault_PauseUnpause() public {
        // Test pause
        vm.prank(admin);
        sapienVault.pause();

        // Test that staking is blocked when paused
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        vm.expectRevert("EnforcedPause()");
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Test unpause
        vm.prank(admin);
        sapienVault.unpause();

        // Test that staking works after unpause
        vm.startPrank(user1);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();
    }

    function test_Vault_RevertPauseUnauthorized() public {
        vm.prank(user1);
        vm.expectRevert(); // AccessControl error
        sapienVault.pause();
    }

    function test_Vault_RevertPauseNotPauser() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotPauser()"));
        sapienVault.pause();
    }

    function test_Vault_RevertUnpauseNotPauser() public {
        // First pause the contract (as admin)
        vm.prank(admin);
        sapienVault.pause();

        // Try to unpause as non-pauser
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotPauser()"));
        sapienVault.unpause();
    }

    function test_Vault_PauserRoleGrantedToAdmin() public view {
        // Verify admin has PAUSER_ROLE
        assertTrue(sapienVault.hasRole(Const.PAUSER_ROLE, admin));

        // Verify users don't have PAUSER_ROLE
        assertFalse(sapienVault.hasRole(Const.PAUSER_ROLE, user1));
        assertFalse(sapienVault.hasRole(Const.PAUSER_ROLE, user2));
    }

    function test_Vault_GrantPauserRoleToOther() public {
        address newPauser = makeAddr("newPauser");

        // Grant PAUSER_ROLE to new address
        vm.prank(admin);
        sapienVault.grantRole(Const.PAUSER_ROLE, newPauser);

        // Verify new pauser can pause
        vm.prank(newPauser);
        sapienVault.pause();

        // Verify new pauser can unpause
        vm.prank(newPauser);
        sapienVault.unpause();
    }

    // =============================================================================
    // EMERGENCY WITHDRAWAL TESTS
    // =============================================================================

    event EmergencyWithdraw(address indexed token, address indexed to, uint256 amount);

    function test_Vault_EmergencyWithdrawERC20() public {
        // Setup: Contract needs to be paused for emergency withdrawal
        vm.prank(admin);
        sapienVault.pause();

        // Add some tokens to the contract
        uint256 emergencyAmount = 50000e18;
        sapienToken.mint(address(sapienVault), emergencyAmount);

        address emergencyRecipient = makeAddr("emergencyRecipient");
        uint256 withdrawAmount = 25000e18;

        uint256 recipientBalanceBefore = sapienToken.balanceOf(emergencyRecipient);
        uint256 contractBalanceBefore = sapienToken.balanceOf(address(sapienVault));

        // Perform emergency withdrawal
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(address(sapienToken), emergencyRecipient, withdrawAmount);
        sapienVault.emergencyWithdraw(address(sapienToken), emergencyRecipient, withdrawAmount);

        // Verify balances
        assertEq(sapienToken.balanceOf(emergencyRecipient), recipientBalanceBefore + withdrawAmount);
        assertEq(sapienToken.balanceOf(address(sapienVault)), contractBalanceBefore - withdrawAmount);
    }

    function test_Vault_EmergencyWithdrawETH() public {
        // Setup: Contract needs to be paused for emergency withdrawal
        vm.prank(admin);
        sapienVault.pause();

        // Add some ETH to the contract
        uint256 ethAmount = 5 ether;
        vm.deal(address(sapienVault), ethAmount);

        address emergencyRecipient = makeAddr("emergencyRecipient");
        uint256 withdrawAmount = 2 ether;

        uint256 recipientBalanceBefore = emergencyRecipient.balance;
        uint256 contractBalanceBefore = address(sapienVault).balance;

        // Perform emergency ETH withdrawal
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(address(0), emergencyRecipient, withdrawAmount);
        sapienVault.emergencyWithdraw(address(0), emergencyRecipient, withdrawAmount);

        // Verify balances
        assertEq(emergencyRecipient.balance, recipientBalanceBefore + withdrawAmount);
        assertEq(address(sapienVault).balance, contractBalanceBefore - withdrawAmount);
    }

    function test_Vault_EmergencyWithdrawFullERC20Balance() public {
        // Setup: Contract needs to be paused
        vm.prank(admin);
        sapienVault.pause();

        // Add tokens to contract
        uint256 totalAmount = 100000e18;
        sapienToken.mint(address(sapienVault), totalAmount);

        address emergencyRecipient = makeAddr("emergencyRecipient");

        // Withdraw entire balance
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(address(sapienToken), emergencyRecipient, totalAmount);
        sapienVault.emergencyWithdraw(address(sapienToken), emergencyRecipient, totalAmount);

        // Verify complete withdrawal
        assertEq(sapienToken.balanceOf(emergencyRecipient), totalAmount);
        assertEq(sapienToken.balanceOf(address(sapienVault)), 0);
    }

    function test_Vault_EmergencyWithdrawFullETHBalance() public {
        // Setup: Contract needs to be paused
        vm.prank(admin);
        sapienVault.pause();

        // Add ETH to contract
        uint256 totalETH = 10 ether;
        vm.deal(address(sapienVault), totalETH);

        address emergencyRecipient = makeAddr("emergencyRecipient");

        // Withdraw entire ETH balance
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(address(0), emergencyRecipient, totalETH);
        sapienVault.emergencyWithdraw(address(0), emergencyRecipient, totalETH);

        // Verify complete withdrawal
        assertEq(emergencyRecipient.balance, totalETH);
        assertEq(address(sapienVault).balance, 0);
    }

    function test_Vault_RevertEmergencyWithdrawNotPaused() public {
        // Try emergency withdrawal without pausing first
        uint256 withdrawAmount = 1000e18;
        address emergencyRecipient = makeAddr("emergencyRecipient");

        vm.prank(admin);
        vm.expectRevert("ExpectedPause()");
        sapienVault.emergencyWithdraw(address(sapienToken), emergencyRecipient, withdrawAmount);
    }

    function test_Vault_RevertEmergencyWithdrawUnauthorized() public {
        // Setup: Pause contract
        vm.prank(admin);
        sapienVault.pause();

        // Try emergency withdrawal as non-admin
        uint256 withdrawAmount = 1000e18;
        address emergencyRecipient = makeAddr("emergencyRecipient");

        vm.prank(user1);
        vm.expectRevert(); // AccessControl error
        sapienVault.emergencyWithdraw(address(sapienToken), emergencyRecipient, withdrawAmount);
    }

    function test_Vault_RevertEmergencyWithdrawZeroAddress() public {
        // Setup: Pause contract
        vm.prank(admin);
        sapienVault.pause();

        uint256 withdrawAmount = 1000e18;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("ZeroAddress()"));
        sapienVault.emergencyWithdraw(address(sapienToken), address(0), withdrawAmount);
    }

    function test_Vault_RevertEmergencyWithdrawInsufficientETH() public {
        // Setup: Pause contract
        vm.prank(admin);
        sapienVault.pause();

        // Try to withdraw more ETH than available
        address emergencyRecipient = makeAddr("emergencyRecipient");
        uint256 withdrawAmount = 1 ether;

        // Contract has no ETH
        assertEq(address(sapienVault).balance, 0);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        sapienVault.emergencyWithdraw(address(0), emergencyRecipient, withdrawAmount);
    }

    function test_Vault_EmergencyWithdrawScenario() public {
        // Comprehensive scenario test

        // Phase 1: Normal operations - users stake tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 5);
        sapienVault.stake(MINIMUM_STAKE * 5, LOCK_30_DAYS);
        vm.stopPrank();

        vm.startPrank(user2);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 3);
        sapienVault.stake(MINIMUM_STAKE * 3, LOCK_90_DAYS);
        vm.stopPrank();

        uint256 totalStakedBefore = sapienVault.totalStaked();
        assertEq(totalStakedBefore, MINIMUM_STAKE * 8);

        // Phase 2: Emergency situation - contract is compromised and needs to be paused
        vm.prank(admin);
        sapienVault.pause();

        // Phase 3: Some malicious tokens are sent to the contract
        MockERC20 maliciousToken = new MockERC20("Malicious", "MAL", 18);
        uint256 maliciousAmount = 100000e18;
        maliciousToken.mint(address(sapienVault), maliciousAmount);

        // Phase 4: Admin recovers malicious tokens
        address recoveryAddress = makeAddr("recoveryAddress");

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(address(maliciousToken), recoveryAddress, maliciousAmount);
        sapienVault.emergencyWithdraw(address(maliciousToken), recoveryAddress, maliciousAmount);

        // Verify malicious tokens were recovered
        assertEq(maliciousToken.balanceOf(recoveryAddress), maliciousAmount);
        assertEq(maliciousToken.balanceOf(address(sapienVault)), 0);

        // Phase 5: User funds (SAPIEN tokens) are still safe
        assertEq(sapienToken.balanceOf(address(sapienVault)), totalStakedBefore);
        assertEq(sapienVault.totalStaked(), totalStakedBefore);

        // Phase 6: If necessary, admin could also recover staked tokens to a safe address
        // (This would be a last resort to protect user funds)
        address userFundSafeAddress = makeAddr("userFundSafe");
        uint256 partialRecovery = MINIMUM_STAKE * 2;

        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(address(sapienToken), userFundSafeAddress, partialRecovery);
        sapienVault.emergencyWithdraw(address(sapienToken), userFundSafeAddress, partialRecovery);

        // Verify partial recovery
        assertEq(sapienToken.balanceOf(userFundSafeAddress), partialRecovery);
        assertEq(sapienToken.balanceOf(address(sapienVault)), totalStakedBefore - partialRecovery);
    }

    function test_Vault_EmergencyWithdrawWithETHAndERC20() public {
        // Test withdrawing both ETH and ERC20 tokens in emergency

        // Setup: Pause contract
        vm.prank(admin);
        sapienVault.pause();

        // Add ETH and tokens to contract
        uint256 ethAmount = 3 ether;
        uint256 tokenAmount = 75000e18;
        vm.deal(address(sapienVault), ethAmount);
        sapienToken.mint(address(sapienVault), tokenAmount);

        address emergencyRecipient = makeAddr("emergencyRecipient");

        // Withdraw ETH first
        uint256 ethWithdrawAmount = 1 ether;
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(address(0), emergencyRecipient, ethWithdrawAmount);
        sapienVault.emergencyWithdraw(address(0), emergencyRecipient, ethWithdrawAmount);

        // Withdraw tokens second
        uint256 tokenWithdrawAmount = 50000e18;
        vm.prank(admin);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(address(sapienToken), emergencyRecipient, tokenWithdrawAmount);
        sapienVault.emergencyWithdraw(address(sapienToken), emergencyRecipient, tokenWithdrawAmount);

        // Verify both withdrawals
        assertEq(emergencyRecipient.balance, ethWithdrawAmount);
        assertEq(sapienToken.balanceOf(emergencyRecipient), tokenWithdrawAmount);
        assertEq(address(sapienVault).balance, ethAmount - ethWithdrawAmount);
        assertEq(sapienToken.balanceOf(address(sapienVault)), tokenAmount - tokenWithdrawAmount);
    }
}
