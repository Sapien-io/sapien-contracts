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
