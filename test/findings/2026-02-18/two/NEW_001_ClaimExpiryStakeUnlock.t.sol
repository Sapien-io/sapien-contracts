// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {StakeAccount} from "src/Types.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";

/// @title NEW-001 VERIFIED: Claim Expiry Premature Stake Unlock
/// @notice expireClaim() unlocks stake for submitted (in-pipeline) contributions.
///         When those contributions are later rejected by computeConsensus(), the slash
///         reverts because the contributor lock is already zero.
contract NEW_001_ClaimExpiryStakeUnlock is BaseTest {
    function test_expiryUnlocksInPipelineStake() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 3, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        engine.contribute(claimId, indices[1], keccak256("sub1"), "");
        // indices[2] left unsubmitted
        vm.stopPrank();

        assertEq(vault.getStakeAccount(contributor1).contributorLock, 3 * STAKE_AMOUNT, "initial lock = 3x stake");

        vm.warp(block.timestamp + engine.claimDeadline() + 1);
        engine.expireClaim(claimId, indices);

        // BUG: submitted indices' stake was unlocked despite being in the validation pipeline
        assertEq(vault.getStakeAccount(contributor1).contributorLock, 0, "lock is 0 after expire");
    }

    function test_consensusRevertsAfterPrematureUnlock() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        // indices[1] left unsubmitted
        vm.stopPrank();

        vm.warp(block.timestamp + engine.claimDeadline() + 1);
        engine.expireClaim(claimId, indices);

        // Validators reject the submitted contribution
        _commitAndReveal(validator1, projectId, indices[0], 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, indices[0], 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, indices[0], 3000, VALIDATOR_STAKE);

        // computeConsensus tries to slash contributor but lock is already 0
        vm.expectRevert(abi.encodeWithSelector(SapienVault.InsufficientContributorLock.selector, STAKE_AMOUNT, 0));
        engine.computeConsensus(projectId, indices[0]);
    }

    function test_validatorStakePermanentlyLocked() public {
        bytes32 projectId = _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 2, address(0));
        engine.contribute(claimId, indices[0], keccak256("sub0"), "");
        vm.stopPrank();

        vm.warp(block.timestamp + engine.claimDeadline() + 1);
        engine.expireClaim(claimId, indices);

        _commitAndReveal(validator1, projectId, indices[0], 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, projectId, indices[0], 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator3, projectId, indices[0], 3000, VALIDATOR_STAKE);

        StakeAccount memory v1Before = vault.getStakeAccount(validator1);
        assertGt(v1Before.inFlight, 0, "validator has in-flight stake");

        vm.expectRevert();
        engine.computeConsensus(projectId, indices[0]);

        // Validators' in-flight stake is permanently stuck — cannot settle
        assertEq(vault.getStakeAccount(validator1).inFlight, v1Before.inFlight, "validator stake locked forever");
    }
}
