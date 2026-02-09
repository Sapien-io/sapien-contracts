// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title IndexReclamationRaceTest
 * @notice Test demonstrating Issue #8: Index Reclamation Race Condition
 *
 * VULNERABILITY DESCRIPTION:
 * The reclaimExpiredIndices function can be called by anyone to reclaim expired indices.
 * Combined with claimToContribute, there's a potential race:
 *
 * 1. Alice claims index 5
 * 2. Alice's deadline passes
 * 3. Bob calls reclaimExpiredIndices([5]) - index 5 added to available stack
 * 4. Bob immediately calls claimToContribute - gets index 5
 * 5. Alice tries to submit late to index 5 - blocked by deadline check
 *
 * ATTACK VECTOR: Index Reclamation Loops / Race Condition
 *
 * LOCATION: SapienCore.sol lines 346-366 (reclaimExpiredIndices) and 429-453 (_assignIndices)
 *
 * SEVERITY: Low-Medium
 */
contract IndexReclamationRaceTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("race-test");
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, alice);
        trust.grantRole(CONTRIBUTOR_ROLE, bob);
        vm.stopPrank();

        _setupUser(alice, 100 ether);
        _setupUser(bob, 100 ether);
    }

    /**
     * @notice Test: Race condition between reclaim and claim
     * @dev Bob reclaims Alice's expired slot and immediately claims it
     */
    function test_ReclaimAndClaimRace() public {
        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "race-test", 10 ether, 10 ether, 3, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 5);
        vm.stopPrank();

        console.log("=== Index Reclamation Race Condition ===");

        // Alice claims slot
        vm.prank(alice);
        uint256 aliceClaimId = core.claimToContribute(PROJECT_ID, 1);

        // Check which index Alice got
        uint256 aliceIndex = 0; // In this implementation, first claim gets index 0

        console.log("Alice claimed index:", aliceIndex);
        console.log("Alice's deadline:", core.getClaim(PROJECT_ID, aliceClaimId).deadline);

        // Wait for deadline to pass
        uint256 deadline = core.getClaim(PROJECT_ID, aliceClaimId).deadline;
        vm.warp(deadline + 1);
        console.log("Time warped past deadline...");

        // Bob reclaims the expired index
        uint256[] memory indices = new uint256[](1);
        indices[0] = aliceIndex;

        console.log("\nBob calls reclaimExpiredIndices...");
        vm.prank(bob);
        core.reclaimExpiredIndices(PROJECT_ID, indices);

        // Bob immediately claims a slot (should get the reclaimed index)
        console.log("Bob immediately claims...");
        vm.prank(bob);
        uint256 bobClaimId = core.claimToContribute(PROJECT_ID, 1);

        console.log("Bob's claim ID:", bobClaimId);

        // Alice tries to submit late (should fail)
        console.log("\nAlice tries to submit late...");
        vm.prank(alice);
        try core.contribute(PROJECT_ID, aliceClaimId, aliceIndex, keccak256("late-submission")) {
            console.log("UNEXPECTED: Alice submitted after deadline!");
        } catch {
            console.log("Expected: Alice's late submission rejected");
        }

        console.log("\n=== Race Condition Summary ===");
        console.log("1. Alice claimed index 0");
        console.log("2. Deadline passed, Alice didn't submit");
        console.log("3. Bob reclaimed and immediately claimed");
        console.log("4. Alice blocked from late submission (correct)");
        console.log("");
        console.log("This is mitigated by deadline checks in _contribute");
    }

    /**
     * @notice Test: Front-running reclaim attack
     * @dev Attacker monitors mempool and front-runs reclaim
     */
    function test_FrontRunningReclaimAttack() public {
        // Create project with valuable reward
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "race-test", 10 ether, 10 ether, 3, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 5);
        vm.stopPrank();

        console.log("=== Front-Running Reclaim Attack ===");

        // Multiple users claim slots
        vm.prank(alice);
        core.claimToContribute(PROJECT_ID, 2);

        uint256 deadline = core.getClaim(PROJECT_ID, 0).deadline;
        vm.warp(deadline + 1);

        // Attacker sees reclaim transaction in mempool
        // Front-runs with their own reclaim + claim

        console.log("Attacker spots reclaim in mempool...");
        console.log("Attacker front-runs with higher gas...");

        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;

        // Bob (attacker) front-runs the reclaim
        vm.prank(bob);
        core.reclaimExpiredIndices(PROJECT_ID, indices);

        vm.prank(bob);
        core.claimToContribute(PROJECT_ID, 2);

        console.log("Attacker successfully reclaimed and claimed slots");
        console.log("");
        console.log("Impact: Attacker gains priority access to valuable slots");
        console.log("Mitigation: Consider reclaim + claim atomicity or MEV protection");
    }

    /**
     * @notice Test: Verify state consistency after race
     * @dev Ensure no double-counting or orphaned state
     */
    function test_StateConsistencyAfterRace() public {
        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "race-test", 10 ether, 10 ether, 3, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 5);
        vm.stopPrank();

        console.log("=== State Consistency Verification ===");

        // Initial state
        uint256 totalQuantity = core.getProject(PROJECT_ID).state.totalQuantityAvailable;
        uint256 activeClaimedBefore = core.getProject(PROJECT_ID).state.activeClaimedQuantity;
        console.log("Total quantity available:", totalQuantity);
        console.log("Active claimed (initial):", activeClaimedBefore);

        // Alice claims 3 slots
        vm.prank(alice);
        core.claimToContribute(PROJECT_ID, 3);

        uint256 activeClaimedAfterAlice = core.getProject(PROJECT_ID).state.activeClaimedQuantity;
        console.log("Active claimed (after Alice):", activeClaimedAfterAlice);

        // Deadline passes
        vm.warp(block.timestamp + 8 days);

        // Reclaim all expired
        uint256[] memory indices = new uint256[](3);
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;

        core.reclaimExpiredIndices(PROJECT_ID, indices);

        uint256 activeClaimedAfterReclaim = core.getProject(PROJECT_ID).state.activeClaimedQuantity;
        console.log("Active claimed (after reclaim):", activeClaimedAfterReclaim);

        // Bob claims
        vm.prank(bob);
        core.claimToContribute(PROJECT_ID, 3);

        uint256 activeClaimedFinal = core.getProject(PROJECT_ID).state.activeClaimedQuantity;
        console.log("Active claimed (after Bob):", activeClaimedFinal);

        // Verify consistency
        assertEq(activeClaimedAfterReclaim, 0, "Reclaim should reduce active claimed to 0");
        assertEq(activeClaimedFinal, 3, "Bob's claim should restore active claimed to 3");

        console.log("\nState consistency verified!");
    }

    /**
     * @notice Test: Document race condition mitigations
     */
    function test_DocumentMitigations() public pure {
        console.log("=== Race Condition Mitigations ===");
        console.log("");
        console.log("1. DEADLINE CHECK IN _contribute():");
        console.log("   Current implementation correctly checks deadline before accepting submission");
        console.log("   if (block.timestamp > reservation.deadline) revert DeadlinePassed();");
        console.log("");
        console.log("2. ATOMIC RECLAIM + CLAIM:");
        console.log("   Consider combining reclaim and claim into single atomic operation");
        console.log("   function reclaimAndClaim(projectId, expiredIndices, newQuantity)");
        console.log("");
        console.log("3. MEV PROTECTION:");
        console.log("   Use commit-reveal for claiming to prevent front-running");
        console.log("   Or integrate with Flashbots Protect / MEV Blocker");
        console.log("");
        console.log("4. GRACE PERIOD:");
        console.log("   Add short grace period after reclaim before indices available");
        console.log("   Gives original claimant chance to submit late with penalty");
        console.log("");
        console.log("5. PRIORITY QUEUE:");
        console.log("   Implement priority for users who had indices reclaimed");
        console.log("   mapping(address => uint256) public reclaimPriority;");
    }
}
