// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {IRewards} from "../../src/interface/IRewards.sol";
import {Rewards} from "../../src/Rewards.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title Opus4_L5_RewardsCoreReassignment
 * @notice Opus 4.6 Security Review - L-5 FIX VERIFICATION
 *
 * ORIGINAL FINDING:
 * IRewards defined error CoreAlreadySet() but it was never used. Admin could
 * re-set core at any time, allowing a compromised admin to redirect to a
 * malicious contract that drains all project rewards.
 *
 * FIX APPLIED:
 * setCore now enforces one-time-set: reverts with CoreAlreadySet if core != address(0).
 *
 * LOCATION: Rewards.sol:setCore()
 * SEVERITY: Low (now fixed)
 */
contract Opus4_L5_RewardsCoreReassignment is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice FIX VERIFIED: Core cannot be re-assigned after initial set
     */
    function test_L5_Fix_CoreCannotBeReassigned() public {
        console.log("=== L-5 FIX: Core Re-Assignment Blocked ===");

        // Core is already set in BaseTest via _setupRolesAndAlgorithms
        address currentCore = rewards.core();
        console.log("Current core:", currentCore);
        assertTrue(currentCore != address(0), "Core should already be set");

        // Admin tries to re-set core - should REVERT
        vm.prank(admin);
        vm.expectRevert(IRewards.CoreAlreadySet.selector);
        rewards.setCore(makeAddr("newCore"));

        console.log("setCore() correctly REVERTED with CoreAlreadySet");
        assertEq(rewards.core(), currentCore, "Core should be unchanged");

        console.log("FIX VERIFIED: Core is one-time-set. Re-assignment blocked.");
    }

    /**
     * @notice First-time set still works on a fresh Rewards contract
     */
    function test_L5_Fix_FirstTimeSetWorks() public {
        console.log("=== L-5 FIX: First-Time Set Works ===");

        // Deploy a fresh Rewards contract (core not yet set)
        address rewardsImpl = address(new Rewards());
        bytes memory rewardsInitData = abi.encodeWithSelector(Rewards.initialize.selector, admin);
        Rewards freshRewards = Rewards(address(new ERC1967Proxy(rewardsImpl, rewardsInitData)));

        assertEq(freshRewards.core(), address(0), "Core should be unset initially");

        // First set succeeds
        vm.prank(admin);
        freshRewards.setCore(address(core));
        assertEq(freshRewards.core(), address(core), "Core should be set");
        console.log("First setCore() SUCCEEDED");

        // Second set fails
        vm.prank(admin);
        vm.expectRevert(IRewards.CoreAlreadySet.selector);
        freshRewards.setCore(makeAddr("attacker"));
        console.log("Second setCore() correctly REVERTED");

        console.log("FIX VERIFIED: One-time-set pattern working correctly.");
    }

    /**
     * @notice Non-admin still cannot set core
     */
    function test_L5_Fix_NonAdminCannotSetCore() public {
        address attacker = makeAddr("attacker");

        vm.prank(attacker);
        vm.expectRevert();
        rewards.setCore(attacker);

        console.log("Non-admin correctly blocked from setting core");
    }
}
