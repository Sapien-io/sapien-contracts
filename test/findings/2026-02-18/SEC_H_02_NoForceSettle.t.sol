// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {IQualityEngine} from "src/interfaces/IQualityEngine.sol";
import {Constants as C} from "src/Constants.sol";

/// @title SEC-H-02 FIX VERIFICATION: forceSettleValidator now available
/// @notice Verifies that a permissionless forceSettleValidator function exists, allowing
///         anyone to settle a validator after FORCE_SETTLE_DELAY, preventing permanent stake lock.
contract SEC_H_02_NoForceSettle is BaseTest {
    function test_forceSettleAfterDelay() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator2, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator3, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        engine.computeConsensus(projectId, idx);

        uint256 inFlightBefore = vault.getStakeAccount(validator3).inFlight;
        assertTrue(inFlightBefore > 0, "validator3 has in-flight stake");

        // Warp past FORCE_SETTLE_DELAY
        vm.warp(block.timestamp + C.FORCE_SETTLE_DELAY + 1);

        // FIX VERIFIED: a third party (keeper) can now force-settle for validator3
        address keeper = makeAddr("keeper");
        vm.prank(keeper);
        engine.forceSettleValidator(projectId, idx, 0, validator3);

        uint256 inFlightAfter = vault.getStakeAccount(validator3).inFlight;
        assertEq(inFlightAfter, inFlightBefore - uint256(VALIDATOR_STAKE), "in-flight stake released");
    }

    function test_forceSettleTooEarlyReverts() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator2, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator3, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        engine.computeConsensus(projectId, idx);

        // Try to force-settle too early
        address keeper = makeAddr("keeper");
        vm.prank(keeper);
        vm.expectRevert(IQualityEngine.ForceSettleTooEarly.selector);
        engine.forceSettleValidator(projectId, idx, 0, validator3);
    }

    function test_selfSettleStillWorks() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator2, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator3, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        engine.computeConsensus(projectId, idx);

        // Self-settle still works without delay
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);

        assertTrue(engine.isValidatorSettled(projectId, idx, 0, validator1), "validator1 settled");
    }

    function test_outlierForceSettled() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator2, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator3, projectId, idx, 1000, 1e18);
        engine.computeConsensus(projectId, idx);

        assertTrue(engine.isValidatorOutlier(projectId, idx, validator3), "validator3 should be outlier");

        uint256 inFlightBefore = vault.getStakeAccount(validator3).inFlight;
        assertTrue(inFlightBefore > 0, "validator3 has in-flight stake");

        // Warp past force-settle delay
        vm.warp(block.timestamp + C.FORCE_SETTLE_DELAY + 1);

        // Keeper force-settles the outlier — their stake gets slashed
        address keeper = makeAddr("keeper");
        vm.prank(keeper);
        engine.forceSettleValidator(projectId, idx, 0, validator3);

        assertTrue(engine.isValidatorSettled(projectId, idx, 0, validator3), "validator3 force-settled");
    }
}
