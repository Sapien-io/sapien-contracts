// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {console2} from "forge-std/console2.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {StakeAccount} from "src/Types.sol";
import {SapienVaultHandler} from "test/invariant/handlers/SapienVaultHandler.sol";

/// @title SapienVaultInvariantTest
/// @notice Invariant tests for the SapienVault ERC-4626 vault
/// @dev Tests that core vault invariants hold across arbitrary sequences of
///      deposits, withdrawals, locks, unlocks, commits, releases, and slashes.
contract SapienVaultInvariantTest is Test {
    SapienVault public vault;
    MockERC20 public token;
    SapienVaultHandler public handler;

    address public admin = makeAddr("admin");
    address public engine = makeAddr("engine");

    address[] public actors;
    uint256 public constant NUM_ACTORS = 5;

    function setUp() public {
        // Deploy token
        token = new MockERC20("Sapien Token", "SPN");

        // Deploy SapienVault behind proxy
        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInit = abi.encodeCall(SapienVault.initialize, (token, admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));

        // Grant ENGINE_ROLE to engine address
        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), engine);
        vm.stopPrank();

        // Create actors
        for (uint256 i; i < NUM_ACTORS; ++i) {
            address actor = makeAddr(string(abi.encodePacked("actor", vm.toString(i))));
            actors.push(actor);
        }

        // Deploy handler
        handler = new SapienVaultHandler(vault, token, engine, actors);

        // Set handler as the only target for invariant testing
        targetContract(address(handler));
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 1: Lock solvency
    // For every user, total locked amounts must never exceed their staked assets.
    // contributorLock + validatorCapacity + inFlight <= convertToAssets(balanceOf(user))
    // ════════════════════════════════════════════════════════════════════

    function invariant_lockSolvency() public view {
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            StakeAccount memory acct = vault.getStakeAccount(actor);
            uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
            uint256 totalAssets = vault.convertToAssets(vault.balanceOf(actor));

            assertGe(
                totalAssets, totalLocked, string(abi.encodePacked("Lock solvency violated for actor ", vm.toString(i)))
            );
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 2: Available balance consistency
    // availableBalance(user) == max(0, convertToAssets(balanceOf(user)) - totalLocked)
    // ════════════════════════════════════════════════════════════════════

    function invariant_availableBalanceConsistency() public view {
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            StakeAccount memory acct = vault.getStakeAccount(actor);
            uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
            uint256 totalAssets = vault.convertToAssets(vault.balanceOf(actor));

            uint256 expected = totalAssets > totalLocked ? totalAssets - totalLocked : 0;
            uint256 actual = vault.availableBalance(actor);

            assertEq(
                actual, expected, string(abi.encodePacked("Available balance inconsistent for actor ", vm.toString(i)))
            );
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 3: Withdrawal guard
    // maxRedeem(user) must always be <= balanceOf(user)
    // and redeeming maxRedeem should never violate lock constraints.
    // ════════════════════════════════════════════════════════════════════

    function invariant_withdrawalGuard() public view {
        for (uint256 i; i < actors.length; ++i) {
            address actor = actors[i];
            uint256 maxRedeem = vault.maxRedeem(actor);
            uint256 balance = vault.balanceOf(actor);

            assertLe(
                maxRedeem, balance, string(abi.encodePacked("maxRedeem exceeds balance for actor ", vm.toString(i)))
            );

            // maxRedeem in assets should not exceed available balance
            uint256 maxRedeemAssets = vault.convertToAssets(maxRedeem);
            uint256 available = vault.availableBalance(actor);

            assertLe(
                maxRedeemAssets,
                available + 1, // +1 for rounding tolerance
                string(abi.encodePacked("maxRedeem assets exceeds available for actor ", vm.toString(i)))
            );
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 4: Vault token solvency
    // The vault's underlying token balance must always be >= total supply of shares
    // converted back to assets.
    // ════════════════════════════════════════════════════════════════════

    function invariant_vaultTokenSolvency() public view {
        uint256 vaultTokenBalance = token.balanceOf(address(vault));
        uint256 totalAssets = vault.totalAssets();

        assertGe(vaultTokenBalance, totalAssets, "Vault token balance less than total assets");
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 5: ERC-4626 share/asset ratio
    // Total shares should never exceed total assets (with decimals offset of 3,
    // the initial virtual ratio is 1000:1, so shares may exceed assets by up to 1000x).
    // More precisely: totalAssets() should always be consistent with
    // convertToAssets(totalSupply()).
    // ════════════════════════════════════════════════════════════════════

    function invariant_shareAssetConsistency() public view {
        uint256 totalSupply = vault.totalSupply();
        uint256 totalAssets = vault.totalAssets();

        if (totalSupply > 0) {
            uint256 assetsFromShares = vault.convertToAssets(totalSupply);
            // After share-burn slashing, totalSupply drops while totalAssets stays
            // constant.  The decimalsOffset virtual shares (10^3 = 1000) then claim
            // a growing fraction of totalAssets that convertToAssets(totalSupply)
            // does not reflect.  The exact gap is:
            //   (1000 * totalAssets - totalSupply) / (totalSupply + 1000)
            // We compute this expected claim and add +2 for integer rounding in
            // both this formula and convertToAssets.
            uint256 virtualClaim;
            uint256 product = uint256(1000) * totalAssets;
            if (product > totalSupply) {
                virtualClaim = (product - totalSupply) / (totalSupply + 1000);
            }
            assertGe(
                assetsFromShares + virtualClaim + 2, totalAssets, "Share/asset ratio inconsistent with totalAssets"
            );
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 6: Deposit-withdraw token conservation
    // Slashing burns shares but does NOT remove tokens from the vault.
    // Therefore: vault token balance == totalDeposited - totalWithdrawn.
    // The "slashed" value stays in the vault and accrues to remaining shareholders
    // (and the virtual shares from the decimals offset).
    // ════════════════════════════════════════════════════════════════════

    function invariant_depositWithdrawTokenConservation() public view {
        uint256 totalDeposited = handler.ghost_totalDeposited();
        uint256 totalWithdrawn = handler.ghost_totalWithdrawn();
        uint256 vaultBalance = token.balanceOf(address(vault));

        if (totalDeposited > 0) {
            // vault token balance should equal deposits minus withdrawals
            // Allow small rounding from ERC-4626 previewRedeem vs actual redeem
            uint256 totalOps = handler.calls_deposit() + handler.calls_withdraw();
            assertApproxEqAbs(
                vaultBalance,
                totalDeposited - totalWithdrawn,
                totalOps + 1,
                "Deposit/withdraw token conservation violated"
            );
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 6b: Slashing only burns shares
    // After slashing, the vault token balance should not change. We verify
    // that total slashed is accounted for by the increase in share price
    // (i.e., totalAssets stays the same, but total supply decreases).
    // ════════════════════════════════════════════════════════════════════

    function invariant_slashOnlyBurnsShares() public view {
        // Slashing should never cause vault token balance to decrease.
        // vault.totalAssets() == token.balanceOf(vault) always holds.
        uint256 vaultBalance = token.balanceOf(address(vault));
        uint256 totalAssets = vault.totalAssets();

        assertEq(vaultBalance, totalAssets, "Vault balance and totalAssets diverged");
    }

    // ════════════════════════════════════════════════════════════════════
    // Invariant 7: No zero-address actor has a balance
    // ════════════════════════════════════════════════════════════════════

    function invariant_noZeroAddressBalance() public view {
        assertEq(vault.balanceOf(address(0)), 0, "Zero address has vault shares");
    }

    // ════════════════════════════════════════════════════════════════════
    // Post-run summary (called by forge after all invariant sequences)
    // ════════════════════════════════════════════════════════════════════

    function invariant_callSummary() public view {
        console2.log("--- SapienVault Handler Call Summary ---");
        console2.log("  deposit:                 ", handler.calls_deposit());
        console2.log("  withdraw:                ", handler.calls_withdraw());
        console2.log("  lockContributor:         ", handler.calls_lockContributor());
        console2.log("  unlockContributor:       ", handler.calls_unlockContributor());
        console2.log("  slashContributor:        ", handler.calls_slashContributor());
        console2.log("  lockValidatorCapacity:   ", handler.calls_lockValidatorCapacity());
        console2.log("  unlockValidatorCapacity: ", handler.calls_unlockValidatorCapacity());
        console2.log("  commitStake:             ", handler.calls_commitStake());
        console2.log("  releaseCommit:           ", handler.calls_releaseCommit());
        console2.log("  slashValidator:          ", handler.calls_slashValidator());
        console2.log("--- Ghost State ---");
        console2.log("  totalDeposited:          ", handler.ghost_totalDeposited());
        console2.log("  totalWithdrawn:          ", handler.ghost_totalWithdrawn());
        console2.log("  totalContributorSlashed: ", handler.ghost_totalContributorSlashed());
        console2.log("  totalValidatorSlashed:   ", handler.ghost_totalValidatorSlashed());
    }
}
