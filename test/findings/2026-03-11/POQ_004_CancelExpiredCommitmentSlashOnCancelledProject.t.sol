// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {StakeAccount, ProjectStatus} from "src/Types.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title POQ-004: cancelExpiredCommitment slashes validators on cancelled projects
/// @notice A committed-but-not-revealed validator whose project gets cancelled should
///         have their stake released, not slashed.  Before the fix, a third party could
///         call cancelExpiredCommitment after the reveal window and fully slash the
///         validator — the same fund-stranding scenario POQ-4 set out to eliminate.
contract POQ_004_CancelExpiredCommitmentSlashOnCancelledProject is BaseTest {
    /// @notice On a cancelled project, cancelExpiredCommitment releases stake
    ///         instead of slashing.
    function test_cancelExpiredCommitment_releasesOnCancelledProject() public {
        bytes32 pid = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, pid, 1);
        uint256 index = indices[0];

        // validator1 commits but does NOT reveal
        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, index));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(pid, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(pid, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        StakeAccount memory before = vault.getStakeAccount(validator1);
        assertGt(before.inFlight, 0, "validator has in-flight stake after commit");

        // Operator cancels the project
        vm.prank(admin);
        engine.removeProject(pid);
        assertEq(uint256(engine.getProject(pid).status), uint256(ProjectStatus.Cancelled));

        // Warp past the full commit+reveal window so the commitment is "expired"
        vm.warp(block.timestamp + engine.commitDeadline() + engine.revealDeadline() + 1);

        // Anyone calls cancelExpiredCommitment — should release, not slash
        uint256 sharesBefore = vault.balanceOf(validator1);

        vm.expectEmit(true, true, true, true);
        emit ISapienCore.ValidatorSettled(pid, index, validator1, false);

        engine.cancelExpiredCommitment(pid, index, validator1);

        StakeAccount memory after_ = vault.getStakeAccount(validator1);
        assertEq(after_.inFlight, 0, "in-flight stake released");

        uint256 sharesAfter = vault.balanceOf(validator1);
        assertEq(sharesAfter, sharesBefore, "no shares burned - stake was released, not slashed");
    }

    /// @notice On a cancelled project, cancelExpiredCommitment reverts if already
    ///         settled via settleValidator.
    function test_cancelExpiredCommitment_revertsIfAlreadySettled() public {
        bytes32 pid = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, pid, 1);
        uint256 index = indices[0];

        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, index));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(pid, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(pid, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        vm.prank(admin);
        engine.removeProject(pid);

        // Validator settles first via the POQ-4 pull path
        vm.prank(validator1);
        engine.settleValidator(pid, index, 0);

        // Now cancelExpiredCommitment should revert
        vm.warp(block.timestamp + engine.commitDeadline() + engine.revealDeadline() + 1);
        vm.expectRevert(ISapienCore.AlreadySettled.selector);
        engine.cancelExpiredCommitment(pid, index, validator1);
    }

    /// @notice On an ACTIVE project, cancelExpiredCommitment still slashes as before.
    function test_cancelExpiredCommitment_stillSlashesOnActiveProject() public {
        bytes32 pid = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, pid, 1);
        uint256 index = indices[0];

        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, index));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(pid, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(pid, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // Project stays active — warp past the window
        vm.warp(block.timestamp + engine.commitDeadline() + engine.revealDeadline() + 1);

        uint256 sharesBefore = vault.balanceOf(validator1);

        engine.cancelExpiredCommitment(pid, index, validator1);

        uint256 sharesAfter = vault.balanceOf(validator1);
        assertLt(sharesAfter, sharesBefore, "validator slashed on active project");
    }
}
