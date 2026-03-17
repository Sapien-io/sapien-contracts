// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "../../mocks/MockERC20.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Project, ProjectStatus} from "src/Types.sol";

/// @title POQ_006_EarlyScoreDisclosure
/// @notice Test for POQ-6: Missing Reveal Phase Lower Bound Enables Early Score Disclosure
/// @dev This test validates that the vulnerability exists where validators can commit and reveal
///      in the same block, exposing scores early and allowing score copying by later validators.
contract POQ_006_EarlyScoreDisclosure is Test {
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

    event ValidationCommitted(bytes32 indexed projectId, uint256 indexed index, address indexed validator);
    event ValidationRevealed(
        bytes32 indexed projectId, uint256 indexed index, address indexed validator, uint256 score
    );

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
            acceptedContributions: 0,
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

    function _submitContribution() internal returns (uint256 index) {
        vm.prank(contributor);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, address(0));
        index = indices[0];

        vm.prank(contributor);
        engine.contribute(claimId, index, keccak256("submission"), "ipfs://test");
    }

    /// @notice Test that validator CANNOT commit and reveal in the same block (vulnerability fixed)
    /// @dev This test demonstrates that the fix prevents same-block reveal
    function test_VulnerabilityFixed_SameBlockCommitRevealBlocked() public {
        _createAndFundProject();
        uint256 index = _submitContribution();

        // Validators claim to validate
        vm.prank(validator1);
        engine.claimToValidate(PROJECT_ID, 1);

        // Lock validator capacity
        vm.prank(validator1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        // validator1 commits
        uint256 score = 8000;
        bytes32 salt = keccak256("salt1");
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.prank(validator1);
        engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));

        // Attempt to reveal in the same block - should fail with CommitPhaseActive
        vm.expectRevert(ISapienCore.CommitPhaseActive.selector);
        vm.prank(validator1);
        engine.revealValidation(PROJECT_ID, index, score, salt);
    }

    /// @notice Test that score copying is prevented by commit phase enforcement
    /// @dev This demonstrates that the fix prevents the score copying attack
    function test_VulnerabilityFixed_ScoreCopyingPrevented() public {
        _createAndFundProject();
        uint256 index = _submitContribution();

        // All validators claim
        vm.prank(validator1);
        engine.claimToValidate(PROJECT_ID, 1);
        vm.prank(validator2);
        engine.claimToValidate(PROJECT_ID, 1);
        vm.prank(validator3);
        engine.claimToValidate(PROJECT_ID, 1);

        // Lock validator capacities
        vm.prank(validator1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.prank(validator2);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.prank(validator3);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        // All validators must commit before any can reveal
        uint256 score1 = 8000;
        bytes32 salt1 = keccak256("salt1");
        bytes32 commitHash1 = keccak256(abi.encodePacked(score1, salt1));

        vm.prank(validator1);
        engine.commitValidation(PROJECT_ID, index, commitHash1, VALIDATOR_STAKE, address(0));

        // validator1 cannot reveal immediately - commit phase still active
        vm.expectRevert(ISapienCore.CommitPhaseActive.selector);
        vm.prank(validator1);
        engine.revealValidation(PROJECT_ID, index, score1, salt1);

        // validator2 and validator3 commit their scores independently
        bytes32 salt2 = keccak256("salt2");
        bytes32 commitHash2 = keccak256(abi.encodePacked(uint256(7500), salt2));

        vm.prank(validator2);
        engine.commitValidation(PROJECT_ID, index, commitHash2, VALIDATOR_STAKE, address(0));

        bytes32 salt3 = keccak256("salt3");
        bytes32 commitHash3 = keccak256(abi.encodePacked(uint256(8200), salt3));

        vm.prank(validator3);
        engine.commitValidation(PROJECT_ID, index, commitHash3, VALIDATOR_STAKE, address(0));

        // Fast forward past commit deadline
        uint256 commitDeadline = engine.commitDeadline();
        vm.warp(block.timestamp + commitDeadline);

        // Now all can reveal - no one could copy scores during commit phase
        vm.prank(validator1);
        engine.revealValidation(PROJECT_ID, index, score1, salt1);

        vm.prank(validator2);
        engine.revealValidation(PROJECT_ID, index, 7500, salt2);

        vm.prank(validator3);
        engine.revealValidation(PROJECT_ID, index, 8200, salt3);
    }

    /// @notice Test that reveal cannot happen before commit deadline expires (after fix)
    /// @dev This test verifies the fix prevents same-block reveals
    function test_Fix_CannotRevealBeforeCommitDeadline() public {
        _createAndFundProject();
        uint256 index = _submitContribution();

        vm.prank(validator1);
        engine.claimToValidate(PROJECT_ID, 1);

        vm.prank(validator1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        uint256 score = 8000;
        bytes32 salt = keccak256("salt1");
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.prank(validator1);
        engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));

        // Attempt to reveal immediately should fail with CommitPhaseActive error
        vm.expectRevert(ISapienCore.CommitPhaseActive.selector);
        vm.prank(validator1);
        engine.revealValidation(PROJECT_ID, index, score, salt);

        // Fast forward past commit deadline
        uint256 commitDeadline = engine.commitDeadline();
        vm.warp(block.timestamp + commitDeadline);

        // Now reveal should succeed
        vm.prank(validator1);
        engine.revealValidation(PROJECT_ID, index, score, salt);
    }
}
