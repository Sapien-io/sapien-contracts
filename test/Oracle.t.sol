// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "./BaseTest.t.sol";
import {IValidationOracle} from "../src/interface/IValidationOracle.sol";
import {
    ISharedTypes,
    SAPIEN_CORE_ROLE,
    VALIDATOR_ROLE,
    UNAUTHORIZED_MISSING_CORE_ROLE
} from "../src/interface/ISharedTypes.sol";

contract OracleTest is BaseTest {
    // forge-lint: disable-next-line(mixed-case-variable)
    // PROJECT_ID is a test constant used throughout the test file
    bytes32 public PROJECT_ID;

    function setUp() public override {
        super.setUp();
        PROJECT_ID = keccak256(abi.encodePacked("oracle-project"));
        vm.prank(admin);
        oracle.grantRole(SAPIEN_CORE_ROLE, admin);

        vm.prank(admin);
        oracle.registerProject(PROJECT_ID, 10, "", originator);
    }

    function testSybilProtection() public {
        // Originator cannot validate
        vm.startPrank(originator);
        _stakeForOracle(originator, 1000 ether);
        vm.expectRevert();
        oracle.claimToValidate(PROJECT_ID);
        vm.stopPrank();

        // Contributor cannot validate
        vm.prank(admin);
        oracle.setContributionContributor(PROJECT_ID, 0, contributor);

        vm.startPrank(contributor);
        _stakeForOracle(contributor, 1000 ether);
        vm.expectRevert();
        oracle.claimToValidate(PROJECT_ID);
        vm.stopPrank();
    }

    function testRevealDeadline() public {
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        _setValidatorCapacity(validator1, 1000 ether);
        vm.prank(validator1);
        oracle.claimToValidate(PROJECT_ID);

        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;
        bytes32 h = keccak256(abi.encodePacked(uint256(8000), stake, salt));

        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, 0, 0, h);

        // Try to cancel too early
        vm.expectRevert();
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);

        // Advance time
        vm.warp(block.timestamp + 4 days); // Default reveal deadline is 3 days

        uint256 balanceBefore = vault.getStake(validator1);
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);
        uint256 balanceAfter = vault.getStake(validator1);

        // Should be slashed
        assertTrue(balanceAfter < balanceBefore);
    }

    function testOracleInitializeReverts() public {
        vm.expectRevert(InvalidInitialization.selector);
        oracle.initialize(address(trust), address(vault), "SqrtStake", admin);
    }

    function testClaimToValidateEdgeCases() public {
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        // Missing skill
        vm.prank(admin);
        oracle.setProjectRequiredSkill(PROJECT_ID, "Solidity");

        _setValidatorCapacity(validator1, 1000 ether);
        vm.prank(validator1);
        vm.expectRevert(); // MissingRequiredSkill
        oracle.claimToValidate(PROJECT_ID);

        // Capacity reached - set numberOfValidations to 1 and enqueue again
        vm.startPrank(admin);
        oracle.setProjectRequiredSkill(PROJECT_ID, "");
        oracle.setProjectNumberOfValidations(PROJECT_ID, 1);
        // Clear queue by claiming all existing items first, then enqueue with new max
        // Actually, let's use a fresh project for this test
        bytes32 projectId2 = keccak256(abi.encodePacked("project2"));
        oracle.registerProject(projectId2, 1, "", originator);
        oracle.enqueueValidation(projectId2, 0, block.timestamp);
        vm.stopPrank();

        vm.prank(validator1);
        oracle.claimToValidate(projectId2);

        _setValidatorCapacity(validator2, 1000 ether);
        vm.prank(validator2);
        vm.expectRevert(); // AllValidationsClaimed - queue is empty
        oracle.claimToValidate(projectId2);

        // Duplicate claim - validator1 already claimed the only slot
        vm.prank(validator1);
        vm.expectRevert(); // AllValidationsClaimed - no more items in queue
        oracle.claimToValidate(projectId2);
    }

    function testCancelClaim() public {
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        _setValidatorCapacity(validator1, 1000 ether);
        vm.prank(validator1);
        oracle.claimToValidate(PROJECT_ID);

        // Cancel by self
        vm.prank(validator1);
        oracle.cancelExpiredValidationClaim(PROJECT_ID, 0);

        // Re-claim and let expire
        vm.prank(validator1);
        uint256 newClaimId = oracle.claimToValidate(PROJECT_ID);
        vm.warp(block.timestamp + 2 hours); // CLAIM_DURATION is 1 hour

        // Cancel the new expired claim
        oracle.cancelExpiredValidationClaim(PROJECT_ID, newClaimId);
    }

    function testCommitRevealEdgeCases() public {
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        _setValidatorCapacity(validator1, 1000 ether);
        vm.prank(validator1);
        oracle.claimToValidate(PROJECT_ID);

        // Commit before deadline expires
        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;
        bytes32 h = keccak256(abi.encodePacked(uint256(8000), stake, salt));
        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, 0, 0, h);

        // Now warp past deadline - commit should fail
        vm.warp(block.timestamp + 2 hours);
        vm.prank(validator1);
        vm.expectRevert(); // ClaimAlreadyExpired
        oracle.commitValidation(PROJECT_ID, 0, 0, keccak256("h"));

        bytes32 wrongSalt = keccak256("wrong-salt");

        vm.prank(validator1);
        vm.expectRevert(); // InvalidCommitHash
        oracle.revealValidation(PROJECT_ID, 0, 7000, wrongSalt);

        vm.prank(validator2);
        vm.expectRevert(); // NoUnrevealedCommit
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt);
    }

    function testAdminAndRegistryFunctions() public {
        vm.startPrank(admin);
        oracle.registerAlgorithm("NewAlgo", address(0x123));
        assertEq(oracle.algorithms(keccak256("NewAlgo")), address(0x123));

        oracle.setProjectAlgorithm(PROJECT_ID, "NewAlgo");
        oracle.setProjectRevealDeadline(PROJECT_ID, 5 days);
        oracle.setProjectOriginator(PROJECT_ID, validator3);
        oracle.setRevealDeadline(7 days);
        vm.stopPrank();
    }

    function testGetConsensusNotReady() public {
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        // Less than numberOfValidations
        IValidationOracle.ConsensusReport memory report = oracle.getConsensus(PROJECT_ID, 0);
        assertFalse(report.isReady);

        // Commits not revealed
        _setValidatorCapacity(validator1, 1000 ether);
        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);
        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, claimId, 0, keccak256("h"));

        report = oracle.getConsensus(PROJECT_ID, 0);
        assertFalse(report.isReady);

        // Algorithm not found
        vm.prank(admin);
        oracle.setProjectAlgorithm(PROJECT_ID, "NonExistent");
        vm.expectRevert();
        oracle.getAlgorithm(PROJECT_ID);
    }

    function testValidatorCapacity() public {
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        // Validator must set capacity before claiming
        vm.prank(validator1);
        vm.expectRevert(); // Unauthorized - insufficient capacity
        oracle.claimToValidate(PROJECT_ID);

        // Set capacity and claim
        _setValidatorCapacity(validator1, 1000 ether);
        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);

        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;
        bytes32 h = keccak256(abi.encodePacked(uint256(8000), stake, salt));

        // Now can commit (capacity is set)
        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, claimId, 0, h);

        // Verify capacity is being used
        uint256 availableCapacity = oracle.getAvailableCapacity(validator1);
        assertTrue(availableCapacity < 1000 ether); // Some capacity is in-flight

        // Reveal to release in-flight stake
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt);

        // Capacity should be available again
        uint256 availableAfter = oracle.getAvailableCapacity(validator1);
        assertEq(availableAfter, 1000 ether); // All capacity available again
    }

    function testEnqueueValidation() public {
        // Test that enqueueValidation adds items to the queue
        uint256 contributionIndex = 0;
        uint256 submittedAt = block.timestamp;

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, contributionIndex, submittedAt);

        // Should have numberOfValidations (10) items in queue
        uint256 pendingCount = oracle.getPendingValidationCount(PROJECT_ID);
        assertEq(pendingCount, 10);

        // Test unauthorized access
        vm.prank(validator1);
        vm.expectRevert();
        oracle.enqueueValidation(PROJECT_ID, 1, block.timestamp);

        // Test with custom numberOfValidations
        vm.prank(admin);
        oracle.setProjectNumberOfValidations(PROJECT_ID, 5);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 1, block.timestamp);

        uint256 newPendingCount = oracle.getPendingValidationCount(PROJECT_ID);
        assertEq(newPendingCount, 15); // 10 + 5
    }

    function testGetPendingValidationCount() public {
        assertEq(oracle.getPendingValidationCount(PROJECT_ID), 0);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        assertEq(oracle.getPendingValidationCount(PROJECT_ID), 10);

        // Claim some validations (must claim one at a time per Option B)
        _setValidatorCapacity(validator1, 1000 ether);
        vm.prank(validator1);
        oracle.claimToValidate(PROJECT_ID);
        vm.prank(validator1);
        oracle.claimToValidate(PROJECT_ID);
        vm.prank(validator1);
        oracle.claimToValidate(PROJECT_ID);

        assertEq(oracle.getPendingValidationCount(PROJECT_ID), 7);
    }

    function testClaimToValidateOnlyAcceptsQuantityOne() public {
        _setValidatorCapacity(validator1, 1000 ether);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        // Should succeed - claims exactly one slot (Option B: parameter removed)
        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);

        // Verify claim was created with quantity = 1
        (address validator, uint256 quantity,,,,,) = oracle.validationClaims(PROJECT_ID, claimId);
        assertEq(validator, validator1);
        assertEq(quantity, 1); // Always 1 per Option B
    }

    function testIsValidatorAssigned() public {
        _setValidatorCapacity(validator1, 1000 ether);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        vm.prank(validator1);
        oracle.claimToValidate(PROJECT_ID);

        assertTrue(oracle.isValidatorAssigned(PROJECT_ID, 0, validator1));
        assertFalse(oracle.isValidatorAssigned(PROJECT_ID, 0, validator2));

        // After deadline expires
        vm.warp(block.timestamp + 2 hours);
        assertFalse(oracle.isValidatorAssigned(PROJECT_ID, 0, validator1));
    }

    function testBatchCommitValidations() public {
        _setValidatorCapacity(validator1, 1000 ether);

        // Set numberOfValidations to 3 to work with per-validator claim limit of 3
        vm.prank(admin);
        oracle.setProjectNumberOfValidations(PROJECT_ID, 3);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 1, block.timestamp);

        // Queue: [0,0,0,1,1,1] - 3 slots per contribution
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        uint256 stake = 100 ether;
        bytes32 h1 = keccak256(abi.encodePacked(uint256(8000), stake, salt1));
        bytes32 h2 = keccak256(abi.encodePacked(uint256(8500), stake, salt2));

        vm.startPrank(validator1);
        // Claim 3 slots (all from index 0), hitting the per-validator active claim limit
        uint256 claimId0 = oracle.claimToValidate(PROJECT_ID);
        oracle.claimToValidate(PROJECT_ID);
        oracle.claimToValidate(PROJECT_ID);

        // Commit to index 0 (fulfills claimId0, freeing one active claim slot)
        oracle.commitValidation(PROJECT_ID, claimId0, 0, h1);

        // Now can claim again (active claims dropped from 3 to 2)
        uint256 claimId1 = oracle.claimToValidate(PROJECT_ID); // gets index 1

        // Commit to index 1
        oracle.commitValidation(PROJECT_ID, claimId1, 1, h2);
        vm.stopPrank();

        // Verify commits were recorded
        IValidationOracle.ConsensusReport memory report = oracle.getConsensus(PROJECT_ID, 0);
        assertFalse(report.isReady); // Not revealed yet
    }

    function testBatchRevealValidations() public {
        _setValidatorCapacity(validator1, 1000 ether);

        // Set numberOfValidations to 3 to work with per-validator claim limit of 3
        vm.prank(admin);
        oracle.setProjectNumberOfValidations(PROJECT_ID, 3);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 1, block.timestamp);

        // Queue: [0,0,0,1,1,1] - 3 slots per contribution
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        uint256 stake = 100 ether;
        bytes32 h1 = keccak256(abi.encodePacked(uint256(8000), stake, salt1));
        bytes32 h2 = keccak256(abi.encodePacked(uint256(8500), stake, salt2));

        vm.startPrank(validator1);
        // Claim 3 slots (all from index 0), hitting the per-validator active claim limit
        uint256 claimId0 = oracle.claimToValidate(PROJECT_ID);
        oracle.claimToValidate(PROJECT_ID);
        oracle.claimToValidate(PROJECT_ID);

        // Commit to index 0 (fulfills claimId0, freeing one active claim slot)
        oracle.commitValidation(PROJECT_ID, claimId0, 0, h1);

        // Now can claim again (active claims dropped from 3 to 2)
        uint256 claimId1 = oracle.claimToValidate(PROJECT_ID); // gets index 1

        // Commit to index 1
        oracle.commitValidation(PROJECT_ID, claimId1, 1, h2);
        vm.stopPrank();

        // Reveal both using batch reveal
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        uint256[] memory scores = new uint256[](2);
        scores[0] = 8000;
        scores[1] = 8500;
        bytes32[] memory salts = new bytes32[](2);
        salts[0] = salt1;
        salts[1] = salt2;

        vm.prank(validator1);
        oracle.batchRevealValidations(PROJECT_ID, indices, scores, salts);

        // Verify reveals
        IValidationOracle.Validation[] memory validations0 = oracle.getValidations(PROJECT_ID, 0);
        IValidationOracle.Validation[] memory validations1 = oracle.getValidations(PROJECT_ID, 1);

        assertEq(validations0.length, 1);
        assertEq(validations0[0].score, 8000);
        assertEq(validations1.length, 1);
        assertEq(validations1[0].score, 8500);

        // Test mismatched array lengths
        uint256[] memory indicesShort = new uint256[](1);
        indicesShort[0] = 0;
        vm.prank(validator1);
        vm.expectRevert();
        oracle.batchRevealValidations(PROJECT_ID, indicesShort, scores, salts);
    }

    function testGetValidations() public {
        _setValidatorCapacity(validator1, 1000 ether);
        _setValidatorCapacity(validator2, 1000 ether);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        vm.prank(validator1);
        uint256 claimId1 = oracle.claimToValidate(PROJECT_ID);
        vm.prank(validator2);
        uint256 claimId2 = oracle.claimToValidate(PROJECT_ID);

        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        uint256 stake = 100 ether;

        bytes32 h1 = keccak256(abi.encodePacked(uint256(8000), stake, salt1));
        bytes32 h2 = keccak256(abi.encodePacked(uint256(9000), stake, salt2));

        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, claimId1, 0, h1);
        vm.prank(validator2);
        oracle.commitValidation(PROJECT_ID, claimId2, 0, h2);

        // Before reveal
        IValidationOracle.Validation[] memory validations = oracle.getValidations(PROJECT_ID, 0);
        assertEq(validations.length, 0);

        // After reveals
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt1);
        vm.prank(validator2);
        oracle.revealValidation(PROJECT_ID, 0, 9000, salt2);

        validations = oracle.getValidations(PROJECT_ID, 0);
        assertEq(validations.length, 2);
        assertEq(validations[0].score, 8000);
        assertEq(validations[1].score, 9000);
    }

    function testSetValidatorCapacityEdgeCases() public {
        // Test increasing capacity
        _setValidatorCapacity(validator1, 500 ether);
        assertEq(oracle.getAvailableCapacity(validator1), 500 ether);

        // Test reducing capacity below in-flight stake
        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;
        bytes32 h = keccak256(abi.encodePacked(uint256(8000), stake, salt));

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);
        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, claimId, 0, h);

        // Try to reduce capacity below in-flight stake
        vm.prank(validator1);
        vm.expectRevert(); // Cannot reduce below active risk
        oracle.setValidatorCapacity(50 ether);

        // Reveal to release in-flight stake
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt);

        // Now can reduce capacity
        vm.prank(validator1);
        oracle.setValidatorCapacity(300 ether);
        assertEq(oracle.getAvailableCapacity(validator1), 300 ether);

        // Test insufficient available stake
        vm.prank(validator1);
        vm.expectRevert(); // Insufficient available stake
        oracle.setValidatorCapacity(2000 ether);
    }

    function testGetConsensusWithActualResults() public {
        _setValidatorCapacity(validator1, 1000 ether);
        _setValidatorCapacity(validator2, 1000 ether);
        _setValidatorCapacity(validator3, 1000 ether);

        // Set numberOfValidations to 3 to match the number of validators
        vm.prank(admin);
        oracle.setProjectNumberOfValidations(PROJECT_ID, 3);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        vm.prank(validator1);
        uint256 claimId1 = oracle.claimToValidate(PROJECT_ID);
        vm.prank(validator2);
        uint256 claimId2 = oracle.claimToValidate(PROJECT_ID);
        vm.prank(validator3);
        uint256 claimId3 = oracle.claimToValidate(PROJECT_ID);

        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;

        bytes32 h1 = keccak256(abi.encodePacked(uint256(8000), stake, salt));
        bytes32 h2 = keccak256(abi.encodePacked(uint256(8500), stake, salt));
        bytes32 h3 = keccak256(abi.encodePacked(uint256(9000), stake, salt));

        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, claimId1, 0, h1);
        vm.prank(validator2);
        oracle.commitValidation(PROJECT_ID, claimId2, 0, h2);
        vm.prank(validator3);
        oracle.commitValidation(PROJECT_ID, claimId3, 0, h3);

        // Before reveals
        IValidationOracle.ConsensusReport memory report = oracle.getConsensus(PROJECT_ID, 0);
        assertEq(report.weightedAverage, 0);
        assertEq(report.validatorCount, 0);
        assertFalse(report.isReady);

        // Reveal all
        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt);
        vm.prank(validator2);
        oracle.revealValidation(PROJECT_ID, 0, 8500, salt);
        vm.prank(validator3);
        oracle.revealValidation(PROJECT_ID, 0, 9000, salt);

        // After reveals
        report = oracle.getConsensus(PROJECT_ID, 0);
        assertTrue(report.isReady);
        assertEq(report.validatorCount, 3);
        assertTrue(report.weightedAverage > 0); // Should calculate weighted average
    }

    function testProjectSpecificRevealDeadline() public {
        _setValidatorCapacity(validator1, 1000 ether);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        // Set project-specific deadline to 2 days BEFORE commit
        // so the snapshot captures the 2-day deadline
        vm.prank(originator);
        oracle.setProjectRevealDeadline(PROJECT_ID, 2 days);

        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);

        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;
        bytes32 h = keccak256(abi.encodePacked(uint256(8000), stake, salt));

        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, claimId, 0, h);

        // Try to cancel before snapshot deadline (2 days)
        vm.warp(block.timestamp + 1 days);
        vm.expectRevert(); // Still within snapshot deadline
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);

        // After snapshot deadline (2 days)
        vm.warp(block.timestamp + 1 days + 1);
        uint256 balanceBefore = vault.getStake(validator1);
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);
        uint256 balanceAfter = vault.getStake(validator1);
        assertTrue(balanceAfter < balanceBefore);
    }

    function testHandleValidatorSlash() public {
        _setValidatorCapacity(validator1, 1000 ether);

        (uint256 capacityBefore,) = oracle.validatorStates(validator1);
        assertEq(capacityBefore, 1000 ether);

        // Slash validator
        vm.prank(admin);
        oracle.handleValidatorSlash(PROJECT_ID, 0, validator1, 200 ether);

        (uint256 capacityAfter,) = oracle.validatorStates(validator1);
        assertEq(capacityAfter, 800 ether);

        // Test slashing more than capacity
        vm.prank(admin);
        oracle.handleValidatorSlash(PROJECT_ID, 0, validator1, 1000 ether);

        (uint256 capacityFinal,) = oracle.validatorStates(validator1);
        assertEq(capacityFinal, 0);

        // Test unauthorized access
        vm.prank(validator1);
        vm.expectRevert();
        oracle.handleValidatorSlash(PROJECT_ID, 0, validator1, 100 ether);

        // Test zero slash amount
        vm.prank(admin);
        oracle.handleValidatorSlash(PROJECT_ID, 0, validator1, 0);
        // Should not revert, just return early
    }

    function testMultipleContributionIndices() public {
        _setValidatorCapacity(validator1, 1000 ether);

        // Set numberOfValidations to 1 so each contribution has exactly 1 queue slot
        vm.prank(admin);
        oracle.setProjectNumberOfValidations(PROJECT_ID, 1);

        // Enqueue multiple contributions
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 1, block.timestamp);
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 2, block.timestamp);

        // Queue: [0, 1, 2] - 1 slot per contribution
        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;

        bytes32 h1 = keccak256(abi.encodePacked(uint256(8000), stake, salt));
        bytes32 h2 = keccak256(abi.encodePacked(uint256(8500), stake, salt));
        bytes32 h3 = keccak256(abi.encodePacked(uint256(9000), stake, salt));

        // Interleave claim-commit to stay within the per-validator active claim limit of 3
        vm.startPrank(validator1);
        uint256 claimId0 = oracle.claimToValidate(PROJECT_ID); // index 0
        oracle.commitValidation(PROJECT_ID, claimId0, 0, h1);

        uint256 claimId1 = oracle.claimToValidate(PROJECT_ID); // index 1
        oracle.commitValidation(PROJECT_ID, claimId1, 1, h2);

        uint256 claimId2 = oracle.claimToValidate(PROJECT_ID); // index 2
        oracle.commitValidation(PROJECT_ID, claimId2, 2, h3);

        // Reveal all three
        oracle.revealValidation(PROJECT_ID, 0, 8000, salt);
        oracle.revealValidation(PROJECT_ID, 1, 8500, salt);
        oracle.revealValidation(PROJECT_ID, 2, 9000, salt);
        vm.stopPrank();

        // Verify all three have validations
        assertEq(oracle.getValidations(PROJECT_ID, 0).length, 1);
        assertEq(oracle.getValidations(PROJECT_ID, 1).length, 1);
        assertEq(oracle.getValidations(PROJECT_ID, 2).length, 1);
    }

    function testCancelExpiredCommitmentEdgeCases() public {
        _setValidatorCapacity(validator1, 1000 ether);

        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);

        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(PROJECT_ID);

        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;
        bytes32 h = keccak256(abi.encodePacked(uint256(8000), stake, salt));

        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, claimId, 0, h);

        // Try to cancel non-existent commitment
        vm.expectRevert(); // NoUnrevealedCommit
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator2);

        // Try to cancel before deadline
        vm.expectRevert(); // NoUnrevealedCommit (not expired yet)
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);

        // After deadline
        vm.warp(block.timestamp + 4 days);

        (uint256 capacityBefore,) = oracle.validatorStates(validator1);
        (, uint256 inFlightBefore) = oracle.validatorStates(validator1);

        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);

        (uint256 capacityAfter,) = oracle.validatorStates(validator1);
        (, uint256 inFlightAfter) = oracle.validatorStates(validator1);

        assertTrue(capacityAfter < capacityBefore);
        assertTrue(inFlightAfter < inFlightBefore);

        // Try to cancel already cancelled
        vm.expectRevert(); // NoUnrevealedCommit
        oracle.cancelExpiredCommitment(PROJECT_ID, 0, validator1);
    }

    function testSetProjectAlgorithmPermissions() public {
        // Only originator or admin can set algorithm
        vm.prank(originator);
        oracle.setProjectAlgorithm(PROJECT_ID, "SqrtStake");

        // Unauthorized user cannot set
        vm.prank(validator1);
        vm.expectRevert();
        oracle.setProjectAlgorithm(PROJECT_ID, "SqrtStake");

        // Admin can set
        vm.prank(admin);
        oracle.setProjectAlgorithm(PROJECT_ID, "SqrtStake");
    }

    function testSetProjectRevealDeadlinePermissions() public {
        // Only originator or admin can set reveal deadline
        vm.prank(originator);
        oracle.setProjectRevealDeadline(PROJECT_ID, 5 days);

        // Unauthorized user cannot set
        vm.prank(validator1);
        vm.expectRevert();
        oracle.setProjectRevealDeadline(PROJECT_ID, 5 days);

        // Admin can set
        vm.prank(admin);
        oracle.setProjectRevealDeadline(PROJECT_ID, 7 days);
    }

    function testFullValidationFlow() public {
        // Complete flow: enqueue -> claim -> commit -> reveal -> consensus
        // Use a separate project with numberOfValidations=1 for this single-validator test
        bytes32 singleValProject = keccak256("single-val-project");
        vm.prank(admin);
        oracle.registerProject(singleValProject, 1, "", originator);

        // 1. Enqueue
        vm.prank(admin);
        oracle.enqueueValidation(singleValProject, 0, block.timestamp);
        assertEq(oracle.getPendingValidationCount(singleValProject), 1);

        // 2. Set capacity and claim
        _setValidatorCapacity(validator1, 1000 ether);
        vm.prank(validator1);
        uint256 claimId = oracle.claimToValidate(singleValProject);
        assertEq(oracle.getPendingValidationCount(singleValProject), 0);
        assertTrue(oracle.isValidatorAssigned(singleValProject, 0, validator1));

        // 3. Commit
        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;
        bytes32 h = keccak256(abi.encodePacked(uint256(8000), stake, salt));
        vm.prank(validator1);
        oracle.commitValidation(singleValProject, claimId, 0, h);

        // 4. Reveal
        vm.prank(validator1);
        oracle.revealValidation(singleValProject, 0, 8000, salt);

        // 5. Check consensus
        IValidationOracle.ConsensusReport memory report = oracle.getConsensus(singleValProject, 0);
        assertTrue(report.isReady);
        assertEq(report.validatorCount, 1);
        assertEq(report.weightedAverage, 8000); // Single validator, so average is their score

        // 6. Verify validation recorded
        IValidationOracle.Validation[] memory validations = oracle.getValidations(singleValProject, 0);
        assertEq(validations.length, 1);
        assertEq(validations[0].score, 8000);
        assertEq(validations[0].validator, validator1);
    }

    function testClaimToValidateWithQueue() public {
        // Set numberOfValidations to 3 to work with per-validator claim limit of 3
        vm.prank(admin);
        oracle.setProjectNumberOfValidations(PROJECT_ID, 3);

        // Test claiming from queue
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 0, block.timestamp);
        vm.prank(admin);
        oracle.enqueueValidation(PROJECT_ID, 1, block.timestamp);

        // Queue: [0,0,0,1,1,1] - 3 slots per contribution
        _setValidatorCapacity(validator1, 1000 ether);

        // Claim all 3 index-0 slots (exactly at the per-validator active claim limit)
        vm.startPrank(validator1);
        oracle.claimToValidate(PROJECT_ID);
        oracle.claimToValidate(PROJECT_ID);
        oracle.claimToValidate(PROJECT_ID);
        vm.stopPrank();

        assertEq(oracle.getPendingValidationCount(PROJECT_ID), 3); // 6 - 3

        // Verify assignments - all 3 claimed items are from first enqueue (index 0)
        assertTrue(oracle.isValidatorAssigned(PROJECT_ID, 0, validator1));
        // Index 1 items are still in queue, not assigned yet
        assertFalse(oracle.isValidatorAssigned(PROJECT_ID, 1, validator1));
    }

    function _stakeForOracle(address user, uint256 amount) internal {
        stakeToken.mint(user, amount);
        vm.startPrank(user);
        stakeToken.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    error InvalidInitialization();

    // --- COVERAGE TESTS FROM OracleCoverage.t.sol ---

    function testCommitValidation_InsufficientCapacity() public {
        bytes32 projectId = keccak256("coverage-project-capacity");
        // Register project with admin
        vm.prank(admin);
        oracle.registerProject(projectId, 10, "", admin);

        // Grant VALIDATOR_ROLE to validator1
        vm.prank(admin);
        trust.grantRole(VALIDATOR_ROLE, validator1);

        // 1. Enqueue as admin (need at least 2 for this test)
        vm.startPrank(admin);
        oracle.enqueueValidation(projectId, 0, block.timestamp);
        oracle.enqueueValidation(projectId, 1, block.timestamp);
        vm.stopPrank();

        // 2. Set capacity to exactly 1 validation (100 ether)
        vm.startPrank(validator1);
        oracle.setValidatorCapacity(100 ether);

        // 3. Attempt to claim 2 validations - should fail due to InvalidQuantity (Option B)
        // With Option B, parameter removed - always claims 1 slot
        // No need to test invalid quantities since function signature doesn't accept them

        // 4. Can claim 1 validation (within capacity)
        uint256 claimId = oracle.claimToValidate(projectId);

        // 5. Commit succeeds (to index 0, which we're assigned to)
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 commitHash1 = keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), bytes32("salt1")));
        oracle.commitValidation(projectId, claimId, 0, commitHash1);

        // 6. Cannot commit to index 1 because we're not assigned to it (only claimed 1 slot, assigned to index 0)
        // Note: The original test expected this to fail at commit time due to capacity,
        // but with our fix, it now fails at claim time. Since we can't claim 2 slots,
        // we can't test the commit-time capacity check. Instead, we verify that
        // attempting to commit to an unassigned index fails appropriately.
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        bytes32 commitHash2 = keccak256(abi.encodePacked(uint256(8000), uint256(100 ether), bytes32("salt2")));
        // The error may be ClaimNotActive if claimId is 0, or Unauthorized if assignment check fails first
        vm.expectRevert(); // Either ClaimNotActive or Unauthorized is acceptable
        oracle.commitValidation(projectId, claimId, 1, commitHash2);
        vm.stopPrank();
    }

    function testRegisterProject_Unauthorized() public {
        vm.prank(contributor);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_MISSING_CORE_ROLE));
        oracle.registerProject(keccak256("new-project"), 10, "", contributor);
    }

    function testSetProjectNumberOfValidations_Unauthorized() public {
        bytes32 projectId = keccak256("coverage-project-maxval");
        // Register project with admin
        vm.prank(admin);
        oracle.registerProject(projectId, 10, "", admin);

        vm.prank(contributor);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_MISSING_CORE_ROLE));
        oracle.setProjectNumberOfValidations(projectId, 20);
    }

    function testSetProjectRequiredSkill_Unauthorized() public {
        bytes32 projectId = keccak256("coverage-project-skill");
        // Register project with admin
        vm.prank(admin);
        oracle.registerProject(projectId, 10, "", admin);

        vm.prank(contributor);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_MISSING_CORE_ROLE));
        oracle.setProjectRequiredSkill(projectId, "Solidity");
    }

    function testSetProjectOriginator_Unauthorized() public {
        bytes32 projectId = keccak256("coverage-project-originator");
        // Register project with admin
        vm.prank(admin);
        oracle.registerProject(projectId, 10, "", admin);

        vm.prank(contributor);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_MISSING_CORE_ROLE));
        oracle.setProjectOriginator(projectId, contributor);
    }

    function testSetContributionContributor_Unauthorized() public {
        bytes32 projectId = keccak256("coverage-project-contributor");
        // Register project with admin
        vm.prank(admin);
        oracle.registerProject(projectId, 10, "", admin);

        vm.prank(contributor);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_MISSING_CORE_ROLE));
        oracle.setContributionContributor(projectId, 0, contributor);
    }

    function testHandleValidatorSlash_CapacitySafetyChecks() public {
        bytes32 projectId = keccak256("coverage-project-slash");
        // Register project with admin
        vm.prank(admin);
        oracle.registerProject(projectId, 10, "", admin);

        // Line 609: if (validatorCapacity[validator] > vaultLockedStake)

        // Use validator1 who already has capacity from setUp

        // Simulate a slash that happens only in vault but not oracle capacity yet
        vm.startPrank(address(oracle));
        vault.slash(validator1, 200 ether, projectId);
        vm.stopPrank();

        // 2. Call handleValidatorSlash for a small amount
        vm.prank(admin);
        oracle.handleValidatorSlash(PROJECT_ID, 0, validator1, 100 ether);

        // Initial capacity was 1000. Slashed 200 in vault.
        // handleValidatorSlash(100) -> capacity would be 1000 - 100 = 900.
        // But it should be clamped to vault.getLockedStake(validator1).
        (uint256 cap,) = oracle.validatorStates(validator1);
        assertEq(cap, vault.getLockedStake(validator1));
        assertTrue(cap < 900 ether);
    }
}
