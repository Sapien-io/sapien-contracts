// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "./BaseTest.t.sol";
import {SLASHER_ROLE} from "../src/interface/ISharedTypes.sol";

contract VaultTest is BaseTest {
    function testDeposit() public {
        uint256 amount = 100 ether;
        stakeToken.mint(contributor, amount);

        vm.startPrank(contributor);
        stakeToken.approve(address(vault), amount);
        vault.deposit(amount, contributor);
        vm.stopPrank();

        assertEq(vault.getStake(contributor), 1100 ether); // 1000 from BaseTest + 100
    }

    function testLocking() public {
        vm.startPrank(admin);

        vault.lockStake(validator1, 500 ether, "test lock");
        assertEq(vault.getLockedStake(validator1), 500 ether);
        assertEq(vault.getAvailableStake(validator1), 500 ether);

        vm.expectRevert(); // Insufficient unlocked stake
        vault.withdraw(600 ether, validator1, validator1);

        vault.unlockStake(validator1, 200 ether, "test unlock");
        assertEq(vault.getLockedStake(validator1), 300 ether);

        vm.stopPrank();
    }

    function testSlashing() public {
        vm.startPrank(admin);
        assertTrue(vault.hasRole(SLASHER_ROLE, admin));

        uint256 balanceBefore = vault.balanceOf(validator1);
        uint256 assetBalanceBefore = vault.getStake(validator1);
        uint256 sharesToSlash = vault.convertToShares(100 ether);

        uint256 slashed = vault.slash(validator1, 100 ether, "test project");
        uint256 balanceAfter = vault.balanceOf(validator1);
        uint256 assetBalanceAfter = vault.getStake(validator1);

        // Shares should be burned
        assertEq(balanceBefore - balanceAfter, sharesToSlash);
        assertEq(slashed, 100 ether);

        // Asset balance should decrease, but less than 100 ether due to redistribution
        // (the slashed assets stay in the vault, increasing the value of remaining shares)
        assertTrue(assetBalanceAfter < assetBalanceBefore);

        // Locked stake should be adjusted if it exceeds new balance
        vault.lockStake(validator2, 900 ether, "lock most");
        vault.slash(validator2, 200 ether, "test project");
        uint256 newBalance2 = vault.getStake(validator2);
        assertLe(vault.getLockedStake(validator2), newBalance2);

        vm.stopPrank();
    }

    function testVaultInitializeReverts() public {
        vm.expectRevert(InvalidInitialization.selector);
        vault.initialize(address(stakeToken), admin);
    }

    function testLockUnlockEdgeCases() public {
        vm.startPrank(admin);

        vm.expectRevert(bytes4(keccak256("ZeroAmount()")));
        vault.lockStake(validator1, 0, "zero");

        vm.expectRevert(bytes4(keccak256("ZeroAmount()")));
        vault.unlockStake(validator1, 0, "zero");

        uint256 available = vault.getAvailableStake(validator1);
        vm.expectRevert(
            abi.encodeWithSignature(
                "InsufficientUnlockedStake(address,uint256,uint256)", validator1, available + 1, available
            )
        );
        vault.lockStake(validator1, available + 1, "too much");

        vault.lockStake(validator1, 100 ether, "lock");
        vm.expectRevert(
            abi.encodeWithSignature(
                "InsufficientLockedStake(address,uint256,uint256)", validator1, 200 ether, 100 ether
            )
        );
        vault.unlockStake(validator1, 200 ether, "too much");

        vm.stopPrank();
    }

    function testVaultPause() public {
        vm.startPrank(admin);
        vault.pause();
        assertTrue(vault.paused());

        vm.expectRevert(EnforcedPause.selector);
        vault.lockStake(validator1, 100 ether, "paused");

        vm.expectRevert(EnforcedPause.selector);
        vault.slash(validator1, 100 ether, "paused");

        // transfer is restricted
        vm.expectRevert(EnforcedPause.selector);
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        // return value not checked because we expect revert
        vault.transfer(validator2, 10);

        vault.unpause();
        assertFalse(vault.paused());
        vm.stopPrank();
    }

    function testTransferRestrictions() public {
        vm.prank(admin);
        vault.lockStake(validator1, 900 ether, "lock 900");

        vm.startPrank(validator1);
        // Shares are 1000x assets due to decimalsOffset=3?
        // Let's check convertToShares logic.
        uint256 availableShares = vault.balanceOf(validator1) - vault.convertToShares(900 ether);

        // Should be able to transfer available shares
        bool success1 = vault.transfer(validator2, availableShares / 2);
        assertTrue(success1, "Transfer should succeed");

        // Should fail to transfer more than available
        vm.expectRevert();
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        // return value not checked because we expect revert
        vault.transfer(validator2, availableShares); // already transferred half
        vm.stopPrank();
    }

    function testWithdrawRedeemRestrictions() public {
        vm.prank(admin);
        vault.lockStake(validator1, 900 ether, "lock 900");

        vm.startPrank(validator1);
        uint256 availableAssets = vault.getStake(validator1) - 900 ether;

        // Should fail to withdraw more than available
        vm.expectRevert();
        vault.withdraw(availableAssets + 1 ether, validator1, validator1);

        // Should fail to redeem more than available
        uint256 availableShares = vault.balanceOf(validator1) - vault.convertToShares(900 ether);
        vm.expectRevert();
        vault.redeem(availableShares + 1, validator1, validator1);

        // Success cases
        vault.withdraw(availableAssets / 2, validator1, validator1);
        vm.stopPrank();
    }

    function testViewFunctions() public view {
        assertEq(address(vault.stakingToken()), address(stakeToken));
        assertEq(vault.totalStaked(), vault.totalAssets());
        assertEq(vault.totalStaked(), stakeToken.balanceOf(address(vault)));
    }

    function testSlashEdgeCases() public {
        vm.startPrank(admin);

        // Slash more than balance
        uint256 balance = vault.getStake(validator3);
        uint256 slashed = vault.slash(validator3, balance + 100 ether, "project");
        assertEq(slashed, balance);
        assertEq(vault.getStake(validator3), 0);

        // Slash 0 balance
        uint256 slashedZero = vault.slash(validator3, 100 ether, "project");
        assertEq(slashedZero, 0);

        vm.stopPrank();
    }

    function testGetAvailableStakeAllLocked() public {
        vm.startPrank(admin);
        vault.lockStake(contributor, vault.getStake(contributor), "test");

        // All stake is locked, available should be 0
        assertEq(vault.getAvailableStake(contributor), 0);
        vm.stopPrank();
    }

    function testSlashAdjustsLockedStake() public {
        vm.startPrank(admin);

        // Lock all stake
        uint256 totalStake = vault.getStake(contributor);
        vault.lockStake(contributor, totalStake, "test");

        // Slash more than locked amount
        vault.slash(contributor, totalStake, keccak256("project"));

        // Locked stake should be adjusted to new balance
        uint256 newBalance = vault.getStake(contributor);
        assertEq(vault.getLockedStake(contributor), newBalance);
        assertTrue(newBalance < totalStake);

        vm.stopPrank();
    }

    function testSlashZeroShares() public {
        address newUser = makeAddr("newUser");

        vm.startPrank(admin);
        // User with no shares
        uint256 slashed = vault.slash(newUser, 100 ether, keccak256("project"));
        assertEq(slashed, 0);
        vm.stopPrank();
    }

    function testSlashZeroAmount() public {
        vm.startPrank(admin);
        // Slash zero amount
        uint256 slashed = vault.slash(contributor, 0, keccak256("project"));
        assertEq(slashed, 0);
        vm.stopPrank();
    }

    function testCheckUnlockedStakeAllLocked() public {
        vm.startPrank(admin);
        uint256 totalStake = vault.getStake(contributor);
        vault.lockStake(contributor, totalStake, "test");

        // Try to transfer - should revert
        vm.stopPrank();

        vm.startPrank(contributor);
        vm.expectRevert(); // InsufficientUnlockedStake
        // forge-lint: disable-next-line(erc20-unchecked-transfer)
        // return value not checked because we expect revert
        vault.transfer(validator1, 1);
        vm.stopPrank();
    }

    error InvalidInitialization();
    error EnforcedPause();
}

