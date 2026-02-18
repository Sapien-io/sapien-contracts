// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {StakeVault} from "../../../src/StakeVault.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {StakeAccount} from "../../../src/Types.sol";

/// @title StakeVaultHandler
/// @notice Foundry invariant-test handler that wraps StakeVault operations with bounded
///         inputs and tracks ghost state for invariant assertions.
/// @dev All "engine" functions (lock/unlock/slash/commit/release) are called via vm.prank
///      using the engine address so that the ENGINE_ROLE check passes.
contract StakeVaultHandler is Test {
    // ── Contracts ────────────────────────────────────────────────────────
    StakeVault public vault;
    MockERC20 public token;
    address public engine;

    // ── Actor management ────────────────────────────────────────────────
    address[] public actors;
    mapping(address => bool) public isActor;

    // ── Ghost variables (for invariant assertions) ─────────────────────
    uint256 public ghost_totalDeposited;
    uint256 public ghost_totalWithdrawn;
    uint256 public ghost_totalContributorSlashed;
    uint256 public ghost_totalValidatorSlashed;

    // Per-actor ghost tracking
    mapping(address => uint256) public ghost_deposited;
    mapping(address => uint256) public ghost_withdrawn;

    // ── Call counters ───────────────────────────────────────────────────
    uint256 public calls_deposit;
    uint256 public calls_withdraw;
    uint256 public calls_lockContributor;
    uint256 public calls_unlockContributor;
    uint256 public calls_slashContributor;
    uint256 public calls_lockValidatorCapacity;
    uint256 public calls_unlockValidatorCapacity;
    uint256 public calls_commitStake;
    uint256 public calls_releaseCommit;
    uint256 public calls_slashValidator;

    // ── Bounds ──────────────────────────────────────────────────────────
    uint256 public constant MAX_DEPOSIT = 1_000_000e18;
    uint256 public constant MIN_DEPOSIT = 1e18;

    constructor(StakeVault vault_, MockERC20 token_, address engine_, address[] memory actors_) {
        vault = vault_;
        token = token_;
        engine = engine_;

        for (uint256 i; i < actors_.length; ++i) {
            actors.push(actors_[i]);
            isActor[actors_[i]] = true;
        }
    }

    // ── Helpers ──────────────────────────────────────────────────────────

    function _selectActor(uint256 seed) internal view returns (address) {
        return actors[seed % actors.length];
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    // ── ERC-4626 deposit/withdraw ───────────────────────────────────────

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = _selectActor(actorSeed);
        amount = bound(amount, MIN_DEPOSIT, MAX_DEPOSIT);

        token.mint(actor, amount);

        vm.startPrank(actor);
        token.approve(address(vault), amount);
        vault.deposit(amount, actor);
        vm.stopPrank();

        ghost_totalDeposited += amount;
        ghost_deposited[actor] += amount;
        calls_deposit++;
    }

    function withdraw(uint256 actorSeed, uint256 amount) external {
        address actor = _selectActor(actorSeed);
        uint256 maxRedeem = vault.maxRedeem(actor);
        if (maxRedeem == 0) return;

        uint256 sharesToRedeem = bound(amount, 1, maxRedeem);
        uint256 assets = vault.previewRedeem(sharesToRedeem);

        vm.startPrank(actor);
        vault.redeem(sharesToRedeem, actor, actor);
        vm.stopPrank();

        ghost_totalWithdrawn += assets;
        ghost_withdrawn[actor] += assets;
        calls_withdraw++;
    }

    // ── Contributor lock operations ─────────────────────────────────────

    function lockContributor(uint256 actorSeed, uint256 amount) external {
        address actor = _selectActor(actorSeed);
        uint256 avail = vault.availableBalance(actor);
        if (avail == 0) return;

        amount = bound(amount, 1, avail);

        vm.prank(engine);
        vault.lockContributor(actor, amount);

        calls_lockContributor++;
    }

    function unlockContributor(uint256 actorSeed, uint256 amount) external {
        address actor = _selectActor(actorSeed);
        StakeAccount memory acct = vault.getStakeAccount(actor);
        if (acct.contributorLock == 0) return;

        amount = bound(amount, 1, acct.contributorLock);

        vm.prank(engine);
        vault.unlockContributor(actor, amount);

        calls_unlockContributor++;
    }

    function slashContributor(uint256 actorSeed, uint256 amount) external {
        address actor = _selectActor(actorSeed);
        StakeAccount memory acct = vault.getStakeAccount(actor);
        if (acct.contributorLock == 0) return;

        amount = bound(amount, 1, acct.contributorLock);

        vm.prank(engine);
        vault.slashContributor(actor, amount);

        ghost_totalContributorSlashed += amount;
        calls_slashContributor++;
    }

    // ── Validator capacity operations ───────────────────────────────────

    function lockValidatorCapacity(uint256 actorSeed, uint256 amount) external {
        address actor = _selectActor(actorSeed);
        uint256 avail = vault.availableBalance(actor);
        if (avail == 0) return;

        amount = bound(amount, 1, avail);

        vm.prank(engine);
        vault.lockValidatorCapacity(actor, amount);

        calls_lockValidatorCapacity++;
    }

    function unlockValidatorCapacity(uint256 actorSeed, uint256 amount) external {
        address actor = _selectActor(actorSeed);
        StakeAccount memory acct = vault.getStakeAccount(actor);
        if (acct.validatorCapacity == 0) return;

        amount = bound(amount, 1, acct.validatorCapacity);

        vm.prank(engine);
        vault.unlockValidatorCapacity(actor, amount);

        calls_unlockValidatorCapacity++;
    }

    // ── Validator in-flight operations ──────────────────────────────────

    function commitStake(uint256 actorSeed, uint256 amount) external {
        address actor = _selectActor(actorSeed);
        StakeAccount memory acct = vault.getStakeAccount(actor);
        if (acct.validatorCapacity == 0) return;

        amount = bound(amount, 1, acct.validatorCapacity);

        vm.prank(engine);
        vault.commitStake(actor, amount);

        calls_commitStake++;
    }

    function releaseCommit(uint256 actorSeed, uint256 amount) external {
        address actor = _selectActor(actorSeed);
        StakeAccount memory acct = vault.getStakeAccount(actor);
        if (acct.inFlight == 0) return;

        amount = bound(amount, 1, acct.inFlight);

        vm.prank(engine);
        vault.releaseCommit(actor, amount);

        calls_releaseCommit++;
    }

    function slashValidator(uint256 actorSeed, uint256 amount) external {
        address actor = _selectActor(actorSeed);
        StakeAccount memory acct = vault.getStakeAccount(actor);
        if (acct.inFlight == 0) return;

        amount = bound(amount, 1, acct.inFlight);

        vm.prank(engine);
        vault.slashValidator(actor, amount);

        ghost_totalValidatorSlashed += amount;
        calls_slashValidator++;
    }
}
