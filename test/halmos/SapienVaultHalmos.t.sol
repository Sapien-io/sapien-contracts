// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {SapienVaultHalmosBase} from "./SapienVaultHalmosBase.sol";

/// @notice Core ERC-4626 and stake-lock symbolic properties (minDepositAge disabled).
contract SapienVaultHalmosTest is SapienVaultHalmosBase {
    function setUp() public {
        _deployVault();
        vm.prank(ADMIN);
        vault.setMinDepositAge(0);
        _fund(USER, type(uint64).max);
        _fund(USER2, type(uint64).max);
    }

    /// @dev ERC-4626 solvency: vault token balance covers reported totalAssets.
    function check_tokenBalanceCoversTotalAssets(uint256 assets) external {
        _assumeReasonableAssets(assets);

        vm.prank(USER);
        vault.deposit(assets, USER);

        assert(token.balanceOf(address(vault)) >= vault.totalAssets());
    }

    /// @dev Deposited assets increase the receiver's share balance.
    function check_depositIncreasesShares(uint256 assets) external {
        _assumeReasonableAssets(assets);

        uint256 sharesBefore = vault.balanceOf(USER);

        vm.prank(USER);
        vault.deposit(assets, USER);

        assert(vault.balanceOf(USER) > sharesBefore);
    }

    /// @dev With minDepositAge disabled, all shares are immediately mature.
    function check_zeroAgeMakesAllSharesMature(uint256 assets) external {
        _assumeReasonableAssets(assets);

        vm.prank(USER);
        vault.deposit(assets, USER);

        assert(vault.maturedShares(USER) == vault.balanceOf(USER));
        assert(vault.pendingShares(USER) == 0);
    }

    /// @dev Tranche accounting: mature + pending always equals ERC-20 balance.
    function check_trancheSumEqualsBalance(uint256 assets) external {
        _assumeReasonableAssets(assets);

        vm.prank(USER);
        vault.deposit(assets, USER);

        assert(vault.maturedShares(USER) + vault.pendingShares(USER) == vault.balanceOf(USER));
    }

    /// @dev Locked stake never exceeds the user's total asset value.
    function check_lockStakeWithinAssets(uint256 depositAmt, uint256 lockAmt) external {
        _assumeReasonableAssets(depositAmt);
        vm.assume(lockAmt > 0 && lockAmt <= depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);

        vm.prank(USER);
        vault.lockStake(lockAmt);

        assert(vault.getStakeAccount(USER).lockedAmount == lockAmt);
        assert(vault.convertToAssets(vault.balanceOf(USER)) >= lockAmt);
    }

    /// @dev Full withdraw after deposit returns the same asset amount (no age guard).
    function check_depositWithdrawRoundtrip(uint256 assets) external {
        _assumeReasonableAssets(assets);

        uint256 balBefore = token.balanceOf(USER);

        vm.startPrank(USER);
        vault.deposit(assets, USER);
        vault.withdraw(assets, USER, USER);
        vm.stopPrank();

        assert(token.balanceOf(USER) == balBefore);
    }

    /// @dev Transfers move only matured shares; tranche sum preserved on both sides.
    function check_transferPreservesTrancheAccounting(uint256 depositAmt, uint256 transferShares) external {
        _assumeReasonableAssets(depositAmt);
        vm.assume(transferShares > 0);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);

        vm.assume(transferShares <= vault.balanceOf(USER));

        vm.prank(USER);
        vault.transfer(USER2, transferShares);

        assert(vault.maturedShares(USER) + vault.pendingShares(USER) == vault.balanceOf(USER));
        assert(vault.maturedShares(USER2) + vault.pendingShares(USER2) == vault.balanceOf(USER2));
        assert(vault.balanceOf(USER2) == transferShares);
    }

    /// @dev Total supply equals sum of holder balances after transfer.
    function check_transferConservesSupply(uint256 depositAmt, uint256 transferShares) external {
        _assumeReasonableAssets(depositAmt);
        vm.assume(transferShares > 0);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.assume(transferShares <= vault.balanceOf(USER));

        uint256 supplyBefore = vault.totalSupply();

        vm.prank(USER);
        vault.transfer(USER2, transferShares);

        assert(vault.totalSupply() == supplyBefore);
        assert(vault.balanceOf(USER) + vault.balanceOf(USER2) <= supplyBefore);
    }

    /// @dev maxRedeem never exceeds matured shares.
    function check_maxRedeemBoundedByMature(uint256 depositAmt, uint256 lockAmt) external {
        _assumeReasonableAssets(depositAmt);
        vm.assume(lockAmt > 0 && lockAmt <= depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.prank(USER);
        vault.lockStake(lockAmt);

        assert(vault.maxRedeem(USER) <= vault.maturedShares(USER));
    }

    /// @dev maxWithdraw never exceeds maxRedeem converted bound.
    function check_maxWithdrawBoundedByMature(uint256 depositAmt) external {
        _assumeReasonableAssets(depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);

        assert(vault.maxWithdraw(USER) <= vault.convertToAssets(vault.maturedShares(USER)));
        assert(vault.maxRedeem(USER) <= vault.maturedShares(USER));
    }

    /// @dev Redeeming all max shares zeroes balance when nothing locked.
    function check_redeemMaxClearsBalance(uint256 depositAmt) external {
        _assumeReasonableAssets(depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);

        uint256 maxShares = vault.maxRedeem(USER);
        vm.assume(maxShares > 0);

        vm.prank(USER);
        vault.redeem(maxShares, USER, USER);

        assert(vault.balanceOf(USER) == 0);
    }
}
