// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AuditBase} from "./AuditBase.t.sol";
import {StakeAccount} from "../../src/Types.sol";

/// @title SAP-2 — Partial Slashes Are Self-Redistributed Back to the Slashed Holder (Medium, Unresolved)
/// @notice `slashStake` burns shares but no SAPIEN leaves the vault. Because
///         `totalAssets()` is the raw token balance, the slashed value stays in
///         the pool and lifts the exchange rate for all remaining shares —
///         including those still held by the slashed user, who can then redeem
///         close to their original deposit.
contract SAP2_PartialSlashSelfRedistributionTest is AuditBase {
    /// @dev Proves the finding in its starkest form: a sole staker slashed for a
    ///      portion of their stake recovers ~100% of their deposit, because the
    ///      burned shares simply concentrate ownership of the unchanged asset
    ///      pool back onto them.
    function test_SAP2_soleStakerRecoversValueAfterSlash() public {
        uint256 balBeforeDeposit = token.balanceOf(user1);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 sharesBefore = vault.balanceOf(user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(engine);
        vault.slashStake(user1, 400e18);

        // The slash visibly happened: shares were burned and the lock cleared.
        assertLt(vault.balanceOf(user1), sharesBefore, "slash should burn shares");
        assertEq(vault.getStakeAccount(user1).lockedAmount, 0, "locked stake should be cleared");

        // ...yet the user redeems essentially their entire original deposit.
        uint256 redeemable = vault.maxRedeem(user1);
        vm.prank(user1);
        vault.redeem(redeemable, user1, user1);

        uint256 recovered = token.balanceOf(user1) - (balBeforeDeposit - DEPOSIT_AMOUNT);
        assertGe(
            recovered,
            DEPOSIT_AMOUNT * 999 / 1000,
            "Slashed sole staker recovered <99.9% - finding would be mitigated"
        );
    }

    /// @dev With a second honest staker the slashed user still claws back a large
    ///      fraction of the slashed value via the exchange-rate bump (the loss is
    ///      socialized across all remaining holders, including the slashed user).
    function test_SAP2_slashedHolderClawsBackViaExchangeRate() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        vm.prank(user1);
        vault.lockStake(400e18);

        uint256 user1ValueBefore = vault.convertToAssets(vault.balanceOf(user1));

        vm.prank(engine);
        vault.slashStake(user1, 400e18);

        uint256 user1ValueAfter = vault.convertToAssets(vault.balanceOf(user1));
        uint256 actualLoss = user1ValueBefore - user1ValueAfter;

        // A fully-effective 400e18 slash would remove ~400e18 of value from the
        // slashed user. Here the user keeps part of it because they share in the
        // redistribution of their own burned value.
        assertLt(actualLoss, 400e18, "Slashed user absorbed the full penalty - finding would be mitigated");
    }
}
