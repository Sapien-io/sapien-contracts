// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AuditBase} from "./AuditBase.t.sol";
import {ISapienVault} from "../../src/interfaces/ISapienVault.sol";
import {
    IAccessControlDefaultAdminRules
} from "lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";

/// @title S2 — Improved Role Management (Resolved)
/// @notice The vault now extends `AccessControlDefaultAdminRulesUpgradeable`:
///         a single `DEFAULT_ADMIN_ROLE` holder, two-step time-locked admin
///         transfers, and a hard block on renouncing the admin role so the vault
///         can never be left ownerless.
contract S2_ImprovedRoleManagementTest is AuditBase {
    address internal newAdmin = makeAddr("newAdmin");

    /// @dev Single-admin enforcement: `DEFAULT_ADMIN_ROLE` cannot be granted via
    ///      the direct `grantRole` path (only the two-step transfer rotates it).
    function test_S2_cannotDirectlyGrantDefaultAdmin() public {
        vm.expectRevert(IAccessControlDefaultAdminRules.AccessControlEnforcedDefaultAdminRules.selector);
        vm.prank(admin);
        vault.grantRole(ADMIN_ROLE, newAdmin);
    }

    /// @dev The incumbent admin is recorded as `defaultAdmin()` / `owner()`.
    function test_S2_defaultAdminAndOwnerResolve() public view {
        assertEq(vault.defaultAdmin(), admin, "defaultAdmin");
        assertEq(vault.owner(), admin, "owner (ERC-5313)");
        assertEq(vault.defaultAdminDelay(), vault.DEFAULT_ADMIN_TRANSFER_DELAY(), "initial delay");
    }

    /// @dev Renouncing `DEFAULT_ADMIN_ROLE` is hard-disabled.
    function test_S2_renounceDefaultAdminDisabled() public {
        vm.expectRevert(ISapienVault.DefaultAdminRenounceDisabled.selector);
        vm.prank(admin);
        vault.renounceRole(ADMIN_ROLE, admin);
    }

    /// @dev Non-admin roles renounce normally (the block is scoped to admin).
    function test_S2_renounceOtherRoleAllowed() public {
        assertTrue(vault.hasRole(ENGINE_ROLE, engine));
        vm.prank(engine);
        vault.renounceRole(ENGINE_ROLE, engine);
        assertFalse(vault.hasRole(ENGINE_ROLE, engine), "engine role should be renounceable");
    }

    /// @dev Two-step transfer: accepting before the delay elapses reverts; after
    ///      the delay the role moves atomically from the old to the new admin.
    function test_S2_twoStepAdminTransfer() public {
        vm.prank(admin);
        vault.beginDefaultAdminTransfer(newAdmin);

        // Premature acceptance is rejected by the time lock.
        vm.expectRevert();
        vm.prank(newAdmin);
        vault.acceptDefaultAdminTransfer();

        skip(vault.DEFAULT_ADMIN_TRANSFER_DELAY() + 1);

        vm.prank(newAdmin);
        vault.acceptDefaultAdminTransfer();

        assertEq(vault.defaultAdmin(), newAdmin, "admin handed over");
        assertFalse(vault.hasRole(ADMIN_ROLE, admin), "old admin demoted");
        assertTrue(vault.hasRole(ADMIN_ROLE, newAdmin), "new admin promoted");

        // New admin can govern; old admin cannot.
        vm.prank(newAdmin);
        vault.pause();
        assertTrue(vault.paused());
    }

    /// @dev Only the pending admin may accept the transfer.
    function test_S2_onlyPendingAdminCanAccept() public {
        vm.prank(admin);
        vault.beginDefaultAdminTransfer(newAdmin);
        skip(vault.DEFAULT_ADMIN_TRANSFER_DELAY() + 1);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControlDefaultAdminRules.AccessControlInvalidDefaultAdmin.selector, user1)
        );
        vm.prank(user1);
        vault.acceptDefaultAdminTransfer();
    }
}
