// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {ISapienVault} from "../../src/interfaces/ISapienVault.sol";

/// @title Base-Sepolia fork rehearsal of the V1 -> V2 UUPS upgrade
/// @notice Same shape as `UpgradeFork.t.sol`, but against the retired Sepolia
///         V1 proxy (`0x58E72…`) which already holds real depositor state.
///         Defaults to forking one block *before* the on-chain V2 upgrade
///         (block 44794238 → impl `0x345999cc…`) so `initializeV2` is still
///         available. Tip-of-chain is already V2 — see
///         `test_fork_tip_initializeV2AlreadyConsumed`.
///
/// @dev Environment:
///        BASE_SEPOLIA_RPC_URL / FORK_RPC_URL — required; suite skips when unset.
///        FORK_BLOCK                          — optional; default 44794237.
///        VAULT_ADMIN                         — optional; defaults to the Safe.
///        FORK_HOLDERS                        — optional; comma-separated holders.
///
///      Anvil:
///        anvil --fork-url $BASE_SEPOLIA_RPC_URL --fork-block-number 44794237
///        FORK_RPC_URL=http://127.0.0.1:8545 forge test \
///          --match-path test/fork/SepoliaUpgradeFork.t.sol -vvv
contract SepoliaUpgradeForkTest is Test {
    address internal constant PROXY = 0x58E72Fa7fb92B100f2c652377465EEEe2642544C;
    address internal constant SAPIEN = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6;
    address internal constant KNOWN_ADMIN = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    /// @dev Last V1 block; V2 upgrade landed in 44794238.
    uint256 internal constant PRE_UPGRADE_BLOCK = 44794237;

    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    SapienVault internal vault = SapienVault(PROXY);
    address internal admin;
    address[] internal holders;
    bool internal forkEnabled;
    uint256 internal forkBlock;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            rpc = vm.envOr("BASE_SEPOLIA_RPC_URL", string(""));
        }
        if (bytes(rpc).length == 0) return;

        // When pointing at a local anvil that was already started with
        // --fork-block-number, FORK_BLOCK=0 means "use whatever tip anvil has".
        forkBlock = vm.envOr("FORK_BLOCK", PRE_UPGRADE_BLOCK);
        if (forkBlock > 0) {
            vm.createSelectFork(rpc, forkBlock);
        } else {
            vm.createSelectFork(rpc);
        }
        forkEnabled = true;

        admin = vm.envOr("VAULT_ADMIN", KNOWN_ADMIN);
        holders = vm.envOr("FORK_HOLDERS", ",", new address[](0));

        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), "fork: admin does not hold DEFAULT_ADMIN_ROLE");
    }

    modifier onlyFork() {
        vm.skip(!forkEnabled);
        _;
    }

    function _executeUpgrade() internal returns (address newImpl) {
        newImpl = address(new SapienVault());
        bytes memory initData = abi.encodeCall(SapienVault.initializeV2, (admin));
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, initData);

        vm.prank(admin);
        (bool ok,) = PROXY.call(upgradeCalldata);
        assertTrue(ok, "fork: upgradeToAndCall failed");
    }

    function test_fork_upgrade_stateAndAdminSeeding() public onlyFork {
        // Guard: this suite expects a pre-initializeV2 (V1) tip.
        (bool hasDefaultAdmin,) = PROXY.staticcall(abi.encodeWithSignature("defaultAdmin()"));
        assertFalse(hasDefaultAdmin, "fork: tip is already V2; pin FORK_BLOCK to PRE_UPGRADE_BLOCK");

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

        if (minAgeBefore > 0) {
            assertEq(vault.minDepositAge(), minAgeBefore, "verify: pre-upgrade minDepositAge clobbered");
        }

        assertEq(vault.totalSupply(), supplyBefore, "verify: totalSupply changed");
        assertEq(vault.totalAssets(), assetsBefore, "verify: totalAssets changed");

        for (uint256 i; i < n; ++i) {
            address u = holders[i];
            assertEq(vault.balanceOf(u), balBefore[i], "holder: balance changed by upgrade");
            assertEq(vault.getStakeAccount(u).lockedAmount, lockedBefore[i], "holder: locked stake changed");
            assertEq(
                vault.maturedShares(u) + vault.pendingShares(u),
                vault.balanceOf(u),
                "holder: matured + pending != balanceOf (view)"
            );
            vm.prank(u);
            vault.transfer(u, 0);
            assertEq(
                vault.maturedShares(u) + vault.pendingShares(u),
                vault.balanceOf(u),
                "holder: matured + pending != balanceOf (post-touch)"
            );
        }

        vm.prank(admin);
        vm.expectRevert();
        vault.initializeV2(admin);
    }

    function test_fork_upgrade_syntheticDepositorLifecycle() public onlyFork {
        (bool hasDefaultAdmin,) = PROXY.staticcall(abi.encodeWithSignature("defaultAdmin()"));
        assertFalse(hasDefaultAdmin, "fork: tip is already V2; pin FORK_BLOCK to PRE_UPGRADE_BLOCK");

        address user = makeAddr("forkDepositor");
        uint256 amount = 1_000e18;

        deal(SAPIEN, user, amount);
        vm.startPrank(user);
        IERC20(SAPIEN).approve(PROXY, amount);
        uint256 shares = vault.deposit(amount, user);
        vm.stopPrank();
        assertGt(shares, 0, "fork: live V1 deposit minted no shares");

        uint256 minAgeBefore = vault.minDepositAge();

        _executeUpgrade();

        uint256 minAge = vault.minDepositAge();
        if (minAgeBefore > 0) {
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

    function test_fork_upgrade_initializeV2RejectsNonAdmin() public onlyFork {
        (bool hasDefaultAdmin,) = PROXY.staticcall(abi.encodeWithSignature("defaultAdmin()"));
        assertFalse(hasDefaultAdmin, "fork: tip is already V2; pin FORK_BLOCK to PRE_UPGRADE_BLOCK");

        address newImpl = address(new SapienVault());
        address notAdmin = makeAddr("notAdmin");
        bytes memory initData = abi.encodeCall(SapienVault.initializeV2, (notAdmin));

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.NotCurrentAdmin.selector, notAdmin));
        SapienVault(PROXY).upgradeToAndCall(newImpl, initData);
    }
}
