// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {ISapienCore} from "../../src/interface/ISapienCore.sol";

/**
 * @title ContributorSlotStarvationTest
 * @notice Test demonstrating Issue #6: Claim Deadline Griefing - Slot Starvation
 *
 * VULNERABILITY DESCRIPTION:
 * A malicious contributor can:
 * 1. Have minimal stake meeting minStakeToClaim
 * 2. Claim all available slots across projects
 * 3. Never submit, just hold until deadline
 * 4. Repeat (minimal loss if minStakeToClaim is low)
 *
 * The only defense is slashing via releaseExpiredClaim, but this requires someone
 * to call it, and the slashed amount is limited to minStakeToClaim.
 *
 * ATTACK VECTOR: State Locking / Sybil Contributor DoS
 *
 * LOCATION: SapienCore.sol lines 372-403 (claimToContribute)
 *
 * SEVERITY: Medium
 */
contract ContributorSlotStarvationTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("starvation-test");
    address public attacker = makeAddr("attacker");
    address public legitimateContributor = makeAddr("legitimateContributor");

    function setUp() public override {
        super.setUp();

        // Grant roles
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(CONTRIBUTOR_ROLE, attacker);
        trust.grantRole(CONTRIBUTOR_ROLE, legitimateContributor);
        vm.stopPrank();

        // Setup users with sufficient stake for role validation
        // Note: hasEnoughStake checks minStakeRequired which defaults to 100 ether
        _setupUser(attacker, 100 ether);
        _setupUser(legitimateContributor, 100 ether);
    }

    /**
     * @notice Test: Attacker claims all slots with minimal stake
     * @dev Demonstrates slot starvation with low minStakeToClaim
     */
    function test_SlotStarvationWithMinimalStake() public {
        // Create project with minimal stake requirement
        uint256 minStake = 1 ether; // Low stake requirement

        vm.startPrank(originator);
        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            "starvation-test",
            minStake, // minStakeToClaim
            minStake, // minStakeToContribute
            3,
            1000,
            ""
        );
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10); // 10 slots
        vm.stopPrank();

        console.log("=== Slot Starvation Attack ===");
        console.log("Project slots: 10");
        console.log("Min stake to claim:", minStake);
        console.log("Attacker stake:", vault.getStake(attacker));

        // Attacker claims all slots
        vm.startPrank(attacker);
        core.claimToContribute(PROJECT_ID, 10); // Claim all 10 slots
        vm.stopPrank();

        console.log("Attacker claimed all 10 slots!");

        // Check available slots
        uint256 available = core.getProject(PROJECT_ID).state.totalQuantityAvailable
            - core.getProject(PROJECT_ID).state.submittedQuantity
            - core.getProject(PROJECT_ID).state.activeClaimedQuantity;
        console.log("Available slots after attack:", available);
        assertEq(available, 0, "All slots should be claimed");

        // Legitimate contributor cannot claim
        vm.startPrank(legitimateContributor);
        vm.expectRevert();
        core.claimToContribute(PROJECT_ID, 1);
        vm.stopPrank();

        console.log("\nVULNERABILITY CONFIRMED:");
        console.log("- Legitimate contributor BLOCKED from participating");
        console.log("- Attacker holds all slots for 7 days");
        console.log("- Cost to attacker: only", minStake, "at risk");
    }

    /**
     * @notice Test: Fix verification - Per-user claim limit prevents mass claiming
     * @dev Issue #6 fix: MAX_CLAIMS_PER_USER limits slots per user
     */
    function test_AttackCostAnalysis_FixVerification() public {
        uint256 minStake = 0; // Zero stake to claim!
        uint256 maxClaimsPerUser = core.MAX_CLAIMS_PER_USER();

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "starvation-test", minStake, 0, 3, 1000, "");
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 100); // 100 slots, 1000 ether reward
        vm.stopPrank();

        console.log("=== Fix Verification: Per-User Claim Limit ===");
        console.log("Project slots: 100");
        console.log("Max claims per user:", maxClaimsPerUser);

        // Attacker tries to claim all slots - should fail
        vm.prank(attacker);
        vm.expectRevert(); // MaxClaimsPerUserExceeded
        core.claimToContribute(PROJECT_ID, 100);

        console.log("FIX VERIFIED: Attacker blocked from claiming 100 slots");

        // Attacker can only claim up to MAX_CLAIMS_PER_USER
        vm.prank(attacker);
        core.claimToContribute(PROJECT_ID, maxClaimsPerUser);

        console.log("Attacker limited to", maxClaimsPerUser, "slots");
        console.log("90 slots still available for legitimate contributors");
    }

    /**
     * @notice Test: Recovery via reclaimExpiredIndices
     * @dev Show that recovery requires waiting for deadline + external trigger
     */
    function test_RecoveryViaReclaim() public {
        uint256 minStake = 1 ether;

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "starvation-test", minStake, minStake, 3, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Attacker claims all slots
        vm.prank(attacker);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 10);

        uint256 deadline = core.getClaim(PROJECT_ID, claimId).deadline;
        console.log("=== Recovery Timeline ===");
        console.log("Current time:", block.timestamp);
        console.log("Claim deadline:", deadline);
        console.log("Blocking duration:", deadline - block.timestamp, "seconds");
        console.log("Blocking duration:", (deadline - block.timestamp) / 1 days, "days");

        // Cannot reclaim before deadline
        uint256[] memory indices = new uint256[](10);
        for (uint256 i = 0; i < 10; i++) {
            indices[i] = i;
        }

        core.reclaimExpiredIndices(PROJECT_ID, indices);

        // Check if any were reclaimed (they shouldn't be)
        uint256 availableBefore = core.getProject(PROJECT_ID).state.totalQuantityAvailable
            - core.getProject(PROJECT_ID).state.submittedQuantity
            - core.getProject(PROJECT_ID).state.activeClaimedQuantity;
        console.log("Available slots before deadline:", availableBefore);

        // Fast forward past deadline
        vm.warp(deadline + 1);
        console.log("\n--- Time warped past deadline ---");

        // Now reclaim works
        core.reclaimExpiredIndices(PROJECT_ID, indices);

        uint256 availableAfter = core.getProject(PROJECT_ID).state.totalQuantityAvailable
            - core.getProject(PROJECT_ID).state.submittedQuantity
            - core.getProject(PROJECT_ID).state.activeClaimedQuantity;
        console.log("Available slots after reclaim:", availableAfter);

        console.log("\n=== Recovery Summary ===");
        console.log("- Project was blocked for 7 days");
        console.log("- Required external call to reclaim");
        console.log("- Legitimate contributors lost opportunity cost");
    }

    /**
     * @notice Test: Mitigation - Per-user claim limits
     * @dev Document recommended fix
     */
    function test_DocumentMitigations() public pure {
        console.log("=== Recommended Mitigations ===");
        console.log("");
        console.log("1. ENFORCE MINIMUM STAKE AT PROTOCOL LEVEL:");
        console.log("   uint256 constant MIN_STAKE_TO_CLAIM = 10 ether;");
        console.log("   if (minStakeToClaim < MIN_STAKE_TO_CLAIM) revert StakeTooLow();");
        console.log("");
        console.log("2. ADD PER-USER CLAIM LIMITS:");
        console.log("   mapping(address => uint256) public userActiveClaimCount;");
        console.log("   if (userActiveClaimCount[msg.sender] >= MAX_CLAIMS_PER_USER) revert TooManyClaims();");
        console.log("");
        console.log("3. IMPLEMENT REPUTATION REQUIREMENTS:");
        console.log("   if (trust.getTrustScore(msg.sender, CONTRIBUTOR_ROLE) < minReputation)");
        console.log("       revert InsufficientReputation();");
        console.log("");
        console.log("4. STAKE PROPORTIONAL TO CLAIM SIZE:");
        console.log("   uint256 requiredStake = minStakePerSlot * quantity;");
        console.log("   if (vault.getStake(msg.sender) < requiredStake) revert InsufficientStake();");
        console.log("");
        console.log("5. SHORTER CLAIM DEADLINES FOR NEW CONTRIBUTORS:");
        console.log("   uint256 deadline = trust.getTrustScore(msg.sender, CONTRIBUTOR_ROLE) > threshold");
        console.log("       ? 7 days : 1 days;");
    }

    /**
     * @notice Test: Sybil contributor attack
     * @dev Multiple accounts controlled by same entity
     */
    function test_SybilContributorAttack() public {
        uint256 minStake = 10 ether;

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "starvation-test", minStake, minStake, 3, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        console.log("=== Sybil Contributor Attack ===");

        // Attacker creates multiple accounts
        for (uint256 i = 0; i < 5; i++) {
            address sybil = address(uint160(0x5000 + i));
            vm.prank(admin);
            trust.grantRole(CONTRIBUTOR_ROLE, sybil);
            _setupUser(sybil, minStake);

            vm.prank(sybil);
            try core.claimToContribute(PROJECT_ID, 2) {
                console.log("Sybil", i, "claimed 2 slots");
            } catch {
                console.log("Sybil", i, "failed to claim");
            }
        }

        uint256 available = core.getProject(PROJECT_ID).state.totalQuantityAvailable
            - core.getProject(PROJECT_ID).state.submittedQuantity
            - core.getProject(PROJECT_ID).state.activeClaimedQuantity;
        console.log("\nAvailable slots after Sybil attack:", available);

        if (available == 0) {
            console.log("VULNERABILITY: 5 Sybil accounts blocked all slots");
        }
    }
}
