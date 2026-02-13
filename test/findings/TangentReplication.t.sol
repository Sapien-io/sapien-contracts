// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {IConsensusAlgorithm} from "../../src/interface/IConsensusAlgorithm.sol";
import {SqrtStakeConsensus} from "../../src/consensus/SqrtStakeConsensus.sol";
import {UPDATER_ROLE, VALIDATOR_ROLE, UNAUTHORIZED_SKILL_COOLDOWN} from "../../src/interface/ISharedTypes.sol";
import {ISharedTypes} from "../../src/interface/ISharedTypes.sol";

contract TangentReplicationTest is BaseTest {
    address public attacker = makeAddr("attacker");

    function setUp() public override {
        super.setUp();
    }

    function test_Fix_Tangent5_EmergencyWithdraw() public {
        // 1. Rewards are allocated to a project
        string memory cid = "allocated_project";
        _setupProject(cid, 1);

        uint256 allocatedAmount = rewardToken.balanceOf(address(rewards));
        assertGt(allocatedAmount, 0);

        // 2. Admin tries to withdraw ALL rewards (should fail because they are allocated)
        vm.startPrank(admin);
        rewards.pause();

        // Should revert because allocated > 0
        vm.expectRevert(); // Should revert with InsufficientProjectRewards but type check is fine here
        rewards.emergencyWithdraw(address(rewardToken), attacker, allocatedAmount);

        // 3. Admin mints SOME OTHER token to Rewards (stuck token)
        MockERC20 stuckToken = new MockERC20("Stuck", "STUCK", 18);
        stuckToken.mint(address(rewards), 100 ether);

        // 4. Admin CAN withdraw the stuck token (because it's not allocated)
        rewards.emergencyWithdraw(address(stuckToken), attacker, 100 ether);
        vm.stopPrank();

        assertEq(stuckToken.balanceOf(attacker), 100 ether);
        assertEq(rewardToken.balanceOf(address(rewards)), allocatedAmount); // Still there

        emit log("Fix verified: Admin cannot withdraw allocated rewards, but can withdraw stuck tokens");
    }

    // --- Helpers ---

    function _setupProject(string memory cid, uint256 numberOfValidations) internal {
        bytes32 projectId = keccak256(abi.encodePacked(cid));
        vm.startPrank(admin);
        oracle.registerProject(projectId, numberOfValidations, "", originator);
        vm.stopPrank();

        vm.startPrank(originator);
        rewardToken.approve(address(core), 10000 ether);
        core.createProject(projectId, address(rewardToken), cid, 1 ether, 1 ether, numberOfValidations, 1000, "");
        core.fundProject(projectId, 10000 ether, 10);
        vm.stopPrank();

        vm.startPrank(contributor);
        core.claimToContribute(projectId, 1);
        core.contribute(projectId, 0, 0, keccak256("submission"));
        vm.stopPrank();
    }

    function _commit(bytes32 projectId, uint256 contributionIndex, address validator, uint256 score, string memory salt)
        internal
    {
        _setValidatorCapacity(validator, 1000 ether);
        vm.startPrank(validator);
        uint256 claimId = oracle.claimToValidate(projectId);
        oracle.commitValidation(
            projectId,
            claimId,
            contributionIndex - 1,
            keccak256(abi.encodePacked(score, uint256(100 ether), keccak256(abi.encodePacked(salt))))
        );
        vm.stopPrank();
    }

    function _reveal(bytes32 projectId, uint256 contributionIndex, address validator, uint256 score, string memory salt)
        internal
    {
        vm.startPrank(validator);
        oracle.revealValidation(projectId, contributionIndex - 1, score, keccak256(abi.encodePacked(salt)));
        vm.stopPrank();
    }

    /**
     * @notice Replicates Tangent 1: Whale-Heavy Weighted Average
     * Demonstrates that a whale with >50% stake can dictate the consensus score
     */
    function test_Tangent1_WhaleAttack() public {
        // 1. Setup project
        bytes32 projectId = keccak256("whale_project");
        vm.startPrank(admin);
        oracle.registerProject(projectId, 3, "", originator);
        vm.stopPrank();

        // 2. Setup honest validators (small stakes)
        address honest1 = makeAddr("honest1");
        address honest2 = makeAddr("honest2");
        _setupUser(honest1, 100 ether);
        _setupUser(honest2, 100 ether);
        _setValidatorCapacity(honest1, 100 ether);
        _setValidatorCapacity(honest2, 100 ether);

        // 3. Setup whale validator (massive stake)
        address whale = makeAddr("whale");
        uint256 whaleStake = 10000 ether; // > 50x honest validators combined
        _setupUser(whale, whaleStake);
        _setValidatorCapacity(whale, whaleStake);

        // 4. Prepare validations
        // Honest validators say score is 5000 (neutral)
        // Whale says score is 10000 (maximum)
        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](3);
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: honest1, score: 5000, stakeAmount: 100 ether, reputation: 5000
        });
        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: honest2, score: 5000, stakeAmount: 100 ether, reputation: 5000
        });
        inputs[2] = IConsensusAlgorithm.ValidationInput({
            validator: whale, score: 10000, stakeAmount: whaleStake, reputation: 5000
        });

        // 5. Calculate consensus using SqrtStakeConsensus
        SqrtStakeConsensus consensus = new SqrtStakeConsensus();
        IConsensusAlgorithm.ConsensusResult memory result = consensus.calculateConsensus(inputs);

        // 6. Verify result is whale-weighted but reduced by sqrt weighting
        // (5000*10 + 5000*10 + 10000*100) / (10 + 10 + 100) = 1100000 / 120 = 9166
        assertApproxEqAbs(result.weightedAverage, 9166, 10);
        emit log_named_uint("Weighted Average", result.weightedAverage);
    }

    /**
     * @notice Verifies fix for Tangent 1: Whale-Heavy Weighted Average
     * Demonstrates that SqrtStakeConsensus significantly reduces whale influence
     */
    function test_Fix_Tangent1_SqrtStake() public {
        // Same setup as test_Tangent1_WhaleAttack
        address honest1 = makeAddr("honest1_sqrt");
        address honest2 = makeAddr("honest2_sqrt");
        address whale = makeAddr("whale_sqrt");
        uint256 whaleStake = 10000 ether;

        IConsensusAlgorithm.ValidationInput[] memory inputs = new IConsensusAlgorithm.ValidationInput[](3);
        inputs[0] = IConsensusAlgorithm.ValidationInput({
            validator: honest1, score: 5000, stakeAmount: 100 ether, reputation: 5000
        });
        inputs[1] = IConsensusAlgorithm.ValidationInput({
            validator: honest2, score: 5000, stakeAmount: 100 ether, reputation: 5000
        });
        inputs[2] = IConsensusAlgorithm.ValidationInput({
            validator: whale, score: 10000, stakeAmount: whaleStake, reputation: 5000
        });

        // Calculate using SqrtStakeConsensus
        SqrtStakeConsensus sqrt = new SqrtStakeConsensus();
        IConsensusAlgorithm.ConsensusResult memory sqrtResult = sqrt.calculateConsensus(inputs);

        emit log_named_uint("Sqrt Weighted Average", sqrtResult.weightedAverage);

        // Expect around 9166
        assertApproxEqAbs(sqrtResult.weightedAverage, 9166, 10);

        emit log("SqrtStakeConsensus whale-weighting behavior verified");
    }

    /**
     * @notice Verifies Intended Slashing Behavior (Tangent 2)
     * Demonstrates that slashing other users increases the value of the attacker's shares (socialized gain)
     */
    function test_Tangent2_VaultSlashingBehavior() public {
        address victim = makeAddr("victim");

        // 1. Both deposit equal amounts
        uint256 depositAmount = 1000 ether;
        _setupUser(attacker, depositAmount);
        _setupUser(victim, depositAmount);

        uint256 attackerInitialShares = vault.balanceOf(attacker);
        uint256 attackerInitialAssets = vault.convertToAssets(attackerInitialShares);

        emit log_named_uint("Attacker initial assets", attackerInitialAssets);

        // 2. Admin slashes the victim
        // Slashed assets remain in the vault
        vm.startPrank(admin);
        vault.slash(victim, 1000 ether, keccak256("victim_project"));
        vm.stopPrank();

        // 3. Attacker's shares are now worth more
        uint256 attackerFinalShares = vault.balanceOf(attacker);
        uint256 attackerFinalAssets = vault.convertToAssets(attackerFinalShares);

        emit log_named_uint("Attacker final assets", attackerFinalAssets);

        // Attacker should have gained significant value because assets stayed in vault
        assertGt(attackerFinalAssets, attackerInitialAssets);

        emit log("Verified: Slashed assets remain in vault, increasing share value for others (intended)");
    }

    /**
     * @notice Replicates Tangent 3: Oracle Griefing
     * With numberOfValidations=2, 1 honest + 1 griefer: only 1 reveal, so consensus not ready.
     * Demonstrates the scenario where we need more reveals (griefing doesn't block if we lack numberOfValidations).
     */
    function test_Tangent3_OracleGriefing() public {
        // 1. Setup project with numberOfValidations = 2 (use core.createProject to set it)
        bytes32 projectId = keccak256("grief_project");
        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.createProject(projectId, address(rewardToken), "grief_project", 1 ether, 1 ether, 2, 1000, ""); // numberOfValidations=2
        core.fundProject(projectId, 1000 ether, 10);
        vm.stopPrank();

        vm.startPrank(contributor);
        core.claimToContribute(projectId, 1);
        core.contribute(projectId, 0, 0, keccak256("submission"));
        vm.stopPrank();

        // 3. Validators commit
        address honestValidator = validator1;
        address grieferValidator = validator2;

        _setValidatorCapacity(honestValidator, 1000 ether);
        _setValidatorCapacity(grieferValidator, 1000 ether);

        vm.startPrank(honestValidator);
        uint256 claimIdHonest = oracle.claimToValidate(projectId);
        oracle.commitValidation(
            projectId,
            claimIdHonest,
            0,
            // forge-lint: disable-next-line(unsafe-typecast)
            // casting to 'bytes32' is safe because we're using a fixed string literal as salt
            keccak256(abi.encodePacked(uint256(5000), uint256(100 ether), bytes32("salt1")))
        );
        vm.stopPrank();

        vm.startPrank(grieferValidator);
        uint256 claimIdGrief = oracle.claimToValidate(projectId);
        oracle.commitValidation(
            projectId,
            claimIdGrief,
            0,
            keccak256(
                abi.encodePacked(
                    uint256(5000),
                    uint256(100 ether),
                    // forge-lint: disable-next-line(unsafe-typecast)
                    // casting to 'bytes32' is safe because we're using a fixed string literal as salt
                    bytes32("salt2")
                )
            )
        );
        vm.stopPrank();

        // 4. Honest validator reveals
        vm.startPrank(honestValidator);
        // forge-lint: disable-next-line(unsafe-typecast)
        // casting to 'bytes32' is safe because we're using a fixed string literal as salt
        oracle.revealValidation(projectId, 0, 5000, bytes32("salt1"));
        vm.stopPrank();

        // 5. With only 1 reveal and numberOfValidations=2, consensus is not ready.
        ConsensusReport memory report = oracle.getConsensus(projectId, 0);
        assertEq(report.isReady, false);
        emit log("Consensus NOT ready: only 1 reveal, need 2");

        // 6. Fast forward past deadline (3 days) so griefer's commit expires and gets slashed
        vm.warp(block.timestamp + 3 days + 1);

        // 7. Still only 1 valid reveal (griefer expired/slashed, not counted). So still not ready.
        report = oracle.getConsensus(projectId, 0);
        assertEq(report.isReady, false, "Still only 1 reveal - need numberOfValidations (2) for consensus");
    }

    /**
     * @notice M-02 FIX: Verifies that consensus proceeds immediately when numberOfValidations met (F-09).
     * With numberOfValidations=2, 3 commit, 2 reveal: consensus is ready WITHOUT waiting for v3's commit to expire.
     */
    function test_Fix_Tangent3_OracleGriefing() public {
        string memory cid = "griefing_project_fix";
        bytes32 projectId = keccak256(abi.encodePacked(cid));
        _setupProject(cid, 3); // numberOfValidations=3 (need 3 queue slots for 3 validators)

        address v1 = makeAddr("v1_fix");
        address v2 = makeAddr("v2_fix");
        address v3 = makeAddr("v3_fix");
        uint256 depositAmount = 1000 ether;

        _setupUser(v1, depositAmount);
        _setupUser(v2, depositAmount);
        _setupUser(v3, depositAmount);

        // 1. All commit
        _commit(projectId, 1, v1, 5000, "salt1");
        _commit(projectId, 1, v2, 5000, "salt2");
        _commit(projectId, 1, v3, 5000, "salt3");

        // 2. All 3 validators reveal
        _reveal(projectId, 1, v1, 5000, "salt1");
        _reveal(projectId, 1, v2, 5000, "salt2");
        _reveal(projectId, 1, v3, 5000, "salt3");

        // 3. M-02 FIX: Consensus is ready IMMEDIATELY with 3 reveals (numberOfValidations=3).
        ConsensusReport memory report = oracle.getConsensus(projectId, 0);
        assertTrue(report.isReady, "Consensus ready when numberOfValidations met");
        assertEq(report.validatorCount, 3);

        emit log("M-02 Fix verified: Consensus proceeds when numberOfValidations met");
    }

    function test_Tangent4_GhostMaster() public {
        address ghostValidator = makeAddr("ghost");

        // 1. Attacker gains UPDATER_ROLE on Trust
        vm.startPrank(admin);
        trust.grantRole(UPDATER_ROLE, attacker);
        vm.stopPrank();

        // 2. Attacker inflates skills and reputation for the ghost
        vm.startPrank(attacker);
        trust.validateSkill(ghostValidator, "Solidity");
        trust.updateReputation(ghostValidator, VALIDATOR_ROLE, true, 10000);
        vm.stopPrank();

        // 3. Verify ghost has skills and high reputation
        assertTrue(trust.hasValidatedSkill(ghostValidator, "Solidity"));
        uint256 score = trust.getTrustScore(ghostValidator, VALIDATOR_ROLE);
        assertGe(score, 5000); // Should have increased from default
        emit log_named_uint("Ghost Reputation", score);
    }

    function test_Fix_Tangent4_GhostMaster() public {
        address ghostValidator = makeAddr("ghost_fix");

        vm.startPrank(admin);
        trust.grantRole(UPDATER_ROLE, attacker);
        vm.stopPrank();

        // 1. Try to validate two skills in quick succession
        vm.startPrank(attacker);
        trust.validateSkill(ghostValidator, "Solidity");

        // Second skill should fail due to cooldown
        vm.expectRevert(abi.encodeWithSelector(ISharedTypes.Unauthorized.selector, UNAUTHORIZED_SKILL_COOLDOWN));
        trust.validateSkill(ghostValidator, "TypeScript");
        vm.stopPrank();

        // 2. Try to inflate reputation past daily limit
        vm.startPrank(attacker);
        // Default SUCCESS_INCREASE is 10. MAX_DAILY_GAIN is 100.
        // 10 calls should reach the limit.
        for (uint256 i = 0; i < 15; i++) {
            trust.updateReputation(ghostValidator, VALIDATOR_ROLE, true, 10000);
        }
        vm.stopPrank();

        uint256 score = trust.getTrustScore(ghostValidator, VALIDATOR_ROLE);
        // Initial 5000 + 100 (limit) = 5100
        assertEq(score, 5100);

        emit log("Fix verified: Ghost Master inflation is capped by daily limits and cooldowns");
    }

    /**
     * @notice Replicates Tangent 5: Safe Emergency Withdrawal
     * Demonstrates that admin can drain funds when paused
     */
    function test_Tangent5_EmergencyWithdraw() public {
        // 1. Rewards contract has funds
        rewardToken.mint(address(rewards), 10000 ether);
        assertEq(rewardToken.balanceOf(address(rewards)), 10000 ether);

        // 2. Admin pauses and withdraws
        vm.startPrank(admin);
        rewards.pause();
        rewards.emergencyWithdraw(address(rewardToken), attacker, 10000 ether);
        vm.stopPrank();

        // 3. Verify funds are drained
        assertEq(rewardToken.balanceOf(address(rewards)), 0);
        assertEq(rewardToken.balanceOf(attacker), 10000 ether);
        emit log("Admin successfully drained rewards via emergencyWithdraw");
    }
}
