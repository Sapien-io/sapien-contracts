// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../BaseTest.t.sol";
import "forge-std/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title CEIFixVerificationTest
 * @notice Comprehensive tests to verify CEI pattern fixes don't break functionality
 * @dev Tests that state changes work correctly after implementing CEI pattern
 */
contract CEIFixVerificationTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");

    function setUp() public override {
        super.setUp();

        // Setup roles
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "test-project", 0, 0, 1, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();
    }

    /**
     * @notice Test that _contribute state changes work correctly after CEI fix
     */
    function test_Contribute_StateChanges_CorrectAfterCEIFix() public {
        // Setup contributor
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        vm.stopPrank();

        // Get initial state
        uint256 initialSubmittedCount = _getClaimSubmittedCount(PROJECT_ID, claimId);
        uint256 initialSubmittedQuantity = _getProjectSubmittedQuantity(PROJECT_ID);
        uint256 initialActiveClaimedQuantity = _getProjectActiveClaimedQuantity(PROJECT_ID);

        // Contribute
        vm.prank(contributor);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));

        // Verify all state changes occurred correctly
        uint256 finalSubmittedCount = _getClaimSubmittedCount(PROJECT_ID, claimId);
        uint256 finalSubmittedQuantity = _getProjectSubmittedQuantity(PROJECT_ID);
        uint256 finalActiveClaimedQuantity = _getProjectActiveClaimedQuantity(PROJECT_ID);

        assertEq(finalSubmittedCount, initialSubmittedCount + 1, "Submitted count should increment");
        assertEq(finalSubmittedQuantity, initialSubmittedQuantity + 1, "Submitted quantity should increment");
        assertEq(
            finalActiveClaimedQuantity, initialActiveClaimedQuantity - 1, "Active claimed quantity should decrement"
        );

        // Verify contribution was recorded
        assertEq(core.getContribution(PROJECT_ID, 0).contributor, contributor, "Contributor should be set");
        assertEq(core.getContribution(PROJECT_ID, 0).submittedAt, block.timestamp, "Submitted timestamp should be set");

        // Verify claim status updated
        assertEq(
            uint256(getClaimStatus(PROJECT_ID, claimId)), uint256(ClaimStatus.Fulfilled), "Claim should be fulfilled"
        );
    }

    /**
     * @notice Test that _finalizeContribution state changes work correctly after CEI fix
     */
    function test_FinalizeContribution_StateChanges_CorrectAfterCEIFix() public {
        // Setup contribution
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Setup validators
        _setupValidator(validator1, 100 ether);
        _setupValidator(validator2, 100 ether);

        // Validators validate
        _validateContribution(validator1, PROJECT_ID, 0, 8000);
        _validateContribution(validator2, PROJECT_ID, 0, 8000);

        // Get initial state
        uint256 initialRewardedQuantity = _getProjectRewardedQuantity(PROJECT_ID);
        uint256 initialFinalizedCount = _getClaimFinalizedCount(PROJECT_ID, claimId);
        uint256 initialSubmittedQuantity = _getProjectSubmittedQuantity(PROJECT_ID);

        // Fast forward to allow finalization
        vm.warp(block.timestamp + 4 days);

        // Finalize
        core.finalizeContribution(PROJECT_ID, 0);

        // Verify state changes
        uint256 finalRewardedQuantity = _getProjectRewardedQuantity(PROJECT_ID);
        uint256 finalFinalizedCount = _getClaimFinalizedCount(PROJECT_ID, claimId);
        uint256 finalSubmittedQuantity = _getProjectSubmittedQuantity(PROJECT_ID);

        assertEq(finalRewardedQuantity, initialRewardedQuantity + 1, "Rewarded quantity should increment");
        assertEq(finalFinalizedCount, initialFinalizedCount + 1, "Finalized count should increment");
        assertEq(finalSubmittedQuantity, initialSubmittedQuantity, "Submitted quantity should not change for accepted");

        // Verify contribution status
        assertEq(
            uint256(core.getContribution(PROJECT_ID, 0).status),
            uint256(ContributionStatus.Rewarded),
            "Contribution should be rewarded"
        );
    }

    /**
     * @notice Test rejected contribution state changes after CEI fix
     */
    function test_FinalizeContribution_Rejected_StateChanges_CorrectAfterCEIFix() public {
        // Setup contribution
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Setup validators with low scores (rejection)
        _setupValidator(validator1, 100 ether);
        _setupValidator(validator2, 100 ether);

        // Validators validate with low scores
        _validateContribution(validator1, PROJECT_ID, 0, 3000); // Low score
        _validateContribution(validator2, PROJECT_ID, 0, 2000); // Low score

        // Get initial state
        uint256 initialSubmittedQuantity = _getProjectSubmittedQuantity(PROJECT_ID);
        uint256 initialFinalizedCount = _getClaimFinalizedCount(PROJECT_ID, claimId);

        // Fast forward to allow finalization
        vm.warp(block.timestamp + 4 days);

        // Finalize (should reject)
        core.finalizeContribution(PROJECT_ID, 0);

        // Verify state changes for rejected contribution
        uint256 finalSubmittedQuantity = _getProjectSubmittedQuantity(PROJECT_ID);
        uint256 finalFinalizedCount = _getClaimFinalizedCount(PROJECT_ID, claimId);

        assertEq(
            finalSubmittedQuantity, initialSubmittedQuantity - 1, "Submitted quantity should decrement for rejected"
        );
        assertEq(finalFinalizedCount, initialFinalizedCount + 1, "Finalized count should increment");

        // Verify contribution was deleted (rejected contributions are reset)
        assertEq(core.getContribution(PROJECT_ID, 0).submittedAt, 0, "Contribution should be deleted");
    }

    /**
     * @notice Test multiple contributions to verify state consistency
     */
    function test_MultipleContributions_StateConsistency() public {
        // Create multiple contributions
        vm.startPrank(contributor);
        uint256 claimId1 = core.claimToContribute(PROJECT_ID, 2);
        core.contribute(PROJECT_ID, claimId1, 0, keccak256("submission1"));
        core.contribute(PROJECT_ID, claimId1, 1, keccak256("submission2"));
        vm.stopPrank();

        // Verify state
        assertEq(_getClaimSubmittedCount(PROJECT_ID, claimId1), 2, "Claim should have 2 submissions");
        assertEq(_getProjectSubmittedQuantity(PROJECT_ID), 2, "Project should have 2 submitted");
        assertEq(_getProjectActiveClaimedQuantity(PROJECT_ID), 0, "No active claimed quantity");

        // Verify both contributions exist
        assertEq(core.getContribution(PROJECT_ID, 0).contributor, contributor, "Contribution 0 should exist");
        assertEq(core.getContribution(PROJECT_ID, 1).contributor, contributor, "Contribution 1 should exist");
    }

    /**
     * @notice Test that external calls still work correctly after CEI fix
     */
    function test_ExternalCalls_StillWorkAfterCEIFix() public {
        // Setup contribution
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Verify oracle was notified (check through contribution state)
        // Note: Oracle stores contributor through setContributionContributor call
        // We verify this indirectly by checking the contribution exists
        assertEq(
            core.getContribution(PROJECT_ID, 0).contributor, contributor, "Oracle should have contributor recorded"
        );

        // Setup validators
        _setupValidator(validator1, 100 ether);
        _validateContribution(validator1, PROJECT_ID, 0, 8000);

        // Fast forward and finalize
        vm.warp(block.timestamp + 4 days);
        core.finalizeContribution(PROJECT_ID, 0);

        // Verify rewards were distributed
        uint256 contributorReward = rewards.getAvailableRewards(contributor, PROJECT_ID, address(rewardToken));
        assertTrue(contributorReward > 0, "Contributor should have rewards");
    }

    /**
     * @notice Test that claim unlock works correctly after CEI fix
     */
    function test_ClaimUnlock_WorksAfterCEIFix() public {
        // Create project with stake requirement
        bytes32 projectId2 = keccak256("project2");
        vm.startPrank(originator);
        core.createProject(projectId2, address(rewardToken), "project2", 10 ether, 0, 1, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(projectId2, 100 ether, 1);
        vm.stopPrank();

        // Contributor claims and contributes
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(projectId2, 1);
        uint256 lockedBefore = vault.getLockedStake(contributor);
        assertEq(lockedBefore, 10 ether, "Stake should be locked");

        core.contribute(projectId2, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Setup validator
        _setupValidator(validator1, 100 ether);
        _validateContribution(validator1, projectId2, 0, 8000);

        // Fast forward and finalize
        vm.warp(block.timestamp + 4 days);
        core.finalizeContribution(projectId2, 0);

        // Verify stake was unlocked
        uint256 lockedAfter = vault.getLockedStake(contributor);
        assertEq(lockedAfter, 0, "Stake should be unlocked after finalization");
    }

    // Helper functions
    function _getClaimSubmittedCount(bytes32 projectId, uint256 claimId) internal view returns (uint256) {
        return core.getClaim(projectId, claimId).submittedCount;
    }

    function _getProjectSubmittedQuantity(bytes32 projectId) internal view returns (uint256) {
        return core.getProject(projectId).state.submittedQuantity;
    }

    function _getProjectActiveClaimedQuantity(bytes32 projectId) internal view returns (uint256) {
        return core.getProject(projectId).state.activeClaimedQuantity;
    }

    function _getProjectRewardedQuantity(bytes32 projectId) internal view returns (uint256) {
        return core.getProject(projectId).state.rewardedQuantity;
    }

    function _getClaimFinalizedCount(bytes32 projectId, uint256 claimId) internal view returns (uint256) {
        return core.getClaim(projectId, claimId).finalizedCount;
    }

    function _setupValidator(address v, uint256 amount) internal {
        _setupUser(v, amount);
        vm.startPrank(admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();

        vm.prank(v);
        oracle.setValidatorCapacity(amount);
    }

    function _validateContribution(address validator, bytes32 projectId, uint256 contributionIndex, uint256 score)
        internal
    {
        vm.startPrank(validator);
        uint256 vClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(
            projectId,
            vClaimId,
            contributionIndex,
            keccak256(abi.encodePacked(score, uint256(100 ether), keccak256("salt")))
        );
        vm.warp(block.timestamp + 1 hours + 1);
        oracle.revealValidation(projectId, contributionIndex, score, keccak256("salt"));
        vm.stopPrank();
    }
}
