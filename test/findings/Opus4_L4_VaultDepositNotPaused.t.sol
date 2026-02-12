// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";

/**
 * @title Opus4_L4_VaultDepositNotPaused
 * @notice Opus 4.6 Security Review - L-4 FIX VERIFICATION
 *
 * ORIGINAL FINDING:
 * deposit() and mint() inherited from ERC4626Upgradeable were NOT guarded
 * by whenNotPaused, allowing deposits during emergency pauses but blocking
 * withdrawals, trapping tokens.
 *
 * FIX APPLIED:
 * deposit() and mint() now override with whenNotPaused modifier.
 *
 * LOCATION: SapienVault.sol
 * SEVERITY: Low (now fixed)
 */
contract Opus4_L4_VaultDepositNotPaused is BaseTest {
    address public depositor = makeAddr("depositor");

    function setUp() public override {
        super.setUp();

        stakeToken.mint(depositor, 100 ether);
        vm.prank(depositor);
        stakeToken.approve(address(vault), 100 ether);
    }

    /**
     * @notice FIX VERIFIED: deposit reverts while paused
     */
    function test_L4_Fix_DepositRevertsWhilePaused() public {
        console.log("=== L-4 FIX: Deposit Reverts While Paused ===");

        vm.prank(admin);
        vault.pause();

        vm.prank(depositor);
        vm.expectRevert(); // EnforcedPause
        vault.deposit(50 ether, depositor);

        console.log("deposit() correctly REVERTED while paused");
        console.log("FIX VERIFIED: No tokens can be trapped during emergency pause.");
    }

    /**
     * @notice FIX VERIFIED: mint reverts while paused
     */
    function test_L4_Fix_MintRevertsWhilePaused() public {
        console.log("=== L-4 FIX: Mint Reverts While Paused ===");

        vm.prank(admin);
        vault.pause();

        vm.prank(depositor);
        vm.expectRevert(); // EnforcedPause
        vault.mint(1000, depositor);

        console.log("mint() correctly REVERTED while paused");
    }

    /**
     * @notice deposit and mint still work when NOT paused
     */
    function test_L4_Fix_DepositAndMintWorkWhenUnpaused() public {
        console.log("=== L-4 FIX: Normal Operation ===");

        vm.prank(depositor);
        uint256 shares = vault.deposit(50 ether, depositor);
        assertGt(shares, 0, "Deposit should succeed when unpaused");
        console.log("deposit() SUCCEEDED when unpaused");

        uint256 mintShares = vault.previewDeposit(10 ether);
        vm.prank(depositor);
        vault.mint(mintShares, depositor);
        console.log("mint() SUCCEEDED when unpaused");
    }

    /**
     * @notice Full pause symmetry: all ERC4626 operations blocked during pause
     */
    function test_L4_Fix_FullPauseSymmetry() public {
        console.log("=== L-4 FIX: Full Pause Symmetry ===");

        // Deposit first while unpaused
        vm.prank(depositor);
        vault.deposit(50 ether, depositor);

        vm.prank(admin);
        vault.pause();

        // All operations should revert
        vm.startPrank(depositor);

        vm.expectRevert();
        vault.deposit(10 ether, depositor);
        console.log("[PAUSED] deposit     -> REVERTED");

        vm.expectRevert();
        vault.mint(1000, depositor);
        console.log("[PAUSED] mint        -> REVERTED");

        vm.expectRevert();
        vault.withdraw(1 ether, depositor, depositor);
        console.log("[PAUSED] withdraw    -> REVERTED");

        vm.expectRevert();
        vault.redeem(1, depositor, depositor);
        console.log("[PAUSED] redeem      -> REVERTED");

        vm.expectRevert();
        vault.transfer(admin, 1);
        console.log("[PAUSED] transfer    -> REVERTED");

        vm.stopPrank();

        console.log("FIX VERIFIED: All ERC4626 operations now consistently paused.");
    }
}
