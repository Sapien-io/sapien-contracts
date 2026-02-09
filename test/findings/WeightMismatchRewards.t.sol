// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ORIGINATOR_ROLE, CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {SqrtStakeConsensus} from "../../src/consensus/SqrtStakeConsensus.sol";
import {ConsensusLib} from "../../src/libraries/ConsensusLib.sol";

/**
 * @title WeightMismatchRewardsTest
 * @notice Verifies the FIX for M-1: Weight Mismatch Between Consensus and Reward Distribution
 *
 * ORIGINAL VULNERABILITY:
 * Reward distribution always used `ConsensusLib.calculateBaseWeight(stake, reputation)`
 * (linear stake * rep) regardless of which consensus algorithm was active. With SqrtStakeConsensus,
 * a whale with 50:1 stake advantage had 7:1 consensus weight (sqrt) but 50:1 reward share (linear).
 *
 * FIX APPLIED:
 * `_distributeValidatorRewards` now receives `validatorWeights` from the `ConsensusReport`
 * (which are the actual weights computed by the consensus algorithm) and uses them for
 * reward distribution. Rewards are now proportional to consensus influence.
 *
 * LOCATION: SapienCore._distributeValidatorRewards(), ISharedTypes.ConsensusReport
 *
 * SEVERITY: MEDIUM (now fixed)
 */
contract WeightMismatchRewardsTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("weight-mismatch-test");

    address public whale = makeAddr("whale");
    address public smallValidator = makeAddr("smallValidator");

    function setUp() public override {
        super.setUp();

        // Register SqrtStakeConsensus
        vm.startPrank(admin);
        oracle.registerAlgorithm("SqrtStake", address(new SqrtStakeConsensus()));

        trust.grantRole(ORIGINATOR_ROLE, originator);
        trust.grantRole(CONTRIBUTOR_ROLE, contributor);
        trust.grantRole(VALIDATOR_ROLE, whale);
        trust.grantRole(VALIDATOR_ROLE, smallValidator);
        trust.grantRole(VALIDATOR_ROLE, validator1);
        vm.stopPrank();

        // Whale gets 10000 ether stake, small gets 100 ether
        _setupUser(whale, 10000 ether);
        _setupUser(smallValidator, 100 ether);

        // Initialize reputations
        vm.startPrank(admin);
        trust.updateReputation(whale, VALIDATOR_ROLE, true, 5000);
        trust.updateReputation(smallValidator, VALIDATOR_ROLE, true, 5000);
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 5000);
        vm.stopPrank();

        // Set capacities
        vm.prank(whale);
        oracle.setValidatorCapacity(5000 ether);
        vm.prank(smallValidator);
        oracle.setValidatorCapacity(100 ether);
        _setValidatorCapacity(validator1, 200 ether);
    }

    /**
     * @notice FIX VERIFIED: Reward ratio now matches consensus weight ratio
     * @dev With SqrtStakeConsensus:
     *      - Consensus weight(whale) = sqrt(5000e18) ~= 7.07e10
     *      - Consensus weight(small) = sqrt(100e18)  ~= 1e10
     *      - Consensus ratio: ~7:1
     *
     *      Before fix: reward ratio was 50:1 (linear mismatch)
     *      After fix: reward ratio should be ~7:1 (matching consensus)
     */
    function test_M1_Fix_RewardRatioMatchesConsensusRatio() public {
        // Create project using SqrtStake consensus
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "weight-mismatch-test", 0, 0, 3, 1000, "");
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(PROJECT_ID, 1000 ether, 10);
        vm.stopPrank();

        // Set project to use SqrtStake algorithm
        vm.prank(originator);
        oracle.setProjectAlgorithm(PROJECT_ID, "SqrtStake");

        // Submit a contribution
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(PROJECT_ID, 1);
        core.contribute(PROJECT_ID, claimId, 0, keccak256("work"));
        vm.stopPrank();

        // All validators vote the same score with different stakes
        uint256 whaleStake = 5000 ether;
        uint256 smallStake = 100 ether;
        uint256 v1Stake = 100 ether;
        uint256 score = 8000;

        _commitAndRevealWithStake(whale, PROJECT_ID, 0, score, whaleStake);
        _commitAndRevealWithStake(smallValidator, PROJECT_ID, 0, score, smallStake);
        _commitAndRevealWithStake(validator1, PROJECT_ID, 0, score, v1Stake);

        // Record balances before finalization
        uint256 whaleRewardsBefore = rewards.getAvailableValidatorRewards(whale, PROJECT_ID, address(rewardToken));
        uint256 smallRewardsBefore =
            rewards.getAvailableValidatorRewards(smallValidator, PROJECT_ID, address(rewardToken));

        // Finalize
        core.finalizeContribution(PROJECT_ID, 0);

        // Check rewards
        uint256 whaleReward =
            rewards.getAvailableValidatorRewards(whale, PROJECT_ID, address(rewardToken)) - whaleRewardsBefore;
        uint256 smallReward =
            rewards.getAvailableValidatorRewards(smallValidator, PROJECT_ID, address(rewardToken)) - smallRewardsBefore;

        console.log("=== M-1 FIX VERIFIED ===");
        console.log("Algorithm: SqrtStake");
        console.log("Whale stake:", whaleStake / 1e18, "ether");
        console.log("Small stake:", smallStake / 1e18, "ether");

        // Calculate expected consensus ratio
        uint256 sqrtWhale = ConsensusLib.sqrt(whaleStake);
        uint256 sqrtSmall = ConsensusLib.sqrt(smallStake);
        uint256 consensusRatio = sqrtSmall > 0 ? sqrtWhale / sqrtSmall : 0;
        console.log("Consensus ratio (sqrt):", consensusRatio, ":1");

        if (smallReward > 0) {
            uint256 actualRewardRatio = whaleReward / smallReward;
            console.log("Actual reward ratio:", actualRewardRatio, ":1");
            console.log("Before fix: would have been ~50:1 (linear mismatch)");

            // After fix: reward ratio should approximate the consensus weight ratio
            // Allow some tolerance for rounding (within 2x of consensus ratio)
            assertLe(
                actualRewardRatio, consensusRatio * 2, "FIX VERIFIED: Reward ratio should approximate consensus ratio"
            );

            console.log("FIX VERIFIED: Reward ratio now matches consensus influence.");
        }
    }

    // ============================================
    // HELPERS
    // ============================================

    function _commitAndRevealWithStake(address v, bytes32 projectId, uint256 contribIndex, uint256 score, uint256 stake)
        internal
    {
        bytes32 salt = keccak256(abi.encodePacked(v, score, contribIndex, block.timestamp));
        bytes32 commitHash = keccak256(abi.encodePacked(score, stake, salt));

        vm.startPrank(v);
        uint256 claimId = oracle.claimToValidate(projectId);
        oracle.commitValidationWithStake(projectId, claimId, contribIndex, stake, commitHash);
        vm.stopPrank();

        vm.warp(block.timestamp + 2 hours);

        vm.prank(v);
        oracle.revealValidation(projectId, contribIndex, score, salt);
    }
}
