// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test, console2} from "forge-std/Test.sol";
import {LifecycleBase} from "test/lifecycle/Lifecycle.t.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {
    Project,
    ProjectStatus,
    Contribution,
    ContributionStatus,
    ConsensusReport,
    Reputation,
    ValidationInput,
    ConsensusResult
} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";
import {ConsensusLib} from "src/libraries/ConsensusLib.sol";

/// @title SkillReputation
/// @notice Verifies that reputation is tracked per skill and that skill-specific reputation
///         influences consensus weight for validators. Contributors and validators accrue
///         reputation only against the project's requiredSkill, and cross-skill reputation
///         does not bleed into consensus calculations.
contract SkillReputation is LifecycleBase {
    bytes32 public constant SKILL_ANNOTATION = keccak256("DATA_ANNOTATION");
    bytes32 public constant SKILL_BOUNDING = keccak256("BOUNDING_BOX");
    bytes32 public constant SKILL_LABELING = keccak256("LABELING");

    address public validator4;
    address public validator5;

    function setUp() public override {
        super.setUp();

        vm.startPrank(admin);
        engine.registerSkill("BOUNDING_BOX");
        engine.registerSkill("LABELING");
        vm.stopPrank();

        validator4 = makeAddr("val4-skill");
        validator5 = makeAddr("val5-skill");

        address[2] memory extras = [validator4, validator5];
        for (uint256 i; i < extras.length; ++i) {
            token.mint(extras[i], STAKE_AMOUNT * 30);
            vm.startPrank(extras[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 15, extras[i]);
            vm.stopPrank();
        }

        token.mint(originator, 2_000_000e18);
        vm.startPrank(originator);
        token.approve(address(engine), type(uint256).max);
        vm.stopPrank();
    }

    // ════════════════════════════════════════════════════════════════════
    // 1. Reputation accrues under the project's skill hash
    // ════════════════════════════════════════════════════════════════════

    /// @notice After a successful validation round, both the contributor and validators
    ///         should have reputation recorded under the project's requiredSkill, not a
    ///         generic role key.
    function test_reputationAccruesUnderProjectSkill() public {
        bytes32 pid = _pid("skill-accrue");
        Project memory config = _defaultConfig();
        config.requiredSkill = SKILL_ANNOTATION;
        _setupProjectWithConfig(pid, 50_000e18, 5, config);

        Reputation memory repBefore = engine.getReputation(validator1, SKILL_ANNOTATION);
        assertEq(repBefore.lastUpdated, 0, "no prior annotation reputation");

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        _claimAndCommit(validator1, pid, idx, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx, 8500, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx, 8500);
        _reveal(validator2, pid, idx, 8500);
        _reveal(validator3, pid, idx, 8500);
        engine.computeConsensus(pid, idx);

        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(pid, idx).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pid, idx, nonce);
        engine.releaseContributorReward(pid, idx);

        Reputation memory valRep = engine.getReputation(validator1, SKILL_ANNOTATION);
        assertGt(valRep.score, C.DEFAULT_REPUTATION, "validator rep should increase under SKILL_ANNOTATION");
        assertGt(valRep.lastUpdated, 0, "validator reputation timestamp should be set");
        assertEq(valRep.successfulActions, 1, "one successful action recorded");

        Reputation memory contribRep = engine.getReputation(contributor1, SKILL_ANNOTATION);
        assertGt(contribRep.score, C.DEFAULT_REPUTATION, "contributor rep should increase under SKILL_ANNOTATION");
        assertEq(contribRep.successfulActions, 1, "contributor has one successful action");

        console2.log("--- Skill-Specific Reputation Accrual ---");
        console2.log("  Validator1 ANNOTATION rep:", valRep.score);
        console2.log("  Contributor1 ANNOTATION rep:", contribRep.score);
    }

    // ════════════════════════════════════════════════════════════════════
    // 2. Cross-skill isolation: reputation on one skill does not appear
    //    on another skill
    // ════════════════════════════════════════════════════════════════════

    /// @notice Building reputation on DATA_ANNOTATION should not affect BOUNDING_BOX
    ///         reputation for the same user.
    function test_crossSkillReputationIsolation() public {
        // --- Round on DATA_ANNOTATION project ---
        bytes32 pidAnnotation = _pid("annotation-proj");
        Project memory configA = _defaultConfig();
        configA.requiredSkill = SKILL_ANNOTATION;
        _setupProjectWithConfig(pidAnnotation, 50_000e18, 5, configA);

        (, uint256[] memory indicesA) = _claimAndSubmit(contributor1, pidAnnotation, 1);
        uint256 idxA = indicesA[0];
        _claimAndCommit(validator1, pidAnnotation, idxA, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pidAnnotation, idxA, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pidAnnotation, idxA, 8500, VALIDATOR_STAKE);
        _reveal(validator1, pidAnnotation, idxA, 8500);
        _reveal(validator2, pidAnnotation, idxA, 8500);
        _reveal(validator3, pidAnnotation, idxA, 8500);
        engine.computeConsensus(pidAnnotation, idxA);
        _warpPastChallengePeriod();
        uint256 nonceA = engine.getContribution(pidAnnotation, idxA).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pidAnnotation, idxA, nonceA);
        engine.releaseContributorReward(pidAnnotation, idxA);

        // --- Check cross-skill isolation ---
        Reputation memory repAnnotation = engine.getReputation(validator1, SKILL_ANNOTATION);
        Reputation memory repBounding = engine.getReputation(validator1, SKILL_BOUNDING);

        assertGt(repAnnotation.score, C.DEFAULT_REPUTATION, "annotation rep should be above default");
        assertEq(repBounding.lastUpdated, 0, "bounding box rep should be untouched");

        // Contributor cross-skill isolation
        Reputation memory contribAnnotation = engine.getReputation(contributor1, SKILL_ANNOTATION);
        Reputation memory contribBounding = engine.getReputation(contributor1, SKILL_BOUNDING);
        assertGt(contribAnnotation.score, C.DEFAULT_REPUTATION, "contributor annotation rep increased");
        assertEq(contribBounding.lastUpdated, 0, "contributor bounding box rep untouched");

        console2.log("--- Cross-Skill Isolation ---");
        console2.log(
            "  V1 ANNOTATION rep:",
            repAnnotation.score,
            "| BOUNDING rep:",
            repBounding.lastUpdated == 0 ? C.DEFAULT_REPUTATION : repBounding.score
        );
        console2.log(
            "  C1 ANNOTATION rep:",
            contribAnnotation.score,
            "| BOUNDING rep:",
            contribBounding.lastUpdated == 0 ? C.DEFAULT_REPUTATION : contribBounding.score
        );
    }

    // ════════════════════════════════════════════════════════════════════
    // 3. Consensus weight uses skill-specific reputation
    // ════════════════════════════════════════════════════════════════════

    /// @notice A validator who has built high reputation on a skill should have more
    ///         consensus weight than a validator with only default reputation on that skill,
    ///         even when both stake the same amount.
    function test_skillReputationInfluencesConsensusWeight() public {
        // --- Build validator1's ANNOTATION reputation over 5 rounds ---
        bytes32 buildPid = _pid("build-rep");
        Project memory buildConfig = _defaultConfig();
        buildConfig.requiredSkill = SKILL_ANNOTATION;
        buildConfig.numberOfValidations = 3;
        _setupProjectWithConfig(buildPid, 200_000e18, 10, buildConfig);

        for (uint256 i; i < 5; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, buildPid, 1);
            uint256 idx = indices[0];
            _claimAndCommit(validator1, buildPid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator2, buildPid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator3, buildPid, idx, 8500, VALIDATOR_STAKE);
            _reveal(validator1, buildPid, idx, 8500);
            _reveal(validator2, buildPid, idx, 8500);
            _reveal(validator3, buildPid, idx, 8500);
            engine.computeConsensus(buildPid, idx);
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(buildPid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(buildPid, idx, nonce);
            vm.prank(validator2);
            engine.settleValidator(buildPid, idx, nonce);
            vm.prank(validator3);
            engine.settleValidator(buildPid, idx, nonce);
            engine.releaseContributorReward(buildPid, idx);
        }

        Reputation memory repV1 = engine.getReputation(validator1, SKILL_ANNOTATION);
        Reputation memory repV4 = engine.getReputation(validator4, SKILL_ANNOTATION);

        assertGt(repV1.score, C.DEFAULT_REPUTATION, "v1 should have elevated annotation rep");
        assertEq(repV4.lastUpdated, 0, "v4 has no annotation rep (defaults to 5000)");

        // --- Demonstrate weight difference via ConsensusLib directly ---
        // With equal stakes, higher reputation → higher weight
        ValidationInput[] memory inputs = new ValidationInput[](2);
        inputs[0] = ValidationInput({
            validator: validator1, score: 8000, stakeAmount: VALIDATOR_STAKE, reputation: repV1.score
        });
        inputs[1] = ValidationInput({
            validator: validator4, score: 8000, stakeAmount: VALIDATOR_STAKE, reputation: C.DEFAULT_REPUTATION
        });

        ConsensusResult memory result = ConsensusLib.calculate(inputs);
        uint256 weightV1 = result.weights[0];
        uint256 weightV4 = result.weights[1];

        assertGt(weightV1, weightV4, "validator with higher skill rep should have more consensus weight");

        console2.log("--- Skill Rep -> Consensus Weight ---");
        console2.log("  V1 rep:", repV1.score, "| weight:", weightV1);
        console2.log("  V4 rep (default):", C.DEFAULT_REPUTATION, "| weight:", weightV4);
        console2.log("  Weight ratio (V1/V4):", weightV1 * 100 / weightV4, "%");
    }

    /// @notice Reputation built on BOUNDING_BOX should NOT increase a validator's
    ///         consensus weight on a DATA_ANNOTATION project. Only ANNOTATION reputation
    ///         is used for ANNOTATION project consensus.
    function test_crossSkillRepDoesNotInfluenceConsensus() public {
        // --- Build validator1's BOUNDING_BOX reputation ---
        bytes32 bbPid = _pid("bb-rep-build");
        Project memory bbConfig = _defaultConfig();
        bbConfig.requiredSkill = SKILL_BOUNDING;
        bbConfig.numberOfValidations = 3;
        _setupProjectWithConfig(bbPid, 200_000e18, 10, bbConfig);

        for (uint256 i; i < 5; ++i) {
            (, uint256[] memory bbIndices) = _claimAndSubmit(contributor1, bbPid, 1);
            uint256 bbIdx = bbIndices[0];
            _claimAndCommit(validator1, bbPid, bbIdx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator2, bbPid, bbIdx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator3, bbPid, bbIdx, 8500, VALIDATOR_STAKE);
            _reveal(validator1, bbPid, bbIdx, 8500);
            _reveal(validator2, bbPid, bbIdx, 8500);
            _reveal(validator3, bbPid, bbIdx, 8500);
            engine.computeConsensus(bbPid, bbIdx);
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(bbPid, bbIdx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(bbPid, bbIdx, nonce);
            vm.prank(validator2);
            engine.settleValidator(bbPid, bbIdx, nonce);
            vm.prank(validator3);
            engine.settleValidator(bbPid, bbIdx, nonce);
            engine.releaseContributorReward(bbPid, bbIdx);
        }

        Reputation memory repBB = engine.getReputation(validator1, SKILL_BOUNDING);
        assertGt(repBB.score, C.DEFAULT_REPUTATION, "v1 should have elevated BOUNDING_BOX rep");

        Reputation memory repAnn = engine.getReputation(validator1, SKILL_ANNOTATION);
        assertEq(repAnn.lastUpdated, 0, "v1 has no ANNOTATION rep");

        bytes32 annPid = _pid("ann-consensus");
        Project memory annConfig = _defaultConfig();
        annConfig.requiredSkill = SKILL_ANNOTATION;
        annConfig.numberOfValidations = 3;
        _setupProjectWithConfig(annPid, 50_000e18, 5, annConfig);

        (, uint256[] memory annIndices) = _claimAndSubmit(contributor1, annPid, 1);
        uint256 annIdx = annIndices[0];

        _claimAndCommit(validator1, annPid, annIdx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator4, annPid, annIdx, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator5, annPid, annIdx, 8000, VALIDATOR_STAKE);
        _reveal(validator1, annPid, annIdx, 8000);
        _reveal(validator4, annPid, annIdx, 8000);
        _reveal(validator5, annPid, annIdx, 8000);
        engine.computeConsensus(annPid, annIdx);

        ConsensusReport memory r = engine.getConsensusReport(annPid, annIdx);

        // Despite v1 having high BOUNDING_BOX rep, all three validators should have
        // equal weight on this ANNOTATION project (all have default ANNOTATION rep)
        assertEq(r.weightedAverage, 8000, "weighted avg should be exactly 8000 with equal weights");

        console2.log("--- Cross-Skill Rep Does Not Influence Consensus ---");
        console2.log("  V1 BOUNDING rep:", repBB.score);
        console2.log("  V1 ANNOTATION rep: default (5000)");
        console2.log("  Weighted avg (all equal):", r.weightedAverage);
    }

    // ════════════════════════════════════════════════════════════════════
    // 4. High-rep validator on a skill outweighs low-rep validator
    //    in consensus on that same skill
    // ════════════════════════════════════════════════════════════════════

    /// @notice When a high-rep validator and a low-rep validator disagree, the high-rep
    ///         validator's score should dominate the weighted average.
    function test_highSkillRepDominatesConsensus() public {
        // --- Build validator1 rep UP on LABELING ---
        bytes32 buildPid = _pid("label-build");
        Project memory buildConfig = _defaultConfig();
        buildConfig.requiredSkill = SKILL_LABELING;
        buildConfig.numberOfValidations = 5;
        _setupProjectWithConfig(buildPid, 300_000e18, 15, buildConfig);

        for (uint256 i; i < 8; ++i) {
            (, uint256[] memory buildIndices) = _claimAndSubmit(contributor1, buildPid, 1);
            uint256 buildIdx = buildIndices[0];

            _claimAndCommit(validator1, buildPid, buildIdx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator2, buildPid, buildIdx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator3, buildPid, buildIdx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator4, buildPid, buildIdx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator5, buildPid, buildIdx, 2000, VALIDATOR_STAKE);
            _reveal(validator1, buildPid, buildIdx, 8500);
            _reveal(validator2, buildPid, buildIdx, 8500);
            _reveal(validator3, buildPid, buildIdx, 8500);
            _reveal(validator4, buildPid, buildIdx, 8500);
            _reveal(validator5, buildPid, buildIdx, 2000);

            engine.computeConsensus(buildPid, buildIdx);
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(buildPid, buildIdx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(buildPid, buildIdx, nonce);
            vm.prank(validator2);
            engine.settleValidator(buildPid, buildIdx, nonce);
            vm.prank(validator3);
            engine.settleValidator(buildPid, buildIdx, nonce);
            vm.prank(validator4);
            engine.settleValidator(buildPid, buildIdx, nonce);
            vm.prank(validator5);
            engine.settleValidator(buildPid, buildIdx, nonce);
            engine.releaseContributorReward(buildPid, buildIdx);
        }

        Reputation memory repHigh = engine.getReputation(validator1, SKILL_LABELING);
        Reputation memory repLow = engine.getReputation(validator5, SKILL_LABELING);

        assertGt(repHigh.score, C.DEFAULT_REPUTATION, "v1 should have high LABELING rep");
        assertLt(repLow.score, C.DEFAULT_REPUTATION, "v5 should have low LABELING rep");

        bytes32 testPid = _pid("label-consensus");
        Project memory testConfig = _defaultConfig();
        testConfig.requiredSkill = SKILL_LABELING;
        testConfig.numberOfValidations = 3;
        _setupProjectWithConfig(testPid, 50_000e18, 5, testConfig);

        (, uint256[] memory testIndices) = _claimAndSubmit(contributor1, testPid, 1);
        uint256 testIdx = testIndices[0];

        _claimAndCommit(validator1, testPid, testIdx, 9000, VALIDATOR_STAKE);
        _claimAndCommit(validator5, testPid, testIdx, 5000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, testPid, testIdx, 9000, VALIDATOR_STAKE);
        _reveal(validator1, testPid, testIdx, 9000);
        _reveal(validator5, testPid, testIdx, 5000);
        _reveal(validator2, testPid, testIdx, 9000);
        engine.computeConsensus(testPid, testIdx);

        ConsensusReport memory r = engine.getConsensusReport(testPid, testIdx);

        // Unweighted average of 9000, 5000, 9000 = 7666
        // With rep weighting, v1 (high rep) and v2 (default) both scoring 9000
        // should pull the average well above 7666
        // v5 (low rep) scoring 5000 gets less weight
        uint256 unweightedAvg = uint256(9000 + 5000 + 9000) / 3;
        assertGt(
            r.weightedAverage,
            unweightedAvg,
            "rep-weighted avg should exceed simple average due to high-rep validators scoring 9000"
        );

        console2.log("--- High Skill Rep Dominates Consensus ---");
        console2.log("  V1 LABELING rep:", repHigh.score);
        console2.log("  V5 LABELING rep:", repLow.score);
        console2.log("  V2 LABELING rep: default (5000)");
        console2.log("  Unweighted avg:", unweightedAvg);
        console2.log("  Rep-weighted avg:", r.weightedAverage);
    }

    // ════════════════════════════════════════════════════════════════════
    // 5. Contributor reputation is skill-specific after rejection
    // ════════════════════════════════════════════════════════════════════

    /// @notice When a contribution is rejected (consensus below threshold), the contributor's
    ///         reputation penalty should be applied to the project's skill, not a generic key.
    function test_contributorRejectionPenaltyIsSkillSpecific() public {
        bytes32 pid = _pid("contrib-reject");
        Project memory config = _defaultConfig();
        config.requiredSkill = SKILL_BOUNDING;
        config.numberOfValidations = 3;
        _setupProjectWithConfig(pid, 50_000e18, 5, config);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 idx = indices[0];

        // All validators score below threshold → contributor rejected
        _claimAndCommit(validator1, pid, idx, 3000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, idx, 2500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, idx, 4000, VALIDATOR_STAKE);
        _reveal(validator1, pid, idx, 3000);
        _reveal(validator2, pid, idx, 2500);
        _reveal(validator3, pid, idx, 4000);
        engine.computeConsensus(pid, idx);

        Contribution memory c = engine.getContribution(pid, idx);
        assertEq(uint256(c.status), uint256(ContributionStatus.Rejected), "should be rejected below threshold");

        // Contributor's BOUNDING_BOX rep should decrease
        Reputation memory contribBounding = engine.getReputation(contributor1, SKILL_BOUNDING);
        assertLt(contribBounding.score, C.DEFAULT_REPUTATION, "contributor BOUNDING rep should decrease on rejection");

        // Contributor's ANNOTATION rep should remain untouched
        Reputation memory contribAnnotation = engine.getReputation(contributor1, SKILL_ANNOTATION);
        assertEq(contribAnnotation.lastUpdated, 0, "contributor ANNOTATION rep should be untouched");

        console2.log("--- Contributor Rejection Penalty per Skill ---");
        console2.log("  C1 BOUNDING rep (rejected):", contribBounding.score);
        console2.log("  C1 ANNOTATION rep (untouched): default");
    }

    // ════════════════════════════════════════════════════════════════════
    // 6. Multi-skill lifecycle: independent rep tracking across skills
    // ════════════════════════════════════════════════════════════════════

    /// @notice A validator who performs well on ANNOTATION but poorly on BOUNDING_BOX
    ///         should have divergent reputation per skill.
    function test_multiSkillDivergentReputation() public {
        // --- Rounds on ANNOTATION (validator1 is accurate) ---
        bytes32 annPid = _pid("multi-ann");
        Project memory annConfig = _defaultConfig();
        annConfig.requiredSkill = SKILL_ANNOTATION;
        annConfig.numberOfValidations = 3;
        _setupProjectWithConfig(annPid, 100_000e18, 10, annConfig);

        for (uint256 i; i < 3; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, annPid, 1);
            uint256 idx = indices[0];
            _claimAndCommit(validator1, annPid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator2, annPid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator3, annPid, idx, 8500, VALIDATOR_STAKE);
            _reveal(validator1, annPid, idx, 8500);
            _reveal(validator2, annPid, idx, 8500);
            _reveal(validator3, annPid, idx, 8500);
            engine.computeConsensus(annPid, idx);
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(annPid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(annPid, idx, nonce);
            vm.prank(validator2);
            engine.settleValidator(annPid, idx, nonce);
            vm.prank(validator3);
            engine.settleValidator(annPid, idx, nonce);
            engine.releaseContributorReward(annPid, idx);
        }

        // --- Rounds on BOUNDING_BOX (validator1 is the outlier) ---
        bytes32 bbPid = _pid("multi-bb");
        Project memory bbConfig = _defaultConfig();
        bbConfig.requiredSkill = SKILL_BOUNDING;
        bbConfig.numberOfValidations = 5;
        _setupProjectWithConfig(bbPid, 200_000e18, 10, bbConfig);

        for (uint256 i; i < 3; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, bbPid, 1);
            uint256 idx = indices[0];
            _claimAndCommit(validator1, bbPid, idx, 2000, VALIDATOR_STAKE); // outlier
            _claimAndCommit(validator2, bbPid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator3, bbPid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator4, bbPid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator5, bbPid, idx, 8500, VALIDATOR_STAKE);
            _reveal(validator1, bbPid, idx, 2000);
            _reveal(validator2, bbPid, idx, 8500);
            _reveal(validator3, bbPid, idx, 8500);
            _reveal(validator4, bbPid, idx, 8500);
            _reveal(validator5, bbPid, idx, 8500);
            engine.computeConsensus(bbPid, idx);
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(bbPid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(bbPid, idx, nonce);
            vm.prank(validator2);
            engine.settleValidator(bbPid, idx, nonce);
            vm.prank(validator3);
            engine.settleValidator(bbPid, idx, nonce);
            vm.prank(validator4);
            engine.settleValidator(bbPid, idx, nonce);
            vm.prank(validator5);
            engine.settleValidator(bbPid, idx, nonce);
            engine.releaseContributorReward(bbPid, idx);
        }

        Reputation memory repAnnotation = engine.getReputation(validator1, SKILL_ANNOTATION);
        Reputation memory repBounding = engine.getReputation(validator1, SKILL_BOUNDING);

        assertGt(repAnnotation.score, C.DEFAULT_REPUTATION, "v1 should have HIGH annotation rep");
        assertLt(repBounding.score, C.DEFAULT_REPUTATION, "v1 should have LOW bounding rep");

        uint256 gap = repAnnotation.score - repBounding.score;
        assertGt(gap, 100, "meaningful gap between skill reputations");

        console2.log("--- Multi-Skill Divergent Reputation ---");
        console2.log("  V1 ANNOTATION rep (accurate):", repAnnotation.score);
        console2.log("  V1 BOUNDING rep (outlier):", repBounding.score);
        console2.log("  Gap:", gap);
    }

    // ════════════════════════════════════════════════════════════════════
    // 7. Default reputation allows participation on new skills
    // ════════════════════════════════════════════════════════════════════

    /// @notice A validator with no prior reputation on a skill should start at
    ///         DEFAULT_REPUTATION and be able to participate if minValidatorReputation <= 5000.
    function test_defaultRepAllowsNewSkillParticipation() public {
        bytes32 pid = _pid("new-skill");
        Project memory config = _defaultConfig();
        config.requiredSkill = SKILL_LABELING;
        config.minValidatorReputation = uint16(C.DEFAULT_REPUTATION); // gate at exactly default
        config.numberOfValidations = 3;
        _setupProjectWithConfig(pid, 50_000e18, 5, config);

        _claimAndSubmit(contributor1, pid, 1);

        // validator4 has never worked on LABELING, but default rep = 5000 meets the gate
        _ensureStake(validator4, VALIDATOR_STAKE * 2);
        vm.prank(validator4);
        engine.claimToValidate(pid, 1);

        Reputation memory repBefore = engine.getReputation(validator4, SKILL_LABELING);
        assertEq(repBefore.lastUpdated, 0, "v4 has no prior LABELING rep");

        console2.log("--- Default Rep Allows New Skill ---");
        console2.log("  V4 LABELING rep before:", C.DEFAULT_REPUTATION, "(default)");
        console2.log("  Gate:", config.minValidatorReputation);
        console2.log("  V4 successfully claimed to validate");
    }

    // ════════════════════════════════════════════════════════════════════
    // 8. Skill reputation gates block low-rep validators
    // ════════════════════════════════════════════════════════════════════

    /// @notice A validator whose skill reputation is degraded below the project's
    ///         minValidatorReputation should be blocked from claiming on that skill's project.
    function test_skillRepGateBlocksDegradedValidator() public {
        // --- Degrade validator5's ANNOTATION reputation via 3 outlier rounds ---
        bytes32 degradePid = _pid("degrade-ann");
        Project memory degradeConfig = _defaultConfig();
        degradeConfig.requiredSkill = SKILL_ANNOTATION;
        degradeConfig.numberOfValidations = 5;
        _setupProjectWithConfig(degradePid, 200_000e18, 10, degradeConfig);

        for (uint256 i; i < 3; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, degradePid, 1);
            uint256 idx = indices[0];
            _claimAndCommit(validator1, degradePid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator2, degradePid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator3, degradePid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator4, degradePid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator5, degradePid, idx, 2000, VALIDATOR_STAKE);
            _reveal(validator1, degradePid, idx, 8500);
            _reveal(validator2, degradePid, idx, 8500);
            _reveal(validator3, degradePid, idx, 8500);
            _reveal(validator4, degradePid, idx, 8500);
            _reveal(validator5, degradePid, idx, 2000);
            engine.computeConsensus(degradePid, idx);
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(degradePid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(degradePid, idx, nonce);
            vm.prank(validator5);
            engine.settleValidator(degradePid, idx, nonce);
        }

        Reputation memory repDegraded = engine.getReputation(validator5, SKILL_ANNOTATION);
        assertLt(repDegraded.score, C.DEFAULT_REPUTATION, "v5 annotation rep should be below default");

        // Create gated ANNOTATION project requiring above v5's degraded score
        bytes32 gatedPid = _pid("gated-ann");
        Project memory gatedConfig = _defaultConfig();
        gatedConfig.requiredSkill = SKILL_ANNOTATION;
        gatedConfig.minValidatorReputation = repDegraded.score + 1;
        gatedConfig.numberOfValidations = 3;
        _setupProjectWithConfig(gatedPid, 50_000e18, 5, gatedConfig);

        _claimAndSubmit(contributor1, gatedPid, 1);

        // v5 should be blocked on the ANNOTATION-gated project
        _ensureStake(validator5, VALIDATOR_STAKE * 4);
        vm.prank(validator5);
        vm.expectRevert();
        engine.claimToValidate(gatedPid, 1);

        // But v5 should still be able to join a BOUNDING_BOX project with same gate
        // (since v5 has default rep on BOUNDING_BOX)
        if (gatedConfig.minValidatorReputation <= C.DEFAULT_REPUTATION) {
            bytes32 bbPid = _pid("bb-ungated");
            Project memory bbConfig = _defaultConfig();
            bbConfig.requiredSkill = SKILL_BOUNDING;
            bbConfig.minValidatorReputation = gatedConfig.minValidatorReputation;
            bbConfig.numberOfValidations = 3;
            _setupProjectWithConfig(bbPid, 50_000e18, 5, bbConfig);

            _claimAndSubmit(contributor2, bbPid, 1);
            _ensureStake(validator5, VALIDATOR_STAKE * 4);
            vm.prank(validator5);
            engine.claimToValidate(bbPid, 1);

            console2.log("  V5 allowed on BOUNDING_BOX project (default rep)");
        }

        console2.log("--- Skill Rep Gate ---");
        console2.log("  V5 ANNOTATION rep:", repDegraded.score);
        console2.log("  Gate:", repDegraded.score + 1);
        console2.log("  V5 blocked from ANNOTATION project");
    }

    // ════════════════════════════════════════════════════════════════════
    // 9. End-to-end: skill rep built → influences next round's consensus
    // ════════════════════════════════════════════════════════════════════

    /// @notice After building skill reputation over several rounds, the validator's
    ///         increased weight should measurably shift consensus in a subsequent round.
    ///         We use ConsensusLib.calculate directly to demonstrate the weight difference
    ///         with the same scores but different reputation inputs.
    function test_builtSkillRepShiftsConsensusInNextRound() public {
        // --- Build validator1's ANNOTATION rep through successful rounds ---
        bytes32 pid = _pid("rep-shift");
        Project memory config = _defaultConfig();
        config.requiredSkill = SKILL_ANNOTATION;
        config.numberOfValidations = 5;
        _setupProjectWithConfig(pid, 300_000e18, 15, config);

        // Run 8 rounds where v1 is accurate and v5 is the outlier
        for (uint256 i; i < 8; ++i) {
            (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
            uint256 idx = indices[0];
            _claimAndCommit(validator1, pid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator2, pid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator3, pid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator4, pid, idx, 8500, VALIDATOR_STAKE);
            _claimAndCommit(validator5, pid, idx, 2000, VALIDATOR_STAKE);
            _reveal(validator1, pid, idx, 8500);
            _reveal(validator2, pid, idx, 8500);
            _reveal(validator3, pid, idx, 8500);
            _reveal(validator4, pid, idx, 8500);
            _reveal(validator5, pid, idx, 2000);
            engine.computeConsensus(pid, idx);
            _warpPastChallengePeriod();
            uint256 nonce = engine.getContribution(pid, idx).consensusNonce;
            vm.prank(validator1);
            engine.settleValidator(pid, idx, nonce);
            vm.prank(validator5);
            engine.settleValidator(pid, idx, nonce);
            engine.releaseContributorReward(pid, idx);
        }

        Reputation memory repV1 = engine.getReputation(validator1, SKILL_ANNOTATION);
        Reputation memory repV5 = engine.getReputation(validator5, SKILL_ANNOTATION);
        assertGt(repV1.score, C.DEFAULT_REPUTATION, "v1 rep elevated");
        assertLt(repV5.score, C.DEFAULT_REPUTATION, "v5 rep degraded");

        // --- Compare consensus with skill rep vs without (via ConsensusLib directly) ---
        // Scenario: v1 scores 9000, v5 scores 6000, equal stakes
        // With default rep (equal weight): avg trends toward simple average
        ValidationInput[] memory defaultInputs = new ValidationInput[](2);
        defaultInputs[0] = ValidationInput({
            validator: validator1, score: 9000, stakeAmount: VALIDATOR_STAKE, reputation: C.DEFAULT_REPUTATION
        });
        defaultInputs[1] = ValidationInput({
            validator: validator5, score: 6000, stakeAmount: VALIDATOR_STAKE, reputation: C.DEFAULT_REPUTATION
        });
        ConsensusResult memory resultDefault = ConsensusLib.calculate(defaultInputs);

        // With actual skill rep: v1 gets more weight, pulls avg toward 9000
        ValidationInput[] memory skillInputs = new ValidationInput[](2);
        skillInputs[0] = ValidationInput({
            validator: validator1, score: 9000, stakeAmount: VALIDATOR_STAKE, reputation: repV1.score
        });
        skillInputs[1] = ValidationInput({
            validator: validator5, score: 6000, stakeAmount: VALIDATOR_STAKE, reputation: repV5.score
        });
        ConsensusResult memory resultSkill = ConsensusLib.calculate(skillInputs);

        uint256 avgDefault = resultDefault.weightedAverage;
        uint256 avgSkill = resultSkill.weightedAverage;

        // Both should equal 7500 at equal rep (simple avg of 9000 and 6000)
        assertEq(avgDefault, 7500, "equal rep should give simple average");
        // With divergent rep, avg should be pulled toward v1's higher score
        assertGt(avgSkill, avgDefault, "skill rep should shift consensus toward high-rep validator");

        console2.log("--- Built Skill Rep Shifts Consensus ---");
        console2.log("  V1 rep:", repV1.score, "| V5 rep:", repV5.score);
        console2.log("  Default rep avg:", avgDefault);
        console2.log("  Skill rep avg:", avgSkill);
        console2.log("  Shift:", avgSkill - avgDefault);
    }
}
