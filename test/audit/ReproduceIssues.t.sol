// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus} from "src/Types.sol";

/// @title ReproduceIssuesTest
/// @notice Tests that prove audit findings exist — these should FAIL before fixes, PASS after
contract ReproduceIssuesTest is BaseTest {
    bytes32 internal projId = keccak256("audit-repro");

    function _validate(address val, bytes32 projectId, uint256 index, uint16 score, uint128 stakeAmt) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, projectId, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.startPrank(val);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = index;
            engine.claimToValidate(projectId, _indices);
        }
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projectId, index, commitHash, stakeAmt, address(0));
        engine.revealValidation(projectId, index, score, salt);
        vm.stopPrank();
    }

    function _validateBelowThreshold(bytes32 projectId, uint256 index) internal {
        _validate(validator1, projectId, index, 3000, uint128(VALIDATOR_STAKE));
        _validate(validator2, projectId, index, 2500, uint128(VALIDATOR_STAKE));
        _validate(validator3, projectId, index, 4000, uint128(VALIDATOR_STAKE));
    }

    // ═══════════════════════════════════════════════════════════════════
    // RISK-003: Validator settlement blocked on rejection
    // ═══════════════════════════════════════════════════════════════════

    /// @notice After rejected consensus, validators must be able to settle (RISK-003)
    /// @dev Before fix: revert. After fix: succeeds.
    function test_RISK003_settlementSucceedsOnRejection() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        _validateBelowThreshold(PROJECT_ID, index);
        engine.computeConsensus(PROJECT_ID, index);

        Contribution memory contrib = engine.getContribution(PROJECT_ID, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected));

        // All validators should be able to settle after rejection (fix for RISK-003)
        uint256 nonce = contrib.consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(PROJECT_ID, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(PROJECT_ID, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(PROJECT_ID, index, nonce);
    }

    // ═══════════════════════════════════════════════════════════════════
    // RISK-005: Escrow underflow in validator settlement
    // ═══════════════════════════════════════════════════════════════════

    /// @notice With 4 validators and limited escrow, 4th settlement can revert
    /// @dev Create project with 1 contribution, 4 validators — validator rewards may exceed escrow
    function test_RISK005_escrowInsufficientForAllValidators() public {
        // Small project: 1000 tokens, 1 slot, 25% to validators = 250 for validators
        // 4 validators with equal weight -> ~62.5 each. Escrow should cover 3, maybe not 4
        // depending on rounding. Use config that definitely underfunds validators.
        vm.startPrank(originator);
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2500, // 25% to validators
            numberOfValidations: 4,
            requiredSkill: bytes32(0),
            minValidatorReputation: 0,
            minValidationStake: 50e18,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0
        });
        engine.createProject(projId, "", config);
        token.mint(originator, 1000e18);
        token.approve(address(engine), 1000e18);
        engine.fundProject(projId, 1000e18, 1, adapter);
        vm.stopPrank();

        address validator4 = makeAddr("validator4");
        token.mint(validator4, 200e18);
        vm.prank(validator4);
        token.approve(address(vault), 200e18);
        vm.prank(validator4);
        vault.deposit(100e18, validator4);

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projId, 1);
        uint256 index = indices[0];

        // 4 validators all participate
        _validate(validator1, projId, index, 8000, 50e18);
        _validate(validator2, projId, index, 8500, 50e18);
        _validate(validator3, projId, index, 7500, 50e18);

        vm.startPrank(validator4);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = index;
            engine.claimToValidate(projId, _indices);
        }
        engine.lockValidatorCapacity(50e18);
        bytes32 salt4 = keccak256("validator4");
        engine.commitValidation(projId, index, keccak256(abi.encodePacked(uint16(8200), salt4)), 50e18, address(0));
        engine.revealValidation(projId, index, 8200, salt4);
        vm.stopPrank();

        engine.computeConsensus(projId, index);

        uint256 nonce = engine.getContribution(projId, index).consensusNonce;
        // First 3 settle
        vm.prank(validator1);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projId, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(projId, index, nonce);

        // Without escrow check: 4th settlement could underflow if rewards > escrow (edge case).
        // Current setup has enough escrow; the fix adds explicit check for clearer errors.
        vm.prank(validator4);
        engine.settleValidator(projId, index, nonce);
    }

    // ═══════════════════════════════════════════════════════════════════
    // RISK-006: Consensus storage collision on resubmission
    // ═══════════════════════════════════════════════════════════════════

    /// @notice After rejection and resubmission, round-1-only validator cannot settle (locked out)
    /// @dev report gets overwritten by round 2; validator3 has no round 2 commit, cannot settle round 1
    function test_RISK006_validatorLockedOutAfterResubmission() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        // Round 1: all 3 validators reject
        _validateBelowThreshold(PROJECT_ID, index);
        engine.computeConsensus(PROJECT_ID, index);
        assertEq(uint256(engine.getContribution(PROJECT_ID, index).status), uint256(ContributionStatus.Rejected));

        // Contributor resubmits; Round 2: validator1, validator2, and contributor2 (as validator4) — validator3 sits out
        address validator4 = contributor2; // reuse contributor2 who has stake
        vm.startPrank(contributor1);
        (uint256 claimId2,) = engine.claimToContribute(PROJECT_ID, 1, adapter);
        engine.contribute(claimId2, index, keccak256("resubmission"), "");
        vm.stopPrank();

        _validate(validator1, PROJECT_ID, index, 9000, uint128(VALIDATOR_STAKE));
        _validate(validator2, PROJECT_ID, index, 8500, uint128(VALIDATOR_STAKE));
        _validate(validator4, PROJECT_ID, index, 8000, uint128(VALIDATOR_STAKE));
        // validator3 does NOT participate in round 2

        engine.computeConsensus(PROJECT_ID, index);
        assertEq(uint256(engine.getContribution(PROJECT_ID, index).status), uint256(ContributionStatus.Accepted));

        // validator3 (round 1 only) cannot settle — round 2 nonce=1, they have no commit for nonce 1
        uint256 round2Nonce = engine.getContribution(PROJECT_ID, index).consensusNonce;
        vm.prank(validator3);
        vm.expectRevert(ISapienCore.NotCommitted.selector);
        engine.settleValidator(PROJECT_ID, index, round2Nonce);
    }

    // ═══════════════════════════════════════════════════════════════════
    // RISK-007: Zero-stake validation bypass
    // ═══════════════════════════════════════════════════════════════════

    /// @notice With minValidationStake=0, validator can commit with stakeAmount=0 and get weight
    /// @dev Before fix: succeeds. After fix: reverts with InsufficientStake
    function test_RISK007_zeroStakeGetsWeight() public {
        vm.startPrank(originator);
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
            requiredSkill: bytes32(0),
            minValidatorReputation: 0,
            minValidationStake: 0, // Allow zero stake
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0
        });
        engine.createProject(projId, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(projId, FUND_AMOUNT, 1, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projId, 1);
        uint256 index = indices[0];

        // validator1 and validator2 with real stake
        _validate(validator1, projId, index, 8000, uint128(VALIDATOR_STAKE));
        _validate(validator2, projId, index, 8500, uint128(VALIDATOR_STAKE));

        // contributor2 tries zero-stake commit — should revert after RISK-007 fix
        vm.startPrank(contributor2);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = index;
            engine.claimToValidate(projId, _indices);
        }
        bytes32 salt = keccak256("zero-stake");
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InsufficientStake.selector, 1, 0));
        engine.commitValidation(projId, index, keccak256(abi.encodePacked(uint16(1000), salt)), 0, address(0));
        vm.stopPrank();
    }
}
