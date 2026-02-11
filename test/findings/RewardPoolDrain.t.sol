// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {IRewards} from "../../src/interface/IRewards.sol";

/**
 * @title RewardPoolDrainTest
 * @notice Investigation of H-1: Reward Pool Drain Through Repeated Rejections
 *
 * ORIGINAL HYPOTHESIS:
 * The contributor reward formula uses `project.state.totalRewardsAvailable` which is
 * NEVER decremented. Validator rewards are paid on EVERY finalization (accepted AND
 * rejected). Each rejection depletes the actual `projectRewards[projectId][token]`
 * balance in the Rewards contract while leaving the formula's denominator unchanged.
 *
 * ACTUAL FINDING:
 * The vulnerability as originally described does NOT manifest in the current code.
 * On rejection, `oracle.resetContributionState()` (line 722) is called BEFORE
 * `_processValidators()` (line 726). This clears the validation data from the oracle,
 * so when `_distributeValidatorRewards` calls `_fetchValidations()`, it gets an empty
 * array and returns early. NO validator rewards are paid on rejection.
 *
 * HOWEVER, this creates a DIFFERENT issue:
 * - Validators do work (commit, reveal) for rejected contributions
 * - On rejection, their validation data is cleared before reward distribution
 * - They receive NO compensation for their validation effort on rejected contributions
 * - Only outlier slashing still occurs (from the in-memory ConsensusReport)
 *
 * This test documents both the original hypothesis and the actual behavior.
 *
 * LOCATION: SapienCore._finalizeContribution():720-726
 * SEVERITY: FINDING INVALIDATED (H-1 not reproducible), but related unfairness exists
 */
contract RewardPoolDrainTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("drain-test");

    address public contributor2 = makeAddr("contributor2");

    function setUp() public override {
        super.setUp();

        // Grant roles
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor2);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        // Setup contributor2 with stake
        _setupUser(contributor2, 1000 ether);

        // Setup validators with capacity and reputation
        _setupValidator(validator1, 200 ether);
        _setupValidator(validator2, 200 ether);
        _setupValidator(validator3, 200 ether);
    }

    /**
     * @notice INVESTIGATION: Verify that validator rewards are NOT paid on rejection
     * @dev This test disproves the original H-1 hypothesis.
     *
     *      Code flow on rejection:
     *      1. contrib.status = Rejected (line 666)
     *      2. oracle.resetContributionState() clears validations (line 722)
     *      3. _processValidators() → _distributeValidatorRewards() (line 726)
     *      4. _fetchValidations() returns empty array (data was cleared in step 2)
     *      5. Early return — NO validator rewards distributed
     *
     *      Result: Pool balance is unchanged after rejection.
     */
    function test_H1_Investigation_ValidatorRewardsNotPaidOnRejection() public {
        uint256 rewardAmount = 100 ether;
        uint256 quantity = 1;
        uint256 validatorBps = 2500; // 25%

        // 1. Create & fund single-slot project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "drain-test", 0, 0, 3, validatorBps, "");
        rewardToken.approve(address(core), rewardAmount);
        core.fundProject(PROJECT_ID, rewardAmount, quantity);
        vm.stopPrank();

        // Record initial pool balance
        uint256 poolBefore = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));
        console.log("=== H-1: Investigation - Validator Rewards on Rejection ===");
        console.log("Pool before:", poolBefore / 1e18, "tokens");

        // 2. Submit and reject a contribution (score below threshold)
        _submitContribution(contributor, PROJECT_ID, 0);
        _validateContribution(PROJECT_ID, 0, 2000); // Score 2000 < 5000 threshold
        core.finalizeContribution(PROJECT_ID, 0);

        // 3. Check pool after rejection
        uint256 poolAfterRejection = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));
        uint256 drained = poolBefore - poolAfterRejection;

        console.log("Pool after rejection:", poolAfterRejection / 1e18, "tokens");
        console.log("Drained:", drained / 1e18, "tokens");

        // 4. FINDING: Pool is UNCHANGED — no validator rewards were paid
        assertEq(
            poolAfterRejection,
            poolBefore,
            "H-1 INVALIDATED: Pool should be unchanged - no validator rewards paid on rejection"
        );

        console.log("");
        console.log("RESULT: H-1 NOT REPRODUCIBLE");
        console.log("resetContributionState() clears validation data BEFORE");
        console.log("_processValidators() runs, so _distributeValidatorRewards()");
        console.log("gets an empty array and returns early.");
    }

    /**
     * @notice Verify validators receive zero rewards for rejected contributions
     * @dev Even though validators did work (commit + reveal), they get nothing
     *      because resetContributionState clears the data before reward distribution.
     */
    function test_H1_ValidatorsGetNoRewardOnRejection() public {
        uint256 rewardAmount = 100 ether;

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "drain-test", 0, 0, 3, 2500, "");
        rewardToken.approve(address(core), rewardAmount);
        core.fundProject(PROJECT_ID, rewardAmount, 10);
        vm.stopPrank();

        // Record validator reward balances before
        uint256 v1RewardsBefore = rewards.getAvailableValidatorRewards(validator1, PROJECT_ID, address(rewardToken));
        uint256 v2RewardsBefore = rewards.getAvailableValidatorRewards(validator2, PROJECT_ID, address(rewardToken));
        uint256 v3RewardsBefore = rewards.getAvailableValidatorRewards(validator3, PROJECT_ID, address(rewardToken));

        // Submit, validate (reject), finalize
        _submitContribution(contributor, PROJECT_ID, 0);
        _validateContribution(PROJECT_ID, 0, 2000); // Reject
        core.finalizeContribution(PROJECT_ID, 0);

        // Check validator rewards after rejection
        uint256 v1RewardsAfter = rewards.getAvailableValidatorRewards(validator1, PROJECT_ID, address(rewardToken));
        uint256 v2RewardsAfter = rewards.getAvailableValidatorRewards(validator2, PROJECT_ID, address(rewardToken));
        uint256 v3RewardsAfter = rewards.getAvailableValidatorRewards(validator3, PROJECT_ID, address(rewardToken));

        console.log("=== Validator Rewards After Rejection ===");
        console.log("Validator1 reward:", v1RewardsAfter - v1RewardsBefore);
        console.log("Validator2 reward:", v2RewardsAfter - v2RewardsBefore);
        console.log("Validator3 reward:", v3RewardsAfter - v3RewardsBefore);

        // All validators get zero rewards on rejection
        assertEq(v1RewardsAfter, v1RewardsBefore, "V1 should get no reward on rejection");
        assertEq(v2RewardsAfter, v2RewardsBefore, "V2 should get no reward on rejection");
        assertEq(v3RewardsAfter, v3RewardsBefore, "V3 should get no reward on rejection");

        console.log("");
        console.log("CONFIRMED: Validators receive ZERO rewards on rejection.");
        console.log("This means H-1 (pool drain) cannot occur, but validators");
        console.log("are uncompensated for work on rejected contributions.");
    }

    /**
     * @notice Verify the pool formula is consistent after a rejection + acceptance cycle
     * @dev After rejection and re-submission, the accepted contribution should
     *      finalize successfully since the pool was not drained.
     */
    function test_H1_PoolConsistentAfterRejectionThenAcceptance() public {
        uint256 rewardAmount = 100 ether;
        uint256 quantity = 1;
        uint256 validatorBps = 2500; // 25%

        // Create single-slot project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "drain-test", 0, 0, 3, validatorBps, "");
        rewardToken.approve(address(core), rewardAmount);
        core.fundProject(PROJECT_ID, rewardAmount, quantity);
        vm.stopPrank();

        uint256 poolBefore = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));
        console.log("=== Rejection Then Acceptance Cycle ===");
        console.log("Pool initially:", poolBefore / 1e18, "tokens");

        // Reject first submission
        _submitContribution(contributor, PROJECT_ID, 0);
        _validateContribution(PROJECT_ID, 0, 2000);
        core.finalizeContribution(PROJECT_ID, 0);

        uint256 poolAfterReject = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));
        console.log("Pool after rejection:", poolAfterReject / 1e18, "tokens");

        // Accept second submission on the same slot
        _submitContribution(contributor2, PROJECT_ID, 0);
        _validateContribution(PROJECT_ID, 0, 8000);
        core.finalizeContribution(PROJECT_ID, 0);

        // Claim reward after challenge period
        uint256 challengePeriod = core.getProject(PROJECT_ID).config.challengePeriod;
        vm.warp(block.timestamp + challengePeriod + 1);
        core.claimContributionReward(PROJECT_ID, 0);

        uint256 poolAfterAccept = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));
        console.log("Pool after acceptance:", poolAfterAccept / 1e18, "tokens");

        // Pool should be depleted by contributor reward + validator rewards
        assertLt(poolAfterAccept, poolBefore, "Pool should decrease after acceptance");

        // Check contributor got their reward
        uint256 contributorReward = rewards.getAvailableRewards(contributor2, PROJECT_ID, address(rewardToken));
        console.log("Contributor reward:", contributorReward / 1e18, "tokens");
        assertGt(contributorReward, 0, "Contributor should receive reward on acceptance");

        console.log("");
        console.log("CONFIRMED: Rejection does not drain pool.");
        console.log("Subsequent acceptance works correctly.");
    }

    /**
     * @notice Verify the reward formula uses static totalRewardsAvailable
     * @dev Even though the pool isn't drained on rejection, the formula still uses
     *      the ORIGINAL totalRewardsAvailable. This is correct behavior when validator
     *      rewards aren't paid on rejection, but worth documenting.
     */
    function test_H1_RewardFormula_UsesStaticTotal() public {
        uint256 rewardAmount = 100 ether;
        uint256 quantity = 2;
        uint256 validatorBps = 1000; // 10%

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "drain-test", 0, 0, 3, validatorBps, "");
        rewardToken.approve(address(core), rewardAmount);
        core.fundProject(PROJECT_ID, rewardAmount, quantity);
        vm.stopPrank();

        // Check totalRewardsAvailable is set
        uint256 totalRewards = getProjectRewards(PROJECT_ID);
        uint256 totalQuantity = getProjectQuantity(PROJECT_ID);
        console.log("=== Static Reward Formula Analysis ===");
        console.log("totalRewardsAvailable:", totalRewards / 1e18, "tokens");
        console.log("totalQuantityAvailable:", totalQuantity);

        // Expected per-slot contributor reward:
        // (100 * (10000 - 1000)) / (10000 * 2) = 100 * 9000 / 20000 = 45
        uint256 expectedContributorReward = (totalRewards * (10000 - validatorBps)) / (10000 * totalQuantity);
        console.log("Expected contributor reward per slot:", expectedContributorReward / 1e18, "tokens");

        // Accept slot 0
        _submitContribution(contributor, PROJECT_ID, 0);
        _validateContribution(PROJECT_ID, 0, 8000);
        core.finalizeContribution(PROJECT_ID, 0);

        // Claim reward after challenge period
        uint256 challengePeriod = core.getProject(PROJECT_ID).config.challengePeriod;
        vm.warp(block.timestamp + challengePeriod + 1);
        core.claimContributionReward(PROJECT_ID, 0);

        uint256 actualReward = rewards.getAvailableRewards(contributor, PROJECT_ID, address(rewardToken));
        console.log("Actual contributor reward:", actualReward / 1e18, "tokens");
        assertEq(actualReward, expectedContributorReward, "Reward should match formula");

        // Verify totalRewardsAvailable hasn't changed
        uint256 totalRewardsAfter = getProjectRewards(PROJECT_ID);
        assertEq(totalRewardsAfter, totalRewards, "totalRewardsAvailable is static (never decremented)");

        console.log("totalRewardsAvailable after finalization:", totalRewardsAfter / 1e18, "(unchanged)");
    }

    // ============================================
    // HELPERS
    // ============================================

    function _setupValidator(address v, uint256 capacity) internal {
        vm.startPrank(admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();
        vm.prank(v);
        oracle.setValidatorCapacity(capacity);
    }

    function _submitContribution(address user, bytes32 projectId, uint256 expectedIndex) internal {
        vm.startPrank(user);
        uint256 claimId = core.claimToContribute(projectId, 1);
        core.contribute(projectId, claimId, expectedIndex, keccak256(abi.encodePacked("work", expectedIndex, user)));
        vm.stopPrank();
    }

    function _validateContribution(bytes32 projectId, uint256 contribIndex, uint256 score) internal {
        uint256 stake = 100 ether;

        _commitAndReveal(validator1, projectId, contribIndex, score, stake);
        _commitAndReveal(validator2, projectId, contribIndex, score, stake);
        _commitAndReveal(validator3, projectId, contribIndex, score, stake);
    }

    function _commitAndReveal(address v, bytes32 projectId, uint256 contribIndex, uint256 score, uint256 stake)
        internal
    {
        bytes32 salt = keccak256(abi.encodePacked(v, score, contribIndex, block.timestamp));
        bytes32 commitHash = keccak256(abi.encodePacked(score, stake, salt));

        vm.startPrank(v);
        uint256 claimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, claimId, contribIndex, commitHash);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(v);
        oracle.revealValidation(projectId, contribIndex, score, salt);
    }
}
