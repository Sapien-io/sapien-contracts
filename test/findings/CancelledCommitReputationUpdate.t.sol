// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "lib/forge-std/src/console.sol";
import {VALIDATOR_ROLE, UPDATER_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title CancelledCommitReputationUpdateTest
 * @notice Tests for QS-3: cancelExpiredCommitment() does not update reputation
 * @dev This test demonstrates the vulnerability where validators can maintain
 *      high reputation scores even after failing to reveal commitments.
 */
contract CancelledCommitReputationUpdateTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("reputation-gaming-project");
    bytes32 public constant PROJECT_ID_2 = keccak256("reputation-gaming-project-2");

    function setUp() public override {
        super.setUp();
    }

    /**
     * @notice Test that cancelExpiredCommitment() does NOT update reputation
     * @dev This demonstrates the vulnerability - reputation only changes due to decay,
     *      not due to explicit penalty for failing to reveal
     */
    function test_CancelExpiredCommitment_DoesNotUpdateReputation() public {
        // Setup project
        vm.prank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "reputation-gaming-project", 100 ether, 0, 1, 500, "test");

        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();

        // Setup contributor
        vm.prank(admin);
        trust.validateSkill(contributor, "test");

        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("sub"));
        vm.stopPrank();

        // Setup validator with high initial reputation
        _setupValidator(validator1, 1000 ether);
        vm.startPrank(admin);
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 8000); // Set high reputation
        vm.stopPrank();

        uint256 initialReputation = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        console.log("Initial reputation:", initialReputation);

        // Validator commits but will intentionally not reveal
        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v1ClaimId, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt1")))
        );
        vm.stopPrank();

        // Warp past reveal deadline (but not enough for significant decay)
        vm.warp(block.timestamp + 4 days);

        // Get reputation before cancelExpiredCommitment
        uint256 reputationBefore = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        uint256 balanceBefore = vault.getStake(validator1);

        // Cancel expired commitment (this should slash AND update reputation)
        vm.prank(validator1);
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);

        // Get reputation immediately after cancelExpiredCommitment (no time passed for decay)
        uint256 reputationAfter = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        uint256 balanceAfter = vault.getStake(validator1);

        console.log("Reputation before cancel:", reputationBefore);
        console.log("Reputation after cancel:", reputationAfter);
        console.log("Balance before:", balanceBefore);
        console.log("Balance after:", balanceAfter);

        // FIXED: Reputation should decrease by SLASH_DECREASE (100 bps = 1%) for failing to reveal
        assertTrue(reputationAfter < reputationBefore, "Reputation should decrease due to explicit penalty");
        assertEq(reputationBefore - reputationAfter, 100, "Reputation should decrease by SLASH_DECREASE (100 bps)");

        // Balance should also decrease (slashing works)
        assertTrue(balanceAfter < balanceBefore, "Validator should be slashed");
    }

    /**
     * @notice Test that cancelExpiredValidationClaim() DOES update reputation
     * @dev This shows the inconsistency - similar function updates reputation correctly
     */
    function test_CancelExpiredValidationClaim_DoesUpdateReputation() public {
        // Setup project
        vm.prank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "reputation-gaming-project", 100 ether, 0, 1, 500, "test");

        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();

        // Setup contributor to create a contribution that needs validation
        vm.prank(admin);
        trust.validateSkill(contributor, "test");

        vm.startPrank(contributor);
        uint256 contribClaimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, contribClaimId, 0, keccak256("sub"));
        vm.stopPrank();

        // Setup validator with high initial reputation
        _setupValidator(validator1, 1000 ether);
        vm.startPrank(admin);
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 8000); // Set high reputation
        vm.stopPrank();

        uint256 initialReputation = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        console.log("Initial reputation:", initialReputation);

        // Validator claims but never commits
        vm.startPrank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);
        vm.stopPrank();

        // Warp past claim deadline
        vm.warp(block.timestamp + 8 days); // Past 7 day claim deadline

        // Get reputation before cancelExpiredValidationClaim
        uint256 reputationBefore = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        uint256 balanceBefore = vault.getStake(validator1);

        // Cancel expired validation claim
        vm.prank(validator1);
        oracle.cancelExpiredValidationClaim(PROJECT_ID, claimId);

        // Get reputation immediately after cancelExpiredValidationClaim
        uint256 reputationAfter = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        uint256 balanceAfter = vault.getStake(validator1);

        console.log("Reputation before cancel:", reputationBefore);
        console.log("Reputation after cancel:", reputationAfter);
        console.log("Expected decrease (SLASH_DECREASE = 100 bps): 100");
        console.log("Actual decrease:", reputationBefore - reputationAfter);
        console.log("Balance before:", balanceBefore);
        console.log("Balance after:", balanceAfter);

        // CORRECT BEHAVIOR: Reputation should decrease by SLASH_DECREASE (100 bps = 1%)
        // Note: Some decay may also apply, but the explicit penalty should be visible
        assertTrue(reputationAfter < reputationBefore, "Reputation should decrease due to explicit penalty");

        // Balance should also decrease (slashing works)
        assertTrue(balanceAfter < balanceBefore, "Validator should be slashed");
    }

    /**
     * @notice Test demonstrating reputation gaming attack
     * @dev Shows how a validator can maintain high reputation while intentionally
     *      failing to reveal commitments - only paying economic cost, not reputation cost
     */
    function test_ReputationGamingAttack() public {
        // Setup project
        vm.prank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "reputation-gaming-project", 100 ether, 0, 1, 500, "test");

        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();

        // Setup contributor
        vm.prank(admin);
        trust.validateSkill(contributor, "test");

        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("sub"));
        vm.stopPrank();

        // Setup validator with high initial reputation
        _setupValidator(validator1, 1000 ether);
        vm.startPrank(admin);
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 9000); // Very high reputation
        vm.stopPrank();

        uint256 initialReputation = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        console.log("=== ATTACK SCENARIO ===");
        console.log("Initial reputation:", initialReputation);

        // Attack: Validator commits but never reveals
        // This allows them to maintain high reputation while only paying economic cost

        vm.startPrank(validator1);
        uint256 vClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, vClaimId, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt")))
        );
        vm.stopPrank();

        // Warp past reveal deadline (but minimal time for decay)
        vm.warp(block.timestamp + 4 days);

        uint256 reputationBeforeCancel = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        uint256 balanceBefore = vault.getStake(validator1);

        // Cancel expired commitment
        vm.prank(validator1);
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);

        uint256 reputationAfterCancel = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        uint256 balanceAfter = vault.getStake(validator1);

        console.log("Reputation before cancel:", reputationBeforeCancel);
        console.log("Reputation after cancel:", reputationAfterCancel);
        console.log("Balance before:", balanceBefore);
        console.log("Balance after:", balanceAfter);
        console.log("Balance lost:", balanceBefore - balanceAfter);

        // FIXED: Reputation should decrease by SLASH_DECREASE (100 bps = 1%) for failing to reveal
        assertTrue(reputationAfterCancel < reputationBeforeCancel, "Reputation should decrease due to explicit penalty");
        assertEq(
            reputationBeforeCancel - reputationAfterCancel,
            100,
            "Reputation should decrease by SLASH_DECREASE (100 bps)"
        );

        // Balance also decreases (both economic and reputation penalties apply)
        assertTrue(balanceAfter < balanceBefore, "Validator should be slashed economically");

        // Attack prevented: Validator now pays both economic and reputation costs
        // This prevents reputation gaming and maintains protocol integrity
    }

    /**
     * @notice Test showing impact on consensus weighting
     * @dev Demonstrates that high reputation affects consensus calculations
     *      and the vulnerability allows maintaining high reputation despite failures
     */
    function test_ReputationAffectsConsensusWeighting() public {
        // Setup project
        vm.prank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "reputation-gaming-project", 100 ether, 0, 2, 500, "test");

        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();

        // Setup contributor
        vm.prank(admin);
        trust.validateSkill(contributor, "test");

        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("sub"));
        vm.stopPrank();

        // Setup two validators with different reputations
        // Validator 1: High reputation, will fail to reveal
        _setupValidator(validator1, 1000 ether);
        vm.startPrank(admin);
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 9000); // High reputation
        vm.stopPrank();

        // Validator 2: Lower reputation, will reveal correctly
        _setupValidator(validator2, 1000 ether);
        vm.startPrank(admin);
        trust.updateReputation(validator2, VALIDATOR_ROLE, true, 6000); // Lower reputation
        vm.stopPrank();

        uint256 rep1Before = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        uint256 rep2Before = trust.getTrustScore(validator2, VALIDATOR_ROLE);

        console.log("=== CONSENSUS WEIGHTING IMPACT ===");
        console.log("Validator 1 reputation (will fail):", rep1Before);
        console.log("Validator 2 reputation (will succeed):", rep2Before);

        // Both validators commit
        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v1ClaimId, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt1")))
        );
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v2ClaimId, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt2")))
        );
        vm.stopPrank();

        // Validator 2 reveals correctly
        vm.prank(validator2);
        oracle.revealValidation(PROJECT_ID, 0, 8000, keccak256("salt2"));

        // Warp past reveal deadline (minimal time for decay)
        vm.warp(block.timestamp + 4 days);

        // Get reputation before cancel (accounting for any decay)
        uint256 rep1BeforeCancel = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        uint256 rep2BeforeCancel = trust.getTrustScore(validator2, VALIDATOR_ROLE);

        // Validator 1's commitment expires - cancel it
        vm.prank(validator1);
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);

        // Get reputation immediately after cancel (no additional time for decay)
        uint256 rep1After = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        uint256 rep2After = trust.getTrustScore(validator2, VALIDATOR_ROLE);

        console.log("After cancel:");
        console.log("Validator 1 reputation before:", rep1BeforeCancel);
        console.log("Validator 1 reputation after:", rep1After);
        console.log("Validator 2 reputation:", rep2After);

        // FIXED: Validator 1's reputation should decrease due to explicit penalty
        // This prevents them from maintaining high reputation despite failures
        assertTrue(rep1After < rep1BeforeCancel, "Validator 1 reputation should decrease (fixed)");
        assertEq(rep1BeforeCancel - rep1After, 100, "Should decrease by SLASH_DECREASE (100 bps)");

        // Validator 2's reputation should remain unchanged (no action taken yet)
        assertEq(rep2After, rep2BeforeCancel, "Validator 2 reputation unchanged");

        // Impact mitigated: Validator 1's reputation now accurately reflects their failure
        // This prevents disproportionate influence in future consensus calculations
        // Reputation is used in _prepareValidationInputs() for weighted consensus calculations
        // After the fix, reputation scores accurately reflect validator reliability
    }

    /**
     * @notice Test comparing both functions side-by-side
     * @dev Shows the inconsistency between cancelExpiredCommitment and cancelExpiredValidationClaim
     *      Both represent similar failure scenarios but have different reputation treatment
     */
    function test_InconsistencyBetweenCancelFunctions() public {
        // Setup project
        vm.prank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "reputation-gaming-project", 100 ether, 0, 2, 500, "test");

        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();

        // Setup two validators with same initial reputation
        _setupValidator(validator1, 1000 ether);
        _setupValidator(validator2, 1000 ether);

        vm.startPrank(admin);
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 8000);
        trust.updateReputation(validator2, VALIDATOR_ROLE, true, 8000);
        vm.stopPrank();

        uint256 rep1Initial = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        uint256 rep2Initial = trust.getTrustScore(validator2, VALIDATOR_ROLE);
        assertEq(rep1Initial, rep2Initial, "Both should start with same reputation");

        // Validator 1: Uses cancelExpiredCommitment (missing reputation update)
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("sub"));
        vm.stopPrank();

        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v1ClaimId, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), keccak256("salt1")))
        );
        vm.stopPrank();

        vm.warp(block.timestamp + 4 days);
        uint256 rep1BeforeCancel = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        vm.prank(validator1);
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);
        uint256 rep1After = trust.getTrustScore(validator1, VALIDATOR_ROLE);

        // Validator 2: Uses cancelExpiredValidationClaim (has reputation update)
        vm.startPrank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(PROJECT_ID);
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days); // Past claim deadline
        uint256 rep2BeforeCancel = trust.getTrustScore(validator2, VALIDATOR_ROLE);
        vm.prank(validator2);
        oracle.cancelExpiredValidationClaim(PROJECT_ID, v2ClaimId);
        uint256 rep2After = trust.getTrustScore(validator2, VALIDATOR_ROLE);

        console.log("=== INCONSISTENCY TEST ===");
        console.log("Validator 1 (cancelExpiredCommitment - commit but no reveal):");
        console.log("  Before cancel:", rep1BeforeCancel);
        console.log("  After cancel:", rep1After);
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'int256' is safe because we're calculating a difference for logging purposes
        console.log("  Change:", int256(rep1After) - int256(rep1BeforeCancel));
        console.log("Validator 2 (cancelExpiredValidationClaim - claim but no commit):");
        console.log("  Before cancel:", rep2BeforeCancel);
        console.log("  After cancel:", rep2After);
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'int256' is safe because we're calculating a difference for logging purposes
        console.log("  Change:", int256(rep2After) - int256(rep2BeforeCancel));
        console.log("Expected penalty (SLASH_DECREASE): 100 bps = 1%");

        // FIXED: Both functions now apply consistent reputation penalties
        // Validator 1: Explicit penalty of 100 bps (1%) for failing to reveal
        // Validator 2: Explicit penalty of 100 bps (1%) for failing to commit

        // Both should decrease by the same amount (SLASH_DECREASE = 100 bps)
        assertTrue(rep1After < rep1BeforeCancel, "Validator 1 reputation should decrease (fixed)");
        assertTrue(rep2After < rep2BeforeCancel, "Validator 2 reputation should decrease (correct behavior)");

        // Both should decrease by the same amount
        uint256 rep1Decrease = rep1BeforeCancel - rep1After;
        uint256 rep2Decrease = rep2BeforeCancel - rep2After;
        assertEq(rep1Decrease, rep2Decrease, "Both should decrease by same amount (consistent treatment)");
        assertEq(rep1Decrease, 100, "Both should decrease by SLASH_DECREASE (100 bps)");
    }

    function _setupValidator(address v, uint256 amount) internal {
        _setupUser(v, amount);
        vm.startPrank(admin);
        trust.grantRole(UPDATER_ROLE, admin);
        trust.validateSkill(v, "test");
        vm.stopPrank();

        vm.prank(v);
        oracle.setValidatorCapacity(amount);
    }
}
