// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {SapienVaultHalmosBase} from "./SapienVaultHalmosBase.sol";

/// @notice Reproducers for Halmos limitation investigation (not in halmos.toml match set).
/// @dev See investigation notes in the Halmos formal verification PR / chat.
contract HalmosInvestigationTest is SapienVaultHalmosBase {
    uint256 internal constant MIN_AGE = 1 days;

    function setUp() public {
        _deployVault();
        vm.startPrank(ADMIN);
        vault.grantRole(vault.ENGINE_ROLE(), ENGINE);
        vault.setMinDepositAge(0);
        vm.stopPrank();
        _fund(USER, 10_000e18);
        _fund(USER2, 10_000e18);
    }

    function _minSlashAssets() internal view returns (uint256) {
        return vault.previewMint(1);
    }

    // Symbolic SAP-2: times out (nonlinear mulDiv through convertToAssets × slash).
    function check_slashNeverOverPenalizes_symbolic(uint256 depositAmt, uint256 slashAmt) external {
        _assumeReasonableAssets(depositAmt);
        uint256 minSlash = _minSlashAssets();
        vm.assume(depositAmt >= minSlash);
        vm.assume(slashAmt >= minSlash && slashAmt <= depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.prank(USER);
        vault.lockStake(slashAmt);

        uint256 valueBefore = vault.convertToAssets(vault.balanceOf(USER));
        vm.prank(ENGINE);
        vault.slashStake(USER, slashAmt);
        assert(valueBefore - vault.convertToAssets(vault.balanceOf(USER)) <= slashAmt);
    }

    // Symbolic slash burn >= naive (pure mulDiv): times out even without ERC-4626.
    function check_slashBurnGteNaiveShares_symbolic(uint256 naiveShares, uint256 userBalance, uint256 totalSupply)
        external
        pure
    {
        vm.assume(naiveShares > 0 && naiveShares <= 1e24);
        vm.assume(userBalance >= naiveShares && userBalance <= 1e24);
        vm.assume(totalSupply >= userBalance && totalSupply <= 1e24);

        uint256 s = totalSupply + 1;
        uint256 burn = Math.mulDiv(naiveShares, s, s + naiveShares - userBalance, Math.Rounding.Floor);
        if (burn > userBalance) burn = userBalance;
        assert(burn >= naiveShares);
    }

    // Symbolic multi-cohort: times out (two symbolic ERC-4626 mint paths + tranche settle).
    function check_newDepositAddsPendingCohort_symbolic(uint256 first, uint256 second) external {
        vm.prank(ADMIN);
        vault.setMinDepositAge(MIN_AGE);
        _assumeReasonableAssets(first);
        _assumeReasonableAssets(second);

        vm.prank(USER);
        vault.deposit(first, USER);
        vm.warp(block.timestamp + MIN_AGE + 1);
        vm.prank(USER);
        vault.deposit(second, USER);

        assert(vault.pendingShares(USER) > 0);
        assert(vault.maturedShares(USER) > 0);
    }

    // Symbolic redeem-with-lock (3 vars): times out.
    function check_redeemRespectsLock_symbolic(uint256 depositAmt, uint256 lockAmt, uint256 redeemShares) external {
        vm.prank(ADMIN);
        vault.setMinDepositAge(0);
        _assumeReasonableAssets(depositAmt);
        vm.assume(lockAmt > 0 && lockAmt < depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.prank(USER);
        vault.lockStake(lockAmt);

        uint256 maxRedeem = vault.maxRedeem(USER);
        vm.assume(redeemShares > 0 && redeemShares <= maxRedeem);

        vm.prank(USER);
        vault.redeem(redeemShares, USER, USER);

        assert(vault.getStakeAccount(USER).lockedAmount == lockAmt);
    }

    // Symbolic mint/redeem roundtrip: times out.
    function check_mintRedeemRoundtrip_symbolic(uint256 assets) external {
        vm.prank(ADMIN);
        vault.setMinDepositAge(0);
        _assumeReasonableAssets(assets);
        uint256 shares = vault.previewDeposit(assets);
        vm.assume(shares > 0);
        vm.startPrank(USER);
        vault.mint(shares, USER);
        vault.redeem(shares, USER, USER);
        vm.stopPrank();
        assert(vault.balanceOf(USER) == 0);
    }
}
