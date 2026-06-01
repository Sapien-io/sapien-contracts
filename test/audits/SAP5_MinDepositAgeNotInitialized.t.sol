// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AuditBase} from "./AuditBase.t.sol";

/// @title SAP-5 — minDepositAge Is Not Initialized (Informational, Unresolved)
/// @notice `minDepositAge` is admin-configurable but is never set during
///         `initialize`, so it defaults to 0 and the MEV protection is disabled
///         on a freshly deployed vault until an admin explicitly sets it.
contract SAP5_MinDepositAgeNotInitializedTest is AuditBase {
    /// @dev Proves the finding: immediately after deployment the guard is off.
    function test_SAP5_minDepositAgeDefaultsToZero() public view {
        assertEq(vault.minDepositAge(), 0, "minDepositAge should be 0 right after init (MEV guard disabled)");
    }

    /// @dev With the guard at its uninitialized default, a user can deposit and
    ///      lock in the same block — the flash-loan/MEV window the parameter is
    ///      meant to close is wide open until an admin configures it.
    function test_SAP5_depositAndLockSameBlockWhileUninitialized() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(DEPOSIT_AMOUNT);

        assertEq(vault.getStakeAccount(user1).lockedAmount, DEPOSIT_AMOUNT, "no cooldown enforced at default age 0");
    }
}
