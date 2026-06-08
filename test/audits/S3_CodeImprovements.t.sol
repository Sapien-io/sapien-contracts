// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AuditBase} from "./AuditBase.t.sol";
import {StakeAccount} from "../../src/Types.sol";

/// @title S3 — Code Improvements (Resolved / Decided)
/// @notice Covers the accepted code-quality items:
///         (c) `maxRedeem`/`maxWithdraw` share one `_availableMatureShares` helper;
///         (d) `getUserStakeBalance` renamed to `assetsOf` (its real meaning);
///         (e) `setMinDepositAge` no longer emits/writes on a no-op.
///         (a) was deliberately kept: `StakeAccount` remains a struct (public ABI).
///         (b) was already removed by the SAP-1 refactor.
contract S3_CodeImprovementsTest is AuditBase {
    /// @dev (d) `assetsOf` reports the asset value of the user's whole share
    ///      balance, and tracks donations to the vault (rate appreciation).
    function test_S3_assetsOf_reportsAssetValue() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        assertEq(vault.assetsOf(user1), vault.convertToAssets(vault.balanceOf(user1)), "assetsOf == convertToAssets");
        assertEq(vault.assetsOf(user1), DEPOSIT_AMOUNT, "1:1 on first deposit");

        token.mint(address(this), 500e18);
        token.transfer(address(vault), 500e18);
        assertGt(vault.assetsOf(user1), DEPOSIT_AMOUNT, "assetsOf tracks rate appreciation");
    }

    /// @dev (a) The `StakeAccount` struct is retained as the public return type.
    function test_S3_stakeAccountStructRetained() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        vault.lockStake(400e18);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, 400e18, "struct carries lockedAmount");
    }

    /// @dev (c) The shared helper keeps `maxWithdraw`, `maxRedeem`, and
    ///      `availableBalance` mutually consistent for a partially-locked holder.
    function test_S3_maxWithdrawRedeemConsistent() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        vault.lockStake(400e18);

        assertEq(vault.availableBalance(user1), vault.maxWithdraw(user1), "availableBalance == maxWithdraw");
        assertEq(
            vault.maxWithdraw(user1),
            vault.convertToAssets(vault.maxRedeem(user1)),
            "maxWithdraw == convertToAssets(maxRedeem)"
        );
        assertApproxEqAbs(vault.maxWithdraw(user1), 600e18, 1, "available ~= deposit - locked");
    }

    /// @dev (e) A redundant `setMinDepositAge` neither writes nor emits.
    function test_S3_setMinDepositAgeNoopIsSilent() public {
        vm.prank(admin);
        vault.setMinDepositAge(2 days);

        vm.recordLogs();
        vm.prank(admin);
        vault.setMinDepositAge(2 days);
        assertEq(vm.getRecordedLogs().length, 0, "no-op must not emit");
        assertEq(vault.minDepositAge(), 2 days, "value unchanged");
    }
}
