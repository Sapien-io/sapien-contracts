// test/unit/june-audit-findings/sap-1-cooldown-bypass/JuneAudit_SAP_1.t.sol
// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "lib/forge-std/src/Test.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants as Const} from "src/utils/Constants.sol";

/**
 * @title JuneAudit_SAP_1_CooldownBypassTest
 * @notice Test that demonstrates the cooldown bypass vulnerability
 * @dev This test verifies the specific exploit scenario described in the audit finding
 */
contract JuneAudit_SAP_1_CooldownBypassTest is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");

    uint256 public constant STAKE_AMOUNT = 1000e18; // 1,000 tokens
    uint256 public constant SMALL_UNSTAKE = 1e18; // 1 token
    uint256 public constant LARGE_UNSTAKE = 999e18; // 999 tokens
    uint256 public constant LOCKUP_PERIOD = 30 days; // Use 30 days as per contract constants
    uint256 public constant COOLDOWN_PERIOD = 2 days;

    // Events
    event UnstakingInitiated(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 amount);

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
        sapienToken.mint(user1, STAKE_AMOUNT);
    }

    /**
     * @notice Test that demonstrates the cooldown bypass vulnerability
     * @dev This test follows the exact exploit scenario from the audit finding
     * the test should fail if sap-1 vuln is possible
     */
    function skip_test_Vault_SAP_1_CooldownBypassExploit() public {
        console.log("\n=== DEMONSTRATING COOLDOWN BYPASS VULNERABILITY ===");

        // Step 1: User stakes 1,000 tokens with lockup period
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), STAKE_AMOUNT);
        sapienVault.stake(STAKE_AMOUNT, LOCKUP_PERIOD);
        vm.stopPrank();

        console.log("Step 1: User staked", STAKE_AMOUNT / 1e18);
        console.log("Lockup period:", LOCKUP_PERIOD / 1 days);

        // Verify initial state
        assertEq(sapienVault.getTotalStaked(user1), STAKE_AMOUNT);
        assertEq(sapienVault.getTotalLocked(user1), STAKE_AMOUNT);
        assertEq(sapienVault.getTotalUnlocked(user1), 0);

        // Step 2: Wait for lockup period to expire
        vm.warp(block.timestamp + LOCKUP_PERIOD + 1);

        console.log("Step 2: Lockup period expired, tokens now unlocked");

        // Verify tokens are now unlocked
        assertEq(sapienVault.getTotalLocked(user1), 0);
        assertEq(sapienVault.getTotalUnlocked(user1), STAKE_AMOUNT);

        // Step 3: User initiates unstaking for only 1 token (sets cooldownStart)
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit UnstakingInitiated(user1, SMALL_UNSTAKE);
        sapienVault.initiateUnstake(SMALL_UNSTAKE);

        console.log("Step 3: User initiated unstake for", SMALL_UNSTAKE / 1e18);

        // Verify cooldown state
        assertEq(sapienVault.getTotalInCooldown(user1), SMALL_UNSTAKE);
        assertEq(sapienVault.getTotalUnlocked(user1), LARGE_UNSTAKE); // 999 tokens still available

        // Step 4: Wait for cooldown period to complete (2 days)
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        console.log("Step 4: Cooldown completed for the 1 token");

        // Verify the 1 token is ready for unstaking
        assertEq(sapienVault.getTotalReadyForUnstake(user1), SMALL_UNSTAKE);

        // Step 5: User initiates unstaking for remaining 999 tokens
        // THIS IS THE BUG: cooldownStart is NOT updated because it's already set
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit UnstakingInitiated(user1, LARGE_UNSTAKE);
        sapienVault.initiateUnstake(LARGE_UNSTAKE);

        console.log("Step 5: User initiated unstake for remaining", LARGE_UNSTAKE / 1e18);
        console.log("BUG: cooldownStart was NOT updated, still points to original timestamp");

        // Step 6: User can IMMEDIATELY unstake all 999 tokens without waiting
        // This should fail but doesn't due to the bug
        uint256 balanceBefore = sapienToken.balanceOf(user1);

        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Unstaked(user1, LARGE_UNSTAKE);
        sapienVault.unstake(LARGE_UNSTAKE); // This should revert but doesn't!

        uint256 balanceAfter = sapienToken.balanceOf(user1);

        console.log("Step 6: EXPLOIT SUCCESSFUL - User immediately unstaked", LARGE_UNSTAKE / 1e18);
        console.log("Expected cooldown time bypassed:", COOLDOWN_PERIOD / 1 days);

        // Verify the exploit worked
        assertEq(balanceAfter - balanceBefore, LARGE_UNSTAKE);
        assertEq(sapienVault.getTotalStaked(user1), SMALL_UNSTAKE); // Only 1 token left
        assertEq(sapienVault.getTotalInCooldown(user1), SMALL_UNSTAKE); // 1 token still in cooldown

        console.log("\n=== VULNERABILITY CONFIRMED ===");
        console.log("User bypassed", COOLDOWN_PERIOD / 1 days);
        console.log("day cooldown for", LARGE_UNSTAKE / 1e18);
        console.log("Only had to wait cooldown for", SMALL_UNSTAKE / 1e18);
    }

    /**
     * @notice Test showing the intended behavior (what should happen)
     * @dev This test shows how cooldown should work correctly
     * the test should fail if sap-1 vuln is possible
     */
    function skip_test_Vault_SAP_1_IntendedCooldownBehavior() public {
        console.log("\n=== DEMONSTRATING INTENDED COOLDOWN BEHAVIOR ===");

        // Setup: User stakes tokens and waits for unlock
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), STAKE_AMOUNT);
        sapienVault.stake(STAKE_AMOUNT, LOCKUP_PERIOD);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCKUP_PERIOD + 1);

        // User initiates unstaking for 1 token
        vm.prank(user1);
        sapienVault.initiateUnstake(SMALL_UNSTAKE);

        // Wait for cooldown to complete
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // User initiates unstaking for remaining tokens
        vm.prank(user1);
        sapienVault.initiateUnstake(LARGE_UNSTAKE);

        // User should NOT be able to immediately unstake the large amount
        // In a fixed implementation, this should revert
        console.log("In fixed implementation, unstaking 999 tokens should require additional cooldown");

        // For now, this demonstrates the bug exists
        vm.prank(user1);
        sapienVault.unstake(LARGE_UNSTAKE); // This works due to the bug

        console.log("BUG: Large unstake succeeded immediately without proper cooldown");
    }

    /**
     * @notice Test the severity of the vulnerability with larger amounts
     * @dev Shows how this could be exploited with significant stake amounts
     * the test should fail if sap-1 vuln is possible
     */
    function skip_test_Vault_SAP_1_LargeScaleExploit() public {
        uint256 largeStake = 1_000_000e18; // 1M tokens
        uint256 smallTrigger = 1e18; // 1 token to trigger cooldown
        uint256 majorUnstake = largeStake - smallTrigger;

        // Setup large stake
        sapienToken.mint(user1, largeStake);

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), largeStake);
        sapienVault.stake(largeStake, LOCKUP_PERIOD);
        vm.stopPrank();

        // Wait for unlock
        vm.warp(block.timestamp + LOCKUP_PERIOD + 1);

        // Start cooldown with tiny amount
        vm.prank(user1);
        sapienVault.initiateUnstake(smallTrigger);

        // Wait for cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // Exploit: Bypass cooldown for major amount
        vm.prank(user1);
        sapienVault.initiateUnstake(majorUnstake);

        uint256 balanceBefore = sapienToken.balanceOf(user1);

        vm.prank(user1);
        sapienVault.unstake(majorUnstake);

        uint256 balanceAfter = sapienToken.balanceOf(user1);

        console.log("\n=== LARGE SCALE EXPLOIT ===");
        console.log("Bypassed cooldown for:", (balanceAfter - balanceBefore) / 1e18);
        console.log("Only waited cooldown for:", smallTrigger / 1e18);

        // This demonstrates the severity - massive amounts can bypass cooldown
        assertEq(balanceAfter - balanceBefore, majorUnstake);
    }

    /**
     * @notice Test multiple cooldown bypass attempts
     * @dev Shows the vulnerability can be exploited multiple times
     * the test should fail if sap-1 vuln is possible
     */
    function skip_test_Vault_SAP_1_MultipleCooldownBypasses() public {
        uint256 stake1 = 100e18;
        uint256 stake2 = 200e18;
        uint256 stake3 = 300e18;
        uint256 totalStake = stake1 + stake2 + stake3;

        // Setup
        sapienToken.mint(user1, totalStake);
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), totalStake);
        sapienVault.stake(totalStake, LOCKUP_PERIOD);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCKUP_PERIOD + 1);

        // First bypass: Small amount to set cooldown
        vm.prank(user1);
        sapienVault.initiateUnstake(1e18);

        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // Multiple large bypasses
        vm.prank(user1);
        sapienVault.initiateUnstake(stake1);

        vm.prank(user1);
        sapienVault.unstake(stake1); // Should require cooldown but doesn't

        vm.prank(user1);
        sapienVault.initiateUnstake(stake2);

        vm.prank(user1);
        sapienVault.unstake(stake2); // Should require cooldown but doesn't

        console.log("\n=== MULTIPLE BYPASSES SUCCESSFUL ===");
        console.log("Bypassed cooldown multiple times using same initial cooldownStart");
    }

    /**
     * @notice Test that demonstrates the cooldown reset is intentional and prevents bypasses
     * @dev This test shows the new behavior where adding to cooldown resets the timer for security
     */
    function test_Vault_SAP_1_FixedCooldownBehavior() public {
        console.log("\n=== DEMONSTRATING FIXED COOLDOWN BEHAVIOR ===");

        // Setup: User stakes tokens and waits for unlock
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), STAKE_AMOUNT);
        sapienVault.stake(STAKE_AMOUNT, LOCKUP_PERIOD);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCKUP_PERIOD + 1);

        // User initiates unstaking for 1 token
        vm.prank(user1);
        sapienVault.initiateUnstake(SMALL_UNSTAKE);

        console.log("Step 1: User initiated unstake for", SMALL_UNSTAKE / 1e18, "tokens");

        // Wait 1 day (halfway through 2-day cooldown)
        vm.warp(block.timestamp + 1 days);

        console.log("Step 2: Waited 1 day - cooldown period is 2 days");

        // User initiates unstaking for remaining tokens
        // This should reset the cooldown timer for ALL tokens (security feature)
        vm.prank(user1);
        sapienVault.initiateUnstake(LARGE_UNSTAKE);

        console.log("Step 3: User initiated unstake for remaining", LARGE_UNSTAKE / 1e18, "tokens");
        console.log("SECURITY: cooldownStart was updated - all tokens must wait full cooldown period");

        // User should NOT be able to immediately unstake ANY amount
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotReadyForUnstake()"));
        sapienVault.unstake(SMALL_UNSTAKE);

        console.log("Step 4: SECURITY ENFORCED - Cannot unstake even the original 1 token immediately");

        // User should NOT be able to unstake the large amount either
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("NotReadyForUnstake()"));
        sapienVault.unstake(LARGE_UNSTAKE);

        console.log("Step 5: SECURITY ENFORCED - Cannot unstake large amount immediately");

        // Only after full cooldown period should unstaking work
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        console.log("Step 6: After full cooldown period elapsed");

        // Now both amounts should be available for unstaking
        uint256 balanceBefore = sapienToken.balanceOf(user1);

        vm.prank(user1);
        sapienVault.unstake(STAKE_AMOUNT); // Can unstake all at once

        uint256 balanceAfter = sapienToken.balanceOf(user1);

        console.log("Step 7: Successfully unstaked all", STAKE_AMOUNT / 1e18, "tokens after proper cooldown");

        // Verify the security fix worked
        assertEq(balanceAfter - balanceBefore, STAKE_AMOUNT);
        assertEq(sapienVault.getTotalStaked(user1), 0);

        console.log("\n=== SECURITY FIX CONFIRMED ===");
        console.log("Cooldown bypass vulnerability has been fixed");
        console.log("All tokens must wait full cooldown period when new amounts are added");
    }

    /**
     * @notice Test that earlyUnstake cannot be used to bypass cooldown requirements
     * @dev Verify that locked tokens and cooldown tokens cannot exist simultaneously
     */
    function test_Vault_SAP_1_EarlyUnstakeCannotBypassCooldown() public {
        console.log("\n=== TESTING EARLY UNSTAKE COOLDOWN BYPASS SCENARIOS ===");

        // Setup: User stakes tokens with lockup
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), STAKE_AMOUNT);
        sapienVault.stake(STAKE_AMOUNT, LOCKUP_PERIOD);
        vm.stopPrank();

        console.log("Step 1: User staked tokens with lockup period");

        // Verify tokens are locked - earlyUnstake should work
        assertEq(sapienVault.getTotalLocked(user1), STAKE_AMOUNT, "All tokens should be locked");
        assertEq(sapienVault.getTotalUnlocked(user1), 0, "No tokens should be unlocked");
        assertEq(sapienVault.getTotalInCooldown(user1), 0, "No tokens should be in cooldown");

        // Test 1: Cannot initiate cooldown while tokens are locked
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("StakeStillLocked()"));
        sapienVault.initiateUnstake(SMALL_UNSTAKE);

        console.log("Step 2: VERIFIED - Cannot initiate cooldown while tokens are locked");

        // Test 2: EarlyUnstake now requires cooldown (SAP-3 fix)
        uint256 earlyUnstakeAmount = SMALL_UNSTAKE;

        // First attempt to early unstake directly should fail (new behavior)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("EarlyUnstakeCooldownRequired()"));
        sapienVault.earlyUnstake(earlyUnstakeAmount);

        console.log("Step 3: VERIFIED - EarlyUnstake now requires cooldown initiation (SAP-3 fix)");

        // Initiate early unstake cooldown
        vm.prank(user1);
        sapienVault.initiateEarlyUnstake(earlyUnstakeAmount);

        console.log("Step 3a: Early unstake cooldown initiated");

        // Fast forward past cooldown period BUT stay within lock period
        // We need to advance enough for cooldown (2 days) but not exceed the lock period
        uint256 cooldownPeriod = 2 days;
        uint256 timeToAdvance = cooldownPeriod + 1;

        // Make sure we don't exceed the original lock period from when we started
        // We've already used some time, so be more careful about timing
        vm.warp(block.timestamp + timeToAdvance);

        // Now early unstake should work
        uint256 expectedPenalty = (earlyUnstakeAmount * 20) / 100; // 20% penalty
        uint256 expectedPayout = earlyUnstakeAmount - expectedPenalty;

        uint256 balanceBefore = sapienToken.balanceOf(user1);

        vm.prank(user1);
        sapienVault.earlyUnstake(earlyUnstakeAmount);

        uint256 balanceAfter = sapienToken.balanceOf(user1);

        console.log("Step 3b: VERIFIED - EarlyUnstake works after cooldown period with penalty");
        assertEq(balanceAfter - balanceBefore, expectedPayout, "Should receive reduced amount due to penalty");

        // Test 3: Advance to after lock period and check unlocked tokens
        vm.warp(block.timestamp + LOCKUP_PERIOD); // Ensure we're past the original lock period

        console.log("Step 4: Advanced past lock period, checking remaining stake");

        // Now remaining tokens should be unlocked
        uint256 remainingStake = STAKE_AMOUNT - earlyUnstakeAmount;
        assertEq(sapienVault.getTotalUnlocked(user1), remainingStake, "Remaining tokens should be unlocked");
        assertEq(sapienVault.getTotalLocked(user1), 0, "No tokens should be locked");

        // EarlyUnstake should no longer work (since tokens are unlocked)
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSignature("LockPeriodCompleted()"));
        sapienVault.initiateEarlyUnstake(SMALL_UNSTAKE);

        console.log("Step 5: VERIFIED - Cannot initiate early unstake after lock period expires");

        // Test 4: Now initiate cooldown should work
        vm.prank(user1);
        sapienVault.initiateUnstake(SMALL_UNSTAKE);

        console.log("Step 6: VERIFIED - Can initiate cooldown after unlock");

        // Verify state
        assertEq(sapienVault.getTotalInCooldown(user1), SMALL_UNSTAKE, "Tokens should be in cooldown");
        assertEq(
            sapienVault.getTotalUnlocked(user1), remainingStake - SMALL_UNSTAKE, "Remaining unlocked should be reduced"
        );

        console.log("\n=== EARLY UNSTAKE COOLDOWN SECURITY CONFIRMED ===");
        console.log("- Cannot initiate cooldown while locked");
        console.log("- Cannot use earlyUnstake after unlock");
        console.log("- No bypass scenario exists between locked and cooldown states");
    }
}
