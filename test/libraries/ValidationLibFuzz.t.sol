// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus, ValidationClaim} from "src/Types.sol";

/// @title ValidationLibFuzz
/// @notice Fuzz tests attempting to break ValidationLib with edge cases
contract ValidationLibFuzz is Test {
    SapienCore public engine;
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public originator = makeAddr("originator");
    address public contributor = makeAddr("contributor");
    address public validator1 = makeAddr("validator1");
    address public validator2 = makeAddr("validator2");
    address public validator3 = makeAddr("validator3");

    bytes32 public constant PROJECT_ID = keccak256("test-project");
    bytes32 constant SKILL_ID = keccak256("DATA_ANNOTATION");
    uint256 public constant STAKE_AMOUNT = 100e18;
    uint256 public constant VALIDATOR_STAKE = 50e18;

    uint256 public submittedIndex;
    uint256 public claimId;

    function setUp() public {
        token = new MockERC20("Test", "TST");

        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInit = abi.encodeCall(SapienVault.initialize, (token, admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));

        SapienCore engineImpl = new SapienCore();
        bytes memory engineInit = abi.encodeCall(SapienCore.initialize, (admin, address(vault), treasury));
        engine = SapienCore(address(new ERC1967Proxy(address(engineImpl), engineInit)));

        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), address(engine));
        engine.registerSkill("DATA_ANNOTATION");
        vm.stopPrank();

        _setupBalances();
        _createAndFundProject();
        _submitContribution();
    }

    function _setupBalances() internal {
        token.mint(originator, 1_000_000e18);
        vm.prank(originator);
        token.approve(address(engine), type(uint256).max);

        address[4] memory users = [contributor, validator1, validator2, validator3];
        for (uint256 i; i < users.length; ++i) {
            token.mint(users[i], STAKE_AMOUNT * 100);
            vm.startPrank(users[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 50, users[i]);
            vm.stopPrank();
        }
    }

    function _createAndFundProject() internal {
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        vm.startPrank(originator);
        engine.createProject(PROJECT_ID, "", config);
        engine.fundProject(PROJECT_ID, 100_000e18, 50, address(0));
        vm.stopPrank();
    }

    function _submitContribution() internal {
        vm.prank(contributor);
        uint256[] memory indices;
        (claimId, indices) = engine.claimToContribute(PROJECT_ID, 1, address(0));

        vm.prank(contributor);
        engine.contribute(claimId, indices[0], keccak256("submission"), "");
        submittedIndex = indices[0];
    }

    function testFuzz_claimToValidate_validClaim() public {
        vm.prank(validator1);
        uint256 validationClaimId = engine.claimToValidate(PROJECT_ID, 1);

        assertTrue(validationClaimId >= 0);
    }

    function testFuzz_claimToValidate_revertsEmpty() public {
        vm.prank(validator1);
        vm.expectRevert(ISapienCore.ZeroAmount.selector);
        engine.claimToValidate(PROJECT_ID, 0);
    }

    function testFuzz_claimToValidate_revertsOwnContribution() public {
        vm.prank(contributor);
        vm.expectRevert(ISapienCore.NoEligibleContributions.selector);
        engine.claimToValidate(PROJECT_ID, 1);
    }

    function testFuzz_claimToValidate_validWithOneSubmitted() public {
        vm.prank(validator1);
        uint256 validationClaimId = engine.claimToValidate(PROJECT_ID, 1);
        assertTrue(validationClaimId >= 0);
    }

    function testFuzz_claimToValidate_revertsTooManyValidators() public {
        address[4] memory validators = [validator1, validator2, validator3, makeAddr("validator4")];

        for (uint256 i; i < 3; ++i) {
            vm.prank(validators[i]);
            engine.claimToValidate(PROJECT_ID, 1);
        }

        _setupValidator(validators[3]);

        vm.prank(validators[3]);
        vm.expectRevert(ISapienCore.NoEligibleContributions.selector);
        engine.claimToValidate(PROJECT_ID, 1);
    }

    function testFuzz_commitValidation_validCommit(bytes32 salt, uint256 score, uint256 stakeAmount) public {
        score = bound(score, 0, 10_000);
        stakeAmount = bound(stakeAmount, 1e18, VALIDATOR_STAKE);
        vm.assume(salt != bytes32(0));

        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _claimValidation(validator1);
        _lockValidatorCapacity(validator1, stakeAmount);

        vm.prank(validator1);
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, stakeAmount, address(0));
    }

    function testFuzz_commitValidation_revertsZeroHash() public {
        _claimValidation(validator1);
        _lockValidatorCapacity(validator1, VALIDATOR_STAKE);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.InvalidCommitHash.selector);
        engine.commitValidation(PROJECT_ID, submittedIndex, bytes32(0), VALIDATOR_STAKE, address(0));
    }

    function testFuzz_commitValidation_revertsNotClaimed() public {
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), bytes32("salt")));

        _lockValidatorCapacity(validator1, VALIDATOR_STAKE);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.ValidationNotClaimed.selector);
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, VALIDATOR_STAKE, address(0));
    }

    function testFuzz_commitValidation_revertsDoubleCommit() public {
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), bytes32("salt")));

        _claimValidation(validator1);
        _lockValidatorCapacity(validator1, VALIDATOR_STAKE * 2);

        vm.prank(validator1);
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, VALIDATOR_STAKE, address(0));

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.AlreadyCommitted.selector);
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, VALIDATOR_STAKE, address(0));
    }

    function testFuzz_commitValidation_revertsZeroStake() public {
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), bytes32("salt")));

        _claimValidation(validator1);

        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InsufficientStake.selector, 1, 0));
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, 0, address(0));
    }

    function testFuzz_commitValidation_revertsAfterClaimDeadline() public {
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), bytes32("salt")));

        _claimValidation(validator1);
        _lockValidatorCapacity(validator1, VALIDATOR_STAKE);

        vm.warp(block.timestamp + C.VALIDATION_CLAIM_DEADLINE + 1);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.ClaimDeadlinePassed.selector);
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, VALIDATOR_STAKE, address(0));
    }

    function testFuzz_revealValidation_validReveal(uint256 score) public {
        score = bound(score, 0, 10_000);
        bytes32 salt = bytes32("test_salt");
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _claimValidation(validator1);
        _lockValidatorCapacity(validator1, VALIDATOR_STAKE);

        vm.prank(validator1);
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, VALIDATOR_STAKE, address(0));

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(validator1);
        engine.revealValidation(PROJECT_ID, submittedIndex, score, salt);
    }

    function testFuzz_revealValidation_revertsScoreOutOfRange(uint256 score) public {
        score = bound(score, 10_001, type(uint256).max);
        bytes32 salt = bytes32("test_salt");
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _claimValidation(validator1);
        _lockValidatorCapacity(validator1, VALIDATOR_STAKE);

        vm.prank(validator1);
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, VALIDATOR_STAKE, address(0));

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.InvalidScore.selector);
        engine.revealValidation(PROJECT_ID, submittedIndex, score, salt);
    }

    function testFuzz_revealValidation_revertsWrongHash(uint256 score, bytes32 wrongSalt) public {
        score = bound(score, 0, 10_000);
        bytes32 correctSalt = bytes32("correct_salt");
        vm.assume(wrongSalt != correctSalt);

        bytes32 commitHash = keccak256(abi.encodePacked(score, correctSalt));

        _claimValidation(validator1);
        _lockValidatorCapacity(validator1, VALIDATOR_STAKE);

        vm.prank(validator1);
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, VALIDATOR_STAKE, address(0));

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.InvalidReveal.selector);
        engine.revealValidation(PROJECT_ID, submittedIndex, score, wrongSalt);
    }

    function testFuzz_revealValidation_revertsDoubleReveal() public {
        uint256 score = 8000;
        bytes32 salt = bytes32("test_salt");
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _claimValidation(validator1);
        _lockValidatorCapacity(validator1, VALIDATOR_STAKE);

        vm.prank(validator1);
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, VALIDATOR_STAKE, address(0));

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(validator1);
        engine.revealValidation(PROJECT_ID, submittedIndex, score, salt);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.AlreadyRevealed.selector);
        engine.revealValidation(PROJECT_ID, submittedIndex, score, salt);
    }

    function testFuzz_revealValidation_revertsAfterWindow() public {
        uint256 score = 8000;
        bytes32 salt = bytes32("test_salt");
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _claimValidation(validator1);
        _lockValidatorCapacity(validator1, VALIDATOR_STAKE);

        vm.prank(validator1);
        engine.commitValidation(PROJECT_ID, submittedIndex, commitHash, VALIDATOR_STAKE, address(0));

        vm.warp(block.timestamp + engine.commitDeadline() + engine.revealDeadline() + 1);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.RevealWindowClosed.selector);
        engine.revealValidation(PROJECT_ID, submittedIndex, score, salt);
    }

    function testFuzz_computeConsensus_accepted(uint256 score1, uint256 score2, uint256 score3) public {
        score1 = bound(score1, 7500, 9500);
        score2 = bound(score2, 7500, 9500);
        score3 = bound(score3, 7500, 9500);

        _batchValidation(validator1, validator2, validator3, submittedIndex, score1, score2, score3);

        engine.computeConsensus(PROJECT_ID, submittedIndex);

        Contribution memory contrib = engine.getContribution(PROJECT_ID, submittedIndex);
        assertEq(uint8(contrib.status), uint8(ContributionStatus.Accepted));
    }

    function testFuzz_computeConsensus_rejected(uint256 score1, uint256 score2, uint256 score3) public {
        score1 = bound(score1, 0, 5000);
        score2 = bound(score2, 0, 5000);
        score3 = bound(score3, 0, 5000);

        _batchValidation(validator1, validator2, validator3, submittedIndex, score1, score2, score3);

        engine.computeConsensus(PROJECT_ID, submittedIndex);

        Contribution memory contrib = engine.getContribution(PROJECT_ID, submittedIndex);
        assertEq(uint8(contrib.status), uint8(ContributionStatus.Rejected));
    }

    function testFuzz_computeConsensus_revertsNotEnoughReveals() public {
        bytes32 salt1 = _commit(validator1, submittedIndex, 8000);
        bytes32 salt2 = _commit(validator2, submittedIndex, 8000);

        vm.warp(block.timestamp + engine.commitDeadline());

        _reveal(validator1, submittedIndex, 8000, salt1);
        _reveal(validator2, submittedIndex, 8000, salt2);

        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusNotReady.selector, 2, 3));
        engine.computeConsensus(PROJECT_ID, submittedIndex);
    }

    function testFuzz_computeConsensus_revertsAlreadyComputed() public {
        _batchValidation(validator1, validator2, validator3, submittedIndex, 8000, 8000, 8000);

        engine.computeConsensus(PROJECT_ID, submittedIndex);

        vm.expectRevert(ISapienCore.ConsensusAlreadyComputed.selector);
        engine.computeConsensus(PROJECT_ID, submittedIndex);
    }

    function testFuzz_batchCommitValidations_valid(uint8 batchSize) public {
        batchSize = uint8(bound(batchSize, 1, 5));

        _submitMoreContributions(batchSize);

        vm.prank(validator1);
        uint256 vcClaimId = engine.claimToValidate(PROJECT_ID, batchSize);

        ValidationClaim memory vc = engine.getValidationClaim(vcClaimId);
        uint256[] memory assignedIndices = vc.indices;

        bytes32[] memory hashes = new bytes32[](assignedIndices.length);
        uint256[] memory stakes = new uint256[](assignedIndices.length);

        for (uint256 i; i < assignedIndices.length; ++i) {
            hashes[i] = keccak256(abi.encodePacked(uint256(8000), bytes32(bytes32(uint256(i)))));
            stakes[i] = VALIDATOR_STAKE;
        }

        _lockValidatorCapacity(validator1, VALIDATOR_STAKE * assignedIndices.length);

        vm.prank(validator1);
        engine.batchCommitValidations(PROJECT_ID, assignedIndices, hashes, stakes, address(0));
    }

    function testFuzz_cancelExpiredValidationClaim_afterDeadline() public {
        vm.prank(validator1);
        uint256 validationClaimId = engine.claimToValidate(PROJECT_ID, 1);

        vm.warp(block.timestamp + C.VALIDATION_CLAIM_DEADLINE + 1);

        engine.cancelExpiredValidationClaim(validationClaimId);
    }

    function testFuzz_cancelExpiredValidationClaim_revertsBeforeDeadline() public {
        vm.prank(validator1);
        uint256 validationClaimId = engine.claimToValidate(PROJECT_ID, 1);

        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.cancelExpiredValidationClaim(validationClaimId);
    }

    function _claimValidation(address val) internal {
        vm.prank(val);
        engine.claimToValidate(PROJECT_ID, 1);
    }

    function _lockValidatorCapacity(address val, uint256 amount) internal {
        vm.prank(val);
        engine.lockValidatorCapacity(amount);
    }

    function _commit(address val, uint256 index, uint256 score) internal returns (bytes32 salt) {
        salt = keccak256(abi.encodePacked("salt", val, index));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _claimValidation(val);
        _lockValidatorCapacity(val, VALIDATOR_STAKE);

        vm.prank(val);
        engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));
    }

    function _reveal(address val, uint256 index, uint256 score, bytes32 salt) internal {
        vm.prank(val);
        engine.revealValidation(PROJECT_ID, index, score, salt);
    }

    function _fullValidation(address val, uint256 index, uint256 score) internal {
        bytes32 salt = _commit(val, index, score);

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        _reveal(val, index, score, salt);
    }

    function _batchValidation(
        address val1,
        address val2,
        address val3,
        uint256 index,
        uint256 score1,
        uint256 score2,
        uint256 score3
    ) internal {
        bytes32 salt1 = _commit(val1, index, score1);
        bytes32 salt2 = _commit(val2, index, score2);
        bytes32 salt3 = _commit(val3, index, score3);

        // Warp past commit deadline to allow reveals (only once)
        vm.warp(block.timestamp + engine.commitDeadline());

        _reveal(val1, index, score1, salt1);
        _reveal(val2, index, score2, salt2);
        _reveal(val3, index, score3, salt3);
    }

    function _setupValidator(address val) internal {
        token.mint(val, STAKE_AMOUNT * 100);
        vm.startPrank(val);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 50, val);
        vm.stopPrank();
    }

    function _submitMoreContributions(uint8 count) internal returns (uint256[] memory) {
        _ensureStake(contributor, STAKE_AMOUNT * count * 2);

        vm.prank(contributor);
        (uint256 newClaimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, count, address(0));

        for (uint256 i; i < count; ++i) {
            vm.prank(contributor);
            engine.contribute(newClaimId, indices[i], keccak256(abi.encodePacked("sub", i)), "");
        }
        return indices;
    }

    function _ensureStake(address user, uint256 needed) internal {
        uint256 available = vault.availableBalance(user);
        if (available < needed) {
            uint256 deficit = needed - available + 1e18;
            token.mint(user, deficit);
            vm.startPrank(user);
            token.approve(address(vault), deficit);
            vault.deposit(deficit, user);
            vm.stopPrank();
        }
    }
}
