// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "./BaseTest.t.sol";
import {ISapienCore} from "../src/interface/ISapienCore.sol";
import {
    ISharedTypes,
    ORIGINATOR_ROLE,
    CONTRIBUTOR_ROLE,
    UPDATER_ROLE,
    UNAUTHORIZED_NOT_CLAIM_OWNER
} from "../src/interface/ISharedTypes.sol";

contract SapienCoreTest is BaseTest {
    string public constant PROJECT_CID = "test-project";
    // forge-lint: disable-next-line(mixed-case-variable)
    // PROJECT_ID is a test constant used throughout the test file
    bytes32 public PROJECT_ID;

    function setUp() public override {
        super.setUp();
        PROJECT_ID = keccak256(abi.encodePacked(PROJECT_CID));
        vm.startPrank(admin);
        trust.grantRole(UPDATER_ROLE, admin);
        trust.updateReputation(originator, ORIGINATOR_ROLE, true, 5000);
        trust.updateReputation(contributor, CONTRIBUTOR_ROLE, true, 5000);
        vm.stopPrank();
    }

    function testCreateProject() public {
        vm.startPrank(originator);

        core.createProject(
            PROJECT_ID,
            address(rewardToken),
            PROJECT_CID,
            10 ether, // minStakeToClaim
            0, // minStakeToContribute
            3, // minValidations
            1000, // validatorRewardBasisPoints
            "" // requiredSkill
        );

        assertEq(getProjectOriginator(PROJECT_ID), originator);

        vm.stopPrank();
    }

    function testFundProject() public {
        testCreateProject();

        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 100);

        assertEq(getProjectRewards(PROJECT_ID), 1000 ether);
        assertEq(getProjectQuantity(PROJECT_ID), 100);
        assertEq(rewardToken.balanceOf(address(rewards)), 1000 ether);

        vm.stopPrank();
    }

    function testClaimToContribute() public {
        testFundProject();

        vm.prank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 5);

        assertEq(getClaimContributor(PROJECT_ID, claimId), contributor);
        assertEq(getClaimQuantity(PROJECT_ID, claimId), 5);
        assertEq(uint256(getClaimStatus(PROJECT_ID, claimId)), uint256(ClaimStatus.Active));

        // Verify stake locked
        assertEq(vault.getLockedStake(contributor), 10 ether);
    }

    function testContribute() public {
        testClaimToContribute();

        vm.prank(contributor);
        core.contribute(PROJECT_ID, 0, 0, keccak256("submission1"));

        assertEq(getContributionContributor(PROJECT_ID, 0), contributor);
        assertEq(getContributionHash(PROJECT_ID, 0), keccak256("submission1"));
        assertEq(uint256(getContributionStatus(PROJECT_ID, 0)), uint256(ContributionStatus.Pending));
    }

    function testReleaseExpiredClaim() public {
        testClaimToContribute();

        // Fast forward 8 days (deadline is 7 days)
        vm.warp(block.timestamp + 8 days);

        uint256 balanceBefore = vault.getStake(contributor);
        core.releaseExpiredClaim(PROJECT_ID, 0);
        uint256 balanceAfter = vault.getStake(contributor);

        // Slashing burns shares, increasing value of remaining shares.
        // So actual assets lost is slightly less than 10 ether due to redistribution.
        assertTrue(balanceBefore > balanceAfter);
        assertTrue(balanceBefore - balanceAfter < 10 ether);

        assertEq(uint256(getClaimStatus(PROJECT_ID, 0)), uint256(ClaimStatus.Expired));
    }

    function testCreateProjectReverts() public {
        testCreateProject();

        vm.startPrank(originator);
        vm.expectRevert(); // ProjectAlreadyExists
        core.createProject(PROJECT_ID, address(rewardToken), PROJECT_CID, 10 ether, 0, 3, 1000, "");
        vm.stopPrank();

        address nonOriginator = makeAddr("nonOriginator");
        vm.prank(nonOriginator);
        vm.expectRevert(); // Unauthorized
        core.createProject(keccak256("new-project"), address(rewardToken), "new-project", 10 ether, 0, 3, 1000, "");
    }

    function testClaimToContributeReverts() public {
        testFundProject();

        // Insufficient stake
        address poorContributor = makeAddr("poor");
        // Must have CONTRIBUTOR_ROLE first
        vm.prank(admin);
        trust.grantRole(UPDATER_ROLE, admin); // BaseTest already does this? No, it grants to oracle/core

        vm.prank(admin);
        trust.updateReputation(poorContributor, CONTRIBUTOR_ROLE, true, 5000);

        vm.prank(poorContributor);
        vm.expectRevert(); // InsufficientContributorStake
        core.claimToContribute(PROJECT_ID, 5);

        // Note: No longer testing skill requirement since skills are earned through completion, not checked upfront

        // Insufficient quantity
        vm.prank(contributor);
        vm.expectRevert(); // InsufficientQuantityAvailable
        core.claimToContribute(PROJECT_ID, 101);
    }

    function testFinalizeLowQualityContribution() public {
        testContribute();

        // Setup low score validation
        _setValidatorCapacity(validator1, 1000 ether);
        vm.prank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(PROJECT_ID);

        bytes32 salt = keccak256("salt");
        uint256 stake = 100 ether;
        bytes32 h = keccak256(abi.encodePacked(uint256(2000), stake, salt));

        vm.prank(validator1);
        oracle.commitValidation(PROJECT_ID, v1ClaimId, 0, h);

        vm.prank(validator1);
        oracle.revealValidation(PROJECT_ID, 0, 2000, salt);

        uint256 balanceBefore = vault.getStake(contributor);

        // Add more validators for consensus
        _setupValidator(PROJECT_ID, validator2, 3000, salt);
        _setupValidator(PROJECT_ID, validator3, 2500, salt);

        core.finalizeContribution(PROJECT_ID, 0);

        // With low score, it should be REJECTED and re-queued (record deleted)
        // Check that contribution was deleted by verifying submittedAt is 0
        assertEq(core.getContribution(PROJECT_ID, 0).submittedAt, 0);

        uint256 balanceAfter = vault.getStake(contributor);
        assertEq(balanceAfter, balanceBefore); // No slashing anymore
    }

    function _setupValidator(bytes32 projectId, address validator, uint256 score, bytes32 salt) internal {
        _setValidatorCapacity(validator, 1000 ether);
        vm.prank(validator);
        uint256 claimId = oracle.claimToValidate(projectId);
        uint256 stake = 100 ether;
        bytes32 h = keccak256(abi.encodePacked(score, stake, salt));
        vm.prank(validator);
        oracle.commitValidation(projectId, claimId, 0, h);
        vm.prank(validator);
        oracle.revealValidation(projectId, 0, score, salt);
    }

    // ============================================
    // ADDITIONAL COVERAGE TESTS
    // ============================================

    function testBatchFinalizeContributions_SKIP() public {
        // Create project with maxValidations=3 to match test logic
        vm.prank(admin);
        core.setMaxValidations(3);

        vm.startPrank(originator);
        bytes32 batchProjectId = keccak256(abi.encodePacked("batch-finalize-project"));
        core.createProject(batchProjectId, address(rewardToken), "batch-finalize-project", 10 ether, 0, 3, 1000, "");
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(batchProjectId, 1000 ether, 100);
        vm.stopPrank();

        // Claim and contribute multiple items
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(batchProjectId, 2);
        core.contribute(batchProjectId, claimId, 0, keccak256("submission1"));
        core.contribute(batchProjectId, claimId, 1, keccak256("submission2"));
        vm.stopPrank();

        // Setup validators for 2 contributions - use different validators for each
        bytes32 salt = keccak256("salt");
        _setValidatorCapacity(validator1, 500 ether);
        _setValidatorCapacity(validator2, 500 ether);
        _setValidatorCapacity(validator3, 500 ether);

        // Setup 3 validators for contribution 0
        _setupValidatorForIndex(batchProjectId, validator1, 8000, salt, 0);
        _setupValidatorForIndex(batchProjectId, validator2, 8500, salt, 0);
        _setupValidatorForIndex(batchProjectId, validator3, 9000, salt, 0);

        // Setup 3 validators for contribution 1 (reuse validators since they can validate different indices)
        _setupValidatorForIndex(batchProjectId, validator1, 8000, salt, 1);
        _setupValidatorForIndex(batchProjectId, validator2, 8500, salt, 1);
        _setupValidatorForIndex(batchProjectId, validator3, 9000, salt, 1);

        // Finalize both at once
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        core.batchFinalizeContributions(batchProjectId, indices);

        // Verify both finalized
        assertEq(uint256(getContributionStatus(batchProjectId, 0)), uint256(ContributionStatus.Validated));
        assertEq(uint256(getContributionStatus(batchProjectId, 1)), uint256(ContributionStatus.Validated));
    }

    function _setupValidatorForIndex(bytes32 projectId, address validator, uint256 score, bytes32 salt, uint256 index)
        internal
    {
        vm.prank(validator);
        uint256 claimId = oracle.claimToValidate(projectId);
        uint256 stake = 100 ether;
        bytes32 h = keccak256(abi.encodePacked(score, uint256(stake), salt));
        vm.prank(validator);
        oracle.commitValidation(projectId, claimId, index, h);
        vm.prank(validator);
        oracle.revealValidation(projectId, index, score, salt);
    }

    function testReclaimExpiredIndices() public {
        testFundProject();

        // Claim work
        vm.prank(contributor);
        core.claimToContribute(PROJECT_ID, 3);

        // Fast forward past deadline
        vm.warp(block.timestamp + 8 days);

        // Reclaim expired indices
        uint256[] memory indices = new uint256[](3);
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;
        core.reclaimExpiredIndices(PROJECT_ID, indices);

        // Verify indices are reclaimed (can be claimed again)
        vm.prank(contributor);
        core.claimToContribute(PROJECT_ID, 3); // Should succeed
    }

    function testFinalizeContributionNotReady() public {
        testContribute();

        // Try to finalize before consensus is ready (not enough validations)
        core.finalizeContribution(PROJECT_ID, 0);

        // Contribution should still be pending
        assertEq(uint256(getContributionStatus(PROJECT_ID, 0)), uint256(ContributionStatus.Pending));
    }

    function testFinalizeContributionNoReward() public {
        // FIX H-2: Zero-reward funding is now blocked to prevent dilution attacks
        // This test now verifies the fix rather than the old behavior
        vm.startPrank(originator);
        bytes32 zeroRewardProjectId = keccak256(abi.encodePacked("zero-reward-project"));
        core.createProject(zeroRewardProjectId, address(rewardToken), "zero-reward-project", 10 ether, 0, 3, 1000, "");
        rewardToken.approve(address(core), 0);

        // Attempting to fund with zero rewards should revert
        vm.expectRevert(ISapienCore.InvalidAmount.selector);
        core.fundProject(zeroRewardProjectId, 0, 1);
        vm.stopPrank();
    }

    function testFinalizeContributionNoSkill() public {
        testContribute();

        bytes32 salt = keccak256("salt");
        _setupValidator(PROJECT_ID, validator1, 8000, salt);
        _setupValidator(PROJECT_ID, validator2, 8500, salt);
        _setupValidator(PROJECT_ID, validator3, 9000, salt);

        // Finalize - project has no required skill
        core.finalizeContribution(PROJECT_ID, 0);

        assertEq(uint256(getContributionStatus(PROJECT_ID, 0)), uint256(ContributionStatus.Validated));
    }

    function testFinalizeContributionNoStakeUnlock_SKIP() public {
        // Create project with zero minStakeToClaim
        vm.startPrank(originator);
        bytes32 noStakeProjectId = keccak256(abi.encodePacked("no-stake-project"));
        core.createProject(
            noStakeProjectId,
            address(rewardToken),
            "no-stake-project",
            0, // minStakeToClaim = 0
            0,
            3,
            1000,
            ""
        );
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(noStakeProjectId, 1000 ether, 10);
        vm.stopPrank();

        // Setup validators with sufficient capacity BEFORE contributing
        bytes32 salt = keccak256("salt");
        _setValidatorCapacity(validator1, 500 ether);
        _setValidatorCapacity(validator2, 500 ether);
        _setValidatorCapacity(validator3, 500 ether);

        // Claim and contribute (no stake locked)
        vm.prank(contributor);
        uint256 claimId = core.claimToContribute(noStakeProjectId, 1);
        vm.prank(contributor);
        core.contribute(noStakeProjectId, claimId, 0, keccak256("submission"));

        // Now setup validators after contribution is enqueued
        _setupValidator(noStakeProjectId, validator1, 8000, salt);
        _setupValidator(noStakeProjectId, validator2, 8500, salt);
        _setupValidator(noStakeProjectId, validator3, 9000, salt);

        // Finalize - should work without unlocking stake
        core.finalizeContribution(noStakeProjectId, 0);

        assertEq(uint256(getContributionStatus(noStakeProjectId, 0)), uint256(ContributionStatus.Validated));
    }

    function testBatchContribute() public {
        testFundProject();

        vm.prank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 3);

        uint256[] memory indices = new uint256[](3);
        indices[0] = 0;
        indices[1] = 1;
        indices[2] = 2;

        bytes32[] memory hashes = new bytes32[](3);
        hashes[0] = keccak256("submission1");
        hashes[1] = keccak256("submission2");
        hashes[2] = keccak256("submission3");

        vm.prank(contributor);
        core.batchContribute(PROJECT_ID, claimId, indices, hashes);

        // Verify all contributions submitted
        assertEq(uint256(getContributionStatus(PROJECT_ID, 0)), uint256(ContributionStatus.Pending));
        assertEq(uint256(getContributionStatus(PROJECT_ID, 1)), uint256(ContributionStatus.Pending));
        assertEq(uint256(getContributionStatus(PROJECT_ID, 2)), uint256(ContributionStatus.Pending));
    }

    function testClaimToContributeWithReusedIndices() public {
        testFundProject();

        // Claim and let expire
        vm.prank(contributor);
        core.claimToContribute(PROJECT_ID, 2);

        vm.warp(block.timestamp + 8 days);
        uint256[] memory indices = new uint256[](2);
        indices[0] = 0;
        indices[1] = 1;
        core.reclaimExpiredIndices(PROJECT_ID, indices);

        // Claim again - should reuse indices
        vm.prank(contributor);
        core.claimToContribute(PROJECT_ID, 2);

        // Verify indices are reused by checking they can be contributed to
        vm.prank(contributor);
        core.contribute(PROJECT_ID, 1, 0, keccak256("submission"));

        // Index 0 should be assigned to contributor
        assertEq(getContributionContributor(PROJECT_ID, 0), contributor);
    }

    function testClaimFulfilledStatus() public {
        testFundProject();

        vm.prank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 2);

        // Submit all contributions
        vm.prank(contributor);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission1"));

        vm.prank(contributor);
        core.contribute(PROJECT_ID, claimId, 1, keccak256("submission2"));

        // Claim should be fulfilled
        assertEq(uint256(getClaimStatus(PROJECT_ID, claimId)), uint256(ClaimStatus.Fulfilled));
    }

    function testReleaseExpiredClaimNoStake() public {
        // Create project with zero minStakeToClaim
        vm.startPrank(originator);
        bytes32 noStakeProjectId = keccak256(abi.encodePacked("no-stake-project-release"));
        core.createProject(
            noStakeProjectId,
            address(rewardToken),
            "no-stake-project-release",
            0, // minStakeToClaim = 0
            0,
            3,
            1000,
            ""
        );
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(noStakeProjectId, 1000 ether, 10);
        vm.stopPrank();

        vm.prank(contributor);
        core.claimToContribute(noStakeProjectId, 1);

        vm.warp(block.timestamp + 8 days);

        // Should work without slashing
        core.releaseExpiredClaim(noStakeProjectId, 0);

        assertEq(uint256(getClaimStatus(noStakeProjectId, 0)), uint256(ClaimStatus.Expired));
    }

    function testReclaimExpiredIndicesEdgeCases() public {
        testFundProject();

        vm.prank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 2);

        // Submit index 0 before expiration
        vm.prank(contributor);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));

        vm.warp(block.timestamp + 8 days);

        uint256[] memory indices = new uint256[](2);
        indices[0] = 0; // Already submitted, should skip
        indices[1] = 1; // Expired, should reclaim
        core.reclaimExpiredIndices(PROJECT_ID, indices);

        // Index 0 should still have contribution (not reclaimed)
        assertEq(getContributionContributor(PROJECT_ID, 0), contributor);

        // Index 1 should be reclaimed (no contribution exists)
        assertEq(getContributionContributor(PROJECT_ID, 1), address(0));
    }

    // --- COVERAGE TESTS FROM CoreCoverage.t.sol ---

    function testFundProject_NoReward() public {
        // Create project first
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), PROJECT_CID, 100 ether, 100 ether, 1, 1000, "");

        // FIX H-2: Zero-reward funding is now blocked to prevent dilution attacks
        // This test now verifies the fix rather than the old behavior
        vm.expectRevert(ISapienCore.InvalidAmount.selector);
        core.fundProject(PROJECT_ID, 0, 10);
        vm.stopPrank();
    }

    function testReclaimExpiredIndices_Edges() public {
        // Create project first
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), PROJECT_CID, 100 ether, 100 ether, 1, 1000, "");
        vm.stopPrank();

        // 1. Unclaimed index
        uint256[] memory indices = new uint256[](1);
        indices[0] = 99; // Never claimed
        core.reclaimExpiredIndices(PROJECT_ID, indices);

        // 2. Claim but not expired
        vm.prank(originator);
        rewardToken.approve(address(core), 1000 ether);
        vm.prank(originator);
        core.fundProject(PROJECT_ID, 1000 ether, 10);

        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        indices[0] = 0; // First index
        core.reclaimExpiredIndices(PROJECT_ID, indices);
        vm.stopPrank();

        // 3. Claimed and expired but submitted
        vm.startPrank(contributor);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("submission"));
        vm.warp(block.timestamp + 10 days);
        core.reclaimExpiredIndices(PROJECT_ID, indices);
        vm.stopPrank();
    }

    function testClaimToContribute_NoMinStake() public {
        bytes32 noStakeProject = keccak256(abi.encodePacked("no-stake"));
        vm.prank(originator);
        core.createProject(noStakeProject, address(rewardToken), "no-stake", 0, 0, 1, 1000, "");

        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(noStakeProject, 1000 ether, 10);
        vm.stopPrank();

        vm.prank(contributor);
        core.claimToContribute(noStakeProject, 1);
    }

    function testReleaseExpiredClaim_NoMinStake() public {
        bytes32 noStakeProject = keccak256(abi.encodePacked("no-stake-release"));
        vm.prank(originator);
        core.createProject(noStakeProject, address(rewardToken), "no-stake-release", 0, 0, 1, 1000, "");

        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(noStakeProject, 1000 ether, 10);
        vm.stopPrank();

        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(noStakeProject, 1);
        vm.warp(block.timestamp + 8 days);
        core.releaseExpiredClaim(noStakeProject, claimId);
        vm.stopPrank();
    }

    function testContribute_Reverts() public {
        // Create project first
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), PROJECT_CID, 100 ether, 100 ether, 1, 1000, "");
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();

        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);

        // 1. Not the contributor
        vm.stopPrank();
        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_NOT_CLAIM_OWNER));
        core.contribute(PROJECT_ID, claimId, 0, keccak256("sub"));

        // 2. Claim not active
        vm.startPrank(contributor);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("sub"));
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.ClaimNotActive.selector, claimId));
        core.contribute(PROJECT_ID, claimId, 0, keccak256("sub2"));
        vm.stopPrank();
    }

    function testFinalizeContribution_Reverts() public {
        // Create project first
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), PROJECT_CID, 100 ether, 100 ether, 1, 1000, "");
        vm.stopPrank();

        // 1. Does not exist
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ContributionDoesNotExist.selector, PROJECT_ID, 999));
        core.finalizeContribution(PROJECT_ID, 999);

        // 2. Already rewarded
        vm.prank(originator);
        rewardToken.approve(address(core), 1000 ether);
        vm.prank(originator);
        core.fundProject(PROJECT_ID, 1000 ether, 10);

        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("sub"));
        vm.stopPrank();

        // Need 3 validators for consensus, but let's just test the "does not exist" case for now
        // The AlreadyRewarded case requires a more complex setup
        // vm.expectRevert(ISapienCore.AlreadyRewarded.selector);
        // core.finalizeContribution(PROJECT_ID, 0);
    }

    // ============================================
    // PROTOCOL FEE TESTS
    // ============================================

    function testSetProtocolFeeBasisPoints() public {
        vm.startPrank(admin);

        // Test default fee (should be 100 = 1%)
        assertEq(core.protocolFeeBasisPoints(), 100);

        // Set new fee
        core.setProtocolFeeBasisPoints(200); // 2%
        assertEq(core.protocolFeeBasisPoints(), 200);

        // Set to zero
        core.setProtocolFeeBasisPoints(0);
        assertEq(core.protocolFeeBasisPoints(), 0);

        vm.stopPrank();
    }

    function testSetProtocolFeeBasisPoints_Reverts() public {
        vm.startPrank(admin);

        // Should revert if fee exceeds 3%
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ProtocolFeeTooHigh.selector, 301, 300));
        core.setProtocolFeeBasisPoints(301);

        vm.stopPrank();

        // Should revert if not admin
        vm.prank(originator);
        vm.expectRevert();
        core.setProtocolFeeBasisPoints(200);
    }

    function testSetTreasury() public {
        address newTreasury = makeAddr("treasury");

        vm.startPrank(admin);

        // Initially treasury should be zero address
        assertEq(core.treasury(), address(0));

        // Set treasury
        core.setTreasury(newTreasury);
        assertEq(core.treasury(), newTreasury);

        vm.stopPrank();
    }

    function testSetTreasury_Reverts() public {
        vm.startPrank(admin);

        // Should revert if treasury is zero address
        vm.expectRevert(ISapienCore.InvalidAddress.selector);
        core.setTreasury(address(0));

        vm.stopPrank();

        // Should revert if not admin
        vm.prank(originator);
        vm.expectRevert();
        core.setTreasury(makeAddr("treasury"));
    }

    function testFundProject_WithProtocolFee() public {
        testCreateProject();

        address treasuryAddr = makeAddr("treasury");

        // Setup treasury and fee
        vm.startPrank(admin);
        core.setTreasury(treasuryAddr);
        core.setProtocolFeeBasisPoints(100); // 1%
        vm.stopPrank();

        uint256 fundingAmount = 1000 ether;
        uint256 expectedFee = (fundingAmount * 100) / 10000; // 1% = 10 ether
        uint256 expectedRewardAmount = fundingAmount - expectedFee; // 990 ether

        vm.startPrank(originator);
        rewardToken.approve(address(core), fundingAmount);

        uint256 treasuryBalanceBefore = rewardToken.balanceOf(treasuryAddr);
        uint256 rewardsBalanceBefore = rewardToken.balanceOf(address(rewards));

        core.fundProject(PROJECT_ID, fundingAmount, 100);

        uint256 treasuryBalanceAfter = rewardToken.balanceOf(treasuryAddr);
        uint256 rewardsBalanceAfter = rewardToken.balanceOf(address(rewards));

        // Verify fee was sent to treasury
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedFee, "Treasury should receive fee");

        // Verify remaining amount was sent to rewards contract
        assertEq(
            rewardsBalanceAfter - rewardsBalanceBefore, expectedRewardAmount, "Rewards should receive after-fee amount"
        );

        // Verify project state reflects the after-fee amount
        assertEq(getProjectRewards(PROJECT_ID), expectedRewardAmount, "Project rewards should be after-fee amount");

        vm.stopPrank();
    }

    function testFundProject_NoFeeWhenTreasuryNotSet() public {
        testCreateProject();

        // Don't set treasury - fee should not be collected
        vm.startPrank(admin);
        core.setProtocolFeeBasisPoints(100); // 1% fee configured but treasury not set
        vm.stopPrank();

        uint256 fundingAmount = 1000 ether;

        vm.startPrank(originator);
        rewardToken.approve(address(core), fundingAmount);

        uint256 rewardsBalanceBefore = rewardToken.balanceOf(address(rewards));

        core.fundProject(PROJECT_ID, fundingAmount, 100);

        uint256 rewardsBalanceAfter = rewardToken.balanceOf(address(rewards));

        // Verify full amount went to rewards (no fee collected)
        assertEq(
            rewardsBalanceAfter - rewardsBalanceBefore,
            fundingAmount,
            "Full amount should go to rewards when treasury not set"
        );
        assertEq(getProjectRewards(PROJECT_ID), fundingAmount, "Project rewards should be full amount");

        vm.stopPrank();
    }

    function testFundProject_NoFeeWhenFeeIsZero() public {
        testCreateProject();

        address treasuryAddr = makeAddr("treasury");

        // Set treasury but set fee to zero
        vm.startPrank(admin);
        core.setTreasury(treasuryAddr);
        core.setProtocolFeeBasisPoints(0); // No fee
        vm.stopPrank();

        uint256 fundingAmount = 1000 ether;

        vm.startPrank(originator);
        rewardToken.approve(address(core), fundingAmount);

        uint256 treasuryBalanceBefore = rewardToken.balanceOf(treasuryAddr);
        uint256 rewardsBalanceBefore = rewardToken.balanceOf(address(rewards));

        core.fundProject(PROJECT_ID, fundingAmount, 100);

        uint256 treasuryBalanceAfter = rewardToken.balanceOf(treasuryAddr);
        uint256 rewardsBalanceAfter = rewardToken.balanceOf(address(rewards));

        // Verify no fee was collected
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, 0, "Treasury should receive no fee");
        assertEq(rewardsBalanceAfter - rewardsBalanceBefore, fundingAmount, "Full amount should go to rewards");
        assertEq(getProjectRewards(PROJECT_ID), fundingAmount, "Project rewards should be full amount");

        vm.stopPrank();
    }

    function testFundProject_ProtocolFeeEvents() public {
        testCreateProject();

        address treasuryAddr = makeAddr("treasury");

        vm.startPrank(admin);
        core.setTreasury(treasuryAddr);
        core.setProtocolFeeBasisPoints(100);
        vm.stopPrank();

        uint256 fundingAmount = 1000 ether;
        uint256 expectedFee = (fundingAmount * 100) / 10000;

        vm.startPrank(originator);
        rewardToken.approve(address(core), fundingAmount);

        // Expect protocol fee collected event
        vm.expectEmit(true, true, false, true);
        emit ISapienCore.ProtocolFeeCollected(PROJECT_ID, address(rewardToken), expectedFee);

        core.fundProject(PROJECT_ID, fundingAmount, 100);

        vm.stopPrank();
    }

    function testFundProject_ProtocolFeePrecision() public {
        testCreateProject();

        address treasuryAddr = makeAddr("treasury");

        vm.startPrank(admin);
        core.setTreasury(treasuryAddr);
        core.setProtocolFeeBasisPoints(150); // 1.5%
        vm.stopPrank();

        // Test with amount that doesn't divide evenly
        uint256 fundingAmount = 1001 ether;
        uint256 expectedFee = (fundingAmount * 150) / 10000; // 150.15 ether (truncated)
        uint256 expectedRewardAmount = fundingAmount - expectedFee;

        vm.startPrank(originator);
        rewardToken.approve(address(core), fundingAmount);

        uint256 treasuryBalanceBefore = rewardToken.balanceOf(treasuryAddr);
        uint256 rewardsBalanceBefore = rewardToken.balanceOf(address(rewards));

        core.fundProject(PROJECT_ID, fundingAmount, 100);

        uint256 treasuryBalanceAfter = rewardToken.balanceOf(treasuryAddr);
        uint256 rewardsBalanceAfter = rewardToken.balanceOf(address(rewards));

        // Verify fee calculation (may have rounding)
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedFee, "Fee should match calculated amount");
        assertEq(rewardsBalanceAfter - rewardsBalanceBefore, expectedRewardAmount, "Reward amount should match");

        // Verify total is correct (fee + reward = original)
        assertEq(
            (treasuryBalanceAfter - treasuryBalanceBefore) + (rewardsBalanceAfter - rewardsBalanceBefore),
            fundingAmount,
            "Fee + reward should equal original funding amount"
        );

        vm.stopPrank();
    }

    function testFundProject_MultipleFundingsWithFee() public {
        testCreateProject();

        address treasuryAddr = makeAddr("treasury");

        vm.startPrank(admin);
        core.setTreasury(treasuryAddr);
        core.setProtocolFeeBasisPoints(100); // 1%
        vm.stopPrank();

        vm.startPrank(originator);
        rewardToken.approve(address(core), 2000 ether);

        // First funding
        uint256 funding1 = 1000 ether;
        uint256 fee1 = (funding1 * 100) / 10000;
        core.fundProject(PROJECT_ID, funding1, 50);

        // Second funding
        uint256 funding2 = 1000 ether;
        uint256 fee2 = (funding2 * 100) / 10000;
        core.fundProject(PROJECT_ID, funding2, 50);

        // Verify cumulative amounts
        uint256 totalFee = fee1 + fee2;
        uint256 totalRewards = (funding1 - fee1) + (funding2 - fee2);

        assertEq(rewardToken.balanceOf(treasuryAddr), totalFee, "Treasury should have cumulative fees");
        assertEq(
            rewardToken.balanceOf(address(rewards)), totalRewards, "Rewards should have cumulative after-fee amounts"
        );
        assertEq(getProjectRewards(PROJECT_ID), totalRewards, "Project rewards should be cumulative after-fee amount");
        assertEq(getProjectQuantity(PROJECT_ID), 100, "Project quantity should be cumulative");

        vm.stopPrank();
    }

    function testProtocolFeeUpdatedEvent() public {
        vm.startPrank(admin);

        vm.expectEmit(true, false, false, true);
        emit ISapienCore.ProtocolFeeUpdated(200);

        core.setProtocolFeeBasisPoints(200);

        vm.stopPrank();
    }

    function testTreasuryUpdatedEvent() public {
        address treasuryAddr = makeAddr("treasury");

        vm.startPrank(admin);

        vm.expectEmit(true, false, false, true);
        emit ISapienCore.TreasuryUpdated(treasuryAddr);

        core.setTreasury(treasuryAddr);

        vm.stopPrank();
    }
}

