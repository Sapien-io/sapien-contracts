// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {ISapienVault} from "../../src/interfaces/ISapienVault.sol";

/// @title Base-mainnet fork rehearsal of the V1 -> V2 UUPS upgrade (SEC-1)
/// @notice Executes the exact `upgradeToAndCall(newImpl, initializeV2(admin))`
///         calldata destined for the governance Safe against the *live* proxy
///         state on a Base mainnet fork — not against the hand-reconstructed
///         `SapienVaultV1` mock used by `test/SapienVaultMigration.t.sol`.
///         If any assumption the mock encodes by hand (storage slots, role
///         grants, timer semantics) diverges from the deployed V1, it surfaces
///         here instead of after an irreversible mainnet upgrade.
///
/// @dev Environment:
///        BASE_MAINNET_RPC_URL  - required; suite is skipped when unset so
///                                local/CI runs without an RPC stay green.
///        FORK_BLOCK            - optional; pin the fork block for determinism.
///        VAULT_ADMIN           - optional; defaults to the known mainnet admin.
///        FORK_HOLDERS          - optional; comma-separated real holder
///                                addresses to assert migration invariants on.
///
///      Run: BASE_MAINNET_RPC_URL=... forge test --match-path test/fork/UpgradeFork.t.sol -vvv
contract UpgradeForkTest is Test {
    /// @dev Live Base mainnet addresses (deployments/base-mainnet.json).
    address internal constant PROXY = 0x60Bf63729f688287a450299962b36Cef0aFfaa42;
    address internal constant SAPIEN = 0xC729777d0470F30612B1564Fd96E8Dd26f5814E3;
    /// @dev Known DEFAULT_ADMIN_ROLE holder (script/DeployBaseMainnet.s.sol).
    address internal constant KNOWN_ADMIN = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;

    /// @dev ERC-1967 implementation slot.
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    SapienVault internal vault = SapienVault(PROXY);
    address internal admin;
    address[] internal holders;
    bool internal forkEnabled;

    function setUp() public {
        string memory rpc = vm.envOr("BASE_MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) return; // tests skip via the modifier

        uint256 forkBlock = vm.envOr("FORK_BLOCK", uint256(0));
        if (forkBlock > 0) {
            vm.createSelectFork(rpc, forkBlock);
        } else {
            vm.createSelectFork(rpc);
        }
        forkEnabled = true;

        admin = vm.envOr("VAULT_ADMIN", KNOWN_ADMIN);
        holders = vm.envOr("FORK_HOLDERS", ",", new address[](0));

        // Sanity: the supplied admin must hold the role on the live V1, and the
        // proxy must still be pre-upgrade (initializeV2 is reinitializer(2), so
        // a second run on an already-upgraded proxy would revert differently).
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), "fork: admin does not hold DEFAULT_ADMIN_ROLE");
    }

    modifier onlyFork() {
        vm.skip(!forkEnabled);
        _;
    }

    /// @dev Build and execute the exact Safe payload: a raw call of
    ///      `upgradeToAndCall(newImpl, initializeV2(admin))` from the admin.
    function _executeUpgrade() internal returns (address newImpl) {
        newImpl = address(new SapienVault());
        bytes memory initData = abi.encodeCall(SapienVault.initializeV2, (admin));
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, initData);

        vm.prank(admin);
        (bool ok,) = PROXY.call(upgradeCalldata);
        assertTrue(ok, "fork: upgradeToAndCall failed");
    }

    /// @notice Core rehearsal: real state in, exact calldata, script-equivalent
    ///         post-upgrade assertions plus migration invariants on real holders.
    function test_fork_upgrade_stateAndAdminSeeding() public onlyFork {
        uint256 supplyBefore = vault.totalSupply();
        uint256 assetsBefore = vault.totalAssets();
        uint256 minAgeBefore = vault.minDepositAge();

        uint256 n = holders.length;
        uint256[] memory balBefore = new uint256[](n);
        uint256[] memory lockedBefore = new uint256[](n);
        for (uint256 i; i < n; ++i) {
            balBefore[i] = vault.balanceOf(holders[i]);
            lockedBefore[i] = vault.getStakeAccount(holders[i]).lockedAmount;
        }

        address newImpl = _executeUpgrade();

        // Mirror of script/UpgradeVault.s.sol _verify().
        assertTrue(vault.verifyStorageLocation(), "verify: ERC-7201 storage slot mismatch");
        assertEq(vault.defaultAdmin(), admin, "verify: defaultAdmin not seeded to admin");
        assertEq(vault.owner(), admin, "verify: owner() mismatch");
        assertGt(vault.minDepositAge(), 0, "verify: minDepositAge not seeded (SAP-5)");
        assertEq(vault.defaultAdminDelay(), vault.DEFAULT_ADMIN_TRANSFER_DELAY(), "verify: admin delay not seeded");
        assertEq(
            address(uint160(uint256(vm.load(PROXY, IMPLEMENTATION_SLOT)))),
            newImpl,
            "verify: implementation slot != new impl"
        );

        // A pre-upgrade admin-configured minDepositAge must be preserved, not clobbered.
        if (minAgeBefore > 0) {
            assertEq(vault.minDepositAge(), minAgeBefore, "verify: pre-upgrade minDepositAge clobbered");
        }

        // Upgrade moves no value and mints/burns nothing.
        assertEq(vault.totalSupply(), supplyBefore, "verify: totalSupply changed");
        assertEq(vault.totalAssets(), assetsBefore, "verify: totalAssets changed");

        // Real-holder migration invariants (lazy migration is view-consistent
        // before first touch and write-consistent after).
        for (uint256 i; i < n; ++i) {
            address u = holders[i];
            assertEq(vault.balanceOf(u), balBefore[i], "holder: balance changed by upgrade");
            assertEq(vault.getStakeAccount(u).lockedAmount, lockedBefore[i], "holder: locked stake changed");
            assertEq(
                vault.maturedShares(u) + vault.pendingShares(u),
                vault.balanceOf(u),
                "holder: matured + pending != balanceOf (view)"
            );
            // First post-upgrade touch triggers _lazyMigrate; invariant must hold after.
            vm.prank(u);
            vault.transfer(u, 0);
            assertEq(
                vault.maturedShares(u) + vault.pendingShares(u),
                vault.balanceOf(u),
                "holder: matured + pending != balanceOf (post-touch)"
            );
        }

        // reinitializer(2) is consumed: the Safe cannot run initializeV2 twice.
        vm.prank(admin);
        vm.expectRevert();
        vault.initializeV2(admin);
    }

    /// @notice A depositor whose state was written by the *live V1 bytecode*
    ///         (not the mock) migrates with its cooldown preserved and can
    ///         withdraw once aged.
    function test_fork_upgrade_syntheticDepositorLifecycle() public onlyFork {
        address user = makeAddr("forkDepositor");
        uint256 amount = 1_000e18;

        deal(SAPIEN, user, amount);
        vm.startPrank(user);
        IERC20(SAPIEN).approve(PROXY, amount);
        // Self-deposit through the live V1 implementation stamps the legacy
        // lastDepositTimestamp — exactly the storage _lazyMigrate must honor.
        uint256 shares = vault.deposit(amount, user);
        vm.stopPrank();
        assertGt(shares, 0, "fork: live V1 deposit minted no shares");

        uint256 minAgeBefore = vault.minDepositAge();

        _executeUpgrade();

        uint256 minAge = vault.minDepositAge();
        if (minAgeBefore > 0) {
            // Mid-cooldown at upgrade: still immature, age preserved not reset.
            assertEq(vault.maturedShares(user), 0, "fork: fresh deposit should be immature");
            assertEq(vault.pendingShares(user), shares, "fork: pending != minted shares");
            assertEq(vault.maxWithdraw(user), 0, "fork: fresh deposit withdrawable too early");
        }

        skip(minAge);
        assertEq(vault.maturedShares(user), shares, "fork: shares did not mature");
        uint256 maxOut = vault.maxWithdraw(user);
        assertGt(maxOut, 0, "fork: matured holder cannot withdraw");

        vm.prank(user);
        vault.withdraw(maxOut, user, user);
        assertEq(IERC20(SAPIEN).balanceOf(user), maxOut, "fork: withdraw did not pay out");
    }

    /// @notice The upgrade calldata cannot smuggle in a fresh admin: initializeV2
    ///         rejects an address that does not already hold the role on the
    ///         live vault (S2).
    function test_fork_upgrade_initializeV2RejectsNonAdmin() public onlyFork {
        address newImpl = address(new SapienVault());
        address notAdmin = makeAddr("notAdmin");
        bytes memory initData = abi.encodeCall(SapienVault.initializeV2, (notAdmin));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.NotCurrentAdmin.selector, notAdmin));
        SapienVault(PROXY).upgradeToAndCall(newImpl, initData);
    }
}
