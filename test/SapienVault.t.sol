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
        // initialize() now seeds minDepositAge with DEFAULT_MIN_DEPOSIT_AGE
        // (SAP-5). These mechanics tests exercise lock/slash/transfer/withdraw
        // logic independently of the cooldown, so disable the guard here; the
        // cooldown-specific tests set their own non-zero age, and the seeded
        // default is verified by test_initialize_seedsDefaultMinDepositAge.
        vault.setMinDepositAge(0);
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
        assertEq(vault.assetsOf(user1), DEPOSIT_AMOUNT);
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

        // Freshly-deposited shares are immature, so none are available to lock.
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientAvailableBalance.selector, 400e18, 0));
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.warp(block.timestamp + 1 days);

        vm.prank(user1);
        vault.lockStake(400e18);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, 400e18);
    }

    /// @dev Age travels with shares: a recipient of MATURE shares can lock them
    ///      immediately (the SAP-1 refactor binds the cooldown to the shares,
    ///      not to the receiving address).
    function test_lockStake_allowsMatureTransferRecipient() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        skip(1 days);

        uint256 sharesToTransfer = vault.balanceOf(user1) / 2;
        uint256 transferredAssets = vault.convertToAssets(sharesToTransfer);

        vm.prank(user1);
        vault.transfer(user2, sharesToTransfer);

        // Recipient received matured shares, so it can lock without waiting.
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

    /// @dev SEC-M-03: pause must halt engine-driven mutations. Admin remains
    ///      able to neutralise a misbehaving engine by `revokeRole` while
    ///      paused; this test only asserts the pause modifier itself.
    function test_unlockStake_revertsWhenPaused() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(admin);
        vault.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(engine);
        vault.unlockStake(user1, 100e18);
    }

    /// @dev SEC-M-03: slashStake also gated by pause for symmetry with
    ///      unlockStake. Unblocks once admin unpauses.
    function test_slashStake_revertsWhenPaused() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(admin);
        vault.pause();

        vm.expectRevert(PausableUpgradeable.EnforcedPause.selector);
        vm.prank(engine);
        vault.slashStake(user1, 100e18);

        vm.prank(admin);
        vault.unpause();

        vm.prank(engine);
        vault.slashStake(user1, 100e18);

        assertEq(vault.getStakeAccount(user1).lockedAmount, 300e18);
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

    /// @dev SAP-5: a freshly initialized vault seeds the MEV guard with
    ///      DEFAULT_MIN_DEPOSIT_AGE rather than leaving it at 0. (The shared
    ///      fixture disables it afterwards for the mechanics tests.)
    function test_initialize_seedsDefaultMinDepositAge() public {
        SapienVault impl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), admin));
        SapienVault fresh = SapienVault(address(new ERC1967Proxy(address(impl), initData)));

        assertEq(fresh.minDepositAge(), fresh.DEFAULT_MIN_DEPOSIT_AGE());
        assertEq(fresh.minDepositAge(), 1 days);
    }

    function test_setMinDepositAge_tooHigh() public {
        uint256 maxAge = vault.MAX_MIN_DEPOSIT_AGE();
        uint256 tooHigh = maxAge + 1;

        vm.expectRevert(abi.encodeWithSelector(ISapienVault.MinDepositAgeTooHigh.selector, tooHigh, maxAge));
        vm.prank(admin);
        vault.setMinDepositAge(tooHigh);
    }

    function test_minTrancheSize_view() public {
        assertEq(vault.minTrancheSize(), 0);

        vm.prank(admin);
        vault.setMinTrancheSize(1e18);

        assertEq(vault.minTrancheSize(), 1e18);
    }

    function test_deposit_belowMinTrancheSize_revertsWhenAgeEnabled() public {
        vm.startPrank(admin);
        vault.setMinDepositAge(1 days);
        vault.setMinTrancheSize(1e18);
        vm.stopPrank();

        uint256 dustAssets = 1;
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.BelowMinTrancheSize.selector, dustAssets, 1e18));
        vm.prank(user1);
        vault.deposit(dustAssets, user1);

        vm.prank(user1);
        vault.deposit(1e18, user1);
        assertGt(vault.balanceOf(user1), 0);
    }

    function test_deposit_belowMinTrancheSize_allowedWhenAgeDisabled() public {
        vm.prank(admin);
        vault.setMinTrancheSize(1e18);

        vm.prank(user1);
        vault.deposit(1, user1);
        assertGt(vault.balanceOf(user1), 0);
    }

    function test_delegateDeposit_belowMinTrancheSize_reverts() public {
        vm.startPrank(admin);
        vault.setMinDepositAge(1 days);
        vault.setMinTrancheSize(1e18);
        vm.stopPrank();

        uint256 dustAssets = 1;
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.BelowMinTrancheSize.selector, dustAssets, 1e18));
        vm.prank(user2);
        vault.deposit(dustAssets, user1);
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

        uint256 stakeBalBefore = vault.assetsOf(user1);

        token.mint(address(this), 500e18);
        token.transfer(address(vault), 500e18);

        assertGe(vault.assetsOf(user1), stakeBalBefore, "Donation decreased user's stake value");
    }

    // ── Mint & Redeem Paths ────────────────────────────────────────

    function test_mint() public {
        uint256 sharesToMint = vault.previewDeposit(DEPOSIT_AMOUNT);

        vm.prank(user1);
        vault.mint(sharesToMint, user1);

        assertEq(vault.balanceOf(user1), sharesToMint);
        assertGt(vault.assetsOf(user1), 0);
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

        // Sender's freshly-deposited shares are immature, so the transfer of
        // unlocked shares it cannot yet move reverts.
        vm.expectRevert(ISapienVault.TransferExceedsUnlockedShares.selector);
        vm.prank(user2);
        vault.transferFrom(user1, user2, transferAmount);

        vm.warp(block.timestamp + 1 days);

        vm.prank(user2);
        vault.transferFrom(user1, user2, transferAmount);

        assertEq(vault.balanceOf(user2), transferAmount);
    }

    /// @dev A transferFrom recipient receives MATURE shares (age travels) and
    ///      can act on them immediately; no global timer is reset.
    function test_transferFrom_recipientReceivesMatureShares() public {
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

        // user2 was already matured and receives matured shares: lock succeeds.
        vm.prank(user2);
        vault.lockStake(400e18);
        assertEq(vault.getStakeAccount(user2).lockedAmount, 400e18);
    }

    // ── Slash Rounding Fix ─────────────────────────────────────────

    /// @dev After the fix, slashing 1 wei at 1:1 rate rounds up to 1 share
    ///      (thanks to decimalsOffset the virtual offset makes previewWithdraw(1) >= 1).
    function test_slashStake_burnsAtLeastOneShare() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(DEPOSIT_AMOUNT);

        uint256 sharesBefore = vault.balanceOf(user1);

        vm.prank(engine);
        vault.slashStake(user1, 1);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertLt(sharesAfter, sharesBefore, "slash must burn >= 1 share");

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.lockedAmount, DEPOSIT_AMOUNT - 1, "lockedAmount not decremented");
    }

    /// @dev With a high exchange rate (donation) and a second staker, the
    ///      dilution-compensated slash still inflicts ~the intended net damage on
    ///      the user (never more) and burns strictly more than the naive
    ///      convertToShares equivalent (SAP-2).
    function test_slashStake_netDamage_afterDonation() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        token.mint(address(this), 2 * DEPOSIT_AMOUNT);
        token.transfer(address(vault), 2 * DEPOSIT_AMOUNT);

        vm.prank(user1);
        vault.lockStake(400e18);

        uint256 naiveShares = vault.convertToShares(400e18);
        uint256 sharesBefore = vault.balanceOf(user1);
        uint256 valueBefore = vault.convertToAssets(vault.balanceOf(user1));

        vm.prank(engine);
        vault.slashStake(user1, 400e18);

        uint256 sharesBurned = sharesBefore - vault.balanceOf(user1);
        uint256 loss = valueBefore - vault.convertToAssets(vault.balanceOf(user1));

        assertGt(sharesBurned, naiveShares, "dilution-compensated burn exceeds naive convertToShares");
        assertLe(loss, 400e18, "slash must never over-penalize");
        assertApproxEqAbs(loss, 400e18, 1e16, "net damage equals the intended amount");
    }

    /// @dev Slashing an amount that would round to zero shares with the old
    ///      convertToShares now reverts with ZeroShareSlash when even
    ///      previewWithdraw yields 0. This is unreachable with the virtual
    ///      offset (decimalsOffset = 3 means 1 asset -> 1000 virtual shares),
    ///      but the guard protects future configurations.
    function test_slashStake_zeroShareSlash_reverts() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vault.lockStake(DEPOSIT_AMOUNT);

        uint256 sharesToBurn = vault.previewWithdraw(1);
        assertGt(sharesToBurn, 0, "With offset=3, previewWithdraw(1) should be > 0");
    }

    /// @dev After a large donation pushes the exchange rate so high that one wei
    ///      of asset value is worth less than a single share, a sub-share slash
    ///      rounds to zero shares and reverts with ZeroShareSlash (never silently
    ///      reducing lockedAmount without a burn). A slash at/above one share's
    ///      value still burns. Rounding is *down* to keep slashing solvency-safe.
    function test_slashStake_smallSlash_highExchangeRate() public {
        vm.prank(user1);
        vault.deposit(1e18, user1);

        token.mint(address(this), 1000e18);
        token.transfer(address(vault), 1000e18);

        vm.prank(user1);
        vault.lockStake(1e18);

        // 1 wei of damage is below one share's value at this rate -> reverts.
        assertEq(vault.convertToShares(1), 0, "1 wei should round to 0 shares at this rate");
        vm.prank(engine);
        vm.expectRevert(ISapienVault.ZeroShareSlash.selector);
        vault.slashStake(user1, 1);

        // A slash worth at least one share burns shares as expected.
        uint256 minSlash = vault.convertToAssets(1) + 2;
        uint256 sharesBefore = vault.balanceOf(user1);
        vm.prank(engine);
        vault.slashStake(user1, minSlash);
        assertLt(vault.balanceOf(user1), sharesBefore, "slash >= one share must burn shares");
    }

    /// @dev Fuzz: slashing any non-zero locked amount must always burn at least
    ///      one share (the dilution-compensated burn is >= the naive equivalent).
    function testFuzz_slashStake_alwaysBurnsShares(uint256 depositAmt, uint256 donationAmt, uint256 slashAmt) public {
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
        // A slash must be worth at least one share to burn anything; sub-share
        // amounts correctly revert with ZeroShareSlash (see unit test).
        uint256 minSlash = vault.previewMint(1);
        vm.assume(userAssets >= minSlash);
        slashAmt = bound(slashAmt, minSlash, userAssets);

        vm.prank(user1);
        vault.lockStake(slashAmt);

        uint256 sharesBefore = vault.balanceOf(user1);

        vm.prank(engine);
        vault.slashStake(user1, slashAmt);

        uint256 sharesAfter = vault.balanceOf(user1);
        assertLt(sharesAfter, sharesBefore, "Fuzz: slash >= one share must burn at least 1 share");
    }

    /// @dev Verify that after slashing, the remaining shares still cover any
    ///      remaining locked amount (the lock invariant holds).
    function testFuzz_slashStake_preservesLockInvariant(
        uint256 depositAmt,
        uint256 donationAmt,
        uint256 lockAmt,
        uint256 slashAmt
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
        // Keep the slash at/above one share's value (sub-share slashes revert).
        uint256 minSlash = vault.previewMint(1);
        vm.assume(userAssets >= minSlash);
        lockAmt = bound(lockAmt, minSlash, userAssets);
        slashAmt = bound(slashAmt, minSlash, lockAmt);

        vm.prank(user1);
        vault.lockStake(lockAmt);

        vm.prank(engine);
        vault.slashStake(user1, slashAmt);

        uint256 remainingLocked = vault.getStakeAccount(user1).lockedAmount;
        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user1));

        // SAP-2: rounding the compensated burn down guarantees the user is never
        // left under-collateralised — their surviving value still covers any
        // remaining locked stake.
        assertGe(remainingAssets, remainingLocked, "Remaining assets must still cover remaining locked stake");
    }

    // ── Event Emission Assertions ──────────────────────────────────

    function test_lockStake_emitsStakeLocked() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ISapienVault.StakeLocked(user1, 400e18);

        vm.prank(user1);
        vault.lockStake(400e18);
    }

    function test_unlockStake_emitsStakeUnlocked() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ISapienVault.StakeUnlocked(user1, 150e18);

        vm.prank(engine);
        vault.unlockStake(user1, 150e18);
    }

    function test_slashStake_emitsStakeSlashed() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user1);
        vault.lockStake(400e18);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ISapienVault.StakeSlashed(user1, 100e18);

        vm.prank(engine);
        vault.slashStake(user1, 100e18);
    }

    function test_setMinDepositAge_emitsMinDepositAgeUpdated() public {
        // setUp set the guard to 0, so this transition is 0 -> 1 days.
        vm.expectEmit(true, true, false, true, address(vault));
        emit ISapienVault.MinDepositAgeUpdated(0, 1 days);

        vm.prank(admin);
        vault.setMinDepositAge(1 days);
    }

    /// @dev S3: a redundant set (new == stored) must not emit or write.
    function test_setMinDepositAge_noopDoesNotEmit() public {
        vm.prank(admin);
        vault.setMinDepositAge(2 days);

        vm.recordLogs();
        vm.prank(admin);
        vault.setMinDepositAge(2 days);
        assertEq(vm.getRecordedLogs().length, 0, "no-op set should not emit");
        assertEq(vault.minDepositAge(), 2 days);
    }

    // ── Multi-User Interaction Tests ───────────────────────────────

    function test_slashDoesNotReduceOtherUserBalance() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        vm.prank(user2);
        vault.deposit(DEPOSIT_AMOUNT, user2);

        uint256 user2BalBefore = vault.assetsOf(user2);

        vm.prank(user1);
        vault.lockStake(400e18);

        vm.prank(engine);
        vault.slashStake(user1, 400e18);

        assertGe(vault.assetsOf(user2), user2BalBefore, "Slash reduced other user's value");
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

    function test_selfTransfer_preservesMaturedShares() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        skip(1 days);

        uint256 bal = vault.balanceOf(user1);

        vm.prank(user1);
        vault.transfer(user1, bal);

        assertEq(vault.balanceOf(user1), bal, "Balance changed on self-transfer");

        // Age travels with the shares (even to oneself): matured shares stay
        // matured, so the lock succeeds and the timer is not re-armed.
        vm.prank(user1);
        vault.lockStake(400e18);
        assertEq(vault.getStakeAccount(user1).lockedAmount, 400e18);
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

        uint256 totalAssets = vault.assetsOf(user1);

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

    /// @dev S2: renouncing `DEFAULT_ADMIN_ROLE` is hard-disabled so the vault can
    ///      never be left without an admin. Admin handover must go through the
    ///      two-step, time-locked transfer flow instead.
    function test_adminRenounce_isDisabled() public {
        vm.expectRevert(ISapienVault.DefaultAdminRenounceDisabled.selector);
        vm.prank(admin);
        vault.renounceRole(ADMIN_ROLE, admin);

        // Admin retains all privileges.
        vm.prank(admin);
        vault.pause();
        assertTrue(vault.paused());
    }

    // ── SAP-1: Inbound Transfers Cannot Grief (Resolved) ───────────

    /// @dev SAP-1 resolved: an inbound dust transfer no longer resets the
    ///      victim's cooldown. Matured funds stay lockable and withdrawable in
    ///      the same block. (See test/audits/SAP1_SharesTransferGriefing.t.sol
    ///      for the full finding-level coverage.)
    function test_inboundDustTransferDoesNotFreezeVictim() public {
        vm.prank(admin);
        vault.setMinDepositAge(1 days);

        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);
        skip(1 days);

        // Attacker prepares and ages a dust share, then sends it to the victim.
        token.mint(user2, 1);
        vm.prank(user2);
        token.approve(address(vault), 1);
        vm.prank(user2);
        vault.deposit(1, user2);
        skip(1 days);
        vm.prank(user2);
        vault.transfer(user1, 1);

        // Victim is not frozen: matured funds remain withdrawable and lockable.
        assertGt(vault.maxWithdraw(user1), 0, "victim wrongly frozen by inbound dust");
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
        assertEq(vault.assetsOf(user1), amount);
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
    function testFuzz_maxWithdraw_preservesLockInvariant(uint256 depositAmt, uint256 donationAmt, uint256 lockAmt)
        public
    {
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
        assertGe(remainingAssets, vault.getStakeAccount(user1).lockedAmount, "Lock invariant violated");
    }

    /// @dev Fuzz test: for any deposit, donation, and lock, redeeming
    ///      maxRedeem must preserve the locked-amount invariant.
    function testFuzz_maxRedeem_preservesLockInvariant(uint256 depositAmt, uint256 donationAmt, uint256 lockAmt)
        public
    {
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
        assertGe(remainingAssets, vault.getStakeAccount(user1).lockedAmount, "Lock invariant violated after maxRedeem");
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

    // ── Transfer guard rounding-up fix tests ────────────────────────

    /// @dev Reproduce the undercollateralisation bug: with a high exchange rate,
    ///      convertToShares(lockedAmount) rounds down to 0, letting the user
    ///      transfer all shares despite having a non-zero lockedAmount.
    ///      After the fix (previewWithdraw rounds up), this transfer must revert.
    function test_transferGuard_preventsUndercollateralisation_highExchangeRate() public {
        vm.prank(user1);
        vault.deposit(1e18, user1);

        uint256 sharesBefore = vault.balanceOf(user1);
        assertGt(sharesBefore, 0, "User should have shares after deposit");

        token.mint(address(this), 1000e18);
        token.transfer(address(vault), 1000e18);

        vm.prank(user1);
        vault.lockStake(1);

        uint256 lockedShares = vault.previewWithdraw(1);
        assertGt(lockedShares, 0, "previewWithdraw should round up to at least 1 share");

        vm.expectRevert(ISapienVault.TransferExceedsUnlockedShares.selector);
        vm.prank(user1);
        vault.transfer(user2, sharesBefore);
    }

    /// @dev Even with small locked amounts and high exchange rate, the user
    ///      cannot transfer away shares that would leave lockedAmount undercollateralised.
    function test_transferGuard_roundUpReservation_smallLock() public {
        vm.prank(user1);
        vault.deposit(10e18, user1);

        token.mint(address(this), 10_000e18);
        token.transfer(address(vault), 10_000e18);

        uint256 userShares = vault.balanceOf(user1);
        uint256 userAssets = vault.convertToAssets(userShares);
        uint256 lockAmt = userAssets / 100;
        assertGt(lockAmt, 0, "lockAmt must be > 0");

        vm.prank(user1);
        vault.lockStake(lockAmt);

        uint256 lockedSharesNeeded = vault.previewWithdraw(lockAmt);
        uint256 maxTransferable = userShares > lockedSharesNeeded ? userShares - lockedSharesNeeded : 0;

        if (maxTransferable < userShares) {
            vm.expectRevert(ISapienVault.TransferExceedsUnlockedShares.selector);
            vm.prank(user1);
            vault.transfer(user2, userShares);
        }

        if (maxTransferable > 0) {
            vm.prank(user1);
            vault.transfer(user2, maxTransferable);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user1));
        uint256 locked = vault.getStakeAccount(user1).lockedAmount;
        assertGe(remainingAssets, locked, "Lock invariant violated after transfer");
    }

    /// @dev Verify that transferring exactly the unlocked portion succeeds
    ///      and the lock invariant holds, even after a large donation.
    function test_transferGuard_allowsMaxUnlocked_postDonation() public {
        vm.prank(user1);
        vault.deposit(100e18, user1);

        token.mint(address(this), 5000e18);
        token.transfer(address(vault), 5000e18);

        uint256 userShares = vault.balanceOf(user1);
        uint256 userAssets = vault.convertToAssets(userShares);
        uint256 lockAmt = userAssets / 2;

        vm.prank(user1);
        vault.lockStake(lockAmt);

        uint256 lockedSharesNeeded = vault.previewWithdraw(lockAmt);
        uint256 maxTransferable = userShares > lockedSharesNeeded ? userShares - lockedSharesNeeded : 0;

        if (maxTransferable > 0) {
            vm.prank(user1);
            vault.transfer(user2, maxTransferable);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user1));
        uint256 locked = vault.getStakeAccount(user1).lockedAmount;
        assertGe(remainingAssets, locked, "Lock invariant violated after max transfer");
    }

    /// @dev Fuzz test: after a donation that raises the exchange rate, the transfer
    ///      guard must never allow transferring shares that undercollateralise the lock.
    function testFuzz_transferGuard_roundUp_invariant(uint256 depositAmt, uint256 donationAmt, uint256 lockFraction)
        public
    {
        depositAmt = bound(depositAmt, 1e6, 1e24);
        donationAmt = bound(donationAmt, 1, 1e24);
        lockFraction = bound(lockFraction, 1, 1e18);

        token.mint(user1, depositAmt);
        vm.prank(user1);
        vault.deposit(depositAmt, user1);

        token.mint(address(this), donationAmt);
        token.transfer(address(vault), donationAmt);

        uint256 userShares = vault.balanceOf(user1);
        uint256 userAssets = vault.convertToAssets(userShares);
        uint256 lockAmt = (userAssets * lockFraction) / 1e18;
        if (lockAmt == 0 || lockAmt > userAssets) return;

        vm.prank(user1);
        vault.lockStake(lockAmt);

        uint256 lockedSharesNeeded = vault.previewWithdraw(lockAmt);
        uint256 maxTransferable = userShares > lockedSharesNeeded ? userShares - lockedSharesNeeded : 0;

        if (maxTransferable > 0) {
            vm.prank(user1);
            vault.transfer(user2, maxTransferable);
        }

        uint256 remainingAssets = vault.convertToAssets(vault.balanceOf(user1));
        uint256 locked = vault.getStakeAccount(user1).lockedAmount;
        assertGe(remainingAssets, locked, "Fuzz: lock invariant violated after transfer");
    }

    /// @dev Transferring all shares when nothing is locked should still work fine.
    function test_transferGuard_noLock_fullTransfer_postDonation() public {
        vm.prank(user1);
        vault.deposit(100e18, user1);

        token.mint(address(this), 5000e18);
        token.transfer(address(vault), 5000e18);

        uint256 userShares = vault.balanceOf(user1);

        vm.prank(user1);
        vault.transfer(user2, userShares);

        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.balanceOf(user2), userShares);
    }

    // ── ETH rescue (Aderyn H-1) ────────────────────────────────────────

    /// @dev Admin can recover ETH that lands on the proxy (e.g. via the inherited
    ///      payable `upgradeToAndCall`). Validates the H-1 mitigation.
    function test_rescueETH_adminCanRecover() public {
        address payable recipient = payable(makeAddr("recipient"));
        vm.deal(address(vault), 1 ether);

        assertEq(address(vault).balance, 1 ether);
        assertEq(recipient.balance, 0);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ISapienVault.EthRescued(recipient, 1 ether);

        vm.prank(admin);
        vault.rescueETH(recipient);

        assertEq(address(vault).balance, 0);
        assertEq(recipient.balance, 1 ether);
    }

    function test_rescueETH_revertsForNonAdmin() public {
        vm.deal(address(vault), 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user1, ADMIN_ROLE)
        );
        vm.prank(user1);
        vault.rescueETH(payable(user1));
    }

    function test_rescueETH_revertsOnZeroAddress() public {
        vm.deal(address(vault), 1 ether);

        vm.expectRevert(ISapienVault.ZeroAddress.selector);
        vm.prank(admin);
        vault.rescueETH(payable(address(0)));
    }

    function test_rescueETH_revertsWhenNoBalance() public {
        assertEq(address(vault).balance, 0);

        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vm.prank(admin);
        vault.rescueETH(payable(makeAddr("recipient")));
    }

    function test_rescueETH_revertsWhenRecipientRejects() public {
        EthRejector rejector = new EthRejector();
        vm.deal(address(vault), 1 ether);

        vm.expectRevert(ISapienVault.EthTransferFailed.selector);
        vm.prank(admin);
        vault.rescueETH(payable(address(rejector)));

        assertEq(address(vault).balance, 1 ether, "ETH must remain on revert");
    }

    function testFuzz_rescueETH_anyBalance(uint96 amount) public {
        vm.assume(amount > 0);
        address payable recipient = payable(makeAddr("recipient"));
        vm.deal(address(vault), amount);

        vm.prank(admin);
        vault.rescueETH(recipient);

        assertEq(address(vault).balance, 0);
        assertEq(recipient.balance, amount);
    }
}

/// @dev Receiver that always rejects ETH; used to exercise the rescue failure path.
contract EthRejector {
    receive() external payable {
        revert("nope");
    }
}
