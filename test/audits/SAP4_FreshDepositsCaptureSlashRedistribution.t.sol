// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AuditBase} from "./AuditBase.t.sol";
import {ISapienVault} from "../../src/interfaces/ISapienVault.sol";
import {
    ERC4626Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";

/// @title SAP-4 — MEV: Fresh Deposits Capture Slash Redistribution (Low, Mitigated)
/// @notice Because slashed value stays in the vault (see SAP-2) and lifts the
///         exchange rate, an operator who deposits before a predictable slash
///         could capture the redistribution. The tranche refactor ages every
///         inflow (including the SAP-3 delegate path), so freshly-deposited
///         shares are immature and cannot be redeemed/transferred in the slash
///         window. Capture now requires aged, at-risk capital (the incumbent
///         reward the design intends), not flash-positioned fresh capital.
contract SAP4_FreshDepositsCaptureSlashRedistributionTest is AuditBase {
    /// @dev A self-depositing front-runner is blocked: fresh shares are immature,
    ///      so both withdraw and transfer-out revert in the slash window.
    function test_mev_frontrunSlashStakeBlocked() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        vault.lockStake(400e18);

        token.mint(user2, DEPOSIT_AMOUNT * 10);
        vm.prank(user2);
        token.approve(address(vault), DEPOSIT_AMOUNT * 10);

        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT * 10, user2);

        vm.prank(engine);
        vault.slashStake(user1, 400e18);

        vm.expectRevert(
            abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxWithdraw.selector, user2, DEPOSIT_AMOUNT * 10, 0)
        );
        vm.prank(user2);
        vault.withdraw(DEPOSIT_AMOUNT * 10, user2, user2);

        // Fresh (immature) shares cannot be transferred out either.
        uint256 u2Bal = vault.balanceOf(user2);
        vm.expectRevert(ISapienVault.TransferExceedsUnlockedShares.selector);
        vm.prank(user2);
        vault.transfer(user1, u2Bal);
    }

    /// @dev Resolved bypass: the SAP-3 delegate-deposit path now ages the
    ///      receiver, so an attacker funded via a helper holds only immature
    ///      shares and cannot redeem in the slash window — no capture.
    function test_SAP4_delegateBypassCaptureBlocked() public {
        address attacker = makeAddr("attacker");
        address helper = makeAddr("helper");
        uint256 stake = DEPOSIT_AMOUNT;

        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(stake, user1);
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        vault.lockStake(stake);

        token.mint(helper, stake);
        vm.prank(helper);
        token.approve(address(vault), stake);
        vm.prank(helper);
        vault.deposit(stake, attacker);

        vm.prank(engine);
        vault.slashStake(user1, stake);

        // Attacker's delegate-deposited shares are immature: redeem is capped to 0.
        uint256 attackerShares = vault.balanceOf(attacker);
        assertEq(vault.maxRedeem(attacker), 0, "fresh delegate-deposited shares must be non-redeemable");
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector, attacker, attackerShares, 0)
        );
        vm.prank(attacker);
        vault.redeem(attackerShares, attacker, attacker);
    }
}
