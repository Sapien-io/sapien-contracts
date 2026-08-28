// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test, Vm} from "forge-std/Test.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {StakeAccount} from "src/Types.sol";
import {CollateralReport} from "test/CollateralReport.sol";

/// @title Local collateral loop: deposit → age → lock → unlock or slash
/// @notice Mirrors issue #167 against an in-process vault (CI always runs this).
///         The live-Sepolia / fork counterpart is `test/fork/SepoliaCollateralLoop.t.sol`.
contract CollateralLoopTest is Test {
    uint256 internal constant DEPOSIT = 1000e18;
    uint256 internal constant LOCK = 400e18;

    SapienVault internal vault;
    MockERC20 internal token;
    address internal admin = makeAddr("admin");
    address internal engine = makeAddr("engine");
    address internal validator = makeAddr("validator");

    function setUp() public {
        token = new MockERC20("Sapien Token", "SAPIEN");
        SapienVault impl = new SapienVault();
        vault = SapienVault(
            address(
                new ERC1967Proxy(address(impl), abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), admin)))
            )
        );

        vm.prank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), engine);

        token.mint(validator, DEPOSIT);
        vm.prank(validator);
        token.approve(address(vault), DEPOSIT);
    }

    /// @notice AC1: deposit, wait `minDepositAge` (seeded default), then `lockStake`.
    ///         Engine holds `ENGINE_ROLE`.
    function test_depositWaitLock_engineHasRole() public {
        assertTrue(vault.hasRole(vault.ENGINE_ROLE(), engine), "engine missing ENGINE_ROLE");
        assertEq(vault.minDepositAge(), vault.DEFAULT_MIN_DEPOSIT_AGE());

        vm.prank(validator);
        uint256 shares = vault.deposit(DEPOSIT, validator);
        assertGt(shares, 0, "deposit minted no shares");
        assertEq(vault.maturedShares(validator), 0, "fresh deposit already mature");

        vm.prank(validator);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientAvailableBalance.selector, LOCK, 0));
        vault.lockStake(LOCK);

        skip(vault.minDepositAge());

        vm.prank(validator);
        vault.lockStake(LOCK);

        StakeAccount memory acct = vault.getStakeAccount(validator);
        assertEq(acct.lockedAmount, LOCK, "lockedAmount != lock");
        assertEq(vault.availableBalance(validator), DEPOSIT - LOCK);
    }

    /// @notice AC2 happy path: accepted review → `unlockStake` → report.stake.
    function test_acceptedReview_unlock_reportStake() public {
        _depositMatureAndLock();

        uint256 lockedAtReview = vault.getStakeAccount(validator).lockedAmount;
        CollateralReport.Stake memory stake = CollateralReport.accepted(lockedAtReview);

        vm.expectEmit(true, true, false, true, address(vault));
        emit ISapienVault.StakeUnlocked(validator, LOCK);

        vm.prank(engine);
        vault.unlockStake(validator, LOCK);

        assertEq(stake.slashedWei, 0, "stake.slashed_wei must be 0");
        assertEq(stake.stakeAtRiskWei, LOCK, "stake.stake_at_risk_wei != locked at review");
        assertEq(vault.getStakeAccount(validator).lockedAmount, 0, "lock not cleared");
        assertEq(vault.availableBalance(validator), DEPOSIT);
    }

    /// @notice AC3 forced path: `slashStake` burns shares; report.stake + Basescan URL.
    function test_forcedReview_slash_reportStakeAndBasescanUrl() public {
        _depositMatureAndLock();

        uint256 lockedAtReview = vault.getStakeAccount(validator).lockedAmount;
        uint256 sharesBefore = vault.balanceOf(validator);

        vm.recordLogs();
        vm.prank(engine);
        vault.slashStake(validator, LOCK);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        bool sawSlash;
        bool sawShares;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].emitter != address(vault)) continue;
            if (logs[i].topics[0] == ISapienVault.StakeSlashed.selector) {
                assertEq(uint256(logs[i].topics[2]), LOCK, "StakeSlashed.amount != burned assets");
                sawSlash = true;
            }
            if (logs[i].topics[0] == ISapienVault.SharesSlashed.selector) {
                assertGt(uint256(logs[i].topics[2]), 0, "SharesSlashed.shares == 0");
                sawShares = true;
            }
        }
        assertTrue(sawSlash, "missing StakeSlashed");
        assertTrue(sawShares, "missing SharesSlashed");

        uint256 sharesAfter = vault.balanceOf(validator);
        assertLt(sharesAfter, sharesBefore, "slash did not burn shares");

        CollateralReport.Stake memory stake = CollateralReport.slashed(LOCK, lockedAtReview);
        assertEq(stake.slashedWei, LOCK, "stake.slashed_wei != burned asset amount");
        assertEq(stake.stakeAtRiskWei, lockedAtReview, "stake.stake_at_risk_wei != locked at review");
        assertEq(vault.getStakeAccount(validator).lockedAmount, 0, "lock not reduced");

        bytes32 slashTx = keccak256("sepolia-slash-example");
        assertEq(
            CollateralReport.sepoliaTxUrl(slashTx),
            string.concat("https://sepolia.basescan.org/tx/", vm.toString(slashTx))
        );
    }

    /// @notice Unlock / slash remain `ENGINE_ROLE`-gated (owner cannot self-unlock).
    function test_unlockAndSlash_onlyEngine() public {
        _depositMatureAndLock();

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

    function _depositMatureAndLock() internal {
        vm.prank(validator);
        vault.deposit(DEPOSIT, validator);
        skip(vault.minDepositAge());
        vm.prank(validator);
        vault.lockStake(LOCK);
    }
}
