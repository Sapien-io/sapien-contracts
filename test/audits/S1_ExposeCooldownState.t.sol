// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AuditBase} from "./AuditBase.t.sol";
import {ISapienVault} from "../../src/interfaces/ISapienVault.sol";

/// @title S1 — Expose Explicit Cooldown State for Users and Integrators (Resolved)
/// @notice The pre-refactor finding asked for a public `lastDepositTimestamp` /
///         `depositAgeStatus` getter so integrators could distinguish a cooldown
///         from a pause, a lock, or an empty balance when `maxWithdraw == 0`.
///         The tranche refactor has no single per-user timer, so the resolution
///         exposes `depositAgeStatus(user)` (matured/pending split, configured
///         `minAge`, and seconds until the next cohort matures) and widens
///         `MinDepositAgeUpdated` to carry both the old and new value.
contract S1_ExposeCooldownStateTest is AuditBase {
    function _enableGuard(uint256 age) internal {
        vm.prank(admin);
        vault.setMinDepositAge(age);
    }

    /// @dev Fresh deposit: everything pending, remaining ~= minAge; after the
    ///      window it is fully matured with zero remaining.
    function test_S1_depositAgeStatus_freshThenMatured() public {
        uint256 age = 2 days;
        _enableGuard(age);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 bal = vault.balanceOf(user1);

        (uint256 matured, uint256 pending, uint256 minAge, uint256 remaining) = vault.depositAgeStatus(user1);
        assertEq(matured, 0, "nothing matured yet");
        assertEq(pending, bal, "all shares pending");
        assertEq(minAge, age, "minAge reported");
        assertEq(remaining, age, "remaining equals full window at deposit");
        // Cross-check the maxWithdraw==0 ambiguity is now explainable.
        assertEq(vault.maxWithdraw(user1), 0, "immature shares not withdrawable");

        skip(age);
        (matured, pending, minAge, remaining) = vault.depositAgeStatus(user1);
        assertEq(matured, bal, "all matured after window");
        assertEq(pending, 0, "nothing pending after window");
        assertEq(remaining, 0, "no remaining once matured");
    }

    /// @dev Two cohorts deposited at different times: the matured/pending split
    ///      tracks each cohort and `remaining` counts down to the *oldest* still
    ///      immature cohort.
    function test_S1_depositAgeStatus_partialMaturity() public {
        uint256 age = 4 days;
        _enableGuard(age);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 firstCohort = vault.balanceOf(user1);

        skip(1 days);
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        uint256 secondCohort = vault.balanceOf(user1) - firstCohort;

        // Neither cohort has matured; oldest matures in (age - 1 day).
        (uint256 matured, uint256 pending,, uint256 remaining) = vault.depositAgeStatus(user1);
        assertEq(matured, 0, "no cohort matured");
        assertEq(pending, firstCohort + secondCohort, "both cohorts pending");
        assertEq(remaining, age - 1 days, "remaining tracks oldest cohort");

        // Advance until only the first cohort has matured.
        skip(age - 1 days);
        (matured, pending,, remaining) = vault.depositAgeStatus(user1);
        assertEq(matured, firstCohort, "first cohort matured");
        assertEq(pending, secondCohort, "second cohort still pending");
        assertEq(remaining, 1 days, "remaining now tracks second cohort");
    }

    /// @dev With the guard disabled, all shares are immediately mature and there
    ///      is nothing to wait for.
    function test_S1_depositAgeStatus_guardDisabled() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        (uint256 matured, uint256 pending, uint256 minAge, uint256 remaining) = vault.depositAgeStatus(user1);
        assertEq(matured, vault.balanceOf(user1), "all mature when guard off");
        assertEq(pending, 0, "nothing pending when guard off");
        assertEq(minAge, 0, "minAge zero");
        assertEq(remaining, 0, "no remaining when guard off");
    }

    /// @dev `MinDepositAgeUpdated` now carries the previous value too.
    function test_S1_minDepositAgeUpdated_reportsOldAndNew() public {
        _enableGuard(1 days);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ISapienVault.MinDepositAgeUpdated(1 days, 3 days);
        vm.prank(admin);
        vault.setMinDepositAge(3 days);
    }
}
