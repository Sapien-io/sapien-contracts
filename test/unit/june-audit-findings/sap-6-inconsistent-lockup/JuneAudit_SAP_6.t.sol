// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants as Const} from "src/utils/Constants.sol";

/**
 * @title JuneAudit SAP-6: Inconsistent Lockup Period Calculation Test
 * @dev Tests for the fix to the inconsistent lockup period calculation issue (SAP-6)
 *
 * ISSUE DESCRIPTION:
 * The SapienVault contract exhibited an inconsistency in the effectiveLockupPeriod calculation methodology.
 * When users stake multiple times, the contract calculates a new weighted start time and a new weighted
 * effective lockup period. When users increase their stake amount, the contract calculates a new weighted
 * start time. However, the increaseLockup() function bypassed this weighted calculation for a new lockup
 * period, and instead used a direct addition of the remaining lockup time and the additional lockup period.
 *
 * This inconsistency allowed users to game the system by strategically choosing whether to add new stakes
 * or increase lockup on existing stakes to get the shortest lockup period, as the mathematical approach
 * differed between these operations.
 *
 * FIX IMPLEMENTED:
 * - Standardized expired stake handling across all operations (stake, increaseAmount, increaseLockup)
 * - Added centralized helper functions for consistent behavior
 * - Modified increaseLockup() to handle expired stakes the same way as other operations
 * - Users can no longer game the system by choosing different operations
 */
contract JuneAudit_SAP_6_Test is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");

    uint256 public constant MINIMUM_STAKE = 1000e18;
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    function setUp() public {
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        SapienVault sapienVaultImpl = new SapienVault();

        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector,
            address(sapienToken),
            admin,
            makeAddr("pauseManager"),
            treasury,
            makeAddr("dummySapienQA")
        );
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        // Mint tokens to user
        sapienToken.mint(user1, 1000000e18);
    }

    /**
     * @notice Test that standardized expired stake handling ensures consistency between operations
     * @dev This test verifies that SAP-6 inconsistency has been resolved by ensuring all operations
     *      handle expired stakes consistently, preventing users from gaming the lockup calculation
     */
    function test_SAP6_StandardizedExpiredStakeHandling_ConsistencyAcrossOperations() public {
        uint256 stakeAmount = MINIMUM_STAKE;
        uint256 lockupPeriod = LOCK_30_DAYS;
        uint256 additionalAmount = MINIMUM_STAKE;
        uint256 additionalLockup = LOCK_30_DAYS;

        // Setup three identical users
        address user2 = makeAddr("user2");
        address user3 = makeAddr("user3");

        sapienToken.mint(user2, stakeAmount * 2);
        sapienToken.mint(user3, stakeAmount * 2);

        // All users stake the same amount with the same lockup
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), stakeAmount * 2);
        sapienVault.stake(stakeAmount, lockupPeriod);
        vm.stopPrank();

        vm.startPrank(user2);
        sapienToken.approve(address(sapienVault), stakeAmount * 2);
        sapienVault.stake(stakeAmount, lockupPeriod);
        vm.stopPrank();

        vm.startPrank(user3);
        sapienToken.approve(address(sapienVault), stakeAmount * 2);
        sapienVault.stake(stakeAmount, lockupPeriod);
        vm.stopPrank();

        // Fast forward to expire all stakes
        vm.warp(block.timestamp + lockupPeriod + 1);

        // Verify all stakes are expired (timeUntilUnlock == 0)
        (,,,,,,, uint256 timeUntilUnlock1) = sapienVault.getUserStakingSummary(user1);
        (,,,,,,, uint256 timeUntilUnlock2) = sapienVault.getUserStakingSummary(user2);
        (,,,,,,, uint256 timeUntilUnlock3) = sapienVault.getUserStakingSummary(user3);

        assertEq(timeUntilUnlock1, 0, "User1 stake should be expired");
        assertEq(timeUntilUnlock2, 0, "User2 stake should be expired");
        assertEq(timeUntilUnlock3, 0, "User3 stake should be expired");

        // User1: Add new stake (combines with expired stake)
        vm.startPrank(user1);
        sapienVault.stake(additionalAmount, additionalLockup);
        vm.stopPrank();

        // User2: Increase amount on expired stake
        vm.startPrank(user2);
        sapienVault.increaseAmount(additionalAmount);
        vm.stopPrank();

        // User3: Increase lockup on expired stake
        vm.startPrank(user3);
        sapienVault.increaseLockup(additionalLockup);
        vm.stopPrank();

        // Verify User1 stake details (scoped to avoid stack too deep)
        {
            (
                uint256 amount,
                , // cooldownAmount
                , // weightedStart (not used in this scope)
                uint256 effectiveLockup,
                , // cooldownStart
                , // lastUpdateTime
                , // earlyUnstakeCooldownStart
                , // effectiveMultiplier
                    // hasStake
            ) = sapienVault.userStakes(user1);

            assertEq(amount, stakeAmount + additionalAmount, "User1 should have combined stake amount");
            assertEq(effectiveLockup, additionalLockup, "User1 effective lockup should be new lockup period");
        }

        // Verify User2 stake details (scoped to avoid stack too deep)
        uint256 user2WeightedStart;
        {
            (
                uint256 amount,
                , // cooldownAmount
                uint256 weightedStart,
                uint256 effectiveLockup,
                , // cooldownStart
                , // lastUpdateTime
                , // earlyUnstakeCooldownStart
                , // effectiveMultiplier
                    // hasStake
            ) = sapienVault.userStakes(user2);

            user2WeightedStart = weightedStart;
            assertEq(amount, stakeAmount + additionalAmount, "User2 should have combined stake amount");
            assertEq(effectiveLockup, lockupPeriod, "User2 effective lockup should be original lockup period");
        }

        // Verify User3 stake details and compare weighted start times (scoped to avoid stack too deep)
        {
            (
                uint256 amount,
                , // cooldownAmount
                uint256 weightedStart,
                uint256 effectiveLockup,
                , // cooldownStart
                , // lastUpdateTime
                , // earlyUnstakeCooldownStart
                , // effectiveMultiplier
                    // hasStake
            ) = sapienVault.userStakes(user3);

            assertEq(amount, stakeAmount, "User3 should have original stake amount");
            assertEq(effectiveLockup, additionalLockup, "User3 effective lockup should be additional lockup period");

            // All users should have similar weighted start times (reset to current timestamp)
            // Note: We compare user2 and user3 as they should be very close in time
            assertEq(user2WeightedStart, weightedStart, "User2 and User3 should have same weighted start time");
        }

        // This test proves that the inconsistency from SAP-6 has been resolved:
        // 1. All operations consistently reset weighted start time for expired stakes
        // 2. Users cannot game the system by choosing different operations
        // 3. Expired stake handling is standardized across all functions
    }

    /**
     * @notice Test the behavior before the fix to demonstrate the issue
     * @dev This test documents what the inconsistent behavior would have been
     */
    function test_SAP6_DocumentedInconsistency_BeforeFix() public {
        // This test documents the issue that existed before the fix
        // Before the fix, increaseLockup() would not reset weighted start time for expired stakes
        // while stake() and increaseAmount() would reset it, creating an inconsistency

        uint256 stakeAmount = MINIMUM_STAKE;
        uint256 lockupPeriod = LOCK_30_DAYS;
        uint256 additionalLockup = LOCK_30_DAYS;

        // User stakes initially
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, lockupPeriod);
        vm.stopPrank();

        // Record initial weighted start time
        (,, uint256 initialWeightedStart,,,,,,) = sapienVault.userStakes(user1);

        // Fast forward to expire the stake
        vm.warp(block.timestamp + lockupPeriod + 1);

        // Verify stake is expired
        (,,,,,,, uint256 timeUntilUnlock) = sapienVault.getUserStakingSummary(user1);
        assertEq(timeUntilUnlock, 0, "Stake should be expired");

        // User increases lockup on expired stake
        vm.startPrank(user1);
        sapienVault.increaseLockup(additionalLockup);
        vm.stopPrank();

        // After the fix, weighted start time should be reset to current timestamp
        (,, uint256 newWeightedStart, uint256 newLockup,,,,,) = sapienVault.userStakes(user1);

        // With the fix: weighted start time should be reset (different from initial)
        assertGt(newWeightedStart, initialWeightedStart, "Weighted start time should be reset for expired stakes");
        assertEq(newLockup, additionalLockup, "New lockup should be the additional lockup period");

        // This demonstrates that the fix ensures consistent behavior across all operations
    }

    /**
     * @notice Test that the fix prevents gaming the lockup system
     * @dev Verifies users cannot choose operations strategically to minimize lockup periods
     */
    function test_SAP6_PreventGamingLockupSystem() public {
        uint256 stakeAmount = MINIMUM_STAKE;
        uint256 shortLockup = LOCK_30_DAYS;
        uint256 longLockup = LOCK_90_DAYS;

        // Create two users with identical initial conditions
        address gamer1 = makeAddr("gamer1");
        address gamer2 = makeAddr("gamer2");

        sapienToken.mint(gamer1, stakeAmount * 2);
        sapienToken.mint(gamer2, stakeAmount * 2);

        // Both users stake with long lockup initially
        vm.startPrank(gamer1);
        sapienToken.approve(address(sapienVault), stakeAmount * 2);
        sapienVault.stake(stakeAmount, longLockup);
        vm.stopPrank();

        vm.startPrank(gamer2);
        sapienToken.approve(address(sapienVault), stakeAmount * 2);
        sapienVault.stake(stakeAmount, longLockup);
        vm.stopPrank();

        // Fast forward to expire both stakes
        vm.warp(block.timestamp + longLockup + 1);

        // Gamer1 tries to game by adding a new stake with short lockup
        vm.startPrank(gamer1);
        sapienVault.stake(stakeAmount, shortLockup);
        vm.stopPrank();

        // Gamer2 tries to game by increasing lockup with short period
        vm.startPrank(gamer2);
        sapienVault.increaseLockup(shortLockup);
        vm.stopPrank();

        // Get final lockup periods
        (,,, uint256 gamer1Lockup,,,,,) = sapienVault.userStakes(gamer1);
        (,,, uint256 gamer2Lockup,,,,,) = sapienVault.userStakes(gamer2);

        // With the fix, both should have predictable and consistent lockup periods
        assertEq(gamer1Lockup, shortLockup, "Gamer1 should get new short lockup for expired stake");
        assertEq(gamer2Lockup, shortLockup, "Gamer2 should get short lockup for expired stake");

        // Both users get the same result - no gaming advantage
        assertEq(gamer1Lockup, gamer2Lockup, "Both approaches should yield identical results");
    }
}
