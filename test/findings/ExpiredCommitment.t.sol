// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {VALIDATOR_ROLE, UPDATER_ROLE} from "../../src/interface/ISharedTypes.sol";

contract ExpiredCommitmentTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("expired-project");

    function setUp() public override {
        super.setUp();
    }

    function testExpiredCommitmentSlashing() public {
        // Create project with 2 validation slots.
        // Validator 1 reveals, Validator 2's commit expires.
        // After cancelling the expired commitment (which slashes v2 and re-queues the slot),
        // Validator 3 fills the freed slot so consensus becomes ready for finalization.
        vm.prank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "expired-project", 100 ether, 0, 2, 500, "test");

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

        // Validator 1 commits and reveals
        _setupValidator(validator1, 1000 ether);
        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v1ClaimId, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt1")))
        );
        vm.stopPrank();

        // Validator 2 commits (will expire - never reveals)
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

        // Validator 2 does NOT reveal — their commitment is now expired

        // Cancel validator 2's expired commitment: this slashes v2 and re-queues the slot
        uint256 v2BalanceBefore = vault.getStake(validator2);
        console.log("Current time:", block.timestamp);

        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator2);

        uint256 v2BalanceAfter = vault.getStake(validator2);
        console.log("Validator 2 balance before:", v2BalanceBefore);
        console.log("Validator 2 balance after:", v2BalanceAfter);

        // Validator 2 should be slashed for failing to reveal
        assertTrue(v2BalanceAfter < v2BalanceBefore, "Validator 2 should be slashed for expired commitment");
        uint256 lost = v2BalanceBefore - v2BalanceAfter;
        console.log("Actual loss:", lost);
        assertTrue(lost > 0, "Slashing amount should be positive");

        // Validator 3 fills the re-queued slot so consensus can be reached
        _setupValidator(validator3, 1000 ether);
        vm.startPrank(validator3);
        uint256 v3ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v3ClaimId, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt3")))
        );
        vm.stopPrank();

        vm.prank(validator3);
        oracle.revealValidation(PROJECT_ID, 0, 8000, keccak256("salt3"));

        // Finalize - now 2 revealed validations meet numberOfValidations=2
        core.finalizeContribution(PROJECT_ID, 0);

        // Verify contribution is validated (consensus score 8000 > threshold 5000)
        assertEq(uint256(core.getContribution(PROJECT_ID, 0).status), uint256(ContributionStatus.Validated));
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
