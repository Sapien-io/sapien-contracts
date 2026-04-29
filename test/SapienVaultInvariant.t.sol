// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {SapienVaultHandler} from "./SapienVaultHandler.t.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {StakeAccount} from "../src/Types.sol";

contract SapienVaultInvariantTest is Test {
    SapienVault public vault;
    MockERC20 public token;
    SapienVaultHandler public handler;

    address public admin = makeAddr("admin");
    address public engine = makeAddr("engine");

    uint256 public maxObservedExchangeRate;

    function setUp() public {
        token = new MockERC20("Sapien Token", "SAPIEN");

        SapienVault impl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), admin));
        vault = SapienVault(address(new ERC1967Proxy(address(impl), initData)));

        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), engine);
        vault.setMinDepositAge(7 days);
        vm.stopPrank();

        handler = new SapienVaultHandler(vault, token, engine, admin);

        targetContract(address(handler));

        bytes4[] memory actionSelectors = new bytes4[](11);
        actionSelectors[0] = handler.deposit.selector;
        actionSelectors[1] = handler.depositOnBehalf.selector;
        actionSelectors[2] = handler.mintShares.selector;
        actionSelectors[3] = handler.withdraw.selector;
        actionSelectors[4] = handler.redeem.selector;
        actionSelectors[5] = handler.transfer.selector;
        actionSelectors[6] = handler.lockStake.selector;
        actionSelectors[7] = handler.unlockStake.selector;
        actionSelectors[8] = handler.slashStake.selector;
        actionSelectors[9] = handler.togglePause.selector;
        actionSelectors[10] = handler.passTime.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: actionSelectors}));

        vm.warp(100 days);

        maxObservedExchangeRate = vault.convertToAssets(1e18);
    }

    /// @notice Global Solvency: The vault must always hold enough assets to cover all locked stake
    function invariant_TotalAssetsGteTotalLocked() public view {
        assertGe(
            vault.totalAssets(), handler.totalLockedAmount(), "Global solvency broken: Total assets < Total locked"
        );
    }

    /// @notice Token-level Solvency: Real token balance must back totalAssets()
    function invariant_VaultTokenBalance() public view {
        assertGe(
            token.balanceOf(address(vault)), vault.totalAssets(), "Token solvency broken: token balance < totalAssets"
        );
    }

    /// @notice User Solvency: Each user must hold enough unlocked shares to cover their own locked stake
    function invariant_UserSharesCoverLocked() public view {
        for (uint256 i = 0; i < 5; i++) {
            address actor = handler.getActor(i);
            StakeAccount memory acct = vault.getStakeAccount(actor);

            if (acct.lockedAmount > 0) {
                uint256 lockedShares = vault.convertToShares(acct.lockedAmount);
                assertGe(vault.balanceOf(actor), lockedShares, "User solvency broken: Balance < Locked shares");

                uint256 totalAssetsOfUser = vault.convertToAssets(vault.balanceOf(actor));
                assertGe(totalAssetsOfUser, acct.lockedAmount, "User solvency broken: Total assets < Locked amount");
            }
        }
    }

    /// @notice Locked Never Exceeds Total: No user can have locked > their total asset value
    function invariant_LockedNeverExceedsTotal() public view {
        for (uint256 i = 0; i < 5; i++) {
            address actor = handler.getActor(i);
            StakeAccount memory acct = vault.getStakeAccount(actor);
            uint256 totalVal = vault.convertToAssets(vault.balanceOf(actor));
            assertGe(totalVal, acct.lockedAmount, "Locked exceeds total value");
        }
    }

    /// @notice Ghost Accounting: Sum of all individual locked amounts equals the handler's ghost total
    function invariant_GhostLockedMatchesActual() public view {
        uint256 sum;
        for (uint256 i = 0; i < 5; i++) {
            address actor = handler.getActor(i);
            sum += vault.getStakeAccount(actor).lockedAmount;
        }
        assertEq(sum, handler.totalLockedAmount(), "Ghost locked amount desynced from on-chain state");
    }

    /// @notice Time-Lock Enforcement: Users within minDepositAge must be restricted from withdrawing
    function invariant_TimeLockSafety() public view {
        uint256 minAge = vault.minDepositAge();

        for (uint256 i = 0; i < 5; i++) {
            address actor = handler.getActor(i);
            uint256 lastTs = handler.actorLastDepositTs(actor);

            if (lastTs > 0 && block.timestamp - lastTs < minAge) {
                assertEq(vault.maxWithdraw(actor), 0, "Time-lock broken: maxWithdraw > 0");
                assertEq(vault.maxRedeem(actor), 0, "Time-lock broken: maxRedeem > 0");
            }
        }
    }

    /// @notice Exchange Rate Monotonicity: The value of shares should only ever stay flat or increase (due to slashing)
    function invariant_ExchangeRateNeverDecreases() public {
        uint256 currentRate = vault.convertToAssets(1e18);
        if (currentRate > maxObservedExchangeRate) {
            maxObservedExchangeRate = currentRate;
        } else {
            assertGe(currentRate, maxObservedExchangeRate, "Exchange rate monotonicity broken: Rate decreased");
        }
    }
}
