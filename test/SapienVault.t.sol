// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {StakeAccount} from "src/Types.sol";

contract SapienVaultTest is Test {
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public engine = makeAddr("engine");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant DEPOSIT_AMOUNT = 1000e18;

    function setUp() public {
        token = new MockERC20("Sapien Token", "SPN");

        SapienVault vaultImpl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), initData)));

        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), engine);
        vm.stopPrank();

        // Setup user balances
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
        assertEq(vault.totalStaked(user1), DEPOSIT_AMOUNT);
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

    // ── Contributor Lock ───────────────────────────────────────────

    function test_lockContributor() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(engine);
        vault.lockContributor(user1, 500e18);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.contributorLock, 500e18);
        assertEq(vault.availableBalance(user1), DEPOSIT_AMOUNT - 500e18);
    }

    function test_unlockContributor() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.startPrank(engine);
        vault.lockContributor(user1, 500e18);
        vault.unlockContributor(user1, 200e18);
        vm.stopPrank();

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.contributorLock, 300e18);
    }

    function test_slashContributor() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 sharesBefore = vault.balanceOf(user1);

        vm.startPrank(engine);
        vault.lockContributor(user1, 500e18);
        vault.slashContributor(user1, 200e18);
        vm.stopPrank();

        uint256 sharesAfter = vault.balanceOf(user1);
        assertLt(sharesAfter, sharesBefore);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.contributorLock, 300e18);
    }

    function test_lockContributor_revertsInsufficientBalance() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(engine);
        vm.expectRevert();
        vault.lockContributor(user1, DEPOSIT_AMOUNT + 1);
    }

    // ── Validator Capacity ─────────────────────────────────────────

    function test_lockValidatorCapacity() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(engine);
        vault.lockValidatorCapacity(user1, 400e18);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.validatorCapacity, 400e18);
    }

    function test_unlockValidatorCapacity() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.startPrank(engine);
        vault.lockValidatorCapacity(user1, 400e18);
        vault.unlockValidatorCapacity(user1, 150e18);
        vm.stopPrank();

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.validatorCapacity, 250e18);
    }

    // ── In-Flight Stake ────────────────────────────────────────────

    function test_commitStake() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.startPrank(engine);
        vault.lockValidatorCapacity(user1, 400e18);
        vault.commitStake(user1, 200e18);
        vm.stopPrank();

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.validatorCapacity, 200e18);
        assertEq(acct.inFlight, 200e18);
    }

    function test_releaseCommit() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.startPrank(engine);
        vault.lockValidatorCapacity(user1, 400e18);
        vault.commitStake(user1, 200e18);
        vault.releaseCommit(user1, 200e18);
        vm.stopPrank();

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.validatorCapacity, 400e18);
        assertEq(acct.inFlight, 0);
    }

    function test_slashValidator() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 sharesBefore = vault.balanceOf(user1);

        vm.startPrank(engine);
        vault.lockValidatorCapacity(user1, 400e18);
        vault.commitStake(user1, 200e18);
        vault.slashValidator(user1, 100e18);
        vm.stopPrank();

        uint256 sharesAfter = vault.balanceOf(user1);
        assertLt(sharesAfter, sharesBefore);

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.inFlight, 100e18);
    }

    // ── Withdrawal Guard ───────────────────────────────────────────

    function test_cannotWithdrawLockedFunds() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(engine);
        vault.lockContributor(user1, 800e18);

        // Try to withdraw more than available
        uint256 maxW = vault.maxRedeem(user1);
        uint256 maxAssets = vault.convertToAssets(maxW);
        assertLe(maxAssets, DEPOSIT_AMOUNT - 800e18);
    }

    // ── Access Control ─────────────────────────────────────────────

    function test_onlyEngineCanLock() public {
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        vm.prank(user1);
        vm.expectRevert();
        vault.lockContributor(user1, 500e18);
    }

    // ── Decimals Offset ────────────────────────────────────────────

    function test_decimalsOffset() public view {
        // Vault should use 3 decimal offset for inflation protection
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
        vm.prank(user1);
        vm.expectRevert();
        vault.pause();
    }

    // ── Transfer Guard Rounding Fix ────────────────────────────────

    function test_transferGuard_roundsUpLockedShares() public {
        // Deposit a meaningful amount so user1 has shares
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 initialShares = vault.balanceOf(user1);

        // Donate assets directly to the vault to inflate the exchange rate.
        // This makes each share worth many more assets, so a small locked
        // asset amount maps to a fractional share that rounds down to 0
        // under the old (buggy) code.
        uint256 donationAmount = 100_000e18;
        token.mint(address(vault), donationAmount);

        // Lock a small contributor amount — small enough that
        // convertToShares (round-down) would yield 0, but the lock is non-zero.
        uint256 lockAmount = 1; // 1 wei of asset
        vm.prank(engine);
        vault.lockContributor(user1, lockAmount);

        // Verify the lock is active
        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.contributorLock, lockAmount);

        // The user should NOT be able to transfer ALL shares because some
        // are needed to back the locked amount. With rounding-up, at least
        // 1 share must be reserved.
        vm.prank(user1);
        vm.expectRevert();
        vault.transfer(user2, initialShares);
    }

    function test_transferGuard_preventsUndercollateralisation_highExchangeRate() public {
        // Step 1: Deposit and get shares
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 initialShares = vault.balanceOf(user1);

        // Step 2: Donate to vault to raise exchange rate dramatically
        // After donation, 1 share represents many more assets
        uint256 donationAmount = 1_000_000e18;
        token.mint(address(vault), donationAmount);

        // Step 3: Lock some amount via contributor lock
        uint256 lockAmount = 100e18;
        vm.prank(engine);
        vault.lockContributor(user1, lockAmount);

        // Step 4: Verify convertToShares(lockAmount) rounds DOWN to fewer
        // shares than needed. The old code used this value.
        uint256 roundedDownShares = vault.convertToShares(lockAmount);

        // Step 5: previewWithdraw gives the correct rounding-up share count
        // that is needed to cover `lockAmount` assets
        uint256 roundedUpShares = vault.previewWithdraw(lockAmount);

        // The rounding-up count should be >= the rounding-down count
        assertGe(roundedUpShares, roundedDownShares);

        // Step 6: Try to transfer shares that would leave only
        // roundedDownShares behind (insufficient). Should revert.
        if (roundedDownShares < roundedUpShares) {
            uint256 transferAmount = initialShares - roundedDownShares;
            vm.prank(user1);
            vm.expectRevert();
            vault.transfer(user2, transferAmount);
        }

        // Step 7: Transferring shares that leave roundedUpShares behind
        // should succeed.
        uint256 safeTransfer = initialShares - roundedUpShares;
        if (safeTransfer > 0) {
            vm.prank(user1);
            vault.transfer(user2, safeTransfer);
            assertGe(vault.balanceOf(user1), roundedUpShares);
        }
    }

    function test_transferGuard_allLocksRoundUp() public {
        // Test that all three lock types are protected by rounding-up
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 initialShares = vault.balanceOf(user1);

        // Inflate exchange rate
        token.mint(address(vault), 500_000e18);

        // Lock via all three mechanisms
        vm.startPrank(engine);
        vault.lockContributor(user1, 1);
        vault.lockValidatorCapacity(user1, 1);
        vm.stopPrank();

        StakeAccount memory acct = vault.getStakeAccount(user1);
        uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
        assertEq(totalLocked, 2);

        // Should not be able to transfer all shares
        vm.prank(user1);
        vm.expectRevert();
        vault.transfer(user2, initialShares);
    }

    function test_transferGuard_noLocks_fullTransferAllowed() public {
        // With no locks, full transfer should always be allowed
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 initialShares = vault.balanceOf(user1);

        // Inflate exchange rate
        token.mint(address(vault), 500_000e18);

        // No locks — full transfer should succeed
        vm.prank(user1);
        vault.transfer(user2, initialShares);

        assertEq(vault.balanceOf(user1), 0);
        assertEq(vault.balanceOf(user2), initialShares);
    }

    function test_transferGuard_exactLockedSharesBoundary() public {
        // Test the exact boundary: transferring all but the exact
        // rounding-up locked shares should succeed, but one more should fail.
        vm.prank(user1);
        vault.deposit(DEPOSIT_AMOUNT, user1);

        uint256 initialShares = vault.balanceOf(user1);

        // Moderate donation to create a non-trivial exchange rate
        token.mint(address(vault), 50_000e18);

        uint256 lockAmount = 500e18;
        vm.prank(engine);
        vault.lockContributor(user1, lockAmount);

        // The correct locked shares with rounding-up
        uint256 neededShares = vault.previewWithdraw(lockAmount);

        // Transferring up to (initialShares - neededShares) should succeed
        uint256 maxTransferable = initialShares - neededShares;
        if (maxTransferable > 0) {
            vm.prank(user1);
            vault.transfer(user2, maxTransferable);
        }

        // Now user1 has exactly neededShares left
        assertEq(vault.balanceOf(user1), neededShares);

        // Transferring even 1 more share should fail
        vm.prank(user1);
        vm.expectRevert();
        vault.transfer(user2, 1);
    }
}
