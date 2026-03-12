// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Project, ProjectStatus, StakeAccount, ContributionStatus} from "src/Types.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Constants as C} from "src/Constants.sol";

/// @title POQ-4: Cancellation Paths Do Not Unwind Active Pipeline, Permanently Stranding Validator Funds
/// @notice Tests that validator in-flight stakes are recoverable after project cancellation
///         and that status guards prevent new validators from entering cancelled projects.
contract POQ_004_ValidatorFundsCancellation is BaseTest {
    bytes32 constant PID = keccak256("poq4-test");

    function _createSmallProject() internal returns (bytes32) {
        return _createAndFundProject(PID, FUND_AMOUNT, 2);
    }

    function _fullValidationFlow(bytes32 projectId, uint256 index) internal {
        _commitAndReveal(validator1, projectId, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, index, 8000, VALIDATOR_STAKE);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Test: Validator settlement works on cancelled projects (removeProject)
    // ═══════════════════════════════════════════════════════════════════════

    function test_POQ4_settleValidator_afterRemoveProject() public {
        bytes32 projectId = _createSmallProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _fullValidationFlow(projectId, idx);
        engine.computeConsensus(projectId, idx);

        StakeAccount memory v1Before = vault.getStakeAccount(validator1);
        StakeAccount memory v2Before = vault.getStakeAccount(validator2);
        StakeAccount memory v3Before = vault.getStakeAccount(validator3);

        assertGt(v1Before.inFlight, 0, "v1 should have in-flight stake");
        assertGt(v2Before.inFlight, 0, "v2 should have in-flight stake");
        assertGt(v3Before.inFlight, 0, "v3 should have in-flight stake");

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        assertEq(
            uint256(engine.getProject(projectId).status),
            uint256(ProjectStatus.Cancelled),
            "project should be cancelled"
        );

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);

        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);

        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        StakeAccount memory v1After = vault.getStakeAccount(validator1);
        StakeAccount memory v2After = vault.getStakeAccount(validator2);
        StakeAccount memory v3After = vault.getStakeAccount(validator3);

        assertEq(v1After.inFlight, 0, "v1 in-flight should be 0 after settlement");
        assertEq(v2After.inFlight, 0, "v2 in-flight should be 0 after settlement");
        assertEq(v3After.inFlight, 0, "v3 in-flight should be 0 after settlement");

        assertEq(
            v1After.validatorCapacity,
            v1Before.validatorCapacity + v1Before.inFlight,
            "v1 capacity should include released stake"
        );
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Test: Validator settlement works on cancelled projects (upholdOriginatorReport)
    // ═══════════════════════════════════════════════════════════════════════

    function test_POQ4_settleValidator_afterUpholdOriginatorReport() public {
        bytes32 projectId = _createSmallProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _fullValidationFlow(projectId, idx);
        engine.computeConsensus(projectId, idx);

        StakeAccount memory v1Before = vault.getStakeAccount(validator1);
        assertGt(v1Before.inFlight, 0, "v1 should have in-flight stake");

        _ensureStake(contributor2, 1000e18);
        vm.prank(contributor2);
        engine.reportOriginator(projectId, keccak256("evidence"));

        vm.prank(admin);
        engine.resolveOriginatorReport(projectId, true);

        assertEq(
            uint256(engine.getProject(projectId).status),
            uint256(ProjectStatus.Cancelled),
            "project should be cancelled"
        );

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);

        StakeAccount memory v1After = vault.getStakeAccount(validator1);
        assertEq(v1After.inFlight, 0, "v1 in-flight should be 0 after settlement");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Test: forceSettleValidator works on cancelled projects
    // ═══════════════════════════════════════════════════════════════════════

    function test_POQ4_forceSettleValidator_afterCancellation() public {
        bytes32 projectId = _createSmallProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _fullValidationFlow(projectId, idx);
        engine.computeConsensus(projectId, idx);

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        engine.forceSettleValidator(projectId, idx, 0, validator1);

        StakeAccount memory v1After = vault.getStakeAccount(validator1);
        assertEq(v1After.inFlight, 0, "v1 in-flight should be 0 after force settlement");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Test: Committed-but-not-revealed validators can settle on cancelled projects
    // ═══════════════════════════════════════════════════════════════════════

    function test_POQ4_settleCommittedNotRevealed_afterCancellation() public {
        bytes32 projectId = _createSmallProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, idx));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        StakeAccount memory v1Before = vault.getStakeAccount(validator1);
        assertGt(v1Before.inFlight, 0, "v1 should have in-flight stake");

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);

        StakeAccount memory v1After = vault.getStakeAccount(validator1);
        assertEq(v1After.inFlight, 0, "v1 in-flight should be 0");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Test: claimToValidate is blocked on cancelled projects
    // ═══════════════════════════════════════════════════════════════════════

    function test_POQ4_claimToValidate_blockedOnCancelledProject() public {
        bytes32 projectId = _createSmallProject();

        _claimAndContribute(contributor1, projectId, 1);

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.ProjectNotActive.selector);
        engine.claimToValidate(projectId, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Test: commitValidation is blocked on cancelled projects
    // ═══════════════════════════════════════════════════════════════════════

    function test_POQ4_commitValidation_blockedOnCancelledProject() public {
        bytes32 projectId = _createSmallProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.prank(validator1);
        engine.claimToValidate(projectId, 1);

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, idx));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

        vm.startPrank(validator1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.expectRevert(ISapienCore.ProjectNotActive.selector);
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Test: revealValidation is blocked on cancelled projects
    // ═══════════════════════════════════════════════════════════════════════

    function test_POQ4_revealValidation_blockedOnCancelledProject() public {
        bytes32 projectId = _createSmallProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, idx));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, idx, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.ProjectNotActive.selector);
        engine.revealValidation(projectId, idx, 8000, salt);
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Test: No rewards paid to validators on cancelled project settlement
    // ═══════════════════════════════════════════════════════════════════════

    function test_POQ4_noRewards_onCancelledProjectSettlement() public {
        bytes32 projectId = _createSmallProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _fullValidationFlow(projectId, idx);
        engine.computeConsensus(projectId, idx);

        uint256 v1RewardsBefore = engine.getPendingRewards(validator1, address(token));

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        _warpPastChallengePeriod();

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);

        uint256 v1RewardsAfter = engine.getPendingRewards(validator1, address(token));
        assertEq(v1RewardsAfter, v1RewardsBefore, "no rewards should be paid on cancelled project");
    }

    // ═══════════════════════════════════════════════════════════════════════
    // Test: Double settlement is still prevented on cancelled projects
    // ═══════════════════════════════════════════════════════════════════════

    function test_POQ4_doubleSettlement_reverts() public {
        bytes32 projectId = _createSmallProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _fullValidationFlow(projectId, idx);
        engine.computeConsensus(projectId, idx);

        vm.prank(admin);
        engine.removeProject(projectId, 0);

        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.AlreadySettled.selector);
        engine.settleValidator(projectId, idx, 0);
    }
}
