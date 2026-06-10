// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {StakeAccount} from "../src/Types.sol";

/// @notice Invariant-test handler. Every action is revert-safe (preconditions
///         are checked or bounded away) so the suite runs with
///         `fail_on_revert = true`: an unexpected revert in the vault is a
///         test failure, not silently swallowed state-space shrinkage (TEST-1).
contract SapienVaultHandler is Test {
    SapienVault public vault;
    MockERC20 public token;

    address[] public actors;
    uint256 public totalLockedAmount;

    address public engine;
    address public admin;

    /// @dev Upper bound for the fuzzed `setMinTrancheSize` action. Kept below
    ///      the deposit bound so a valid deposit amount always exists.
    uint256 internal constant MAX_FUZZED_TRANCHE_SIZE = 10_000e18;
    uint256 internal constant MAX_DEPOSIT = 100_000e18;

    constructor(SapienVault _vault, MockERC20 _token, address _engine, address _admin) {
        vault = _vault;
        token = _token;
        engine = _engine;
        admin = _admin;

        for (uint256 i = 0; i < 5; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", vm.toString(i))));
            actors.push(actor);

            token.mint(actor, 1_000_000e18);

            vm.prank(actor);
            token.approve(address(vault), type(uint256).max);
        }
    }

    function getActor(uint256 index) public view returns (address) {
        return actors[index % actors.length];
    }

    /// @dev Smallest depositable amount under the current admin config:
    ///      `minTrancheSize` only binds while the MEV guard is on.
    function _minDeposit() internal view returns (uint256) {
        uint256 minSize = vault.minDepositAge() > 0 ? vault.minTrancheSize() : 0;
        return minSize > 0 ? minSize : 1;
    }

    function deposit(uint256 actorSeed, uint256 amount) public {
        if (vault.paused()) return;
        address actor = getActor(actorSeed);
        amount = bound(amount, _minDeposit(), MAX_DEPOSIT);

        if (token.balanceOf(actor) < amount) {
            token.mint(actor, amount);
        }

        vm.prank(actor);
        vault.deposit(amount, actor);
    }

    function depositOnBehalf(uint256 callerSeed, uint256 receiverSeed, uint256 amount) public {
        if (vault.paused()) return;
        address caller = getActor(callerSeed);
        address receiver = getActor(receiverSeed);
        amount = bound(amount, _minDeposit(), MAX_DEPOSIT);

        if (token.balanceOf(caller) < amount) {
            token.mint(caller, amount);
        }

        vm.prank(caller);
        vault.deposit(amount, receiver);
    }

    function mintShares(uint256 actorSeed, uint256 shares) public {
        if (vault.paused()) return;
        shares = bound(shares, 1, 100_000e21);
        address actor = getActor(actorSeed);

        uint256 assetsNeeded = vault.previewMint(shares);
        // BelowMinTrancheSize is checked on the asset amount in _deposit.
        if (assetsNeeded < _minDeposit()) return;
        if (token.balanceOf(actor) < assetsNeeded) {
            token.mint(actor, assetsNeeded);
        }

        vm.prank(actor);
        vault.mint(shares, actor);
    }

    function withdraw(uint256 actorSeed, uint256 amount) public {
        address actor = getActor(actorSeed);

        uint256 maxW = vault.maxWithdraw(actor);
        if (maxW == 0) return;

        amount = bound(amount, 1, maxW);

        vm.prank(actor);
        vault.withdraw(amount, actor, actor);
    }

    function redeem(uint256 actorSeed, uint256 shares) public {
        address actor = getActor(actorSeed);

        uint256 maxR = vault.maxRedeem(actor);
        if (maxR == 0) return;

        shares = bound(shares, 1, maxR);

        vm.prank(actor);
        vault.redeem(shares, actor, actor);
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amount) public {
        address from = getActor(fromSeed);
        address to = getActor(toSeed);
        if (from == to) return;

        // Transferable shares == matured minus the locked reservation, which is
        // exactly maxRedeem (and 0 while paused), so the transfer guard in
        // _update can never fire on a bounded amount.
        uint256 transferable = vault.maxRedeem(from);
        if (transferable == 0) return;

        amount = bound(amount, 1, transferable);

        vm.prank(from);
        vault.transfer(to, amount);
    }

    function lockStake(uint256 actorSeed, uint256 amount) public {
        if (vault.paused()) return;
        address actor = getActor(actorSeed);

        uint256 avail = vault.availableBalance(actor);
        if (avail == 0) return;
        amount = bound(amount, 1, avail);

        vm.prank(actor);
        vault.lockStake(amount);
        totalLockedAmount += amount;
    }

    function unlockStake(uint256 actorSeed, uint256 amount) public {
        if (vault.paused()) return;
        address actor = getActor(actorSeed);
        StakeAccount memory acct = vault.getStakeAccount(actor);

        if (acct.lockedAmount == 0) return;
        amount = bound(amount, 1, acct.lockedAmount);

        vm.prank(engine);
        vault.unlockStake(actor, amount);

        totalLockedAmount -= amount;
    }

    function slashStake(uint256 actorSeed, uint256 amount) public {
        if (vault.paused()) return;
        address actor = getActor(actorSeed);
        StakeAccount memory acct = vault.getStakeAccount(actor);

        if (acct.lockedAmount == 0) return;
        amount = bound(amount, 1, acct.lockedAmount);
        // A slash worth less than one share reverts ZeroShareSlash by design.
        if (vault.convertToShares(amount) == 0) return;

        vm.prank(engine);
        vault.slashStake(actor, amount);

        totalLockedAmount -= amount;
    }

    function togglePause() public {
        vm.startPrank(admin);
        if (vault.paused()) {
            vault.unpause();
        } else {
            vault.pause();
        }
        vm.stopPrank();
    }

    /// @notice T8: fuzz the MEV-guard age across the 0 <-> nonzero transition,
    ///         where `_pushImmature` switches code paths and `_matureSharesView`
    ///         changes semantics.
    function setMinDepositAge(uint256 age) public {
        age = bound(age, 0, vault.MAX_MIN_DEPOSIT_AGE());
        vm.prank(admin);
        vault.setMinDepositAge(age);
    }

    /// @notice T8: fuzz the dust-deposit floor (0 = disabled).
    function setMinTrancheSize(uint256 size) public {
        size = bound(size, 0, MAX_FUZZED_TRANCHE_SIZE);
        vm.prank(admin);
        vault.setMinTrancheSize(size);
    }

    function passTime(uint256 timeDelta) public {
        timeDelta = bound(timeDelta, 1, 30 days);
        vm.warp(block.timestamp + timeDelta);
    }
}
