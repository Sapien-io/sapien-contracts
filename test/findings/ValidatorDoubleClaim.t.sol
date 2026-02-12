// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ISharedTypes, ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title ValidatorDoubleClaimTest
 * @notice Test demonstrating that a validator can claim multiple slots for the same contribution index,
 *         wasting queue slots and potentially blocking consensus.
 */
contract ValidatorDoubleClaimTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");

    function setUp() public override {
        super.setUp();

        // Grant roles to participants
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        vm.stopPrank();

        // Set validator capacity (enough for many validations)
        _setupValidator(validator1, 1000 ether);
        _setupValidator(validator2, 1000 ether);

        // Create and fund project requiring 3 validations
        vm.startPrank(originator);
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "test-project",
            10 ether, // minStakeToClaim
            10 ether, // minStakeToContribute
            3, // numberOfValidations
            1000, // validatorRewardBasisPoints (10%)
            "" // No required skill
        );

        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();
    }

    function test_ValidatorCanClaimMultipleSlotsForSameIndex() public {
        // 1. Contributor submits work (index 0)
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission1"));
        vm.stopPrank();

        // Verify queue has 3 slots for index 0
        uint256 pendingCount = oracle.getPendingValidationCount(PROJECT_ID);
        assertEq(pendingCount, 3, "Queue should have 3 slots for index 0");

        // 2. Validator 1 claims 2 slots
        vm.startPrank(validator1);
        uint256 v1ClaimId1 = oracle.claimToValidate(PROJECT_ID);
        uint256 v1ClaimId2 = oracle.claimToValidate(PROJECT_ID);
        vm.stopPrank();

        // Check that both claims are for index 0
        (,, uint256 index1,,,,) = oracle.validationClaims(PROJECT_ID, v1ClaimId1);
        (,, uint256 index2,,,,) = oracle.validationClaims(PROJECT_ID, v1ClaimId2);

        assertEq(index1, 0, "Claim 1 should be for index 0");
        assertEq(index2, 0, "Claim 2 should be for index 0");
        console.log("Validator1 claimed two slots for the same index (0)");

        // 3. Validator 1 tries to commit for both claims
        vm.startPrank(validator1);
        uint256 stake = 100 ether;
        bytes32 salt1 = keccak256("salt1");
        bytes32 commitHash1 = keccak256(abi.encodePacked(uint256(8000), stake, salt1));

        // First commit succeeds
        oracle.commitValidation(PROJECT_ID, v1ClaimId1, 0, commitHash1);

        // Second commit fails with AlreadyCommitted
        vm.expectRevert(abi.encodeWithSignature("AlreadyCommitted(address)", validator1));
        oracle.commitValidation(PROJECT_ID, v1ClaimId2, 0, commitHash1);
        vm.stopPrank();

        console.log("Validator1 could only fulfill one of the two claims");

        // 4. Validator 2 claims the last remaining slot
        vm.prank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(PROJECT_ID);

        // Verify it's also for index 0
        (,, uint256 v2Index,,,,) = oracle.validationClaims(PROJECT_ID, v2ClaimId);
        assertEq(v2Index, 0, "Validator2 claim should be for index 0");

        // Validator 2 commits and reveals
        vm.startPrank(validator2);
        bytes32 salt2 = keccak256("salt2");
        bytes32 commitHash2 = keccak256(abi.encodePacked(uint256(8000), stake, salt2));
        oracle.commitValidation(PROJECT_ID, v2ClaimId, 0, commitHash2);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt2);
        vm.stopPrank();

        // Validator 1 reveals their single commit
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt1);

        // 5. Check if consensus is ready
        // numberOfValidations is 3, but only 2 unique validators could claim/submit
        ISharedTypes.ConsensusReport memory report = oracle.getConsensus(PROJECT_ID, 0);
        assertEq(report.isReady, false, "Consensus should NOT be ready (2/3 validations)");
        assertEq(report.validatorCount, 2, "Should only have 2 validations");

        console.log("Consensus blocked because Validator1 hoarded a slot they couldn't fulfill");
    }

    // Helper function to set up validator
    function _setupValidator(address validator, uint256 capacity) internal {
        _setupUser(validator, capacity);
        vm.startPrank(admin);
        trust.updateReputation(validator, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();

        vm.prank(validator);
        oracle.setValidatorCapacity(capacity);
    }
}
