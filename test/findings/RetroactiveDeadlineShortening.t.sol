// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {IValidationOracle} from "../../src/interface/IValidationOracle.sol";

/**
 * @title RetroactiveDeadlineShorteningTest
 * @notice Verifies FIX for M-2 and M-5
 *
 * M-2 FIX: Reveal deadline is now snapshot at commit time in `ValidationCommit.revealDeadlineSnapshot`.
 *          The `_revealValidation` function uses this stored value instead of fetching the current
 *          project setting. Retroactive changes to the deadline no longer affect existing commits.
 *
 * M-5 FIX: `setRevealDeadline` now enforces `MIN_REVEAL_DEADLINE` (1 hour), matching the
 *          per-project `setProjectRevealDeadline` behavior.
 */
contract RetroactiveDeadlineShorteningTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("deadline-test");

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        _setupValidator(validator1, 200 ether);
        _setupValidator(validator2, 200 ether);
        _setupValidator(validator3, 200 ether);

        // Create project with default reveal deadline
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "deadline-test", 0, 0, 3, 1000, "");
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();
    }

    /**
     * @notice M-2 FIX VERIFIED: Retroactive deadline shortening no longer blocks reveals
     * @dev Steps:
     *      1. Validator commits under 3-day default deadline (snapshot stored)
     *      2. Originator changes deadline to 1 hour
     *      3. 2 hours pass (past new deadline, within original)
     *      4. Validator can still reveal using the snapshot deadline
     */
    function test_M2_Fix_RevealSucceedsWithOriginalDeadline() public {
        // 1. Submit contribution
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("work"));
        vm.stopPrank();

        // 2. Validator commits (deadline snapshot = 3 days)
        uint256 score = 8000;
        uint256 stake = 100 ether;
        bytes32 salt = keccak256("salt-v1");
        bytes32 commitHash = keccak256(abi.encodePacked(score, stake, salt));

        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(PROJECT_ID, v1ClaimId, 0, commitHash);
        vm.stopPrank();

        uint256 commitTimestamp = block.timestamp;
        console.log("=== M-2 FIX VERIFIED ===");
        console.log("Validator committed at:", commitTimestamp);

        // 3. Originator retroactively shortens deadline to 1 hour
        vm.prank(originator);
        oracle.setProjectRevealDeadline(PROJECT_ID, 1 hours);
        console.log("Originator changed deadline to 1 hour AFTER commit");

        // 4. 2 hours pass (past new 1hr deadline, within original 3-day snapshot)
        vm.warp(commitTimestamp + 2 hours);

        // 5. Validator reveals successfully using the snapshot deadline
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, score, salt);
        console.log("Reveal SUCCEEDED using snapshot deadline (3 days)");
        console.log("FIX VERIFIED: Retroactive deadline change did not block reveal.");
    }

    /**
     * @notice M-2 FIX: Validator is still bound by the ORIGINAL (snapshot) deadline
     */
    function test_M2_Fix_RevealStillFailsAfterOriginalDeadline() public {
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("work2"));
        vm.stopPrank();

        uint256 score = 8000;
        uint256 stake = 100 ether;
        bytes32 salt = keccak256("salt-v2");
        bytes32 commitHash = keccak256(abi.encodePacked(score, stake, salt));

        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(PROJECT_ID, v1ClaimId, 0, commitHash);
        vm.stopPrank();

        // Warp PAST the original snapshot deadline (3 days + 1 second)
        vm.warp(block.timestamp + 3 days + 1);

        vm.prank(validator1);
        vm.expectRevert("Reveal deadline passed");
        oracle.revealValidation(PROJECT_ID, 0, score, salt);

        console.log("FIX VERIFIED: Reveal correctly fails after ORIGINAL deadline expires.");
    }

    /**
     * @notice M-5 FIX VERIFIED: Global setRevealDeadline now enforces minimum
     */
    function test_M5_Fix_GlobalDeadlineEnforcesMinimum() public {
        console.log("=== M-5 FIX VERIFIED ===");

        // Admin cannot set global deadline to 0
        vm.prank(admin);
        vm.expectRevert(IValidationOracle.InvalidDeadline.selector);
        oracle.setRevealDeadline(0);
        console.log("setRevealDeadline(0) correctly reverted with InvalidDeadline");

        // Admin cannot set below MIN_REVEAL_DEADLINE (1 hour)
        vm.prank(admin);
        vm.expectRevert(IValidationOracle.InvalidDeadline.selector);
        oracle.setRevealDeadline(30 minutes);
        console.log("setRevealDeadline(30min) correctly reverted with InvalidDeadline");

        // Admin CAN set to exactly MIN_REVEAL_DEADLINE
        vm.prank(admin);
        oracle.setRevealDeadline(1 hours);
        assertEq(oracle.revealDeadline(), 1 hours, "Should allow setting to MIN_REVEAL_DEADLINE");
        console.log("setRevealDeadline(1 hour) succeeded - minimum enforced correctly");

        console.log("FIX VERIFIED: Global and per-project deadlines now have consistent minimum checks.");
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
}
