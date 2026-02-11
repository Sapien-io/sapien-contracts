// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {ISapienCore} from "../../src/interface/ISapienCore.sol";

/**
 * @title Opus4_L3_MissingInputValidation
 * @notice Opus 4.6 Security Review - L-3 FIX VERIFICATION
 *
 * ORIGINAL FINDING:
 * 1. claimToContribute accepted quantity=0, creating orphaned claims.
 * 2. createProject accepted rewardToken=address(0), creating broken projects.
 *
 * FIX APPLIED:
 * 1. _verifyClaimEligibility now reverts with InvalidAmount() for quantity=0.
 * 2. createProject now reverts with InvalidAddress() for rewardToken=address(0).
 *
 * LOCATION: SapienCore.sol:claimToContribute(), createProject()
 * SEVERITY: Low (now fixed)
 */
contract Opus4_L3_MissingInputValidation is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("opus4-l3-test");
    bytes32 public constant PROJECT_ID_ZERO = keccak256("opus4-l3-zero-token");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        vm.stopPrank();

        // Create a valid project for claim tests
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "opus4-l3-test", 0, 0, 3, 1000, "");
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();
    }

    /**
     * @notice FIX VERIFIED: claimToContribute reverts on quantity=0
     */
    function test_L3_Fix_ZeroQuantityClaimReverts() public {
        console.log("=== L-3 FIX: Zero Quantity Claim Reverts ===");

        vm.prank(contributor);
        vm.expectRevert(ISapienCore.InvalidAmount.selector);
        core.claimToContribute(PROJECT_ID, 0);

        console.log("claimToContribute(0) correctly reverted with InvalidAmount");
        console.log("FIX VERIFIED: Orphaned zero-quantity claims prevented.");
    }

    /**
     * @notice FIX VERIFIED: createProject reverts on rewardToken=address(0)
     */
    function test_L3_Fix_ZeroAddressRewardTokenReverts() public {
        console.log("=== L-3 FIX: Zero Address Reward Token Reverts ===");

        vm.prank(originator);
        vm.expectRevert(ISapienCore.InvalidAddress.selector);
        core.createProject(PROJECT_ID_ZERO, address(0), "opus4-l3-zero-token", 0, 0, 3, 1000, "");

        console.log("createProject(address(0)) correctly reverted with InvalidAddress");
        console.log("FIX VERIFIED: Broken projects with zero reward token prevented.");
    }

    /**
     * @notice Valid quantities still work
     */
    function test_L3_Fix_ValidQuantityStillWorks() public {
        vm.prank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        assertGt(claimId + 1, 0, "Valid claim should succeed");
        console.log("Valid claim (quantity=1) SUCCEEDED");
    }
}
