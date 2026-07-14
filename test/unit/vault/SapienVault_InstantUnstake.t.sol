// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienVault, ISapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {ReentrantERC20} from "test/mocks/ReentrantERC20.sol";
import {Constants as Const} from "src/utils/Constants.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";

contract SapienVaultInstantUnstakeTest is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public pauser = makeAddr("pauser");
    address public sapienQA = makeAddr("sapienQA");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant MINIMUM_STAKE = 1e18; // 1 SAPIEN
    uint256 public constant COOLDOWN_PERIOD = Const.COOLDOWN_PERIOD;
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant STAKE_AMOUNT = 100e18;

    function setUp() public {
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector, address(sapienToken), admin, pauser, treasury, sapienQA
        );
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        sapienToken.mint(user1, 100000e18);
        sapienToken.mint(user2, 100000e18);
    }

    function _stake(uint256 amount, uint256 lockup) internal {
        _stakeAs(user1, amount, lockup);
    }

    function _stakeAs(address user, uint256 amount, uint256 lockup) internal {
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, lockup);
        vm.stopPrank();
    }

    // =============================================================================
    // CORE BEHAVIOR: bypasses lockup, cooldown, and penalty
    // =============================================================================

    function test_InstantUnstake_WhileLocked_FullAmount_NoPenalty() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        // Still well within the lockup period
        assertGt(sapienVault.getTimeUntilUnlock(user1), 0);

        uint256 userBalanceBefore = sapienToken.balanceOf(user1);
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        vm.expectEmit(true, false, false, true);
        emit ISapienVault.InstantUnstaked(user1, STAKE_AMOUNT);

        vm.prank(user1);
        sapienVault.instantUnstake(STAKE_AMOUNT);

        // Full amount returned, no penalty taken
        assertEq(sapienToken.balanceOf(user1), userBalanceBefore + STAKE_AMOUNT);
        assertEq(sapienToken.balanceOf(treasury), treasuryBalanceBefore);

        // Position fully reset
        assertEq(sapienVault.totalStaked(), 0);
        assertFalse(sapienVault.hasActiveStake(user1));
        assertEq(sapienToken.balanceOf(address(sapienVault)), 0);
    }

    function test_InstantUnstake_NoCooldownRequired() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        // Immediately unstake in the same block - no cooldown wait
        vm.prank(user1);
        sapienVault.instantUnstake(STAKE_AMOUNT);

        assertFalse(sapienVault.hasActiveStake(user1));
    }

    function test_InstantUnstake_Partial_LeavesValidPosition() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        uint256 withdrawAmount = 40e18;
        uint256 expectedRemaining = STAKE_AMOUNT - withdrawAmount;
        uint256 userBalanceBefore = sapienToken.balanceOf(user1);

        vm.prank(user1);
        sapienVault.instantUnstake(withdrawAmount);

        assertEq(sapienToken.balanceOf(user1), userBalanceBefore + withdrawAmount);
        assertEq(sapienVault.totalStaked(), expectedRemaining);
        assertEq(sapienVault.getTotalStaked(user1), expectedRemaining);
        assertTrue(sapienVault.hasActiveStake(user1));
    }

    function test_InstantUnstake_RemainderBelowMinimum_ForcesFullExit() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        // Leaving less than MINIMUM_STAKE_AMOUNT should force a full exit
        uint256 withdrawAmount = STAKE_AMOUNT - (MINIMUM_STAKE / 2);
        uint256 userBalanceBefore = sapienToken.balanceOf(user1);

        vm.expectEmit(true, false, false, true);
        emit ISapienVault.InstantUnstaked(user1, STAKE_AMOUNT);

        vm.prank(user1);
        sapienVault.instantUnstake(withdrawAmount);

        // Full stake returned despite requesting less
        assertEq(sapienToken.balanceOf(user1), userBalanceBefore + STAKE_AMOUNT);
        assertEq(sapienVault.totalStaked(), 0);
        assertFalse(sapienVault.hasActiveStake(user1));
    }

    // =============================================================================
    // COOLDOWN STATE CLEANUP
    // =============================================================================

    function test_InstantUnstake_ClearsNormalCooldown() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        // Move past lockup and initiate a normal unstake cooldown
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);
        vm.prank(user1);
        sapienVault.initiateUnstake(STAKE_AMOUNT);
        assertEq(sapienVault.getTotalInCooldown(user1), STAKE_AMOUNT);

        vm.prank(user1);
        sapienVault.instantUnstake(STAKE_AMOUNT);

        assertFalse(sapienVault.hasActiveStake(user1));
        assertEq(sapienVault.getTotalInCooldown(user1), 0);
    }

    function test_InstantUnstake_ClearsEarlyUnstakeCooldown() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        // Initiate an early unstake cooldown while locked
        vm.prank(user1);
        sapienVault.initiateEarlyUnstake(STAKE_AMOUNT);
        assertEq(sapienVault.getEarlyUnstakeCooldownAmount(user1), STAKE_AMOUNT);

        vm.prank(user1);
        sapienVault.instantUnstake(STAKE_AMOUNT);

        assertFalse(sapienVault.hasActiveStake(user1));
        assertEq(sapienVault.getEarlyUnstakeCooldownAmount(user1), 0);
    }

    // =============================================================================
    // STAKING STATE UPDATE: full UserStake struct correctness
    // =============================================================================

    /// @dev Verifies every field of the UserStake struct is zeroed after a full instant unstake.
    function test_InstantUnstake_FullExit_ResetsEntireStakeStruct() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        vm.prank(user1);
        sapienVault.instantUnstake(STAKE_AMOUNT);

        ISapienVault.UserStake memory stake = sapienVault.getUserStake(user1);
        assertEq(stake.amount, 0, "amount");
        assertEq(stake.cooldownAmount, 0, "cooldownAmount");
        assertEq(stake.weightedStartTime, 0, "weightedStartTime");
        assertEq(stake.effectiveLockUpPeriod, 0, "effectiveLockUpPeriod");
        assertEq(stake.cooldownStart, 0, "cooldownStart");
        assertEq(stake.lastUpdateTime, 0, "lastUpdateTime");
        assertEq(stake.earlyUnstakeCooldownStart, 0, "earlyUnstakeCooldownStart");
        assertEq(stake.effectiveMultiplier, 0, "effectiveMultiplier");
        assertEq(stake.earlyUnstakeCooldownAmount, 0, "earlyUnstakeCooldownAmount");
    }

    /// @dev Verifies the full struct is updated correctly after a partial instant unstake
    ///      with no cooldowns active: amount/multiplier/lastUpdateTime updated, lockup fields preserved.
    function test_InstantUnstake_Partial_UpdatesStakeStructCorrectly() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        ISapienVault.UserStake memory before = sapienVault.getUserStake(user1);

        uint256 withdrawAmount = 40e18;
        uint256 expectedRemaining = STAKE_AMOUNT - withdrawAmount;
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(expectedRemaining, LOCK_30_DAYS);

        vm.prank(user1);
        sapienVault.instantUnstake(withdrawAmount);

        ISapienVault.UserStake memory afterStake = sapienVault.getUserStake(user1);

        // Reduced amount and recalculated multiplier
        assertEq(afterStake.amount, expectedRemaining, "amount");
        assertEq(afterStake.effectiveMultiplier, expectedMultiplier, "effectiveMultiplier");
        // lastUpdateTime bumped to the unstake block
        assertEq(afterStake.lastUpdateTime, block.timestamp, "lastUpdateTime");

        // Lockup-defining fields must be preserved on a partial unstake
        assertEq(afterStake.weightedStartTime, before.weightedStartTime, "weightedStartTime");
        assertEq(afterStake.effectiveLockUpPeriod, before.effectiveLockUpPeriod, "effectiveLockUpPeriod");

        // No cooldowns were active, so they must remain cleared
        assertEq(afterStake.cooldownAmount, 0, "cooldownAmount");
        assertEq(afterStake.cooldownStart, 0, "cooldownStart");
        assertEq(afterStake.earlyUnstakeCooldownAmount, 0, "earlyUnstakeCooldownAmount");
        assertEq(afterStake.earlyUnstakeCooldownStart, 0, "earlyUnstakeCooldownStart");

        // Cross-check against the public getters / summary for consistency
        assertEq(sapienVault.getTotalStaked(user1), expectedRemaining, "getTotalStaked");
        assertEq(sapienVault.getUserMultiplier(user1), expectedMultiplier, "getUserMultiplier");
        assertEq(sapienVault.getEffectiveStakeAmount(user1), expectedRemaining, "getEffectiveStakeAmount");
        assertEq(sapienVault.getUserLockupPeriod(user1), LOCK_30_DAYS, "getUserLockupPeriod");
        assertTrue(sapienVault.hasActiveStake(user1), "hasActiveStake");
    }

    /// @dev Partial instant unstake must decrement (not just clear) an active normal cooldown amount.
    function test_InstantUnstake_Partial_ReducesNormalCooldownAmount() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        // Move past lockup and queue part of the stake into the unstaking cooldown.
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);
        vm.prank(user1);
        sapienVault.initiateUnstake(60e18);

        ISapienVault.UserStake memory before = sapienVault.getUserStake(user1);
        assertEq(before.cooldownAmount, 60e18, "setup cooldownAmount");
        assertGt(before.cooldownStart, 0, "setup cooldownStart");

        uint256 withdrawAmount = 30e18;
        uint256 expectedRemaining = STAKE_AMOUNT - withdrawAmount;
        uint256 expectedCooldown = 60e18 - withdrawAmount;

        vm.prank(user1);
        sapienVault.instantUnstake(withdrawAmount);

        ISapienVault.UserStake memory afterStake = sapienVault.getUserStake(user1);

        assertEq(afterStake.amount, expectedRemaining, "amount");
        assertEq(afterStake.cooldownAmount, expectedCooldown, "cooldownAmount decremented");
        // Cooldown start is preserved because cooldown is only partially drained.
        assertEq(afterStake.cooldownStart, before.cooldownStart, "cooldownStart preserved");
        assertEq(
            afterStake.effectiveMultiplier,
            sapienVault.calculateMultiplier(expectedRemaining, LOCK_30_DAYS),
            "effectiveMultiplier"
        );
        assertEq(afterStake.lastUpdateTime, block.timestamp, "lastUpdateTime");

        // Getter consistency
        assertEq(sapienVault.getTotalInCooldown(user1), expectedCooldown, "getTotalInCooldown");
        assertEq(sapienVault.getEffectiveStakeAmount(user1), expectedRemaining - expectedCooldown, "effectiveStake");
    }

    /// @dev Partial instant unstake must decrement (not just clear) an active early-unstake cooldown amount.
    function test_InstantUnstake_Partial_ReducesEarlyUnstakeCooldownAmount() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        // While still locked, queue part of the stake into the early-unstake cooldown.
        vm.prank(user1);
        sapienVault.initiateEarlyUnstake(60e18);

        ISapienVault.UserStake memory before = sapienVault.getUserStake(user1);
        assertEq(before.earlyUnstakeCooldownAmount, 60e18, "setup earlyUnstakeCooldownAmount");
        assertGt(before.earlyUnstakeCooldownStart, 0, "setup earlyUnstakeCooldownStart");

        uint256 withdrawAmount = 30e18;
        uint256 expectedRemaining = STAKE_AMOUNT - withdrawAmount;
        uint256 expectedEarlyCooldown = 60e18 - withdrawAmount;

        vm.prank(user1);
        sapienVault.instantUnstake(withdrawAmount);

        ISapienVault.UserStake memory afterStake = sapienVault.getUserStake(user1);

        assertEq(afterStake.amount, expectedRemaining, "amount");
        assertEq(afterStake.earlyUnstakeCooldownAmount, expectedEarlyCooldown, "earlyUnstakeCooldownAmount decremented");
        // Start is preserved because the early cooldown is only partially drained.
        assertEq(afterStake.earlyUnstakeCooldownStart, before.earlyUnstakeCooldownStart, "earlyUnstakeCooldownStart preserved");
        assertEq(
            afterStake.effectiveMultiplier,
            sapienVault.calculateMultiplier(expectedRemaining, LOCK_30_DAYS),
            "effectiveMultiplier"
        );
        assertEq(afterStake.lastUpdateTime, block.timestamp, "lastUpdateTime");

        // Getter consistency
        assertEq(sapienVault.getEarlyUnstakeCooldownAmount(user1), expectedEarlyCooldown, "getEarlyUnstakeCooldownAmount");
        assertEq(sapienVault.getEffectiveStakeAmount(user1), expectedRemaining - expectedEarlyCooldown, "effectiveStake");
    }

    // =============================================================================
    // REVERTS
    // =============================================================================

    function test_InstantUnstake_RevertsOnZeroAmount() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        vm.prank(user1);
        vm.expectRevert(ISapienVault.InvalidAmount.selector);
        sapienVault.instantUnstake(0);
    }

    function test_InstantUnstake_RevertsWhenNoStake() public {
        vm.prank(user1);
        vm.expectRevert(ISapienVault.NoStakeFound.selector);
        sapienVault.instantUnstake(STAKE_AMOUNT);
    }

    function test_InstantUnstake_RevertsWhenAmountExceedsBalance() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        vm.prank(user1);
        vm.expectRevert(ISapienVault.AmountExceedsAvailableBalance.selector);
        sapienVault.instantUnstake(STAKE_AMOUNT + 1);
    }

    function test_InstantUnstake_RevertsWhenPaused() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        vm.prank(pauser);
        sapienVault.pause();

        vm.prank(user1);
        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        sapienVault.instantUnstake(STAKE_AMOUNT);
    }

    // =============================================================================
    // SECURITY: reentrancy protection
    // =============================================================================

    /// @dev Deploys a fresh vault backed by a malicious reentrant token and stakes for user1.
    function _deployReentrantVault() internal returns (SapienVault vault, ReentrantERC20 token) {
        token = new ReentrantERC20("Reentrant", "RE", 18);

        SapienVault impl = new SapienVault();
        bytes memory initData =
            abi.encodeWithSelector(SapienVault.initialize.selector, address(token), admin, pauser, treasury, sapienQA);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        vault = SapienVault(address(proxy));

        token.mint(user1, 100000e18);

        vm.startPrank(user1);
        token.approve(address(vault), STAKE_AMOUNT);
        vault.stake(STAKE_AMOUNT, LOCK_30_DAYS);
        vm.stopPrank();
    }

    function test_InstantUnstake_BlocksReentrancy_SameFunction() public {
        (SapienVault vault, ReentrantERC20 token) = _deployReentrantVault();

        // On the withdrawal transfer, the token re-enters instantUnstake.
        token.armAttack(address(vault), abi.encodeWithSelector(vault.instantUnstake.selector, STAKE_AMOUNT));

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        vault.instantUnstake(STAKE_AMOUNT);

        // State must be fully rolled back: stake intact, nothing leaked.
        assertEq(vault.getTotalStaked(user1), STAKE_AMOUNT);
        assertEq(vault.totalStaked(), STAKE_AMOUNT);
        assertEq(token.balanceOf(address(vault)), STAKE_AMOUNT);
    }

    function test_InstantUnstake_BlocksReentrancy_CrossFunction() public {
        (SapienVault vault, ReentrantERC20 token) = _deployReentrantVault();

        // On the withdrawal transfer, the token tries to re-enter a different state-changing function.
        token.armAttack(address(vault), abi.encodeWithSelector(vault.initiateUnstake.selector, STAKE_AMOUNT));

        vm.prank(user1);
        vm.expectRevert(ReentrancyGuardUpgradeable.ReentrancyGuardReentrantCall.selector);
        vault.instantUnstake(STAKE_AMOUNT);

        assertEq(vault.getTotalStaked(user1), STAKE_AMOUNT);
        assertEq(vault.totalStaked(), STAKE_AMOUNT);
    }

    // =============================================================================
    // SECURITY: solvency, isolation, and accounting invariants
    // =============================================================================

    function test_InstantUnstake_CannotDrainOtherUsersFunds() public {
        _stakeAs(user1, STAKE_AMOUNT, LOCK_30_DAYS);
        _stakeAs(user2, STAKE_AMOUNT, LOCK_30_DAYS);

        uint256 vaultBalanceBefore = sapienToken.balanceOf(address(sapienVault));
        assertEq(vaultBalanceBefore, 2 * STAKE_AMOUNT);

        // user1 can never withdraw more than their own stake, even though the vault holds more.
        vm.prank(user1);
        vm.expectRevert(ISapienVault.AmountExceedsAvailableBalance.selector);
        sapienVault.instantUnstake(STAKE_AMOUNT + 1);

        // user1 fully exits; user2's position is untouched.
        vm.prank(user1);
        sapienVault.instantUnstake(STAKE_AMOUNT);

        assertEq(sapienVault.getTotalStaked(user2), STAKE_AMOUNT);
        assertEq(sapienVault.totalStaked(), STAKE_AMOUNT);
        assertEq(sapienToken.balanceOf(address(sapienVault)), STAKE_AMOUNT);
        assertTrue(sapienVault.hasActiveStake(user2));
    }

    function test_InstantUnstake_RepeatedCallsCannotExceedStake() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        vm.prank(user1);
        sapienVault.instantUnstake(60e18);
        assertEq(sapienVault.getTotalStaked(user1), 40e18);

        // Requesting more than what remains reverts.
        vm.prank(user1);
        vm.expectRevert(ISapienVault.AmountExceedsAvailableBalance.selector);
        sapienVault.instantUnstake(41e18);

        // The exact remaining balance succeeds and closes the position.
        vm.prank(user1);
        sapienVault.instantUnstake(40e18);
        assertFalse(sapienVault.hasActiveStake(user1));
        assertEq(sapienVault.totalStaked(), 0);
    }

    function test_InstantUnstake_AccountingInvariant_AfterPartial() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        vm.prank(user1);
        sapienVault.instantUnstake(30e18);

        uint256 remaining = STAKE_AMOUNT - 30e18;
        // Contract token balance must always equal totalStaked (vault holds only stakes here).
        assertEq(sapienToken.balanceOf(address(sapienVault)), sapienVault.totalStaked());
        assertEq(sapienVault.totalStaked(), remaining);
        assertEq(sapienVault.getTotalStaked(user1), remaining);
        assertEq(sapienVault.getEffectiveStakeAmount(user1), remaining);
    }

    function test_InstantUnstake_RecalculatesMultiplierAfterPartial() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        vm.prank(user1);
        sapienVault.instantUnstake(50e18);

        uint256 expected = sapienVault.calculateMultiplier(50e18, LOCK_30_DAYS);
        assertEq(sapienVault.getUserMultiplier(user1), expected);
    }

    function test_InstantUnstake_QAPenaltyConsistentAfterPartial() public {
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        vm.prank(user1);
        sapienVault.instantUnstake(40e18); // 60e18 remains

        uint256 treasuryBefore = sapienToken.balanceOf(treasury);

        // QA penalty must still apply cleanly against the reduced stake.
        vm.prank(sapienQA);
        uint256 applied = sapienVault.processQAPenalty(user1, 20e18);

        assertEq(applied, 20e18);
        assertEq(sapienVault.getTotalStaked(user1), 40e18);
        assertEq(sapienVault.totalStaked(), 40e18);
        assertEq(sapienToken.balanceOf(treasury), treasuryBefore + 20e18);
        // Invariant: vault balance still backs totalStaked exactly.
        assertEq(sapienToken.balanceOf(address(sapienVault)), sapienVault.totalStaked());
    }

    // =============================================================================
    // SECURITY: fuzzing
    // =============================================================================

    function testFuzz_InstantUnstake_BalancesConsistent(uint256 amount) public {
        amount = bound(amount, 1, STAKE_AMOUNT);
        _stake(STAKE_AMOUNT, LOCK_30_DAYS);

        uint256 userBalanceBefore = sapienToken.balanceOf(user1);

        // Mirror the contract's force-full-exit rule.
        uint256 remainder = STAKE_AMOUNT - amount;
        uint256 effectiveWithdraw = (remainder > 0 && remainder < MINIMUM_STAKE) ? STAKE_AMOUNT : amount;
        uint256 expectedRemaining = STAKE_AMOUNT - effectiveWithdraw;

        vm.prank(user1);
        sapienVault.instantUnstake(amount);

        assertEq(sapienToken.balanceOf(user1), userBalanceBefore + effectiveWithdraw);
        assertEq(sapienVault.totalStaked(), expectedRemaining);
        assertEq(sapienToken.balanceOf(address(sapienVault)), expectedRemaining);

        if (expectedRemaining == 0) {
            assertFalse(sapienVault.hasActiveStake(user1));
        } else {
            assertEq(sapienVault.getTotalStaked(user1), expectedRemaining);
        }
    }
}
