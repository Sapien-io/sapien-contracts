// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {AuditBase} from "./AuditBase.t.sol";
import {ISapienVault} from "../../src/interfaces/ISapienVault.sol";
import {StakeAccount} from "../../src/Types.sol";

/// @title SAP-1 — Shares Transfer Griefing Vector (High, Resolved)
/// @notice The MEV/cooldown timer used to apply globally to a user's full
///         balance and was reset by any incoming share transfer, so an attacker
///         could repeatedly send dust shares to freeze a victim's stake/transfer/
///         withdraw flows. The tranche refactor binds the cooldown to the
///         specific shares that arrive, never to the victim's already-matured
///         balance, so the griefing vector no longer exists.
/// @dev These tests assert the resolved behavior: a victim's matured funds stay
///      actionable regardless of inbound dust (transfer or delegate deposit),
///      and the per-user tranche cap bounds the work an attacker can impose.
contract SAP1_SharesTransferGriefingTest is AuditBase {
    /// @dev With `minTrancheSize` set, dust delegate deposits revert outright
    ///      instead of creating immature cohorts on the victim.
    function test_resolved_minTrancheSizeBlocksDustDelegateDeposit() public {
        vm.startPrank(admin);
        vault.setMinDepositAge(1 days);
        vault.setMinTrancheSize(1e18);
        vm.stopPrank();

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        skip(1 days);

        uint256 dustAssets = 1;
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.BelowMinTrancheSize.selector, dustAssets, 1e18));
        vm.prank(user2);
        vault.deposit(dustAssets, user1);

        assertGt(vault.maxWithdraw(user1), 0);
    }

    /// @dev A mature-share transfer to a victim can no longer freeze them: the
    ///      received shares simply arrive as matured and the victim's prior
    ///      matured balance remains lockable/withdrawable in the same block.
    function test_resolved_dustTransferDoesNotFreezeVictim() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        skip(1 days);

        // Attacker prepares and ages 1 share, then sends it to the victim.
        token.mint(user2, 1);
        vm.prank(user2);
        token.approve(address(vault), 1);
        vm.prank(user2);
        vault.deposit(1, user2);
        skip(1 days);
        vm.prank(user2);
        vault.transfer(user1, 1);

        // Victim is NOT frozen: lockStake and withdrawals work immediately.
        assertGt(vault.maxWithdraw(user1), 0, "victim wrongly frozen by inbound transfer");
        vm.prank(user1);
        vault.lockStake(400e18);
        assertEq(vault.getStakeAccount(user1).lockedAmount, 400e18);
    }

    /// @dev A delegate dust deposit to the victim only adds an immature cohort;
    ///      it cannot touch the victim's already-matured balance.
    function test_resolved_delegateDustDepositDoesNotFreezeVictim() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        skip(1 days);

        uint256 withdrawableBefore = vault.maxWithdraw(user1);

        // Attacker dust-deposits to the victim every block.
        token.mint(user2, 10);
        vm.prank(user2);
        token.approve(address(vault), 10);
        for (uint256 i; i < 10; ++i) {
            vm.prank(user2);
            vault.deposit(1, user1);
        }

        // Matured balance is untouched; victim can still withdraw and lock it.
        assertEq(vault.maxWithdraw(user1), withdrawableBefore, "matured balance must be unaffected by dust");
        vm.prank(user1);
        vault.lockStake(400e18);
        assertEq(vault.getStakeAccount(user1).lockedAmount, 400e18);
    }

    /// @dev The per-user immature-tranche cap bounds attacker-imposed work: even
    ///      after far more than MAX_IMMATURE_TRANCHES dust deposits, the victim's
    ///      matured funds remain fully actionable and operations succeed.
    function test_resolved_dustSpamIsGasBounded() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        skip(1 days);

        token.mint(user2, 100);
        vm.prank(user2);
        token.approve(address(vault), 100);
        for (uint256 i; i < 100; ++i) {
            vm.prank(user2);
            vault.deposit(1, user1);
        }

        // lockStake still settles within a bounded amount of gas.
        uint256 gasBefore = gasleft();
        vm.prank(user1);
        vault.lockStake(400e18);
        uint256 gasUsed = gasBefore - gasleft();
        assertLt(gasUsed, 500_000, "settle should be bounded by the tranche cap");
        assertEq(vault.getStakeAccount(user1).lockedAmount, 400e18);
    }

    /// @dev A first-time recipient of MATURE shares receives them as matured and
    ///      can act immediately (age travels with the shares).
    function test_resolved_matureTransferToFirstTimeRecipient() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        skip(1 days);

        uint256 sharesToTransfer = vault.balanceOf(user1) / 2;
        uint256 transferredAssets = vault.convertToAssets(sharesToTransfer);

        vm.prank(user1);
        vault.transfer(user2, sharesToTransfer);

        // Recipient can lock immediately: the shares were already aged.
        vm.prank(user2);
        vault.lockStake(transferredAssets);
        StakeAccount memory acct = vault.getStakeAccount(user2);
        assertEq(acct.lockedAmount, transferredAssets);
    }
}
