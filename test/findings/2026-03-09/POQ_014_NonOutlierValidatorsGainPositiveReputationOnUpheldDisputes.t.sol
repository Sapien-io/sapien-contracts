// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {DisputeStatus} from "src/Types.sol";

/// @title FIX VERIFIED — POQ-014: Non-Outlier Validators Gain Positive Reputation on Upheld Disputes
/// @notice Confirms that validators who were demonstrably incorrect (their consensus was
///         overturned by an upheld dispute) no longer receive positive reputation.
///         This prevents the compounding feedback loop on consensus weight.
contract POQ_014_NonOutlierValidatorsGainPositiveReputationOnUpheldDisputes is BaseTest {
    function test_validatorsDoNotGainReputationWhenDisputeIsUpheld() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        // Check initial reputation
        uint256 v1RepBefore = engine.getReputation(validator1, SKILL_ID).score;
        uint256 v2RepBefore = engine.getReputation(validator2, SKILL_ID).score;
        uint256 v3RepBefore = engine.getReputation(validator3, SKILL_ID).score;

        // All three validators vote to accept (score 8000)
        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);

        // Compute consensus - contribution is accepted
        engine.computeConsensus(projectId, idx);

        // Open and uphold a dispute (proving validators were wrong)
        vm.prank(contributor2);
        engine.openDispute(projectId, idx, keccak256("wrong-acceptance"), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(projectId, idx, 0, true); // upheld = true

        assertEq(
            uint256(engine.getDispute(projectId, idx).status), uint256(DisputeStatus.Upheld), "dispute should be upheld"
        );

        // Settle validators
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // Check reputation after settlement
        uint256 v1RepAfter = engine.getReputation(validator1, SKILL_ID).score;
        uint256 v2RepAfter = engine.getReputation(validator2, SKILL_ID).score;
        uint256 v3RepAfter = engine.getReputation(validator3, SKILL_ID).score;

        // FIX: Validators should receive negative reputation when disputes are upheld (POQ-9 fix)
        assertLt(v1RepAfter, v1RepBefore, "validator1 should lose reputation when dispute upheld");
        assertLt(v2RepAfter, v2RepBefore, "validator2 should lose reputation when dispute upheld");
        assertLt(v3RepAfter, v3RepBefore, "validator3 should lose reputation when dispute upheld");
    }

    function test_validatorsGainReputationOnlyWhenDisputeNotUpheld() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory contribIndices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = contribIndices[0];

        // Check initial reputation
        uint256 v1RepBefore = engine.getReputation(validator1, SKILL_ID).score;
        uint256 v2RepBefore = engine.getReputation(validator2, SKILL_ID).score;
        uint256 v3RepBefore = engine.getReputation(validator3, SKILL_ID).score;

        // All three validators vote to accept (score 8000)
        _commitAndReveal(validator1, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, idx, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, idx, 8000, VALIDATOR_STAKE);

        // Compute consensus - contribution is accepted
        engine.computeConsensus(projectId, idx);

        // Warp past challenge period (no dispute)
        _warpPastChallengePeriod();

        // Settle validators
        vm.prank(validator1);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator2);
        engine.settleValidator(projectId, idx, 0);
        vm.prank(validator3);
        engine.settleValidator(projectId, idx, 0);

        // Check reputation after settlement
        uint256 v1RepAfter = engine.getReputation(validator1, SKILL_ID).score;
        uint256 v2RepAfter = engine.getReputation(validator2, SKILL_ID).score;
        uint256 v3RepAfter = engine.getReputation(validator3, SKILL_ID).score;

        // EXPECTED: Validators should gain reputation when no dispute is upheld
        assertGt(v1RepAfter, v1RepBefore, "validator1 should gain reputation");
        assertGt(v2RepAfter, v2RepBefore, "validator2 should gain reputation");
        assertGt(v3RepAfter, v3RepBefore, "validator3 should gain reputation");
    }
}
