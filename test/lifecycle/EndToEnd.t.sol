// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.t.sol";
import {CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

contract EndToEndTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("end-to-end-project");
    string public constant SKILL = "EndToEndSkill";

    function setUp() public override {
        super.setUp();
    }

    function test_HappyPath_CompleteFlow() public {
        console.log("=== HAPPY PATH LIFECYCLE ===");

        // 1. Project Setup
        vm.startPrank(originator);
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "end-to-end-project",
            100 ether, // minStakeToClaim
            50 ether, // minStakeToContribute
            3, // minValidations
            1000, // 10% validator rewards
            SKILL
        );

        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();

        // Fix: Set maxValidations to 3 so queue aligns with minValidations
        // Otherwise queue has 10 slots per contribution (default) and we only claim 3
        vm.prank(admin);
        oracle.setProjectMaxValidations(PROJECT_ID, 3);

        // 2. Contributor Claim & Submit
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("work1"));
        vm.stopPrank();

        address contributor2 = makeAddr("contributor2");
        _setupUser(contributor2, 1000 ether);
        vm.startPrank(admin);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor2);
        vm.stopPrank();

        vm.startPrank(contributor2);
        uint256 claimId2 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId2, 1, keccak256("work2"));
        vm.stopPrank();

        // 3. Validators Commit & Reveal
        _setValidatorCapacity(validator1, 1000 ether);
        _setValidatorCapacity(validator2, 1000 ether);
        _setValidatorCapacity(validator3, 1000 ether);

        vm.startPrank(admin);
        trust.validateSkill(validator1, SKILL);
        trust.validateSkill(validator2, SKILL);
        trust.validateSkill(validator3, SKILL);
        vm.stopPrank();

        address[3] memory validators = [validator1, validator2, validator3];
        bytes32[3] memory salts = [keccak256("salt1"), keccak256("salt2"), keccak256("salt3")];
        uint256[3] memory scores = [uint256(8000), uint256(8500), uint256(9000)];

        // Validate BOTH contributions
        for (uint256 k = 0; k < 2; k++) {
            for (uint256 i = 0; i < 3; i++) {
                vm.prank(validators[i]);
                uint256 vClaimId = oracle.claimToValidate(PROJECT_ID);

                bytes32 hash = keccak256(abi.encodePacked(scores[i], uint256(100 ether), salts[i]));
                vm.prank(validators[i]);
                oracle.commitValidation(PROJECT_ID, vClaimId, k, hash);
            }
        }

        vm.warp(block.timestamp + 1 hours + 1);

        for (uint256 k = 0; k < 2; k++) {
            for (uint256 i = 0; i < 3; i++) {
                vm.prank(validators[i]);
                oracle.revealValidation(PROJECT_ID, k, scores[i], salts[i]);
            }
        }

        vm.warp(block.timestamp + 3 days + 1);

        // 4. Batch Finalize
        uint256 balanceBefore = rewardToken.balanceOf(contributor);

        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        core.batchFinalizeContributions(PROJECT_ID, indices);

        // 4.5 Claim rewards after challenge period
        uint256 challengePeriod = core.getProject(PROJECT_ID).config.challengePeriod;
        vm.warp(block.timestamp + challengePeriod + 1);
        core.claimContributionReward(PROJECT_ID, 0);
        core.claimContributionReward(PROJECT_ID, 1);

        // 5. Assertions
        assertEq(uint256(core.getContribution(PROJECT_ID, 0).status), uint256(ContributionStatus.Rewarded));
        assertEq(uint256(core.getContribution(PROJECT_ID, 1).status), uint256(ContributionStatus.Rewarded));

        // Check Rewards
        uint256 reward = rewards.getAvailableRewards(contributor, PROJECT_ID, address(rewardToken));
        assertTrue(reward > 0, "Contributor should have rewards");

        vm.prank(contributor);
        rewards.claimRewards(PROJECT_ID, address(rewardToken), address(0), 0);
        assertTrue(rewardToken.balanceOf(contributor) > balanceBefore);
    }
}
