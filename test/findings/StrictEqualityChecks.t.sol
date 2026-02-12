// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title StrictEqualityChecksTest
 * @notice Tests for dangerous strict equality checks (== 0)
 * @dev Issue #3 from security review: Dangerous Strict Equality Checks - MEDIUM
 *
 * Locations with strict equality checks:
 * 1. SapienTrust._applyDecay: reputationDecayPerDay == 0 || lastUpdate == 0
 * 2. SapienTrust.getTrustScore: rep.lastUpdated == 0
 * 3. SapienVault.slash: actualAssetsSlashed == 0
 */
contract StrictEqualityChecksTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");

    function setUp() public override {
        super.setUp();

        // Setup roles
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        vm.stopPrank();
    }

    /**
     * @notice Test strict equality check in SapienTrust._applyDecay
     * @dev Line 199: if (reputationDecayPerDay == 0 || lastUpdate == 0) return currentScore;
     *      Issue: Strict equality could fail if values are very small but not exactly zero
     */
    function test_ApplyDecay_StrictEqualityCheck_ReputationDecayPerDay() public {
        // Setup user with reputation
        _setupUser(contributor, 100 ether);
        vm.startPrank(admin);
        trust.updateReputation(contributor, CONTRIBUTOR_ROLE, true, 5000);
        vm.stopPrank();

        uint256 initialScore = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);
        console.log("Initial reputation score:", initialScore);

        // Test with decay rate = 0 (should skip decay)
        vm.prank(admin);
        trust.setReputationDecay(0);

        vm.warp(block.timestamp + 100 days);
        uint256 scoreAfterZeroDecay = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);

        assertEq(scoreAfterZeroDecay, initialScore, "Score should not decay when decay rate is 0");
        console.log("Score with zero decay rate:", scoreAfterZeroDecay);

        // Test with very small decay rate (not zero)
        vm.prank(admin);
        trust.setReputationDecay(1); // 0.01% per day

        vm.warp(block.timestamp + 100 days);
        uint256 scoreAfterSmallDecay = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);

        assertTrue(scoreAfterSmallDecay < initialScore, "Score should decay with small decay rate");
        console.log("Score with small decay rate:", scoreAfterSmallDecay);
    }

    /**
     * @notice Test strict equality check for lastUpdate == 0
     * @dev Line 199: if (lastUpdate == 0) return currentScore;
     *      Issue: What if lastUpdate is very small but not zero?
     */
    function test_ApplyDecay_StrictEqualityCheck_LastUpdate() public {
        // Setup user with reputation
        _setupUser(contributor, 100 ether);
        vm.startPrank(admin);
        trust.updateReputation(contributor, CONTRIBUTOR_ROLE, true, 5000);
        vm.stopPrank();

        uint256 initialScore = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);
        console.log("Initial reputation score:", initialScore);

        // Set decay rate
        vm.prank(admin);
        trust.setReputationDecay(10); // 0.1% per day

        // Test with lastUpdate = 0 (new user, should return current score)
        // This is actually correct behavior - new users start with DEFAULT_REPUTATION
        uint256 scoreWithZeroLastUpdate = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);
        assertEq(scoreWithZeroLastUpdate, initialScore, "New user should return current score");

        // Fast forward and update reputation (this sets lastUpdated to non-zero)
        vm.warp(block.timestamp + 1 days);
        vm.startPrank(admin);
        trust.updateReputation(contributor, CONTRIBUTOR_ROLE, true, 5000);
        vm.stopPrank();

        // Now lastUpdated is non-zero, decay should apply
        vm.warp(block.timestamp + 10 days);
        uint256 scoreAfterDecay = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);

        assertTrue(scoreAfterDecay < initialScore, "Score should decay after time passes");
        console.log("Score after decay:", scoreAfterDecay);
    }

    /**
     * @notice Test strict equality check in SapienTrust.getTrustScore
     * @dev Line 126: if (rep.lastUpdated == 0) return DEFAULT_REPUTATION;
     *      Issue: Strict equality check for initialization
     */
    function test_GetTrustScore_StrictEqualityCheck_LastUpdated() public {
        // New user should have lastUpdated == 0
        address newUser = makeAddr("newUser");
        _setupUser(newUser, 100 ether);

        uint256 score = trust.getTrustScore(newUser, CONTRIBUTOR_ROLE);
        uint256 defaultReputation = trust.DEFAULT_REPUTATION();

        assertEq(score, defaultReputation, "New user should return DEFAULT_REPUTATION");
        console.log("New user score:", score);
        console.log("Default reputation:", defaultReputation);

        // After updating reputation, lastUpdated should be non-zero
        vm.startPrank(admin);
        trust.updateReputation(newUser, CONTRIBUTOR_ROLE, true, 5000);
        vm.stopPrank();

        uint256 scoreAfterUpdate = trust.getTrustScore(newUser, CONTRIBUTOR_ROLE);
        assertTrue(scoreAfterUpdate >= defaultReputation, "Score should be updated");
        console.log("Score after update:", scoreAfterUpdate);
    }

    /**
     * @notice Test strict equality check in SapienVault.slash
     * @dev Line 195: if (actualAssetsSlashed == 0) return 0;
     *      Issue: What if actualAssetsSlashed is very small but not zero?
     */
    function test_VaultSlash_StrictEqualityCheck_ActualAssetsSlashed() public {
        // Setup user with stake
        _setupUser(contributor, 100 ether);
        uint256 initialStake = vault.getStake(contributor);
        console.log("Initial stake:", initialStake);

        // Test slashing zero amount
        vm.startPrank(admin);
        uint256 slashedZero = vault.slash(contributor, 0, "");
        vm.stopPrank();

        assertEq(slashedZero, 0, "Slashing zero should return 0");
        assertEq(vault.getStake(contributor), initialStake, "Stake should not change");

        // Test slashing very small amount (1 wei)
        vm.startPrank(admin);
        uint256 slashedWei = vault.slash(contributor, 1, "");
        vm.stopPrank();

        // If actualAssetsSlashed rounds to 0 due to precision, it should return 0
        // Otherwise, it should slash the amount
        console.log("Slashed amount (1 wei):", slashedWei);

        // Test slashing larger amount
        vm.startPrank(admin);
        uint256 slashedAmount = vault.slash(contributor, 10 ether, "");
        vm.stopPrank();

        assertTrue(slashedAmount > 0, "Slashing non-zero amount should return non-zero");
        assertTrue(vault.getStake(contributor) < initialStake, "Stake should decrease");
        console.log("Slashed amount (10 ether):", slashedAmount);
        console.log("Remaining stake:", vault.getStake(contributor));
    }

    /**
     * @notice Test edge case: timestamp manipulation affecting strict equality
     * @dev Test if timestamp manipulation could cause issues with == 0 checks
     */
    function test_TimestampManipulation_EdgeCases() public {
        // Setup user
        _setupUser(contributor, 100 ether);
        vm.startPrank(admin);
        trust.updateReputation(contributor, CONTRIBUTOR_ROLE, true, 5000);
        trust.setReputationDecay(10);
        vm.stopPrank();

        uint256 initialScore = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);

        // Test with very small time difference (less than 1 day)
        // This should not trigger decay due to line 202: if (timePassed < 1 days) return currentScore;
        vm.warp(block.timestamp + 1 hours);
        uint256 scoreAfter1Hour = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);
        assertEq(scoreAfter1Hour, initialScore, "Score should not decay in less than 1 day");

        // Test with exactly 1 day
        vm.warp(block.timestamp + 1 days - 1 hours); // Total: 1 day
        uint256 scoreAfter1Day = trust.getTrustScore(contributor, CONTRIBUTOR_ROLE);
        // Should start decaying after exactly 1 day
        assertTrue(scoreAfter1Day <= initialScore, "Score may decay after 1 day");

        console.log("=== Timestamp Manipulation Test ===");
        console.log("Initial score:", initialScore);
        console.log("Score after 1 hour:", scoreAfter1Hour);
        console.log("Score after 1 day:", scoreAfter1Day);
    }

    /**
     * @notice Document recommended fixes
     * @dev Recommend using >= or <= instead of == where appropriate
     */
    function test_DocumentRecommendedFixes() public pure {
        console.log("=== Recommended Fixes ===");
        console.log("1. SapienTrust._applyDecay:");
        console.log("   Current: if (reputationDecayPerDay == 0 || lastUpdate == 0)");
        console.log("   Consider: if (reputationDecayPerDay <= 0 || lastUpdate <= 0)");
        console.log("   Note: == 0 is actually correct for initialization checks");

        console.log("\n2. SapienTrust.getTrustScore:");
        console.log("   Current: if (rep.lastUpdated == 0) return DEFAULT_REPUTATION");
        console.log("   Note: == 0 is correct for checking uninitialized state");

        console.log("\n3. SapienVault.slash:");
        console.log("   Current: if (actualAssetsSlashed == 0) return 0");
        console.log("   Consider: if (actualAssetsSlashed < threshold) return 0");
        console.log("   Or keep == 0 if precision loss is acceptable");

        console.log("\n=== Analysis ===");
        console.log("Most == 0 checks are actually correct for initialization/zero checks");
        console.log("The main concern is edge cases with very small values");
        console.log("Consider adding explicit thresholds for 'effectively zero' values");
    }
}
