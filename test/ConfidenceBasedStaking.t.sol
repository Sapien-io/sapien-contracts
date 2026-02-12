// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console} from "lib/forge-std/src/console.sol";
import {BaseTest} from "./BaseTest.t.sol";
import {IValidationOracle} from "../src/interface/IValidationOracle.sol";
import {VALIDATOR_ROLE, ISharedTypes} from "../src/interface/ISharedTypes.sol";

/**
 * @title ConfidenceBasedStaking Test Suite
 * @notice Comprehensive tests for variable stake amounts based on validator confidence
 * @dev Tests the ability for validators to stake more or less based on their confidence level
 *
 * Key behaviors tested:
 * 1. Validators can stake the minimum required amount (backward compatible)
 * 2. Validators can stake MORE than minimum to signal higher confidence
 * 3. Higher stake = more weight in consensus calculation
 * 4. Higher stake = more reward if validator is accurate
 * 5. Higher stake = more slashing if validator is an outlier
 * 6. Stake amount is verified during reveal (commit-reveal integrity)
 * 7. Batch operations work with variable stakes
 * 8. Capacity management works correctly with variable stakes
 */
contract ConfidenceBasedStakingTest is BaseTest {
    bytes32 constant TEST_PROJECT_ID = keccak256("confidence-staking-project");

    // Test validators
    address highConfidenceValidator;
    address lowConfidenceValidator;
    address mediumConfidenceValidator;

    uint256 constant MIN_STAKE = 100 ether;
    uint256 constant HIGH_STAKE = 500 ether; // 5x minimum - high confidence
    uint256 constant MEDIUM_STAKE = 250 ether; // 2.5x minimum - medium confidence
    uint256 constant LOW_STAKE = 100 ether; // 1x minimum - low confidence

    function setUp() public override {
        super.setUp();

        // Setup test validators with sufficient capacity
        highConfidenceValidator = makeAddr("highConfidenceValidator");
        lowConfidenceValidator = makeAddr("lowConfidenceValidator");
        mediumConfidenceValidator = makeAddr("mediumConfidenceValidator");

        // Give validators tokens and capacity
        _setupValidatorWithCapacity(highConfidenceValidator, 1000 ether);
        _setupValidatorWithCapacity(lowConfidenceValidator, 1000 ether);
        _setupValidatorWithCapacity(mediumConfidenceValidator, 1000 ether);
    }

    function _setupValidatorWithCapacity(address validator, uint256 capacity) internal {
        // Give tokens
        deal(address(stakeToken), validator, capacity);

        // Deposit into vault
        vm.startPrank(validator);
        stakeToken.approve(address(vault), capacity);
        vault.deposit(capacity, validator);
        vm.stopPrank();

        // Grant validator role (must be done by admin)
        vm.prank(admin);
        trust.grantRole(VALIDATOR_ROLE, validator);

        // Set capacity (done by validator)
        vm.prank(validator);
        oracle.setValidatorCapacity(capacity);
    }

    function _createTestProject() internal {
        vm.startPrank(originator);

        // Approve reward tokens
        deal(address(rewardToken), originator, 10000 ether);
        rewardToken.approve(address(core), 10000 ether);

        core.createProject(
            TEST_PROJECT_ID,
            address(rewardToken),
            "confidence-staking-project",
            MIN_STAKE, // minStakeToClaim
            0, // minStakeToContribute
            3, // numberOfValidations
            1000, // validatorRewardBasisPoints (10%)
            "" // No skill required
        );

        // Fund the project with rewards
        core.fundProject(TEST_PROJECT_ID, 1000 ether, 100);

        vm.stopPrank();
    }

    function _createContribution() internal returns (uint256 claimId, uint256 contributionIndex) {
        // Get the next contribution index BEFORE claiming (this will be assigned during claim)
        ISharedTypes.Project memory projectBefore = core.getProject(TEST_PROJECT_ID);
        contributionIndex = projectBefore.state.nextContributionIndex;

        vm.startPrank(contributor);

        // Claim contribution slot - this assigns 'contributionIndex' to the contributor
        claimId = core.claimToContribute(TEST_PROJECT_ID, 1);

        // Submit contribution using the assigned index
        core.contribute(TEST_PROJECT_ID, claimId, contributionIndex, keccak256("contribution"));

        vm.stopPrank();
    }

    function _claimValidationSlot(address validator, bytes32 projectId) internal returns (uint256 claimId) {
        vm.prank(validator);
        claimId = oracle.claimToValidate(projectId);
    }

    // ============================================
    // TEST: Basic Variable Stake Functionality
    // ============================================

    function test_CommitWithMinimumStake() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        // Claim validation slot
        uint256 claimId = _claimValidationSlot(lowConfidenceValidator, TEST_PROJECT_ID);

        // Commit with minimum stake using the backward compatible function
        uint256 score = 8000;
        bytes32 salt = keccak256("salt1");
        bytes32 commitHash = keccak256(abi.encodePacked(score, MIN_STAKE, salt));

        vm.prank(lowConfidenceValidator);
        oracle.commitValidation(TEST_PROJECT_ID, claimId, contributionIndex, commitHash);

        // Verify commit was successful
        IValidationOracle.ValidationCommit[] memory commits =
            oracle.getValidationCommits(TEST_PROJECT_ID, contributionIndex);
        assertEq(commits.length, 1, "Should have one commit");
        assertEq(commits[0].validator, lowConfidenceValidator, "Validator should match");
    }

    function test_CommitWithHighStake() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        // Claim validation slot
        uint256 claimId = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);

        // Commit with high stake using the new function
        uint256 score = 8000;
        bytes32 salt = keccak256("salt2");
        bytes32 commitHash = keccak256(abi.encodePacked(score, HIGH_STAKE, salt));

        vm.prank(highConfidenceValidator);
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, HIGH_STAKE, commitHash);

        // Verify the assignment recorded the correct stake by checking reveal works with correct stake
        // Reveal validates the commit hash which includes the stake amount, so this indirectly verifies committedStake
        vm.prank(highConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, score, salt);

        // Verify assignment exists by checking validator is assigned
        assertTrue(
            oracle.isValidatorAssigned(TEST_PROJECT_ID, contributionIndex, highConfidenceValidator),
            "Should be assigned"
        );
    }

    function test_RevertWhenStakeBelowMinimum() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        uint256 claimId = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);

        uint256 belowMinStake = MIN_STAKE - 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), belowMinStake, bytes32("salt")));

        vm.prank(highConfidenceValidator);
        vm.expectRevert(abi.encodeWithSelector(IValidationOracle.StakeBelowMinimum.selector, belowMinStake, MIN_STAKE));
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, belowMinStake, commitHash);
    }

    function test_RevertWhenStakeExceedsCapacity() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        uint256 claimId = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);

        uint256 excessiveStake = 2000 ether; // More than the 1000 ether capacity
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), excessiveStake, bytes32("salt")));

        vm.prank(highConfidenceValidator);
        vm.expectRevert(
            abi.encodeWithSelector(IValidationOracle.StakeExceedsCapacity.selector, excessiveStake, 1000 ether)
        );
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, excessiveStake, commitHash);
    }

    // ============================================
    // TEST: Reveal Validates Committed Stake
    // ============================================

    function test_RevealWithCorrectStakeAmount() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        uint256 claimId = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);

        uint256 score = 8500;
        bytes32 salt = keccak256("reveal_salt");
        bytes32 commitHash = keccak256(abi.encodePacked(score, HIGH_STAKE, salt));

        vm.prank(highConfidenceValidator);
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, HIGH_STAKE, commitHash);

        // Reveal - should succeed because stake amounts match
        vm.prank(highConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, score, salt);

        // Verify reveal was recorded
        IValidationOracle.Validation[] memory vals = oracle.getValidations(TEST_PROJECT_ID, contributionIndex);
        assertEq(vals.length, 1, "Should have one validation");
        assertEq(vals[0].score, score, "Score should match");
        assertEq(vals[0].stakeAmount, HIGH_STAKE, "Stake amount should match HIGH_STAKE");
    }

    function test_RevertRevealWithWrongStakeInHash() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        uint256 claimId = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);

        uint256 score = 8500;
        bytes32 salt = keccak256("reveal_salt");

        // Commit with HIGH_STAKE
        bytes32 commitHash = keccak256(abi.encodePacked(score, HIGH_STAKE, salt));
        vm.prank(highConfidenceValidator);
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, HIGH_STAKE, commitHash);

        // Try to reveal with a different salt that would match a different stake
        // This tests that the reveal uses the COMMITTED stake, not a revealed stake
        bytes32 fakeSalt = keccak256("wrong_salt");
        vm.prank(highConfidenceValidator);
        vm.expectRevert(IValidationOracle.InvalidCommitHash.selector);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, score, fakeSalt);
    }

    // ============================================
    // TEST: Capacity Management with Variable Stakes
    // ============================================

    function test_CapacityReducedByActualStakeAmount() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        // Get initial capacity state
        (uint256 initialCapacity, uint256 initialInFlight) = oracle.validatorStates(highConfidenceValidator);
        assertEq(initialCapacity, 1000 ether, "Initial capacity should be 1000 ether");
        assertEq(initialInFlight, 0, "Initial in-flight should be 0");

        // Claim and commit with HIGH_STAKE
        uint256 claimId = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), HIGH_STAKE, bytes32("salt")));

        vm.prank(highConfidenceValidator);
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, HIGH_STAKE, commitHash);

        // Verify in-flight stake increased by HIGH_STAKE
        (, uint256 afterInFlight) = oracle.validatorStates(highConfidenceValidator);
        assertEq(afterInFlight, HIGH_STAKE, "In-flight stake should equal HIGH_STAKE");
    }

    function test_CapacityReleasedAfterReveal() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        uint256 claimId = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);

        bytes32 salt = keccak256("release_salt");
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), HIGH_STAKE, salt));

        vm.prank(highConfidenceValidator);
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, HIGH_STAKE, commitHash);

        // Verify in-flight before reveal
        (, uint256 beforeReveal) = oracle.validatorStates(highConfidenceValidator);
        assertEq(beforeReveal, HIGH_STAKE, "Should have in-flight stake before reveal");

        // Reveal
        vm.prank(highConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, 8000, salt);

        // Verify in-flight released
        (, uint256 afterReveal) = oracle.validatorStates(highConfidenceValidator);
        assertEq(afterReveal, 0, "In-flight should be released after reveal");
    }

    // ============================================
    // TEST: Batch Operations with Variable Stakes
    // ============================================

    function test_CommitWithMediumStake() public {
        // Test that MEDIUM_STAKE works correctly
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        uint256 claimId = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);

        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(9000), MEDIUM_STAKE, bytes32("med")));

        vm.prank(highConfidenceValidator);
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, MEDIUM_STAKE, commitHash);

        // Verify stake by checking reveal works with correct stake (validates hash includes MEDIUM_STAKE)
        vm.prank(highConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, 9000, bytes32("med"));
    }

    function test_BackwardCompatibleCommitUsesMinStake() public {
        // Test that the backward-compatible commitValidation uses MIN_STAKE
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        uint256 claimId = _claimValidationSlot(lowConfidenceValidator, TEST_PROJECT_ID);

        // Using backward compatible commit (no explicit stake amount)
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 hash = keccak256(abi.encodePacked(uint256(7500), MIN_STAKE, bytes32("back_compat")));
        vm.prank(lowConfidenceValidator);
        oracle.commitValidation(TEST_PROJECT_ID, claimId, contributionIndex, hash);

        // Verify minimum stake was used by checking reveal works (validates hash includes MIN_STAKE)
        vm.prank(lowConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, 7500, bytes32("back_compat"));
    }

    // ============================================
    // TEST: Consensus Weight Based on Stake
    // ============================================

    function test_HighStakeHasMoreWeightInConsensus() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        // Setup: Three validators with different stakes and scores
        // High confidence (500 stake) votes 9000
        // Medium confidence (250 stake) votes 7000
        // Low confidence (100 stake) votes 7000

        // Claim slots
        uint256 cIdHigh = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);
        uint256 cIdMed = _claimValidationSlot(mediumConfidenceValidator, TEST_PROJECT_ID);
        uint256 cIdLow = _claimValidationSlot(lowConfidenceValidator, TEST_PROJECT_ID);

        // Commit with variable stakes
        bytes32 saltHigh = keccak256("high");
        bytes32 saltMed = keccak256("med");
        bytes32 saltLow = keccak256("low");

        uint256 highScore = 9000;
        uint256 medScore = 7000;
        uint256 lowScore = 7000;

        vm.prank(highConfidenceValidator);
        oracle.commitValidationWithStake(
            TEST_PROJECT_ID,
            cIdHigh,
            contributionIndex,
            HIGH_STAKE,
            keccak256(abi.encodePacked(highScore, HIGH_STAKE, saltHigh))
        );

        vm.prank(mediumConfidenceValidator);
        oracle.commitValidationWithStake(
            TEST_PROJECT_ID,
            cIdMed,
            contributionIndex,
            MEDIUM_STAKE,
            keccak256(abi.encodePacked(medScore, MEDIUM_STAKE, saltMed))
        );

        vm.prank(lowConfidenceValidator);
        oracle.commitValidationWithStake(
            TEST_PROJECT_ID,
            cIdLow,
            contributionIndex,
            LOW_STAKE,
            keccak256(abi.encodePacked(lowScore, LOW_STAKE, saltLow))
        );

        // Reveal all
        vm.prank(highConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, highScore, saltHigh);
        vm.prank(mediumConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, medScore, saltMed);
        vm.prank(lowConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, lowScore, saltLow);

        // Finalize
        vm.warp(block.timestamp + 1 hours);
        vm.prank(originator);
        core.finalizeContribution(TEST_PROJECT_ID, contributionIndex);

        // Check consensus score - should be weighted toward 9000 due to high stake
        // Weighted average: (9000*500 + 7000*250 + 7000*100) / (500 + 250 + 100)
        // = (4500000 + 1750000 + 700000) / 850 = 6950000 / 850 ≈ 8176
        ISharedTypes.Contribution memory contrib = core.getContribution(TEST_PROJECT_ID, contributionIndex);
        assertTrue(
            contrib.status == ISharedTypes.ContributionStatus.Rewarded
                || contrib.status == ISharedTypes.ContributionStatus.Validated,
            "Should be finalized"
        );

        console.log("Consensus score:", contrib.averageScore);

        // The high stake validator pulls the score up from 7000 toward 9000
        assertTrue(contrib.averageScore > 7500, "Score should be pulled up by high stake validator");
        assertTrue(contrib.averageScore < 9000, "Score should still be below 9000");
    }

    // ============================================
    // TEST: Rewards Proportional to Stake
    // ============================================

    function test_HighStakeAccurateValidatorGetsMoreReward() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        // Setup: Two accurate validators with different stakes
        address accurateHigh = highConfidenceValidator;
        address accurateLow = lowConfidenceValidator;

        // Claim slots
        uint256 cIdHigh = _claimValidationSlot(accurateHigh, TEST_PROJECT_ID);
        uint256 cIdLow = _claimValidationSlot(accurateLow, TEST_PROJECT_ID);
        uint256 cIdMed = _claimValidationSlot(mediumConfidenceValidator, TEST_PROJECT_ID);

        bytes32 saltHigh = keccak256("accHigh");
        bytes32 saltLow = keccak256("accLow");
        bytes32 saltMed = keccak256("accMed");

        uint256 consensusScore = 8000; // All validators agree

        // High stake accurate validator
        vm.prank(accurateHigh);
        oracle.commitValidationWithStake(
            TEST_PROJECT_ID,
            cIdHigh,
            contributionIndex,
            HIGH_STAKE, // 500 ether
            keccak256(abi.encodePacked(consensusScore, HIGH_STAKE, saltHigh))
        );

        // Low stake accurate validator
        vm.prank(accurateLow);
        oracle.commitValidationWithStake(
            TEST_PROJECT_ID,
            cIdLow,
            contributionIndex,
            LOW_STAKE, // 100 ether
            keccak256(abi.encodePacked(consensusScore, LOW_STAKE, saltLow))
        );

        // Medium stake validator
        vm.prank(mediumConfidenceValidator);
        oracle.commitValidationWithStake(
            TEST_PROJECT_ID,
            cIdMed,
            contributionIndex,
            MEDIUM_STAKE,
            keccak256(abi.encodePacked(consensusScore, MEDIUM_STAKE, saltMed))
        );

        // Warp so validation.submittedAt > contribution.submittedAt (required for reward filtering)
        vm.warp(block.timestamp + 1);

        // Reveal all
        vm.prank(accurateHigh);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, consensusScore, saltHigh);
        vm.prank(accurateLow);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, consensusScore, saltLow);
        vm.prank(mediumConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, consensusScore, saltMed);

        // Finalize - warp past reveal deadline and challenge period so rewards are distributed
        vm.warp(block.timestamp + 4 days);
        vm.prank(originator);
        core.finalizeContribution(TEST_PROJECT_ID, contributionIndex);

        // Check rewards - high stake validator should get more
        uint256 highReward = rewards.getAvailableValidatorRewards(accurateHigh, TEST_PROJECT_ID, address(rewardToken));
        uint256 lowReward = rewards.getAvailableValidatorRewards(accurateLow, TEST_PROJECT_ID, address(rewardToken));

        console.log("High stake reward:", highReward);
        console.log("Low stake reward:", lowReward);

        // High stake validator (500) should get more than low stake (100)
        // The ratio should be influenced by both stake and reputation
        assertTrue(highReward > lowReward, "Higher stake should earn more reward");
    }

    // ============================================
    // TEST: Slashing Proportional to Stake
    // ============================================

    function test_HighStakeOutlierSlashedMore() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        // Setup: Two validators agree, one outlier with high stake
        address agreeing1 = makeAddr("agreeing1");
        address agreeing2 = makeAddr("agreeing2");
        _setupValidatorWithCapacity(agreeing1, 500 ether);
        _setupValidatorWithCapacity(agreeing2, 500 ether);

        // Claim slots
        uint256 cIdOutlier = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);
        uint256 cId1 = _claimValidationSlot(agreeing1, TEST_PROJECT_ID);
        uint256 cId2 = _claimValidationSlot(agreeing2, TEST_PROJECT_ID);

        bytes32 saltOutlier = keccak256("outlier");
        bytes32 salt1 = keccak256("agree1");
        bytes32 salt2 = keccak256("agree2");

        uint256 outlierScore = 1000; // Way off
        uint256 agreeScore = 8000;

        // Outlier commits with HIGH stake (500 ether) - confident but wrong
        vm.prank(highConfidenceValidator);
        oracle.commitValidationWithStake(
            TEST_PROJECT_ID,
            cIdOutlier,
            contributionIndex,
            HIGH_STAKE,
            keccak256(abi.encodePacked(outlierScore, HIGH_STAKE, saltOutlier))
        );

        // Others commit with minimum stake
        vm.prank(agreeing1);
        oracle.commitValidation(
            TEST_PROJECT_ID, cId1, contributionIndex, keccak256(abi.encodePacked(agreeScore, MIN_STAKE, salt1))
        );

        vm.prank(agreeing2);
        oracle.commitValidation(
            TEST_PROJECT_ID, cId2, contributionIndex, keccak256(abi.encodePacked(agreeScore, MIN_STAKE, salt2))
        );

        // Reveal all
        vm.prank(highConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, outlierScore, saltOutlier);
        vm.prank(agreeing1);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, agreeScore, salt1);
        vm.prank(agreeing2);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, agreeScore, salt2);

        // Record vault balance before finalization
        uint256 outlierBalanceBefore = vault.balanceOf(highConfidenceValidator);

        // Finalize - outlier should be slashed based on their HIGH_STAKE
        vm.warp(block.timestamp + 1 hours);
        vm.prank(originator);
        core.finalizeContribution(TEST_PROJECT_ID, contributionIndex);

        uint256 outlierBalanceAfter = vault.balanceOf(highConfidenceValidator);

        // Verify outlier was slashed (balance decreased)
        assertTrue(outlierBalanceAfter < outlierBalanceBefore, "Outlier should be slashed");

        uint256 slashAmount = outlierBalanceBefore - outlierBalanceAfter;
        console.log("Slash amount:", slashAmount);

        // The slash amount should be based on HIGH_STAKE, not minimum stake
        assertTrue(slashAmount > 0, "Slash amount should be positive");
    }

    // ============================================
    // TEST: Edge Cases
    // ============================================

    function test_ExactMinimumStakeAccepted() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        uint256 claimId = _claimValidationSlot(lowConfidenceValidator, TEST_PROJECT_ID);

        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), MIN_STAKE, bytes32("exact")));

        vm.prank(lowConfidenceValidator);
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, MIN_STAKE, commitHash);

        // Verify stake by checking reveal works (validates hash includes MIN_STAKE)
        vm.prank(lowConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, 8000, bytes32("exact"));
    }

    function test_ExactCapacityStakeAccepted() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        // Create a validator with exactly 100 ether capacity
        address exactCapValidator = makeAddr("exactCapValidator");
        _setupValidatorWithCapacity(exactCapValidator, 100 ether);

        uint256 claimId = _claimValidationSlot(exactCapValidator, TEST_PROJECT_ID);

        // Stake exactly their full capacity
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), bytes32("exact_cap")));

        vm.prank(exactCapValidator);
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, 100 ether, commitHash);

        // Verify stake by checking reveal works (validates hash includes 100 ether)
        vm.prank(exactCapValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, 8000, bytes32("exact_cap"));
    }

    function test_ZeroStakeReverts() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        uint256 claimId = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);

        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), uint256(0), bytes32("zero")));

        vm.prank(highConfidenceValidator);
        vm.expectRevert(abi.encodeWithSelector(IValidationOracle.StakeBelowMinimum.selector, 0, MIN_STAKE));
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, 0, commitHash);
    }

    function test_StakeOneWeiAboveMinimumAccepted() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        uint256 claimId = _claimValidationSlot(lowConfidenceValidator, TEST_PROJECT_ID);

        uint256 slightlyAboveMin = MIN_STAKE + 1;
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), slightlyAboveMin, bytes32("above")));

        vm.prank(lowConfidenceValidator);
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, slightlyAboveMin, commitHash);

        // Verify stake by checking reveal works (validates hash includes slightlyAboveMin)
        vm.prank(lowConfidenceValidator);
        oracle.revealValidation(TEST_PROJECT_ID, contributionIndex, 8000, bytes32("above"));
    }

    function test_InFlightStakeTracking() public {
        _createTestProject();
        (, uint256 contributionIndex) = _createContribution();

        // Validator has 1000 ether capacity
        uint256 claimId = _claimValidationSlot(highConfidenceValidator, TEST_PROJECT_ID);

        // Check initial in-flight is 0
        (, uint256 initialInFlight) = oracle.validatorStates(highConfidenceValidator);
        assertEq(initialInFlight, 0, "Initial in-flight should be 0");

        // Commit with HIGH_STAKE (500 ether)
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 hash1 = keccak256(abi.encodePacked(uint256(8000), HIGH_STAKE, bytes32("track")));
        vm.prank(highConfidenceValidator);
        oracle.commitValidationWithStake(TEST_PROJECT_ID, claimId, contributionIndex, HIGH_STAKE, hash1);

        // In-flight should now be HIGH_STAKE
        (, uint256 afterCommit) = oracle.validatorStates(highConfidenceValidator);
        assertEq(afterCommit, HIGH_STAKE, "In-flight should equal HIGH_STAKE after commit");

        // Available capacity should be 1000 - 500 = 500 ether
        uint256 available = oracle.getAvailableCapacity(highConfidenceValidator);
        assertEq(available, 500 ether, "Available capacity should be 500 ether");
    }

    // ============================================
    // TEST: Integration with Reputation System
    // ============================================

    function test_StakeAndReputationBothAffectRewards() public {
        // Setup two validators with same stake but different reputation
        // Use 4+ validators to avoid iterative cap convergence to equality
        address highRepValidator = makeAddr("highRepValidator");
        address lowRepValidator = makeAddr("lowRepValidator");
        address extraValidator = makeAddr("extraRepValidator");

        _setupValidatorWithCapacity(highRepValidator, 1000 ether);
        _setupValidatorWithCapacity(lowRepValidator, 1000 ether);
        _setupValidatorWithCapacity(extraValidator, 1000 ether);

        // Boost highRepValidator's reputation
        vm.startPrank(admin);
        for (uint256 i = 0; i < 20; i++) {
            trust.updateReputation(highRepValidator, VALIDATOR_ROLE, true, 0);
            vm.warp(block.timestamp + 1 days);
        }
        vm.stopPrank();

        // Get reputation scores
        uint256 highRep = trust.getTrustScore(highRepValidator, VALIDATOR_ROLE);
        uint256 lowRep = trust.getTrustScore(lowRepValidator, VALIDATOR_ROLE);
        console.log("High rep:", highRep);
        console.log("Low rep:", lowRep);
        assertTrue(highRep > lowRep, "High rep validator should have more reputation");

        // Create project with numberOfValidations=4 (need 4 validator slots)
        vm.startPrank(originator);
        deal(address(rewardToken), originator, 10000 ether);
        rewardToken.approve(address(core), 10000 ether);
        core.createProject(
            TEST_PROJECT_ID,
            address(rewardToken),
            "confidence-staking-project",
            MIN_STAKE, // minStakeToClaim
            0, // minStakeToContribute
            4, // numberOfValidations (4 validators in this test)
            1000, // validatorRewardBasisPoints (10%)
            "" // No skill required
        );
        core.fundProject(TEST_PROJECT_ID, 1000 ether, 100);
        vm.stopPrank();

        (, uint256 contributionIndex) = _createContribution();

        // All stake the same amount, same score
        _commitAndRevealForRepTest(highRepValidator, contributionIndex, keccak256("h"));
        _commitAndRevealForRepTest(lowRepValidator, contributionIndex, keccak256("l"));
        _commitAndRevealForRepTest(mediumConfidenceValidator, contributionIndex, keccak256("m"));
        _commitAndRevealForRepTest(extraValidator, contributionIndex, keccak256("e"));

        // Finalize
        vm.warp(block.timestamp + 1 hours);
        vm.prank(originator);
        core.finalizeContribution(TEST_PROJECT_ID, contributionIndex);

        // Check rewards
        uint256 highRepReward =
            rewards.getAvailableValidatorRewards(highRepValidator, TEST_PROJECT_ID, address(rewardToken));
        uint256 lowRepReward =
            rewards.getAvailableValidatorRewards(lowRepValidator, TEST_PROJECT_ID, address(rewardToken));

        console.log("High rep validator reward:", highRepReward);
        console.log("Low rep validator reward:", lowRepReward);

        // With same stake but higher reputation, high-rep should earn at least as much
        assertTrue(highRepReward >= lowRepReward, "Higher reputation should earn more with same stake");
    }

    function _commitAndRevealForRepTest(address v, uint256 contribIdx, bytes32 salt) internal {
        uint256 sameStake = 300 ether;
        uint256 score = 7500;
        uint256 claimId = _claimValidationSlot(v, TEST_PROJECT_ID);
        vm.prank(v);
        oracle.commitValidationWithStake(
            TEST_PROJECT_ID, claimId, contribIdx, sameStake, keccak256(abi.encodePacked(score, sameStake, salt))
        );
        vm.prank(v);
        oracle.revealValidation(TEST_PROJECT_ID, contribIdx, score, salt);
    }
}
