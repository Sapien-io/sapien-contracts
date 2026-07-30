// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {AuditBase} from "./AuditBase.t.sol";
import {ISapienVault} from "../../src/interfaces/ISapienVault.sol";
import {StakeAccount} from "../../src/Types.sol";

/// @title SAP-3 — MEV: Protection Bypass via Delegate Deposits (Medium, Resolved)
/// @notice Previously `_deposit` only aged the receiver when `caller == receiver`,
///         so a helper could mint shares to a receiver without arming the
///         cooldown. The tranche refactor ages every mint in `_update` (mint
///         branch) regardless of caller, so delegated/third-party deposits land
///         as immature shares that cannot be locked, transferred, or redeemed
///         until they mature.
contract SAP3_MevBypassViaDelegateDepositsTest is AuditBase {
    /// @dev Resolved: shares delegate-deposited to an aged user are immature and
    ///      cannot be locked beyond the user's already-matured balance.
    function test_resolved_delegateDepositSharesAreImmature() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.warp(block.timestamp + 1 days);

        // Helper delegate-deposits 500 more to user1 (caller != receiver).
        token.mint(user2, 500e18);
        vm.prank(user2);
        token.approve(address(vault), 500e18);
        vm.prank(user2);
        vault.deposit(500e18, user1);

        // The fresh 500 is immature: user1 can only lock its matured 1000.
        uint256 avail = vault.availableBalance(user1);
        assertApproxEqAbs(avail, DEPOSIT_AMOUNT, 1, "only matured balance should be available");
        vm.expectRevert(
            abi.encodeWithSelector(ISapienVault.InsufficientAvailableBalance.selector, DEPOSIT_AMOUNT + 500e18, avail)
        );
        vm.prank(user1);
        vault.lockStake(DEPOSIT_AMOUNT + 500e18);

        // After aging, the delegated shares become lockable.
        skip(1 days);
        vm.prank(user1);
        vault.lockStake(DEPOSIT_AMOUNT + 500e18);
        assertEq(vault.getStakeAccount(user1).lockedAmount, DEPOSIT_AMOUNT + 500e18);
    }

    /// @dev Resolved: a fresh receiver funded entirely via a third-party deposit
    ///      can no longer lock immediately — the granted shares are immature.
    function test_resolved_thirdPartyDepositAgesReceiver() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        token.mint(user2, DEPOSIT_AMOUNT);
        vm.prank(user2);
        token.approve(address(vault), DEPOSIT_AMOUNT);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        assertEq(vault.availableBalance(user1), 0, "granted shares must be immature");
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientAvailableBalance.selector, DEPOSIT_AMOUNT, 0));
        vm.prank(user1);
        vault.lockStake(DEPOSIT_AMOUNT);

        skip(1 days);
        vm.prank(user1);
        vault.lockStake(DEPOSIT_AMOUNT);
        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, DEPOSIT_AMOUNT);
    }
}
