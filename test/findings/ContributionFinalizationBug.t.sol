// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {ISharedTypes} from "../../src/interface/ISharedTypes.sol";
import {Vm} from "forge-std/Vm.sol";

contract ContributionFinalizationBugTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function test_ContributionFinalizationBug_StatusIsPending() public {
        bytes32 projectId = keccak256("bug_project");
        uint256 numberOfValidations = 1;

        // 1. Setup project
        vm.startPrank(admin);
        oracle.registerProject(projectId, numberOfValidations, "", originator);
        vm.stopPrank();

        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.createProject(projectId, address(rewardToken), "bug_project", 1 ether, 1 ether, 1, 1000, "");
        core.fundProject(projectId, 1000 ether, 10);
        vm.stopPrank();

        // 2. Contributor creates contribution
        vm.startPrank(contributor);
        core.claimToContribute(projectId, 1);
        uint256 contributionIndex = 0;
        core.contribute(projectId, 0, contributionIndex, keccak256("submission"));
        vm.stopPrank();

        // 3. Validator validates with LOW score (below 5000 threshold) -> Should be REJECTED
        address validator = validator1;
        _setValidatorCapacity(validator, 1000 ether);

        vm.startPrank(validator);
        uint256 claimIdVal = oracle.claimToValidate(projectId);
        oracle.commitValidation(
            projectId,
            claimIdVal,
            contributionIndex,
            keccak256(abi.encodePacked(uint256(1000), uint256(100 ether), keccak256("salt")))
        );
        vm.stopPrank();

        vm.startPrank(validator);
        oracle.revealValidation(projectId, contributionIndex, 1000, keccak256("salt"));
        vm.stopPrank();

        // 4. Finalize contribution and check event
        // We expect status 3 (Rejected), but bug report says it emits 0 (Pending)

        // We'll perform the finalization and capture the logs to assert the value
        vm.recordLogs();
        core.finalizeContribution(projectId, contributionIndex);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bool foundEvent = false;
        // ContributionFinalized event signature (updated to include contributor and claimId params)
        bytes32 eventSig = keccak256("ContributionFinalized(bytes32,uint256,uint8,uint256,address,uint256)");

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == eventSig) {
                if (entries[i].topics[1] == projectId && entries[i].topics[2] == bytes32(contributionIndex)) {
                    foundEvent = true;

                    (uint256 decodedStatus,,,) = abi.decode(entries[i].data, (uint256, uint256, address, uint256));

                    emit log_named_uint("Emitted Status", decodedStatus);

                    // IF BUG EXISTS: status should be 0
                    if (decodedStatus == 0) {
                        emit log("BUG REPRODUCED: Status is 0 (Pending) instead of 3 (Rejected)");
                    } else if (decodedStatus == 3) {
                        emit log("FIX VERIFIED: Status is 3 (Rejected)");
                    } else {
                        emit log_named_uint("Unexpected status", decodedStatus);
                    }

                    assertEq(decodedStatus, 3, "Fix failed: Expected status 3 (Rejected)");
                }
            }
        }

        assertTrue(foundEvent, "ContributionFinalized event not found");
    }
}
