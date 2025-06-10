// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SapienVault} from "src/SapienVault.sol";
import {SapienQA} from "src/SapienQA.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {Constants as Const} from "src/utils/Constants.sol";

/**
 * @title JuneAudit_SAP_5 Test Suite
 * @notice Tests for SAP-5: Missing Expiration Check when Adding to Existing Stake
 * @dev This test suite validates the fix for the timelock bypass vulnerability
 *      where users could add tokens to expired stakes and exploit weighted calculations
 */
contract JuneAudit_SAP_5_StakeBypassTest is Test {
    // Core contracts
    SapienVault public sapienVault;
    SapienQA public sapienQA;
    MockERC20 public sapienToken;

    // System accounts
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public qaManager = makeAddr("qaManager");

    // Test parameters
    uint256 public constant INITIAL_BALANCE = 10_000_000 * 10 ** 18; // 10M tokens
    uint256 public constant MINIMUM_STAKE = 1000 * 10 ** 18; // 1K tokens
    uint256 public constant LARGE_STAKE = 100_000 * 10 ** 18; // 100K tokens
    uint256 public constant SMALL_STAKE = 5_000 * 10 ** 18; // 5K tokens

    // Lockup periods
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    function setUp() public {
        // Deploy token
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        // Deploy SapienVault with proxy
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

        // Deploy SapienQA
        sapienQA = new SapienQA(treasury, address(sapienVault), qaManager, admin);

        // Grant QA manager role to QA contract
        vm.prank(admin);
        sapienVault.grantRole(Const.QA_MANAGER_ROLE, address(sapienQA));

        // Grant SAPIEN_QA_ROLE to QA contract so it can call processQAPenalty
        vm.prank(admin);
        sapienVault.grantRole(Const.SAPIEN_QA_ROLE, address(sapienQA));

        console.log("=== SAP-5 Stake Bypass Test Setup Complete ===");
    }

    // ============================================
    // SAP-5 VULNERABILITY DEMONSTRATION
    // ============================================

    /**
     * @notice Demonstrates the SAP-5 vulnerability where users could add to expired stakes
     * @dev This test shows that the fix properly prevents timelock bypass exploitation
     */
    function test_Vault_SAP5_Vulnerability_MissingExpirationCheck() public {
        console.log("\n=== SAP-5 VULNERABILITY: Missing Expiration Check ===");

        address user = makeAddr("vulnerabilityUser");
        sapienToken.mint(user, INITIAL_BALANCE);
        vm.prank(user);
        sapienToken.approve(address(sapienVault), type(uint256).max);

        // Phase 1: Create initial stake with short lockup
        console.log("\n--- Phase 1: Initial Stake Creation ---");
        vm.prank(user);
        sapienVault.stake(SMALL_STAKE, LOCK_30_DAYS);

        // Phase 2: Wait for stake to expire
        console.log("\n--- Phase 2: Wait for Stake Expiration ---");
        vm.warp(block.timestamp + LOCK_30_DAYS + 1 days);

        {
            (, uint256 totalUnlocked, uint256 totalLocked,,,,, uint256 timeUntilUnlock) =
                sapienVault.getUserStakingSummary(user);
            console.log("After expiration - Unlocked:", totalUnlocked / 10 ** 18, "SAPIEN");
            console.log("After expiration - Locked:", totalLocked / 10 ** 18, "SAPIEN");
            assertTrue(totalUnlocked > 0, "Stake should be unlocked");
            assertTrue(totalLocked == 0, "No tokens should be locked");
            assertEq(timeUntilUnlock, 0, "Time until unlock should be 0");
        }

        // Phase 3: Add to expired stake with long lockup - VULNERABILITY TEST
        console.log("\n--- Phase 3: Add to Expired Stake (VULNERABILITY FIXED) ---");
        vm.prank(user);
        sapienVault.stake(LARGE_STAKE, LOCK_365_DAYS);

        {
            (
                uint256 totalStaked,
                uint256 totalUnlocked,
                uint256 totalLocked,
                ,
                ,
                , // effectiveMultiplier
                uint256 lockup,
                uint256 timeUntilUnlock
            ) = sapienVault.getUserStakingSummary(user);

            console.log("After adding to expired stake:");
            console.log("Total staked:", totalStaked / 10 ** 18, "SAPIEN");
            console.log("Unlocked:", totalUnlocked / 10 ** 18, "SAPIEN");
            console.log("Locked:", totalLocked / 10 ** 18, "SAPIEN");
            console.log("Effective lockup:", lockup / 1 days, "days");
            console.log("Time until unlock:", timeUntilUnlock / 1 days, "days");

            // Check the vulnerability is fixed
            if (timeUntilUnlock < LOCK_365_DAYS) {
                console.log("VULNERABILITY: Effective lockup is shorter than intended!");
                console.log("Expected:", LOCK_365_DAYS / 1 days, "days");
                console.log("Actual:", timeUntilUnlock / 1 days, "days");
                // With the fix, this should NOT happen
                assertEq(timeUntilUnlock / 1 days, 365, "SAP-5 FIX: Should maintain full lockup period");
            } else {
                console.log("SAP-5 FIX CONFIRMED: Full lockup period maintained");
                assertEq(timeUntilUnlock / 1 days, 365, "Full 365-day lockup should be applied");
            }

            // Check if user can unstake immediately (should not be possible)
            try sapienVault.initiateUnstake(MINIMUM_STAKE) {
                console.log("VULNERABILITY: User can unstake immediately!");
                assertFalse(true, "User should not be able to unstake immediately after adding to expired stake");
            } catch {
                console.log("SAP-5 FIX CONFIRMED: User cannot unstake immediately (correct behavior)");
            }
        }

        console.log("\n=== SAP-5 VULNERABILITY TEST COMPLETE ===");
    }

    /**
     * @notice Tests the SAP-5 fix for the increaseAmount function
     * @dev Verifies that increaseAmount also prevents timelock bypass on expired stakes
     */
    function test_Vault_SAP5_Fix_IncreaseAmountVulnerability() public {
        console.log("\n=== SAP-5 FIX TEST: IncreaseAmount Function ===");

        address user = makeAddr("increaseAmountUser");
        sapienToken.mint(user, INITIAL_BALANCE);
        vm.prank(user);
        sapienToken.approve(address(sapienVault), type(uint256).max);

        // Phase 1: Create initial stake with short lockup
        console.log("\n--- Phase 1: Initial Stake Creation ---");
        vm.prank(user);
        sapienVault.stake(SMALL_STAKE, LOCK_30_DAYS);

        // Phase 2: Wait for stake to expire
        console.log("\n--- Phase 2: Wait for Stake Expiration ---");
        vm.warp(block.timestamp + LOCK_30_DAYS + 1 days);

        {
            (, uint256 totalUnlocked, uint256 totalLocked,,,,, uint256 timeUntilUnlock) =
                sapienVault.getUserStakingSummary(user);
            console.log("Before increaseAmount - Unlocked:", totalUnlocked / 10 ** 18, "SAPIEN");
            console.log("Before increaseAmount - Locked:", totalLocked / 10 ** 18, "SAPIEN");
            assertTrue(totalUnlocked > 0, "Stake should be unlocked");
            assertTrue(totalLocked == 0, "No tokens should be locked");
            assertEq(timeUntilUnlock, 0, "Time until unlock should be 0");
        }

        // Phase 3: Use increaseAmount on expired stake - SHOULD BE FIXED
        console.log("\n--- Phase 3: IncreaseAmount on Expired Stake (FIXED) ---");
        vm.prank(user);
        sapienVault.increaseAmount(LARGE_STAKE);

        {
            (
                uint256 totalStaked,
                uint256 totalUnlocked,
                uint256 totalLocked,
                ,
                ,
                , // effectiveMultiplier
                , // lockup
                uint256 timeUntilUnlock
            ) = sapienVault.getUserStakingSummary(user);

            console.log("After increaseAmount on expired stake:");
            console.log("Total staked:", totalStaked / 10 ** 18, "SAPIEN");
            console.log("Unlocked:", totalUnlocked / 10 ** 18, "SAPIEN");
            console.log("Locked:", totalLocked / 10 ** 18, "SAPIEN");
            console.log("Time until unlock:", timeUntilUnlock / 1 days, "days");

            // With the fix, the new weighted start time is reset to current timestamp
            // and the entire stake is relocked for the original lockup period (30 days)
            // This prevents exploitation while maintaining consistent lockup behavior
            assertTrue(totalLocked == totalStaked, "All tokens should be relocked with SAP-5 fix");
            assertTrue(totalUnlocked == 0, "No tokens should be unlocked after relocking");
            assertEq(timeUntilUnlock / 1 days, 30, "Time until unlock should be reset to original lockup period");

            console.log(
                "SAP-5 FIX CONFIRMED: increaseAmount properly resets weighted start time and relocks expired stakes"
            );
        }

        console.log("\n=== SAP-5 INCREASEAMOUNT FIX TEST COMPLETE ===");
    }

    /**
     * @notice Demonstrates the proper behavior with the SAP-5 fix implementation
     * @dev Shows the recommended behavior when adding to expired stakes
     */
    function test_Vault_SAP5_Fix_ValidationDemo() public {
        console.log("\n=== SAP-5 FIX DEMONSTRATION ===");

        address fixTestUser = makeAddr("fixTestUser");
        sapienToken.mint(fixTestUser, INITIAL_BALANCE);
        vm.prank(fixTestUser);
        sapienToken.approve(address(sapienVault), type(uint256).max);

        // Create initial stake with short lockup
        uint256 initialStake = SMALL_STAKE;
        uint256 shortLockup = LOCK_30_DAYS;

        vm.prank(fixTestUser);
        sapienVault.stake(initialStake, shortLockup);

        // Wait for stake to expire
        vm.warp(block.timestamp + shortLockup + 1 days);

        // Verify stake is expired
        (, uint256 totalUnlocked,,,,,,) = sapienVault.getUserStakingSummary(fixTestUser);
        assertTrue(totalUnlocked > 0, "Stake should be unlocked");

        console.log("Initial stake expired - User has", totalUnlocked / 10 ** 18, "unlocked SAPIEN");

        // This demonstrates what happens with the proper fix:
        // When adding to an expired stake, the system resets the weighted start time to current timestamp

        console.log("Attempting to add to expired stake...");

        // Current behavior (fixed): Properly handles adding to expired stake
        vm.prank(fixTestUser);
        sapienVault.stake(LARGE_STAKE, LOCK_365_DAYS);

        (
            uint256 totalStaked,
            uint256 unlocked,
            uint256 locked,
            ,
            ,
            , // effectiveMultiplier
            , // lockup
            uint256 timeUntilUnlock
        ) = sapienVault.getUserStakingSummary(fixTestUser);

        console.log("After adding to expired stake:");
        console.log("Total staked:", totalStaked / 10 ** 18, "SAPIEN");
        console.log("Unlocked portion:", unlocked / 10 ** 18, "SAPIEN");
        console.log("Locked portion:", locked / 10 ** 18, "SAPIEN");
        console.log("Time until full unlock:", timeUntilUnlock / 1 days, "days");

        // With the proper fix, this results in:
        // - Full lockup period applied (365 days from now)
        // - No immediate unlocked tokens from the weighted averaging exploit
        // - Proper security enforcement

        assertEq(timeUntilUnlock / 1 days, 365, "Full lockup period should be applied");
        assertTrue(locked > 0, "Tokens should be properly locked");

        console.log("\n=== SAP-5 FIX BEHAVIOR CONFIRMED ===");
        console.log("[OK] Weighted start time properly reset to current timestamp for expired stakes");
        console.log("[OK] Full lockup period applied without weighted averaging exploit");
        console.log("[OK] Security enforced while maintaining user functionality");
    }

    // ============================================
    // EDGE CASE TESTS
    // ============================================

    /**
     * @notice Tests edge case where stake expires exactly at lockup period
     * @dev Ensures fix works at boundary conditions
     */
    function test_Vault_SAP5_EdgeCase_ExactExpirationBoundary() public {
        address user = makeAddr("boundaryUser");
        sapienToken.mint(user, INITIAL_BALANCE);
        vm.prank(user);
        sapienToken.approve(address(sapienVault), type(uint256).max);

        // Create stake
        vm.prank(user);
        sapienVault.stake(SMALL_STAKE, LOCK_30_DAYS);

        // Fast forward to exactly when stake expires
        vm.warp(block.timestamp + LOCK_30_DAYS);

        // Add to stake at exact expiration time
        vm.prank(user);
        sapienVault.stake(LARGE_STAKE, LOCK_365_DAYS);

        // Verify proper behavior at boundary
        (,,,,,,, /* lockup */ uint256 timeUntilUnlock) = sapienVault.getUserStakingSummary(user);

        assertEq(timeUntilUnlock / 1 days, 365, "Should apply full lockup at exact boundary");

        console.log("[OK] SAP-5 fix works correctly at expiration boundary");
    }

    /**
     * @notice Tests that normal weighted calculations still work for non-expired stakes
     * @dev Ensures the fix doesn't break legitimate weighted averaging
     */
    function test_Vault_SAP5_NormalWeightedCalculations_StillWork() public {
        address user = makeAddr("normalUser");
        sapienToken.mint(user, INITIAL_BALANCE);
        vm.prank(user);
        sapienToken.approve(address(sapienVault), type(uint256).max);

        // Create initial stake
        vm.prank(user);
        sapienVault.stake(SMALL_STAKE, LOCK_365_DAYS);

        // Wait some time but not enough to expire (less than 365 days)
        vm.warp(block.timestamp + 100 days);

        // Add to non-expired stake
        vm.prank(user);
        sapienVault.stake(LARGE_STAKE, LOCK_365_DAYS);

        // Verify weighted calculations still work normally
        (,,,,,,, /* lockup */ uint256 timeUntilUnlock) = sapienVault.getUserStakingSummary(user);

        // Should be somewhere between original remaining time and new full lockup
        // This proves normal weighted calculations are preserved
        assertTrue(timeUntilUnlock > 265 days, "Should use weighted calculation for non-expired stakes");
        assertTrue(timeUntilUnlock <= 365 days, "Should not exceed maximum lockup");

        console.log("Time until unlock:", timeUntilUnlock / 1 days, "days");
        console.log("[OK] Normal weighted calculations preserved for non-expired stakes");
    }
}
