// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {SapienVault} from "../../src/SapienVault.sol";

/// @title Base-Sepolia fork of the live V2 vault
/// @notice The V1 → V2 UUPS upgrade (`initializeV2`) has already been executed
///         on this same proxy. This suite does **not** replay that calldata.
///         It asserts the same post-upgrade invariants as `UpgradeFork.t.sol`.
///
/// @dev Environment:
///        BASE_SEPOLIA_RPC_URL / FORK_RPC_URL — required; suite skips when unset.
///        FORK_BLOCK                          — optional; pin for determinism.
///        VAULT_ADMIN                         — optional; defaults to the Safe.
///        FORK_HOLDERS                        — optional; comma-separated holders.
///
///      Run: BASE_SEPOLIA_RPC_URL=... forge test --match-path test/fork/SepoliaUpgradeFork.t.sol -vvv
contract SepoliaUpgradeForkTest is Test {
    /// @dev Live Base Sepolia proxy (deployments/base-sepolia.json). V2 is a
    ///      UUPS implementation swap; the proxy address does not change.
    address internal constant PROXY = 0x58E72Fa7fb92B100f2c652377465EEEe2642544C;
    address internal constant SAPIEN = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6;
    address internal constant KNOWN_ADMIN = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;

    SapienVault internal vault = SapienVault(PROXY);
    address internal admin;
    address[] internal holders;
    bool internal forkEnabled;

    function setUp() public {
        string memory rpc = vm.envOr("FORK_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            rpc = vm.envOr("BASE_SEPOLIA_RPC_URL", string(""));
        }
        if (bytes(rpc).length == 0) return;

        uint256 forkBlock = vm.envOr("FORK_BLOCK", uint256(0));
        if (forkBlock > 0) {
            vm.createSelectFork(rpc, forkBlock);
        } else {
            vm.createSelectFork(rpc);
        }
        forkEnabled = true;

        admin = vm.envOr("VAULT_ADMIN", KNOWN_ADMIN);
        holders = vm.envOr("FORK_HOLDERS", ",", new address[](0));
    }

    modifier onlyFork() {
        vm.skip(!forkEnabled);
        _;
    }

    function test_fork_liveV2_adminAndPause() public onlyFork {
        assertTrue(vault.verifyStorageLocation(), "fork: ERC-7201 storage slot mismatch");
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), "fork: admin missing DEFAULT_ADMIN_ROLE");
        assertEq(vault.defaultAdmin(), admin, "fork: defaultAdmin != expected Safe");
        assertEq(vault.owner(), admin, "fork: owner() != expected Safe");
        assertEq(
            vault.defaultAdminDelay(), vault.DEFAULT_ADMIN_TRANSFER_DELAY(), "fork: admin delay not the S2 default"
        );
        assertFalse(vault.paused(), "fork: live vault is paused");
        assertEq(vault.maxDeposit(address(0)), type(uint256).max, "fork: maxDeposit gated while unpaused");
    }

    function test_fork_liveV2_minDepositAge() public onlyFork {
        uint256 minAge = vault.minDepositAge();
        assertGt(minAge, 0, "fork: minDepositAge disabled on live V2");
        assertEq(minAge, vault.DEFAULT_MIN_DEPOSIT_AGE(), "fork: minDepositAge != DEFAULT_MIN_DEPOSIT_AGE");
        assertLe(minAge, vault.MAX_MIN_DEPOSIT_AGE(), "fork: minDepositAge above MAX_MIN_DEPOSIT_AGE");
    }

    function test_fork_liveV2_shareRate() public onlyFork {
        assertEq(address(vault.asset()), SAPIEN, "fork: asset() != SAPIEN");
        uint256 assets = vault.totalAssets();
        uint256 supply = vault.totalSupply();
        assertEq(assets, IERC20(SAPIEN).balanceOf(PROXY), "fork: totalAssets != token balance");
        assertGt(supply, 0, "fork: live vault has no shares");
        assertGt(assets, 0, "fork: live vault has no assets");

        uint256 oneShare = 10 ** vault.decimals();
        uint256 assetsPerShare = vault.convertToAssets(oneShare);
        assertGt(assetsPerShare, 0, "fork: convertToAssets(1 share) is zero");
        assertEq(vault.convertToAssets(0), 0, "fork: convertToAssets(0) != 0");
    }

    function test_fork_liveV2_trancheSplit() public onlyFork {
        for (uint256 i; i < holders.length; ++i) {
            address u = holders[i];
            assertEq(
                vault.maturedShares(u) + vault.pendingShares(u),
                vault.balanceOf(u),
                "holder: matured + pending != balanceOf"
            );
        }

        address user = makeAddr("forkDepositor");
        uint256 amount = 1_000e18;
        deal(SAPIEN, user, amount);
        vm.startPrank(user);
        IERC20(SAPIEN).approve(PROXY, amount);
        uint256 shares = vault.deposit(amount, user);
        vm.stopPrank();
        assertGt(shares, 0, "fork: deposit minted no shares");

        assertEq(vault.maturedShares(user) + vault.pendingShares(user), shares, "fork: tranche split != minted");
        assertEq(vault.maturedShares(user), 0, "fork: fresh deposit already mature");
        assertEq(vault.pendingShares(user), shares, "fork: fresh deposit not pending");
        assertEq(vault.maxWithdraw(user), 0, "fork: fresh deposit withdrawable too early");

        skip(vault.minDepositAge());
        assertEq(vault.maturedShares(user), shares, "fork: shares did not mature");
        assertEq(vault.pendingShares(user), 0, "fork: pending leftover after maturity");
        uint256 maxOut = vault.maxWithdraw(user);
        assertGt(maxOut, 0, "fork: matured holder cannot withdraw");

        vm.prank(user);
        vault.withdraw(maxOut, user, user);
        assertEq(IERC20(SAPIEN).balanceOf(user), maxOut, "fork: withdraw did not pay out");
    }

    function test_fork_liveV2_pauseGatesFlows() public onlyFork {
        vm.prank(admin);
        vault.pause();
        assertTrue(vault.paused(), "fork: pause() did not pause");
        assertEq(vault.maxDeposit(address(0)), 0, "fork: maxDeposit not zero while paused");
        assertEq(vault.maxMint(address(0)), 0, "fork: maxMint not zero while paused");
        assertEq(vault.maxWithdraw(admin), 0, "fork: maxWithdraw not zero while paused");
        assertEq(vault.maxRedeem(admin), 0, "fork: maxRedeem not zero while paused");
    }

    /// @notice `initializeV2` is consumed on this proxy (`reinitializer(2)`).
    function test_fork_liveV2_initializeV2Consumed() public onlyFork {
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initializeV2(admin);
    }
}
