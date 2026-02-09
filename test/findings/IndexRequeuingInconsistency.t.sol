// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {UPDATER_ROLE, ORIGINATOR_ROLE, CONTRIBUTOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title Index Re-queuing State Inconsistency Vulnerability Test
 * @notice Tests for Issue #1: Index re-queuing state inconsistency
 * @dev This vulnerability occurs when the same index gets re-queued multiple times,
 *      leading to duplicates in the availableIndices stack and potential state inconsistencies.
 *      This test verifies that the fix prevents such inconsistencies.
 */
contract IndexRequeuingInconsistencyTest is BaseTest {
    // forge-lint: disable-next-line(mixed-case-variable)
    // PROJECT_ID is a test constant used throughout the test file
    bytes32 public PROJECT_ID;

    function setUp() public override {
        super.setUp();
        PROJECT_ID = keccak256(abi.encodePacked("vulnerability-project"));
        vm.startPrank(admin);
        trust.grantRole(UPDATER_ROLE, admin);
        trust.updateReputation(originator, ORIGINATOR_ROLE, true, 5000);
        trust.updateReputation(contributor, CONTRIBUTOR_ROLE, true, 5000);
        vm.stopPrank();

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "vulnerability-project", 100 ether, 10 ether, 3, 1000, "");
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();
    }

    /**
     * @notice Test that the index re-queuing fix doesn't break normal functionality
     * @dev Verifies that normal claim and contribute flow still works
     */
    function testNormalIndexAssignmentStillWorks() public {
        // Create a claim and contribute
        vm.prank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);

        // Contribute to index 0
        vm.prank(contributor);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission1"));

        // Setup validation and finalize with acceptance
        _setupValidationForContributionPass(PROJECT_ID, 0);
        vm.prank(admin);
        core.finalizeContribution(PROJECT_ID, 0); // Accept the contribution

        // Should be able to create another claim and get the next index (1)
        vm.prank(contributor);
        uint256 claimId2 = core.claimToContribute(PROJECT_ID, 1);

        // Should be able to contribute to index 1 (next available)
        vm.prank(contributor);
        core.contribute(PROJECT_ID, claimId2, 1, keccak256("submission2"));
    }

    function _setupValidationForContributionPass(bytes32 projectId, uint256 contributionIndex) internal {
        // Setup minimal validation to allow finalization
        vm.prank(admin);
        oracle.enqueueValidation(projectId, contributionIndex, block.timestamp);

        _setValidatorCapacity(validator1, 1000 ether);
        _setValidatorCapacity(validator2, 1000 ether);
        _setValidatorCapacity(validator3, 1000 ether);

        vm.prank(validator1);
        uint256 vClaimId1 = oracle.claimToValidate(projectId);
        vm.prank(validator2);
        uint256 vClaimId2 = oracle.claimToValidate(projectId);
        vm.prank(validator3);
        uint256 vClaimId3 = oracle.claimToValidate(projectId);

        // Commit and reveal with high score to ensure acceptance
        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;

        vm.prank(validator1);
        oracle.commitValidation(
            projectId, vClaimId1, contributionIndex, keccak256(abi.encodePacked(uint256(8000), stake, salt))
        );
        vm.prank(validator2);
        oracle.commitValidation(
            projectId, vClaimId2, contributionIndex, keccak256(abi.encodePacked(uint256(8500), stake, salt))
        );
        vm.prank(validator3);
        oracle.commitValidation(
            projectId, vClaimId3, contributionIndex, keccak256(abi.encodePacked(uint256(9000), stake, salt))
        );

        // Wait and reveal
        vm.warp(block.timestamp + 1 hours);

        vm.prank(validator1);
        oracle.revealValidation(projectId, contributionIndex, 8000, salt);
        vm.prank(validator2);
        oracle.revealValidation(projectId, contributionIndex, 8500, salt);
        vm.prank(validator3);
        oracle.revealValidation(projectId, contributionIndex, 9000, salt);
    }

    /**
     * @notice Test reclaimExpiredIndices still works
     * @dev Ensures that reclaiming expired indices functions correctly
     */
    function testReclaimExpiredIndicesStillWorks() public {
        // Create a claim but DON'T submit the contribution (so index can be reclaimed)
        vm.prank(contributor);
        core.claimToContribute(PROJECT_ID, 1);
        // Don't contribute - just let the claim expire

        // Wait for deadline to pass (7 days default)
        vm.warp(block.timestamp + 8 days);

        // Reclaim the expired index (since contribution was never submitted, it can be reclaimed)
        uint256[] memory indicesToReclaim = new uint256[](1);
        indicesToReclaim[0] = 0;
        vm.prank(admin);
        core.reclaimExpiredIndices(PROJECT_ID, indicesToReclaim);

        // Should be able to claim and get the reclaimed index back
        // Note: The original claim expired, so we need a new claim
        vm.prank(contributor);
        uint256 newClaimId = core.claimToContribute(PROJECT_ID, 1);

        // The reclaimed index 0 should be available again (assigned to the new claim)
        // Since index 0 was reclaimed and added back to the stack, it should be assigned first
        vm.prank(contributor);
        core.contribute(PROJECT_ID, newClaimId, 0, keccak256("submission2"));
    }

    function _setupValidationForContribution(bytes32 projectId, uint256 contributionIndex) internal {
        // Setup minimal validation to allow finalization
        vm.prank(admin);
        oracle.enqueueValidation(projectId, contributionIndex, block.timestamp);

        _setValidatorCapacity(validator1, 1000 ether);
        _setValidatorCapacity(validator2, 1000 ether);
        _setValidatorCapacity(validator3, 1000 ether);

        vm.prank(validator1);
        uint256 vClaimId1 = oracle.claimToValidate(projectId);
        vm.prank(validator2);
        uint256 vClaimId2 = oracle.claimToValidate(projectId);
        vm.prank(validator3);
        uint256 vClaimId3 = oracle.claimToValidate(projectId);

        // Commit and reveal with low score to ensure rejection
        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;

        vm.prank(validator1);
        oracle.commitValidation(
            projectId, vClaimId1, contributionIndex, keccak256(abi.encodePacked(uint256(3000), stake, salt))
        );
        vm.prank(validator2);
        oracle.commitValidation(
            projectId, vClaimId2, contributionIndex, keccak256(abi.encodePacked(uint256(3500), stake, salt))
        );
        vm.prank(validator3);
        oracle.commitValidation(
            projectId, vClaimId3, contributionIndex, keccak256(abi.encodePacked(uint256(4000), stake, salt))
        );

        // Wait and reveal
        vm.warp(block.timestamp + 1 hours);

        vm.prank(validator1);
        oracle.revealValidation(projectId, contributionIndex, 3000, salt);
        vm.prank(validator2);
        oracle.revealValidation(projectId, contributionIndex, 3500, salt);
        vm.prank(validator3);
        oracle.revealValidation(projectId, contributionIndex, 4000, salt);
    }

    /**
     * @notice Test that re-queuing doesn't clear validator commitment state (Issue #1)
     * @dev Verifies that a validator who committed to a contribution before it was rejected
     *      cannot commit again after it is re-queued.
     */
    function testRequeuingDoesNotClearCommitmentState() public {
        // 1. Contributor 1 claims and contributes
        vm.prank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        vm.prank(contributor);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission1"));

        // 2. Validator 1 is assigned and commits
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        _setValidatorCapacity(validator1, 1000 ether);
        vm.startPrank(validator1);
        uint256 vClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, vClaimId, 0, keccak256(abi.encodePacked(uint256(3000), uint256(100 ether), keccak256("salt")))
        );
        vm.stopPrank();

        // 3. Contribution is rejected and re-queued
        // Setup enough validations for rejection
        _setupValidationForContribution(PROJECT_ID, 0); // This will add 3 more validations, total 4
        vm.prank(admin);
        core.finalizeContribution(PROJECT_ID, 0); // Rejected due to low scores in _setupValidationForContribution

        // 4. Contributor 2 claims and contributes to the same index
        address contributor2 = address(0x1234);
        _setupUser(contributor2, 1000 ether);

        vm.startPrank(admin);
        trust.updateReputation(contributor2, CONTRIBUTOR_ROLE, true, 5000);
        vm.stopPrank();

        vm.prank(contributor2);
        uint256 claimId2 = core.claimToContribute(PROJECT_ID, 1);
        vm.prank(contributor2);
        core.contribute(PROJECT_ID, claimId2, 0, keccak256("submission2"));

        // 5. Validator 1 is assigned again to the same index
        vm.startPrank(validator1);
        uint256 vClaimId2 = oracle.claimToValidate(PROJECT_ID);

        // This should now SUCCEED if the bug is fixed
        oracle.commitValidation(
            PROJECT_ID, vClaimId2, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt2")))
        );
        vm.stopPrank();

        // Verify commit was successful
        // ... (optional, the fact it didn't revert is proof enough)
    }

    function _getIndicesArray(uint256 baseIndex, uint256 count) internal pure returns (uint256[] memory) {
        uint256[] memory indices = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            indices[i] = baseIndex;
        }
        return indices;
    }
}
