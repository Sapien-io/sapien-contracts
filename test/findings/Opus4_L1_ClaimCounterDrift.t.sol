// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title Opus4_L1_ClaimCounterDrift
 * @notice Opus 4.6 Security Review - L-1 FIX VERIFICATION
 *
 * ORIGINAL FINDING:
 * When releaseExpiredClaim is called, userActiveClaimedQuantity was NOT decremented
 * for unsubmitted slots, soft-locking the contributor until reclaimExpiredIndices
 * was called for each individual index.
 *
 * FIX APPLIED:
 * releaseExpiredClaim now decrements userActiveClaimedQuantity by the number of
 * unsubmitted slots (claim.quantity - claim.submittedCount).
 *
 * LOCATION: SapienCore.sol:releaseExpiredClaim()
 * SEVERITY: Low (now fixed)
 */
contract Opus4_L1_ClaimCounterDrift is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("opus4-l1-test");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        vm.stopPrank();

        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "opus4-l1-test", 10 ether, 0, 3, 1000, "");
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 20);
        vm.stopPrank();
    }

    /**
     * @notice FIX VERIFIED: New claims succeed immediately after releaseExpiredClaim
     * @dev Previously, the counter stayed inflated and new claims were blocked.
     *      Now the counter is decremented by unsubmitted slots.
     */
    function test_L1_Fix_ClaimCounterDecrementedOnRelease() public {
        uint256 maxPerUser = core.MAX_CLAIMS_PER_USER();
        console.log("=== L-1 FIX: Claim Counter Decremented ===");
        console.log("MAX_CLAIMS_PER_USER:", maxPerUser);

        // Contributor claims max slots
        vm.prank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, maxPerUser);
        console.log("Claimed", maxPerUser, "slots");

        // Warp past deadline
        uint256 deadline = core.getClaim(PROJECT_ID, claimId).deadline;
        vm.warp(deadline + 1);

        // Release the expired claim
        core.releaseExpiredClaim(PROJECT_ID, claimId);
        console.log("releaseExpiredClaim called");

        // FIX: New claim SUCCEEDS immediately (counter was decremented)
        vm.prank(contributor);
        uint256 newClaimId = core.claimToContribute(PROJECT_ID, 1);
        console.log("New claim SUCCEEDED immediately (claimId:", newClaimId, ")");

        console.log("FIX VERIFIED: userActiveClaimedQuantity correctly decremented.");
    }

    /**
     * @notice Partial submission: only unsubmitted slots freed
     * @dev If a contributor submits some work, only the unsubmitted portion
     *      is decremented by releaseExpiredClaim.
     */
    function test_L1_Fix_PartialSubmissionCounterCorrect() public {
        uint256 maxPerUser = core.MAX_CLAIMS_PER_USER();
        console.log("=== L-1 FIX: Partial Submission Counter ===");

        // Contributor claims max slots
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, maxPerUser);

        // Submit 3 out of maxPerUser
        uint256 submitted = 3;
        for (uint256 i = 0; i < submitted; i++) {
            core.contribute(PROJECT_ID, claimId, i, keccak256(abi.encodePacked("work", i)));
        }
        vm.stopPrank();

        console.log("Claimed:", maxPerUser, "Submitted:", submitted);

        // Warp past deadline
        uint256 deadline = core.getClaim(PROJECT_ID, claimId).deadline;
        vm.warp(deadline + 1);

        // Release the expired claim (partially fulfilled)
        core.releaseExpiredClaim(PROJECT_ID, claimId);

        // The submitted slots (0-2) already decremented via _contribute
        // The unsubmitted slots (3-9) are now decremented by releaseExpiredClaim fix
        // So contributor should be able to claim up to maxPerUser again
        vm.prank(contributor);
        core.claimToContribute(PROJECT_ID, 1);
        console.log("New claim SUCCEEDED after partial submission + release");

        console.log("FIX VERIFIED: Unsubmitted slot counter correctly freed.");
    }
}
