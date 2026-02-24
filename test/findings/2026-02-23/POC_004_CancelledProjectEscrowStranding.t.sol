// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ProjectStatus} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";

/// @title FIX VERIFIED — PoC-004: Cancelled Projects Can Now Refund Escrow
/// @notice Confirms that funded projects cancelled via operator removal or upheld
///         originator reports can use `refundEscrow` to recover locked tokens.
contract POC_004_CancelledProjectEscrowStranding is BaseTest {
    function test_removeProjectCancellationStrandsEscrow() public {
        bytes32 projectId = _createAndFundProject();
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        assertGt(escrowBefore, 0, "project should have funded escrow");

        vm.prank(admin);
        engine.removeProject(projectId);

        assertEq(
            uint256(engine.getProject(projectId).status),
            uint256(ProjectStatus.Cancelled),
            "project should be cancelled"
        );

        // After fix: refundEscrow is permitted on Cancelled projects after completion delay.
        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);
        vm.prank(originator);
        engine.refundEscrow(projectId);
        assertEq(engine.getProjectEscrow(projectId, address(token)), 0, "escrow should be drained");
    }

    function test_originatorReportCancellationStrandsEscrow() public {
        bytes32 projectId = _createAndFundProject();
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        assertGt(escrowBefore, 0, "project should have funded escrow");

        vm.prank(contributor2);
        engine.reportOriginator(projectId, keccak256("originator-misconduct"));

        vm.prank(admin);
        engine.resolveOriginatorReport(projectId, true);

        assertEq(
            uint256(engine.getProject(projectId).status),
            uint256(ProjectStatus.Cancelled),
            "project should be cancelled"
        );

        // After fix: refundEscrow is permitted on Cancelled projects after completion delay.
        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);
        vm.prank(originator);
        engine.refundEscrow(projectId);
        assertEq(engine.getProjectEscrow(projectId, address(token)), 0, "escrow should be drained");
    }
}
