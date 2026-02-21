// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ProjectStatus} from "src/Types.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title SEC-M-03 FIX VERIFICATION: Contributions blocked on cancelled/completed projects
/// @notice Verifies that contribute() now checks project status and reverts with
///         ProjectNotActive when the project is cancelled or completed.
contract SEC_M_03_CancelledProjectContribution is BaseTest {
    function test_contributeRevertsOnCancelledProject() public {
        bytes32 projectId = _createAndFundProject();

        // Contributor claims indices
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, adapter);
        engine.contribute(claimId, indices[0], keccak256("submission-0"), "");
        vm.stopPrank();

        // Cancel the project via originator report
        vm.prank(contributor2);
        engine.reportOriginator(projectId, keccak256("misconduct"));

        vm.prank(admin);
        engine.resolveOriginatorReport(projectId, true);

        assertEq(
            uint8(engine.getProject(projectId).status), uint8(ProjectStatus.Cancelled), "project should be cancelled"
        );

        // FIX VERIFIED: contribute reverts on cancelled project
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.ProjectNotActive.selector);
        engine.contribute(claimId, indices[1], keccak256("submission-1"), "");
    }
}
