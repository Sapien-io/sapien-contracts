// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {ISapienCore} from "../../src/interface/ISapienCore.sol";

/**
 * @title UnrecoverableRewardsFromRejections
 * @notice Test demonstrating H-1: Unrecoverable Rewards from Rejected Contributions
 *
 * ISSUE DESCRIPTION (ORIGINAL):
 * When contributions are rejected (score below quality threshold), the contributor's reward portion
 * remains permanently stuck in the Rewards contract with no recovery mechanism.
 *
 * FIX IMPLEMENTED (Option 1: Automatic Reclaim):
 * When contributions are rejected, the rewards automatically remain in projectRewards and
 * become available for future contributors. An event is emitted for transparency.
 * This test now verifies both the original issue and the fix.
 *
 * ROOT CAUSE:
 * Rewards are pre-allocated to projectRewards[projectId][token] when a task is funded.
 * On validated contributions, tokens move to claimable balances.
 * On rejected contributions, no distribution occurs but rewards remain available.
 *
 * IMPACT (WITHOUT FIX):
 * Permanent loss of funds proportional to rejection rate.
 * A project with 10% rejections and 100,000 USDC rewards loses 9,000 USDC forever.
 *
 * IMPACT (WITH FIX):
 * Zero loss - rewards remain in pool for future contributions.
 */
contract UnrecoverableRewardsFromRejectionsTest is BaseTest {
    bytes32 projectId;
    uint256 constant TOTAL_REWARDS = 10_000 ether; // Match BaseTest funding
    uint256 constant TOTAL_QUANTITY = 10;
    uint256 constant REWARD_PER_CONTRIBUTION = TOTAL_REWARDS / TOTAL_QUANTITY;

    function setUp() public override {
        super.setUp();

        // Grant roles to participants
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        // Set validator capacity
        _setValidatorCapacity(validator1, 100 ether);
        _setValidatorCapacity(validator2, 100 ether);
        _setValidatorCapacity(validator3, 100 ether);

        // Create and fund project
        vm.startPrank(originator);
        projectId = keccak256("test-project");
        core.createProject(
            projectId,
            address(rewardToken),
            "test-project",
            10 ether, // minStakeToClaim
            10 ether, // minStakeToContribute
            3, // numberOfValidations
            1000, // validatorRewardBasisPoints (10%)
            "" // No required skill for simplicity
        );

        rewardToken.approve(address(core), TOTAL_REWARDS);
        core.fundProject(projectId, TOTAL_REWARDS, TOTAL_QUANTITY);
        vm.stopPrank();
    }

    /**
     * @notice Test that rejected contributions preserve rewards (demonstrating the fix)
     */
    function test_RejectedContributionPreservesRewards() public {
        // ============================================
        // 1. RECORD INITIAL STATE
        // ============================================
        uint256 initialRewardsBalance = rewardToken.balanceOf(address(rewards));
        uint256 initialProjectRewards = rewards.getRemainingProjectRewards(projectId, address(rewardToken));

        assertEq(initialRewardsBalance, TOTAL_REWARDS, "Initial rewards balance should match total rewards");
        assertEq(initialProjectRewards, TOTAL_REWARDS, "Initial project rewards should match total rewards");

        // ============================================
        // 2. CONTRIBUTOR CLAIMS AND SUBMITS
        // ============================================
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(projectId, 1);
        core.contribute(projectId, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // ============================================
        // 3. VALIDATORS REJECT THE CONTRIBUTION (score < 50%)
        // ============================================
        uint256 stake = 100 ether;
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");

        bytes32 commitHash1 = keccak256(abi.encodePacked(uint256(2000), stake, salt1)); // 20% score
        bytes32 commitHash2 = keccak256(abi.encodePacked(uint256(3000), stake, salt2)); // 30% score
        bytes32 commitHash3 = keccak256(abi.encodePacked(uint256(2500), stake, salt3)); // 25% score

        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v1ClaimId, 0, commitHash1);
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v2ClaimId, 0, commitHash2);
        vm.stopPrank();

        vm.startPrank(validator3);
        uint256 v3ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v3ClaimId, 0, commitHash3);
        vm.stopPrank();

        // Move forward past commit period
        vm.warp(block.timestamp + 2 hours);

        vm.prank(validator1);
        oracle.revealValidation(projectId, 0, 2000, salt1);
        vm.prank(validator2);
        oracle.revealValidation(projectId, 0, 3000, salt2);
        vm.prank(validator3);
        oracle.revealValidation(projectId, 0, 2500, salt3);

        // ============================================
        // 4. FINALIZE CONTRIBUTION (should be rejected)
        // ============================================
        uint256 contributorRewardAmount = (TOTAL_REWARDS * 9000) / (10000 * TOTAL_QUANTITY);

        // Expect the ContributorRewardPreserved event
        vm.expectEmit(true, true, true, true);
        emit ISapienCore.ContributorRewardPreserved(projectId, 0, address(rewardToken), contributorRewardAmount);

        vm.prank(contributor);
        core.finalizeContribution(projectId, 0);

        // Verify contribution was rejected (deleted)
        assertEq(
            uint256(getContributionStatus(projectId, 0)),
            uint256(ContributionStatus.Pending), // Status reverts to Pending as contribution is deleted
            "Contribution should be rejected/deleted"
        );

        // ============================================
        // 5. VERIFY REWARDS ARE PRESERVED (NOT STUCK)
        // ============================================
        uint256 afterRewardsBalance = rewardToken.balanceOf(address(rewards));
        uint256 afterProjectRewards = rewards.getRemainingProjectRewards(projectId, address(rewardToken));

        // The Rewards contract still holds ALL tokens (validators haven't claimed yet)
        assertEq(afterRewardsBalance, TOTAL_REWARDS, "Rewards contract should still hold all tokens");

        // FIX VERIFICATION: Project rewards remain available (not stuck)
        // When a contribution is rejected, contributor rewards stay in projectRewards
        // and automatically become available for the next contributor

        console.log("Initial project rewards:", initialProjectRewards / 1 ether);
        console.log("After project rewards:", afterProjectRewards / 1 ether);
        console.log("Difference:", (initialProjectRewards - afterProjectRewards) / 1 ether);

        // Verify that project rewards remain unchanged (preserved for reuse)
        assertEq(
            afterProjectRewards,
            initialProjectRewards,
            "FIX VERIFIED: Project rewards preserved and available for next contributor"
        );

        // The contributor portion that was preserved (not distributed, not stuck)
        uint256 contributorPortionPreserved = (TOTAL_REWARDS * 9000) / (10000 * TOTAL_QUANTITY);
        console.log("Contributor portion preserved (tokens):", contributorPortionPreserved / 1 ether);

        // ============================================
        // 6. VERIFY REWARDS ARE AUTOMATICALLY REUSABLE
        // ============================================

        // FIX: Rewards remain in projectRewards and are automatically available
        // No manual reclaim function needed - the next contributor can use them

        // The index has been freed up and can be claimed again
        assertTrue(afterProjectRewards == initialProjectRewards, "Rewards available for reuse");

        console.log("Total rewards funded (tokens):", TOTAL_REWARDS / 1 ether);
        console.log("Rewards per contribution (tokens):", contributorPortionPreserved / 1 ether);
        console.log("Preserved from 1 rejection (tokens):", contributorPortionPreserved / 1 ether);
        console.log("Percentage preserved:", (contributorPortionPreserved * 100) / TOTAL_REWARDS);
    }

    /**
     * @notice Test multiple rejections compound the stuck rewards
     * NOTE: This test is disabled as it's replaced by test_PreservedRewardsAreReusableByNextContributor
     */
    function skipTestMultipleRejectionsCompoundStuckRewards() public {
        uint256 initialProjectRewards = rewards.getRemainingProjectRewards(projectId, address(rewardToken));
        uint256 stake = 100 ether;

        // Submit and reject 3 contributions
        for (uint256 i = 0; i < 3; i++) {
            // Contributor claims and submits
            vm.startPrank(contributor);
            uint256 claimId = core.claimToContribute(projectId, 1);
            core.contribute(projectId, claimId, i, keccak256(abi.encodePacked("submission", i)));
            vm.stopPrank();

            // Validators reject with low scores
            bytes32 salt1 = keccak256(abi.encodePacked("salt", i, uint256(1)));
            bytes32 salt2 = keccak256(abi.encodePacked("salt", i, uint256(2)));
            bytes32 salt3 = keccak256(abi.encodePacked("salt", i, uint256(3)));

            bytes32 commitHash1 = keccak256(abi.encodePacked(uint256(2000), stake, salt1));
            bytes32 commitHash2 = keccak256(abi.encodePacked(uint256(2000), stake, salt2));
            bytes32 commitHash3 = keccak256(abi.encodePacked(uint256(2000), stake, salt3));

            vm.startPrank(validator1);
            uint256 v1ClaimId = oracle.claimToValidate(projectId);
            oracle.commitValidation(projectId, v1ClaimId, i, commitHash1);
            vm.stopPrank();

            vm.startPrank(validator2);
            uint256 v2ClaimId = oracle.claimToValidate(projectId);
            oracle.commitValidation(projectId, v2ClaimId, i, commitHash2);
            vm.stopPrank();

            vm.startPrank(validator3);
            uint256 v3ClaimId = oracle.claimToValidate(projectId);
            oracle.commitValidation(projectId, v3ClaimId, i, commitHash3);
            vm.stopPrank();

            vm.warp(block.timestamp + 2 hours);

            vm.prank(validator1);
            oracle.revealValidation(projectId, i, 2000, salt1);
            vm.prank(validator2);
            oracle.revealValidation(projectId, i, 2000, salt2);
            vm.prank(validator3);
            oracle.revealValidation(projectId, i, 2000, salt3);

            vm.prank(contributor);
            core.finalizeContribution(projectId, i);
        }

        // Calculate expected stuck rewards
        // Each rejection leaves contributor rewards stuck (90% of per-contribution rewards)
        uint256 contributorRewardPerContribution = (TOTAL_REWARDS * 9000) / (10000 * TOTAL_QUANTITY);
        uint256 expectedStuckRewards = contributorRewardPerContribution * 3;

        // Validator rewards are distributed, so total stuck = initial - (validator rewards for 3 contributions)
        // Fix divide-before-multiply: multiply first to avoid precision loss
        uint256 validatorRewardsDistributed = (TOTAL_REWARDS * 1000 * 3) / (10000 * TOTAL_QUANTITY);
        uint256 afterProjectRewards = rewards.getRemainingProjectRewards(projectId, address(rewardToken));

        assertEq(
            afterProjectRewards,
            initialProjectRewards - validatorRewardsDistributed,
            "Project rewards should remain except validator distributions"
        );

        console.log("Rejections count: 3");
        console.log("Stuck rewards (tokens):", expectedStuckRewards / 1 ether);
        console.log("Percentage of total stuck:", (expectedStuckRewards * 100) / TOTAL_REWARDS);
    }

    /**
     * @notice Test that preserved rewards from rejection can be used by next contributor
     * This is the KEY TEST proving the fix works!
     */
    function test_PreservedRewardsAreReusableByNextContributor() public {
        uint256 initialProjectRewards = rewards.getRemainingProjectRewards(projectId, address(rewardToken));
        uint256 contributorRewardAmount = (TOTAL_REWARDS * 9000) / (10000 * TOTAL_QUANTITY);

        // ============================================
        // STEP 1: First contributor submits and gets REJECTED
        // ============================================
        address contributor2 = makeAddr("contributor2");
        _setupUser(contributor2, 1000 ether);

        vm.startPrank(admin);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor2);
        vm.stopPrank();

        vm.startPrank(contributor);
        uint256 claimId1 = core.claimToContribute(projectId, 1);
        core.contribute(projectId, claimId1, 0, keccak256("bad submission"));
        vm.stopPrank();

        // Validators reject with low scores
        uint256 stake = 100 ether;
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");

        bytes32 commitHash1 = keccak256(abi.encodePacked(uint256(2000), stake, salt1));
        bytes32 commitHash2 = keccak256(abi.encodePacked(uint256(2000), stake, salt2));
        bytes32 commitHash3 = keccak256(abi.encodePacked(uint256(2000), stake, salt3));

        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v1ClaimId, 0, commitHash1);
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v2ClaimId, 0, commitHash2);
        vm.stopPrank();

        vm.startPrank(validator3);
        uint256 v3ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v3ClaimId, 0, commitHash3);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(validator1);
        oracle.revealValidation(projectId, 0, 2000, salt1);
        vm.prank(validator2);
        oracle.revealValidation(projectId, 0, 2000, salt2);
        vm.prank(validator3);
        oracle.revealValidation(projectId, 0, 2000, salt3);

        // Expect the ContributorRewardPreserved event
        vm.expectEmit(true, true, true, true);
        emit ISapienCore.ContributorRewardPreserved(projectId, 0, address(rewardToken), contributorRewardAmount);

        vm.prank(contributor);
        core.finalizeContribution(projectId, 0);

        uint256 afterFirstRejection = rewards.getRemainingProjectRewards(projectId, address(rewardToken));
        assertEq(afterFirstRejection, initialProjectRewards, "Rewards should be preserved after rejection");

        // ============================================
        // STEP 2: Second contributor claims the SAME INDEX and gets ACCEPTED
        // ============================================
        vm.startPrank(contributor2);
        uint256 claimId2 = core.claimToContribute(projectId, 1);
        core.contribute(projectId, claimId2, 0, keccak256("good submission"));
        vm.stopPrank();

        // Validators accept with high scores
        bytes32 salt4 = keccak256("salt4");
        bytes32 salt5 = keccak256("salt5");
        bytes32 salt6 = keccak256("salt6");

        bytes32 commitHash4 = keccak256(abi.encodePacked(uint256(8000), stake, salt4));
        bytes32 commitHash5 = keccak256(abi.encodePacked(uint256(8000), stake, salt5));
        bytes32 commitHash6 = keccak256(abi.encodePacked(uint256(8000), stake, salt6));

        vm.startPrank(validator1);
        uint256 v1ClaimId2 = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v1ClaimId2, 0, commitHash4);
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2ClaimId2 = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v2ClaimId2, 0, commitHash5);
        vm.stopPrank();

        vm.startPrank(validator3);
        uint256 v3ClaimId2 = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v3ClaimId2, 0, commitHash6);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(validator1);
        oracle.revealValidation(projectId, 0, 8000, salt4);
        vm.prank(validator2);
        oracle.revealValidation(projectId, 0, 8000, salt5);
        vm.prank(validator3);
        oracle.revealValidation(projectId, 0, 8000, salt6);

        vm.prank(contributor2);
        core.finalizeContribution(projectId, 0);

        // Claim reward after challenge period
        uint256 challengePeriod = core.getProject(projectId).config.challengePeriod;
        vm.warp(block.timestamp + challengePeriod + 1);
        core.claimContributionReward(projectId, 0);

        // ============================================
        // VERIFY: Second contributor can claim the PRESERVED rewards!
        // ============================================
        assertEq(
            uint256(getContributionStatus(projectId, 0)),
            uint256(ContributionStatus.Rewarded),
            "Contribution should be rewarded"
        );

        uint256 availableRewards = rewards.getAvailableRewards(contributor2, projectId, address(rewardToken));
        assertEq(availableRewards, contributorRewardAmount, "Contributor2 should have claimable rewards");

        uint256 balanceBefore = rewardToken.balanceOf(contributor2);
        vm.prank(contributor2);
        rewards.claimRewards(projectId, address(rewardToken), address(0), 0);
        uint256 balanceAfter = rewardToken.balanceOf(contributor2);

        assertEq(
            balanceAfter - balanceBefore, contributorRewardAmount, "Contributor2 should receive the preserved rewards"
        );

        console.log("FIX VERIFIED: Preserved rewards successfully reused!");
        console.log("Preserved amount (tokens):", contributorRewardAmount / 1 ether);
        console.log("Second contributor received (tokens):", (balanceAfter - balanceBefore) / 1 ether);
    }

    /**
     * @notice Test that accepted contributions properly distribute rewards (for comparison)
     */
    function test_AcceptedContributionsDistributeRewardsProperly() public {
        uint256 initialProjectRewards = rewards.getRemainingProjectRewards(projectId, address(rewardToken));

        // Contributor claims and submits
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(projectId, 1);
        core.contribute(projectId, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Validators ACCEPT with high scores (>= 50%)
        uint256 stake = 100 ether;
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");

        bytes32 commitHash1 = keccak256(abi.encodePacked(uint256(8000), stake, salt1));
        bytes32 commitHash2 = keccak256(abi.encodePacked(uint256(8000), stake, salt2));
        bytes32 commitHash3 = keccak256(abi.encodePacked(uint256(8000), stake, salt3));

        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v1ClaimId, 0, commitHash1);
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v2ClaimId, 0, commitHash2);
        vm.stopPrank();

        vm.startPrank(validator3);
        uint256 v3ClaimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v3ClaimId, 0, commitHash3);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(validator1);
        oracle.revealValidation(projectId, 0, 8000, salt1);
        vm.prank(validator2);
        oracle.revealValidation(projectId, 0, 8000, salt2);
        vm.prank(validator3);
        oracle.revealValidation(projectId, 0, 8000, salt3);

        vm.prank(contributor);
        core.finalizeContribution(projectId, 0);

        // Claim reward after challenge period
        uint256 challengePeriod = core.getProject(projectId).config.challengePeriod;
        vm.warp(block.timestamp + challengePeriod + 1);
        core.claimContributionReward(projectId, 0);

        // Verify contribution was accepted
        assertEq(
            uint256(getContributionStatus(projectId, 0)),
            uint256(ContributionStatus.Rewarded),
            "Contribution should be rewarded"
        );

        // Verify rewards were properly distributed
        uint256 afterProjectRewards = rewards.getRemainingProjectRewards(projectId, address(rewardToken));

        // Both contributor and validator rewards should be distributed
        uint256 contributorReward = (TOTAL_REWARDS * 9000) / (10000 * TOTAL_QUANTITY);
        uint256 validatorReward = (TOTAL_REWARDS * 1000) / (10000 * TOTAL_QUANTITY);
        uint256 totalDistributed = contributorReward + validatorReward;

        // Allow for small rounding differences due to integer division
        assertApproxEqRel(
            afterProjectRewards,
            initialProjectRewards - totalDistributed,
            0.0001e18, // 0.01% tolerance
            "Project rewards should decrease by distributed amount"
        );

        // Contributor should be able to claim their rewards
        uint256 availableRewards = rewards.getAvailableRewards(contributor, projectId, address(rewardToken));
        assertEq(availableRewards, contributorReward, "Contributor should have claimable rewards");

        vm.prank(contributor);
        rewards.claimRewards(projectId, address(rewardToken), address(0), 0);

        uint256 contributorBalance = rewardToken.balanceOf(contributor);
        assertEq(contributorBalance, contributorReward, "Contributor should receive their rewards");
    }
}
