// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {StakeAccount} from "src/Types.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title MaxWithdrawRoundingTest
/// @notice Tests that maxWithdraw is conservative enough for locked accounts
///         even under exchange-rate shifts caused by direct asset donations.
contract MaxWithdrawRoundingTest is Test {
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public engine = makeAddr("engine");
    address public user = makeAddr("user");

    function setUp() public {
        token = new MockERC20("Sapien Token", "SPN");

        SapienVault vaultImpl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), initData)));

        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), engine);
        vm.stopPrank();

        token.mint(user, 100e18);
        vm.prank(user);
        token.approve(address(vault), type(uint256).max);
    }

    /// @notice Reproduces the exact scenario from the issue:
    ///   1. Deposit 1 wei → mints 1000 shares (decimalsOffset = 3).
    ///   2. Donate 4 wei directly to vault (raises exchange rate).
    ///   3. Lock 1 wei via lockContributor.
    ///   4. maxWithdraw must be safe: withdrawing it must not undercollateralise locks.
    function test_maxWithdraw_safeAfterDonation_weiScenario() public {
        vm.prank(user);
        vault.deposit(1, user);

        uint256 sharesAfterDeposit = vault.balanceOf(user);
        assertEq(sharesAfterDeposit, 1000, "1 wei deposit should mint 1000 shares");

        token.mint(address(vault), 4);

        vm.prank(engine);
        vault.lockContributor(user, 1);

        uint256 maxW = vault.maxWithdraw(user);

        if (maxW > 0) {
            vm.prank(user);
            vault.withdraw(maxW, user, user);
        }

        uint256 remainingShares = vault.balanceOf(user);
        uint256 remainingAssets = vault.convertToAssets(remainingShares);
        StakeAccount memory acct = vault.getStakeAccount(user);
        assertGe(remainingAssets, acct.contributorLock, "locked amount must remain backed after maxWithdraw");
    }

    /// @notice Same test but exercising maxRedeem.
    function test_maxRedeem_safeAfterDonation_weiScenario() public {
        vm.prank(user);
        vault.deposit(1, user);

        token.mint(address(vault), 4);

        vm.prank(engine);
        vault.lockContributor(user, 1);

        uint256 maxR = vault.maxRedeem(user);

        if (maxR > 0) {
            vm.prank(user);
            vault.redeem(maxR, user, user);
        }

        uint256 remainingShares = vault.balanceOf(user);
        uint256 remainingAssets = vault.convertToAssets(remainingShares);
        StakeAccount memory acct = vault.getStakeAccount(user);
        assertGe(remainingAssets, acct.contributorLock, "locked amount must remain backed after maxRedeem");
    }

    /// @notice Withdrawing maxWithdraw should never revert due to locked shares.
    function test_maxWithdraw_doesNotRevert() public {
        vm.prank(user);
        vault.deposit(10e18, user);

        token.mint(address(vault), 3e18);

        vm.prank(engine);
        vault.lockContributor(user, 5e18);

        uint256 maxW = vault.maxWithdraw(user);
        assertGt(maxW, 0, "should have some withdrawable amount");

        vm.prank(user);
        vault.withdraw(maxW, user, user);

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user));
        StakeAccount memory acct = vault.getStakeAccount(user);
        assertGe(remainingAssets, acct.contributorLock, "locked amount must remain backed");
    }

    /// @notice After depositing with no locks, maxWithdraw should equal full balance.
    function test_maxWithdraw_noLocks_fullBalance() public {
        vm.prank(user);
        vault.deposit(10e18, user);

        uint256 maxW = vault.maxWithdraw(user);
        assertEq(maxW, 10e18, "with no locks, maxWithdraw should equal deposited amount");
    }

    /// @notice When everything is locked, maxWithdraw should be 0.
    function test_maxWithdraw_fullyLocked_isZero() public {
        vm.prank(user);
        vault.deposit(10e18, user);

        vm.prank(engine);
        vault.lockContributor(user, 10e18);

        uint256 maxW = vault.maxWithdraw(user);
        assertEq(maxW, 0, "fully locked account should have maxWithdraw == 0");
    }

    /// @notice Fuzz test: for any deposit and donation, withdrawing maxWithdraw
    ///         must never leave locked assets undercollateralised.
    function testFuzz_maxWithdraw_preservesLockedInvariant(
        uint256 depositAmount,
        uint256 donationAmount,
        uint256 lockFraction
    ) public {
        depositAmount = bound(depositAmount, 1, 10e18);
        donationAmount = bound(donationAmount, 0, 10e18);
        lockFraction = bound(lockFraction, 1, 1e18);

        vm.prank(user);
        vault.deposit(depositAmount, user);

        if (donationAmount > 0) {
            token.mint(address(vault), donationAmount);
        }

        uint256 avail = vault.availableBalance(user);
        uint256 lockAmount = Math.mulDiv(avail, lockFraction, 1e18);
        if (lockAmount == 0) return;

        vm.prank(engine);
        vault.lockContributor(user, lockAmount);

        uint256 maxW = vault.maxWithdraw(user);

        if (maxW > 0) {
            vm.prank(user);
            vault.withdraw(maxW, user, user);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user));
        StakeAccount memory acct = vault.getStakeAccount(user);
        assertGe(remainingAssets, acct.contributorLock, "invariant: locked amount must be backed");
    }

    /// @notice Fuzz test: for any deposit and donation, redeeming maxRedeem
    ///         must never leave locked assets undercollateralised.
    function testFuzz_maxRedeem_preservesLockedInvariant(
        uint256 depositAmount,
        uint256 donationAmount,
        uint256 lockFraction
    ) public {
        depositAmount = bound(depositAmount, 1, 10e18);
        donationAmount = bound(donationAmount, 0, 10e18);
        lockFraction = bound(lockFraction, 1, 1e18);

        vm.prank(user);
        vault.deposit(depositAmount, user);

        if (donationAmount > 0) {
            token.mint(address(vault), donationAmount);
        }

        uint256 avail = vault.availableBalance(user);
        uint256 lockAmount = Math.mulDiv(avail, lockFraction, 1e18);
        if (lockAmount == 0) return;

        vm.prank(engine);
        vault.lockContributor(user, lockAmount);

        uint256 maxR = vault.maxRedeem(user);

        if (maxR > 0) {
            vm.prank(user);
            vault.redeem(maxR, user, user);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user));
        StakeAccount memory acct = vault.getStakeAccount(user);
        assertGe(remainingAssets, acct.contributorLock, "invariant: locked amount must be backed");
    }

    /// @notice Test with validator capacity lock type to cover all lock categories.
    function test_maxWithdraw_validatorCapacityLock() public {
        vm.prank(user);
        vault.deposit(10e18, user);

        token.mint(address(vault), 5e18);

        vm.prank(engine);
        vault.lockValidatorCapacity(user, 3e18);

        uint256 maxW = vault.maxWithdraw(user);

        if (maxW > 0) {
            vm.prank(user);
            vault.withdraw(maxW, user, user);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user));
        StakeAccount memory acct = vault.getStakeAccount(user);
        uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
        assertGe(remainingAssets, totalLocked, "all lock types must remain backed");
    }

    /// @notice Test with mixed lock types (contributor + validator + inFlight).
    function test_maxWithdraw_mixedLockTypes() public {
        vm.prank(user);
        vault.deposit(30e18, user);

        token.mint(address(vault), 7e18);

        vm.startPrank(engine);
        vault.lockContributor(user, 5e18);
        vault.lockValidatorCapacity(user, 8e18);
        vault.commitStake(user, 3e18);
        vm.stopPrank();

        uint256 maxW = vault.maxWithdraw(user);

        if (maxW > 0) {
            vm.prank(user);
            vault.withdraw(maxW, user, user);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user));
        StakeAccount memory acct = vault.getStakeAccount(user);
        uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
        assertGe(remainingAssets, totalLocked, "mixed locks must all remain backed");
    }

    /// @notice Verify the ERC-4626 maxWithdraw spec: withdraw(maxWithdraw) must succeed.
    function test_maxWithdraw_isWithdrawable() public {
        vm.prank(user);
        vault.deposit(5e18, user);

        token.mint(address(vault), 2e18);

        vm.prank(engine);
        vault.lockContributor(user, 2e18);

        uint256 maxW = vault.maxWithdraw(user);

        vm.prank(user);
        vault.withdraw(maxW, user, user);

        assertEq(token.balanceOf(user), 100e18 - 5e18 + maxW, "user should receive maxWithdraw assets");
    }

    /// @notice Verify the ERC-4626 maxRedeem spec: redeem(maxRedeem) must succeed.
    function test_maxRedeem_isRedeemable() public {
        vm.prank(user);
        vault.deposit(5e18, user);

        token.mint(address(vault), 2e18);

        vm.prank(engine);
        vault.lockContributor(user, 2e18);

        uint256 maxR = vault.maxRedeem(user);

        vm.prank(user);
        vault.redeem(maxR, user, user);
    }
}
