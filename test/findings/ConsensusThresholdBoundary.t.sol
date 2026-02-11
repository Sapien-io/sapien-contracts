// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {ISapienCore} from "../../src/interface/ISapienCore.sol";

/**
 * @title ConsensusThresholdBoundaryTest
 * @notice Test demonstrating Issue #12: Missing Validation on Consensus Threshold
 *
 * VULNERABILITY DESCRIPTION:
 * Setting threshold to 0 means all contributions pass; setting to 10001+ is blocked
 * but there's no minimum. A threshold of 1 effectively approves everything.
 *
 * ATTACK VECTOR: Configuration Error / Admin Mistake
 *
 * LOCATION: SapienCore.sol line 191-195 (setConsensusThreshold)
 *
 * SEVERITY: Low
 */
contract ConsensusThresholdBoundaryTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("threshold-test");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        _setupValidator(validator1, 100 ether);
        _setupValidator(validator2, 100 ether);
        _setupValidator(validator3, 100 ether);
    }

    /**
     * @notice Test: Fix verification - Zero threshold is now blocked
     * @dev Issue #12 fix: setConsensusThreshold enforces MIN_CONSENSUS_THRESHOLD
     */
    function test_ZeroThresholdBlocked() public {
        uint256 minThreshold = core.MIN_CONSENSUS_THRESHOLD();
        console.log("=== Fix Verification: Minimum Consensus Threshold ===");
        console.log("Minimum threshold:", minThreshold);

        // Try to set threshold to 0 - should revert
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusThresholdOutOfRange.selector, 0, 1000, 10000));
        core.setConsensusThreshold(0);

        console.log("FIX VERIFIED: Zero threshold blocked");

        // Verify setting threshold at minimum works
        vm.prank(admin);
        core.setConsensusThreshold(minThreshold);

        uint256 currentThreshold = core.consensusThreshold();
        console.log("Current threshold:", currentThreshold);
        assertEq(currentThreshold, minThreshold, "Threshold should be at minimum");

        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "threshold-test", 0, 0, 2, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Contributor submits terrible work
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("terrible-work"));
        vm.stopPrank();

        // Validators give terrible score
        _validateContribution(PROJECT_ID, 0, 100); // Score of 100/10000 = 1%

        // Finalize
        core.finalizeContribution(PROJECT_ID, 0);

        uint256 status = uint256(core.getContribution(PROJECT_ID, 0).status);
        console.log("Contribution status (2=Accepted, 3=Rejected):", status);

        if (status == 2) {
            console.log("\nVULNERABILITY CONFIRMED:");
            console.log("Contribution with score 100 was ACCEPTED!");
            console.log("Threshold of 0 means everything passes.");
        }
    }

    /**
     * @notice Test: Fix verification - Low threshold (1) is now blocked
     * @dev Issue #12 fix: setConsensusThreshold enforces MIN_CONSENSUS_THRESHOLD
     */
    function test_LowThresholdBlocked() public {
        uint256 minThreshold = core.MIN_CONSENSUS_THRESHOLD();

        // Try to set threshold to 1 - should revert
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusThresholdOutOfRange.selector, 1, 1000, 10000));
        core.setConsensusThreshold(1);

        console.log("=== Fix Verification: Low Threshold Blocked ===");
        console.log("Minimum threshold:", minThreshold);
        console.log("Attempted threshold: 1");
        console.log("FIX VERIFIED: Low threshold blocked");
    }

    /**
     * @notice Test: Upper boundary correctly enforced
     */
    function test_UpperBoundaryEnforced() public {
        console.log("=== Upper Boundary Test ===");

        // Try to set threshold > 10000
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusThresholdOutOfRange.selector, 10001, 1000, 10000));
        core.setConsensusThreshold(10001);
        console.log("Correctly reverted when trying to set threshold to 10001");

        // Threshold at exactly 10000 should work
        vm.prank(admin);
        core.setConsensusThreshold(10000);

        uint256 threshold = core.consensusThreshold();
        console.log("Threshold set to:", threshold);
        assertEq(threshold, 10000, "Should allow threshold of 10000");
    }

    /**
     * @notice Test: Threshold of 10000 rejects everything except perfect scores
     */
    function test_MaxThresholdRejectsAlmost() public {
        // Set threshold to 10000 (100%)
        vm.prank(admin);
        core.setConsensusThreshold(10000);

        console.log("=== Maximum Threshold (10000) ===");
        console.log("Only perfect scores (10000) can pass");

        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "threshold-test", 0, 0, 2, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Submit excellent work
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("excellent-work"));
        vm.stopPrank();

        // Give near-perfect score
        _validateContribution(PROJECT_ID, 0, 9999); // 99.99%

        core.finalizeContribution(PROJECT_ID, 0);

        uint256 status = uint256(core.getContribution(PROJECT_ID, 0).status);
        console.log("Validation score: 9999");
        console.log("Contribution status:", status);

        if (status == 3) {
            console.log("Even 99.99% quality work is REJECTED with max threshold!");
            console.log("This may be too restrictive for practical use.");
        }
    }

    /**
     * @notice Test: Reasonable threshold range
     */
    function test_ReasonableThresholdRange() public {
        console.log("=== Reasonable Threshold Testing ===");

        // Test at 5000 (50% - default)
        vm.prank(admin);
        core.setConsensusThreshold(5000);

        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "threshold-test", 0, 0, 2, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Borderline case at threshold
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Score exactly at threshold
        _validateContribution(PROJECT_ID, 0, 5000);

        core.finalizeContribution(PROJECT_ID, 0);

        uint256 status = uint256(core.getContribution(PROJECT_ID, 0).status);
        console.log("Threshold: 5000");
        console.log("Score: 5000");
        console.log("Status:", status);

        // At exactly threshold, should it pass or fail?
        // This tests the >= vs > logic
        if (status == 2) {
            console.log("Contribution ACCEPTED at exact threshold (>=)");
        } else {
            console.log("Contribution REJECTED at exact threshold (>)");
        }
    }

    /**
     * @notice Document recommended mitigations
     */
    function test_DocumentMitigations() public pure {
        console.log("=== Recommended Mitigations ===");
        console.log("");
        console.log("1. ADD MINIMUM THRESHOLD CHECK:");
        console.log("   uint256 constant MIN_THRESHOLD = 1000; // 10%");
        console.log("   if (_threshold < MIN_THRESHOLD) revert ThresholdTooLow();");
        console.log("");
        console.log("2. USE ENUMERATED PRESETS:");
        console.log("   enum ThresholdLevel { PERMISSIVE, MODERATE, STRICT }");
        console.log("   mapping(ThresholdLevel => uint256) thresholds;");
        console.log("   thresholds[PERMISSIVE] = 3000; // 30%");
        console.log("   thresholds[MODERATE] = 5000;   // 50%");
        console.log("   thresholds[STRICT] = 7000;     // 70%");
        console.log("");
        console.log("3. REQUIRE TIMELOCK FOR THRESHOLD CHANGES:");
        console.log("   function setConsensusThreshold(uint256 _t) external onlyRole(ADMIN) {");
        console.log("       pendingThreshold = _t;");
        console.log("       pendingThresholdActivation = block.timestamp + 24 hours;");
        console.log("   }");
        console.log("");
        console.log("4. DOCUMENT THRESHOLD SEMANTICS:");
        console.log("   // @notice Threshold is inclusive: score >= threshold passes");
        console.log("   // @notice 5000 = 50% minimum quality score");
    }

    function _validateContribution(bytes32 projectId, uint256 contribIndex, uint256 score) internal {
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");
        uint256 stake = 100 ether;

        vm.startPrank(validator1);
        uint256 v1Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v1Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt1)));
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v2Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt2)));
        vm.stopPrank();

        vm.startPrank(validator3);
        uint256 v3Claim = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, v3Claim, contribIndex, keccak256(abi.encodePacked(score, stake, salt3)));
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        vm.prank(validator1);
        oracle.revealValidation(projectId, contribIndex, score, salt1);
        vm.prank(validator2);
        oracle.revealValidation(projectId, contribIndex, score, salt2);
        vm.prank(validator3);
        oracle.revealValidation(projectId, contribIndex, score, salt3);
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
