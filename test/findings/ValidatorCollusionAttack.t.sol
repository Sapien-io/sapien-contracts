// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title ValidatorCollusionAttackTest
 * @notice Test demonstrating Issue #5: Missing Sybil Protection for Validator Collusion
 *
 * VULNERABILITY DESCRIPTION:
 * The protocol checks that originator and contributor can't validate, but there's no
 * enforcement preventing:
 * 1. A contributor from controlling multiple validator addresses
 * 2. Validators from colluding to approve/reject contributions
 * 3. Flash loan staking to temporarily inflate validator weight
 *
 * The HybridConsensus cap at 30% helps but doesn't prevent 4+ colluding validators
 * from controlling consensus.
 *
 * ATTACK VECTOR: Consensus Manipulation / Collusion
 *
 * LOCATION: ValidationOracle.sol and HybridConsensus.sol
 *
 * SEVERITY: Medium
 */
contract ValidatorCollusionAttackTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("collusion-test");

    // Collusion ring
    address public colluder1 = makeAddr("colluder1");
    address public colluder2 = makeAddr("colluder2");
    address public colluder3 = makeAddr("colluder3");
    address public colluder4 = makeAddr("colluder4");
    address public colluder5 = makeAddr("colluder5");

    // Honest validator
    address public honestValidator = makeAddr("honestValidator");

    function setUp() public override {
        super.setUp();

        // Grant roles
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);

        // Setup collusion ring
        trust.grantRole(VALIDATOR_ROLE, colluder1);
        trust.grantRole(VALIDATOR_ROLE, colluder2);
        trust.grantRole(VALIDATOR_ROLE, colluder3);
        trust.grantRole(VALIDATOR_ROLE, colluder4);
        trust.grantRole(VALIDATOR_ROLE, colluder5);
        trust.grantRole(VALIDATOR_ROLE, honestValidator);
        vm.stopPrank();

        // Setup all validators with equal stake
        _setupValidator(colluder1, 100 ether);
        _setupValidator(colluder2, 100 ether);
        _setupValidator(colluder3, 100 ether);
        _setupValidator(colluder4, 100 ether);
        _setupValidator(colluder5, 100 ether);
        _setupValidator(honestValidator, 100 ether);
    }

    /**
     * @notice Test: Collusion ring approves bad contribution
     * @dev 5 colluding validators vote to approve, 1 honest validator dissents
     */
    function test_CollusionRingApprovesBadWork() public {
        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "collusion-test", 0, 0, 3, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Contributor submits (assume this is poor quality work)
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("poor-quality-work"));
        vm.stopPrank();

        console.log("=== Collusion Attack: Approve Bad Work ===");
        console.log("Scenario: Poor quality work submitted");
        console.log("Colluding validators: 5 (voting 9500 = excellent)");
        console.log("Honest validator: 1 (voting 2000 = poor)");

        // Colluders vote high score
        uint256 collusionScore = 9500;
        _commitAndReveal(colluder1, PROJECT_ID, 0, collusionScore);
        _commitAndReveal(colluder2, PROJECT_ID, 0, collusionScore);
        _commitAndReveal(colluder3, PROJECT_ID, 0, collusionScore);
        _commitAndReveal(colluder4, PROJECT_ID, 0, collusionScore);
        _commitAndReveal(colluder5, PROJECT_ID, 0, collusionScore);

        // Honest validator votes low (this is an outlier now!)
        _commitAndReveal(honestValidator, PROJECT_ID, 0, 2000);

        // Finalize
        core.finalizeContribution(PROJECT_ID, 0);

        // Check result
        uint256 contributionStatus = uint256(core.getContribution(PROJECT_ID, 0).status);
        console.log("\n=== Result ===");
        console.log("Contribution status (1=Pending, 2=Accepted, 3=Rejected):", contributionStatus);

        // If accepted, collusion succeeded
        if (contributionStatus == 2) {
            console.log("VULNERABILITY CONFIRMED:");
            console.log("- Poor quality work was ACCEPTED due to collusion");
            console.log("- Honest validator was treated as outlier");
            console.log("- Contributor receives full reward for poor work");
        }

        // Check if honest validator was slashed
        console.log("\n=== Honest Validator Impact ===");
        (uint256 honestCapacity,) = oracle.validatorStates(honestValidator);
        console.log("Honest validator remaining capacity:", honestCapacity);
        if (honestCapacity < 100 ether) {
            console.log("Honest validator was SLASHED for being 'outlier'!");
        }
    }

    /**
     * @notice Test: Collusion ring rejects good contribution
     * @dev 5 colluding validators vote to reject, 1 honest validator approves
     */
    function test_CollusionRingRejectsGoodWork() public {
        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "collusion-test", 0, 0, 3, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Contributor submits (assume this is high quality work)
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("high-quality-work"));
        vm.stopPrank();

        console.log("=== Collusion Attack: Reject Good Work ===");
        console.log("Scenario: High quality work submitted");
        console.log("Colluding validators: 5 (voting 1000 = terrible)");
        console.log("Honest validator: 1 (voting 9000 = excellent)");

        // Colluders vote low score
        uint256 collusionScore = 1000;
        _commitAndReveal(colluder1, PROJECT_ID, 0, collusionScore);
        _commitAndReveal(colluder2, PROJECT_ID, 0, collusionScore);
        _commitAndReveal(colluder3, PROJECT_ID, 0, collusionScore);
        _commitAndReveal(colluder4, PROJECT_ID, 0, collusionScore);
        _commitAndReveal(colluder5, PROJECT_ID, 0, collusionScore);

        // Honest validator votes high
        _commitAndReveal(honestValidator, PROJECT_ID, 0, 9000);

        // Finalize
        core.finalizeContribution(PROJECT_ID, 0);

        // Check result
        uint256 contributionStatus = uint256(core.getContribution(PROJECT_ID, 0).status);
        console.log("\n=== Result ===");
        console.log("Contribution status (1=Pending, 2=Accepted, 3=Rejected):", contributionStatus);

        if (contributionStatus == 3) {
            console.log("VULNERABILITY CONFIRMED:");
            console.log("- High quality work was REJECTED due to collusion");
            console.log("- Contributor loses work and receives no reward");
            console.log("- Colluders may have been competing contributors");
        }
    }

    /**
     * @notice Test: 30% cap protection in HybridConsensus
     * @dev Even with high stake, single validator capped at 30% weight
     */
    function test_ThirtyPercentCapProtection() public {
        // Create project with HybridConsensus (if available)
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "collusion-test", 0, 0, 3, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 10);
        vm.stopPrank();

        // Whale validator with 10x stake
        address whale = makeAddr("whale");
        vm.prank(admin);
        trust.grantRole(VALIDATOR_ROLE, whale);
        _setupValidator(whale, 1000 ether); // 10x normal stake

        // Contributor submits
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        console.log("=== 30% Cap Protection Test ===");
        console.log("Whale stake: 1000 ether");
        console.log("Normal validator stake: 100 ether");

        // Whale votes high
        _commitAndReveal(whale, PROJECT_ID, 0, 9000);

        // Normal validators vote low
        _commitAndReveal(colluder1, PROJECT_ID, 0, 3000);
        _commitAndReveal(colluder2, PROJECT_ID, 0, 3000);
        _commitAndReveal(colluder3, PROJECT_ID, 0, 3000);

        // Finalize
        core.finalizeContribution(PROJECT_ID, 0);

        uint256 status = uint256(core.getContribution(PROJECT_ID, 0).status);
        console.log("Contribution status:", status);

        // With 30% cap, whale's 10x stake is limited
        // 3 normal validators should still influence outcome significantly
        console.log("\nIf rejected: 30% cap is working - whale can't dominate");
        console.log("If accepted: 30% cap may need review");
    }

    /**
     * @notice Test: Document Sybil attack vectors
     */
    function test_DocumentSybilVectors() public pure {
        console.log("=== Sybil Attack Vectors ===");
        console.log("");
        console.log("1. VALIDATOR SOCK PUPPETS:");
        console.log("   - Attacker creates multiple validator addresses");
        console.log("   - Splits stake across addresses to bypass 30% cap");
        console.log("   - All addresses vote together");
        console.log("");
        console.log("2. CONTRIBUTOR-VALIDATOR COLLUSION:");
        console.log("   - Contributor controls validator addresses");
        console.log("   - Uses different wallets to bypass role separation");
        console.log("   - Self-approves their own work");
        console.log("");
        console.log("3. FLASH LOAN STAKE INFLATION:");
        console.log("   - Attacker flash loans tokens");
        console.log("   - Temporarily increases validator stake");
        console.log("   - Commits validation with inflated weight");
        console.log("   - Returns loan (but commitment is locked)");
        console.log("");
        console.log("=== Mitigations ===");
        console.log("1. Require validators to have long-term stake history");
        console.log("2. Implement stake lockup periods before validation");
        console.log("3. Add reputation-based weight (built over time)");
        console.log("4. Require minimum validator diversity (unique IPs, KYC)");
        console.log("5. Implement dispute resolution for contested outcomes");
    }

    // Helper to commit and reveal
    function _commitAndReveal(address v, bytes32 projectId, uint256 contribIndex, uint256 score) internal {
        bytes32 salt = keccak256(abi.encodePacked(v, score));
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
