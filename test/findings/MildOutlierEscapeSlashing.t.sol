// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title MildOutlierEscapeSlashingTest
 * @notice Test demonstrating Issue #9: Mild Outlier Escapes Slashing
 *
 * VULNERABILITY DESCRIPTION:
 * The slash loop correctly updates reputation negatively. However, if slashAmounts[i] == 0
 * (mild outlier), no penalty occurs. The outlier threshold in ConsensusLib is 1500 points
 * OR 2σ - if a validator is at 1499 deviation, they escape slashing entirely.
 *
 * ATTACK VECTOR: Lazy Validation Gaming
 *
 * LOCATION: SapienCore.sol lines 796-807 (_processValidators)
 *
 * SEVERITY: Low-Medium
 */
contract MildOutlierEscapeSlashingTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("outlier-test");

    // Validators
    address public lazyValidator = makeAddr("lazyValidator");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        trust.grantRole(VALIDATOR_ROLE, lazyValidator);
        vm.stopPrank();

        _setupValidator(validator1, 100 ether);
        _setupValidator(validator2, 100 ether);
        _setupValidator(validator3, 100 ether);
        _setupValidator(lazyValidator, 100 ether);
    }

    /**
     * @notice Test: Validator at outlier boundary escapes slashing
     * @dev Score at exactly threshold - 1 to avoid slash
     */
    function test_MildOutlierEscapesSlash() public {
        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "outlier-test", 0, 0, 4, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Contributor submits
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        console.log("=== Mild Outlier Escape Slashing ===");

        // Three validators vote consensus score: 8000
        uint256 consensusScore = 8000;
        // Lazy validator votes at boundary: 8000 - 1499 = 6501 (just under threshold)
        uint256 mildOutlierScore = 6501; // 1499 points off, not quite 1500 threshold

        console.log("Consensus score:", consensusScore);
        console.log("Outlier threshold: 1500 points OR 2 std deviations");
        console.log("Lazy validator score:", mildOutlierScore);
        console.log("Deviation:", consensusScore - mildOutlierScore, "points");

        // Get lazy validator initial state
        (uint256 initialCapacity,) = oracle.validatorStates(lazyValidator);
        uint256 initialReputation = trust.getTrustScore(lazyValidator, VALIDATOR_ROLE);
        console.log("\n=== Initial Lazy Validator State ===");
        console.log("Capacity:", initialCapacity);
        console.log("Reputation:", initialReputation);

        // Commit and reveal all validators
        _commitAndReveal(validator1, PROJECT_ID, 0, consensusScore);
        _commitAndReveal(validator2, PROJECT_ID, 0, consensusScore);
        _commitAndReveal(validator3, PROJECT_ID, 0, consensusScore);
        _commitAndReveal(lazyValidator, PROJECT_ID, 0, mildOutlierScore);

        // Finalize
        core.finalizeContribution(PROJECT_ID, 0);

        // Check lazy validator after finalization
        (uint256 finalCapacity,) = oracle.validatorStates(lazyValidator);
        uint256 finalReputation = trust.getTrustScore(lazyValidator, VALIDATOR_ROLE);
        console.log("\n=== Final Lazy Validator State ===");
        console.log("Capacity:", finalCapacity);
        console.log("Reputation:", finalReputation);
        console.log("Capacity change:", int256(finalCapacity) - int256(initialCapacity));
        console.log("Reputation change:", int256(finalReputation) - int256(initialReputation));

        // If capacity unchanged, lazy validator escaped slashing
        if (finalCapacity == initialCapacity) {
            console.log("\nVULNERABILITY CONFIRMED:");
            console.log("Lazy validator escaped slashing by staying at boundary!");
            console.log("They still receive validator rewards despite inaccurate validation.");
        }
    }

    /**
     * @notice Test: Compare mild outlier vs definite outlier
     * @dev Shows the slashing difference at boundary
     */
    function test_OutlierBoundaryComparison() public {
        bytes32 project1 = keccak256("project1");
        bytes32 project2 = keccak256("project2");

        // Create two projects
        vm.startPrank(originator);
        core.createProject(project1, address(rewardToken), "project1", 0, 0, 4, 1000, "");
        core.createProject(project2, address(rewardToken), "project2", 0, 0, 4, 1000, "");
        rewardToken.approve(address(core), 200 ether);
        core.fundProject(project1, 100 ether, 10);
        core.fundProject(project2, 100 ether, 10);
        vm.stopPrank();

        // Submit to both
        vm.startPrank(contributor);
        uint256 claimId1 = core.claimToContribute(project1, 1);
        core.contribute(project1, claimId1, 0, keccak256("submission1"));
        uint256 claimId2 = core.claimToContribute(project2, 1);
        core.contribute(project2, claimId2, 0, keccak256("submission2"));
        vm.stopPrank();

        console.log("=== Boundary Comparison ===");
        console.log("Consensus score: 8000");
        console.log("Project 1: Validator deviation = 1499 (under threshold)");
        console.log("Project 2: Validator deviation = 1501 (over threshold)");

        // Project 1: Score at 8000 - 1499 = 6501 (mild outlier)
        _commitAndReveal(validator1, project1, 0, 8000);
        _commitAndReveal(validator2, project1, 0, 8000);
        _commitAndReveal(validator3, project1, 0, 8000);
        _commitAndReveal(lazyValidator, project1, 0, 6501);

        (uint256 capBeforeP1,) = oracle.validatorStates(lazyValidator);

        core.finalizeContribution(project1, 0);

        (uint256 capAfterP1,) = oracle.validatorStates(lazyValidator);
        console.log("\n=== Project 1 (Under Threshold) ===");
        console.log("Capacity before:", capBeforeP1);
        console.log("Capacity after:", capAfterP1);
        console.log("Slashed:", capBeforeP1 > capAfterP1 ? "YES" : "NO");

        // Project 2: Score at 8000 - 1501 = 6499 (definite outlier)
        _commitAndReveal(validator1, project2, 0, 8000);
        _commitAndReveal(validator2, project2, 0, 8000);
        _commitAndReveal(validator3, project2, 0, 8000);
        _commitAndReveal(lazyValidator, project2, 0, 6499);

        (uint256 capBeforeP2,) = oracle.validatorStates(lazyValidator);

        core.finalizeContribution(project2, 0);

        (uint256 capAfterP2,) = oracle.validatorStates(lazyValidator);
        console.log("\n=== Project 2 (Over Threshold) ===");
        console.log("Capacity before:", capBeforeP2);
        console.log("Capacity after:", capAfterP2);
        console.log("Slashed:", capBeforeP2 > capAfterP2 ? "YES" : "NO");

        if (capAfterP1 == capBeforeP1 && capAfterP2 < capBeforeP2) {
            console.log("\n=== Boundary Behavior Confirmed ===");
            console.log("At 1499 deviation: NO slash");
            console.log("At 1501 deviation: SLASH");
            console.log("Validators can game this boundary!");
        }
    }

    /**
     * @notice Test: Lazy validator receives rewards despite poor validation
     * @dev Shows economic incentive to be a mild outlier
     */
    function test_LazyValidatorReceivesRewards() public {
        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "outlier-test", 0, 0, 4, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Submit
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        uint256 lazyBalanceBefore = rewardToken.balanceOf(lazyValidator);

        // All validators vote (lazy validator at boundary)
        _commitAndReveal(validator1, PROJECT_ID, 0, 8000);
        _commitAndReveal(validator2, PROJECT_ID, 0, 8000);
        _commitAndReveal(validator3, PROJECT_ID, 0, 8000);
        _commitAndReveal(lazyValidator, PROJECT_ID, 0, 6501); // Mild outlier

        core.finalizeContribution(PROJECT_ID, 0);

        uint256 lazyBalanceAfter = rewardToken.balanceOf(lazyValidator);
        uint256 rewardReceived = lazyBalanceAfter - lazyBalanceBefore;

        console.log("=== Lazy Validator Reward Analysis ===");
        console.log("Lazy validator balance before:", lazyBalanceBefore);
        console.log("Lazy validator balance after:", lazyBalanceAfter);
        console.log("Reward received:", rewardReceived);

        if (rewardReceived > 0) {
            console.log("\nISSUE:");
            console.log("Lazy validator received", rewardReceived, "despite inaccurate validation");
            console.log("This creates incentive to put minimal effort into validation");
        }
    }

    /**
     * @notice Document recommended mitigations
     */
    function test_DocumentMitigations() public pure {
        console.log("=== Recommended Mitigations ===");
        console.log("");
        console.log("1. GRADUATED SLASHING:");
        console.log("   Don't use binary slash/no-slash - use graduated penalties");
        console.log("   slashAmount = deviation * slashFactor / maxDeviation;");
        console.log("");
        console.log("2. REPUTATION PENALTY FOR MILD OUTLIERS:");
        console.log("   Even if not slashed, reduce reputation for being off-consensus");
        console.log("   if (deviation > softThreshold) trust.updateReputation(v, role, false, deviation);");
        console.log("");
        console.log("3. REDUCED REWARDS FOR OUTLIERS:");
        console.log("   Scale rewards inversely with deviation from consensus");
        console.log("   reward = baseReward * (maxDeviation - deviation) / maxDeviation;");
        console.log("");
        console.log("4. ACCURACY TRACKING:");
        console.log("   Track validator accuracy over time");
        console.log("   Use historical accuracy to weight future validations");
        console.log("");
        console.log("5. TIGHTER THRESHOLD:");
        console.log("   Reduce outlier threshold from 1500 to lower value");
        console.log("   Or use percentage-based threshold (e.g., 15%)");
    }

    function _commitAndReveal(address v, bytes32 projectId, uint256 contribIndex, uint256 score) internal {
        bytes32 salt = keccak256(abi.encodePacked(v, projectId, score));
        uint256 stake = 100 ether;

        vm.startPrank(v);
        uint256 claimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, claimId, contribIndex, keccak256(abi.encodePacked(score, stake, salt)));
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        vm.prank(v);
        oracle.revealValidation(projectId, contribIndex, score, salt);
    }

    function _setupValidator(address v, uint256 amount) internal {
        _setupUser(v, amount);
        vm.startPrank(admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();
        vm.prank(v);
        oracle.setValidatorCapacity(amount);
    }
}
