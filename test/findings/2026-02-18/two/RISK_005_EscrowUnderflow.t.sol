// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";

/// @title RISK-005 VERIFIED: No Escrow Sufficiency Check in Validator Settlement
/// @notice FinalizationLib._settleValidatorFor deducts from project escrow without checking
///         balance sufficiency (line 113: `$.projectEscrow[...] -= validatorShare`).
///         DisputeLib.upholdDispute DOES check (`if ($.projectEscrow[...] >= challengerReward)`).
///         This asymmetry means if escrow is ever pre-drained below expected levels
///         (via disputes, fee-on-transfer tokens, or rounding), settlement reverts.
contract RISK_005_EscrowUnderflow is BaseTest {
    function test_settlementDeductsWithoutSufficiencyCheck() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        _reveal(validator1, projectId, idx, 8000);
        _reveal(validator2, projectId, idx, 8000);
        _reveal(validator3, projectId, idx, 8000);
        engine.computeConsensus(projectId, idx);

        _warpPastChallengePeriod();

        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        assertGt(escrowBefore, 0, "escrow should have funds");

        // Settlement directly subtracts without checking:
        //   FinalizationLib:113 → $.projectEscrow[...] -= validatorShare
        // No guard like: if (escrow >= validatorShare)
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);

        uint256 escrowAfter = engine.getProjectEscrow(projectId, address(token));
        assertLt(escrowAfter, escrowBefore, "escrow decreased without sufficiency check");
    }

    function test_disputeHasCheckButSettlementDoesNot() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, idx, 8000, VALIDATOR_STAKE);
        _reveal(validator1, projectId, idx, 8000);
        _reveal(validator2, projectId, idx, 8000);
        _reveal(validator3, projectId, idx, 8000);
        engine.computeConsensus(projectId, idx);

        uint256 escrowBeforeDispute = engine.getProjectEscrow(projectId, address(token));

        // Dispute path checks sufficiency: `if ($.projectEscrow[...] >= challengerReward)`
        _ensureStake(contributor2, 100e18);
        vm.prank(contributor2);
        engine.openDispute(projectId, idx, keccak256("evidence"), "cid");

        vm.prank(admin);
        engine.resolveDispute(projectId, idx, true);

        uint256 escrowAfterDispute = engine.getProjectEscrow(projectId, address(token));
        assertLt(escrowAfterDispute, escrowBeforeDispute, "dispute drained escrow (with safety check)");

        // After upheld dispute, validators can settle (stake released) but receive NO reward.
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        uint256 escrowFinal = engine.getProjectEscrow(projectId, address(token));
        assertGe(escrowFinal, escrowAfterDispute, "upheld dispute blocks validator reward payout");
    }
}
