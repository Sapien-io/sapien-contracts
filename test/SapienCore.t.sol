// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "./BaseTest.sol";
import {SapienCore} from "src/SapienCore.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    Contribution,
    ContributionStatus,
    ConsensusReport,
    Reputation
} from "src/Types.sol";

contract SapienCoreProjectTest is BaseTest {
    // ═══════════════════════════════════════════════════════════════
    // Project Management
    // ═══════════════════════════════════════════════════════════════

    function test_createProject() public {
        vm.prank(originator);
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            acceptedContributions: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        engine.createProject(PROJECT_ID, "", config);

        Project memory proj = engine.getProject(PROJECT_ID);
        assertEq(proj.originator, originator);
        assertEq(proj.rewardToken, address(token));
        assertEq(proj.consensusThreshold, 7000);
        assertEq(proj.minStakeToClaim, STAKE_AMOUNT);
        assertEq(proj.validatorRewardBps, 2000);
        assertEq(proj.numberOfValidations, 3);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Created));
    }

    function test_createProject_revertsDuplicate() public {
        vm.startPrank(originator);
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            acceptedContributions: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });

        engine.createProject(PROJECT_ID, "", config);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "project already exists"));
        engine.createProject(PROJECT_ID, "", config);
        vm.stopPrank();
    }

    function test_fundProject() public {
        _createAndFundProject();

        Project memory proj = engine.getProject(PROJECT_ID);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Funded));
        assertEq(proj.totalQuantity, QUANTITY);
        assertEq(proj.availableSlots, QUANTITY);

        // Protocol fee (10%) = 1000e18, origination fee (4% of 9000e18) = 360e18
        // Escrow = 10000e18 - 1000e18 - 360e18 = 8640e18
        uint256 escrow = engine.getProjectEscrow(PROJECT_ID, address(token));
        assertGt(escrow, 0);
        assertEq(proj.totalRewards, escrow);
    }

    function test_fundProject_protocolFee() public {
        _createAndFundProject();

        // Treasury should have received protocol fee (10% of 10000e18 = 1000e18)
        uint256 treasuryBal = token.balanceOf(treasury);
        assertEq(treasuryBal, 1000e18);
    }

    function test_fundProject_adapterFee() public {
        _createAndFundProject();

        // Adapter should have pending rewards (4% of (10000e18 - 1000e18) = 360e18)
        uint256 adapterRewards = engine.getPendingRewards(adapter, address(token));
        assertEq(adapterRewards, 360e18);
    }

    function test_fundProject_revertsNotOriginator() public {
        vm.prank(originator);
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            acceptedContributions: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
        engine.createProject(PROJECT_ID, "", config);

        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.NotProjectOriginator.selector);
        engine.fundProject(PROJECT_ID, 1000e18, 5, address(0));
    }
}

contract SapienCoreClaimTest is BaseTest {
    // ═══════════════════════════════════════════════════════════════
    // Claims & Contributions
    // ═══════════════════════════════════════════════════════════════

    function test_claimToContribute() public {
        _createAndFundProject();

        vm.prank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 3, adapter);

        assertEq(claimId, 1);
        assertEq(indices.length, 3);

        Claim memory claim = engine.getClaim(claimId);
        assertEq(claim.claimant, contributor1);
        assertEq(claim.projectId, PROJECT_ID);
        assertEq(claim.totalCount, 3);
        assertEq(claim.submittedCount, 0);
        assertEq(uint256(claim.status), uint256(ClaimStatus.Active));

        // Project should have fewer available slots
        Project memory proj = engine.getProject(PROJECT_ID);
        assertEq(proj.availableSlots, QUANTITY - 3);
    }

    function test_claimToContribute_revertsOriginatorCantContribute() public {
        _createAndFundProject();

        vm.prank(originator);
        vm.expectRevert(ISapienCore.OriginatorCannotContribute.selector);
        engine.claimToContribute(PROJECT_ID, 1, address(0));
    }

    function test_claimToContribute_revertsNoSlots() public {
        _createAndFundProject();

        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.NoSlotsAvailable.selector);
        engine.claimToContribute(PROJECT_ID, QUANTITY + 1, address(0));
    }

    function test_contribute() public {
        _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 2, adapter);

        bytes32 hash = keccak256("submission-data");
        engine.contribute(claimId, indices[0], hash, "");

        Contribution memory contrib = engine.getContribution(PROJECT_ID, indices[0]);
        assertEq(contrib.contributor, contributor1);
        assertEq(contrib.submissionHash, hash);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Pending));
        assertGt(contrib.rewardRate, 0);

        Claim memory claim = engine.getClaim(claimId);
        assertEq(claim.submittedCount, 1);
        vm.stopPrank();
    }

    function test_contribute_completeClaim() public {
        _createAndFundProject();

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 2, adapter);

        for (uint256 i; i < indices.length; ++i) {
            engine.contribute(claimId, indices[i], keccak256(abi.encodePacked("data", i)), "");
        }

        Claim memory claim = engine.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(ClaimStatus.Completed));
        vm.stopPrank();
    }

    function test_contribute_revertsNotOwner() public {
        _createAndFundProject();

        vm.prank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, adapter);

        vm.prank(contributor2);
        vm.expectRevert(ISapienCore.NotClaimOwner.selector);
        engine.contribute(claimId, indices[0], keccak256("data"), "");
    }

    function test_expireClaim() public {
        _createAndFundProject();

        vm.prank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 3, adapter);

        // Submit 1 of 3
        vm.prank(contributor1);
        engine.contribute(claimId, indices[0], keccak256("data0"), "");

        // Warp past deadline
        vm.warp(block.timestamp + 8 days);

        // Anyone can expire (pass indices as calldata)
        engine.expireClaim(claimId, indices);

        Claim memory claim = engine.getClaim(claimId);
        assertEq(uint256(claim.status), uint256(ClaimStatus.Expired));

        // 2 indices should be returned to available stack
        Project memory proj = engine.getProject(PROJECT_ID);
        assertEq(proj.availableSlots, QUANTITY - 3 + 2); // 3 claimed, 2 returned
    }

    function test_expireClaim_revertsNotExpired() public {
        _createAndFundProject();

        vm.prank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(PROJECT_ID, 1, adapter);

        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.expireClaim(claimId, indices);
    }
}

contract SapienCoreValidationTest is BaseTest {
    // ═══════════════════════════════════════════════════════════════
    // Validation (Commit-Reveal)
    // ═══════════════════════════════════════════════════════════════

    function test_commitAndReveal() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);

        uint256 index = indices[0];
        uint256 score = 8000;
        bytes32 salt = keccak256("salt1");
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));

        vm.startPrank(validator1);
        engine.claimToValidate(PROJECT_ID, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(validator1);
        engine.revealValidation(PROJECT_ID, index, score, salt);

        uint256 reveals = engine.getRevealCount(PROJECT_ID, index);
        assertEq(reveals, 1);
    }

    function test_commitValidation_revertsOwnContribution() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);

        uint256 index = indices[0];

        vm.startPrank(contributor1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.expectRevert(ISapienCore.NoEligibleContributions.selector);
        engine.claimToValidate(PROJECT_ID, 1);
        vm.stopPrank();
    }

    function test_revealValidation_revertsInvalidHash() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);

        uint256 index = indices[0];
        uint256 score = 8000;
        bytes32 salt = keccak256("salt1");
        uint256 nonce = engine.getSubmissionNonce(PROJECT_ID, index);
        bytes32 commitHash = keccak256(abi.encodePacked(PROJECT_ID, index, nonce, validator1, uint256(score), salt));

        vm.startPrank(validator1);
        engine.claimToValidate(PROJECT_ID, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        // Try to reveal with wrong score
        vm.expectRevert(ISapienCore.InvalidReveal.selector);
        vm.prank(validator1);
        engine.revealValidation(PROJECT_ID, index, 5000, salt);
    }

    function test_commitValidation_revertsAlreadyCommitted() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);

        uint256 index = indices[0];
        uint256 nonce = engine.getSubmissionNonce(PROJECT_ID, index);
        bytes32 commitHash =
            keccak256(abi.encodePacked(PROJECT_ID, index, nonce, validator1, uint256(8000), bytes32("salt")));

        vm.startPrank(validator1);
        engine.claimToValidate(PROJECT_ID, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE * 2);
        engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));

        vm.expectRevert(ISapienCore.AlreadyCommitted.selector);
        engine.commitValidation(PROJECT_ID, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();
    }
}

contract SapienCoreConsensusTest is BaseTest {
    // ═══════════════════════════════════════════════════════════════
    // Consensus & Finalization
    // ═══════════════════════════════════════════════════════════════

    function test_computeConsensus_accepted() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        // 3 validators all score above threshold (70%)
        _commitAndReveal(validator1, PROJECT_ID, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, PROJECT_ID, index, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, PROJECT_ID, index, 7500, VALIDATOR_STAKE);

        engine.computeConsensus(PROJECT_ID, index);

        ConsensusReport memory r = engine.getConsensusReport(PROJECT_ID, index);
        assertTrue(r.computed);
        assertGt(r.weightedAverage, 7000); // Should be above threshold

        Contribution memory contrib = engine.getContribution(PROJECT_ID, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted));
        assertGt(contrib.challengeEndsAt, 0);
    }

    function test_computeConsensus_rejected() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        // 3 validators all score below threshold (70%)
        _commitAndReveal(validator1, PROJECT_ID, index, 3000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, PROJECT_ID, index, 2500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, PROJECT_ID, index, 4000, VALIDATOR_STAKE);

        engine.computeConsensus(PROJECT_ID, index);

        // On rejection, consensusComputed is reset to false because the nonce increments
        // and the index becomes available again for re-submission
        Contribution memory contrib = engine.getContribution(PROJECT_ID, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected));

        // Index should be returned to available pool
        Project memory proj = engine.getProject(PROJECT_ID);
        assertEq(proj.availableSlots, QUANTITY - 1 + 1); // 1 claimed, 1 returned
    }

    function test_computeConsensus_revertsInsufficientReveals() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        // Only 2 of required 3 validations
        _commitAndReveal(validator1, PROJECT_ID, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, PROJECT_ID, index, 8500, VALIDATOR_STAKE);

        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusNotReady.selector, 2, 3));
        engine.computeConsensus(PROJECT_ID, index);
    }

    function test_computeConsensus_revertsAlreadyComputed() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        _commitAndReveal(validator1, PROJECT_ID, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, PROJECT_ID, index, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, PROJECT_ID, index, 7500, VALIDATOR_STAKE);

        engine.computeConsensus(PROJECT_ID, index);

        vm.expectRevert(ISapienCore.ConsensusAlreadyComputed.selector);
        engine.computeConsensus(PROJECT_ID, index);
    }

    function test_settleValidator_accurate() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        _commitAndReveal(validator1, PROJECT_ID, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, PROJECT_ID, index, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, PROJECT_ID, index, 7500, VALIDATOR_STAKE);

        engine.computeConsensus(PROJECT_ID, index);
        uint256 nonce = engine.getContribution(PROJECT_ID, index).consensusNonce;

        _warpPastChallengePeriod();

        // Settle validator1
        vm.prank(validator1);
        engine.settleValidator(PROJECT_ID, index, nonce);

        assertTrue(engine.isValidatorSettled(PROJECT_ID, index, nonce, validator1));
        assertFalse(engine.isValidatorOutlier(PROJECT_ID, index, validator1));

        // Should have pending rewards
        uint256 rewards = engine.getPendingRewards(validator1, address(token));
        assertGt(rewards, 0);
    }

    function test_settleValidator_revertsAlreadySettled() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        _commitAndReveal(validator1, PROJECT_ID, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, PROJECT_ID, index, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, PROJECT_ID, index, 7500, VALIDATOR_STAKE);

        engine.computeConsensus(PROJECT_ID, index);
        uint256 nonce = engine.getContribution(PROJECT_ID, index).consensusNonce;

        _warpPastChallengePeriod();

        vm.startPrank(validator1);
        engine.settleValidator(PROJECT_ID, index, nonce);

        vm.expectRevert(ISapienCore.AlreadySettled.selector);
        engine.settleValidator(PROJECT_ID, index, nonce);
        vm.stopPrank();
    }
}

contract SapienCoreRewardTest is BaseTest {
    // ═══════════════════════════════════════════════════════════════
    // Rewards
    // ═══════════════════════════════════════════════════════════════

    function test_releaseContributorReward() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        _commitAndReveal(validator1, PROJECT_ID, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, PROJECT_ID, index, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, PROJECT_ID, index, 7500, VALIDATOR_STAKE);

        engine.computeConsensus(PROJECT_ID, index);

        // Warp past challenge period
        vm.warp(block.timestamp + 2 days);

        engine.releaseContributorReward(PROJECT_ID, index);

        uint256 pending = engine.getPendingRewards(contributor1, address(token));
        assertGt(pending, 0);
    }

    function test_releaseContributorReward_revertsChallengeNotElapsed() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        _commitAndReveal(validator1, PROJECT_ID, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, PROJECT_ID, index, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, PROJECT_ID, index, 7500, VALIDATOR_STAKE);

        engine.computeConsensus(PROJECT_ID, index);

        // Don't warp — challenge period not elapsed
        vm.expectRevert(ISapienCore.ChallengeNotElapsed.selector);
        engine.releaseContributorReward(PROJECT_ID, index);
    }

    function test_claimReward() public {
        _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, PROJECT_ID, 1);
        uint256 index = indices[0];

        _commitAndReveal(validator1, PROJECT_ID, index, 8000, VALIDATOR_STAKE);
        _commitAndReveal(validator2, PROJECT_ID, index, 8500, VALIDATOR_STAKE);
        _commitAndReveal(validator3, PROJECT_ID, index, 7500, VALIDATOR_STAKE);

        engine.computeConsensus(PROJECT_ID, index);
        uint256 nonce = engine.getContribution(PROJECT_ID, index).consensusNonce;

        // Warp past challenge period then settle
        _warpPastChallengePeriod();
        vm.prank(validator1);
        engine.settleValidator(PROJECT_ID, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(PROJECT_ID, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(PROJECT_ID, index, nonce);
        engine.releaseContributorReward(PROJECT_ID, index);

        // Claim rewards
        uint256 balBefore = token.balanceOf(contributor1);
        vm.prank(contributor1);
        engine.claimReward(address(token));
        uint256 balAfter = token.balanceOf(contributor1);
        assertGt(balAfter, balBefore);
    }

    function test_claimReward_revertsNoReward() public {
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.NoRewardToClaim.selector);
        engine.claimReward(address(token));
    }

    function test_adapterClaimReward() public {
        _createAndFundProject();

        // Adapter should have origination fee pending
        uint256 pending = engine.getPendingRewards(adapter, address(token));
        assertGt(pending, 0);

        uint256 balBefore = token.balanceOf(adapter);
        vm.prank(adapter);
        engine.claimReward(address(token));
        uint256 balAfter = token.balanceOf(adapter);
        assertEq(balAfter - balBefore, pending);
    }
}

contract SapienCoreReputationTest is BaseTest {
    // ═══════════════════════════════════════════════════════════════
    // Reputation
    // ═══════════════════════════════════════════════════════════════

    function test_defaultReputation() public view {
        Reputation memory rep = engine.getReputation(contributor1, keccak256("CONTRIBUTOR"));
        assertEq(rep.score, 5000); // DEFAULT_REPUTATION
    }

    function test_reputationIncreasesOnProjectCreate() public {
        vm.prank(originator);
        Project memory config = Project({
            originator: address(0),
            rewardToken: address(token),
            totalRewards: 0,
            totalQuantity: 0,
            availableSlots: 0,
            consensusThreshold: 7000,
            minStakeToClaim: STAKE_AMOUNT,
            validatorRewardBps: 2000,
            numberOfValidations: 3,
            requiredSkill: SKILL_ID,
            minValidatorReputation: 0,
            minValidationStake: 0,
            acceptedContributions: 0,
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
        engine.createProject(PROJECT_ID, "", config);

        Reputation memory rep = engine.getReputation(originator, keccak256("ORIGINATOR"));
        assertGt(rep.score, 5000);
    }
}

contract SapienCoreAdminTest is BaseTest {
    // ═══════════════════════════════════════════════════════════════
    // Admin Functions
    // ═══════════════════════════════════════════════════════════════

    function test_setProtocolFee() public {
        vm.prank(admin);
        engine.setProtocolFee(200);
    }

    function test_setProtocolFee_revertsTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.AdapterFeeTooHigh.selector, 1500, 1000));
        engine.setProtocolFee(1500);
    }

    function test_setOriginationFee() public {
        vm.prank(admin);
        engine.setOriginationFee(300);

        (uint256 orig,,) = engine.getAdapterFees();
        assertEq(orig, 300);
    }

    function test_setAdapterFees_revertsTooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.AdapterFeeTooHigh.selector, 600, 500));
        engine.setOriginationFee(600);
    }

    function test_pause_unpause() public {
        vm.startPrank(admin);
        engine.pause();

        vm.expectRevert();
        engine.createProject(
            PROJECT_ID,
            "",
            Project({
                originator: address(0),
                rewardToken: address(token),
                totalRewards: 0,
                totalQuantity: 0,
                availableSlots: 0,
                consensusThreshold: 7000,
                minStakeToClaim: STAKE_AMOUNT,
                validatorRewardBps: 2000,
                numberOfValidations: 3,
                requiredSkill: SKILL_ID,
                minValidatorReputation: 0,
                minValidationStake: 0,
                acceptedContributions: 0,
                status: ProjectStatus.Created,
                activatedAt: 0,
                completedAt: 0,
                cancelledAt: 0
            })
        );

        engine.unpause();
        vm.stopPrank();
    }

    function test_setDecayRate() public {
        vm.prank(admin);
        engine.setDecayRate(20);
    }

    function test_setTreasury() public {
        address newTreasury = makeAddr("newTreasury");
        vm.prank(admin);
        engine.setTreasury(newTreasury);
        assertEq(engine.treasury(), newTreasury);
    }

    function test_setTreasury_revertsZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ISapienCore.ZeroAddress.selector);
        engine.setTreasury(address(0));
    }
}
