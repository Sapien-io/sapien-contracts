// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {ValidationClaimStatus} from "src/Types.sol";

/// @title FIX VERIFIED — PoC-001: Expired Validation Claims Now Release Slots
/// @notice Confirms that cancelling expired validation claims properly releases
///         reserved validator slots (`claimCount` / `claimed`), allowing new validators in.
contract POC_001_ValidationClaimExpirySlotLock is BaseTest {
    function test_expiredValidationClaimsPermanentlyBlockNewValidators() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        vm.prank(validator1);
        uint256 claim1 = engine.claimToValidate(projectId, 1);
        vm.prank(validator2);
        uint256 claim2 = engine.claimToValidate(projectId, 1);
        vm.prank(validator3);
        uint256 claim3 = engine.claimToValidate(projectId, 1);

        vm.warp(block.timestamp + C.VALIDATION_CLAIM_DEADLINE + 1);

        engine.cancelExpiredValidationClaim(claim1);
        engine.cancelExpiredValidationClaim(claim2);
        engine.cancelExpiredValidationClaim(claim3);

        assertEq(
            uint256(engine.getValidationClaim(claim1).status),
            uint256(ValidationClaimStatus.Expired),
            "claim1 should be expired"
        );
        assertEq(
            uint256(engine.getValidationClaim(claim2).status),
            uint256(ValidationClaimStatus.Expired),
            "claim2 should be expired"
        );
        assertEq(
            uint256(engine.getValidationClaim(claim3).status),
            uint256(ValidationClaimStatus.Expired),
            "claim3 should be expired"
        );

        // After fix: expired reservations are fully released — new validators can claim.
        address validator4 = makeAddr("validator4");
        vm.prank(validator4);
        engine.claimToValidate(projectId, 1);
    }
}
