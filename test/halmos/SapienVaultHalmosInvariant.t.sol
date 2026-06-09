// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {StakeAccount} from "../../src/Types.sol";

/// @notice Stateful Halmos invariants — lean handler set; depth 1 is tractable.
/// @custom:halmos --loop 4 --invariant-depth 1 --solver-timeout-assertion 0
contract SapienVaultHalmosInvariantTest is Test {
    SapienVault internal vault;
    MockERC20 internal token;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant ENGINE = address(0xE0611E);
    address internal constant ACTOR0 = address(0x1001);
    address internal constant ACTOR1 = address(0x1002);

    uint256 internal totalLockedAmount;

    function setUp() public {
        token = new MockERC20("Sapien Token", "SAPIEN");

        SapienVault impl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), ADMIN));
        vault = SapienVault(address(new ERC1967Proxy(address(impl), initData)));

        vm.startPrank(ADMIN);
        vault.grantRole(vault.ENGINE_ROLE(), ENGINE);
        vault.setMinDepositAge(1 days);
        vm.stopPrank();

        for (uint256 i = 0; i < 2; i++) {
            address actor = i == 0 ? ACTOR0 : ACTOR1;
            token.mint(actor, 1_000_000e18);
            vm.prank(actor);
            token.approve(address(vault), type(uint256).max);
        }

        targetContract(address(this));

        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = this.deposit0.selector;
        selectors[1] = this.deposit1.selector;
        selectors[2] = this.lockStake0.selector;
        selectors[3] = this.slashStake0.selector;
        selectors[4] = this.passTime.selector;
        selectors[5] = this.redeem0.selector;
        targetSelector(FuzzSelector({addr: address(this), selectors: selectors}));

        vm.warp(100 days);
    }

    function _assumeAmount(uint256 amount, uint256 maxAmt) internal {
        vm.assume(amount > 0);
        vm.assume(amount <= maxAmt);
    }

    function deposit0(uint256 amount) external {
        _assumeAmount(amount, 100_000e18);
        vm.prank(ACTOR0);
        vault.deposit(amount, ACTOR0);
    }

    function deposit1(uint256 amount) external {
        _assumeAmount(amount, 100_000e18);
        vm.prank(ACTOR1);
        vault.deposit(amount, ACTOR1);
    }

    function lockStake0(uint256 amount) external {
        uint256 avail = vault.availableBalance(ACTOR0);
        if (avail == 0) return;
        _assumeAmount(amount, avail);
        vm.startPrank(ACTOR0);
        try vault.lockStake(amount) {
            totalLockedAmount += amount;
        } catch {}
        vm.stopPrank();
    }

    function slashStake0(uint256 amount) external {
        StakeAccount memory acct = vault.getStakeAccount(ACTOR0);
        if (acct.lockedAmount == 0) return;
        _assumeAmount(amount, acct.lockedAmount);
        vm.prank(ENGINE);
        vault.slashStake(ACTOR0, amount);
        totalLockedAmount -= amount;
    }

    function passTime(uint256 delta) external {
        vm.assume(delta > 0);
        vm.assume(delta <= 30 days);
        vm.warp(block.timestamp + delta);
    }

    function redeem0(uint256 shares) external {
        uint256 maxShares = vault.maxRedeem(ACTOR0);
        if (maxShares == 0) return;
        _assumeAmount(shares, maxShares);
        vm.prank(ACTOR0);
        vault.redeem(shares, ACTOR0, ACTOR0);
    }

    function invariant_totalSupplyMatchesBalances() external view {
        assert(vault.totalSupply() == vault.balanceOf(ACTOR0) + vault.balanceOf(ACTOR1));
    }

    function invariant_totalAssetsGteTotalLocked() external view {
        assert(vault.totalAssets() >= totalLockedAmount);
    }

    function invariant_vaultTokenBalance() external view {
        assert(token.balanceOf(address(vault)) >= vault.totalAssets());
    }

    function invariant_trancheAccountingMatchesBalance() external view {
        assert(vault.maturedShares(ACTOR0) + vault.pendingShares(ACTOR0) == vault.balanceOf(ACTOR0));
        assert(vault.maturedShares(ACTOR1) + vault.pendingShares(ACTOR1) == vault.balanceOf(ACTOR1));
    }

    function invariant_immatureSharesNotRedeemable() external view {
        assert(vault.maxRedeem(ACTOR0) <= vault.maturedShares(ACTOR0));
        assert(vault.maxRedeem(ACTOR1) <= vault.maturedShares(ACTOR1));
    }

    function invariant_lockedNeverExceedsTotal() external view {
        assert(vault.convertToAssets(vault.balanceOf(ACTOR0)) >= vault.getStakeAccount(ACTOR0).lockedAmount);
        assert(vault.convertToAssets(vault.balanceOf(ACTOR1)) >= vault.getStakeAccount(ACTOR1).lockedAmount);
    }

    function invariant_ghostLockedMatchesActual() external view {
        uint256 sum = vault.getStakeAccount(ACTOR0).lockedAmount + vault.getStakeAccount(ACTOR1).lockedAmount;
        assert(sum == totalLockedAmount);
    }
}
