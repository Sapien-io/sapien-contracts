// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {ISapienVault} from "../src/interfaces/ISapienVault.sol";
import {SapienVaultV1} from "./mocks/SapienVaultV1.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

/// @title SapienVault SAP-1 upgrade/migration tests
/// @notice Proves the live UUPS upgrade from the legacy global-timer
///         implementation to the tranche model preserves balances, locked
///         stake, and each user's pre-upgrade age, and that the
///         `maturedShares + pendingShares == balanceOf` accounting invariant
///         holds on first post-upgrade touch.
contract SapienVaultMigrationTest is Test {
    SapienVaultV1 internal v1Impl;
    SapienVault internal v2Impl;
    SapienVault internal vault; // proxy
    MockERC20 internal token;

    address internal admin = makeAddr("admin");
    address internal engine = makeAddr("engine");
    address internal aged = makeAddr("aged"); // matured + locked pre-upgrade
    address internal fresh = makeAddr("fresh"); // mid-cooldown pre-upgrade
    address internal recipient = makeAddr("recipient"); // got shares via transfer
    address internal exempt = makeAddr("exempt"); // delegated deposit: ts==0 pre-upgrade

    uint256 internal constant MIN_AGE = 1 days;
    uint256 internal constant AMOUNT = 1000e18;

    function setUp() public {
        vm.warp(365 days);
        token = new MockERC20("Sapien Token", "SAPIEN");

        v1Impl = new SapienVaultV1();
        bytes memory initData = abi.encodeCall(SapienVaultV1.initialize, (IERC20(address(token)), admin));
        address proxy = address(new ERC1967Proxy(address(v1Impl), initData));
        vault = SapienVault(proxy);

        SapienVaultV1 v1 = SapienVaultV1(proxy);
        vm.startPrank(admin);
        v1.grantRole(v1.ENGINE_ROLE(), engine);
        v1.setMinDepositAge(MIN_AGE);
        vm.stopPrank();

        for (uint256 i; i < 3; ++i) {
            address u = [aged, fresh, recipient][i];
            token.mint(u, AMOUNT * 10);
            vm.prank(u);
            token.approve(proxy, type(uint256).max);
        }

        // aged: deposits, matures, locks 400 (all under V1).
        vm.prank(aged);
        v1.deposit(AMOUNT, aged);
        skip(MIN_AGE);
        vm.prank(aged);
        v1.lockStake(400e18);

        // recipient: receives shares via transfer from aged (V1 sets its timer
        // on receipt). Do this right after aged matured so the transfer passes.
        vm.prank(aged);
        v1.transfer(recipient, 100e18);

        // exempt: receives a *delegated* deposit (caller != receiver), which under
        // V1 never stamps the receiver's lastDepositTimestamp. This reproduces the
        // legacy "exempt" holder (ts == 0) that migrates as fully mature.
        vm.prank(aged);
        v1.deposit(AMOUNT, exempt);
        assertEq(v1.lastDepositTimestamp(exempt), 0, "exempt should have no V1 timer");

        // fresh: deposits just 12h before the upgrade (still mid-cooldown).
        skip(MIN_AGE - 12 hours);
        vm.prank(fresh);
        v1.deposit(AMOUNT, fresh);
        skip(12 hours);
    }

    function _upgrade() internal {
        v2Impl = new SapienVault();
        vm.prank(admin);
        vault.upgradeToAndCall(address(v2Impl), abi.encodeCall(SapienVault.initializeV2, (admin)));
    }

    function test_migration_preservesBalancesAndLockedStake() public {
        uint256 agedBal = vault.balanceOf(aged);
        uint256 freshBal = vault.balanceOf(fresh);
        uint256 recipientBal = vault.balanceOf(recipient);

        _upgrade();

        assertEq(vault.balanceOf(aged), agedBal, "aged balance changed");
        assertEq(vault.balanceOf(fresh), freshBal, "fresh balance changed");
        assertEq(vault.balanceOf(recipient), recipientBal, "recipient balance changed");
        assertEq(vault.getStakeAccount(aged).lockedAmount, 400e18, "locked stake not preserved");
    }

    function test_migration_preservesAgedWithdrawability() public {
        _upgrade();

        // aged matured pre-upgrade: available (balance minus locked) withdrawable now.
        assertGt(vault.maxWithdraw(aged), 0, "aged should remain withdrawable after upgrade");
        // recipient received shares >12h before upgrade but <1 day; its V1 timer
        // was set on receipt, so it should still be maturing right after upgrade.
        // (Set during the same block aged matured, then skip(MIN_AGE-12h)+12h = MIN_AGE.)
        assertGt(vault.maturedShares(recipient), 0, "recipient shares should have matured");
    }

    function test_migration_preservesFreshCooldown() public {
        _upgrade();

        // fresh was 12h into a 1-day cooldown at upgrade: still locked out.
        assertEq(vault.maxWithdraw(fresh), 0, "fresh should still be in cooldown");
        assertEq(vault.maturedShares(fresh), 0, "fresh shares should be immature");

        // Age is preserved (not reset by the upgrade): matures 12h later.
        skip(12 hours);
        assertGt(vault.maxWithdraw(fresh), 0, "fresh should mature after remaining cooldown");
        assertEq(vault.pendingShares(fresh), 0, "no pending shares after maturing");
    }

    function test_migration_accountingInvariantHolds() public {
        _upgrade();

        address[3] memory users = [aged, fresh, recipient];
        for (uint256 i; i < users.length; ++i) {
            address u = users[i];
            // Touch the account to trigger lazy migration into tranche storage.
            vm.prank(u);
            vault.transfer(u, 0);
            assertEq(
                vault.maturedShares(u) + vault.pendingShares(u), vault.balanceOf(u), "matured + pending != balanceOf"
            );
        }
    }

    function test_migration_cannotReinitialize() public {
        _upgrade();
        vm.expectRevert();
        vault.initializeV2(admin);
    }

    /// @notice S2: the upgrade seeds `AccessControlDefaultAdminRules` storage to
    ///         the incumbent admin, so `defaultAdmin()` / `owner()` resolve and
    ///         renouncing `DEFAULT_ADMIN_ROLE` is hard-disabled post-upgrade.
    function test_migration_seedsDefaultAdminRules() public {
        _upgrade();

        assertEq(vault.defaultAdmin(), admin, "default admin not seeded");
        assertEq(vault.owner(), admin, "owner not seeded");
        assertEq(vault.defaultAdminDelay(), vault.DEFAULT_ADMIN_TRANSFER_DELAY(), "delay not seeded");

        bytes32 adminRole = vault.DEFAULT_ADMIN_ROLE();
        vm.expectRevert(ISapienVault.DefaultAdminRenounceDisabled.selector);
        vm.prank(admin);
        vault.renounceRole(adminRole, admin);
    }

    /// @notice S2: `initializeV2` only blesses an address that already holds the
    ///         role on the live vault, so the upgrade calldata cannot smuggle in a
    ///         fresh admin.
    function test_migration_initializeV2RejectsNonAdmin() public {
        v2Impl = new SapienVault();
        address notAdmin = makeAddr("notAdmin");
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.NotCurrentAdmin.selector, notAdmin));
        vault.upgradeToAndCall(address(v2Impl), abi.encodeCall(SapienVault.initializeV2, (notAdmin)));
    }

    /// @notice A pre-upgrade holder whose V1 `lastDepositTimestamp` was never set
    ///         (e.g. shares acquired via a delegated deposit) migrates as fully
    ///         mature: all shares are immediately mature and none are pending.
    ///         Exercises the `ts == 0` exempt branch in `_matureSharesView`,
    ///         `pendingShares`, and `_lazyMigrate`.
    function test_migration_exemptHolderIsFullyMature() public {
        uint256 exemptBal = vault.balanceOf(exempt);
        assertGt(exemptBal, 0, "exempt should hold shares pre-upgrade");

        _upgrade();

        // Views run before the first touch, so `migrated[exempt]` is still false
        // and these hit the legacy ts == 0 fast paths.
        assertEq(vault.maturedShares(exempt), exemptBal, "exempt shares should be fully mature");
        assertEq(vault.pendingShares(exempt), 0, "exempt should have no pending shares");

        // First touch triggers _lazyMigrate's ts == 0 branch (mature = balance).
        vm.prank(exempt);
        vault.transfer(exempt, 0);
        assertEq(vault.maturedShares(exempt), exemptBal, "mature preserved after lazy migration");
        assertEq(
            vault.maturedShares(exempt) + vault.pendingShares(exempt),
            vault.balanceOf(exempt),
            "matured + pending != balanceOf"
        );

        // Exempt shares are immediately withdrawable post-migration.
        assertEq(vault.maxWithdraw(exempt), vault.convertToAssets(exemptBal), "exempt fully withdrawable");
    }

    /// @notice If the pre-upgrade vault never configured `minDepositAge` (left at
    ///         the default 0), the V2 reinitializer seeds the MEV guard with
    ///         `DEFAULT_MIN_DEPOSIT_AGE` (SAP-5). Exercises the `== 0` branch in
    ///         `initializeV2`.
    function test_migration_initializeV2SeedsDefaultWhenUnset() public {
        SapienVaultV1 freshImpl = new SapienVaultV1();
        bytes memory initData = abi.encodeCall(SapienVaultV1.initialize, (IERC20(address(token)), admin));
        address proxy = address(new ERC1967Proxy(address(freshImpl), initData));
        SapienVault freshVault = SapienVault(proxy);

        // Note: no setMinDepositAge call, so the legacy vault leaves it at 0.
        SapienVault impl = new SapienVault();
        vm.prank(admin);
        freshVault.upgradeToAndCall(address(impl), abi.encodeCall(SapienVault.initializeV2, (admin)));

        assertEq(
            freshVault.minDepositAge(),
            freshVault.DEFAULT_MIN_DEPOSIT_AGE(),
            "initializeV2 should seed default when unset"
        );
    }
}
