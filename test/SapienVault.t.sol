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
}
