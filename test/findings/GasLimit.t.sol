// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

contract GasLimitTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");

    function setUp() public override {
        super.setUp();
    }

    function testUnboundedValidatorLoop() public {
        // Create project with many validators
        uint256 validatorCount = 50; // Try 50 validators

        // Register project with numberOfValidations matching validator count
        bytes32 projectId = keccak256("gas-project");
        vm.startPrank(originator);
        core.createProject(projectId, address(rewardToken), "gas-project", 100 ether, 10, validatorCount, 500, "test");
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(projectId, 1000 ether, 10);
        vm.stopPrank();

        // Contributor contributes
        vm.prank(admin);
        trust.validateSkill(contributor, "test");

        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(projectId, 1);
        core.contribute(projectId, claimId, 0, keccak256("sub"));
        vm.stopPrank();

        // Many validators claim and commit
        for (uint160 i = 0; i < validatorCount; i++) {
            address v = address(uint160(0x1000 + i));
            _setupValidator(v, 1000 ether);
            vm.prank(v);
            uint256 vClaimId = oracle.claimToValidate(projectId);
            vm.prank(v);
            oracle.commitValidation(
                projectId,
                vClaimId,
                0,
                keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt")))
            );
        }

        // Warp to reveal (more than 1 day to avoid skill validation cooldown)
        vm.warp(block.timestamp + 2 days);

        // All validators reveal
        for (uint160 i = 0; i < validatorCount; i++) {
            address v = address(uint160(0x1000 + i));
            vm.prank(v);
            oracle.revealValidation(projectId, 0, 8000, keccak256("salt"));
        }

        // Finalize
        uint256 gasBefore = gasleft();
        core.finalizeContribution(projectId, 0);
        uint256 gasUsed = gasBefore - gasleft();

        console.log("Gas used for 50 validators:", gasUsed);
        // If this is too high, it's a problem.
    }

    function _setupValidator(address v, uint256 amount) internal {
        _setupUser(v, amount);
        vm.startPrank(admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        trust.validateSkill(v, "test");
        vm.stopPrank();

        vm.prank(v);
        oracle.setValidatorCapacity(amount);
    }
}
