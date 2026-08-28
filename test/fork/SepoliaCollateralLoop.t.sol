// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test, Vm} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {StakeAccount} from "src/Types.sol";
import {CollateralReport} from "test/CollateralReport.sol";

/// @title Base-Sepolia fork of the lock → review → unlock/slash loop
/// @notice Issue #167 against the live V2 UUPS. Skips when no Sepolia RPC is set.
///
/// @dev Environment:
///        BASE_SEPOLIA_RPC_URL / FORK_RPC_URL — required; suite skips when unset.
///        FORK_BLOCK                          — optional; pin for determinism.
///        SEPOLIA_ENGINE                      — optional; if set, assert this
///                                              address already holds ENGINE_ROLE
///                                              on the live vault.
///
///      Run: BASE_SEPOLIA_RPC_URL=... forge test --match-path test/fork/SepoliaCollateralLoop.t.sol -vvv
contract SepoliaCollateralLoopTest is Test {
    address internal constant PROXY = 0x58E72Fa7fb92B100f2c652377465EEEe2642544C;
    address internal constant SAPIEN = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6;
    address internal constant MAINNET_VAULT = 0x60Bf63729f688287a450299962b36Cef0aFfaa42;
    address internal constant KNOWN_ADMIN = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;

    uint256 internal constant DEPOSIT = 1_000e18;
    uint256 internal constant LOCK = 400e18;

    SapienVault internal vault = SapienVault(PROXY);
    address internal admin;
    address internal engine;
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

        admin = KNOWN_ADMIN;
        engine = makeAddr("sepoliaEngine");

        // Fork-local grant so unlock/slash can run even before the Safe
        // submits `GrantEngineRole` calldata on the live vault.
        vm.prank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), engine);
    }

    modifier onlyFork() {
        vm.skip(!forkEnabled);
        _;
    }

    /// @notice This suite never touches the mainnet rewards vault.
    function test_fork_refusesMainnetVault() public onlyFork {
        assertEq(address(vault), PROXY, "fork: not the Sepolia proxy");
        assertTrue(address(vault) != MAINNET_VAULT, "fork: pointed at mainnet");
        assertEq(address(vault.asset()), SAPIEN, "fork: asset() != Sepolia SAPIEN");
    }

    /// @notice Live `SEPOLIA_ENGINE` (if configured) already holds `ENGINE_ROLE`.
    function test_fork_liveEngineRole() public onlyFork {
        address liveEngine = vm.envOr("SEPOLIA_ENGINE", address(0));
        if (liveEngine == address(0)) return;
        assertTrue(vault.hasRole(vault.ENGINE_ROLE(), liveEngine), "fork: SEPOLIA_ENGINE missing ENGINE_ROLE");
    }

    /// @notice AC1: deposit Sepolia SAPIEN, wait `minDepositAge`, `lockStake`.
    ///         The fork-local engine (and, if set, `SEPOLIA_ENGINE`) holds the role.
    function test_fork_depositWaitLock() public onlyFork {
        assertTrue(vault.hasRole(vault.ENGINE_ROLE(), engine), "fork: test engine missing ENGINE_ROLE");
        assertFalse(vault.paused(), "fork: vault paused");

        address validator = makeAddr("sepoliaValidator");
        _depositAndMature(validator);

        vm.prank(validator);
        vault.lockStake(LOCK);

        StakeAccount memory acct = vault.getStakeAccount(validator);
        assertEq(acct.lockedAmount, LOCK, "fork: lockedAmount != lock");
    }

    /// @notice AC2: accepted review → `unlockStake` → `report.stake` fields.
    function test_fork_acceptedReview_unlock() public onlyFork {
        address validator = makeAddr("sepoliaHappy");
        _depositAndMature(validator);
        vm.prank(validator);
        vault.lockStake(LOCK);

        uint256 lockedAtReview = vault.getStakeAccount(validator).lockedAmount;
        assertEq(lockedAtReview, LOCK);

        vm.expectEmit(true, true, false, true, PROXY);
        emit ISapienVault.StakeUnlocked(validator, LOCK);

        vm.prank(engine);
        vault.unlockStake(validator, LOCK);

        CollateralReport.Stake memory stake = CollateralReport.accepted(lockedAtReview);
        assertEq(stake.slashedWei, 0, "fork: stake.slashed_wei != 0");
        assertEq(stake.stakeAtRiskWei, lockedAtReview, "fork: stake.stake_at_risk_wei != locked at review");
        assertEq(vault.getStakeAccount(validator).lockedAmount, 0, "fork: lock not cleared");
    }

    /// @notice AC3: `slashStake` burns shares (`SharesSlashed`); report + Basescan URL.
    function test_fork_forcedReview_slash() public onlyFork {
        address validator = makeAddr("sepoliaForced");
        _depositAndMature(validator);
        vm.prank(validator);
        vault.lockStake(LOCK);

        uint256 lockedAtReview = vault.getStakeAccount(validator).lockedAmount;
        uint256 sharesBefore = vault.balanceOf(validator);

        vm.recordLogs();
        vm.prank(engine);
        vault.slashStake(validator, LOCK);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool sawSlash;
        bool sawShares;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != PROXY) continue;
            if (logs[i].topics[0] == ISapienVault.StakeSlashed.selector) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), validator);
                assertEq(uint256(logs[i].topics[2]), LOCK, "fork: StakeSlashed.amount != burned assets");
                sawSlash = true;
            }
            if (logs[i].topics[0] == ISapienVault.SharesSlashed.selector) {
                assertEq(address(uint160(uint256(logs[i].topics[1]))), validator);
                assertGt(uint256(logs[i].topics[2]), 0, "fork: SharesSlashed.shares == 0");
                sawShares = true;
            }
        }
        assertTrue(sawSlash, "fork: missing StakeSlashed");
        assertTrue(sawShares, "fork: missing SharesSlashed");
        assertLt(vault.balanceOf(validator), sharesBefore, "fork: slash did not burn shares");

        CollateralReport.Stake memory stake = CollateralReport.slashed(LOCK, lockedAtReview);
        assertEq(stake.slashedWei, LOCK, "fork: stake.slashed_wei != burned asset amount");
        assertEq(stake.stakeAtRiskWei, lockedAtReview, "fork: stake.stake_at_risk_wei != locked at review");
        assertEq(vault.getStakeAccount(validator).lockedAmount, 0, "fork: lock not reduced");

        // HTML report link. On a fork there is no explorer tx; the helper still
        // produces the Basescan Sepolia URL the engine will emit for the live tx.
        bytes32 example = bytes32(uint256(0x167));
        assertEq(
            CollateralReport.sepoliaTxUrl(example),
            "https://sepolia.basescan.org/tx/0x0000000000000000000000000000000000000000000000000000000000000167"
        );
    }

    /// @notice Owner cannot self-unlock / self-slash on the live proxy ABI.
    function test_fork_unlockSlash_onlyEngine() public onlyFork {
        address validator = makeAddr("sepoliaAuth");
        _depositAndMature(validator);
        vm.prank(validator);
        vault.lockStake(LOCK);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, validator, vault.ENGINE_ROLE()
            )
        );
        vm.prank(validator);
        vault.unlockStake(validator, LOCK);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, validator, vault.ENGINE_ROLE()
            )
        );
        vm.prank(validator);
        vault.slashStake(validator, LOCK);
    }

    function _depositAndMature(address validator) internal {
        deal(SAPIEN, validator, DEPOSIT);
        vm.startPrank(validator);
        IERC20(SAPIEN).approve(PROXY, DEPOSIT);
        uint256 shares = vault.deposit(DEPOSIT, validator);
        vm.stopPrank();
        assertGt(shares, 0, "fork: deposit minted no shares");

        if (vault.minDepositAge() > 0) {
            assertEq(vault.maturedShares(validator), 0, "fork: fresh deposit already mature");
            vm.prank(validator);
            vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientAvailableBalance.selector, LOCK, 0));
            vault.lockStake(LOCK);
            skip(vault.minDepositAge());
        }

        assertGt(vault.availableBalance(validator), 0, "fork: nothing available after maturity");
    }
}
