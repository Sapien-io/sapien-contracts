// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "forge-std/Test.sol";
import {BaseTest} from "../BaseTest.t.sol";
import {CONTRIBUTOR_ROLE, VALIDATOR_ROLE, ORIGINATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {ISapienCore} from "../../src/interface/ISapienCore.sol";

contract SecurityFixesTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("security-project");
    string public constant SKILL = "SecuritySkill";

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        vm.stopPrank();
    }

    function test_DilutionProtection() public {
        vm.startPrank(originator);

        // 1. Create Project
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "security-project",
            100 ether, // minStakeToClaim
            50 ether, // minStakeToContribute
            1, // numberOfValidations
            1000, // 10% validator rewards
            SKILL
        );

        // 2. Initial Funding: 1000 tokens for 10 slots = 100 tokens/slot
        rewardToken.approve(address(core), 10000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);

        // 3. Attempt Dilution: 1 token for 10 slots = 0.1 tokens/slot
        // Should revert because 0.1 < 100
        vm.expectRevert(ISapienCore.RewardDilutionNotAllowed.selector);
        core.fundProject(PROJECT_ID, 1 ether, 10);

        // 4. Proper Funding: 1000 tokens for 10 slots = 100 tokens/slot
        // Should succeed
        core.fundProject(PROJECT_ID, 1000 ether, 10);

        // 5. Increasing Rate: 2000 tokens for 10 slots = 200 tokens/slot
        // Should succeed
        core.fundProject(PROJECT_ID, 2000 ether, 10);

        vm.stopPrank();
    }

    function test_ConfigurableConsensusThreshold() public {
        // Setup project with 1 validation required for simplicity
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "security-project", 100 ether, 50 ether, 1, 1000, SKILL);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();

        // Admin sets high threshold
        vm.prank(admin);
        core.setConsensusThreshold(9000); // 90%

        // Contributor submits
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("work"));
        vm.stopPrank();

        // Validator submits score 8000 (80%)
        // 80% < 90%, so should be REJECTED
        _setValidatorCapacity(validator1, 1000 ether);
        vm.startPrank(admin);
        trust.validateSkill(validator1, SKILL);
        vm.stopPrank();

        vm.startPrank(validator1);
        uint256 vClaimId = oracle.claimToValidate(PROJECT_ID);
        bytes32 hash = keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt")));
        oracle.commitValidation(PROJECT_ID, vClaimId, 0, hash);
        vm.warp(block.timestamp + 1 hours + 1);
        oracle.revealValidation(PROJECT_ID, 0, 8000, keccak256("salt"));
        vm.stopPrank();

        // Finalize
        core.finalizeContribution(PROJECT_ID, 0);

        // Check Rejected
        // When rejected, the contribution is deleted to allow reuse of the index
        // So we check that it no longer exists (submittedAt == 0)
        uint256 submittedAt = core.getContribution(PROJECT_ID, 0).submittedAt;
        assertEq(submittedAt, 0, "Should be rejected and deleted");

        // Now test Acceptance with lower threshold
        // Contributor submits another work (index 1)
        // Since index 0 was reclaimed/deleted, we can likely reuse it if we claim again?
        // But for clarity, let's just make a new claim.

        vm.startPrank(contributor);
        uint256 claimId2 = core.claimToContribute(PROJECT_ID, 1);
        // It might assign index 0 again since it's available.
        // Let's get the assigned index from the event or assume it's 0 because stackTop popped it back?
        // _addToAvailableIndices adds to stack.
        // _assignIndices takes from stack if > 0.
        // So yes, it should be index 0 again.

        core.contribute(PROJECT_ID, claimId2, 0, keccak256("work2"));
        vm.stopPrank();

        // Admin sets low threshold
        vm.prank(admin);
        core.setConsensusThreshold(4000); // 40%

        // Validator submits score 4500 (45%)
        // 45% >= 40%, should be ACCEPTED
        vm.startPrank(validator1);
        uint256 vClaimId2 = oracle.claimToValidate(PROJECT_ID);
        bytes32 hash2 = keccak256(abi.encodePacked(uint256(4500), uint256(100 ether), keccak256("salt2")));
        oracle.commitValidation(PROJECT_ID, vClaimId2, 0, hash2);
        vm.warp(block.timestamp + 1 hours + 1);
        oracle.revealValidation(PROJECT_ID, 0, 4500, keccak256("salt2"));
        vm.stopPrank();

        core.finalizeContribution(PROJECT_ID, 0);

        ContributionStatus status = core.getContribution(PROJECT_ID, 0).status;
        assertEq(uint256(status), uint256(ContributionStatus.Validated), "Should be accepted (4500 >= 4000)");
    }
}
