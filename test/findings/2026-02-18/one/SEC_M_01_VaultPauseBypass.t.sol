// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";

/// @title SEC-M-01 FIX VERIFICATION: ERC4626 functions respect pause
/// @notice Verifies that deposit/withdraw/redeem/mint are all blocked when the vault is paused,
///         preventing front-running of emergency pauses.
contract SEC_M_01_VaultPauseBypass is BaseTest {
    address public user = makeAddr("vaultUser");

    function setUp() public override {
        super.setUp();
        token.mint(user, 1000e18);
        vm.startPrank(user);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(500e18, user);
        vm.stopPrank();
    }

    function test_depositBlockedWhilePaused() public {
        vm.prank(admin);
        vault.pause();
        assertTrue(vault.paused(), "vault is paused");

        // FIX VERIFIED: maxDeposit returns 0 when paused, causing deposit to revert
        assertEq(vault.maxDeposit(user), 0, "maxDeposit should be 0 when paused");

        vm.prank(user);
        vm.expectRevert(); // ERC4626ExceededMaxDeposit
        vault.deposit(100e18, user);
    }

    function test_mintBlockedWhilePaused() public {
        vm.prank(admin);
        vault.pause();

        // FIX VERIFIED: maxMint returns 0 when paused
        assertEq(vault.maxMint(user), 0, "maxMint should be 0 when paused");

        vm.prank(user);
        vm.expectRevert(); // ERC4626ExceededMaxMint
        vault.mint(1e18, user);
    }

    function test_withdrawBlockedWhilePaused() public {
        vm.prank(admin);
        vault.pause();

        // FIX VERIFIED: maxWithdraw returns 0 when paused (via maxRedeem returning 0)
        assertEq(vault.maxWithdraw(user), 0, "maxWithdraw should be 0 when paused");
    }

    function test_redeemBlockedWhilePaused() public {
        vm.prank(admin);
        vault.pause();

        // FIX VERIFIED: maxRedeem returns 0 when paused
        assertEq(vault.maxRedeem(user), 0, "maxRedeem should be 0 when paused");
    }

    function test_depositWorksAfterUnpause() public {
        vm.prank(admin);
        vault.pause();

        vm.prank(admin);
        vault.unpause();

        // After unpausing, deposits should work again
        vm.prank(user);
        vault.deposit(100e18, user);
        assertTrue(vault.totalStaked(user) > 500e18, "deposit succeeded after unpause");
    }
}
