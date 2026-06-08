// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AuditBase} from "./AuditBase.t.sol";
import {ISapienVault} from "../../src/interfaces/ISapienVault.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @dev Minimal "zapper"-style integrator: deposits on its own behalf and then
///      forwards the resulting shares within the same transaction, like an
///      auto-compounder, router, or multi-step zap would.
contract Zapper {
    SapienVault internal immutable VAULT;
    IERC20 internal immutable TOKEN;

    constructor(SapienVault vault_, IERC20 token_) {
        VAULT = vault_;
        TOKEN = token_;
    }

    function depositAndForward(uint256 amount, address to) external {
        TOKEN.transferFrom(msg.sender, address(this), amount);
        TOKEN.approve(address(VAULT), amount);
        VAULT.deposit(amount, address(this));
        VAULT.transfer(to, VAULT.balanceOf(address(this)));
    }
}

/// @title SAP-7 — MEV Guard May Break Composability (Informational, Documented)
/// @notice The cooldown still blocks immediate forwarding of just-deposited
///         shares: an integrator that deposits then moves the SAME fresh shares
///         in one transaction reverts when `minDepositAge > 0` (now with
///         `TransferExceedsUnlockedShares` rather than `DepositTooRecent`). The
///         tranche model does improve the receiving side — an integrator that
///         is sent MATURE shares can act on them immediately (age travels) —
///         but same-tx deposit-and-forward remains a documented limitation.
contract SAP7_MevGuardBreaksComposabilityTest is AuditBase {
    Zapper internal zapper;

    function setUp() public override {
        super.setUp();
        zapper = new Zapper(vault, IERC20(address(token)));
    }

    /// @dev Documented limitation: a deposit-then-forward zap still reverts under
    ///      the cooldown because the zapper's freshly-minted shares are immature
    ///      and cannot be transferred out in the same transaction.
    function test_SAP7_zapDepositThenForwardRevertsUnderCooldown() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        token.approve(address(zapper), DEPOSIT_AMOUNT);

        vm.expectRevert(ISapienVault.TransferExceedsUnlockedShares.selector);
        vm.prank(user1);
        zapper.depositAndForward(DEPOSIT_AMOUNT, user2);
    }

    /// @dev Control: with the guard disabled (its uninitialized default, see
    ///      SAP-5) the same composable flow works, confirming the cooldown is
    ///      the cause of the breakage.
    function test_SAP7_zapWorksWhenGuardDisabled() public {
        vm.prank(user1);
        token.approve(address(zapper), DEPOSIT_AMOUNT);

        vm.prank(user1);
        zapper.depositAndForward(DEPOSIT_AMOUNT, user2);

        assertGt(vault.balanceOf(user2), 0, "shares should have been forwarded to the end user");
    }
}
