// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {AuditBase} from "./AuditBase.t.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {ISapienVault} from "../../src/interfaces/ISapienVault.sol";

/// @title SAP-5 — minDepositAge Is Not Initialized (Informational, Resolved)
/// @notice `initialize`/`initializeV2` now seed `minDepositAge` with
///         `DEFAULT_MIN_DEPOSIT_AGE`, so the MEV guard is active out of the box
///         on a freshly deployed (or freshly upgraded) vault instead of
///         defaulting to 0. These tests deploy a *fresh* proxy because the
///         shared `AuditBase` fixture deliberately disables the guard.
contract SAP5_MinDepositAgeNotInitializedTest is AuditBase {
    /// @dev Deploy a pristine proxy that has only run `initialize`.
    function _freshVault() internal returns (SapienVault fresh) {
        SapienVault impl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), admin));
        fresh = SapienVault(address(new ERC1967Proxy(address(impl), initData)));
    }

    /// @dev Proves the resolution: the guard is enabled immediately after init.
    function test_SAP5_minDepositAgeSeededAtInit() public {
        SapienVault fresh = _freshVault();
        assertEq(
            fresh.minDepositAge(),
            fresh.DEFAULT_MIN_DEPOSIT_AGE(),
            "minDepositAge should be seeded to the default at init (MEV guard enabled)"
        );
        assertGt(fresh.minDepositAge(), 0, "MEV guard must be active out of the box");
    }

    /// @dev With the guard seeded, a deposit-then-lock in the same block now
    ///      reverts: freshly-minted shares are immature, closing the flash/MEV
    ///      window that was open while the parameter defaulted to 0.
    function test_SAP5_depositAndLockSameBlockReverts() public {
        SapienVault fresh = _freshVault();

        token.mint(user1, DEPOSIT_AMOUNT);
        vm.prank(user1);
        token.approve(address(fresh), type(uint256).max);

        vm.prank(user1);
        fresh.deposit(DEPOSIT_AMOUNT, user1);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientAvailableBalance.selector, DEPOSIT_AMOUNT, 0));
        vm.prank(user1);
        fresh.lockStake(DEPOSIT_AMOUNT);
    }
}
