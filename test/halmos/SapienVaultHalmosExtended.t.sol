// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {SapienVaultHalmosBase} from "./SapienVaultHalmosBase.sol";

/// @notice Additional symbolic properties probing multi-user, redeem, and donation paths.
contract SapienVaultHalmosExtendedTest is SapienVaultHalmosBase {
    function setUp() public {
        _deployVault();
        vm.prank(ADMIN);
        vault.setMinDepositAge(0);
        _fund(USER, 10_000_000e18);
        _fund(USER2, 10_000_000e18);
    }

    /// @dev Sequential locks accumulate in lockedAmount.
    function check_doubleLockAccumulates(uint256 depositAmt, uint256 lock1, uint256 lock2) external {
        _assumeReasonableAssets(depositAmt);
        vm.assume(lock1 > 0 && lock2 > 0);
        vm.assume(lock1 + lock2 <= depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.startPrank(USER);
        vault.lockStake(lock1);
        vault.lockStake(lock2);
        vm.stopPrank();

        assert(vault.getStakeAccount(USER).lockedAmount == lock1 + lock2);
    }

    /// @dev Redeeming partial maxRedeem leaves locked stake intact (concrete).
    function check_redeemRespectsLock_concrete() external {
        vm.prank(USER);
        vault.deposit(1000e18, USER);
        vm.prank(USER);
        vault.lockStake(400e18);
        vm.prank(USER);
        vault.redeem(100e18, USER, USER);
        assert(vault.getStakeAccount(USER).lockedAmount == 400e18);
    }

    /// @dev Mint + redeem roundtrip returns assets (concrete; symbolic times out).
    function check_mintRedeemRoundtrip_concrete() external {
        uint256 assets = 100e18;
        uint256 shares = vault.previewDeposit(assets);
        uint256 balBefore = token.balanceOf(USER);

        vm.startPrank(USER);
        vault.mint(shares, USER);
        vault.redeem(shares, USER, USER);
        vm.stopPrank();

        assert(token.balanceOf(USER) == balBefore);
    }

    /// @dev assetsOf always covers locked amount after lock.
    function check_assetsOfCoversLocked(uint256 depositAmt, uint256 lockAmt) external {
        _assumeReasonableAssets(depositAmt);
        vm.assume(lockAmt > 0 && lockAmt <= depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.prank(USER);
        vault.lockStake(lockAmt);

        assert(vault.assetsOf(USER) >= lockAmt);
    }

    /// @dev Donation from a third party increases totalAssets without minting shares.
    function check_donationIncreasesTotalAssets(uint256 depositAmt, uint256 donation) external {
        _assumeReasonableAssets(depositAmt);
        _assumeReasonableAssets(donation);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);

        uint256 totalBefore = vault.totalAssets();
        uint256 supplyBefore = vault.totalSupply();

        vm.prank(USER2);
        token.transfer(address(vault), donation);

        assert(vault.totalAssets() == totalBefore + donation);
        assert(vault.totalSupply() == supplyBefore);
    }

    /// @dev SAP-2 with prior donation — concrete (high exchange-rate edge case).
    function check_slashNetDamageWithDonation_concrete() external {
        vm.prank(USER);
        vault.deposit(1000e18, USER);
        vm.prank(USER2);
        vault.deposit(1000e18, USER2);

        vm.prank(USER2);
        token.transfer(address(vault), 500e18);

        vm.prank(USER);
        vault.lockStake(400e18);

        uint256 valueBefore = vault.convertToAssets(vault.balanceOf(USER));
        vm.prank(ENGINE);
        vault.slashStake(USER, 400e18);
        uint256 loss = valueBefore - vault.convertToAssets(vault.balanceOf(USER));

        assert(loss <= 400e18);
    }

    /// @dev Slashing one staker does not reduce the other staker's share balance.
    function check_slashPreservesOtherShareBalance(uint256 d1, uint256 d2, uint256 slashAmt) external {
        _assumeReasonableAssets(d1);
        _assumeReasonableAssets(d2);
        vm.assume(slashAmt > 0 && slashAmt <= d1);

        vm.prank(USER);
        vault.deposit(d1, USER);
        vm.prank(USER2);
        vault.deposit(d2, USER2);

        uint256 user2SharesBefore = vault.balanceOf(USER2);

        vm.prank(USER);
        vault.lockStake(slashAmt);
        vm.prank(ENGINE);
        vault.slashStake(USER, slashAmt);

        assert(vault.balanceOf(USER2) == user2SharesBefore);
    }

    /// @dev Unlock then re-lock preserves accounting.
    function check_unlockRelockRoundtrip(uint256 depositAmt, uint256 lockAmt, uint256 unlockAmt) external {
        _assumeReasonableAssets(depositAmt);
        vm.assume(lockAmt > 0 && lockAmt <= depositAmt);
        vm.assume(unlockAmt > 0 && unlockAmt <= lockAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.prank(USER);
        vault.lockStake(lockAmt);

        vm.prank(ENGINE);
        vault.unlockStake(USER, unlockAmt);

        vm.prank(USER);
        vault.lockStake(unlockAmt);

        assert(vault.getStakeAccount(USER).lockedAmount == lockAmt);
    }
}
