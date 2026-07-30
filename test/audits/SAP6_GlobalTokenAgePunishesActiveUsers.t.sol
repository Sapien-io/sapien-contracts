// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {AuditBase} from "./AuditBase.t.sol";

/// @title SAP-6 — Global Token Age Requirement May Punish Active Users (Informational, Resolved)
/// @notice The cooldown used to apply to a user's entire balance, so a new
///         deposit re-froze funds that had already aged. With per-tranche
///         accounting, only the freshly-deposited cohort is subject to the
///         cooldown; previously-matured funds remain withdrawable.
contract SAP6_GlobalTokenAgePunishesActiveUsersTest is AuditBase {
    /// @dev Resolved: a fresh deposit does NOT re-freeze already-aged funds.
    function test_resolved_freshDepositKeepsAgedFundsWithdrawable() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        // First deposit ages and becomes fully withdrawable.
        vm.prank(user1);
        vault.deposit(500e18, user1);
        skip(1 days);
        uint256 withdrawableAged = vault.maxWithdraw(user1);
        assertGt(withdrawableAged, 0, "aged funds should be withdrawable");

        // A second deposit must NOT re-freeze the already-aged tranche.
        vm.prank(user1);
        vault.deposit(500e18, user1);

        assertApproxEqAbs(
            vault.maxWithdraw(user1), withdrawableAged, 2, "aged funds must stay withdrawable after a fresh deposit"
        );
    }

    /// @dev The fresh cohort matures independently after its own cooldown,
    ///      unlocking the full balance without re-aging the older funds.
    function test_resolved_freshCohortMaturesIndependently() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(500e18, user1);
        skip(1 days);

        vm.prank(user1);
        vault.deposit(500e18, user1);

        // Only the fresh 500 is locked; the aged 500 stays available.
        uint256 agedOnly = vault.maxWithdraw(user1);
        assertGt(agedOnly, 0, "aged portion remains withdrawable immediately");
        assertEq(vault.pendingShares(user1), vault.convertToShares(500e18), "only the fresh cohort is pending");

        skip(1 days);
        assertEq(vault.pendingShares(user1), 0, "fresh cohort matures after its own cooldown");
        assertGt(vault.maxWithdraw(user1), agedOnly, "full balance withdrawable after fresh cohort matures");
    }
}
