// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {StakeAccount} from "../src/Types.sol";

contract SapienVaultHandler is Test {
    SapienVault public vault;
    MockERC20 public token;

    address[] public actors;
    uint256 public totalLockedAmount;

    mapping(address => uint256) public actorLastDepositTs;

    address public engine;
    address public admin;

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

    function deposit(uint256 actorSeed, uint256 amount) public {
        amount = bound(amount, 1, 100_000e18);
        address actor = getActor(actorSeed);

        if (token.balanceOf(actor) < amount) {
            token.mint(actor, amount);
        }

        vm.prank(actor);
        vault.deposit(amount, actor);

        actorLastDepositTs[actor] = block.timestamp;
    }

    function depositOnBehalf(uint256 callerSeed, uint256 receiverSeed, uint256 amount) public {
        amount = bound(amount, 1, 100_000e18);
        address caller = getActor(callerSeed);
        address receiver = getActor(receiverSeed);

        if (token.balanceOf(caller) < amount) {
            token.mint(caller, amount);
        }

        vm.prank(caller);
        vault.deposit(amount, receiver);

        // SEC-M-01: when caller != receiver the contract no longer resets the
        // receiver's deposit-age timer, so the handler's mirror must mirror
        // that. When caller == receiver this code path is equivalent to a
        // self-deposit and we must update the timer.
        if (caller == receiver) {
            actorLastDepositTs[receiver] = block.timestamp;
        }
    }

    function mintShares(uint256 actorSeed, uint256 shares) public {
        shares = bound(shares, 1, 100_000e21);
        address actor = getActor(actorSeed);

        uint256 assetsNeeded = vault.previewMint(shares);
        if (token.balanceOf(actor) < assetsNeeded) {
            token.mint(actor, assetsNeeded);
        }

        vm.prank(actor);
        vault.mint(shares, actor);

        actorLastDepositTs[actor] = block.timestamp;
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

        uint256 bal = vault.balanceOf(from);
        if (bal == 0) return;

        amount = bound(amount, 1, bal);

        vm.startPrank(from);
        try vault.transfer(to, amount) {
            actorLastDepositTs[to] = block.timestamp;
        } catch {}
        vm.stopPrank();
    }

    function lockStake(uint256 actorSeed, uint256 amount) public {
        address actor = getActor(actorSeed);

        uint256 avail = vault.availableBalance(actor);
        if (avail == 0) return;
        amount = bound(amount, 1, avail);

        vm.startPrank(actor);
        try vault.lockStake(amount) {
            totalLockedAmount += amount;
        } catch {}
        vm.stopPrank();
    }

    function unlockStake(uint256 actorSeed, uint256 amount) public {
        address actor = getActor(actorSeed);
        StakeAccount memory acct = vault.getStakeAccount(actor);

        if (acct.lockedAmount == 0) return;
        amount = bound(amount, 1, acct.lockedAmount);

        vm.prank(engine);
        vault.unlockStake(actor, amount);

        totalLockedAmount -= amount;
    }

    function slashStake(uint256 actorSeed, uint256 amount) public {
        address actor = getActor(actorSeed);
        StakeAccount memory acct = vault.getStakeAccount(actor);

        if (acct.lockedAmount == 0) return;
        amount = bound(amount, 1, acct.lockedAmount);

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

    function passTime(uint256 timeDelta) public {
        timeDelta = bound(timeDelta, 1, 30 days);
        vm.warp(block.timestamp + timeDelta);
    }
}
