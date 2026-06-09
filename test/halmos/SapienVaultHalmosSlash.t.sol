// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {SapienVaultHalmosBase} from "./SapienVaultHalmosBase.sol";

/// @notice Symbolic properties for lock/unlock/slash and exchange-rate behaviour.
/// @dev SAP-2 net-damage / dilution-compensation properties that require heavy
///      mulDiv reasoning remain in forge fuzz tests (`testFuzz_slashStake_*`).
/// @custom:halmos --solver-timeout-assertion 0 --loop 4
contract SapienVaultHalmosSlashTest is SapienVaultHalmosBase {
    function setUp() public {
        _deployVault();
        vm.prank(ADMIN);
        vault.setMinDepositAge(0);
        _fund(USER, 10_000e18);
        _fund(USER2, 10_000e18);
    }

    function _minSlashAssets() internal view returns (uint256) {
        return vault.previewMint(1);
    }

    /// @dev Engine unlock reduces locked amount exactly.
    function check_unlockReducesLocked(uint256 depositAmt, uint256 lockAmt, uint256 unlockAmt) external {
        _assumeReasonableAssets(depositAmt);
        vm.assume(lockAmt > 0 && lockAmt <= depositAmt);
        vm.assume(unlockAmt > 0 && unlockAmt <= lockAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.prank(USER);
        vault.lockStake(lockAmt);

        vm.prank(ENGINE);
        vault.unlockStake(USER, unlockAmt);

        assert(vault.getStakeAccount(USER).lockedAmount == lockAmt - unlockAmt);
    }

    /// @dev Locked stake reduces maxRedeem below full balance.
    function check_lockReducesMaxRedeem(uint256 depositAmt, uint256 lockAmt) external {
        _assumeReasonableAssets(depositAmt);
        vm.assume(lockAmt > 0 && lockAmt < depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);

        uint256 maxBefore = vault.maxRedeem(USER);

        vm.prank(USER);
        vault.lockStake(lockAmt);

        assert(vault.maxRedeem(USER) <= maxBefore);
        assert(vault.maxRedeem(USER) <= vault.maturedShares(USER));
    }

    /// @dev Full slash clears locked amount and burns shares.
    function check_fullSlashClearsLock(uint256 depositAmt, uint256 slashAmt) external {
        _assumeReasonableAssets(depositAmt);
        uint256 minSlash = _minSlashAssets();
        vm.assume(depositAmt >= minSlash);
        vm.assume(slashAmt >= minSlash && slashAmt <= depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.prank(USER);
        vault.lockStake(slashAmt);

        uint256 sharesBefore = vault.balanceOf(USER);

        vm.prank(ENGINE);
        vault.slashStake(USER, slashAmt);

        assert(vault.getStakeAccount(USER).lockedAmount == 0);
        assert(vault.balanceOf(USER) < sharesBefore);
    }

    /// @dev Partial slash reduces locked amount exactly.
    function check_partialSlashReducesLock(uint256 depositAmt, uint256 lockAmt, uint256 slashAmt) external {
        _assumeReasonableAssets(depositAmt);
        uint256 minSlash = _minSlashAssets();
        vm.assume(depositAmt >= minSlash);
        vm.assume(lockAmt >= minSlash && lockAmt <= depositAmt);
        vm.assume(slashAmt >= minSlash && slashAmt < lockAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.prank(USER);
        vault.lockStake(lockAmt);

        vm.prank(ENGINE);
        vault.slashStake(USER, slashAmt);

        assert(vault.getStakeAccount(USER).lockedAmount == lockAmt - slashAmt);
    }

    /// @dev Slashing burns shares but does not remove underlying assets from the vault.
    function check_slashPreservesTotalAssets(uint256 d1, uint256 d2, uint256 slashAmt) external {
        _assumeReasonableAssets(d1);
        _assumeReasonableAssets(d2);
        uint256 minSlash = _minSlashAssets();
        vm.assume(d1 >= minSlash);
        vm.assume(slashAmt >= minSlash && slashAmt <= d1);

        vm.prank(USER);
        vault.deposit(d1, USER);
        vm.prank(USER2);
        vault.deposit(d2, USER2);

        uint256 totalBefore = vault.totalAssets();

        vm.prank(USER);
        vault.lockStake(slashAmt);
        vm.prank(ENGINE);
        vault.slashStake(USER, slashAmt);

        assert(vault.totalAssets() == totalBefore);
        assert(token.balanceOf(address(vault)) >= vault.totalAssets());
    }

    /// @dev SAP-2 net damage — concrete grid (fully symbolic deposit/slash times out).
    function check_slashNeverOverPenalizes_concrete() external {
        _assertSlashNetDamageBounded(1000e18, 400e18);
    }

    function check_slashNeverOverPenalizes_concrete_small() external {
        _assertSlashNetDamageBounded(10e18, 3e18);
    }

    function check_slashNeverOverPenalizes_concrete_full() external {
        _assertSlashNetDamageBounded(1000e18, 1000e18);
    }

    function _assertSlashNetDamageBounded(uint256 depositAmt, uint256 slashAmt) internal {
        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.prank(USER);
        vault.lockStake(slashAmt);

        uint256 valueBefore = vault.convertToAssets(vault.balanceOf(USER));
        vm.prank(ENGINE);
        vault.slashStake(USER, slashAmt);
        uint256 loss = valueBefore - vault.convertToAssets(vault.balanceOf(USER));

        assert(loss <= slashAmt);
    }

    /// @dev Slashing increases other stakers' asset value per share (concrete).
    function check_slashIncreasesOtherStakerValue_concrete() external {
        vm.prank(USER);
        vault.deposit(1000e18, USER);
        vm.prank(USER2);
        vault.deposit(1000e18, USER2);

        uint256 user2AssetsBefore = vault.convertToAssets(vault.balanceOf(USER2));

        vm.prank(USER);
        vault.lockStake(500e18);
        vm.prank(ENGINE);
        vault.slashStake(USER, 500e18);

        assert(vault.convertToAssets(vault.balanceOf(USER2)) > user2AssetsBefore);
    }

    /// @dev Zero-share slash is unreachable above minimum slash assets.
    function check_slashAlwaysBurnsShares(uint256 depositAmt, uint256 slashAmt) external {
        _assumeReasonableAssets(depositAmt);
        uint256 minSlash = _minSlashAssets();
        vm.assume(depositAmt >= minSlash);
        vm.assume(slashAmt >= minSlash && slashAmt <= depositAmt);

        vm.prank(USER);
        vault.deposit(depositAmt, USER);
        vm.prank(USER);
        vault.lockStake(slashAmt);

        uint256 sharesBefore = vault.balanceOf(USER);
        vm.prank(ENGINE);
        vault.slashStake(USER, slashAmt);

        assert(vault.balanceOf(USER) < sharesBefore);
    }
}
