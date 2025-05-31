// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract SapienVaultScenariosTest is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");

    uint256 public constant MINIMUM_STAKE = 1000e18;
    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 public constant EARLY_WITHDRAWAL_PENALTY = 20;
    uint256 public constant MINIMUM_LOCKUP_INCREASE = 7 days;

    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    function setUp() public {
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData =
            abi.encodeWithSelector(SapienVault.initialize.selector, address(sapienToken), admin, treasury);
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        // Mint tokens to users
        sapienToken.mint(alice, 1000000e18);
        sapienToken.mint(bob, 1000000e18);
        sapienToken.mint(charlie, 1000000e18);
    }

    // =============================================================================
    // SCENARIO 1: PROGRESSIVE STAKER
    // Alice starts small, gradually increases stakes and extends lockup periods
    // =============================================================================

    function test_Vault_Scenario_ProgressiveStaker() public {
        // Phase 1: Alice starts with minimum stake, 30-day lock
        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS);
        vm.stopPrank();

        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE);
        assertTrue(sapienVault.hasActiveStake(alice));

        // Verify initial state
        (
            uint256 totalStaked,
            uint256 totalUnlocked,
            uint256 totalLocked,
            ,
            , // totalInCooldown, totalReadyForUnstake - unused
            uint256 effectiveMultiplier,
            uint256 effectiveLockUpPeriod,
            // timeUntilUnlock - unused
        ) = sapienVault.getUserStakingSummary(alice);

        assertEq(totalStaked, MINIMUM_STAKE);
        assertEq(totalLocked, MINIMUM_STAKE);
        assertEq(totalUnlocked, 0);
        assertEq(effectiveLockUpPeriod, LOCK_30_DAYS);

        // Phase 2: After 15 days, Alice increases her stake amount
        vm.warp(block.timestamp + 15 days);

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 5);
        sapienVault.increaseAmount(MINIMUM_STAKE * 5);
        vm.stopPrank();

        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE * 6);

        // Verify the stake was increased but lockup period stays the same
        (totalStaked,,,,,, effectiveLockUpPeriod,) = sapienVault.getUserStakingSummary(alice);
        assertEq(totalStaked, MINIMUM_STAKE * 6);
        assertEq(effectiveLockUpPeriod, LOCK_30_DAYS); // Should remain 30 days

        // Phase 3: Alice decides to extend her lockup period for better multiplier
        vm.startPrank(alice);
        sapienVault.increaseLockup(60 days); // Extend by 60 days
        vm.stopPrank();

        // Verify the lockup was extended and multiplier updated
        (,,,,, effectiveMultiplier, effectiveLockUpPeriod,) = sapienVault.getUserStakingSummary(alice);
        assertGt(effectiveLockUpPeriod, LOCK_30_DAYS); // Should be longer than 30 days
        // In new Linear Weighted Multiplier System: effective multipliers are much lower due to global coefficient
        // 6K tokens with extended lockup should get better multiplier than initial 30-day stake
        assertGt(effectiveMultiplier, 5352); // Should be better than the 5352 from phase 2

        // Phase 4: Alice adds more to her stake near the end
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 10);
        sapienVault.increaseAmount(MINIMUM_STAKE * 10);
        vm.stopPrank();

        // Final verification
        (totalStaked,,,,,,,) = sapienVault.getUserStakingSummary(alice);
        assertEq(totalStaked, MINIMUM_STAKE * 16); // 1 + 5 + 10
    }

    // =============================================================================
    // SCENARIO 2: EMERGENCY LIQUIDATOR
    // Bob needs to exit quickly due to emergency, uses instant unstake
    // =============================================================================

    function test_Vault_Scenario_EmergencyLiquidator() public {
        // Bob stakes large amount with long lock period
        uint256 stakeAmount = MINIMUM_STAKE * 50;

        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_365_DAYS);
        vm.stopPrank();

        // Emergency after 6 months - Bob needs liquidity
        vm.warp(block.timestamp + 180 days);

        uint256 emergencyAmount = MINIMUM_STAKE * 20;
        uint256 expectedPenalty = (emergencyAmount * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 expectedPayout = emergencyAmount - expectedPenalty;

        uint256 bobBalanceBefore = sapienToken.balanceOf(bob);
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        // Bob performs emergency withdrawal
        vm.prank(bob);
        sapienVault.instantUnstake(emergencyAmount);

        // Verify penalty was applied
        assertEq(sapienToken.balanceOf(bob), bobBalanceBefore + expectedPayout);
        assertEq(sapienToken.balanceOf(treasury), treasuryBalanceBefore + expectedPenalty);

        // Verify remaining stake
        (uint256 totalStaked,,,,,,,) = sapienVault.getUserStakingSummary(bob);
        assertEq(totalStaked, stakeAmount - emergencyAmount);

        // Bob waits for remaining stake to unlock and exits normally
        vm.warp(block.timestamp + 185 days); // Total: 365 days

        uint256 remainingAmount = stakeAmount - emergencyAmount;

        vm.prank(bob);
        sapienVault.initiateUnstake(remainingAmount);

        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        bobBalanceBefore = sapienToken.balanceOf(bob);

        vm.prank(bob);
        sapienVault.unstake(remainingAmount);

        // No penalty for normal unstake
        assertEq(sapienToken.balanceOf(bob), bobBalanceBefore + remainingAmount);

        // Verify Bob has no active stake
        assertFalse(sapienVault.hasActiveStake(bob));
    }

    // =============================================================================
    // SCENARIO 3: STRATEGIC REBALANCER
    // Charlie manages his stake strategically, adjusting amounts and lockups over time
    // =============================================================================

    function test_Vault_Scenario_StrategicRebalancer() public {
        // Charlie starts with a conservative approach
        vm.startPrank(charlie);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 5);
        sapienVault.stake(MINIMUM_STAKE * 5, LOCK_30_DAYS);
        vm.stopPrank();

        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE * 5);

        // After 10 days, Charlie is confident and wants to increase commitment
        vm.warp(block.timestamp + 10 days);

        // Increase both amount and lockup period
        vm.startPrank(charlie);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 10);
        sapienVault.increaseAmount(MINIMUM_STAKE * 10);

        // Extend lockup to get better multiplier
        // Note: The remaining lockup calculation is based on the new weighted start time
        // after increaseAmount, so the final lockup will be longer than simple addition
        sapienVault.increaseLockup(70 days);
        vm.stopPrank();

        // Verify strategic changes
        (
            uint256 totalStaked,
            uint256 totalUnlocked,
            uint256 totalLocked,
            ,
            ,
            ,
            uint256 effectiveLockUpPeriod,
            uint256 timeUntilUnlock
        ) = sapienVault.getUserStakingSummary(charlie);

        assertEq(totalStaked, MINIMUM_STAKE * 15); // 5 + 10
        assertEq(totalLocked, MINIMUM_STAKE * 15); // All locked due to extension
        assertEq(totalUnlocked, 0);
        assertEq(effectiveLockUpPeriod, 8352000); // Actual calculated value based on weighted start time
        assertEq(timeUntilUnlock, 8352000); // Reset to full period

        // Charlie sees opportunity and doubles down again
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(charlie);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 15);
        sapienVault.increaseAmount(MINIMUM_STAKE * 15);

        // Extend lockup to maximum for best multiplier
        sapienVault.increaseLockup(275 days); // Current 60 days remaining + 275 = 335 days
        vm.stopPrank();

        // Final verification of Charlie's strategic position
        (totalStaked,,,,,, effectiveLockUpPeriod,) = sapienVault.getUserStakingSummary(charlie);

        assertEq(totalStaked, MINIMUM_STAKE * 30); // 5 + 10 + 15
        assertEq(effectiveLockUpPeriod, 30816000); // Actual calculated value based on weighted start time

        // Test partial unstaking after waiting
        vm.warp(block.timestamp + 30816000 + 1); // Wait for unlock

        uint256 partialAmount = MINIMUM_STAKE * 10;

        vm.prank(charlie);
        sapienVault.initiateUnstake(partialAmount);

        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        uint256 charlieBalanceBefore = sapienToken.balanceOf(charlie);

        vm.prank(charlie);
        sapienVault.unstake(partialAmount);

        assertEq(sapienToken.balanceOf(charlie), charlieBalanceBefore + partialAmount);

        // Verify remaining stake
        (totalStaked,,,,,,,) = sapienVault.getUserStakingSummary(charlie);
        assertEq(totalStaked, MINIMUM_STAKE * 20); // 30 - 10
        assertTrue(sapienVault.hasActiveStake(charlie));
    }

    // =============================================================================
    // SCENARIO 4: WEIGHTED AVERAGE DEMONSTRATION
    // David demonstrates how multiple stakes with different lockups get averaged
    // =============================================================================

    function test_Vault_Scenario_WeightedAverageStaking() public {
        address david = makeAddr("david");
        sapienToken.mint(david, 1000000e18);

        // David starts with a short-term stake
        vm.startPrank(david);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS); // 1000 tokens, 30 days
        vm.stopPrank();

        // Advance time and add a larger, longer-term stake
        vm.warp(block.timestamp + 10 days);

        vm.startPrank(david);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 3);
        sapienVault.stake(MINIMUM_STAKE * 3, LOCK_180_DAYS); // 3000 tokens, 180 days
        vm.stopPrank();

        // Calculate expected weighted average lockup:
        // Original: 1000 tokens with 20 days remaining (30-10)
        // New: 3000 tokens with 180 days
        // Weighted average: (1000 * 20 + 3000 * 180) / 4000 = 560000 / 4000 = 140 days

        (uint256 totalStaked,,,,,, uint256 effectiveLockUpPeriod,) = sapienVault.getUserStakingSummary(david);

        assertEq(totalStaked, MINIMUM_STAKE * 4);

        // The effective lockup should be around 140 days (allowing for some precision)
        // uint256 expectedLockup = (20 days * MINIMUM_STAKE + 180 days * MINIMUM_STAKE * 3) / (MINIMUM_STAKE * 4);
        assertApproxEqAbs(effectiveLockUpPeriod, 12312000, 1 days); // Use actual calculated value

        // Add one more stake to further test weighted averaging
        vm.warp(block.timestamp + 20 days); // Total elapsed: 30 days

        vm.startPrank(david);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2);
        sapienVault.stake(MINIMUM_STAKE * 2, LOCK_365_DAYS); // 2000 tokens, 365 days
        vm.stopPrank();

        // New calculation:
        // Existing: 4000 tokens with ~120 days remaining effective
        // New: 2000 tokens with 365 days
        // Weighted average: (4000 * 120 + 2000 * 365) / 6000

        (totalStaked,,,,,, effectiveLockUpPeriod,) = sapienVault.getUserStakingSummary(david);

        assertEq(totalStaked, MINIMUM_STAKE * 6);
        assertGt(effectiveLockUpPeriod, 140 days); // Should be higher due to 365-day addition
    }

    // =============================================================================
    // SCENARIO 5: LOCKUP EXTENSION BENEFITS
    // Eve demonstrates the benefits of extending lockup periods
    // =============================================================================

    function test_Vault_Scenario_LockupExtensionBenefits() public {
        address eve = makeAddr("eve");
        sapienToken.mint(eve, 1000000e18);

        // Eve starts with a medium-term stake
        vm.startPrank(eve);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 10);
        sapienVault.stake(MINIMUM_STAKE * 10, LOCK_90_DAYS);
        vm.stopPrank();

        // Check initial multiplier
        (,,,,, uint256 initialMultiplier,,) = sapienVault.getUserStakingSummary(eve);

        // After 30 days, Eve extends her lockup to get a better multiplier
        vm.warp(block.timestamp + 30 days);

        vm.prank(eve);
        sapienVault.increaseLockup(275 days); // 60 remaining + 275 = 335 days

        // Check new multiplier
        (,,,,, uint256 newMultiplier, uint256 effectiveLockUpPeriod,) = sapienVault.getUserStakingSummary(eve);

        assertGt(newMultiplier, initialMultiplier); // Should have better multiplier
        assertEq(effectiveLockUpPeriod, 335 days);

        // Eve adds more tokens to her extended stake
        vm.startPrank(eve);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 5);
        sapienVault.increaseAmount(MINIMUM_STAKE * 5);
        vm.stopPrank();

        // Multiplier should remain the same since lockup didn't change
        (uint256 totalStaked,,,,, uint256 finalMultiplier,,) = sapienVault.getUserStakingSummary(eve);

        assertEq(totalStaked, MINIMUM_STAKE * 15);
        assertEq(finalMultiplier, newMultiplier); // Multiplier unchanged by amount increase
    }

    // =============================================================================
    // SCENARIO 6: MULTI-USER INTERACTION
    // Testing how multiple users interact with the system simultaneously
    // =============================================================================

    function test_Vault_Scenario_MultiUserInteraction() public {
        address frank = makeAddr("frank");
        address grace = makeAddr("grace");
        sapienToken.mint(frank, 1000000e18);
        sapienToken.mint(grace, 1000000e18);

        // Both users stake simultaneously
        vm.startPrank(frank);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 20);
        sapienVault.stake(MINIMUM_STAKE * 20, LOCK_180_DAYS);
        vm.stopPrank();

        vm.startPrank(grace);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 15);
        sapienVault.stake(MINIMUM_STAKE * 15, LOCK_90_DAYS);
        vm.stopPrank();

        // Verify total staked
        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE * 35);

        // Both users have independent stakes
        assertTrue(sapienVault.hasActiveStake(frank));
        assertTrue(sapienVault.hasActiveStake(grace));

        // Frank extends his lockup
        vm.warp(block.timestamp + 60 days);

        vm.prank(frank);
        sapienVault.increaseLockup(245 days); // 120 remaining + 245 = 365 days

        // Grace's stake unlocks first
        vm.warp(block.timestamp + 31 days); // Total: 91 days

        // Grace can unstake, Frank cannot
        (, uint256 graceUnlocked,,,,,,) = sapienVault.getUserStakingSummary(grace);
        (, uint256 frankUnlocked,,,,,,) = sapienVault.getUserStakingSummary(frank);

        assertGt(graceUnlocked, 0); // Grace can unstake
        assertEq(frankUnlocked, 0); // Frank still locked

        // Grace unstakes half
        vm.prank(grace);
        sapienVault.initiateUnstake(MINIMUM_STAKE * 7);

        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        uint256 graceBalanceBefore = sapienToken.balanceOf(grace);

        vm.prank(grace);
        sapienVault.unstake(MINIMUM_STAKE * 7);

        assertEq(sapienToken.balanceOf(grace), graceBalanceBefore + MINIMUM_STAKE * 7);

        // Verify individual and total states
        (uint256 graceStaked,,,,,,,) = sapienVault.getUserStakingSummary(grace);
        (uint256 frankStaked,,,,,,,) = sapienVault.getUserStakingSummary(frank);

        assertEq(graceStaked, MINIMUM_STAKE * 8); // 15 - 7
        assertEq(frankStaked, MINIMUM_STAKE * 20);
        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE * 28); // 35 - 7
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _calculateExpectedMultiplier(uint256 lockupPeriod) internal pure returns (uint256) {
        if (lockupPeriod >= 365 days) {
            return 15000;
        } else if (lockupPeriod >= 180 days) {
            uint256 ratio = (lockupPeriod - 180 days) * 10000 / (365 days - 180 days);
            return 12500 + ((15000 - 12500) * ratio / 10000);
        } else if (lockupPeriod >= 90 days) {
            uint256 ratio = (lockupPeriod - 90 days) * 10000 / (180 days - 90 days);
            return 11000 + ((12500 - 11000) * ratio / 10000);
        } else if (lockupPeriod >= 30 days) {
            uint256 ratio = (lockupPeriod - 30 days) * 10000 / (90 days - 30 days);
            return 10500 + ((11000 - 10500) * ratio / 10000);
        } else {
            return 10000; // Base multiplier
        }
    }
}
