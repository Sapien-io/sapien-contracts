// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {VALIDATOR_ROLE, UPDATER_ROLE} from "../../src/interface/ISharedTypes.sol";

contract ExpiredCommitmentTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("expired-project");

    function setUp() public override {
        super.setUp();
    }

    function testExpiredCommitmentSlashing() public {
        // Create project
        vm.prank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "expired-project", 100 ether, 0, 1, 500, "test");

        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();

        // Contributor contributes
        vm.prank(admin);
        trust.validateSkill(contributor, "test");

        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("sub"));
        vm.stopPrank();

        // Validator 1 commits
        _setupValidator(validator1, 1000 ether);
        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v1ClaimId, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt1")))
        );
        vm.stopPrank();

        // Validator 2 commits (will expire)
        _setupValidator(validator2, 1000 ether);
        vm.startPrank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v2ClaimId, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt2")))
        );
        vm.stopPrank();

        // Validator 1 reveals
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 8000, keccak256("salt1"));

        // Warp past reveal deadline (default is 3 days)
        vm.warp(block.timestamp + 4 days);

        // Validator 2 does NOT reveal

        // Finalize
        uint256 v2BalanceBefore = vault.getStake(validator2);

        console.log("Current time:", block.timestamp);

        // This should now succeed because Validator 2's commit is expired and no longer blocks consensus
        core.finalizeContribution(PROJECT_ID, 0);

        uint256 v2BalanceAfter = vault.getStake(validator2);

        console.log("Validator 2 balance before:", v2BalanceBefore);
        console.log("Validator 2 balance after:", v2BalanceAfter);

        // Validator 2 should be slashed
        assertTrue(v2BalanceAfter < v2BalanceBefore);
        uint256 lost = v2BalanceBefore - v2BalanceAfter;
        console.log("Actual loss (socialized):", lost);
        assertTrue(lost > 50 ether && lost <= 100 ether);

        // Verify contribution is rewarded
        assertEq(uint256(core.getContribution(PROJECT_ID, 0).status), uint256(ContributionStatus.Rewarded));
    }

    function _setupValidator(address v, uint256 amount) internal {
        _setupUser(v, amount);
        vm.startPrank(admin);
        trust.grantRole(UPDATER_ROLE, admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        trust.validateSkill(v, "test");
        vm.stopPrank();

        vm.prank(v);
        oracle.setValidatorCapacity(amount);
    }
}
