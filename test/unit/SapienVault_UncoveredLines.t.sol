// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienVault, ISapienVault} from "src/SapienVault.sol";
import {SapienQA} from "src/SapienQA.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants as Const} from "src/utils/Constants.sol";
import {AccessControlUpgradeable} from "src/utils/Common.sol";

/**
 * @title SapienVault Uncovered Lines Test
 * @notice Comprehensive test suite to achieve 100% coverage by testing all previously uncovered lines
 */
contract SapienVaultUncoveredLinesTest is Test {
    SapienVault public vault;
    address public dummyQA;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public pauseManager = makeAddr("pauseManager");
    address public user = makeAddr("user");
    address public unauthorizedUser = makeAddr("unauthorizedUser");

    function setUp() public {
        // Deploy mock SAPIEN token
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        // Create a dummy QA address for vault initialization
        dummyQA = makeAddr("dummyQA");

        // Deploy SapienVault
        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInitData = abi.encodeWithSelector(
            SapienVault.initialize.selector, address(sapienToken), admin, pauseManager, treasury, dummyQA
        );
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), vaultInitData);
        vault = SapienVault(address(vaultProxy));

        // Grant SAPIEN_QA_ROLE to dummyQA so we can test QA functionality
        vm.prank(admin);
        vault.grantRole(Const.SAPIEN_QA_ROLE, dummyQA);

        // Mint tokens to users
        sapienToken.mint(user, 100_000e18);
        sapienToken.mint(unauthorizedUser, 100_000e18);

        // Approve vault for users
        vm.prank(user);
        sapienToken.approve(address(vault), type(uint256).max);

        vm.prank(unauthorizedUser);
        sapienToken.approve(address(vault), type(uint256).max);
    }

    // =============================================================================
    // UNCOVERED LINE TESTS
    // =============================================================================

    /**
     * Test 1: SAPIEN_QA_ROLE function (Lines 124-125)
     * Simple getter test to verify it returns the correct role hash
     */
    function test_Vault_SAPIEN_QA_ROLE_getter() public view {
        bytes32 role = vault.SAPIEN_QA_ROLE();
        assertEq(role, Const.SAPIEN_QA_ROLE);
    }

    /**
     * Test 2: SapienQA role access control error (Line 103)
     * Test unauthorized access to SapienQA functions with non-SapienQA role
     */
    function test_Vault_processQAPenalty_unauthorizedAccess() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                unauthorizedUser,
                Const.SAPIEN_QA_ROLE
            )
        );
        vault.processQAPenalty(user, 100e18);
    }

    /**
     * Test 3: isValidLockUpPeriod function (Line 856)
     * Test this public function directly with valid/invalid lockup periods
     */
    function test_Vault_isValidLockUpPeriod() public view {
        // Valid lockup periods
        assertTrue(vault.isValidLockUpPeriod(Const.LOCKUP_30_DAYS));
        assertTrue(vault.isValidLockUpPeriod(Const.LOCKUP_90_DAYS));
        assertTrue(vault.isValidLockUpPeriod(Const.LOCKUP_180_DAYS));
        assertTrue(vault.isValidLockUpPeriod(Const.LOCKUP_365_DAYS));

        // Edge case: exactly at boundaries
        assertTrue(vault.isValidLockUpPeriod(Const.LOCKUP_30_DAYS));
        assertTrue(vault.isValidLockUpPeriod(Const.LOCKUP_365_DAYS));

        // Invalid lockup periods
        assertFalse(vault.isValidLockUpPeriod(Const.LOCKUP_30_DAYS - 1));
        assertFalse(vault.isValidLockUpPeriod(Const.LOCKUP_365_DAYS + 1));
        assertFalse(vault.isValidLockUpPeriod(0));
        assertFalse(vault.isValidLockUpPeriod(1 days));
        assertFalse(vault.isValidLockUpPeriod(400 days));
    }

    /**
     * Test 4: Expired stake handling return (Line 927)
     * Test cases where stakes have expired
     */
    function test_Vault_expiredStake_scenarios() public {
        // Stake with 30 days lockup
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);

        // Fast forward past expiration
        vm.warp(block.timestamp + Const.LOCKUP_30_DAYS + 1);

        // Test operations on expired stake - should trigger expired handling
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_90_DAYS); // Should reset start time due to expiration

        // Verify the stake was handled as expired
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);
        assertEq(userStake.effectiveLockUpPeriod, Const.LOCKUP_90_DAYS); // Should be new lockup period, not weighted
    }

    /**
     * Test 5: Dust attack prevention (Line 891)
     * Test adding very small amounts (less than MINIMUM_STAKE_AMOUNT / 100)
     */
    function test_Vault_increaseAmount_dustAttackPrevention() public {
        // First establish a valid stake
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);

        // Try to increase with dust amount
        uint256 dustAmount = (Const.MINIMUM_STAKE_AMOUNT / 100) - 1;
        vm.prank(user);
        vm.expectRevert(ISapienVault.InvalidAmount.selector);
        vault.increaseAmount(dustAmount);
    }

    /**
     * Test 6: Maximum lockup capping (Lines 702, 755)
     * Test stake combinations that would exceed maximum lockup period
     */
    function test_Vault_stake_lockupPeriodCapping() public {
        // This is a complex scenario that requires precise calculation
        // We need to create a scenario where weighted calculation would exceed max lockup

        // Start with a very large stake at maximum lockup
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT * 50, Const.LOCKUP_365_DAYS);

        // Fast forward to make the stake expire completely
        vm.warp(block.timestamp + Const.LOCKUP_365_DAYS + 1);

        // Now stake again - this should trigger the expired stake handling
        // and ensure lockup doesn't exceed maximum
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_365_DAYS);

        // Verify lockup period is capped at maximum
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);
        assertLe(userStake.effectiveLockUpPeriod, Const.LOCKUP_365_DAYS);
    }

    /**
     * Test 7: Early unstake with no stake (Line 563)
     * Test initiateEarlyUnstake when user has no stake
     */
    function test_Vault_initiateEarlyUnstake_noStake() public {
        vm.prank(user);
        vm.expectRevert(ISapienVault.NoStakeFound.selector);
        vault.initiateEarlyUnstake(Const.MINIMUM_STAKE_AMOUNT);
    }

    /**
     * Test 8: QA penalty with cooldown stake (Lines 1038, 1065-1071)
     * Test QA penalty when user has both active stake and cooldown stake
     */
    function test_Vault_processQAPenalty_withCooldownStake() public {
        // Setup: User has both active stake AND cooldown stake
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);

        // Fast forward past lockup and initiate unstake (creates cooldown)
        vm.warp(block.timestamp + Const.LOCKUP_30_DAYS + 1);
        vm.prank(user);
        vault.initiateUnstake(Const.MINIMUM_STAKE_AMOUNT * 30 / 100); // 30% to cooldown

        // At this point:
        // - userStake.userTotalStaked = 1000e18 (total stake)
        // - userStake.cooldownAmount = 300e18 (30% in cooldown)

        // Apply a penalty that's smaller than total but exercises the cooldown reduction logic
        uint256 penalty = Const.MINIMUM_STAKE_AMOUNT * 50 / 100; // 50% penalty

        vm.prank(dummyQA);
        uint256 actualPenalty = vault.processQAPenalty(user, penalty);

        // Should apply the full penalty
        assertEq(actualPenalty, penalty);

        // After penalty, should have 50% remaining
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);

        // Should have some stake remaining (1000 - 500 = 500)
        assertEq(userStake.userTotalStaked, Const.MINIMUM_STAKE_AMOUNT - penalty);
        assertTrue(vault.hasActiveStake(user));

        // The cooldown amount should also be reduced proportionally or via the reduction logic
        // Since the penalty reduces from total amount first, cooldown should be adjusted accordingly
        assertLe(userStake.totalInCooldown, Const.MINIMUM_STAKE_AMOUNT * 30 / 100);
    }

    /**
     * Test 8b: QA penalty with cooldown reduction (Lines 1038, 1065-1071)
     * Test that specifically triggers the cooldown reduction logic
     */
    function test_Vault_processQAPenalty_cooldownReduction() public {
        // Setup: Create a stake where we can test the scenario that triggers line 1038
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);

        // Fast forward past lockup and initiate unstake (creates cooldown)
        vm.warp(block.timestamp + Const.LOCKUP_30_DAYS + 1);
        vm.prank(user);
        vault.initiateUnstake(Const.MINIMUM_STAKE_AMOUNT / 2); // Half to cooldown

        // At this point:
        // - userStake.userTotalStaked = 1000e18 (total stake)
        // - userStake.cooldownAmount = 500e18 (in cooldown)

        // Apply penalty that will exhaust the primary stake and trigger cooldown reduction
        // This ensures we reach line 1038 where remainingPenalty > 0
        uint256 penalty = Const.MINIMUM_STAKE_AMOUNT * 120 / 100; // 1200e18 (more than total)

        vm.prank(dummyQA);
        uint256 actualPenalty = vault.processQAPenalty(user, penalty);

        // Should be capped at total available (1000e18)
        assertEq(actualPenalty, Const.MINIMUM_STAKE_AMOUNT);

        // After penalty, should have no stake remaining
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);

        // The key test: this should have triggered the cooldown reduction path (lines 1038, 1065-1071)
        // and reset the user stake completely
        assertEq(userStake.userTotalStaked, 0, "User should have no stake remaining");
        assertEq(userStake.totalInCooldown, 0, "Should have no cooldown amount remaining");
        assertFalse(vault.hasActiveStake(user));
    }

    /**
     * Test 9: Complex expired stake handling in increase operations
     * Test the standardized weighted start time calculation for expired stakes
     */
    function test_Vault_increaseAmount_expiredStake() public {
        // Create initial stake
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);

        // Fast forward past expiration
        vm.warp(block.timestamp + Const.LOCKUP_30_DAYS + 1);

        // Increase amount on expired stake
        vm.prank(user);
        vault.increaseAmount(Const.MINIMUM_STAKE_AMOUNT);

        // Verify the expired stake handling occurred
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);

        assertEq(userStake.userTotalStaked, Const.MINIMUM_STAKE_AMOUNT * 2);
        assertEq(userStake.effectiveLockUpPeriod, Const.LOCKUP_30_DAYS); // Should maintain original lockup
    }

    /**
     * Test 10: Increase lockup on expired stake
     * Test the expired stake handling in lockup increase operations
     */
    function test_Vault_increaseLockup_expiredStake() public {
        // Create initial stake
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);

        // Fast forward past expiration
        vm.warp(block.timestamp + Const.LOCKUP_30_DAYS + 1);

        // Increase lockup on expired stake
        vm.prank(user);
        vault.increaseLockup(60 days);

        // For expired stakes, should reset to new lockup period
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);
        assertEq(userStake.effectiveLockUpPeriod, 60 days);
    }

    /**
     * Test 11: Maximum lockup capping in increase lockup
     * Test the maximum lockup capping in increaseLockup function
     */
    function test_Vault_increaseLockup_maxLockupCapping() public {
        // Create initial stake with maximum lockup
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_365_DAYS);

        // Try to increase lockup beyond maximum
        // This should cap at maximum lockup period
        vm.prank(user);
        vault.increaseLockup(Const.LOCKUP_365_DAYS); // Would theoretically go beyond max

        // Verify lockup is capped at maximum
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);
        assertEq(userStake.effectiveLockUpPeriod, Const.LOCKUP_365_DAYS);
    }

    /**
     * Test 12: Edge case for weighted calculation validation
     * Test invalid lockup period error in weighted calculations (Line 736)
     * This is hard to reach but we can test the validation logic
     */
    function test_Vault_weightedCalculation_validation() public {
        // This tests the internal validation logic
        // The actual line 736 is hard to reach through normal operations
        // but we can verify the validation works by testing boundary conditions

        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);

        // Try to stake with minimum valid lockup
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);

        // Verify the weighted calculation worked correctly
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);
        assertEq(userStake.userTotalStaked, Const.MINIMUM_STAKE_AMOUNT * 2);
        assertGe(userStake.effectiveLockUpPeriod, Const.LOCKUP_30_DAYS);
    }

    /**
     * Test 13: QA penalty edge case - exactly exhaust active stake
     * Test when penalty exactly equals available stake
     */
    function test_Vault_processQAPenalty_exactStakeAmount() public {
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);

        // Apply penalty exactly equal to stake
        vm.prank(dummyQA);
        uint256 actualPenalty = vault.processQAPenalty(user, Const.MINIMUM_STAKE_AMOUNT);

        assertEq(actualPenalty, Const.MINIMUM_STAKE_AMOUNT);

        // User should have no stake remaining
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);
        assertEq(userStake.userTotalStaked, 0);
        assertFalse(vault.hasActiveStake(user));
    }

    /**
     * Test 14: Complex scenario with multiple cooldowns and penalties
     * Test scenario where penalty affects both active and cooldown stakes
     */
    function test_Vault_processQAPenalty_complexScenario() public {
        // Create a complex stake scenario
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT * 2, Const.LOCKUP_30_DAYS);

        // Fast forward and create cooldown
        vm.warp(block.timestamp + Const.LOCKUP_30_DAYS + 1);
        vm.prank(user);
        vault.initiateUnstake(Const.MINIMUM_STAKE_AMOUNT * 80 / 100); // 80% of 1 minimum stake

        // Now we have 1200e18 active, 800e18 in cooldown

        // Apply penalty that requires taking from both pools
        vm.prank(dummyQA);
        uint256 largePenalty = Const.MINIMUM_STAKE_AMOUNT * 150 / 100; // 150% of minimum stake
        uint256 actualPenalty = vault.processQAPenalty(user, largePenalty);

        // Should take from active stake first, then cooldown if needed
        assertEq(actualPenalty, largePenalty);

        // Verify remaining stakes
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);

        // Should have 500e18 remaining total (2000 - 1500)
        assertEq(userStake.userTotalStaked, (Const.MINIMUM_STAKE_AMOUNT * 2) - largePenalty);

        // Some should remain in cooldown (the calculation will depend on implementation)
        // The exact distribution depends on how the penalty is applied
        // Verify cooldown is consistent with total stake
        assertTrue(userStake.totalInCooldown <= userStake.userTotalStaked, "Cooldown should not exceed total stake");
    }

    /**
     * Test 15: Banker's rounding in weighted calculations
     * Test the rounding logic in weighted start time and lockup calculations
     */
    function test_Vault_bankersRounding_weightedCalculations() public {
        // Create a scenario that would trigger banker's rounding
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);

        // Advance time slightly
        vm.warp(block.timestamp + 1 days);

        // Add stake that creates a remainder > 50% in weighted calculation
        vm.prank(user);
        vault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_90_DAYS);

        // Verify the calculation completed successfully
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);
        assertEq(userStake.userTotalStaked, Const.MINIMUM_STAKE_AMOUNT * 2);
    }

    /**
     * Test 16: Lockup cap check in weighted calculations
     * Test the scenario where banker's rounding could push effective lockup over 365 days
     */
    function test_Vault_lockupCapCheck_bankersRounding() public {
        // Create scenario where banker's rounding could exceed 365 days
        uint256 stakeAmount1 = Const.MINIMUM_STAKE_AMOUNT;
        uint256 stakeAmount2 = Const.MINIMUM_STAKE_AMOUNT + 1; // Asymmetric for rounding edge case

        // Initial stake with maximum lockup
        vm.prank(user);
        vault.stake(stakeAmount1, Const.LOCKUP_365_DAYS);

        // Wait exactly 1 second (creates edge case in remaining time calculation)
        vm.warp(block.timestamp + 1);

        // Add stake with maximum lockup - this could trigger the cap due to banker's rounding
        // The weighted calculation with remaining time + rounding could theoretically exceed 365 days
        vm.prank(user);
        vault.stake(stakeAmount2, Const.LOCKUP_365_DAYS);

        // Verify the lockup is properly capped at 365 days
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);
        assertEq(userStake.effectiveLockUpPeriod, Const.LOCKUP_365_DAYS, "Lockup should be capped at 365 days");

        // Verify total stake was combined correctly
        assertEq(vault.getTotalStaked(user), stakeAmount1 + stakeAmount2);
    }

    /**
     * Test 17: Extreme lockup cap edge case
     * Try to force a scenario where weighted calculation exceeds 365 days
     */
    function test_Vault_lockupCapCheck_extremeEdgeCase() public {
        // Use amounts that meet minimum stake requirement but create rounding effects
        uint256 stakeAmount1 = Const.MINIMUM_STAKE_AMOUNT + 1; // Just over minimum
        uint256 stakeAmount2 = Const.MINIMUM_STAKE_AMOUNT + 3; // Another odd amount for rounding

        vm.prank(user);
        vault.stake(stakeAmount1, Const.LOCKUP_365_DAYS);

        // Wait exactly 1 second to create remaining time of 365 days - 1 second
        vm.warp(block.timestamp + 1);

        // Add another stake with max lockup - the weighted average of:
        // (364 days, 23:59:59) * amount1 + (365 days) * amount2
        // divided by total amount, with banker's rounding, might exceed 365 days
        vm.prank(user);
        vault.stake(stakeAmount2, Const.LOCKUP_365_DAYS);

        // Check that lockup is capped properly
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);
        assertLe(userStake.effectiveLockUpPeriod, Const.LOCKUP_365_DAYS, "Lockup must not exceed 365 days");

        // Also verify it's a reasonable value (close to 365 days)
        assertGe(userStake.effectiveLockUpPeriod, Const.LOCKUP_365_DAYS - 1 days, "Lockup should be close to 365 days");
    }

    /**
     * Test 18: Understanding lockup cap behavior with floor protection
     * Since floor protection ensures result >= max(inputs), and inputs are already <= 365 days,
     * the cap check may only be needed for edge cases in arithmetic or future-proofing
     */
    function test_Vault_lockupCapCheck_floorProtectionInteraction() public {
        // Test with maximum possible values to understand the behavior
        uint256 largeStake1 = 1000e18; // 1K tokens
        uint256 largeStake2 = 9000e18; // 9K tokens (creates 9:1 ratio)

        // Initial stake with maximum lockup
        vm.prank(user);
        vault.stake(largeStake1, Const.LOCKUP_365_DAYS);

        // Fast forward to create a very small remaining time (1 second)
        vm.warp(block.timestamp + Const.LOCKUP_365_DAYS - 1);

        // Now remaining time is 1 second, but we add a huge stake with 365 days
        // Due to floor protection, result should be max(weighted_avg, 1_second, 365_days) = 365_days
        vm.prank(user);
        vault.stake(largeStake2, Const.LOCKUP_365_DAYS);

        // With floor protection, this should be exactly 365 days, not exceeding it
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);

        // Should be exactly 365 days due to floor protection taking the max
        assertEq(userStake.effectiveLockUpPeriod, Const.LOCKUP_365_DAYS, "Floor protection should ensure exactly 365 days");

        // The cap check (line 760) might be unreachable due to floor protection logic
        // This test documents the expected behavior
    }

    /**
     * Test 18: Lockup cap in _calculateWeightedValues
     * Documents why line 757 is unreachable due to floor protection logic
     */
    function test_Vault_lockupCap_unreachableDueToFloorProtection() public {
        // This test demonstrates why line 757 in _calculateWeightedValues is unreachable:
        // The lockup cap "if (newValues.effectiveLockup > Const.LOCKUP_365_DAYS)" can never be triggered
        // because the _calculateWeightedLockupPeriod function has floor protection that ensures
        // the result is always the maximum of inputs, which are already ≤ 365 days.

        uint256 stakeAmount1 = Const.MINIMUM_STAKE_AMOUNT;
        uint256 stakeAmount2 = Const.MINIMUM_STAKE_AMOUNT * 10; // Large second stake

        // Test case 1: Start with maximum lockup
        vm.prank(user);
        vault.stake(stakeAmount1, Const.LOCKUP_365_DAYS);

        // Advance time slightly to test remaining time calculation
        vm.warp(block.timestamp + 1 days);

        // Test case 2: Add large stake with maximum lockup
        // Even with extreme weighting, the floor protection ensures lockup ≤ 365 days
        vm.prank(user);
        vault.stake(stakeAmount2, Const.LOCKUP_365_DAYS);

        // Verify the effective lockup never exceeds 365 days
        ISapienVault.UserStakingSummary memory userStake = vault.getUserStakingSummary(user);
        assertLe(userStake.effectiveLockUpPeriod, Const.LOCKUP_365_DAYS, "Lockup should never exceed 365 days");
        assertEq(userStake.effectiveLockUpPeriod, Const.LOCKUP_365_DAYS, "Should equal 365 days with max lockup inputs");

        // Test case 3: Try to create a scenario with potential for rounding over 365 days
        // Use odd amounts that could create banker's rounding edge cases
        uint256 oddAmount1 = Const.MINIMUM_STAKE_AMOUNT + 3333333;
        uint256 oddAmount2 = Const.MINIMUM_STAKE_AMOUNT + 6666667;

        address user2 = makeAddr("user2");

        // Setup user2 with tokens and approvals - user2 needs tokens to stake!
        vm.startPrank(user2);
        // First, give user2 some tokens (user2 doesn't have any tokens by default)
        // Actually, let's just use the main user who already has tokens set up
        vm.stopPrank();

        // Use the main user instead since they already have token setup
        vm.prank(user);
        vault.stake(oddAmount1, Const.LOCKUP_365_DAYS);

        vm.warp(block.timestamp + 1); // Advance 1 second to create edge case

        vm.prank(user);
        vault.stake(oddAmount2, Const.LOCKUP_365_DAYS);

        // Even with banker's rounding, floor protection prevents exceeding 365 days
        ISapienVault.UserStakingSummary memory userStake2 = vault.getUserStakingSummary(user);
        assertLe(userStake2.effectiveLockUpPeriod, Const.LOCKUP_365_DAYS, "Floor protection prevents exceeding max lockup");

        // Note: Line 757 "newValues.effectiveLockup = Const.LOCKUP_365_DAYS;" is unreachable
        // because _calculateWeightedLockupPeriod has floor protection that ensures:
        // result = max(weighted_average, existing_lockup, new_lockup)
        // Since existing_lockup ≤ 365 days and new_lockup ≤ 365 days (validated),
        // the maximum of these values cannot exceed 365 days.
        // The cap is defensive programming but mathematically unreachable.
    }
}
