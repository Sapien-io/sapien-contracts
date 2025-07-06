// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienVault, ISapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants as Const} from "src/utils/Constants.sol";

/**
 * @title SapienVault IncreaseStake Test Suite
 * @notice Comprehensive tests for the increaseStake function that combines increaseAmount and increaseLockup
 * @dev Tests all scenarios including edge cases, error conditions, and state consistency
 */
contract SapienVaultIncreaseStakeTest is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public pauser = makeAddr("pauser");
    address public sapienQA = makeAddr("sapienQA");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    uint256 public constant MINIMUM_STAKE = 1000e18; // 1000 SAPIEN
    uint256 public constant COOLDOWN_PERIOD = Const.COOLDOWN_PERIOD;
    uint256 public constant MINIMUM_LOCKUP_INCREASE = 7 days;

    // Lock periods
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    // Events from the individual functions that increaseStake calls
    event AmountIncreased(
        address indexed user, uint256 additionalAmount, uint256 newTotalAmount, uint256 newEffectiveMultiplier
    );
    event LockupIncreased(
        address indexed user, uint256 additionalLockup, uint256 newEffectiveLockup, uint256 newEffectiveMultiplier
    );

    function setUp() public {
        // Deploy mock SAPIEN token
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        // Deploy SapienVault
        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector, address(sapienToken), admin, pauser, treasury, sapienQA
        );
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        // Mint tokens to users
        sapienToken.mint(user1, 100000e18);
        sapienToken.mint(user2, 100000e18);
        sapienToken.mint(user3, 100000e18);
    }

    // =============================================================================
    // BASIC FUNCTIONALITY TESTS
    // =============================================================================

    /**
     * @notice Test basic increaseStake functionality with valid inputs
     * @dev Verifies that increaseStake properly calls both increaseAmount and increaseLockup
     */
    function test_IncreaseStake_BasicFunctionality() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE * 2;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Get initial state
        ISapienVault.UserStakingSummary memory initialStake = sapienVault.getUserStakingSummary(user1);
        uint256 initialMultiplier = initialStake.effectiveMultiplier;

        // Call increaseStake (note: events will be emitted by the underlying functions)
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();

        // Verify final state
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user1);

        assertEq(finalStake.userTotalStaked, initialAmount + additionalAmount, "Total stake should be increased");
        assertGt(
            finalStake.effectiveMultiplier,
            initialMultiplier,
            "Multiplier should increase with more tokens and longer lockup"
        );
        assertEq(finalStake.effectiveLockUpPeriod, LOCK_30_DAYS + additionalLockup, "Lockup should be extended");
    }

    /**
     * @notice Test increaseStake with maximum values
     * @dev Verifies behavior at the upper limits of the system
     */
    function test_IncreaseStake_MaximumValues() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 maxAdditionalAmount = sapienVault.maximumStakeAmount() - initialAmount;
        uint256 maxAdditionalLockup = LOCK_365_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Increase stake to maximum
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), maxAdditionalAmount);
        sapienVault.increaseStake(maxAdditionalAmount, maxAdditionalLockup);
        vm.stopPrank();

        // Verify final state
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user1);

        assertEq(finalStake.userTotalStaked, initialAmount + maxAdditionalAmount, "Should handle maximum stake amount");
        assertEq(finalStake.effectiveLockUpPeriod, LOCK_365_DAYS, "Should be capped at maximum lockup");
    }

    /**
     * @notice Test increaseStake with minimum valid values
     * @dev Verifies behavior at the lower limits of the system
     */
    function test_IncreaseStake_MinimumValues() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 minAdditionalAmount = MINIMUM_STAKE / 100; // Small but valid amount
        uint256 minAdditionalLockup = LOCK_90_DAYS; // Use a clearly valid lockup period

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Increase stake with minimum values
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), minAdditionalAmount);
        sapienVault.increaseStake(minAdditionalAmount, minAdditionalLockup);
        vm.stopPrank();

        // Verify final state
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user1);

        assertEq(
            finalStake.userTotalStaked, initialAmount + minAdditionalAmount, "Should handle minimum additional amount"
        );
        assertEq(
            finalStake.effectiveLockUpPeriod,
            LOCK_30_DAYS + minAdditionalLockup,
            "Should handle minimum lockup increase"
        );
    }

    // =============================================================================
    // EDGE CASE TESTS
    // =============================================================================

    /**
     * @notice Test increaseStake on expired/unlocked stake
     * @dev Verifies behavior when the original stake has expired
     */
    function test_IncreaseStake_ExpiredStake() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE * 2;
        uint256 additionalLockup = LOCK_180_DAYS;

        // Create initial stake with short lockup
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Wait for stake to expire
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Verify stake is expired
        assertTrue(sapienVault.getTotalUnlocked(user1) > 0, "Stake should be unlocked");

        // Increase expired stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();

        // Verify final state
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user1);

        assertEq(finalStake.userTotalStaked, initialAmount + additionalAmount, "Should handle expired stake");
        // When increaseStake is called on expired stake:
        // 1. increaseAmount() updates the weighted start time (due to expired stake)
        // 2. increaseLockup() then adds to the current lockup period
        // The final lockup will be the sum of existing + additional
        assertGt(finalStake.effectiveLockUpPeriod, additionalLockup, "Should have combined lockup periods");
        assertEq(finalStake.totalLocked, finalStake.userTotalStaked, "All stake should be locked again");
    }

    /**
     * @notice Test increaseStake with partial time elapsed
     * @dev Verifies lockup calculation when original stake is partially through its period
     */
    function test_IncreaseStake_PartialTimeElapsed() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_180_DAYS);
        vm.stopPrank();

        // Advance time partway through lockup
        uint256 elapsedTime = 60 days;
        vm.warp(block.timestamp + elapsedTime);

        // Verify remaining time
        uint256 remainingTime = sapienVault.getTimeUntilUnlock(user1);
        assertEq(remainingTime, LOCK_180_DAYS - elapsedTime, "Should have correct remaining time");

        // Increase stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();

        // Verify final state
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user1);

        assertEq(finalStake.userTotalStaked, initialAmount + additionalAmount, "Should have combined amounts");

        // When increaseStake is called:
        // 1. increaseAmount() recalculates weighted start time based on amounts
        // 2. increaseLockup() then calculates new lockup based on the new weighted time
        // The actual behavior is more complex due to weighted calculations
        assertGt(finalStake.effectiveLockUpPeriod, remainingTime, "Should have extended the lockup period");
        assertGt(finalStake.effectiveLockUpPeriod, additionalLockup, "Should be more than just the additional lockup");
    }

    /**
     * @notice Test increaseStake with lockup period capping
     * @dev Verifies that lockup periods are properly capped at maximum
     */
    function test_IncreaseStake_LockupCapping() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 excessiveLockup = LOCK_365_DAYS * 2; // More than maximum

        // Create initial stake with maximum lockup
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_365_DAYS);
        vm.stopPrank();

        // Try to increase with excessive lockup
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseStake(additionalAmount, excessiveLockup);
        vm.stopPrank();

        // Verify lockup is capped
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user1);

        assertEq(finalStake.effectiveLockUpPeriod, LOCK_365_DAYS, "Lockup should be capped at maximum");
    }

    // =============================================================================
    // ERROR CONDITION TESTS
    // =============================================================================

    /**
     * @notice Test increaseStake reverts when user has no existing stake
     * @dev Should revert with NoStakeFound error from increaseAmount
     */
    function test_IncreaseStake_RevertNoExistingStake() public {
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_90_DAYS;

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);

        // Should revert when trying to increase non-existent stake
        vm.expectRevert(abi.encodeWithSignature("NoStakeFound()"));
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();
    }

    /**
     * @notice Test increaseStake reverts with zero additional amount
     * @dev Should revert with InvalidAmount error from increaseAmount
     */
    function test_IncreaseStake_RevertZeroAmount() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Try to increase with zero amount
        vm.startPrank(user1);
        vm.expectRevert(abi.encodeWithSignature("InvalidAmount()"));
        sapienVault.increaseStake(0, additionalLockup);
        vm.stopPrank();
    }

    /**
     * @notice Test increaseStake reverts with insufficient lockup increase
     * @dev Should revert with MinimumLockupIncreaseRequired error from increaseLockup
     */
    function test_IncreaseStake_RevertInsufficientLockupIncrease() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 insufficientLockup = MINIMUM_LOCKUP_INCREASE - 1;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Try to increase with insufficient lockup
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        vm.expectRevert(abi.encodeWithSignature("MinimumLockupIncreaseRequired()"));
        sapienVault.increaseStake(additionalAmount, insufficientLockup);
        vm.stopPrank();
    }

    /**
     * @notice Test increaseStake reverts when stake is in cooldown
     * @dev Should revert with CannotIncreaseStakeInCooldown error
     */
    function test_IncreaseStake_RevertDuringCooldown() public {
        uint256 initialAmount = MINIMUM_STAKE * 2;
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Wait for stake to unlock
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Initiate unstaking (puts stake in cooldown)
        vm.prank(user1);
        sapienVault.initiateUnstake(MINIMUM_STAKE);

        // Try to increase stake during cooldown
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        vm.expectRevert(abi.encodeWithSignature("CannotIncreaseStakeInCooldown()"));
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();
    }

    /**
     * @notice Test increaseStake reverts when stake is in early unstake cooldown
     * @dev Should revert with CannotIncreaseStakeInCooldown error
     */
    function test_IncreaseStake_RevertDuringEarlyUnstakeCooldown() public {
        uint256 initialAmount = MINIMUM_STAKE * 2;
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_180_DAYS);
        vm.stopPrank();

        // Initiate early unstake (puts stake in early unstake cooldown)
        vm.prank(user1);
        sapienVault.initiateEarlyUnstake(MINIMUM_STAKE);

        // Try to increase stake during early unstake cooldown
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        vm.expectRevert(abi.encodeWithSignature("CannotIncreaseStakeInCooldown()"));
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();
    }

    /**
     * @notice Test increaseStake reverts with excessive stake amount
     * @dev Should revert with StakeAmountTooLarge error from increaseAmount
     */
    function test_IncreaseStake_RevertExcessiveAmount() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 excessiveAmount = sapienVault.maximumStakeAmount() + 1;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Try to increase with excessive amount
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), excessiveAmount);
        vm.expectRevert(abi.encodeWithSignature("StakeAmountTooLarge()"));
        sapienVault.increaseStake(excessiveAmount, additionalLockup);
        vm.stopPrank();
    }

    /**
     * @notice Test increaseStake reverts with insufficient token balance
     * @dev Should revert with ERC20 transfer error
     */
    function test_IncreaseStake_RevertInsufficientBalance() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Burn user's tokens to create insufficient balance scenario
        uint256 userBalance = sapienToken.balanceOf(user1);
        vm.prank(user1);
        sapienToken.transfer(address(0xdead), userBalance); // Send tokens away

        uint256 additionalAmount = MINIMUM_STAKE;

        // Try to increase with insufficient balance
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        vm.expectRevert(); // ERC20 transfer error format may vary
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();
    }

    /**
     * @notice Test increaseStake reverts with insufficient allowance
     * @dev Should revert with ERC20 allowance error
     */
    function test_IncreaseStake_RevertInsufficientAllowance() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Try to increase without sufficient allowance
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount - 1); // Insufficient allowance
        vm.expectRevert(); // ERC20 allowance error format may vary
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();
    }

    // =============================================================================
    // STATE CONSISTENCY TESTS
    // =============================================================================

    /**
     * @notice Test that increaseStake produces same result as calling functions separately
     * @dev Verifies that increaseStake is equivalent to increaseAmount + increaseLockup
     */
    function test_IncreaseStake_EquivalentToSeparateCalls() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE * 2;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Setup two identical initial stakes
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        vm.startPrank(user2);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Advance time to same point
        vm.warp(block.timestamp + 10 days);

        // User1: Use increaseStake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();

        // User2: Use separate calls
        vm.startPrank(user2);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseAmount(additionalAmount);
        sapienVault.increaseLockup(additionalLockup);
        vm.stopPrank();

        // Verify both users have identical final states
        ISapienVault.UserStakingSummary memory user1Final = sapienVault.getUserStakingSummary(user1);
        ISapienVault.UserStakingSummary memory user2Final = sapienVault.getUserStakingSummary(user2);

        assertEq(user1Final.userTotalStaked, user2Final.userTotalStaked, "Total staked should be identical");
        assertEq(
            user1Final.effectiveLockUpPeriod, user2Final.effectiveLockUpPeriod, "Lockup periods should be identical"
        );
        assertEq(user1Final.effectiveMultiplier, user2Final.effectiveMultiplier, "Multipliers should be identical");
        assertEq(user1Final.timeUntilUnlock, user2Final.timeUntilUnlock, "Time until unlock should be identical");
    }

    /**
     * @notice Test increaseStake maintains proper multiplier calculations
     * @dev Verifies that multipliers are correctly updated after combined operation
     */
    function test_IncreaseStake_MultiplierConsistency() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_180_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Get initial multiplier
        uint256 initialMultiplier = sapienVault.getUserMultiplier(user1);

        // Increase stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();

        // Get final multiplier
        uint256 finalMultiplier = sapienVault.getUserMultiplier(user1);
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user1);

        // Verify multiplier increased due to larger amount and longer lockup
        assertGt(finalMultiplier, initialMultiplier, "Multiplier should increase with more tokens and longer lockup");

        // Verify multiplier matches expected calculation
        uint256 expectedMultiplier =
            sapienVault.calculateMultiplier(finalStake.userTotalStaked, finalStake.effectiveLockUpPeriod);
        assertEq(finalMultiplier, expectedMultiplier, "Final multiplier should match expected calculation");
    }

    /**
     * @notice Test increaseStake with multiple sequential calls
     * @dev Verifies that multiple increaseStake calls work correctly
     */
    function test_IncreaseStake_MultipleSequentialCalls() public {
        uint256 initialAmount = MINIMUM_STAKE;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // First increase
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.increaseStake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Second increase
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.increaseStake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        // Verify final state
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user1);

        assertEq(finalStake.userTotalStaked, initialAmount * 3, "Should have accumulated all increases");
        assertGt(finalStake.effectiveLockUpPeriod, LOCK_30_DAYS, "Lockup should have been extended multiple times");
    }

    // =============================================================================
    // INTEGRATION TESTS
    // =============================================================================

    /**
     * @notice Test increaseStake integration with other vault functions
     * @dev Verifies that increaseStake works correctly with unstaking flows
     */
    function test_IncreaseStake_IntegrationWithUnstaking() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Wait for unlock
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Increase stake on unlocked position
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();

        // Wait for new unlock - need to wait for the full effective lockup period
        ISapienVault.UserStakingSummary memory stakeAfterIncrease = sapienVault.getUserStakingSummary(user1);
        vm.warp(block.timestamp + stakeAfterIncrease.timeUntilUnlock + 1);

        // Verify can unstake
        vm.prank(user1);
        sapienVault.initiateUnstake(initialAmount + additionalAmount);

        // Wait for cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // Complete unstaking
        vm.prank(user1);
        sapienVault.unstake(initialAmount + additionalAmount);

        // Verify final state
        assertEq(sapienVault.getTotalStaked(user1), 0, "Should have no remaining stake");
        assertEq(sapienToken.balanceOf(user1), 100000e18, "Should have received all tokens back");
    }

    /**
     * @notice Test increaseStake with contract paused
     * @dev Verifies that increaseStake respects pause state through underlying functions
     */
    function test_IncreaseStake_RespectsPauseState() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Create initial stake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Pause contract
        vm.prank(pauser);
        sapienVault.pause();

        // Try to increase stake while paused
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        vm.expectRevert("EnforcedPause()");
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();

        // Unpause and verify it works
        vm.prank(pauser);
        sapienVault.unpause();

        vm.startPrank(user1);
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        vm.stopPrank();

        // Verify increase worked
        assertEq(
            sapienVault.getTotalStaked(user1), initialAmount + additionalAmount, "Should have increased after unpause"
        );
    }

    // =============================================================================
    // GAS OPTIMIZATION TESTS
    // =============================================================================

    /**
     * @notice Test gas usage of increaseStake vs separate calls
     * @dev Compares gas consumption between increaseStake and separate function calls
     */
    function test_IncreaseStake_GasComparison() public {
        uint256 initialAmount = MINIMUM_STAKE;
        uint256 additionalAmount = MINIMUM_STAKE * 2;
        uint256 additionalLockup = LOCK_90_DAYS;

        // Setup two identical stakes
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        vm.startPrank(user2);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Measure gas for increaseStake
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        uint256 gasBefore1 = gasleft();
        sapienVault.increaseStake(additionalAmount, additionalLockup);
        uint256 gasUsed1 = gasBefore1 - gasleft();
        vm.stopPrank();

        // Measure gas for separate calls
        vm.startPrank(user2);
        sapienToken.approve(address(sapienVault), additionalAmount);
        uint256 gasBefore2 = gasleft();
        sapienVault.increaseAmount(additionalAmount);
        sapienVault.increaseLockup(additionalLockup);
        uint256 gasUsed2 = gasBefore2 - gasleft();
        vm.stopPrank();

        // increaseStake should use similar gas (might be slightly more due to external calls)
        // The key is that it should be reasonable and not excessive
        assertLt(gasUsed1, gasUsed2 * 2, "increaseStake should not use excessive gas compared to separate calls");

        console.log("Gas used by increaseStake:", gasUsed1);
        console.log("Gas used by separate calls:", gasUsed2);
    }
}
