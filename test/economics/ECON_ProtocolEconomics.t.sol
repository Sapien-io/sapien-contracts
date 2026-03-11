// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus, StakeAccount} from "src/Types.sol";

/// @title Economics Scenarios (2026-02-23)
/// @notice Verifies protocol fund-flow behavior for originator, contributor,
///         validator, and adapter actions.
contract ECON_ProtocolEconomics is BaseTest {
    uint256 internal constant DEFAULT_PROTOCOL_FEE_BPS = 1000; // 10%
    string internal constant ECON_DATA_OUTPUT_PATH = "test/economics/economics-model-data.json";
    string internal constant ECON_SUMMARY_OUTPUT_PATH = "test/economics/economics-model-summary.md";

    struct ProtocolSimulation {
        uint256 projectsFunded;
        uint256 contributionsSubmitted;
        uint256 acceptedContributions;
        uint256 rejectedContributions;
        uint256 validatorSettlements;
        uint256 expiredCommitmentSlashes;
        uint256 rewardClaims;
        uint256 fundingAmount;
        uint256 protocolFeeCollected;
        uint256 originationFeeAccrued;
        uint256 escrowAfterFunding;
        uint256 acceptedRewardRate;
        uint256 contributorPendingAfterAccepted;
        uint256 validatorPendingAfterAccepted;
        uint256 adapterPendingAfterAccepted;
        uint256 contributorClaimed;
        uint256 validatorClaimed;
        uint256 adapterClaimed;
        uint256 contributorSlashAmount;
        uint256 validatorSlashShares;
        uint256 escrowBeforeRefund;
        uint256 originatorRefundAmount;
        uint256 remainingEscrowAfterRefund;
    }

    struct ProjectionData {
        uint256[5] enterpriseValidations;
        uint256[5] platformValidations;
        uint256[5] enterpriseRevenueUsd;
        uint256[5] platformRevenueUsd;
        uint256[5] gtvUsd;
        uint256[5] feeRevenueUsd;
        uint256[5] operatingCostsUsd;
        int256[5] operatingIncomeUsd;
    }

    function testECON_fundingWaterfallRoutesProtocolAndOriginationFees() public {
        uint256 originatorBalanceBefore = token.balanceOf(originator);
        uint256 treasuryBalanceBefore = token.balanceOf(treasury);

        bytes32 projectId = _createAndFundProject();

        (uint256 protocolFee, uint256 originationFee, uint256 escrowAmount) = _expectedFundingSplit(FUND_AMOUNT);
        Project memory proj = engine.getProject(projectId);

        assertEq(
            originatorBalanceBefore - token.balanceOf(originator),
            FUND_AMOUNT,
            "originator should transfer full funding amount"
        );
        assertEq(token.balanceOf(treasury) - treasuryBalanceBefore, protocolFee, "treasury should receive protocol fee");
        assertEq(
            engine.getPendingRewards(adapter, address(token)), originationFee, "adapter should accrue origination fee"
        );
        assertEq(
            engine.getProjectEscrow(projectId, address(token)), escrowAmount, "escrow should hold net funded amount"
        );
        assertEq(proj.totalRewards, escrowAmount, "project totalRewards should match escrow net amount");
    }

    function testECON_acceptedContributionSplitsRewardsAcrossRolesAndAdapter() public {
        (bytes32 projectId, uint256 index, uint256 nonce, uint256 rewardRate, uint256 escrowAfterFunding) =
            _setupAcceptedSingleContributionWithAdapters();

        Contribution memory contrib = engine.getContribution(projectId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted), "contribution should be accepted");

        _settleAllAndReleaseContributor(projectId, index, nonce);

        Project memory proj = engine.getProject(projectId);
        (, uint256 contributionFeeBps, uint256 validationFeeBps) = engine.getAdapterFees();

        uint256 contributorShare = (rewardRate * (C.BPS - proj.validatorRewardBps)) / C.BPS;
        uint256 contributorAdapterFee = (contributorShare * contributionFeeBps) / C.BPS;
        uint256 contributorNet = contributorShare - contributorAdapterFee;

        uint256 grossPerValidator = (proj.totalRewards * proj.validatorRewardBps) / (C.BPS * proj.totalQuantity * 3);
        uint256 validationAdapterFeePerValidator = (grossPerValidator * validationFeeBps) / C.BPS;
        uint256 validatorNet = grossPerValidator - validationAdapterFeePerValidator;

        (, uint256 originationFee,) = _expectedFundingSplit(FUND_AMOUNT);
        uint256 expectedAdapterPending = originationFee + contributorAdapterFee + (validationAdapterFeePerValidator * 3);

        assertEq(
            engine.getPendingRewards(contributor1, address(token)), contributorNet, "contributor net reward mismatch"
        );
        assertEq(engine.getPendingRewards(validator1, address(token)), validatorNet, "validator1 net reward mismatch");
        assertEq(engine.getPendingRewards(validator2, address(token)), validatorNet, "validator2 net reward mismatch");
        assertEq(engine.getPendingRewards(validator3, address(token)), validatorNet, "validator3 net reward mismatch");
        assertEq(engine.getPendingRewards(adapter, address(token)), expectedAdapterPending, "adapter pending mismatch");
        assertEq(
            engine.getProjectEscrow(projectId, address(token)),
            escrowAfterFunding - rewardRate,
            "escrow should decrease by exactly one rewardRate"
        );
    }

    function testECON_pendingRewardsCanBeClaimedByContributorValidatorAndAdapter() public {
        (bytes32 projectId, uint256 index, uint256 nonce,,) = _setupAcceptedSingleContributionWithAdapters();
        _settleAllAndReleaseContributor(projectId, index, nonce);

        uint256 contributorPending = engine.getPendingRewards(contributor1, address(token));
        uint256 validatorPending = engine.getPendingRewards(validator1, address(token));
        uint256 adapterPending = engine.getPendingRewards(adapter, address(token));

        assertGt(contributorPending, 0, "contributor should have pending rewards");
        assertGt(validatorPending, 0, "validator should have pending rewards");
        assertGt(adapterPending, 0, "adapter should have pending rewards");

        uint256 contributorBalanceBefore = token.balanceOf(contributor1);
        vm.prank(contributor1);
        engine.claimReward(address(token));
        assertEq(
            token.balanceOf(contributor1) - contributorBalanceBefore,
            contributorPending,
            "contributor wallet delta mismatch"
        );
        assertEq(engine.getPendingRewards(contributor1, address(token)), 0, "contributor pending should be cleared");

        uint256 validatorBalanceBefore = token.balanceOf(validator1);
        vm.prank(validator1);
        engine.claimReward(address(token));
        assertEq(
            token.balanceOf(validator1) - validatorBalanceBefore, validatorPending, "validator wallet delta mismatch"
        );
        assertEq(engine.getPendingRewards(validator1, address(token)), 0, "validator pending should be cleared");

        uint256 adapterBalanceBefore = token.balanceOf(adapter);
        vm.prank(adapter);
        engine.claimReward(address(token));
        assertEq(token.balanceOf(adapter) - adapterBalanceBefore, adapterPending, "adapter wallet delta mismatch");
        assertEq(engine.getPendingRewards(adapter, address(token)), 0, "adapter pending should be cleared");
    }

    function testECON_rejectedContributionSlashesContributorAndRecyclesSlot() public {
        bytes32 projectId = _createAndFundProject();
        uint256 escrowAfterFunding = engine.getProjectEscrow(projectId, address(token));

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 index = indices[0];

        StakeAccount memory contributorBefore = vault.getStakeAccount(contributor1);
        assertEq(contributorBefore.contributorLock, STAKE_AMOUNT, "contributor lock should be present pre-consensus");

        _claimCommitReveal(validator1, projectId, index, 1000, VALIDATOR_STAKE, address(0));
        _claimCommitReveal(validator2, projectId, index, 1000, VALIDATOR_STAKE, address(0));
        _claimCommitReveal(validator3, projectId, index, 1000, VALIDATOR_STAKE, address(0));

        engine.computeConsensus(projectId, index);

        Contribution memory contrib = engine.getContribution(projectId, index);
        Project memory proj = engine.getProject(projectId);
        StakeAccount memory contributorAfter = vault.getStakeAccount(contributor1);

        assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected), "contribution should be rejected");
        assertEq(contributorAfter.contributorLock, 0, "rejected contribution should slash contributor lock");
        assertEq(proj.availableSlots, QUANTITY, "rejected slot should return to project availability");
        assertEq(engine.getSubmissionNonce(projectId, index), 1, "rejected contribution should advance nonce");
        assertEq(
            engine.getPendingRewards(contributor1, address(token)), 0, "rejected contribution should not pay rewards"
        );
        assertEq(
            engine.getProjectEscrow(projectId, address(token)), escrowAfterFunding, "rejection should not reduce escrow"
        );

        vm.expectRevert(ISapienCore.ContributionNotAccepted.selector);
        engine.releaseContributorReward(projectId, index);
    }

    function testECON_expiredCommitmentSlashesValidatorStake() public {
        bytes32 projectId = _createAndFundProject();
        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 index = indices[0];

        uint256 stakeAmount = VALIDATOR_STAKE;
        uint256 totalStakedBefore = vault.totalStaked(validator1);
        uint256 sharesBefore = vault.balanceOf(validator1);
        uint256 expectedShareLoss = vault.convertToShares(stakeAmount);

        bytes32 commitHash = keccak256(abi.encodePacked("economic-unrevealed", validator1, projectId, index));

        vm.startPrank(validator1);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(stakeAmount);
        engine.commitValidation(projectId, index, commitHash, stakeAmount, address(0));
        vm.stopPrank();

        StakeAccount memory afterCommit = vault.getStakeAccount(validator1);
        assertEq(afterCommit.inFlight, stakeAmount, "stake should move to inFlight after commit");
        assertEq(afterCommit.validatorCapacity, 0, "committed amount should leave validator capacity");

        vm.warp(block.timestamp + engine.commitDeadline() + engine.revealDeadline() + 1);
        engine.cancelExpiredCommitment(projectId, index, validator1);

        StakeAccount memory afterSlash = vault.getStakeAccount(validator1);
        uint256 totalStakedAfter = vault.totalStaked(validator1);
        uint256 sharesAfter = vault.balanceOf(validator1);

        assertEq(afterSlash.inFlight, 0, "expired unrevealed commitment should clear inFlight");
        assertEq(afterSlash.validatorCapacity, 0, "validator capacity should remain zero after full slash");
        assertEq(sharesBefore - sharesAfter, expectedShareLoss, "validator share burn mismatch");
        assertLt(totalStakedAfter, totalStakedBefore, "validator totalStaked should decrease after slash");
        assertEq(engine.getPendingRewards(validator1, address(token)), 0, "slashed validator should not earn reward");
    }

    function testECON_originatorCanRecoverUnusedEscrowAfterCompletion() public {
        (bytes32 projectId, uint256 index, uint256 nonce, uint256 rewardRate,) =
            _setupAcceptedSingleContributionWithAdapters();
        _settleAllAndReleaseContributor(projectId, index, nonce);

        vm.prank(originator);
        engine.completeProject(projectId);

        Project memory proj = engine.getProject(projectId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Completed), "project should be completed");

        uint256 escrowBeforeRefund = engine.getProjectEscrow(projectId, address(token));
        uint256 expectedRemaining = proj.totalRewards - rewardRate;
        assertEq(escrowBeforeRefund, expectedRemaining, "remaining escrow mismatch before refund");

        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);

        uint256 originatorBalanceBefore = token.balanceOf(originator);
        vm.prank(originator);
        engine.refundEscrow(projectId);

        assertEq(
            token.balanceOf(originator) - originatorBalanceBefore,
            escrowBeforeRefund,
            "originator refund amount mismatch"
        );
        assertEq(engine.getProjectEscrow(projectId, address(token)), 0, "escrow should be drained after refund");
    }

    function testECON_generateRevenueModelDataFile() public {
        // Ensure this run can fund multiple projects for simulation scenarios.
        token.mint(originator, FUND_AMOUNT * 5);

        ProjectionData memory projection = _computeProjectionData();
        ProtocolSimulation memory simulation = _runProtocolActivitySimulation();

        string memory jsonData = _buildRevenueModelJson(projection, simulation);
        vm.writeFile(ECON_DATA_OUTPUT_PATH, jsonData);

        string memory summary = _buildSummaryMarkdown(projection, simulation);
        vm.writeFile(ECON_SUMMARY_OUTPUT_PATH, summary);

        assertGt(bytes(vm.readFile(ECON_DATA_OUTPUT_PATH)).length, 0, "expected economics JSON output");
        assertGt(bytes(vm.readFile(ECON_SUMMARY_OUTPUT_PATH)).length, 0, "expected economics summary output");
        assertEq(simulation.remainingEscrowAfterRefund, 0, "accepted project escrow should be fully refunded");
    }

    function _setupAcceptedSingleContributionWithAdapters()
        internal
        returns (bytes32 projectId, uint256 index, uint256 nonce, uint256 rewardRate, uint256 escrowAfterFunding)
    {
        projectId = _createAndFundProject();
        escrowAfterFunding = engine.getProjectEscrow(projectId, address(token));

        (, uint256[] memory contributedIndices) = _claimAndContribute(contributor1, projectId, 1);
        index = contributedIndices[0];

        _claimCommitReveal(validator1, projectId, index, 8000, VALIDATOR_STAKE, adapter);
        _claimCommitReveal(validator2, projectId, index, 8000, VALIDATOR_STAKE, adapter);
        _claimCommitReveal(validator3, projectId, index, 8000, VALIDATOR_STAKE, adapter);

        engine.computeConsensus(projectId, index);

        Contribution memory contrib = engine.getContribution(projectId, index);
        rewardRate = contrib.rewardRate;
        nonce = engine.getSubmissionNonce(projectId, index);
    }

    function _settleAllAndReleaseContributor(bytes32 projectId, uint256 index, uint256 nonce) internal {
        vm.warp(block.timestamp + engine.challengePeriod() + 1);

        vm.prank(validator1);
        engine.settleValidator(projectId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projectId, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(projectId, index, nonce);

        engine.releaseContributorReward(projectId, index);
    }

    function _claimCommitReveal(
        address validator,
        bytes32 projectId,
        uint256 index,
        uint256 score,
        uint256 stakeAmount,
        address validationAdapter
    ) internal {
        bytes32 salt = keccak256(abi.encodePacked("econ-salt", validator, projectId, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.startPrank(validator);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(stakeAmount);
        engine.commitValidation(projectId, index, commitHash, stakeAmount, validationAdapter);
        vm.stopPrank();

        // Warp past commit deadline to allow reveals
        vm.warp(block.timestamp + engine.commitDeadline());

        vm.prank(validator);
        engine.revealValidation(projectId, index, score, salt);
    }

    function _runProtocolActivitySimulation() internal returns (ProtocolSimulation memory sim) {
        uint256 treasuryBefore = token.balanceOf(treasury);
        uint256 adapterPendingBeforeFunding = engine.getPendingRewards(adapter, address(token));

        (
            bytes32 acceptedProjectId,
            uint256 acceptedIndex,
            uint256 acceptedNonce,
            uint256 rewardRate,
            uint256 escrowAfterFunding
        ) = _setupAcceptedSingleContributionWithAdapters();
        sim.projectsFunded = 1;
        sim.contributionsSubmitted = 1;
        sim.fundingAmount = FUND_AMOUNT;
        sim.protocolFeeCollected = token.balanceOf(treasury) - treasuryBefore;
        sim.originationFeeAccrued = engine.getPendingRewards(adapter, address(token)) - adapterPendingBeforeFunding;
        sim.escrowAfterFunding = escrowAfterFunding;
        sim.acceptedRewardRate = rewardRate;

        _settleAllAndReleaseContributor(acceptedProjectId, acceptedIndex, acceptedNonce);
        sim.acceptedContributions = 1;
        sim.validatorSettlements = 3;
        sim.contributorPendingAfterAccepted = engine.getPendingRewards(contributor1, address(token));
        sim.validatorPendingAfterAccepted = engine.getPendingRewards(validator1, address(token));
        sim.adapterPendingAfterAccepted = engine.getPendingRewards(adapter, address(token));

        sim.contributorClaimed = _claimAllPending(contributor1);
        sim.validatorClaimed = _claimAllPending(validator1);
        sim.adapterClaimed = _claimAllPending(adapter);
        sim.rewardClaims = 3;

        bytes32 rejectedProjectId = keccak256("econ-rejected-project");
        _createAndFundProject(rejectedProjectId, FUND_AMOUNT, QUANTITY);
        sim.projectsFunded++;

        (, uint256[] memory rejectedIndices) = _claimAndContribute(contributor2, rejectedProjectId, 1);
        sim.contributionsSubmitted++;
        uint256 rejectedIndex = rejectedIndices[0];
        uint256 contributorLockBefore = vault.getStakeAccount(contributor2).contributorLock;

        _claimCommitReveal(validator1, rejectedProjectId, rejectedIndex, 1000, VALIDATOR_STAKE, address(0));
        _claimCommitReveal(validator2, rejectedProjectId, rejectedIndex, 1000, VALIDATOR_STAKE, address(0));
        _claimCommitReveal(validator3, rejectedProjectId, rejectedIndex, 1000, VALIDATOR_STAKE, address(0));
        engine.computeConsensus(rejectedProjectId, rejectedIndex);

        sim.rejectedContributions = 1;
        sim.contributorSlashAmount = contributorLockBefore - vault.getStakeAccount(contributor2).contributorLock;

        bytes32 nonRevealProjectId = keccak256("econ-nonreveal-project");
        _createAndFundProject(nonRevealProjectId, FUND_AMOUNT, QUANTITY);
        sim.projectsFunded++;

        (, uint256[] memory nonRevealIndices) = _claimAndContribute(contributor1, nonRevealProjectId, 1);
        sim.contributionsSubmitted++;
        uint256 nonRevealIndex = nonRevealIndices[0];
        uint256 validatorSharesBefore = vault.balanceOf(validator2);

        bytes32 commitHash =
            keccak256(abi.encodePacked("economic-unrevealed", validator2, nonRevealProjectId, nonRevealIndex));

        vm.startPrank(validator2);
        engine.claimToValidate(nonRevealProjectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(nonRevealProjectId, nonRevealIndex, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        vm.warp(block.timestamp + engine.commitDeadline() + engine.revealDeadline() + 1);
        engine.cancelExpiredCommitment(nonRevealProjectId, nonRevealIndex, validator2);

        sim.expiredCommitmentSlashes = 1;
        sim.validatorSlashShares = validatorSharesBefore - vault.balanceOf(validator2);

        vm.prank(originator);
        engine.completeProject(acceptedProjectId);
        sim.escrowBeforeRefund = engine.getProjectEscrow(acceptedProjectId, address(token));

        vm.warp(block.timestamp + C.PROJECT_COMPLETION_DELAY + 1);
        uint256 originatorBalanceBefore = token.balanceOf(originator);
        vm.prank(originator);
        engine.refundEscrow(acceptedProjectId);
        sim.originatorRefundAmount = token.balanceOf(originator) - originatorBalanceBefore;
        sim.remainingEscrowAfterRefund = engine.getProjectEscrow(acceptedProjectId, address(token));
    }

    function _claimAllPending(address user) internal returns (uint256 claimed) {
        claimed = engine.getPendingRewards(user, address(token));
        if (claimed == 0) return 0;

        uint256 balanceBefore = token.balanceOf(user);
        vm.prank(user);
        engine.claimReward(address(token));
        assertEq(token.balanceOf(user) - balanceBefore, claimed, "claimed amount mismatch");
    }

    function _computeProjectionData() internal pure returns (ProjectionData memory data) {
        uint256[5] memory enterpriseValsM = [uint256(3), uint256(31), uint256(138), uint256(0), uint256(0)];
        uint256[5] memory enterpriseNrrBps =
            [uint256(14_000), uint256(16_000), uint256(17_000), uint256(15_000), uint256(14_000)];
        uint256[5] memory enterprisePriceCents = [uint256(25), uint256(20), uint256(15), uint256(12), uint256(10)];
        uint256[5] memory platformPriceCents = [uint256(5), uint256(4), uint256(3), uint256(3), uint256(2)];
        uint256[5] memory blendedTakeRateBps =
            [uint256(1_500), uint256(1_310), uint256(1_200), uint256(1_130), uint256(1_110)];
        uint256[5] memory operatingCosts =
            [uint256(3_500_000), uint256(4_250_000), uint256(4_500_000), uint256(4_750_000), uint256(5_000_000)];

        enterpriseValsM[3] = (enterpriseValsM[2] * enterpriseNrrBps[3]) / C.BPS;
        enterpriseValsM[4] = (enterpriseValsM[3] * enterpriseNrrBps[4]) / C.BPS;

        _fillProjectionValidations(data, enterpriseValsM);

        for (uint256 i; i < 5; ++i) {
            data.enterpriseRevenueUsd[i] = (data.enterpriseValidations[i] * enterprisePriceCents[i]) / 100;
            data.platformRevenueUsd[i] = (data.platformValidations[i] * platformPriceCents[i]) / 100;
            data.gtvUsd[i] = data.enterpriseRevenueUsd[i] + data.platformRevenueUsd[i];
            data.feeRevenueUsd[i] = (data.gtvUsd[i] * blendedTakeRateBps[i]) / C.BPS;
            data.operatingCostsUsd[i] = operatingCosts[i];
            data.operatingIncomeUsd[i] =
                int256(data.feeRevenueUsd[i] + (i == 0 ? 375_000 : 0)) - int256(operatingCosts[i]);
        }
    }

    function _fillProjectionValidations(ProjectionData memory data, uint256[5] memory enterpriseValsM) internal pure {
        uint256[5] memory registeredDevelopers =
            [uint256(900), uint256(17_500), uint256(64_000), uint256(158_000), uint256(330_000)];
        uint256[5] memory activationBps =
            [uint256(2_000), uint256(3_000), uint256(3_500), uint256(3_800), uint256(4_000)];
        uint256[5] memory monthlyValidations =
            [uint256(1_000), uint256(5_000), uint256(6_000), uint256(8_000), uint256(10_000)];

        for (uint256 i; i < 5; ++i) {
            uint256 ev = enterpriseValsM[i] * 1_000_000;
            if (i == 0) ev = (ev * 4_000) / C.BPS;

            uint256 pv = ((registeredDevelopers[i] * activationBps[i]) / C.BPS) * monthlyValidations[i] * 12;
            if (i == 0) pv = (pv * 4_000) / C.BPS;

            data.enterpriseValidations[i] = ev;
            data.platformValidations[i] = pv;
        }
    }

    function _buildRevenueModelJson(ProjectionData memory projection, ProtocolSimulation memory sim)
        internal
        view
        returns (string memory result)
    {
        result = string(
            abi.encodePacked(
                "{\n",
                '  "title": "SAPIEN PoQ - Revenue Model Assumptions",\n',
                '  "currency": "USD",\n',
                '  "cadUsd": "0.72",\n'
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '  "legend": {"INPUT":"hardcoded assumption","FORMULA":"calculated","LINK":"cross-section reference"},\n',
                '  "A_feeStructure": {\n',
                '    "protocolFeePct": ["10.0","10.0","10.0","10.0","10.0"],\n'
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '    "originatorFeePct": ["4.0","4.0","3.5","3.0","3.0"],\n',
                '    "contributorClaimFeePct": ["3.0","3.0","3.0","3.0","3.0"],\n',
                '    "validatorClaimFeePct": ["3.0","3.0","3.0","3.0","3.0"],\n'
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '    "validatorRewardSharePct": ["10.0","10.0","10.0","10.0","10.0"],\n',
                '    "sapienRoutedVolumePct": ["80","50","35","25","20"],\n',
                '    "blendedTakeRatePct": ["15.0","13.1","12.0","11.3","11.1"]\n',
                "  },\n"
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '  "B_pricing": {"enterpriseUsdPerValidation":["0.25","0.20","0.15","0.12","0.10"],"platformUsdPerValidation":["0.05","0.04","0.03","0.03","0.02"]},\n',
                '  "C_enterpriseTotalsM": {"year1":3,"year2":31,"year3":138},\n'
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '  "D_registeredDevelopers": [900,17500,64000,158000,330000],\n',
                '  "E_activationAndUsage": {"activationPct":["20","30","35","38","40"],"avgMonthlyValidations":[1000,5000,6000,8000,10000]},\n'
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '  "F_operationsAndGtm": {"rampFactorY1Pct":"40","enterpriseNrr":["1.4","1.6","1.7","1.5","1.4"],',
                '"operatingCostsUsd":[3500000,4250000,4500000,4750000,5000000],"seedFundingUsdY1":375000},\n'
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '  "G_tokenAndEcosystem": {"tokenPriceUsd":["0.08","0.10","0.20","0.30","0.80"],',
                '"sapienTreasuryStakedM":[40,60,75,85,90],"totalVaultStakeM":[100,200,400,600,800],'
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '"validatorSlashingRatePct":["8.0","6.0","5.0","4.0","3.0"],"avgSlashSeverityPct":["25","25","20","20","15"],',
                '"sapienValidatorShareOfGtvPct":["25","15","10","8","5"]},\n'
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '  "H_projectionOutputs": {\n',
                '    "enterpriseValidations": ',
                _uintArrayToJson(projection.enterpriseValidations),
                ",\n",
                '    "platformValidations": ',
                _uintArrayToJson(projection.platformValidations),
                ",\n"
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '    "enterpriseRevenueUsd": ',
                _uintArrayToJson(projection.enterpriseRevenueUsd),
                ",\n",
                '    "platformRevenueUsd": ',
                _uintArrayToJson(projection.platformRevenueUsd),
                ",\n"
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '    "gtvUsd": ',
                _uintArrayToJson(projection.gtvUsd),
                ",\n",
                '    "feeRevenueUsd": ',
                _uintArrayToJson(projection.feeRevenueUsd),
                ",\n"
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '    "operatingCostsUsd": ',
                _uintArrayToJson(projection.operatingCostsUsd),
                ",\n",
                '    "operatingIncomeUsd": ',
                _intArrayToJson(projection.operatingIncomeUsd),
                "\n",
                "  },\n"
            )
        );
        result = string(
            abi.encodePacked(
                result,
                '  "protocolSimulation": ',
                _simulationJson(sim),
                ",\n",
                '  "generatedAtBlockTimestamp": ',
                vm.toString(block.timestamp),
                "\n",
                "}\n"
            )
        );
    }

    function _simulationJson(ProtocolSimulation memory sim) internal pure returns (string memory result) {
        result = string(
            abi.encodePacked(
                '{"projectsFunded":',
                vm.toString(sim.projectsFunded),
                ',"contributionsSubmitted":',
                vm.toString(sim.contributionsSubmitted),
                ',"acceptedContributions":',
                vm.toString(sim.acceptedContributions),
                ',"rejectedContributions":',
                vm.toString(sim.rejectedContributions)
            )
        );
        result = string(
            abi.encodePacked(
                result,
                ',"validatorSettlements":',
                vm.toString(sim.validatorSettlements),
                ',"expiredCommitmentSlashes":',
                vm.toString(sim.expiredCommitmentSlashes),
                ',"rewardClaims":',
                vm.toString(sim.rewardClaims),
                ',"fundingAmountWei":',
                vm.toString(sim.fundingAmount)
            )
        );
        result = string(
            abi.encodePacked(
                result,
                ',"protocolFeeCollectedWei":',
                vm.toString(sim.protocolFeeCollected),
                ',"originationFeeAccruedWei":',
                vm.toString(sim.originationFeeAccrued),
                ',"escrowAfterFundingWei":',
                vm.toString(sim.escrowAfterFunding),
                ',"acceptedRewardRateWei":',
                vm.toString(sim.acceptedRewardRate)
            )
        );
        result = string(
            abi.encodePacked(
                result,
                ',"contributorPendingAfterAcceptedWei":',
                vm.toString(sim.contributorPendingAfterAccepted),
                ',"validatorPendingAfterAcceptedWei":',
                vm.toString(sim.validatorPendingAfterAccepted),
                ',"adapterPendingAfterAcceptedWei":',
                vm.toString(sim.adapterPendingAfterAccepted)
            )
        );
        result = string(
            abi.encodePacked(
                result,
                ',"contributorClaimedWei":',
                vm.toString(sim.contributorClaimed),
                ',"validatorClaimedWei":',
                vm.toString(sim.validatorClaimed),
                ',"adapterClaimedWei":',
                vm.toString(sim.adapterClaimed)
            )
        );
        result = string(
            abi.encodePacked(
                result,
                ',"contributorSlashAmountWei":',
                vm.toString(sim.contributorSlashAmount),
                ',"validatorSlashShares":',
                vm.toString(sim.validatorSlashShares),
                ',"escrowBeforeRefundWei":',
                vm.toString(sim.escrowBeforeRefund)
            )
        );
        result = string(
            abi.encodePacked(
                result,
                ',"originatorRefundAmountWei":',
                vm.toString(sim.originatorRefundAmount),
                ',"remainingEscrowAfterRefundWei":',
                vm.toString(sim.remainingEscrowAfterRefund),
                "}"
            )
        );
    }

    function _buildSummaryMarkdown(ProjectionData memory projection, ProtocolSimulation memory sim)
        internal
        pure
        returns (string memory result)
    {
        result = string(
            abi.encodePacked(
                "# SAPIEN PoQ - Generated Economics Summary\n\n",
                "- Data file: `",
                ECON_DATA_OUTPUT_PATH,
                "`\n",
                "- Generated by: `forge test --match-test testECON_generateRevenueModelDataFile`\n\n"
            )
        );
        result = string(
            abi.encodePacked(
                result,
                "## Projection Highlights (USD)\n",
                "- Y1 GTV: $",
                vm.toString(projection.gtvUsd[0]),
                "\n",
                "- Y5 GTV: $",
                vm.toString(projection.gtvUsd[4]),
                "\n"
            )
        );
        result = string(
            abi.encodePacked(
                result,
                "- Y1 Fee Revenue: $",
                vm.toString(projection.feeRevenueUsd[0]),
                "\n",
                "- Y5 Fee Revenue: $",
                vm.toString(projection.feeRevenueUsd[4]),
                "\n"
            )
        );
        result = string(
            abi.encodePacked(
                result,
                "- Y1 Operating Income: $",
                _intToString(projection.operatingIncomeUsd[0]),
                "\n",
                "- Y5 Operating Income: $",
                _intToString(projection.operatingIncomeUsd[4]),
                "\n\n"
            )
        );
        result = string(
            abi.encodePacked(
                result,
                "## Protocol Activity Simulation Snapshot\n",
                "- Projects funded: ",
                vm.toString(sim.projectsFunded),
                "\n",
                "- Contributions submitted: ",
                vm.toString(sim.contributionsSubmitted),
                "\n"
            )
        );
        result = string(
            abi.encodePacked(
                result,
                "- Accepted contributions: ",
                vm.toString(sim.acceptedContributions),
                "\n",
                "- Rejected contributions: ",
                vm.toString(sim.rejectedContributions),
                "\n",
                "- Reward claims: ",
                vm.toString(sim.rewardClaims),
                "\n",
                "- Remaining escrow after refund (wei): ",
                vm.toString(sim.remainingEscrowAfterRefund),
                "\n"
            )
        );
    }

    function _uintArrayToJson(uint256[5] memory values) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "[",
                vm.toString(values[0]),
                ",",
                vm.toString(values[1]),
                ",",
                vm.toString(values[2]),
                ",",
                vm.toString(values[3]),
                ",",
                vm.toString(values[4]),
                "]"
            )
        );
    }

    function _intArrayToJson(int256[5] memory values) internal pure returns (string memory) {
        return string(
            abi.encodePacked(
                "[",
                _intToString(values[0]),
                ",",
                _intToString(values[1]),
                ",",
                _intToString(values[2]),
                ",",
                _intToString(values[3]),
                ",",
                _intToString(values[4]),
                "]"
            )
        );
    }

    function _intToString(int256 value) internal pure returns (string memory) {
        if (value >= 0) return vm.toString(uint256(value));
        return string(abi.encodePacked("-", vm.toString(uint256(-value))));
    }

    function _expectedFundingSplit(uint256 amount)
        internal
        view
        returns (uint256 protocolFee, uint256 originationFee, uint256 escrowAmount)
    {
        (uint256 originationFeeBps,,) = engine.getAdapterFees();

        protocolFee = (amount * DEFAULT_PROTOCOL_FEE_BPS) / C.BPS;
        uint256 afterProtocol = amount - protocolFee;
        originationFee = (afterProtocol * originationFeeBps) / C.BPS;
        escrowAmount = afterProtocol - originationFee;
    }
}
