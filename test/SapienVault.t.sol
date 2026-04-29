// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {
    ERC4626Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {ISapienVault} from "../src/interfaces/ISapienVault.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {StakeAccount} from "../src/Types.sol";

contract SapienVaultTest is Test {
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public engine = makeAddr("engine");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant DEPOSIT_AMOUNT = 1000e18;

    bytes32 internal ENGINE_ROLE;
    bytes32 internal ADMIN_ROLE;

    function setUp() public {
        token = new MockERC20("Sapien Token", "SAPIEN");

        SapienVault vaultImpl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), initData)));

        ENGINE_ROLE = vault.ENGINE_ROLE();
        ADMIN_ROLE = vault.DEFAULT_ADMIN_ROLE();

        vm.startPrank(admin);
        vault.grantRole(ENGINE_ROLE, engine);
        vm.stopPrank();

        token.mint(user1, DEPOSIT_AMOUNT * 10);
        token.mint(user2, DEPOSIT_AMOUNT * 10);

        vm.prank(user1);
        token.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        token.approve(address(vault), type(uint256).max);
    }

    // ── Deposit & Withdraw ─────────────────────────────────────────

    function test_deposit() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        assertGt(vault.balanceOf(user1), 0);
        assertEq(vault.getUserStakeBalance(user1), DEPOSIT_AMOUNT);
    }

    function test_withdraw() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 balBefore = token.balanceOf(user1);
        vm.prank(user1);
        vault.withdraw(DEPOSIT_AMOUNT, user1, user1);
        uint256 balAfter = token.balanceOf(user1);

        assertEq(balAfter - balBefore, DEPOSIT_AMOUNT);
    }

    // ── Lock Stake ─────────────────────────────────────────────────

    function test_lockStake() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, 400e18);
        assertEq(vault.availableBalance(user1), DEPOSIT_AMOUNT - 400e18);
    }

    function test_lockStake_revertsInsufficientBalance() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.expectRevert(
            abi.encodeWithSelector(
                ISapienVault.InsufficientAvailableBalance.selector, DEPOSIT_AMOUNT + 1, DEPOSIT_AMOUNT
            )
        );
        vm.prank(user1);
        vault.lockStake(DEPOSIT_AMOUNT + 1);
    }

    function test_lockStake_revertsZeroAmount() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vm.prank(user1);
        vault.lockStake(0);
    }

    function test_lockStake_respectsMinDepositAge() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.warp(block.timestamp + 1 days);

        vm.prank(user1);
        vault.lockStake(400e18);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, 400e18);
    }

    function test_lockStake_revertsForFreshTransferWhenMinDepositAgeSet() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        skip(1 days);

        uint256 sharesToTransfer = vault.balanceOf(user1) / 2;
        uint256 transferredAssets = vault.convertToAssets(sharesToTransfer);

        vm.prank(user1);
        vault.transfer(user2, sharesToTransfer);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user2);
        vault.lockStake(transferredAssets);

        skip(1 days);

        vm.prank(user2);
        vault.lockStake(transferredAssets);

        StakeAccount memory acct = vault.getStakeAccount(user2);
        assertEq(acct.lockedAmount, transferredAssets);
    }

    function test_lockStake_calledByOwnerNotEngine() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, 400e18);
    }

    // ── Unlock Stake ───────────────────────────────────────────────

    function test_unlockStake() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(engine);
        vault.unlockStake(user1, 150e18);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, 250e18);
    }

    function test_unlockStake_revertsInsufficientLock() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientLockedAmount.selector, 500e18, 400e18));
        vm.prank(engine);
        vault.unlockStake(user1, 500e18);
    }

    function test_unlockStake_onlyEngine() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, ENGINE_ROLE)
        );
        vm.prank(user1);
        vault.unlockStake(user1, 150e18);
    }

    function test_unlockStake_revertsZeroAmount() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vm.prank(engine);
        vault.unlockStake(user1, 0);
    }

    // ── Slash Stake ────────────────────────────────────────────────

    function test_slashStake() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 sharesBefore = vault.balanceOf(user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(engine);
        vault.slashStake(user1, 100e18);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertLt(sharesAfter, sharesBefore);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, 300e18);
    }

    function test_slashStake_revertsInsufficientLock() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientLockedAmount.selector, 500e18, 400e18));
        vm.prank(engine);
        vault.slashStake(user1, 500e18);
    }

    // ── Withdrawal Guard ───────────────────────────────────────────

    function test_cannotWithdrawLockedFunds() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(800e18);

        uint256 maxW = vault.maxRedeem(user1);
        uint256 maxAssets = vault.convertToAssets(maxW);
        assertLe(maxAssets, DEPOSIT_AMOUNT - 800e18);
    }

    // ── Access Control ─────────────────────────────────────────────

    function test_onlyEngineCanUnlockStake() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, ENGINE_ROLE)
        );
        vm.prank(user1);
        vault.unlockStake(user1, 200e18);
    }

    function test_onlyEngineCanSlashStake() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, ENGINE_ROLE)
        );
        vm.prank(user1);
        vault.slashStake(user1, 100e18);
    }

    // ── Decimals Offset ────────────────────────────────────────────

    function test_decimalsOffset() public view {
        assertEq(vault.decimals(), 18 + 3);
    }

    // ── Pause ──────────────────────────────────────────────────────

    function test_adminCanPause() public {
        vm.prank(admin);
        vault.pause();
        assertTrue(vault.paused());

        vm.prank(admin);
        vault.unpause();
        assertFalse(vault.paused());
    }

    function test_nonAdminCannotPause() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, ADMIN_ROLE)
        );
        vm.prank(user1);
        vault.pause();
    }

    function test_transferRevertsWhenPaused() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 transferAmount = vault.balanceOf(user1) / 2;

        vm.prank(admin);
        vault.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(user1);
        vault.transfer(user2, transferAmount);
    }

    function test_lockStake_revertsWhenPaused() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(admin);
        vault.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(admin);
        vault.unpause();

        vm.prank(user1);
        vault.lockStake(400e18);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, 400e18);
    }

    // ── Deposit-timestamp time-lock bypass resistance ───────────────

    function test_depositOnBehalf_resetsTimestamp() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.warp(block.timestamp + 1 days);

        token.mint(user2, 1);
        vm.prank(user2);
        token.approve(address(vault), 1);
        vm.prank(user2);
        vault.deposit(1, user1);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user1);
        vault.lockStake(400e18);
    }

    function test_transfer_resetsTimestampOfExistingStaker() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        vm.warp(block.timestamp + 1 days);

        vm.prank(user2);
        vault.transfer(user1, 1);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user1);
        vault.lockStake(400e18);
    }

    function test_bypass_thirdPartyDeposit_ZeroTimestamp() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        token.mint(user2, DEPOSIT_AMOUNT);
        vm.prank(user2);
        token.approve(address(vault), DEPOSIT_AMOUNT);

        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user1);
        vault.lockStake(DEPOSIT_AMOUNT);
    }

    function test_bypass_warmSybilTransfer() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(1, user1);

        skip(1 days);

        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        skip(1 days);

        uint256 user2Bal = vault.balanceOf(user2);
        vm.prank(user2);
        vault.transfer(user1, user2Bal);

        uint256 avail = vault.availableBalance(user1);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user1);
        vault.lockStake(avail);
    }

    function test_transfer_setsTimestampForFirstTimeRecipient() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        skip(1 days);

        uint256 sharesToTransfer = vault.balanceOf(user1) / 2;
        uint256 transferredAssets = vault.convertToAssets(sharesToTransfer);

        vm.prank(user1);
        vault.transfer(user2, sharesToTransfer);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user2);
        vault.lockStake(transferredAssets);

        skip(1 days);

        vm.prank(user2);
        vault.lockStake(transferredAssets);

        StakeAccount memory acct = vault.getStakeAccount(user2);
        assertEq(acct.lockedAmount, transferredAssets);
    }

    // ── Full lock/unlock lifecycle ─────────────────────────────────

    function test_lockUnlockLifecycle() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, 400e18);
        assertEq(vault.availableBalance(user1), DEPOSIT_AMOUNT - 400e18);

        vm.prank(engine);
        vault.unlockStake(user1, 400e18);

        acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, 0);
        assertEq(vault.availableBalance(user1), DEPOSIT_AMOUNT);

        vm.prank(user1);
        vault.withdraw(DEPOSIT_AMOUNT, user1, user1);
        assertEq(vault.balanceOf(user1), 0);
    }

    // ── MEV Protection ─────────────────────────────────────────────

    function test_mev_frontrunSlashStake() public {
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
            abi.encodeWithSelector(
                ERC4626Upgradeable.ERC4626ExceededMaxWithdraw.selector, user2, DEPOSIT_AMOUNT * 10, 0
            )
        );
        vm.prank(user2);
        vault.withdraw(DEPOSIT_AMOUNT * 10, user2, user2);

        uint256 u2Bal = vault.balanceOf(user2);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user2);
        vault.transfer(user1, u2Bal);
    }

    // ── Coverage specific additions ────────────────────────────────

    function test_verifyStorageLocation() public view {
        assertTrue(vault.verifyStorageLocation());
    }

    function test_maxMintAndDeposit_pausedAndUnpaused() public {
        assertEq(vault.maxDeposit(user1), type(uint256).max);
        assertEq(vault.maxMint(user1), type(uint256).max);

        vm.prank(admin);
        vault.pause();

        assertEq(vault.maxDeposit(user1), 0);
        assertEq(vault.maxMint(user1), 0);
    }

    function test_minDepositAge_view() public {
        assertEq(vault.minDepositAge(), 0);

        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        assertEq(vault.minDepositAge(), 1 days);
    }

    function test_setMinDepositAge_tooHigh() public {
        uint256 maxAge = vault.MAX_MIN_DEPOSIT_AGE();
        uint256 tooHigh = maxAge + 1;

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.MinDepositAgeTooHigh.selector, tooHigh, maxAge));
        vm.prank(admin);
        vault.setMinDepositAge(tooHigh);
    }

    function test_authorizeUpgrade() public {
        SapienVault newImpl = new SapienVault();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, ADMIN_ROLE)
        );
        vm.prank(user1);
        vault.upgradeToAndCall(address(newImpl), "");

        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");
    }

    function test_initialize_revertsZeroAddress() public {
        SapienVault impl = new SapienVault();

        bytes memory initDataAsset0 = abi.encodeCall(SapienVault.initialize, (IERC20(address(0)), admin));
        vm.expectRevert(ISapienVault.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initDataAsset0);

        bytes memory initDataAdmin0 = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), address(0)));
        vm.expectRevert(ISapienVault.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initDataAdmin0);
    }

    function test_slashStake_revertsZeroAmount() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vm.prank(engine);
        vault.slashStake(user1, 0);
    }

    function test_maxRedeem_timeLockNotMet() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        assertEq(vault.maxRedeem(user1), 0);

        vm.warp(block.timestamp + 1 days);
        assertGt(vault.maxRedeem(user1), 0);
    }

    function test_maxRedeem_paused() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(admin);
        vault.pause();

        assertEq(vault.maxRedeem(user1), 0);
    }

    function test_transfer_revertsTransferExceedsUnlockedShares() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(800e18);

        uint256 transferAmount = vault.balanceOf(user1) - vault.convertToShares(800e18) + 1;

        vm.expectRevert(ISapienVault.TransferExceedsUnlockedShares.selector);
        vm.prank(user1);
        vault.transfer(user2, transferAmount);
    }

    // ── Re-initialization Guard ────────────────────────────────────

    function test_cannotReinitialize() public {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(IERC20(address(token)), admin);
    }

    // ── Donation Attack Tests ──────────────────────────────────────

    function test_donationAttack_firstDepositor() public {
        token.mint(address(this), 1e18);
        token.transfer(address(vault), 1e18);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        assertGt(vault.balanceOf(user1), 0, "First depositor got zero shares after donation");
        // Virtual offset protects the depositor — they may lose trivial rounding dust
        // but must retain the vast majority of their deposit.
        assertGe(
            vault.maxWithdraw(user1),
            DEPOSIT_AMOUNT * 999 / 1000,
            "First depositor lost more than 0.1% to donation attack"
        );
    }

    function test_donationDoesNotBreakExistingStakers() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 stakeBalBefore = vault.getUserStakeBalance(user1);

        token.mint(address(this), 500e18);
        token.transfer(address(vault), 500e18);

        assertGe(vault.getUserStakeBalance(user1), stakeBalBefore, "Donation decreased user's stake value");
    }

    // ── Mint & Redeem Paths ────────────────────────────────────────

    function test_mint() public {
        uint256 sharesToMint = vault.previewDeposit(DEPOSIT_AMOUNT);

        vm.prank(user1);
        vault.mint(sharesToMint, user1);

        assertEq(vault.balanceOf(user1), sharesToMint);
        assertGt(vault.getUserStakeBalance(user1), 0);
    }

    function test_redeem() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 shares = vault.balanceOf(user1);
        uint256 balBefore = token.balanceOf(user1);

        vm.prank(user1);
        vault.redeem(shares, user1, user1);

        uint256 balAfter = token.balanceOf(user1);
        assertEq(balAfter - balBefore, DEPOSIT_AMOUNT);
        assertEq(vault.balanceOf(user1), 0);
    }

    function test_mint_revertsWhenPaused() public {
        vm.prank(admin);
        vault.pause();

        uint256 sharesToMint = 1000e21;
        vm.expectRevert(
            abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxMint.selector, user1, sharesToMint, 0)
        );
        vm.prank(user1);
        vault.mint(sharesToMint, user1);
    }

    function test_redeem_revertsWhenPaused() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 shares = vault.balanceOf(user1);

        vm.prank(admin);
        vault.pause();

        vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector, user1, shares, 0));
        vm.prank(user1);
        vault.redeem(shares, user1, user1);
    }

    function test_redeem_respectsTimeLock() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 shares = vault.balanceOf(user1);

        vm.expectRevert(abi.encodeWithSelector(ERC4626Upgradeable.ERC4626ExceededMaxRedeem.selector, user1, shares, 0));
        vm.prank(user1);
        vault.redeem(shares, user1, user1);

        vm.warp(block.timestamp + 1 days);

        vm.prank(user1);
        vault.redeem(shares, user1, user1);

        assertEq(vault.balanceOf(user1), 0);
    }

    function test_redeem_respectsLockedShares() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(800e18);

        uint256 shares = vault.balanceOf(user1);

        vm.expectRevert();
        vm.prank(user1);
        vault.redeem(shares, user1, user1);

        uint256 redeemable = vault.maxRedeem(user1);
        assertGt(redeemable, 0);

        vm.prank(user1);
        vault.redeem(redeemable, user1, user1);
    }

    // ── TransferFrom Path ──────────────────────────────────────────

    function test_transferFrom_respectsPause() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 transferAmount = vault.balanceOf(user1) / 2;

        vm.prank(user1);
        vault.approve(user2, type(uint256).max);

        vm.prank(admin);
        vault.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(user2);
        vault.transferFrom(user1, user2, transferAmount);
    }

    function test_transferFrom_respectsLockedShares() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(800e18);

        vm.prank(user1);
        vault.approve(user2, type(uint256).max);

        uint256 transferAmount = vault.balanceOf(user1) - vault.convertToShares(800e18) + 1;

        vm.expectRevert(ISapienVault.TransferExceedsUnlockedShares.selector);
        vm.prank(user2);
        vault.transferFrom(user1, user2, transferAmount);
    }

    function test_transferFrom_respectsTimeLock() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.approve(user2, type(uint256).max);

        uint256 transferAmount = vault.balanceOf(user1) / 2;

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user2);
        vault.transferFrom(user1, user2, transferAmount);

        vm.warp(block.timestamp + 1 days);

        vm.prank(user2);
        vault.transferFrom(user1, user2, transferAmount);

        assertEq(vault.balanceOf(user2), transferAmount);
    }

    function test_transferFrom_resetsReceiverTimestamp() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        vm.prank(user1);
        vault.approve(user2, type(uint256).max);

        skip(1 days);

        uint256 transferAmount = vault.balanceOf(user1) / 4;

        vm.prank(user2);
        vault.transferFrom(user1, user2, transferAmount);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user2);
        vault.lockStake(400e18);
    }

    // ── Slash Rounding Dust ────────────────────────────────────────

    function test_slashStake_roundingDust() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(DEPOSIT_AMOUNT);

        uint256 sharesBefore = vault.balanceOf(user1);

        vm.prank(engine);
        vault.slashStake(user1, 1);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, DEPOSIT_AMOUNT - 1, "lockedAmount not decremented");

        uint256 sharesAfter = vault.balanceOf(user1);
        uint256 sharesBurned = sharesBefore - sharesAfter;
        if (sharesBurned == 0) {
            // Rounding: 1 wei of assets rounds to 0 shares burned.
            // lockedAmount decreased but no shares removed — potential accounting drift.
            assertEq(sharesAfter, sharesBefore, "Shares changed despite zero-share burn");
        }
    }

    // ── Event Emission Assertions ──────────────────────────────────

    function test_lockStake_emitsStakeLocked() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ISapienVault.StakeLocked(user1, 400e18);

        vm.prank(user1);
        vault.lockStake(400e18);
    }

    function test_unlockStake_emitsStakeUnlocked() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ISapienVault.StakeUnlocked(user1, 150e18);

        vm.prank(engine);
        vault.unlockStake(user1, 150e18);
    }

    function test_slashStake_emitsStakeSlashed() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectEmit(true, false, false, true, address(vault));
        emit ISapienVault.StakeSlashed(user1, 100e18);

        vm.prank(engine);
        vault.slashStake(user1, 100e18);
    }

    function test_setMinDepositAge_emitsMinDepositAgeUpdated() public {
        vm.expectEmit(false, false, false, true, address(vault));
        emit ISapienVault.MinDepositAgeUpdated(1 days);

        vm.prank(admin);
        vault.setMinDepositAge(1 days);
    }

    // ── Multi-User Interaction Tests ───────────────────────────────

    function test_slashDoesNotReduceOtherUserBalance() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        uint256 user2BalBefore = vault.getUserStakeBalance(user2);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(engine);
        vault.slashStake(user1, 400e18);

        assertGe(vault.getUserStakeBalance(user2), user2BalBefore, "Slash reduced other user's value");
        assertGe(vault.maxWithdraw(user2), DEPOSIT_AMOUNT, "Slash blocked other user's withdrawal");
    }

    function test_slashAfterPartialWithdrawal() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(600e18);

        vm.prank(engine);
        vault.unlockStake(user1, 200e18);

        vm.prank(user1);
        vault.withdraw(200e18, user1, user1);

        vm.prank(engine);
        vault.slashStake(user1, 400e18);

        assertEq(vault.getStakeAccount(user1).lockedAmount, 0);
        assertGt(vault.balanceOf(user1), 0, "User has no shares remaining");
    }

    function test_multipleLockUnlockCycles() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(user1);
            vault.lockStake(100e18);

            vm.prank(engine);
            vault.unlockStake(user1, 100e18);
        }

        assertEq(vault.getStakeAccount(user1).lockedAmount, 0);
        assertEq(vault.availableBalance(user1), DEPOSIT_AMOUNT);
    }

    // ── Self-Transfer and Edge Cases ───────────────────────────────

    function test_selfTransfer_resetsOwnTimestamp() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        skip(1 days);

        uint256 bal = vault.balanceOf(user1);

        vm.prank(user1);
        vault.transfer(user1, bal);

        assertEq(vault.balanceOf(user1), bal, "Balance changed on self-transfer");

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user1);
        vault.lockStake(400e18);
    }

    function test_zeroValueTransfer_doesNotResetTimestamp() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        skip(1 days);

        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        skip(1 days);

        vm.prank(user2);
        vault.transfer(user1, 0);

        vm.prank(user1);
        vault.lockStake(400e18);

        assertEq(vault.getStakeAccount(user1).lockedAmount, 400e18);
    }

    function test_deposit_oneWei() public {
        token.mint(user1, 1);
        vm.prank(user1);
        token.approve(address(vault), 1);
        vm.prank(user1);
        vault.deposit(1, user1);

        assertGt(vault.balanceOf(user1), 0, "1 wei deposit minted zero shares");
    }

    function test_lockStake_entireBalance() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 totalAssets = vault.getUserStakeBalance(user1);

        vm.prank(user1);
        vault.lockStake(totalAssets);

        assertEq(vault.maxRedeem(user1), 0, "maxRedeem not zero when fully locked");
        assertEq(vault.maxWithdraw(user1), 0, "maxWithdraw not zero when fully locked");
    }

    // ── Role Management Tests ──────────────────────────────────────

    function test_revokeEngineRole_blocksOperations() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(admin);
        vault.revokeRole(ENGINE_ROLE, engine);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, engine, ENGINE_ROLE)
        );
        vm.prank(engine);
        vault.unlockStake(user1, 200e18);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, engine, ENGINE_ROLE)
        );
        vm.prank(engine);
        vault.slashStake(user1, 100e18);
    }

    function test_multipleEngines() public {
        address engine2 = makeAddr("engine2");
        vm.prank(admin);
        vault.grantRole(ENGINE_ROLE, engine2);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(engine);
        vault.unlockStake(user1, 100e18);

        vm.prank(engine2);
        vault.unlockStake(user1, 100e18);

        assertEq(vault.getStakeAccount(user1).lockedAmount, 200e18);
    }

    function test_adminRenounce_blocksAdminOps() public {
        vm.prank(admin);
        vault.renounceRole(ADMIN_ROLE, admin);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, ADMIN_ROLE)
        );
        vm.prank(admin);
        vault.pause();

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, admin, ADMIN_ROLE)
        );
        vm.prank(admin);
        vault.setMinDepositAge(1 days);
    }

    // ── Griefing Scenario Documentation ────────────────────────────

    function test_griefing_resetTimestampViaDustTransfer() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        skip(1 days);

        // Attacker prepares dust shares
        token.mint(user2, 1);
        vm.prank(user2);
        token.approve(address(vault), 1);
        vm.prank(user2);
        vault.deposit(1, user2);
        skip(1 days);

        // Attacker sends 1 share to victim, resetting their timestamp.
        // This is a known trade-off: we accept inbound griefing to prevent
        // bypassing minDepositAge via sybil share transfers.
        vm.prank(user2);
        vault.transfer(user1, 1);

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.DepositTooRecent.selector, 1 days, 0));
        vm.prank(user1);
        vault.lockStake(400e18);

        assertEq(vault.maxWithdraw(user1), 0, "Griefed user can still withdraw");

        // Victim recovers after waiting
        skip(1 days);
        vm.prank(user1);
        vault.lockStake(400e18);
        assertEq(vault.getStakeAccount(user1).lockedAmount, 400e18);
    }

    // ── Fuzz Tests ──────────────────────────────────────────────────

    function testFuzz_deposit(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(vault), amount);

        vm.prank(user1);
        vault.deposit(amount, user1);

        assertGt(vault.balanceOf(user1), 0);
        assertEq(vault.getUserStakeBalance(user1), amount);
    }

    function testFuzz_withdraw(uint256 amount, uint256 withdrawAmount) public {
        amount = bound(amount, 1, type(uint128).max);
        withdrawAmount = bound(withdrawAmount, 1, amount);

        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(vault), amount);

        vm.prank(user1);
        vault.deposit(amount, user1);

        uint256 balBefore = token.balanceOf(user1);
        vm.prank(user1);
        vault.withdraw(withdrawAmount, user1, user1);
        uint256 balAfter = token.balanceOf(user1);

        assertEq(balAfter - balBefore, withdrawAmount);
    }

    function testFuzz_lockStake(uint256 amount, uint256 lockAmount) public {
        amount = bound(amount, 1, type(uint128).max);
        lockAmount = bound(lockAmount, 1, amount);

        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(vault), amount);

        vm.prank(user1);
        vault.deposit(amount, user1);

        vm.prank(user1);
        vault.lockStake(lockAmount);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, lockAmount);
        assertEq(vault.availableBalance(user1), amount - lockAmount);
    }

    function testFuzz_unlockStake(uint256 amount, uint256 lockAmount, uint256 unlockAmount) public {
        amount = bound(amount, 1, type(uint128).max);
        lockAmount = bound(lockAmount, 1, amount);
        unlockAmount = bound(unlockAmount, 1, lockAmount);

        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(vault), amount);

        vm.prank(user1);
        vault.deposit(amount, user1);

        vm.prank(user1);
        vault.lockStake(lockAmount);

        vm.prank(engine);
        vault.unlockStake(user1, unlockAmount);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, lockAmount - unlockAmount);
    }

    function testFuzz_slashStake(uint256 amount, uint256 lockAmount, uint256 slashAmount) public {
        amount = bound(amount, 1, type(uint128).max);
        lockAmount = bound(lockAmount, 1, amount);
        slashAmount = bound(slashAmount, 1, lockAmount);

        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(vault), amount);

        vm.prank(user1);
        vault.deposit(amount, user1);

        vm.prank(user1);
        vault.lockStake(lockAmount);

        uint256 sharesBefore = vault.balanceOf(user1);

        vm.prank(engine);
        vault.slashStake(user1, slashAmount);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertLt(sharesAfter, sharesBefore);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, lockAmount - slashAmount);
    }

    function testFuzz_transfer(uint256 amount, uint256 lockAmount, uint256 transferAmount) public {
        amount = bound(amount, 1, type(uint128).max);
        lockAmount = bound(lockAmount, 0, amount);

        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(vault), amount);

        vm.prank(user1);
        vault.deposit(amount, user1);

        if (lockAmount > 0) {
            vm.prank(user1);
            vault.lockStake(lockAmount);
        }

        uint256 maxTransferableAssets = vault.availableBalance(user1);
        uint256 maxTransferableShares = vault.convertToShares(maxTransferableAssets);

        transferAmount = bound(transferAmount, 0, maxTransferableShares);

        if (transferAmount > 0) {
            vm.prank(user1);
            vault.transfer(user2, transferAmount);

            assertEq(vault.balanceOf(user2), transferAmount);
        }
    }

    function testFuzz_setMinDepositAge(uint256 age) public {
        age = bound(age, 0, vault.MAX_MIN_DEPOSIT_AGE());

        vm.prank(admin);
        vault.setMinDepositAge(age);

        assertEq(vault.minDepositAge(), age);
    }

    function testFuzz_mint(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        uint256 assetsNeeded = vault.previewMint(amount);
        token.mint(user1, assetsNeeded);
        vm.prank(user1);
        token.approve(address(vault), assetsNeeded);

        vm.prank(user1);
        vault.mint(amount, user1);

        assertEq(vault.balanceOf(user1), amount);
    }

    function testFuzz_redeem(uint256 amount, uint256 redeemShares) public {
        amount = bound(amount, 1, type(uint128).max);

        token.mint(user1, amount);
        vm.prank(user1);
        token.approve(address(vault), amount);

        vm.prank(user1);
        vault.deposit(amount, user1);

        uint256 totalShares = vault.balanceOf(user1);
        redeemShares = bound(redeemShares, 1, totalShares);

        uint256 expectedAssets = vault.previewRedeem(redeemShares);
        uint256 balBefore = token.balanceOf(user1);

        vm.prank(user1);
        vault.redeem(redeemShares, user1, user1);

        uint256 balAfter = token.balanceOf(user1);
        assertEq(balAfter - balBefore, expectedAssets);
    }

    // ── maxWithdraw rounding mismatch fix ─────────────────────────────

    /// @dev Reproduces the exact scenario from the bug report:
    ///      1. Deposit 1 wei → mints 1000 shares (decimalsOffset = 3)
    ///      2. Donate 4 wei directly to the vault (raises exchange rate)
    ///      3. Lock 1 wei
    ///      4. maxWithdraw must be conservative enough that withdrawing it
    ///         does NOT leave lockedAmount undercollateralised.
    function test_maxWithdraw_conservativeAfterDonation() public {
        vm.prank(user1);
        vault.deposit(1, user1);

        uint256 sharesAfterDeposit = vault.balanceOf(user1);
        assertEq(sharesAfterDeposit, 1000, "1 wei deposit should mint 1000 shares with offset=3");

        token.mint(address(this), 4);
        token.transfer(address(vault), 4);

        vm.prank(user1);
        vault.lockStake(1);

        uint256 maxW = vault.maxWithdraw(user1);

        if (maxW > 0) {
            vm.prank(user1);
            vault.withdraw(maxW, user1, user1);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user1));
        assertGe(
            remainingAssets,
            vault.getStakeAccount(user1).lockedAmount,
            "Remaining assets must cover lockedAmount after maxWithdraw withdrawal"
        );
    }

    /// @dev After a donation that skews the exchange rate, withdrawing
    ///      maxWithdraw should never revert and should always preserve the
    ///      locked-amount collateral invariant.
    function test_maxWithdraw_doesNotRevert_afterDonation() public {
        vm.prank(user1);
        vault.deposit(100, user1);

        token.mint(address(this), 50);
        token.transfer(address(vault), 50);

        vm.prank(user1);
        vault.lockStake(50);

        uint256 maxW = vault.maxWithdraw(user1);

        if (maxW > 0) {
            vm.prank(user1);
            vault.withdraw(maxW, user1, user1);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user1));
        assertGe(
            remainingAssets,
            vault.getStakeAccount(user1).lockedAmount,
            "Lock invariant violated after withdrawing maxWithdraw"
        );
    }

    /// @dev maxRedeem should also be conservative: redeeming maxRedeem shares
    ///      must not undercollateralise the lock after a donation.
    function test_maxRedeem_conservativeAfterDonation() public {
        vm.prank(user1);
        vault.deposit(1, user1);

        token.mint(address(this), 4);
        token.transfer(address(vault), 4);

        vm.prank(user1);
        vault.lockStake(1);

        uint256 maxR = vault.maxRedeem(user1);

        if (maxR > 0) {
            vm.prank(user1);
            vault.redeem(maxR, user1, user1);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user1));
        assertGe(
            remainingAssets,
            vault.getStakeAccount(user1).lockedAmount,
            "Remaining assets must cover lockedAmount after maxRedeem redemption"
        );
    }

    /// @dev Fuzz test: for any deposit, donation, and lock, withdrawing
    ///      maxWithdraw must preserve the locked-amount invariant.
    function testFuzz_maxWithdraw_preservesLockInvariant(
        uint256 depositAmt,
        uint256 donationAmt,
        uint256 lockAmt
    ) public {
        depositAmt = bound(depositAmt, 1, 1e24);
        donationAmt = bound(donationAmt, 0, 1e24);

        token.mint(user1, depositAmt);
        vm.prank(user1);
        token.approve(address(vault), depositAmt);
        vm.prank(user1);
        vault.deposit(depositAmt, user1);

        if (donationAmt > 0) {
            token.mint(address(this), donationAmt);
            token.transfer(address(vault), donationAmt);
        }

        uint256 userAssets = vault.convertToAssets(vault.balanceOf(user1));
        lockAmt = bound(lockAmt, 0, userAssets);

        if (lockAmt > 0) {
            vm.prank(user1);
            vault.lockStake(lockAmt);
        }

        uint256 maxW = vault.maxWithdraw(user1);

        if (maxW > 0) {
            vm.prank(user1);
            vault.withdraw(maxW, user1, user1);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user1));
        assertGe(
            remainingAssets,
            vault.getStakeAccount(user1).lockedAmount,
            "Lock invariant violated"
        );
    }

    /// @dev Fuzz test: for any deposit, donation, and lock, redeeming
    ///      maxRedeem must preserve the locked-amount invariant.
    function testFuzz_maxRedeem_preservesLockInvariant(
        uint256 depositAmt,
        uint256 donationAmt,
        uint256 lockAmt
    ) public {
        depositAmt = bound(depositAmt, 1, 1e24);
        donationAmt = bound(donationAmt, 0, 1e24);

        token.mint(user1, depositAmt);
        vm.prank(user1);
        token.approve(address(vault), depositAmt);
        vm.prank(user1);
        vault.deposit(depositAmt, user1);

        if (donationAmt > 0) {
            token.mint(address(this), donationAmt);
            token.transfer(address(vault), donationAmt);
        }

        uint256 userAssets = vault.convertToAssets(vault.balanceOf(user1));
        lockAmt = bound(lockAmt, 0, userAssets);

        if (lockAmt > 0) {
            vm.prank(user1);
            vault.lockStake(lockAmt);
        }

        uint256 maxR = vault.maxRedeem(user1);

        if (maxR > 0) {
            vm.prank(user1);
            vault.redeem(maxR, user1, user1);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user1));
        assertGe(
            remainingAssets,
            vault.getStakeAccount(user1).lockedAmount,
            "Lock invariant violated after maxRedeem"
        );
    }

    /// @dev Verifies that the fix doesn't break normal (no-lock) withdrawals.
    function test_maxWithdraw_fullWithdraw_noLock() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        token.mint(address(this), 500e18);
        token.transfer(address(vault), 500e18);

        uint256 maxW = vault.maxWithdraw(user1);
        assertGt(maxW, 0, "maxWithdraw should be positive with no lock");

        uint256 balBefore = token.balanceOf(user1);
        vm.prank(user1);
        vault.withdraw(maxW, user1, user1);
        uint256 balAfter = token.balanceOf(user1);

        assertEq(balAfter - balBefore, maxW, "Should withdraw exact maxWithdraw amount");
    }

    /// @dev Withdrawing exactly maxWithdraw on a partially-locked account
    ///      should succeed and maintain the invariant.
    function test_maxWithdraw_partialLock_postDonation() public {
        vm.prank(user1);
        vault.deposit(1000, user1);

        token.mint(address(this), 3000);
        token.transfer(address(vault), 3000);

        vm.prank(user1);
        vault.lockStake(500);

        uint256 maxW = vault.maxWithdraw(user1);
        assertGt(maxW, 0, "Should be able to withdraw something");

        vm.prank(user1);
        vault.withdraw(maxW, user1, user1);

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user1));
        uint256 locked = vault.getStakeAccount(user1).lockedAmount;
        assertGe(remainingAssets, locked, "Lock invariant violated on partial lock + donation");
    }
}
