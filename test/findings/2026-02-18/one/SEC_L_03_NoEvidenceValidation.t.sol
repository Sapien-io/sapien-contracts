// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Dispute, OriginatorReport} from "src/Types.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title SEC-L-03 FIX VERIFICATION: Evidence hash validation enforced
/// @notice Verifies that openDispute and reportOriginator now reject bytes32(0) as
///         the evidence hash, requiring meaningful evidence for disputes/reports.
contract SEC_L_03_NoEvidenceValidation is BaseTest {
    address public disputer = makeAddr("disputer");

    function setUp() public override {
        super.setUp();
        token.mint(disputer, STAKE_AMOUNT * 10);
        vm.startPrank(disputer);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 5, disputer);
        vm.stopPrank();
    }

    function test_openDisputeRejectsZeroEvidenceHash() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator2, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator3, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        engine.computeConsensus(projectId, idx);

        // FIX VERIFIED: empty evidence hash is now rejected
        vm.prank(disputer);
        vm.expectRevert(ISapienCore.InvalidEvidenceHash.selector);
        engine.openDispute(projectId, idx, bytes32(0), "evidenceCid");
    }

    function test_reportOriginatorRejectsZeroEvidenceHash() public {
        bytes32 projectId = _createAndFundProject();
        _claimAndContribute(contributor1, projectId, 1);

        // FIX VERIFIED: empty evidence hash is now rejected
        vm.prank(disputer);
        vm.expectRevert(ISapienCore.InvalidEvidenceHash.selector);
        engine.reportOriginator(projectId, bytes32(0));
    }

    function test_nonZeroEvidenceHashAccepted() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _commitAndReveal(validator1, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator2, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        _commitAndReveal(validator3, projectId, idx, 8000, uint128(VALIDATOR_STAKE));
        engine.computeConsensus(projectId, idx);

        // Non-zero evidence hash still works
        vm.prank(disputer);
        engine.openDispute(projectId, idx, keccak256("valid evidence"), "evidenceCid");

        Dispute memory d = engine.getDispute(projectId, idx);
        assertEq(d.evidenceHash, keccak256("valid evidence"), "valid evidence hash accepted");
    }
}
