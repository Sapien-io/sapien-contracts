// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {AuditBase} from "./AuditBase.t.sol";
import {ISapienVault} from "../../src/interfaces/ISapienVault.sol";

/// @title SAP-2 — Partial Slashes Are Self-Redistributed Back to the Slashed Holder (Medium, Resolved)
/// @notice Previously `slashStake` burned `previewWithdraw(amount)` shares while
///         no SAPIEN left the vault, so the exchange-rate bump returned part of
///         the penalty to the slashed user's surviving shares. The fix sizes the
///         burn to the *dilution-compensated* amount
///         `x = s_D * S / (S + s_D - b)`, so the user's value drops by exactly
///         `amount` and the recaptured value accrues to the *other* stakers.
///         (Per the protocol's operating model there is never a sole staker.)
contract SAP2_PartialSlashSelfRedistributionTest is AuditBase {
    /// @dev The slashed user loses ~the full slashed amount of value (no longer
    ///      claws it back), and that value transfers to the honest co-staker.
    function test_SAP2_resolved_slashRemovesFullValueFromUser() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        vm.prank(user1);
        vault.lockStake(400e18);

        uint256 u1Before = vault.convertToAssets(vault.balanceOf(user1));
        uint256 u2Before = vault.convertToAssets(vault.balanceOf(user2));

        vm.prank(engine);
        vault.slashStake(user1, 400e18);

        uint256 u1Loss = u1Before - vault.convertToAssets(vault.balanceOf(user1));
        uint256 u2Gain = vault.convertToAssets(vault.balanceOf(user2)) - u2Before;

        // Net damage equals the intended amount (within share-rounding dust) and
        // never exceeds it (rounding is down, preserving solvency).
        assertLe(u1Loss, 400e18, "slash must never over-penalize");
        assertApproxEqAbs(u1Loss, 400e18, 1e16, "slashed user should lose ~the full slash amount");
        // The slashed value accrues to the honest staker, not back to the slashed user.
        assertApproxEqAbs(u2Gain, 400e18, 1e16, "honest staker should receive the slashed value");
    }

    /// @dev On redeem the slashed user recovers only deposit-minus-slash, instead
    ///      of clawing back ~their entire deposit as in the original finding.
    function test_SAP2_resolved_slashedUserCannotClawBackDeposit() public {
        uint256 balBeforeDeposit = token.balanceOf(user1);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(engine);
        vault.slashStake(user1, 400e18);

        // Lock cleared; remaining (unlocked) shares are freely redeemable.
        assertEq(vault.getStakeAccount(user1).lockedAmount, 0, "locked stake should be cleared");

        uint256 redeemable = vault.maxRedeem(user1);
        vm.prank(user1);
        vault.redeem(redeemable, user1, user1);

        uint256 recovered = token.balanceOf(user1) - (balBeforeDeposit - DEPOSIT_AMOUNT);
        assertApproxEqAbs(recovered, DEPOSIT_AMOUNT - 400e18, 1e16, "recovers deposit minus the slash");
        assertLt(recovered, DEPOSIT_AMOUNT * 999 / 1000, "self-redistribution clawback is closed");
    }

    /// @dev The compensated burn destroys strictly more shares than the naive
    ///      `convertToShares(amount)`, which is exactly what neutralises the
    ///      exchange-rate recapture.
    function test_SAP2_resolved_burnExceedsNaiveShareEquivalent() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        vm.prank(user1);
        vault.lockStake(400e18);

        uint256 naiveShares = vault.convertToShares(400e18);
        uint256 sharesBefore = vault.balanceOf(user1);

        vm.prank(engine);
        vault.slashStake(user1, 400e18);

        uint256 burned = sharesBefore - vault.balanceOf(user1);
        assertGt(burned, naiveShares, "dilution-compensated burn must exceed naive convertToShares");
    }

    /// @dev Fuzz across deposit splits and slash sizes (two stakers, never sole):
    ///      the slash never over-penalizes the user, and the honest co-staker's
    ///      value only ever increases (the redistribution flows away from the
    ///      slashed user, not back to them).
    function testFuzz_SAP2_noSelfRedistribution(uint256 d1, uint256 d2, uint256 slashAmt) public {
        d1 = bound(d1, 1e18, 1e24);
        d2 = bound(d2, 1e18, 1e24);

        token.mint(user1, d1);
        token.mint(user2, d2);
        vm.prank(user1);
        vault.deposit(d1, user1);
        vm.prank(user2);
        vault.deposit(d2, user2);

        uint256 u1Value = vault.convertToAssets(vault.balanceOf(user1));
        slashAmt = bound(slashAmt, vault.previewMint(1), u1Value);

        vm.prank(user1);
        vault.lockStake(slashAmt);

        uint256 u1Before = vault.convertToAssets(vault.balanceOf(user1));
        uint256 u2Before = vault.convertToAssets(vault.balanceOf(user2));

        vm.prank(engine);
        vault.slashStake(user1, slashAmt);

        uint256 u1Loss = u1Before - vault.convertToAssets(vault.balanceOf(user1));
        uint256 u2After = vault.convertToAssets(vault.balanceOf(user2));

        assertLe(u1Loss, slashAmt, "slash must never over-penalize the user");
        assertGe(u2After, u2Before, "honest co-staker value must never decrease from a slash");
    }
}
