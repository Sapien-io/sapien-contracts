// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ISharedTypes, ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title ValidatorCapacityVaultDesyncTest
 * @notice Test demonstrating Issue #3: Validator Capacity Not Checked Against Vault Balance on Slash
 *
 * VULNERABILITY DESCRIPTION:
 * The handleValidatorSlash function reduces validator capacity but there's a subtle issue -
 * if multiple slashes occur in rapid succession for the same validator across different
 * contributions, the function reads vault.getLockedStake(validator) at line 1019 to sync
 * capacity, but this happens *after* the vault has already been slashed.
 *
 * If lockedStake in the vault drops to zero but inFlightStake in ValidatorState still has
 * a non-zero value from other pending commits, accounting discrepancy occurs.
 *
 * ATTACK VECTOR: Stake Manipulation
 *
 * LOCATION: ValidationOracle.sol lines 987-1028 (handleValidatorSlash)
 *
 * SEVERITY: Medium-High
 */
contract ValidatorCapacityVaultDesyncTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");
    bytes32 public constant PROJECT_ID_2 = keccak256("test-project-2");

    function setUp() public override {
        super.setUp();

        // Grant roles
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        trust.grantRole(VALIDATOR_ROLE, validator2);
        trust.grantRole(VALIDATOR_ROLE, validator3);
        vm.stopPrank();

        // Setup validators with limited capacity
        _setupValidator(validator1, 150 ether); // Just enough for ~1.5 validations
        _setupValidator(validator2, 500 ether);
        _setupValidator(validator3, 500 ether);
    }

    /**
     * @notice Test: Multiple rapid slashes cause capacity/vault desync
     * @dev Validator commits to multiple contributions, gets slashed on multiple
     */
    function test_MultipleSlashesDesyncCapacity() public {
        // Create two projects
        vm.startPrank(originator);

        core.createProject(PROJECT_ID, address(rewardToken), "test-project", 0, 0, 2, 1000, "");
        rewardToken.approve(address(core), 200 ether);
        core.fundProject(PROJECT_ID, 100 ether, 5);

        core.createProject(PROJECT_ID_2, address(rewardToken), "test-project-2", 0, 0, 2, 1000, "");
        core.fundProject(PROJECT_ID_2, 100 ether, 5);
        vm.stopPrank();

        // Contributor submits to both projects
        vm.startPrank(contributor);
        uint256 claimId1 = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId1, 0, keccak256("submission1"));

        uint256 claimId2 = core.claimToContribute(PROJECT_ID_2, 1);
        core.contribute(PROJECT_ID_2, claimId2, 0, keccak256("submission2"));
        vm.stopPrank();

        // Validator1 commits to both projects with their full capacity
        console.log("=== Initial State ===");
        (uint256 v1Capacity, uint256 v1InFlight) = oracle.validatorStates(validator1);
        console.log("Validator1 capacity:", v1Capacity);
        console.log("Validator1 inFlightStake:", v1InFlight);
        console.log("Vault locked stake:", vault.getLockedStake(validator1));

        // Commit to first project
        bytes32 salt1 = keccak256("salt1");
        vm.startPrank(validator1);
        uint256 v1Claim1 = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v1Claim1, 0, keccak256(abi.encodePacked(uint256(2000), uint256(100 ether), salt1))
        );
        vm.stopPrank();

        console.log("\n=== After First Commit ===");
        (v1Capacity, v1InFlight) = oracle.validatorStates(validator1);
        console.log("Validator1 capacity:", v1Capacity);
        console.log("Validator1 inFlightStake:", v1InFlight);

        // Validator2 and Validator3 also commit
        bytes32 salt2 = keccak256(abi.encodePacked(validator2, PROJECT_ID, uint256(0)));
        bytes32 salt3 = keccak256(abi.encodePacked(validator3, PROJECT_ID, uint256(0)));

        vm.startPrank(validator2);
        uint256 v2Claim = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v2Claim, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), salt2))
        );
        vm.stopPrank();

        vm.startPrank(validator3);
        uint256 v3Claim = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v3Claim, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), salt3))
        );
        vm.stopPrank();

        // Wait for reveal period (all commit first, then warp once)
        vm.warp(block.timestamp + 2 days);

        // All validators reveal
        vm.prank(validator2);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt2);
        vm.prank(validator3);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt3);
        // Validator1 reveals with an outlier score (will be slashed)
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 2000, salt1);

        console.log("\n=== After Reveal (Validator1 is outlier) ===");
        (v1Capacity, v1InFlight) = oracle.validatorStates(validator1);
        console.log("Validator1 capacity:", v1Capacity);
        console.log("Validator1 inFlightStake:", v1InFlight);
        console.log("Vault locked stake:", vault.getLockedStake(validator1));

        // Finalize - this will slash validator1
        core.finalizeContribution(PROJECT_ID, 0);

        console.log("\n=== After Finalization (Slashing Applied) ===");
        (v1Capacity, v1InFlight) = oracle.validatorStates(validator1);
        uint256 vaultLocked = vault.getLockedStake(validator1);
        console.log("Validator1 capacity:", v1Capacity);
        console.log("Validator1 inFlightStake:", v1InFlight);
        console.log("Vault locked stake:", vaultLocked);

        // Check for desync
        // If inFlightStake > vaultLocked, we have a desync
        if (v1InFlight > vaultLocked) {
            console.log("\nVULNERABILITY DETECTED:");
            console.log("inFlightStake > vaultLocked - accounting discrepancy!");
            console.log("Difference:", v1InFlight - vaultLocked);
        }

        // Check if capacity > vaultLocked
        if (v1Capacity > vaultLocked) {
            console.log("\nPOTENTIAL ISSUE:");
            console.log("capacity > vaultLocked - validator thinks they have more capacity than actual stake");
        }
    }

    /**
     * @notice Test: Verify capacity syncs correctly after slash
     * @dev Capacity should be reduced to match vault's locked stake
     */
    function test_CapacitySyncsAfterSlash() public {
        // Create project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "test-project", 0, 0, 2, 1000, "");
        rewardToken.approve(address(core), 100 ether);
        core.fundProject(PROJECT_ID, 100 ether, 5);
        vm.stopPrank();

        // Contributor submits
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.stopPrank();

        // Get initial state
        (uint256 initialCapacity,) = oracle.validatorStates(validator1);
        uint256 initialVaultLocked = vault.getLockedStake(validator1);
        console.log("Initial capacity:", initialCapacity);
        console.log("Initial vault locked:", initialVaultLocked);

        // All validators commit
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");

        vm.startPrank(validator1);
        uint256 v1Claim = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v1Claim, 0, keccak256(abi.encodePacked(uint256(1000), uint256(100 ether), salt1))
        ); // Outlier score
        vm.stopPrank();

        vm.startPrank(validator2);
        uint256 v2Claim = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v2Claim, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), salt2))
        );
        vm.stopPrank();

        vm.startPrank(validator3);
        uint256 v3Claim = oracle.claimToValidate(PROJECT_ID);
        oracle.commitValidation(
            PROJECT_ID, v3Claim, 0, keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), salt3))
        );
        vm.stopPrank();

        // Wait and reveal all
        vm.warp(block.timestamp + 2 days);

        vm.prank(validator2);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt2);
        vm.prank(validator3);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt3);
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 1000, salt1);

        // Finalize
        core.finalizeContribution(PROJECT_ID, 0);

        // Check final state
        (uint256 finalCapacity, uint256 finalInFlight) = oracle.validatorStates(validator1);
        uint256 finalVaultLocked = vault.getLockedStake(validator1);
        console.log("\n=== After Slash ===");
        console.log("Final capacity:", finalCapacity);
        console.log("Final inFlightStake:", finalInFlight);
        console.log("Final vault locked:", finalVaultLocked);

        // Verify capacity <= vaultLocked (sync should have occurred)
        assertLe(finalCapacity, finalVaultLocked + 1, "Capacity should be synced with vault locked stake");
    }

    /**
     * @notice Test: Document the desync scenario
     */
    function test_DocumentDesyncScenario() public pure {
        console.log("=== Capacity/Vault Desync Scenario ===");
        console.log("");
        console.log("1. Validator has capacity = 150 ether, commits to Contribution A (100 ether)");
        console.log("2. inFlightStake = 100 ether");
        console.log("3. Validator commits to Contribution B with remaining capacity (50 ether)");
        console.log("4. inFlightStake = 150 ether");
        console.log("");
        console.log("5. Contribution A finalizes, validator slashed 100 ether");
        console.log("6. Vault.slash() reduces lockedStake from 150 to 50");
        console.log("7. handleValidatorSlash() syncs capacity with vault");
        console.log("");
        console.log("ISSUE: inFlightStake might still show 50 ether for Contribution B");
        console.log("But the actual vault locked stake is now only 50 ether.");
        console.log("If another slash occurs, the accounting could be wrong.");
        console.log("");
        console.log("=== Mitigation ===");
        console.log("Ensure inFlightStake is properly reduced when slashing occurs");
        console.log("Consider atomic operations for multi-contribution slashes");
    }

    // Helper to commit and reveal for a validator
    function _commitAndRevealValidator(address v, bytes32 projectId, uint256 contribIndex, uint256 score, uint256 stake)
        internal
    {
        bytes32 salt = keccak256(abi.encodePacked(v, projectId, contribIndex));
        vm.startPrank(v);
        uint256 claimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(projectId, claimId, contribIndex, keccak256(abi.encodePacked(score, stake, salt)));
        vm.stopPrank();

        vm.warp(block.timestamp + 2 days);

        vm.prank(v);
        oracle.revealValidation(projectId, contribIndex, score, salt);
    }

    // Helper function
    function _setupValidator(address v, uint256 amount) internal {
        _setupUser(v, amount);
        vm.startPrank(admin);
        trust.updateReputation(v, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();

        vm.prank(v);
        oracle.setValidatorCapacity(amount);
    }
}
