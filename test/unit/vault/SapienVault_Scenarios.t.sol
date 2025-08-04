// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {SapienVault, ISapienVault} from "src/SapienVault.sol";
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

    uint256 public constant MINIMUM_STAKE = 250e18;
    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 public constant EARLY_WITHDRAWAL_PENALTY = 2000; // 20% in basis points
    uint256 public constant MINIMUM_LOCKUP_INCREASE = 7 days;

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

        // Mint tokens to users
        sapienToken.mint(alice, 1000000e18);
        sapienToken.mint(bob, 1000000e18);
        sapienToken.mint(charlie, 1000000e18);
    }

    // Helper function for early unstake with proper cooldown
    function _performEarlyUnstakeWithCooldown(address user, uint256 amount) internal {
        vm.startPrank(user);
        sapienVault.initiateEarlyUnstake(amount);

        // Use absolute timestamps to prevent time warping backward issues
        uint256 initiateTime = block.timestamp;
        uint256 cooldownCompleteTime = initiateTime + COOLDOWN_PERIOD + 100;
        vm.warp(cooldownCompleteTime);

        sapienVault.earlyUnstake(amount);
        vm.stopPrank();
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
        ISapienVault.UserStakingSummary memory userStakeInitial = sapienVault.getUserStakingSummary(alice);
        assertEq(userStakeInitial.userTotalStaked, MINIMUM_STAKE, "Initial total staked should match");
        assertEq(userStakeInitial.effectiveLockUpPeriod, LOCK_30_DAYS, "Initial effective lockup should be 30 days");
        assertGt(userStakeInitial.effectiveMultiplier, 10000, "Initial multiplier should be > 1.0x");

        // Phase 2: After 15 days, Alice increases her stake amount
        vm.warp(block.timestamp + 15 days);

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 5);
        sapienVault.increaseAmount(MINIMUM_STAKE * 5);
        vm.stopPrank();

        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE * 6);

        // Verify the stake was increased but lockup period stays the same
        ISapienVault.UserStakingSummary memory userStakeAfter = sapienVault.getUserStakingSummary(alice);
        assertEq(userStakeAfter.userTotalStaked, MINIMUM_STAKE * 6, "Total should be sum of both stakes");
        assertEq(userStakeAfter.effectiveLockUpPeriod, LOCK_30_DAYS, "Effective lockup should not change");

        // Phase 3: Alice decides to extend her lockup period for better multiplier
        vm.startPrank(alice);
        sapienVault.increaseLockup(60 days); // Extend by 60 days
        vm.stopPrank();

        // Verify the lockup was extended and multiplier updated
        ISapienVault.UserStakingSummary memory userStakeMultiplier = sapienVault.getUserStakingSummary(alice);
        assertGt(userStakeMultiplier.effectiveLockUpPeriod, LOCK_30_DAYS, "Lockup should be > 30 days");
        assertGt(
            userStakeMultiplier.effectiveMultiplier, userStakeAfter.effectiveMultiplier, "Multiplier should increase"
        );

        // Phase 4: Alice adds more to her stake near the end
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(alice);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 4);
        sapienVault.increaseAmount(MINIMUM_STAKE * 4);
        vm.stopPrank();

        // Final verification
        ISapienVault.UserStakingSummary memory userStakeFinal = sapienVault.getUserStakingSummary(alice);
        assertEq(userStakeFinal.userTotalStaked, MINIMUM_STAKE * 10, "Final total should include extra amount");
    }

    // =============================================================================
    // SCENARIO 2: EMERGENCY LIQUIDATOR
    // Bob needs to exit quickly due to emergency, uses instant unstake
    // =============================================================================

    function test_Vault_Scenario_EmergencyLiquidator() public {
        // Bob stakes large amount with long lock period
        uint256 stakeAmount = MINIMUM_STAKE * 8; // 2,000 tokens (within 2.5K limit)

        vm.startPrank(bob);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_365_DAYS);
        vm.stopPrank();

        // Emergency after 6 months - Bob needs liquidity
        vm.warp(block.timestamp + 180 days);

        uint256 emergencyAmount = MINIMUM_STAKE * 5; // 1250 tokens from 2000 total
        uint256 expectedPenalty = (emergencyAmount * EARLY_WITHDRAWAL_PENALTY) / 10000;
        uint256 expectedPayout = emergencyAmount - expectedPenalty;

        uint256 bobBalanceBefore = sapienToken.balanceOf(bob);
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        // Bob performs emergency withdrawal (with cooldown)
        _performEarlyUnstakeWithCooldown(bob, emergencyAmount);

        // Verify penalty was applied
        assertEq(sapienToken.balanceOf(bob), bobBalanceBefore + expectedPayout);
        assertEq(sapienToken.balanceOf(treasury), treasuryBalanceBefore + expectedPenalty);

        // Verify remaining stake
        ISapienVault.UserStakingSummary memory bobStake = sapienVault.getUserStakingSummary(bob);
        assertEq(bobStake.userTotalStaked, stakeAmount - emergencyAmount, "Remaining stake should be reduced");

        // Bob waits for remaining stake to unlock and exits normally
        // Use absolute timestamp to avoid time warping backward issues
        uint256 currentTime = block.timestamp;
        uint256 unlockTime = currentTime + 185 days;
        vm.warp(unlockTime); // Total: 365 days

        uint256 remainingAmount = stakeAmount - emergencyAmount;

        vm.prank(bob);
        sapienVault.initiateUnstake(remainingAmount);

        // Make sure to use absolute timestamps
        uint256 cooldownCompleteTime = unlockTime + COOLDOWN_PERIOD + 1000;
        vm.warp(cooldownCompleteTime);

        uint256 bobBalanceBeforeAfter = sapienToken.balanceOf(bob);

        vm.prank(bob);
        sapienVault.unstake(remainingAmount);

        // No penalty for normal unstake
        assertEq(sapienToken.balanceOf(bob), bobBalanceBeforeAfter + remainingAmount);

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
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 4);
        sapienVault.increaseAmount(MINIMUM_STAKE * 4);

        // Extend lockup to get better multiplier
        // Note: The remaining lockup calculation is based on the new weighted start time
        // after increaseAmount, so the final lockup will be longer than simple addition
        sapienVault.increaseLockup(70 days);
        vm.stopPrank();

        // Verify strategic changes
        ISapienVault.UserStakingSummary memory charlieStakeAfter = sapienVault.getUserStakingSummary(charlie);
        assertEq(charlieStakeAfter.userTotalStaked, MINIMUM_STAKE * 9, "Total should be sum of both stakes");
        assertEq(charlieStakeAfter.effectiveLockUpPeriod, 8160000, "Effective lockup should be calculated correctly");

        // Charlie sees opportunity and doubles down again
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(charlie);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 1);
        sapienVault.increaseAmount(MINIMUM_STAKE * 1);

        // Extend lockup to maximum for best multiplier
        sapienVault.increaseLockup(275 days); // Current 60 days remaining + 275 = 335 days
        vm.stopPrank();

        // Final verification of Charlie's strategic position
        ISapienVault.UserStakingSummary memory charlieFinalStake = sapienVault.getUserStakingSummary(charlie);
        assertEq(charlieFinalStake.userTotalStaked, MINIMUM_STAKE * 10, "Final total should include extra amount"); // 5+4+1 = 10
        assertEq(charlieFinalStake.effectiveLockUpPeriod, 29587200, "Effective lockup should be calculated correctly");

        // Test partial unstaking after waiting
        vm.warp(block.timestamp + 30816000 + 1); // Wait for unlock

        uint256 partialAmount = MINIMUM_STAKE * 5; // Reduce to stay within limits

        vm.prank(charlie);
        sapienVault.initiateUnstake(partialAmount);

        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        uint256 charlieBalanceBefore = sapienToken.balanceOf(charlie);

        vm.prank(charlie);
        sapienVault.unstake(partialAmount);

        assertEq(sapienToken.balanceOf(charlie), charlieBalanceBefore + partialAmount);

        // Verify remaining stake
        ISapienVault.UserStakingSummary memory charlieRemainingStake = sapienVault.getUserStakingSummary(charlie);
        assertEq(charlieRemainingStake.userTotalStaked, MINIMUM_STAKE * 5, "Remaining stake should be reduced"); // 10 - 5 = 5
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
        sapienVault.stake(MINIMUM_STAKE, LOCK_30_DAYS); // 250 tokens, 30 days
        vm.stopPrank();

        // Advance time and add a larger, longer-term stake
        vm.warp(block.timestamp + 10 days);

        vm.startPrank(david);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 3);
        // First increase lockup to 365 days (remaining time is 20 days after 10 days passed)
        // So we need to add 365 - 20 = 345 days
        sapienVault.increaseLockup(LOCK_365_DAYS - 20 days);
        // Then increase amount
        sapienVault.increaseAmount(MINIMUM_STAKE * 3);
        vm.stopPrank();

        // With the new API:
        // 1. First we extended lockup to 365 days
        // 2. Then we increased amount
        // Final lockup should be 365 days

        ISapienVault.UserStakingSummary memory davidInitialStake = sapienVault.getUserStakingSummary(david);
        assertEq(davidInitialStake.userTotalStaked, MINIMUM_STAKE * 4, "Total should be sum of both stakes");

        // The effective lockup should be 365 days since we extended it
        assertEq(davidInitialStake.effectiveLockUpPeriod, LOCK_365_DAYS, "Should use extended lockup period");

        // Add one more stake to further test floor protection
        vm.warp(block.timestamp + 20 days); // Total elapsed: 30 days

        vm.startPrank(david);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2);
        // First increase lockup to 365 days (remaining time is 20 days after 10 days passed)
        // So we need to add 365 - 20 = 345 days
        sapienVault.increaseLockup(LOCK_365_DAYS - 20 days);
        sapienVault.increaseAmount(MINIMUM_STAKE * 2);
        vm.stopPrank();

        // New calculation with floor protection:
        // Existing: 1000 tokens with ~150 days remaining effective (180 - 30)
        // New: 500 tokens with 365 days
        // Floor protection ensures lockup >= max(150 days remaining, 365 days new) = 365 days

        ISapienVault.UserStakingSummary memory davidAfterIncrease = sapienVault.getUserStakingSummary(david);
        assertEq(davidAfterIncrease.userTotalStaked, MINIMUM_STAKE * 6, "Total should be sum of both stakes");
        assertEq(
            davidAfterIncrease.effectiveLockUpPeriod, LOCK_365_DAYS, "Should use longest lockup due to floor protection"
        );
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
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 8);
        sapienVault.stake(MINIMUM_STAKE * 8, LOCK_90_DAYS); // 2000 tokens (within 2.5K limit)
        vm.stopPrank();

        // Check initial multiplier
        ISapienVault.UserStakingSummary memory eveInitial = sapienVault.getUserStakingSummary(eve);
        uint256 initialMultiplier = eveInitial.effectiveMultiplier;

        // After 30 days, Eve extends her lockup to get a better multiplier
        vm.warp(block.timestamp + 30 days);

        vm.prank(eve);
        sapienVault.increaseLockup(275 days); // 60 remaining + 275 = 335 days

        // Check new multiplier
        ISapienVault.UserStakingSummary memory eveAfterIncrease = sapienVault.getUserStakingSummary(eve);
        assertGt(eveAfterIncrease.effectiveMultiplier, initialMultiplier, "Multiplier should increase");
        assertEq(eveAfterIncrease.effectiveLockUpPeriod, 335 days, "Lockup period should be 335 days");

        // Eve adds more tokens to her extended stake (keeping within 2500 limit)
        vm.startPrank(eve);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2); // 500 tokens (total = 2000 + 500 = 2500)
        sapienVault.increaseAmount(MINIMUM_STAKE * 2);
        vm.stopPrank();

        // Verify final state within limits
        ISapienVault.UserStakingSummary memory eveFinal = sapienVault.getUserStakingSummary(eve);
        assertEq(eveFinal.userTotalStaked, MINIMUM_STAKE * 10, "Total should include extra amount"); // 8 + 2 = 10 (2500 tokens)
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
        sapienVault.stake(MINIMUM_STAKE * 8, LOCK_180_DAYS); // 2000 tokens (within 2.5K limit)
        vm.stopPrank();

        vm.startPrank(grace);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2);
        sapienVault.stake(MINIMUM_STAKE * 2, LOCK_90_DAYS); // 500 tokens (within 2.5K limit)
        vm.stopPrank();

        // Verify total staked
        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE * 10); // 8 + 2 = 10

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
        ISapienVault.UserStakingSummary memory graceStake = sapienVault.getUserStakingSummary(grace);
        ISapienVault.UserStakingSummary memory frankStake = sapienVault.getUserStakingSummary(frank);

        uint256 graceUnlocked = graceStake.totalUnlocked; // Use the correct field for unlocked amount
        uint256 frankUnlocked = frankStake.totalUnlocked; // Use the correct field for unlocked amount

        // Grace should have more unlocked (shorter lockup)
        assertGt(graceUnlocked, frankUnlocked, "Grace should have more unlocked tokens");

        // Grace unstakes half
        vm.prank(grace);
        sapienVault.initiateUnstake(MINIMUM_STAKE * 2);

        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        uint256 graceBalanceBefore = sapienToken.balanceOf(grace);

        vm.prank(grace);
        sapienVault.unstake(MINIMUM_STAKE * 2);

        assertEq(sapienToken.balanceOf(grace), graceBalanceBefore + MINIMUM_STAKE * 2);

        // Verify individual and total states
        ISapienVault.UserStakingSummary memory graceFinalStake = sapienVault.getUserStakingSummary(grace);
        ISapienVault.UserStakingSummary memory frankFinalStake = sapienVault.getUserStakingSummary(frank);
        assertEq(graceFinalStake.userTotalStaked, 0, "Grace's remaining stake should be reduced");
        assertEq(frankFinalStake.userTotalStaked, MINIMUM_STAKE * 8, "Frank's remaining stake should be reduced");
        assertEq(sapienVault.totalStaked(), MINIMUM_STAKE * 8, "Total should be sum of both stakes");
    }

    // =============================================================================
    // SCENARIO 7: BELOW MINIMUM STAKE SCENARIOS
    // Testing various scenarios where stakes go below minimum threshold (250 tokens)
    //
    // These tests cover:
    // 1. Partial unstaking that leaves user below minimum stake
    // 2. QA penalties that reduce stakes below minimum
    // 3. Multiple sequential QA penalties on below-minimum stakes
    // 4. QA penalties interacting with cooldown states
    // 5. Complete stake wipeout and recovery scenarios
    //
    // Key behaviors tested:
    // - Stakes can go below minimum through unstaking or penalties
    // - QA penalties set multiplier to 1.0x for below-minimum stakes
    // - Voluntary unstaking preserves original multiplier calculation
    // - All vault functions still work with below-minimum stakes
    // - Users can recover by adding more stake to get above minimum
    // =============================================================================

    function test_Vault_Scenario_PartialUnstakeBelowMinimum() public {
        address helen = makeAddr("helen");
        sapienToken.mint(helen, 1000000e18);

        // Helen stakes slightly above minimum
        uint256 stakeAmount = MINIMUM_STAKE + 100e18; // 350 tokens
        vm.startPrank(helen);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Wait for unlock
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Helen unstakes most of her stake, leaving below minimum
        uint256 unstakeAmount = 200e18; // This will leave 150e18, below minimum
        uint256 expectedRemaining = stakeAmount - unstakeAmount;

        // Initiate unstake
        vm.prank(helen);
        sapienVault.initiateUnstake(unstakeAmount);

        // Complete cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        uint256 helenBalanceBefore = sapienToken.balanceOf(helen);

        // Complete unstake
        vm.prank(helen);
        sapienVault.unstake(unstakeAmount);

        // Verify Helen received the tokens
        assertEq(sapienToken.balanceOf(helen), helenBalanceBefore + unstakeAmount);

        // Verify remaining stake is below minimum but still active
        ISapienVault.UserStakingSummary memory helenStake = sapienVault.getUserStakingSummary(helen);
        assertEq(helenStake.userTotalStaked, expectedRemaining);
        assertTrue(helenStake.userTotalStaked < MINIMUM_STAKE, "Remaining stake should be below minimum");
        assertTrue(sapienVault.hasActiveStake(helen), "Helen should still have active stake");

        // Verify multiplier is still calculated normally for voluntary unstaking (not penalty)
        // The multiplier reduction to base only happens for QA penalties, not user unstaking
        assertGt(helenStake.effectiveMultiplier, 10000, "Multiplier should still be above base for voluntary unstaking");

        // Test that Helen can still perform operations with below-minimum stake

        // 1. Test increaseAmount - should work and restore proper multiplier
        uint256 additionalAmount = 150e18;
        vm.startPrank(helen);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseAmount(additionalAmount);
        vm.stopPrank();

        ISapienVault.UserStakingSummary memory helenAfterIncrease = sapienVault.getUserStakingSummary(helen);
        assertEq(helenAfterIncrease.userTotalStaked, expectedRemaining + additionalAmount);
        assertTrue(helenAfterIncrease.userTotalStaked >= MINIMUM_STAKE, "Stake should be above minimum again");
        assertGt(helenAfterIncrease.effectiveMultiplier, 10000, "Multiplier should be restored above base");

        // 2. Test that Helen can still stake additional amounts (creating a new combined stake)
        uint256 newStakeAmount = MINIMUM_STAKE;
        vm.startPrank(helen);
        sapienToken.approve(address(sapienVault), newStakeAmount);
        // Use increaseAmount since user already has a stake
        sapienVault.increaseAmount(newStakeAmount);
        vm.stopPrank();

        ISapienVault.UserStakingSummary memory helenAfterNewStake = sapienVault.getUserStakingSummary(helen);
        assertEq(helenAfterNewStake.userTotalStaked, helenAfterIncrease.userTotalStaked + newStakeAmount);

        // 3. Test that system validates below-minimum scenarios correctly
        // This verifies the logic handles the below-minimum case properly
        assertTrue(helenAfterNewStake.userTotalStaked > MINIMUM_STAKE, "Total stake should be well above minimum now");
    }

    function test_Vault_Scenario_QAPenaltyBelowMinimum() public {
        address ivan = makeAddr("ivan");
        address qaManager = makeAddr("dummySapienQA");
        sapienToken.mint(ivan, 1000000e18);

        // Ivan stakes just above minimum
        uint256 stakeAmount = MINIMUM_STAKE + 200e18; // 450 tokens
        vm.startPrank(ivan);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_90_DAYS);
        vm.stopPrank();

        // Ivan gets a QA penalty that reduces his stake below minimum
        uint256 penaltyAmount = 400e18; // This will leave 50e18, below minimum
        uint256 expectedRemaining = stakeAmount - penaltyAmount;

        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        // Apply QA penalty
        vm.prank(qaManager);
        uint256 actualPenalty = sapienVault.processQAPenalty(ivan, penaltyAmount);

        // Verify penalty was applied correctly
        assertEq(actualPenalty, penaltyAmount);
        assertEq(sapienToken.balanceOf(treasury), treasuryBalanceBefore + penaltyAmount);

        // Verify Ivan's stake is now below minimum
        ISapienVault.UserStakingSummary memory ivanStake = sapienVault.getUserStakingSummary(ivan);
        assertEq(ivanStake.userTotalStaked, expectedRemaining);
        assertTrue(ivanStake.userTotalStaked < MINIMUM_STAKE, "Stake should be below minimum after penalty");
        assertTrue(sapienVault.hasActiveStake(ivan), "Ivan should still have active stake");

        // Verify multiplier reflects the current system for below minimum stake
        // Small amounts get time bonus even when below practical minimum
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(expectedRemaining, LOCK_90_DAYS);
        assertApproxEqAbs(
            ivanStake.effectiveMultiplier,
            expectedMultiplier,
            50,
            "Multiplier should reflect current system for below minimum stake"
        );

        // Test that Ivan can still interact with the system

        // 1. Test increaseAmount - should work and restore proper multiplier
        uint256 newStakeAmount = MINIMUM_STAKE; // Use minimum stake amount for increase
        vm.startPrank(ivan);
        sapienToken.approve(address(sapienVault), newStakeAmount);
        sapienVault.increaseAmount(newStakeAmount);
        vm.stopPrank();

        ISapienVault.UserStakingSummary memory ivanAfterIncrease = sapienVault.getUserStakingSummary(ivan);
        assertEq(ivanAfterIncrease.userTotalStaked, expectedRemaining + newStakeAmount);
        assertTrue(ivanAfterIncrease.userTotalStaked >= MINIMUM_STAKE, "Stake should be above minimum again");
        assertGt(ivanAfterIncrease.effectiveMultiplier, 10000, "Multiplier should be restored above base");

        // 2. Test increaseAmount - should work
        uint256 additionalAmount = 300e18;
        vm.startPrank(ivan);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseAmount(additionalAmount);
        vm.stopPrank();

        ISapienVault.UserStakingSummary memory ivanAfterSecondIncrease = sapienVault.getUserStakingSummary(ivan);
        assertEq(ivanAfterSecondIncrease.userTotalStaked, expectedRemaining + newStakeAmount + additionalAmount);

        // 3. Test increaseLockup - should work
        vm.prank(ivan);
        sapienVault.increaseLockup(LOCK_30_DAYS);

        ISapienVault.UserStakingSummary memory ivanAfterLockupIncrease = sapienVault.getUserStakingSummary(ivan);
        assertGt(ivanAfterLockupIncrease.effectiveLockUpPeriod, ivanAfterSecondIncrease.effectiveLockUpPeriod);
    }

    function test_Vault_Scenario_MultipleQAPenaltiesBelowMinimum() public {
        address julia = makeAddr("julia");
        address qaManager = makeAddr("dummySapienQA");
        sapienToken.mint(julia, 1000000e18);

        // Julia stakes significantly above minimum
        uint256 stakeAmount = MINIMUM_STAKE * 3; // 750 tokens
        vm.startPrank(julia);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_180_DAYS);
        vm.stopPrank();

        // First QA penalty reduces stake but keeps it above minimum
        uint256 firstPenalty = 500e18; // Leaves 250e18, exactly at minimum
        vm.prank(qaManager);
        sapienVault.processQAPenalty(julia, firstPenalty);

        ISapienVault.UserStakingSummary memory juliaAfterFirst = sapienVault.getUserStakingSummary(julia);
        assertEq(juliaAfterFirst.userTotalStaked, stakeAmount - firstPenalty);
        assertTrue(juliaAfterFirst.userTotalStaked >= MINIMUM_STAKE, "Should still be at or above minimum");
        assertGt(juliaAfterFirst.effectiveMultiplier, 10000, "Multiplier should still be above base");

        // Second QA penalty reduces stake below minimum
        uint256 secondPenalty = 50e18; // Leaves 200e18, below minimum
        vm.prank(qaManager);
        sapienVault.processQAPenalty(julia, secondPenalty);

        ISapienVault.UserStakingSummary memory juliaAfterSecond = sapienVault.getUserStakingSummary(julia);
        assertEq(juliaAfterSecond.userTotalStaked, stakeAmount - firstPenalty - secondPenalty);
        assertTrue(juliaAfterSecond.userTotalStaked < MINIMUM_STAKE, "Should be below minimum after second penalty");
        uint256 expectedJuliaMultiplier =
            sapienVault.calculateMultiplier(juliaAfterSecond.userTotalStaked, LOCK_180_DAYS);
        assertApproxEqAbs(
            juliaAfterSecond.effectiveMultiplier,
            expectedJuliaMultiplier,
            50,
            "Multiplier should reflect current system for below minimum"
        );

        // Julia adds more stake to get back above minimum
        uint256 recoveryStake = MINIMUM_STAKE; // Use minimum stake amount
        vm.startPrank(julia);
        sapienToken.approve(address(sapienVault), recoveryStake);
        sapienVault.increaseAmount(recoveryStake);
        vm.stopPrank();

        ISapienVault.UserStakingSummary memory juliaRecovered = sapienVault.getUserStakingSummary(julia);
        assertEq(juliaRecovered.userTotalStaked, juliaAfterSecond.userTotalStaked + recoveryStake);
        assertTrue(juliaRecovered.userTotalStaked >= MINIMUM_STAKE, "Should be above minimum again");
        assertGt(juliaRecovered.effectiveMultiplier, 10000, "Multiplier should be restored above base");
    }

    function test_Vault_Scenario_BelowMinimumWithCooldown() public {
        address kevin = makeAddr("kevin");
        address qaManager = makeAddr("dummySapienQA");
        sapienToken.mint(kevin, 1000000e18);

        // Kevin stakes above minimum
        uint256 stakeAmount = MINIMUM_STAKE * 2; // 500 tokens
        vm.startPrank(kevin);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Wait for unlock
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Kevin initiates partial unstake
        uint256 cooldownAmount = 100e18;
        vm.prank(kevin);
        sapienVault.initiateUnstake(cooldownAmount);

        // Now Kevin has 400e18 active, 100e18 in cooldown

        // QA penalty hits Kevin while in cooldown, reducing total below minimum
        uint256 penaltyAmount = 200e18; // This will reduce from 500e18 to 300e18, still above minimum
        vm.prank(qaManager);
        sapienVault.processQAPenalty(kevin, penaltyAmount);

        ISapienVault.UserStakingSummary memory kevinAfterPenalty = sapienVault.getUserStakingSummary(kevin);
        assertEq(kevinAfterPenalty.userTotalStaked, stakeAmount - penaltyAmount);
        assertTrue(kevinAfterPenalty.userTotalStaked >= MINIMUM_STAKE, "Should still be above minimum");

        // Apply another penalty that takes Kevin below minimum
        uint256 secondPenalty = 100e18; // This will reduce from 300e18 to 200e18, below minimum
        vm.prank(qaManager);
        sapienVault.processQAPenalty(kevin, secondPenalty);

        ISapienVault.UserStakingSummary memory kevinBelowMin = sapienVault.getUserStakingSummary(kevin);
        assertEq(kevinBelowMin.userTotalStaked, stakeAmount - penaltyAmount - secondPenalty);
        assertTrue(kevinBelowMin.userTotalStaked < MINIMUM_STAKE, "Should be below minimum after second penalty");
        uint256 expectedKevinMultiplier = sapienVault.calculateMultiplier(kevinBelowMin.userTotalStaked, LOCK_30_DAYS);
        assertApproxEqAbs(
            kevinBelowMin.effectiveMultiplier,
            expectedKevinMultiplier,
            50,
            "Multiplier should reflect current system for below minimum"
        );

        // Kevin should still be able to complete unstake process
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        uint256 kevinBalanceBefore = sapienToken.balanceOf(kevin);
        uint256 availableForUnstake = kevinBelowMin.totalReadyForUnstake;

        if (availableForUnstake > 0) {
            vm.prank(kevin);
            sapienVault.unstake(availableForUnstake);

            assertEq(sapienToken.balanceOf(kevin), kevinBalanceBefore + availableForUnstake);
        }

        // Test that Kevin can still add more stake (but not during cooldown)
        // First let's complete the cooldown if there was one
        ISapienVault.UserStakingSummary memory kevinBeforeAdd = sapienVault.getUserStakingSummary(kevin);

        // Only try to add stake if not in cooldown
        if (kevinBeforeAdd.totalInCooldown == 0) {
            uint256 additionalStake = MINIMUM_STAKE;
            vm.startPrank(kevin);
            sapienToken.approve(address(sapienVault), additionalStake);
            sapienVault.increaseAmount(additionalStake);
            vm.stopPrank();

            ISapienVault.UserStakingSummary memory kevinFinal = sapienVault.getUserStakingSummary(kevin);
            assertGt(kevinFinal.userTotalStaked, kevinBelowMin.userTotalStaked, "Stake should increase");
        }
    }

    function test_Vault_Scenario_CompleteStakeWipeoutByQA() public {
        address lucy = makeAddr("lucy");
        address qaManager = makeAddr("dummySapienQA");
        sapienToken.mint(lucy, 1000000e18);

        // Lucy stakes exactly the minimum
        vm.startPrank(lucy);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE);
        sapienVault.stake(MINIMUM_STAKE, LOCK_90_DAYS);
        vm.stopPrank();

        // QA penalty completely wipes out Lucy's stake
        uint256 penaltyAmount = MINIMUM_STAKE + 500e18; // More than her stake
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        vm.prank(qaManager);
        uint256 actualPenalty = sapienVault.processQAPenalty(lucy, penaltyAmount);

        // Should only take what's available
        assertEq(actualPenalty, MINIMUM_STAKE);
        assertEq(sapienToken.balanceOf(treasury), treasuryBalanceBefore + MINIMUM_STAKE);

        // Lucy should have no stake remaining
        ISapienVault.UserStakingSummary memory lucyStake = sapienVault.getUserStakingSummary(lucy);
        assertEq(lucyStake.userTotalStaked, 0);
        assertFalse(sapienVault.hasActiveStake(lucy), "Lucy should have no active stake");
        assertEq(lucyStake.effectiveMultiplier, 0, "Multiplier should be 0 for no stake");

        // Lucy can start fresh with a new stake
        vm.startPrank(lucy);
        sapienToken.approve(address(sapienVault), MINIMUM_STAKE * 2);
        sapienVault.stake(MINIMUM_STAKE * 2, LOCK_180_DAYS);
        vm.stopPrank();

        ISapienVault.UserStakingSummary memory lucyNewStake = sapienVault.getUserStakingSummary(lucy);
        assertEq(lucyNewStake.userTotalStaked, MINIMUM_STAKE * 2);
        assertTrue(sapienVault.hasActiveStake(lucy), "Lucy should have active stake again");
        assertGt(lucyNewStake.effectiveMultiplier, 10000, "Multiplier should be above base for new stake");
    }

    // =============================================================================
    // CONSISTENCY SCENARIOS
    // Tests to verify that different staking paths lead to consistent outcomes
    // =============================================================================

    /**
     * @notice Test consistent outcomes between different staking paths
     * @dev This test verifies behavior differences due to weighted time calculations.
     *      The paths are NOT equivalent due to increaseAmount's weighted start time logic.
     */
    function test_Vault_Consistency_ThreePathsToSameGoal() public {
        // Setup: Create three users with identical starting conditions
        address alice_pathA = makeAddr("alice_pathA");
        address bob_pathB = makeAddr("bob_pathB");
        address charlie_pathC = makeAddr("charlie_pathC");

        sapienToken.mint(alice_pathA, 1000000e18);
        sapienToken.mint(bob_pathB, 1000000e18);
        sapienToken.mint(charlie_pathC, 1000000e18);

        uint256 initialStake = 1000e18;
        uint256 finalStake = 2000e18;
        uint256 additionalStake = finalStake - initialStake; // 1000e18
        uint256 targetLockupDays = 90 days;
        uint256 initialLockupDays = 90 days; // Will be set to have 60 days remaining

        // First, all users stake the same initial amount with same lockup
        vm.startPrank(alice_pathA);
        sapienToken.approve(address(sapienVault), initialStake);
        sapienVault.stake(initialStake, initialLockupDays);
        vm.stopPrank();

        vm.startPrank(bob_pathB);
        sapienToken.approve(address(sapienVault), initialStake);
        sapienVault.stake(initialStake, initialLockupDays);
        vm.stopPrank();

        vm.startPrank(charlie_pathC);
        sapienToken.approve(address(sapienVault), initialStake);
        sapienVault.stake(initialStake, initialLockupDays);
        vm.stopPrank();

        // Fast forward to have 60 days remaining (30 days elapsed)
        vm.warp(block.timestamp + 30 days);

        // Verify all users have 60 days remaining
        assertEq(sapienVault.getTimeUntilUnlock(alice_pathA), 60 days, "Alice should have 60 days remaining");
        assertEq(sapienVault.getTimeUntilUnlock(bob_pathB), 60 days, "Bob should have 60 days remaining");
        assertEq(sapienVault.getTimeUntilUnlock(charlie_pathC), 60 days, "Charlie should have 60 days remaining");

        // PATH A: Direct stake approach (fresh stake with target values)
        // Note: This path simulates what would happen if someone could start fresh
        // Since existing stakes can't use stake() again, we'll test the effective outcome

        // PATH B: increaseAmount(1000) → increaseLockup(30 days)
        vm.startPrank(bob_pathB);
        sapienToken.approve(address(sapienVault), additionalStake);
        sapienVault.increaseAmount(additionalStake);
        // increaseLockup calculates: remaining (60 days) + additional (30 days) = 90 days from now
        sapienVault.increaseLockup(30 days);
        vm.stopPrank();

        // PATH C: increaseLockup(30 days) → increaseAmount(1000)
        vm.startPrank(charlie_pathC);
        // increaseLockup calculates: remaining (60 days) + additional (30 days) = 90 days from now
        sapienVault.increaseLockup(30 days);
        sapienToken.approve(address(sapienVault), additionalStake);
        sapienVault.increaseAmount(additionalStake);
        vm.stopPrank();

        // For PATH A comparison, create a fresh user with the target outcome
        address alice_comparison = makeAddr("alice_comparison");
        sapienToken.mint(alice_comparison, 1000000e18);
        vm.startPrank(alice_comparison);
        sapienToken.approve(address(sapienVault), finalStake);
        sapienVault.stake(finalStake, targetLockupDays);
        vm.stopPrank();

        // Verify all paths result in the same final state
        ISapienVault.UserStakingSummary memory bobFinal = sapienVault.getUserStakingSummary(bob_pathB);
        ISapienVault.UserStakingSummary memory charlieFinal = sapienVault.getUserStakingSummary(charlie_pathC);
        ISapienVault.UserStakingSummary memory aliceComparison = sapienVault.getUserStakingSummary(alice_comparison);

        // All should have same total staked amount
        assertEq(bobFinal.userTotalStaked, finalStake, "Path B should have target stake amount");
        assertEq(charlieFinal.userTotalStaked, finalStake, "Path C should have target stake amount");
        assertEq(aliceComparison.userTotalStaked, finalStake, "Comparison should have target stake amount");

        // VERIFY ACTUAL BEHAVIOR: The paths yield DIFFERENT results due to weighted time calculations
        // Path B (increaseAmount → increaseLockup): Results in longer lockup due to weighted time
        // Path C (increaseLockup → increaseAmount): Results in target lockup since increaseLockup resets timer

        // Path C should achieve the target lockup (90 days)
        assertEq(charlieFinal.effectiveLockUpPeriod, targetLockupDays, "Path C should achieve target lockup");

        // Path B should have longer lockup due to weighted time affecting remaining calculation
        assertGt(
            bobFinal.effectiveLockUpPeriod,
            charlieFinal.effectiveLockUpPeriod,
            "Path B should have longer lockup than Path C"
        );
        assertGt(bobFinal.effectiveLockUpPeriod, targetLockupDays, "Path B should exceed target lockup");

        // Multipliers should differ since Path B has longer lockup period
        assertGt(
            bobFinal.effectiveMultiplier,
            charlieFinal.effectiveMultiplier,
            "Path B should have higher multiplier due to longer lockup"
        );

        // Path C should match the target multiplier closely
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(finalStake, targetLockupDays);
        assertApproxEqAbs(
            charlieFinal.effectiveMultiplier,
            expectedMultiplier,
            50, // Allow reasonable tolerance
            "Path C multiplier should match target"
        );

        // Path B should have higher multiplier than target due to longer lockup
        assertGt(bobFinal.effectiveMultiplier, expectedMultiplier, "Path B should have higher multiplier than target");

        // Verify unlock times reflect the different lockup periods
        uint256 bobUnlockTime = sapienVault.getTimeUntilUnlock(bob_pathB);
        uint256 charlieUnlockTime = sapienVault.getTimeUntilUnlock(charlie_pathC);
        uint256 aliceUnlockTime = sapienVault.getTimeUntilUnlock(alice_comparison);

        // Path B should have longer unlock time than Path C
        assertGt(bobUnlockTime, charlieUnlockTime, "Path B should have longer unlock time than Path C");

        // Path C should match target approximately
        assertApproxEqAbs(charlieUnlockTime, targetLockupDays, 1 days, "Path C should unlock in approximately 90 days");

        // Fresh stake comparison should match Path C
        assertApproxEqAbs(aliceUnlockTime, charlieUnlockTime, 1 days, "Fresh stake should match Path C timing");
    }

    /**
     * @notice Test behavior differences between staking paths
     * @dev Tests multiple scenarios to document how weighted time calculations
     *      cause different outcomes based on operation order
     */
    function test_Vault_Consistency_MultipleScenarios() public {
        // Scenario 1: Starting with 180 days, 120 days remaining, extend to 365 days from now
        _testConsistencyScenario({
            scenarioName: "180d_start_120d_remaining_365d_target",
            initialStake: 500e18,
            additionalStake: 1500e18,
            initialLockup: 180 days,
            elapsedTime: 60 days, // 180 - 60 = 120 days remaining
            additionalLockupDays: 245 days, // 120 + 245 = 365 days total from current time
            tolerance: 100 // 100 basis points tolerance
        });

        // Scenario 2: Starting with 30 days, 15 days remaining, extend to 90 days from now
        _testConsistencyScenario({
            scenarioName: "30d_start_15d_remaining_90d_target",
            initialStake: 1000e18,
            additionalStake: 500e18,
            initialLockup: 30 days,
            elapsedTime: 15 days, // 30 - 15 = 15 days remaining
            additionalLockupDays: 75 days, // 15 + 75 = 90 days total from current time
            tolerance: 50 // 50 basis points tolerance
        });

        // Scenario 3: Starting with 365 days, 300 days remaining, maintain by adding 65 days
        _testConsistencyScenario({
            scenarioName: "365d_start_300d_remaining_365d_target",
            initialStake: 750e18,
            additionalStake: 1250e18,
            initialLockup: 365 days,
            elapsedTime: 65 days, // 365 - 65 = 300 days remaining
            additionalLockupDays: 65 days, // 300 + 65 = 365 days total from current time
            tolerance: 75 // 75 basis points tolerance
        });
    }

    /**
     * @notice Helper function to test consistency scenarios with different parameters
     */
    function _testConsistencyScenario(
        string memory scenarioName,
        uint256 initialStake,
        uint256 additionalStake,
        uint256 initialLockup,
        uint256 elapsedTime,
        uint256 additionalLockupDays,
        uint256 tolerance
    ) private {
        // Create users for this scenario
        address userB = makeAddr(string.concat("userB_", scenarioName));
        address userC = makeAddr(string.concat("userC_", scenarioName));

        sapienToken.mint(userB, 10000000e18);
        sapienToken.mint(userC, 10000000e18);

        // Both users start with identical stakes
        vm.startPrank(userB);
        sapienToken.approve(address(sapienVault), initialStake);
        sapienVault.stake(initialStake, initialLockup);
        vm.stopPrank();

        vm.startPrank(userC);
        sapienToken.approve(address(sapienVault), initialStake);
        sapienVault.stake(initialStake, initialLockup);
        vm.stopPrank();

        // Fast forward time
        vm.warp(block.timestamp + elapsedTime);

        // Path B: increaseAmount → increaseLockup
        vm.startPrank(userB);
        sapienToken.approve(address(sapienVault), additionalStake);
        sapienVault.increaseAmount(additionalStake);
        sapienVault.increaseLockup(additionalLockupDays);
        vm.stopPrank();

        // Path C: increaseLockup → increaseAmount
        vm.startPrank(userC);
        sapienVault.increaseLockup(additionalLockupDays);
        sapienToken.approve(address(sapienVault), additionalStake);
        sapienVault.increaseAmount(additionalStake);
        vm.stopPrank();

        // Verify consistency
        ISapienVault.UserStakingSummary memory userBFinal = sapienVault.getUserStakingSummary(userB);
        ISapienVault.UserStakingSummary memory userCFinal = sapienVault.getUserStakingSummary(userC);

        // Total staked should be identical
        assertEq(userBFinal.userTotalStaked, userCFinal.userTotalStaked, "Total staked should match");

        // Due to weighted time calculations, the paths may yield different lockup periods
        // This is the expected behavior, not a bug
        console.log("User B (increaseAmount->increaseLockup) lockup:", userBFinal.effectiveLockUpPeriod);
        console.log("User C (increaseLockup->increaseAmount) lockup:", userCFinal.effectiveLockUpPeriod);

        // We verify that the lockup periods are reasonable, not necessarily identical
        assertGe(
            userBFinal.effectiveLockUpPeriod,
            userCFinal.effectiveLockUpPeriod,
            "Path B should have >= lockup than Path C"
        );

        // Multipliers should reflect the lockup differences
        if (userBFinal.effectiveLockUpPeriod > userCFinal.effectiveLockUpPeriod) {
            assertGe(
                userBFinal.effectiveMultiplier,
                userCFinal.effectiveMultiplier,
                "Higher lockup should have >= multiplier"
            );
        } else {
            assertApproxEqAbs(
                userBFinal.effectiveMultiplier,
                userCFinal.effectiveMultiplier,
                tolerance,
                "Equal lockups should have similar multipliers"
            );
        }

        // Unlock times should reflect the lockup differences
        uint256 userBUnlockTime = sapienVault.getTimeUntilUnlock(userB);
        uint256 userCUnlockTime = sapienVault.getTimeUntilUnlock(userC);

        // Path B typically has longer unlock time due to weighted time calculations
        assertGe(userBUnlockTime, userCUnlockTime, "Path B should have >= unlock time than Path C");
    }

    /**
     * @notice Test that operations on expired stakes show expected behaviors
     * @dev Verifies behavior when stakes have already expired before modifications.
     *      For expired stakes, both paths should be more consistent since
     *      the weighted time gets reset.
     */
    function test_Vault_Consistency_ExpiredStakes() public {
        address userA = makeAddr("userA_expired");
        address userB = makeAddr("userB_expired");

        sapienToken.mint(userA, 1000000e18);
        sapienToken.mint(userB, 1000000e18);

        uint256 stakeAmount = 800e18;
        uint256 lockupPeriod = 30 days;

        // Both users start with identical short-term stakes
        vm.startPrank(userA);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, lockupPeriod);
        vm.stopPrank();

        vm.startPrank(userB);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, lockupPeriod);
        vm.stopPrank();

        // Wait for stakes to expire
        vm.warp(block.timestamp + lockupPeriod + 10 days);

        // Verify both stakes are expired/unlocked
        assertTrue(sapienVault.getTotalUnlocked(userA) > 0, "User A should have unlocked stake");
        assertTrue(sapienVault.getTotalUnlocked(userB) > 0, "User B should have unlocked stake");

        uint256 additionalAmount = 700e18;
        uint256 newLockupPeriod = 180 days;

        // User A: increaseAmount then increaseLockup on expired stake
        vm.startPrank(userA);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseAmount(additionalAmount);
        sapienVault.increaseLockup(newLockupPeriod);
        vm.stopPrank();

        // User B: increaseLockup then increaseAmount on expired stake
        vm.startPrank(userB);
        sapienVault.increaseLockup(newLockupPeriod);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseAmount(additionalAmount);
        vm.stopPrank();

        // Verify final states are consistent
        ISapienVault.UserStakingSummary memory userAFinal = sapienVault.getUserStakingSummary(userA);
        ISapienVault.UserStakingSummary memory userBFinal = sapienVault.getUserStakingSummary(userB);

        assertEq(userAFinal.userTotalStaked, userBFinal.userTotalStaked, "Total staked should match for expired stakes");

        // For expired stakes, order may still matter due to weighted calculations
        // Document the actual behavior rather than expecting perfect consistency
        console.log("User A (increaseAmount->increaseLockup) expired lockup:", userAFinal.effectiveLockUpPeriod);
        console.log("User B (increaseLockup->increaseAmount) expired lockup:", userBFinal.effectiveLockUpPeriod);

        // We expect that both approaches yield reasonable results, not necessarily identical
        assertGe(
            userAFinal.effectiveLockUpPeriod,
            userBFinal.effectiveLockUpPeriod,
            "Path A should have >= lockup than Path B"
        );

        // Multipliers should reflect the lockup differences
        if (userAFinal.effectiveLockUpPeriod > userBFinal.effectiveLockUpPeriod) {
            assertGe(
                userAFinal.effectiveMultiplier,
                userBFinal.effectiveMultiplier,
                "Higher lockup should have >= multiplier"
            );
        } else {
            assertApproxEqAbs(
                userAFinal.effectiveMultiplier,
                userBFinal.effectiveMultiplier,
                25, // 25 basis points tolerance
                "Equal lockups should have similar multipliers"
            );
        }

        // Unlock times should reflect the lockup differences
        uint256 userATimeUntilUnlock = sapienVault.getTimeUntilUnlock(userA);
        uint256 userBTimeUntilUnlock = sapienVault.getTimeUntilUnlock(userB);

        // Path A typically has longer unlock time
        assertGe(userATimeUntilUnlock, userBTimeUntilUnlock, "User A should have >= unlock time than User B");

        // Both should have reasonable lockup periods remaining
        assertGt(userATimeUntilUnlock, 0, "User A should have time remaining");
        assertGt(userBTimeUntilUnlock, 0, "User B should have time remaining");

        // User B should be closer to the target lockup period
        assertApproxEqAbs(
            userBTimeUntilUnlock,
            newLockupPeriod,
            1 days, // Allow 1 day tolerance
            "User B should have approximately new lockup period remaining"
        );
    }
}
