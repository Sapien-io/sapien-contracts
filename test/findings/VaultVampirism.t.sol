// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {SLASHER_ROLE} from "../../src/interface/ISharedTypes.sol";
import {console} from "lib/forge-std/src/console.sol";

contract VaultVampirismTest is BaseTest {
    address public victim = makeAddr("victim");
    address public attacker = makeAddr("attacker");

    function setUp() public override {
        super.setUp();

        // Setup Victim
        stakeToken.mint(victim, 1000 ether);
        vm.startPrank(victim);
        stakeToken.approve(address(vault), 1000 ether);
        vault.deposit(1000 ether, victim);
        vm.stopPrank();

        // Setup Attacker
        stakeToken.mint(attacker, 100 ether); // Attacker puts in less
        vm.startPrank(attacker);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(100 ether, attacker);
        vm.stopPrank();
    }

    function test_VaultVampirism() public {
        // Initial State
        uint256 victimShares = vault.balanceOf(victim);
        uint256 attackerShares = vault.balanceOf(attacker);
        uint256 totalAssets = vault.totalAssets();

        console.log("Initial Victim Shares:", victimShares);
        console.log("Initial Attacker Shares:", attackerShares);
        console.log("Total Vault Assets:", totalAssets);

        // Assume Attacker gains SLASHER_ROLE (or effectively controls it)
        vm.startPrank(admin);
        vault.grantRole(SLASHER_ROLE, attacker);
        vm.stopPrank();

        // Attacker slashes Victim for 100% of their assets
        vm.startPrank(attacker);
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as project ID
        vault.slash(victim, 1000 ether, bytes32("project_id"));
        vm.stopPrank();

        // Check State after slashing
        uint256 victimSharesAfter = vault.balanceOf(victim);
        uint256 attackerSharesAfter = vault.balanceOf(attacker); // Should be unchanged
        uint256 totalAssetsAfter = vault.totalAssets(); // Should be unchanged (assets remain in vault)

        console.log("Post-Slash Victim Shares:", victimSharesAfter);
        console.log("Post-Slash Attacker Shares:", attackerSharesAfter);
        console.log("Post-Slash Vault Assets:", totalAssetsAfter);

        assertEq(victimSharesAfter, 0, "Victim should have 0 shares");
        assertEq(totalAssetsAfter, totalAssets, "Assets should remain in vault");

        // Attacker withdraws available assets (Floor)
        // vault.redeem(attackerSharesAfter, attacker, attacker); // Fails due to rounding
        // uint256 assetsFloor = vault.convertToAssets(attackerSharesAfter);
        // vm.startPrank(attacker);
        // vault.withdraw(assetsFloor, attacker, attacker);
        // vm.stopPrank();

        uint256 attackerBalance = stakeToken.balanceOf(attacker);
        console.log("Attacker Final Balance:", attackerBalance);

        // Attacker started with 100, Victim with 1000. Vault had 1100 + others from BaseTest setup.
        // BaseTest sets up originator, contributor, validators with 1000 each.
        // Total initial vault assets = 5 users * 1000 = 5000 ether.
        // Plus our 1000 (victim) + 100 (attacker) = 6100 ether total.

        // Wait, BaseTest _setupInitialFunds puts 1000 ether for 5 users = 5000 ether.
        // Victim puts 1000. Attacker puts 100.
        // Total = 6100.
        // If Victim is slashed (1000 shares burned), remaining shares = 5100.
        // Attacker has 100 shares.
        // Attacker share of pool = 100 / 5100 ~= 1.96%.
        // Value = 1.96% * 6100 = 119.6 ether.
        // So attacker gains ~20 ether.

        // BUT if attacker slashes EVERYONE else (as per attack description):
        // "I slash every single user in the protocol except for one account I control."

        // Let's simulate slashing EVERYONE else.
        // Need to slash more than their balance to ensure all shares are burned
        vm.startPrank(attacker);
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using fixed string literals as project IDs
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as project ID
        vault.slash(originator, type(uint256).max, bytes32("p1")); // Slash all
        // forge-lint: disable-next-line(unsafe-typecast)
        vault.slash(contributor, type(uint256).max, bytes32("p2")); // Slash all
        // forge-lint: disable-next-line(unsafe-typecast)
        vault.slash(validator1, type(uint256).max, bytes32("p3")); // Slash all
        // forge-lint: disable-next-line(unsafe-typecast)
        vault.slash(validator2, type(uint256).max, bytes32("p4")); // Slash all
        // forge-lint: disable-next-line(unsafe-typecast)
        vault.slash(validator3, type(uint256).max, bytes32("p5")); // Slash all
        // Victim is already slashed.
        vm.stopPrank();

        // Now Attacker should be the only one with shares (everyone else was slashed)
        uint256 finalAttackerShares = vault.balanceOf(attacker);
        uint256 finalTotalSupply = vault.totalSupply();
        uint256 finalAttackerAssets = vault.convertToAssets(finalAttackerShares);
        uint256 finalTotalAssets = vault.totalAssets();

        console.log("Final Attacker Shares:", finalAttackerShares);
        console.log("Final Total Supply:", finalTotalSupply);
        console.log("Final Attacker Assets Value:", finalAttackerAssets);
        console.log("Final Total Vault Assets:", finalTotalAssets);

        // Attacker should hold nearly all shares (due to decimals offset, there may be tiny rounding differences)
        // Check that attacker holds >99% of supply
        uint256 attackerSharePercentage = (finalAttackerShares * 10000) / finalTotalSupply;
        assertGt(attackerSharePercentage, 9900, "Attacker should hold >99% of supply");

        // The attacker's share value should have increased significantly due to socialized gain
        // Attacker started with 100 ether, should now be worth much more
        assertGt(finalAttackerAssets, 100 ether, "Attacker's share value should have increased");

        // Total assets should remain in vault (socialized gain is intended)
        assertEq(finalTotalAssets, 6100 ether, "All assets should remain in vault");
    }
}
