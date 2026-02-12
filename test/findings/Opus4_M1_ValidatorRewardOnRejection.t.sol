// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title Opus4_M1_ValidatorRewardOnRejection
 * @notice Opus 4.6 Security Review — M-1: Double Validator Reward Payout
 *
 * ORIGINAL FINDING:
 * When a contribution is rejected, `_processValidators()` is called unconditionally,
 * distributing validator rewards even for rejected contributions. If the slot is later
 * re-submitted and accepted, validators are paid again — draining the pool.
 *
 * INVESTIGATION RESULT: FINDING INVALIDATED
 * The code ordering in `_finalizeContribution` prevents this:
 *   1. On rejection: `oracle.resetContributionState()` (line 722) clears validation data
 *   2. Then: `_processValidators()` (line 726) calls `_distributeValidatorRewards()`
 *   3. `_distributeValidatorRewards()` calls `_fetchValidations()` which returns empty array
 *   4. Empty validations → early return → NO validator rewards distributed
 *
 * However, this means validators who did legitimate work on rejected contributions
 * receive NO compensation. Only outlier slashing still occurs (from in-memory report).
 *
 * See also: RewardPoolDrain.t.sol for independent confirmation.
 *
 * LOCATION: SapienCore.sol:_finalizeContribution():720-733
 * SEVERITY: INVALIDATED (code ordering prevents the attack)
 */
contract Opus4_M1_ValidatorRewardOnRejection is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("opus4-m1-test");
    address public contributor2 = makeAddr("contributor2");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor2);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        _setupUser(contributor2, 1000 ether);
        _setupValidator(validator1, 200 ether);
        _setupValidator(validator2, 200 ether);
        _setupValidator(validator3, 200 ether);
    }

    /**
     * @notice Confirms M-1 is NOT exploitable: pool unchanged after rejection
     * @dev The resetContributionState call clears validation data before
     *      _processValidators runs, preventing validator reward distribution.
     */
    function test_M1_PoolNotDrainedOnRejection() public {
        uint256 rewardAmount = 100 ether;
        uint256 quantity = 5;
        uint256 validatorBps = 1000; // 10%

        // Create and fund project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "opus4-m1-test", 0, 0, 3, validatorBps, "");
        rewardToken.approve(address(core), rewardAmount);
        core.fundProject(PROJECT_ID, rewardAmount, quantity);
        vm.stopPrank();

        uint256 poolBefore = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));
        console.log("=== M-1 Investigation: Validator Rewards on Rejection ===");
        console.log("Pool before:", poolBefore / 1e18, "tokens");

        // Submit and REJECT a contribution (score 2000 < threshold 5000)
        _submitContribution(contributor, PROJECT_ID, 0);
        _validateContribution(PROJECT_ID, 0, 2000);
        core.finalizeContribution(PROJECT_ID, 0);

        uint256 poolAfterRejection = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));
        console.log("Pool after rejection:", poolAfterRejection / 1e18, "tokens");

        // ASSERT: Pool is unchanged — no validator rewards were paid
        assertEq(poolAfterRejection, poolBefore, "Pool must be unchanged after rejection");

        // Verify validators got zero rewards
        uint256 v1Rewards = rewards.getAvailableValidatorRewards(validator1, PROJECT_ID, address(rewardToken));
        uint256 v2Rewards = rewards.getAvailableValidatorRewards(validator2, PROJECT_ID, address(rewardToken));
        uint256 v3Rewards = rewards.getAvailableValidatorRewards(validator3, PROJECT_ID, address(rewardToken));
        assertEq(v1Rewards, 0, "V1 should get zero rewards on rejection");
        assertEq(v2Rewards, 0, "V2 should get zero rewards on rejection");
        assertEq(v3Rewards, 0, "V3 should get zero rewards on rejection");

        console.log("FINDING INVALIDATED: resetContributionState() clears data before _processValidators()");
    }

    /**
     * @notice Full rejection-then-acceptance cycle succeeds without pool drain
     * @dev After rejection (pool unchanged), re-submission and acceptance works correctly.
     */
    function test_M1_FullCycleRejectionThenAcceptance() public {
        uint256 rewardAmount = 100 ether;
        uint256 quantity = 1;
        uint256 validatorBps = 1000; // 10%

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "opus4-m1-test", 0, 0, 3, validatorBps, "");
        rewardToken.approve(address(core), rewardAmount);
        core.fundProject(PROJECT_ID, rewardAmount, quantity);
        vm.stopPrank();

        uint256 poolBefore = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));
        console.log("=== M-1 Full Cycle: Rejection Then Acceptance ===");
        console.log("Pool initially:", poolBefore / 1e18, "tokens");

        // Step 1: Submit and reject
        _submitContribution(contributor, PROJECT_ID, 0);
        _validateContribution(PROJECT_ID, 0, 2000); // Reject
        core.finalizeContribution(PROJECT_ID, 0);

        uint256 poolAfterReject = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));
        console.log("Pool after rejection:", poolAfterReject / 1e18, "tokens (unchanged)");
        assertEq(poolAfterReject, poolBefore, "Pool unchanged after rejection");

        // Step 2: Re-submit on same slot and accept
        _submitContribution(contributor2, PROJECT_ID, 0);
        _validateContribution(PROJECT_ID, 0, 8000); // Accept
        core.finalizeContribution(PROJECT_ID, 0);

        // Claim reward after challenge period
        uint256 challengePeriod = core.getProject(PROJECT_ID).config.challengePeriod;
        vm.warp(block.timestamp + challengePeriod + 1);
        core.claimContributionReward(PROJECT_ID, 0);

        uint256 poolAfterAccept = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));
        console.log("Pool after acceptance:", poolAfterAccept / 1e18, "tokens");

        // Contributor gets reward
        uint256 contribReward = rewards.getAvailableRewards(contributor2, PROJECT_ID, address(rewardToken));
        assertGt(contribReward, 0, "Contributor should get reward on acceptance");
        console.log("Contributor reward:", contribReward / 1e18, "tokens");

        // Validators get reward on acceptance
        uint256 v1Rewards = rewards.getAvailableValidatorRewards(validator1, PROJECT_ID, address(rewardToken));
        assertGt(v1Rewards, 0, "Validators should get rewards on acceptance");
        console.log("Validator1 reward:", v1Rewards / 1e18, "tokens");

        console.log("CONFIRMED: Full cycle works. M-1 not exploitable.");
    }

    /**
     * @notice Document the ordering dependency that prevents the vulnerability
     * @dev This test explicitly shows the code path that prevents pool drain.
     */
    function test_M1_DocumentOrderingDependency() public pure {
        console.log("=== M-1 Code Ordering Analysis ===");
        console.log("");
        console.log("In _finalizeContribution (SapienCore.sol:643-736):");
        console.log("");
        console.log("  REJECTED PATH:");
        console.log("  1. contrib.status = Rejected           (line 665)");
        console.log("  2. _addToAvailableIndices()             (line 682)");
        console.log("  3. delete contributions[...]            (line 692)");
        console.log("  4. oracle.resetContributionState()      (line 722) <-- clears validation data");
        console.log("  5. _processValidators()                 (line 726)");
        console.log("     -> _distributeValidatorRewards()");
        console.log("        -> _fetchValidations() returns [] <-- empty after reset");
        console.log("        -> early return, NO rewards paid");
        console.log("");
        console.log("  CRITICAL: Step 4 runs BEFORE Step 5.");
        console.log("  This ordering prevents double validator reward payout.");
        console.log("");
        console.log("  NOTE: If steps 4 and 5 were swapped, M-1 would be exploitable.");
        console.log("  This dependency should be documented as a safety invariant.");
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
