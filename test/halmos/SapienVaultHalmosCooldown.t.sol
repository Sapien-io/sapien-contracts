// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SapienVaultHalmosBase} from "./SapienVaultHalmosBase.sol";

/// @notice Symbolic properties for the minDepositAge / tranche cooldown model.
contract SapienVaultHalmosCooldownTest is SapienVaultHalmosBase {
    uint256 internal constant MIN_AGE = 1 days;

    function setUp() public {
        _deployVault();
        vm.prank(ADMIN);
        vault.setMinDepositAge(MIN_AGE);
        _fund(USER, 10_000e18);
    }

    /// @dev Fresh deposits are pending until the cooldown elapses.
    function check_freshDepositIsPending(uint256 assets) external {
        _assumeReasonableAssets(assets);

        vm.prank(USER);
        vault.deposit(assets, USER);

        assert(vault.pendingShares(USER) == vault.balanceOf(USER));
        assert(vault.maturedShares(USER) == 0);
    }

    /// @dev Immature shares cannot be redeemed.
    function check_immatureNotRedeemable(uint256 assets, uint256 elapsed) external {
        _assumeReasonableAssets(assets);
        vm.assume(elapsed < MIN_AGE);

        vm.prank(USER);
        vault.deposit(assets, USER);

        vm.warp(block.timestamp + elapsed);

        assert(vault.maxRedeem(USER) == 0);
        assert(vault.maxWithdraw(USER) == 0);
    }

    /// @dev After the cooldown, all shares mature and become redeemable.
    function check_matureAfterCooldown(uint256 assets, uint256 extra) external {
        _assumeReasonableAssets(assets);
        vm.assume(extra <= 30 days);

        vm.prank(USER);
        vault.deposit(assets, USER);

        vm.warp(block.timestamp + MIN_AGE + extra);

        assert(vault.maturedShares(USER) == vault.balanceOf(USER));
        assert(vault.pendingShares(USER) == 0);
        assert(vault.maxRedeem(USER) == vault.balanceOf(USER));
    }

    /// @dev Tranche accounting holds even while shares are immature.
    function check_trancheSumWhileImmature(uint256 assets, uint256 elapsed) external {
        _assumeReasonableAssets(assets);
        vm.assume(elapsed <= MIN_AGE);

        vm.prank(USER);
        vault.deposit(assets, USER);

        vm.warp(block.timestamp + elapsed);

        assert(vault.maturedShares(USER) + vault.pendingShares(USER) == vault.balanceOf(USER));
        assert(vault.maxRedeem(USER) <= vault.maturedShares(USER));
    }

    /// @dev Delegate deposits still age on the receiver (SAP-3).
    function check_delegateDepositAgesReceiver(uint256 assets, uint256 elapsed) external {
        _assumeReasonableAssets(assets);
        vm.assume(elapsed < MIN_AGE);
        _fund(USER2, type(uint64).max);

        vm.prank(USER2);
        vault.deposit(assets, USER);

        vm.warp(block.timestamp + elapsed);

        assert(vault.balanceOf(USER) > 0);
        assert(vault.balanceOf(USER2) == 0);
        assert(vault.maxRedeem(USER) == 0);
    }

    /// @dev Multi-cohort — concrete grid (symbolic first/second amounts timeout).
    function check_newDepositAddsPendingCohort_concrete() external {
        _assertMultiCohort(1e18, 1e18);
    }

    function check_newDepositAddsPendingCohort_concrete_largeSmall() external {
        _assertMultiCohort(100e18, 1e18);
    }

    function check_newDepositAddsPendingCohort_concrete_smallLarge() external {
        _assertMultiCohort(1e18, 100e18);
    }

    function _assertMultiCohort(uint256 first, uint256 second) internal {
        vm.prank(USER);
        vault.deposit(first, USER);
        vm.warp(block.timestamp + MIN_AGE + 1);
        vm.prank(USER);
        vault.deposit(second, USER);

        assert(vault.maturedShares(USER) + vault.pendingShares(USER) == vault.balanceOf(USER));
        assert(vault.pendingShares(USER) > 0);
        assert(vault.maturedShares(USER) > 0);
    }

    /// @dev First cohort stays mature after a second pending deposit lands.
    function check_firstCohortStaysMatureAfterSecondDeposit() external {
        vm.prank(USER);
        vault.deposit(50e18, USER);
        vm.warp(block.timestamp + MIN_AGE + 1);
        uint256 matureBefore = vault.maturedShares(USER);

        vm.prank(USER);
        vault.deposit(50e18, USER);

        assert(vault.maturedShares(USER) >= matureBefore);
        assert(vault.pendingShares(USER) > 0);
    }

    /// @dev While fully immature, no shares are transferable (max mature avail is 0).
    function check_noTransferableSharesWhileFullyImmature(uint256 assets) external {
        _assumeReasonableAssets(assets);

        vm.prank(USER);
        vault.deposit(assets, USER);

        assert(vault.maturedShares(USER) == 0);
        assert(vault.maxRedeem(USER) == 0);
    }

    /// @dev Warping past cooldown zeroes pending without changing total balance.
    function check_warpMaturesAllPending(uint256 assets, uint256 extra) external {
        _assumeReasonableAssets(assets);
        vm.assume(extra <= 7 days);

        vm.prank(USER);
        vault.deposit(assets, USER);

        uint256 bal = vault.balanceOf(USER);
        vm.warp(block.timestamp + MIN_AGE + extra);

        assert(vault.balanceOf(USER) == bal);
        assert(vault.pendingShares(USER) == 0);
        assert(vault.maturedShares(USER) == bal);
    }
}
