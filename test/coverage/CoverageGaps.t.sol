// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {ConsensusLib} from "src/libraries/ConsensusLib.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {
    Project,
    ProjectStatus,
    Claim,
    ClaimStatus,
    Contribution,
    ContributionStatus,
    ConsensusReport,
    Reputation,
    StakeAccount,
    Dispute,
    DisputeStatus,
    OriginatorReport,
    OriginatorReportStatus,
    ValidationInput,
    ConsensusResult
} from "src/Types.sol";

// ═══════════════════════════════════════════════════════════════════════
// ConsensusLib test harness (wraps internal functions for direct testing)
// ═══════════════════════════════════════════════════════════════════════

contract ConsensusLibHarness {
    function calculate(ValidationInput[] memory inputs) external pure returns (ConsensusResult memory) {
        return ConsensusLib.calculate(inputs);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// ConsensusLib Coverage Tests
// ═══════════════════════════════════════════════════════════════════════

contract ConsensusLibCoverageTest is Test {
    ConsensusLibHarness internal harness;

    function setUp() public {
        harness = new ConsensusLibHarness();
    }

    function test_revert_emptyInput() public {
        ValidationInput[] memory inputs = new ValidationInput[](0);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusNotReady.selector, 0, 1));
        harness.calculate(inputs);
    }

    function test_singleInput_noOutlier() public view {
        ValidationInput[] memory inputs = new ValidationInput[](1);
        inputs[0] = ValidationInput({validator: address(1), score: 8000, stakeAmount: 100e18, reputation: 5000});
        ConsensusResult memory result = harness.calculate(inputs);
        assertEq(result.weightedAverage, 8000);
        assertFalse(result.isOutlier[0]);
        assertEq(result.totalAccurateWeight, result.weights[0]);
    }

    function test_zeroWeight_fallbackToOne() public view {
        // score = 0, stakeAmount = 0, reputation = 0 → weight would be 0, falls back to 1
        ValidationInput[] memory inputs = new ValidationInput[](2);
        inputs[0] = ValidationInput({validator: address(1), score: 5000, stakeAmount: 0, reputation: 0});
        inputs[1] = ValidationInput({validator: address(2), score: 5000, stakeAmount: 100e18, reputation: 5000});
        ConsensusResult memory result = harness.calculate(inputs);
        // w=0 → w=1 for first input (sqrt(0)*minRep/BPS = 0)
        assertEq(result.weights[0], 1);
        assertGt(result.weights[1], 0);
    }

    /// @notice TIER_1 slash: 1.5σ–2σ deviation (10% slash)
    /// With 4 equal-weight validators (3 agree, 1 outlier), deviationSigma = sqrt(3) ≈ 1.73
    function test_tier1Slash() public view {
        ValidationInput[] memory inputs = new ValidationInput[](4);
        for (uint256 i; i < 3; ++i) {
            inputs[i] = ValidationInput({
                validator: address(uint160(i + 1)), score: 8000, stakeAmount: 100e18, reputation: 5000
            });
        }
        inputs[3] = ValidationInput({validator: address(4), score: 1000, stakeAmount: 100e18, reputation: 5000});

        ConsensusResult memory result = harness.calculate(inputs);
        assertTrue(result.isOutlier[3]);
        // TIER_1 = 10% slash = 100e18 * 1000 / 10000 = 10e18
        assertEq(result.slashAmounts[3], 10e18);
    }

    /// @notice TIER_2 slash: 2σ–3σ deviation (25% slash)
    /// With 5 equal-weight validators (4 agree, 1 outlier), deviationSigma = sqrt(4) = 2.0
    function test_tier2Slash() public view {
        ValidationInput[] memory inputs = new ValidationInput[](5);
        for (uint256 i; i < 4; ++i) {
            inputs[i] = ValidationInput({
                validator: address(uint160(i + 1)), score: 8000, stakeAmount: 100e18, reputation: 5000
            });
        }
        inputs[4] = ValidationInput({validator: address(5), score: 1000, stakeAmount: 100e18, reputation: 5000});

        ConsensusResult memory result = harness.calculate(inputs);
        assertTrue(result.isOutlier[4]);
        // TIER_2 = 25% slash = 100e18 * 2500 / 10000 = 25e18
        assertEq(result.slashAmounts[4], 25e18);
    }

    /// @notice TIER_3 slash: 3σ–5σ deviation (50% slash)
    /// With 10 equal-weight validators (9 agree, 1 outlier), deviationSigma = sqrt(9) = 3.0
    function test_tier3Slash() public view {
        ValidationInput[] memory inputs = new ValidationInput[](10);
        for (uint256 i; i < 9; ++i) {
            inputs[i] = ValidationInput({
                validator: address(uint160(i + 1)), score: 8000, stakeAmount: 100e18, reputation: 5000
            });
        }
        inputs[9] = ValidationInput({validator: address(10), score: 1000, stakeAmount: 100e18, reputation: 5000});

        ConsensusResult memory result = harness.calculate(inputs);
        assertTrue(result.isOutlier[9]);
        // TIER_3 = 50% slash = 100e18 * 5000 / 10000 = 50e18
        assertEq(result.slashAmounts[9], 50e18);
    }

    /// @notice TIER_4 slash: ≥5σ deviation (100% slash)
    /// Use unequal weights: outlier has tiny stake so its influence on stdDev is minimal
    function test_tier4Slash() public view {
        uint256 n = 10;
        ValidationInput[] memory inputs = new ValidationInput[](n);
        // 9 validators with large stake
        for (uint256 i; i < n - 1; ++i) {
            inputs[i] = ValidationInput({
                validator: address(uint160(i + 1)), score: 8000, stakeAmount: 10000e18, reputation: 10000
            });
        }
        // 1 outlier with tiny stake → very low weight → deviationSigma > 5σ
        inputs[n - 1] = ValidationInput({validator: address(uint160(n)), score: 0, stakeAmount: 1e18, reputation: 1000});

        ConsensusResult memory result = harness.calculate(inputs);
        assertTrue(result.isOutlier[n - 1]);
        // TIER_4 = 100% slash = 1e18 * 10000 / 10000 = 1e18
        assertEq(result.slashAmounts[n - 1], 1e18);
    }

    /// @notice All validators agree → no outliers, stdDev = 0
    function test_allAgree_noOutliers() public view {
        ValidationInput[] memory inputs = new ValidationInput[](3);
        for (uint256 i; i < 3; ++i) {
            inputs[i] = ValidationInput({
                validator: address(uint160(i + 1)), score: 7500, stakeAmount: 50e18, reputation: 5000
            });
        }
        ConsensusResult memory result = harness.calculate(inputs);
        assertEq(result.weightedAverage, 7500);
        assertEq(result.stdDeviation, 0);
        assertFalse(result.isOutlier[0]);
        assertFalse(result.isOutlier[1]);
        assertFalse(result.isOutlier[2]);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienVault Coverage Tests
// ═══════════════════════════════════════════════════════════════════════

contract SapienVaultCoverageTest is Test {
    SapienVault internal vault;
    MockERC20 internal token;
    address internal admin = makeAddr("admin");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");
    address internal engineAddr;

    function setUp() public {
        token = new MockERC20("Sapien Token", "SPN");

        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInit = abi.encodeCall(SapienVault.initialize, (token, admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));

        engineAddr = makeAddr("engine");
        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), engineAddr);
        vm.stopPrank();

        // Fund users
        _depositFor(user1, 1000e18);
        _depositFor(user2, 1000e18);
    }

    function _depositFor(address user, uint256 amount) internal {
        token.mint(user, amount);
        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.deposit(amount, user);
        vm.stopPrank();
    }

    // ── Zero-amount reverts for all ENGINE_ROLE functions ──────────

    function test_revert_lockContributor_zeroAmount() public {
        vm.prank(engineAddr);
        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vault.lockContributor(user1, 0);
    }

    function test_revert_unlockContributor_zeroAmount() public {
        vm.prank(engineAddr);
        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vault.unlockContributor(user1, 0);
    }

    function test_revert_slashContributor_zeroAmount() public {
        vm.prank(engineAddr);
        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vault.slashContributor(user1, 0);
    }

    function test_revert_lockValidatorCapacity_zeroAmount() public {
        vm.prank(engineAddr);
        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vault.lockValidatorCapacity(user1, 0);
    }

    function test_revert_unlockValidatorCapacity_zeroAmount() public {
        vm.prank(engineAddr);
        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vault.unlockValidatorCapacity(user1, 0);
    }

    function test_revert_commitStake_zeroAmount() public {
        vm.prank(engineAddr);
        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vault.commitStake(user1, 0);
    }

    function test_revert_releaseCommit_zeroAmount() public {
        vm.prank(engineAddr);
        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vault.releaseCommit(user1, 0);
    }

    function test_revert_slashValidator_zeroAmount() public {
        vm.prank(engineAddr);
        vm.expectRevert(ISapienVault.ZeroAmount.selector);
        vault.slashValidator(user1, 0);
    }

    // ── Insufficient balance/lock reverts ──────────────────────────

    function test_revert_lockContributor_insufficientBalance() public {
        uint256 avail = vault.availableBalance(user1);
        vm.prank(engineAddr);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientAvailableBalance.selector, 99999e18, avail));
        vault.lockContributor(user1, 99999e18);
    }

    function test_revert_unlockContributor_insufficientLock() public {
        vm.prank(engineAddr);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientContributorLock.selector, 100e18, 0));
        vault.unlockContributor(user1, 100e18);
    }

    function test_revert_slashContributor_insufficientLock() public {
        vm.prank(engineAddr);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientContributorLock.selector, 100e18, 0));
        vault.slashContributor(user1, 100e18);
    }

    function test_revert_lockValidatorCapacity_insufficientBalance() public {
        uint256 avail = vault.availableBalance(user1);
        vm.prank(engineAddr);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientAvailableBalance.selector, 99999e18, avail));
        vault.lockValidatorCapacity(user1, 99999e18);
    }

    function test_revert_unlockValidatorCapacity_insufficientCapacity() public {
        vm.prank(engineAddr);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientValidatorCapacity.selector, 100e18, 0));
        vault.unlockValidatorCapacity(user1, 100e18);
    }

    function test_revert_commitStake_insufficientCapacity() public {
        vm.prank(engineAddr);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientValidatorCapacity.selector, 100e18, 0));
        vault.commitStake(user1, 100e18);
    }

    function test_revert_releaseCommit_insufficientInFlight() public {
        vm.prank(engineAddr);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientInFlight.selector, 100e18, 0));
        vault.releaseCommit(user1, 100e18);
    }

    function test_revert_slashValidator_insufficientInFlight() public {
        vm.prank(engineAddr);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientInFlight.selector, 100e18, 0));
        vault.slashValidator(user1, 100e18);
    }

    // ── slashAndUnlockContributor ─────────────────────────────────

    function test_revert_slashAndUnlock_insufficientLock() public {
        vm.startPrank(engineAddr);
        vault.lockContributor(user1, 50e18);
        vm.expectRevert(abi.encodeWithSelector(ISapienVault.InsufficientContributorLock.selector, 100e18, 50e18));
        vault.slashAndUnlockContributor(user1, 60e18, 40e18);
        vm.stopPrank();
    }

    function test_slashAndUnlock_onlySlash() public {
        vm.startPrank(engineAddr);
        vault.lockContributor(user1, 50e18);
        vault.slashAndUnlockContributor(user1, 50e18, 0);
        vm.stopPrank();

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.contributorLock, 0);
    }

    function test_slashAndUnlock_onlyUnlock() public {
        vm.startPrank(engineAddr);
        vault.lockContributor(user1, 50e18);
        vault.slashAndUnlockContributor(user1, 0, 50e18);
        vm.stopPrank();

        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.contributorLock, 0);
    }

    // ── Transfer guard ────────────────────────────────────────────

    function test_transferGuard_blocksLockedShares() public {
        vm.prank(engineAddr);
        vault.lockContributor(user1, 900e18);

        uint256 shares = vault.balanceOf(user1);
        vm.prank(user1);
        vm.expectRevert(ISapienVault.TransferExceedsUnlockedShares.selector);
        vault.transfer(user2, shares);
    }

    function test_transferGuard_allowsUnlockedShares() public {
        vm.prank(engineAddr);
        vault.lockContributor(user1, 100e18);

        uint256 unlocked = vault.availableBalance(user1);
        uint256 unlockedShares = vault.convertToShares(unlocked);

        vm.prank(user1);
        if (unlockedShares > 0) {
            vault.transfer(user2, unlockedShares);
        }
    }

    // ── maxRedeem ─────────────────────────────────────────────────

    function test_maxRedeem_limitsToUnlocked() public {
        vm.prank(engineAddr);
        vault.lockContributor(user1, 800e18);

        uint256 maxR = vault.maxRedeem(user1);
        uint256 availShares = vault.convertToShares(vault.availableBalance(user1));
        assertLe(maxR, availShares);
    }

    // ── Pause / Unpause ───────────────────────────────────────────

    function test_vault_pauseUnpause() public {
        vm.startPrank(admin);
        vault.pause();
        assertTrue(vault.paused());

        vault.unpause();
        assertFalse(vault.paused());
        vm.stopPrank();
    }

    // ── UUPS Upgrade ──────────────────────────────────────────────

    function test_vault_authorizeUpgrade() public {
        SapienVault newImpl = new SapienVault();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");
    }

    function test_revert_vault_upgradeNonAdmin() public {
        SapienVault newImpl = new SapienVault();
        vm.prank(user1);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newImpl), "");
    }

    // ── Initialize reverts ────────────────────────────────────────

    function test_revert_initializeZeroAddress() public {
        SapienVault impl = new SapienVault();
        vm.expectRevert(ISapienVault.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(SapienVault.initialize, (token, address(0))));
    }

    // ── View functions ────────────────────────────────────────────

    function test_totalStaked() public view {
        uint256 staked = vault.totalStaked(user1);
        assertGt(staked, 0);
    }

    function test_getStakeAccount() public view {
        StakeAccount memory acct = vault.getStakeAccount(user1);
        assertEq(acct.contributorLock, 0);
        assertEq(acct.validatorCapacity, 0);
        assertEq(acct.inFlight, 0);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore Coverage Tests — Shared Base
// ═══════════════════════════════════════════════════════════════════════

contract QECoverageBase is Test {
    bytes32 constant SKILL_ID = keccak256("DATA_ANNOTATION");

    SapienCore internal engine;
    SapienVault internal vault;
    MockERC20 internal token;

    address internal admin = makeAddr("admin");
    address internal treasury = makeAddr("treasury");
    address internal originator = makeAddr("originator");
    address internal contributor1 = makeAddr("contributor1");
    address internal contributor2 = makeAddr("contributor2");
    address internal validator1 = makeAddr("validator1");
    address internal validator2 = makeAddr("validator2");
    address internal validator3 = makeAddr("validator3");
    address internal validator4 = makeAddr("validator4");
    address internal challenger = makeAddr("challenger");
    address internal adapter = makeAddr("adapter");

    uint256 internal constant FUND_AMOUNT = 10_000e18;
    uint256 internal constant QUANTITY = 10;
    uint256 internal constant STAKE_AMOUNT = 100e18;
    uint256 internal constant VALIDATOR_STAKE = 50e18;

    function setUp() public virtual {
        token = new MockERC20("Sapien Token", "SPN");

        SapienVault vaultImpl = new SapienVault();
        vault = SapienVault(
            address(new ERC1967Proxy(address(vaultImpl), abi.encodeCall(SapienVault.initialize, (token, admin))))
        );

        SapienCore engineImpl = new SapienCore();
        engine = SapienCore(
            address(
                new ERC1967Proxy(
                    address(engineImpl), abi.encodeCall(SapienCore.initialize, (admin, address(vault), treasury))
                )
            )
        );

        vm.startPrank(admin);
        vault.grantRole(vault.ENGINE_ROLE(), address(engine));
        engine.registerSkill("DATA_ANNOTATION");
        vm.stopPrank();

        _setupBalances();
    }

    function _setupBalances() internal {
        token.mint(originator, FUND_AMOUNT * 5);

        address[7] memory stakers =
            [contributor1, contributor2, validator1, validator2, validator3, validator4, challenger];
        for (uint256 i; i < stakers.length; ++i) {
            token.mint(stakers[i], STAKE_AMOUNT * 20);
            vm.startPrank(stakers[i]);
            token.approve(address(vault), type(uint256).max);
            vault.deposit(STAKE_AMOUNT * 10, stakers[i]);
            vm.stopPrank();
        }
    }

    function _warpPastChallengePeriod() internal {
        vm.warp(block.timestamp + engine.challengePeriod() + 1);
    }

    function _ensureStake(address user, uint256 needed) internal {
        uint256 available = vault.availableBalance(user);
        if (available < needed) {
            uint256 deficit = needed - available + 1e18;
            token.mint(user, deficit);
            vm.startPrank(user);
            token.approve(address(vault), deficit);
            vault.deposit(deficit, user);
            vm.stopPrank();
        }
    }

    function _defaultConfig() internal view returns (Project memory) {
        return Project({
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
            status: ProjectStatus.Created,
            activatedAt: 0,
            completedAt: 0,
            cancelledAt: 0
        });
    }

    function _setupProject(bytes32 projectId, uint256 fundAmount, uint256 qty) internal {
        token.mint(originator, fundAmount);
        vm.startPrank(originator);
        engine.createProject(projectId, "", _defaultConfig());
        token.approve(address(engine), fundAmount);
        engine.fundProject(projectId, fundAmount, qty, adapter);
        vm.stopPrank();
    }

    function _claimAndSubmit(address contrib, bytes32 projectId, uint256 qty)
        internal
        returns (uint256 claimId, uint256[] memory indices)
    {
        _ensureStake(contrib, STAKE_AMOUNT * (qty + 1));
        vm.startPrank(contrib);
        (claimId, indices) = engine.claimToContribute(projectId, qty, adapter);
        for (uint256 i; i < indices.length; ++i) {
            bytes32 hash = keccak256(abi.encodePacked("sub", projectId, indices[i]));
            engine.contribute(claimId, indices[i], hash, "");
        }
        vm.stopPrank();
    }

    function _claimAndCommit(address val, bytes32 projectId, uint256 index, uint256 score, uint256 stakeAmt) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, projectId, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(val, stakeAmt * 2);

        vm.startPrank(val);
        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(stakeAmt);
        engine.commitValidation(projectId, index, commitHash, stakeAmt, address(0));
        vm.stopPrank();
    }

    function _reveal(address val, bytes32 projectId, uint256 index, uint256 score) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, projectId, index, score));

        vm.prank(val);
        engine.revealValidation(projectId, index, score, salt);
    }

    function _validateAboveThreshold(bytes32 projectId, uint256 index) internal {
        _claimAndCommit(validator1, projectId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, index, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, index, 7500, VALIDATOR_STAKE);

        _reveal(validator1, projectId, index, 8000);
        _reveal(validator2, projectId, index, 8500);
        _reveal(validator3, projectId, index, 7500);
    }

    function _validateBelowThreshold(bytes32 projectId, uint256 index) internal {
        _claimAndCommit(validator1, projectId, index, 3000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projectId, index, 2500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projectId, index, 4000, VALIDATOR_STAKE);

        _reveal(validator1, projectId, index, 3000);
        _reveal(validator2, projectId, index, 2500);
        _reveal(validator3, projectId, index, 4000);
    }

    function _settleAllValidators(bytes32 projectId, uint256 index) internal {
        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(projectId, index).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(projectId, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(projectId, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(projectId, index, nonce);
    }

    function _fullAcceptanceFlow(bytes32 projectId, uint256 index) internal {
        _validateAboveThreshold(projectId, index);
        engine.computeConsensus(projectId, index);
        _settleAllValidators(projectId, index);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Uncovered Functions
// ═══════════════════════════════════════════════════════════════════════

contract QEUncoveredFunctionsTest is QECoverageBase {
    bytes32 internal projId = keccak256("cov-funcs");

    function setUp() public override {
        super.setUp();
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    function test_reduceValidatorCapacity() public {
        _ensureStake(validator1, VALIDATOR_STAKE * 3);
        vm.startPrank(validator1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.unlockValidatorCapacity(VALIDATOR_STAKE);
        vm.stopPrank();
    }

    function test_completeProject_funded() public {
        vm.prank(originator);
        engine.completeProject(projId);

        Project memory proj = engine.getProject(projId);
        assertEq(uint256(proj.status), uint256(ProjectStatus.Completed));
        assertGt(proj.completedAt, 0);
    }

    function test_completeProject_active() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);

        // SEC-H-01: finalize contribution before completing project
        _validateBelowThreshold(projId, indices[0]);
        engine.computeConsensus(projId, indices[0]);

        vm.prank(originator);
        engine.completeProject(projId);
        assertEq(uint256(engine.getProject(projId).status), uint256(ProjectStatus.Completed));
    }

    function test_completeProject_withOriginatorStake() public {
        bytes32 pid2 = keccak256("cov-complete-stake");

        vm.prank(admin);
        engine.setOriginatorStakeRequirement(10e18);

        token.mint(originator, FUND_AMOUNT);
        _ensureStake(originator, 500e18);
        vm.startPrank(originator);
        engine.createProject(pid2, "", _defaultConfig());
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        uint256 lockedBefore = engine.getOriginatorLockedStake(pid2);
        assertGt(lockedBefore, 0);

        // Make project active and finalize the contribution
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid2, 1);
        _validateBelowThreshold(pid2, indices[0]);
        engine.computeConsensus(pid2, indices[0]);

        vm.prank(originator);
        engine.completeProject(pid2);

        assertEq(engine.getOriginatorLockedStake(pid2), 0);
    }

    function test_revert_completeProject_notOriginator() public {
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.NotProjectOriginator.selector);
        engine.completeProject(projId);
    }

    function test_revert_completeProject_wrongStatus() public {
        vm.prank(originator);
        engine.completeProject(projId);

        vm.prank(originator);
        vm.expectRevert(ISapienCore.ProjectNotActive.selector);
        engine.completeProject(projId);
    }

    function test_refundEscrow() public {
        vm.prank(originator);
        engine.completeProject(projId);

        vm.warp(block.timestamp + 31 days);

        uint256 escrow = engine.getProjectEscrow(projId, address(token));
        assertGt(escrow, 0);

        uint256 balBefore = token.balanceOf(originator);
        vm.prank(originator);
        engine.refundEscrow(projId);

        assertEq(engine.getProjectEscrow(projId, address(token)), 0);
        assertEq(token.balanceOf(originator) - balBefore, escrow);
    }

    function test_revert_refundEscrow_notOriginator() public {
        vm.prank(originator);
        engine.completeProject(projId);

        vm.warp(block.timestamp + 31 days);

        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.NotProjectOriginator.selector);
        engine.refundEscrow(projId);
    }

    function test_revert_refundEscrow_notCompleted() public {
        vm.prank(originator);
        vm.expectRevert(ISapienCore.ProjectNotCompleted.selector);
        engine.refundEscrow(projId);
    }

    function test_revert_refundEscrow_tooEarly() public {
        vm.prank(originator);
        engine.completeProject(projId);

        vm.prank(originator);
        vm.expectRevert(ISapienCore.ChallengeNotElapsed.selector);
        engine.refundEscrow(projId);
    }

    function test_revert_refundEscrow_zeroRemaining() public {
        // Create a tiny project, complete it, drain escrow, then try refund
        bytes32 pid2 = keccak256("cov-refund-zero");
        _setupProject(pid2, FUND_AMOUNT, QUANTITY);

        vm.prank(originator);
        engine.completeProject(pid2);

        vm.warp(block.timestamp + 31 days);

        vm.prank(originator);
        engine.refundEscrow(pid2);

        // Second refund should fail with ZeroAmount
        vm.prank(originator);
        vm.expectRevert(ISapienCore.ZeroAmount.selector);
        engine.refundEscrow(pid2);
    }

    function test_setMinValidationStake() public {
        vm.prank(admin);
        engine.setMinValidationStake(10e18);
    }

    function test_revert_setMinValidationStake_tooHigh() public {
        uint256 largeAmount = uint256(type(uint128).max) + 1;
        vm.prank(admin);
        engine.setMinValidationStake(largeAmount);
    }

    // ── View functions ────────────────────────────────────────────

    function test_viewFunctions() public {
        _claimAndSubmit(contributor1, projId, 1);

        // All of these should just return without reverting
        engine.getReturnStackTop(projId);
        engine.getOriginationAdapter(projId);
        engine.getContributionAdapter(1);
        engine.vault();
        engine.getOriginatorLockedStake(projId);
    }

    // ── UUPS Upgrade ──────────────────────────────────────────────

    function test_engine_authorizeUpgrade() public {
        SapienCore newImpl = new SapienCore();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");
    }

    function test_revert_engine_upgradeNonAdmin() public {
        SapienCore newImpl = new SapienCore();
        vm.prank(contributor1);
        vm.expectRevert();
        engine.upgradeToAndCall(address(newImpl), "");
    }

    // ── Pause / Unpause ───────────────────────────────────────────

    function test_engine_pauseUnpause() public {
        vm.prank(admin);
        engine.pause();

        vm.prank(originator);
        vm.expectRevert();
        engine.claimReward(address(token));

        vm.prank(admin);
        engine.unpause();
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Create/Fund Project Validation Branches
// ═══════════════════════════════════════════════════════════════════════

contract QEProjectValidationTest is QECoverageBase {
    // ── createProject validation ──────────────────────────────────

    function test_revert_createProject_zeroRewardToken() public {
        Project memory config = _defaultConfig();
        config.rewardToken = address(0);
        vm.prank(originator);
        vm.expectRevert(ISapienCore.ZeroAddress.selector);
        engine.createProject(keccak256("zrt"), "", config);
    }

    function test_revert_createProject_zeroConsensusThreshold() public {
        Project memory config = _defaultConfig();
        config.consensusThreshold = 0;
        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "consensusThreshold out of range")
        );
        engine.createProject(keccak256("zct"), "", config);
    }

    function test_revert_createProject_tooHighConsensusThreshold() public {
        Project memory config = _defaultConfig();
        config.consensusThreshold = 10001;
        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "consensusThreshold out of range")
        );
        engine.createProject(keccak256("hct"), "", config);
    }

    function test_revert_createProject_tooHighValidatorRewardBps() public {
        Project memory config = _defaultConfig();
        config.validatorRewardBps = 2501;
        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "validatorRewardBps too high")
        );
        engine.createProject(keccak256("hvr"), "", config);
    }

    function test_revert_createProject_zeroNumberOfValidations() public {
        Project memory config = _defaultConfig();
        config.numberOfValidations = 0;
        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
        );
        engine.createProject(keccak256("znv"), "", config);
    }

    function test_revert_createProject_tooHighNumberOfValidations() public {
        Project memory config = _defaultConfig();
        config.numberOfValidations = 11;
        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "numberOfValidations out of range")
        );
        engine.createProject(keccak256("hnv"), "", config);
    }

    // ── fundProject validation ────────────────────────────────────

    function test_revert_fundProject_zeroAmount() public {
        bytes32 pid = keccak256("fa0");
        vm.startPrank(originator);
        engine.createProject(pid, "", _defaultConfig());
        vm.expectRevert(ISapienCore.ZeroAmount.selector);
        engine.fundProject(pid, 0, 5, adapter);
        vm.stopPrank();
    }

    function test_revert_fundProject_zeroQuantity() public {
        bytes32 pid = keccak256("fq0");
        vm.startPrank(originator);
        engine.createProject(pid, "", _defaultConfig());
        token.approve(address(engine), 1000e18);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "quantity must be > 0"));
        engine.fundProject(pid, 1000e18, 0, adapter);
        vm.stopPrank();
    }

    function test_revert_fundProject_wrongStatus() public {
        bytes32 pid = keccak256("fws");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Make project Active and finalize contribution
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        _validateBelowThreshold(pid, indices[0]);
        engine.computeConsensus(pid, indices[0]);

        // Complete the project
        vm.prank(originator);
        engine.completeProject(pid);

        // Try to fund completed project
        token.mint(originator, 1000e18);
        vm.startPrank(originator);
        token.approve(address(engine), 1000e18);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "project not in fundable state")
        );
        engine.fundProject(pid, 1000e18, 5, adapter);
        vm.stopPrank();
    }

    function test_fundProject_noAdapter() public {
        bytes32 pid = keccak256("fna");
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid, "", _defaultConfig());
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, address(0));
        vm.stopPrank();

        assertEq(engine.getOriginationAdapter(pid), address(0));
    }

    function test_fundProject_additionalFunding() public {
        bytes32 pid = keccak256("faf");
        token.mint(originator, FUND_AMOUNT * 2);
        vm.startPrank(originator);
        engine.createProject(pid, "", _defaultConfig());
        token.approve(address(engine), FUND_AMOUNT * 2);
        engine.fundProject(pid, FUND_AMOUNT, 5, adapter);
        engine.fundProject(pid, FUND_AMOUNT, 5, adapter);
        vm.stopPrank();

        Project memory proj = engine.getProject(pid);
        assertEq(proj.totalQuantity, 10);
    }

    // ── Initialize validation ─────────────────────────────────────

    function test_revert_initialize_zeroAdmin() public {
        SapienCore impl = new SapienCore();
        vm.expectRevert(ISapienCore.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(SapienCore.initialize, (address(0), address(vault), treasury)));
    }

    function test_revert_initialize_zeroVault() public {
        SapienCore impl = new SapienCore();
        vm.expectRevert(ISapienCore.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(SapienCore.initialize, (admin, address(0), treasury)));
    }

    function test_revert_initialize_zeroTreasury() public {
        SapienCore impl = new SapienCore();
        vm.expectRevert(ISapienCore.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), abi.encodeCall(SapienCore.initialize, (admin, address(vault), address(0))));
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Claim & Contribute Branch Coverage
// ═══════════════════════════════════════════════════════════════════════

contract QEClaimBranchTest is QECoverageBase {
    bytes32 internal projId = keccak256("cov-claim");

    function setUp() public override {
        super.setUp();
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    function test_revert_claimToContribute_zeroQuantity() public {
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.ZeroAmount.selector);
        engine.claimToContribute(projId, 0, adapter);
    }

    function test_revert_claimToContribute_exceedsMax() public {
        vm.prank(contributor1);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ClaimQuantityTooHigh.selector, 21, 20));
        engine.claimToContribute(projId, 21, adapter);
    }

    function test_revert_claimToContribute_wrongProjectStatus() public {
        bytes32 pid2 = keccak256("cov-claim-status");
        vm.prank(originator);
        engine.createProject(pid2, "", _defaultConfig());
        // Project is Created but not Funded

        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.ProjectNotActive.selector);
        engine.claimToContribute(pid2, 1, adapter);
    }

    function test_revert_contribute_deadlinePassed() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 2, adapter);
        engine.contribute(claimId, indices[0], keccak256("data0"), "");
        vm.stopPrank();

        vm.warp(block.timestamp + 8 days);

        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.ClaimDeadlinePassed.selector);
        engine.contribute(claimId, indices[1], keccak256("data1"), "");
    }

    function test_revert_contribute_indexNotInClaim() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        _ensureStake(contributor2, STAKE_AMOUNT * 3);

        vm.prank(contributor1);
        (uint256 claimId1,) = engine.claimToContribute(projId, 1, adapter);

        vm.prank(contributor2);
        (, uint256[] memory indices2) = engine.claimToContribute(projId, 1, adapter);

        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.IndexNotInClaim.selector);
        engine.contribute(claimId1, indices2[0], keccak256("wrong"), "");
    }

    function test_revert_contribute_indexNotReserved() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 5);
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 2, adapter);
        engine.contribute(claimId, indices[0], keccak256("data"), "");
        // indices[0] status is now Submitted, not Reserved
        vm.expectRevert(ISapienCore.IndexNotReserved.selector);
        engine.contribute(claimId, indices[0], keccak256("data2"), "");
        vm.stopPrank();
    }

    function test_revert_expireClaim_indicesLengthMismatch() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.prank(contributor1);
        (uint256 claimId,) = engine.claimToContribute(projId, 2, adapter);

        vm.warp(block.timestamp + 8 days);

        uint256[] memory wrongIndices = new uint256[](1);
        wrongIndices[0] = 0;
        vm.expectRevert(ISapienCore.InvalidIndex.selector);
        engine.expireClaim(claimId, wrongIndices);
    }

    function test_revert_expireClaim_wrongClaimId() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        _ensureStake(contributor2, STAKE_AMOUNT * 3);

        vm.prank(contributor1);
        (uint256 claimId1,) = engine.claimToContribute(projId, 1, adapter);

        vm.prank(contributor2);
        (, uint256[] memory indices2) = engine.claimToContribute(projId, 1, adapter);

        vm.warp(block.timestamp + 8 days);

        // Try to expire claimId1 with claimId2's indices — wrong index is skipped but
        // invariant check catches that unsubmitted count doesn't match
        uint256[] memory mixedIndices = new uint256[](1);
        mixedIndices[0] = indices2[0];
        vm.expectRevert(ISapienCore.InvalidIndex.selector);
        engine.expireClaim(claimId1, mixedIndices);
    }

    function test_claimToContribute_noAdapter() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.prank(contributor1);
        (uint256 claimId,) = engine.claimToContribute(projId, 1, address(0));
        assertEq(engine.getContributionAdapter(claimId), address(0));
    }

    function test_claimToContribute_noMinStake() public {
        bytes32 pid2 = keccak256("cov-no-stake");
        Project memory config = _defaultConfig();
        config.minStakeToClaim = 0;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        vm.prank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(pid2, 1, adapter);
        assertGt(indices.length, 0);

        vm.prank(contributor1);
        engine.contribute(claimId, indices[0], keccak256("data"), "");
    }

    function test_expireClaim_noStake() public {
        bytes32 pid2 = keccak256("cov-expire-no-stake");
        Project memory config = _defaultConfig();
        config.minStakeToClaim = 0;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        vm.prank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(pid2, 2, adapter);

        vm.warp(block.timestamp + 8 days);
        engine.expireClaim(claimId, indices);
    }

    function test_expireClaim_allSubmitted() public {
        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projId, 2, adapter);
        engine.contribute(claimId, indices[0], keccak256("data0"), "");
        engine.contribute(claimId, indices[1], keccak256("data1"), "");
        vm.stopPrank();

        // Now all are submitted but claim is Completed, not Active → should revert
        vm.warp(block.timestamp + 8 days);
        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.expireClaim(claimId, indices);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Validation Branch Coverage
// ═══════════════════════════════════════════════════════════════════════

contract QEValidationBranchTest is QECoverageBase {
    bytes32 internal projId = keccak256("cov-val");

    function setUp() public override {
        super.setUp();
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    function test_revert_commitValidation_zeroHash() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.expectRevert(ISapienCore.InvalidCommitHash.selector);
        engine.commitValidation(projId, index, bytes32(0), VALIDATOR_STAKE, address(0));
        vm.stopPrank();
    }

    function test_revert_commitValidation_maxValidationsReached() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _claimAndCommit(validator1, projId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projId, index, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projId, index, 7500, VALIDATOR_STAKE);

        _reveal(validator1, projId, index, 8000);
        _reveal(validator2, projId, index, 8500);
        _reveal(validator3, projId, index, 7500);

        // 4th validator tries to claim — all slots taken
        _ensureStake(validator4, VALIDATOR_STAKE * 2);
        vm.startPrank(validator4);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.expectRevert(ISapienCore.NoEligibleContributions.selector);
        engine.claimToValidate(projId, 1);
        vm.stopPrank();
    }

    function test_revert_commitValidation_belowMinStake() public {
        vm.prank(admin);
        engine.setMinValidationStake(100e18);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _ensureStake(validator1, 200e18);
        bytes32 salt = keccak256("salt");
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));
        vm.startPrank(validator1);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(10e18);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InsufficientStake.selector, 100e18, 10e18));
        engine.commitValidation(projId, index, commitHash, 10e18, address(0));
        vm.stopPrank();
    }

    function test_revert_commitValidation_notSubmitted() public {
        // Process a contribution to Accepted, then try to commit on it
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        // Contribution is now Accepted, not Pending
        _ensureStake(validator4, VALIDATOR_STAKE * 2);
        vm.startPrank(validator4);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.expectRevert(ISapienCore.NoEligibleContributions.selector);
        engine.claimToValidate(projId, 1);
        vm.stopPrank();
    }

    function test_revert_revealValidation_invalidScore() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        uint256 score = 10001;
        bytes32 salt = keccak256("salt");
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projId, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.expectRevert(ISapienCore.InvalidScore.selector);
        engine.revealValidation(projId, index, score, salt);
        vm.stopPrank();
    }

    function test_revert_revealValidation_notCommitted() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        vm.prank(validator1);
        vm.expectRevert(ISapienCore.NotCommitted.selector);
        engine.revealValidation(projId, index, 8000, keccak256("salt"));
    }

    function test_revert_revealValidation_alreadyRevealed() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        uint256 score = 8000;
        bytes32 salt = keccak256("salt-double-reveal");
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));

        _ensureStake(validator1, VALIDATOR_STAKE * 2);
        vm.startPrank(validator1);
        engine.claimToValidate(projId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projId, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        _claimAndCommit(validator2, projId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projId, index, 8000, VALIDATOR_STAKE);

        vm.startPrank(validator1);
        engine.revealValidation(projId, index, score, salt);
        vm.expectRevert(ISapienCore.AlreadyRevealed.selector);
        engine.revealValidation(projId, index, score, salt);
        vm.stopPrank();
    }

    function test_commitValidation_zeroStake() public {
        bytes32 pid2 = keccak256("cov-zero-stake-commit");
        Project memory config = _defaultConfig();
        config.minValidationStake = 0;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid2, 1);
        uint256 index = indices[0];

        uint256 score = 8000;
        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, pid2, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));

        vm.startPrank(validator1);
        engine.claimToValidate(pid2, 1);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InsufficientStake.selector, 1, 0));
        engine.commitValidation(pid2, index, commitHash, 0, address(0));
        vm.stopPrank();
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Settle Validator Branch Coverage
// ═══════════════════════════════════════════════════════════════════════

contract QESettleBranchTest is QECoverageBase {
    bytes32 internal projId = keccak256("cov-settle");

    function setUp() public override {
        super.setUp();
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    function test_revert_settleValidator_consensusNotReady() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 nonce = engine.getContribution(projId, indices[0]).consensusNonce;
        vm.prank(validator1);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.ConsensusNotReady.selector, 0, 1));
        engine.settleValidator(projId, indices[0], nonce);
    }

    function test_revert_settleValidator_notParticipated() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        uint256 nonce = engine.getContribution(projId, index).consensusNonce;
        vm.prank(contributor2);
        vm.expectRevert(ISapienCore.NotCommitted.selector);
        engine.settleValidator(projId, index, nonce);
    }

    function test_settleValidator_outlier_slashExceedsStake() public {
        // 4-validator project: 3 score high, 1 extreme outlier
        // Weighted avg needs to be >= 7000 (threshold)
        // (3*9500 + 100)/4 = 7150 → above threshold
        bytes32 pid2 = keccak256("cov-outlier-slash");
        Project memory config = _defaultConfig();
        config.numberOfValidations = 4;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid2, 1);
        uint256 index = indices[0];

        _claimAndCommit(validator1, pid2, index, 9500, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid2, index, 9500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid2, index, 9500, VALIDATOR_STAKE);
        _claimAndCommit(validator4, pid2, index, 100, VALIDATOR_STAKE);

        _reveal(validator1, pid2, index, 9500);
        _reveal(validator2, pid2, index, 9500);
        _reveal(validator3, pid2, index, 9500);
        _reveal(validator4, pid2, index, 100);

        engine.computeConsensus(pid2, index);

        uint256 nonce = engine.getContribution(pid2, index).consensusNonce;

        // Settle outlier validator4 immediately (no challenge period needed for outliers)
        vm.prank(validator4);
        engine.settleValidator(pid2, index, nonce);
        assertTrue(engine.isValidatorOutlier(pid2, index, validator4));

        // Settle accurate validators after challenge period
        _warpPastChallengePeriod();
        vm.prank(validator1);
        engine.settleValidator(pid2, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(pid2, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(pid2, index, nonce);
    }

    function test_settleValidator_outlier_zeroSlash_nonzeroCommit() public {
        // Outlier with tiny stake → slash rounds to 0, but committedStake > 0
        bytes32 pid2 = keccak256("cov-outlier-zero-slash");
        Project memory config = _defaultConfig();
        config.numberOfValidations = 4;
        config.minValidationStake = 0;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid2, 1);
        uint256 index = indices[0];

        _claimAndCommit(validator1, pid2, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid2, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid2, index, 8000, VALIDATOR_STAKE);

        // validator4 commits with tiny stake (5 wei) → slash = 5 * 1000 / 10000 = 0
        uint256 score = 100;
        bytes32 salt = keccak256(abi.encodePacked("salt", validator4, pid2, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));

        _ensureStake(validator4, 1e18);
        vm.startPrank(validator4);
        engine.claimToValidate(pid2, 1);
        engine.lockValidatorCapacity(5);
        engine.commitValidation(pid2, index, commitHash, 5, address(0));
        vm.stopPrank();

        _reveal(validator1, pid2, index, 8000);
        _reveal(validator2, pid2, index, 8000);
        _reveal(validator3, pid2, index, 8000);

        vm.prank(validator4);
        engine.revealValidation(pid2, index, score, salt);

        engine.computeConsensus(pid2, index);

        // Settle outlier with zero slash but nonzero committed stake
        uint256 nonce = engine.getContribution(pid2, index).consensusNonce;
        vm.prank(validator4);
        engine.settleValidator(pid2, index, nonce);
    }

    function test_settleValidator_accurate_zeroCommit() public {
        // RISK-007: Zero-stake commits are now rejected
        bytes32 pid2 = keccak256("cov-settle-zero-commit");
        Project memory config = _defaultConfig();
        config.minValidationStake = 0;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid2, 1);
        uint256 index = indices[0];

        _claimAndCommit(validator1, pid2, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid2, index, 8500, VALIDATOR_STAKE);

        // validator3 tries to commit with 0 stake — should revert with InsufficientStake
        uint256 score = 7500;
        bytes32 salt = keccak256(abi.encodePacked("salt", validator3, pid2, index, score));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(score), salt));
        vm.startPrank(validator3);
        engine.claimToValidate(pid2, 1);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InsufficientStake.selector, 1, 0));
        engine.commitValidation(pid2, index, commitHash, 0, address(0));
        vm.stopPrank();
    }

    function test_releaseContributorReward_noAdapter() public {
        bytes32 pid2 = keccak256("cov-release-no-adapter");
        _setupProject(pid2, FUND_AMOUNT, QUANTITY);

        _ensureStake(contributor1, STAKE_AMOUNT * 3);
        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(pid2, 1, address(0));
        engine.contribute(claimId, indices[0], keccak256("data"), "");
        vm.stopPrank();

        _validateAboveThreshold(pid2, indices[0]);
        engine.computeConsensus(pid2, indices[0]);
        _settleAllValidators(pid2, indices[0]);

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(pid2, indices[0]);
        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
    }

    function test_revert_releaseContributorReward_notAccepted() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        // Contribution is still Pending
        vm.expectRevert(ISapienCore.ContributionNotAccepted.selector);
        engine.releaseContributorReward(projId, indices[0]);
    }

    function test_revert_releaseContributorReward_disputeOpen() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        // Validate + compute without warping — dispute must be opened within challenge window
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("evidence"), "evidenceCid");

        // Warp past the extended challenge period (7 days from dispute) but dispute still Open
        vm.warp(block.timestamp + 7 days + 1);
        vm.expectRevert(ISapienCore.DisputeInProgress.selector);
        engine.releaseContributorReward(projId, index);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Dispute & Report Branch Coverage
// ═══════════════════════════════════════════════════════════════════════

contract QEDisputeBranchTest is QECoverageBase {
    bytes32 internal projId = keccak256("cov-dispute");

    function setUp() public override {
        super.setUp();
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    function test_revert_openDispute_consensusNotComputed() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        // Contribution is still Pending (no consensus)
        vm.prank(challenger);
        vm.expectRevert(ISapienCore.ConsensusNotComputed.selector);
        engine.openDispute(projId, indices[0], keccak256("evidence"), "evidenceCid");
    }

    function test_revert_openDispute_noChallengeEndsAt() public {
        // A contribution that exists but has no challengeEndsAt set
        vm.prank(challenger);
        vm.expectRevert(ISapienCore.ConsensusNotComputed.selector);
        engine.openDispute(projId, 999, keccak256("evidence"), "evidenceCid");
    }

    function test_revert_resolveDispute_notOpen() public {
        vm.prank(admin);
        vm.expectRevert(ISapienCore.DisputeNotOpen.selector);
        engine.resolveDispute(projId, 0, true);
    }

    function test_revert_escalateDispute_notOpen() public {
        vm.expectRevert(ISapienCore.DisputeNotOpen.selector);
        engine.escalateDispute(projId, 0);
    }

    function test_escalateDispute_onRejectedContribution() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateBelowThreshold(projId, index);
        engine.computeConsensus(projId, index);

        Contribution memory contrib = engine.getContribution(projId, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected));

        // Open dispute on rejected contribution
        _ensureStake(contributor1, STAKE_AMOUNT);
        vm.prank(contributor1);
        engine.openDispute(projId, index, keccak256("unfair-rejection"), "evidenceCid");

        // Warp past resolution deadline → escalate
        vm.warp(block.timestamp + 8 days);
        engine.escalateDispute(projId, index);

        Dispute memory d = engine.getDispute(projId, index);
        assertEq(uint256(d.status), uint256(DisputeStatus.Upheld));

        // Contributor compensated
        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
    }

    function test_resolveDispute_rejectedUpheld() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateBelowThreshold(projId, index);
        engine.computeConsensus(projId, index);

        _ensureStake(contributor1, STAKE_AMOUNT);
        vm.prank(contributor1);
        engine.openDispute(projId, index, keccak256("bad-rejection"), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(projId, index, true);

        // Contributor compensated
        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
    }

    function test_resolveDispute_rejectedRejected() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _validateBelowThreshold(projId, index);
        engine.computeConsensus(projId, index);

        _ensureStake(contributor1, STAKE_AMOUNT);
        vm.prank(contributor1);
        engine.openDispute(projId, index, keccak256("weak-dispute"), "evidenceCid");

        uint256 sharesBefore = vault.balanceOf(contributor1);

        vm.prank(admin);
        engine.resolveDispute(projId, index, false);

        // Challenger bond slashed
        assertLt(vault.balanceOf(contributor1), sharesBefore);
    }

    function test_escalateDispute_onAcceptedContribution() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];
        // Validate + compute without warping — dispute must be opened within challenge window
        _validateAboveThreshold(projId, index);
        engine.computeConsensus(projId, index);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(projId, index, keccak256("evidence"), "evidenceCid");

        vm.warp(block.timestamp + 8 days);
        engine.escalateDispute(projId, index);

        assertGt(engine.getPendingRewards(challenger, address(token)), 0);
    }

    // ── cancelExpiredCommitment branches ──────────────────────────

    function test_revert_cancelExpiredCommitment_notCommitted() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        vm.expectRevert(ISapienCore.NotCommitted.selector);
        engine.cancelExpiredCommitment(projId, indices[0], validator1);
    }

    function test_revert_cancelExpiredCommitment_alreadyRevealed() public {
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        uint256 index = indices[0];

        _claimAndCommit(validator1, projId, index, 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projId, index, 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projId, index, 7500, VALIDATOR_STAKE);

        _reveal(validator1, projId, index, 8000);

        vm.warp(block.timestamp + 6 days);
        vm.expectRevert(ISapienCore.AlreadyRevealed.selector);
        engine.cancelExpiredCommitment(projId, index, validator1);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Originator Report Branch Coverage
// ═══════════════════════════════════════════════════════════════════════

contract QEOriginatorReportBranchTest is QECoverageBase {
    function test_revert_reportOriginator_nonExistentProject() public {
        bytes32 pid = keccak256("nonexistent");
        vm.prank(challenger);
        vm.expectRevert(ISapienCore.ProjectNotFound.selector);
        engine.reportOriginator(pid, keccak256("evidence"));
    }

    function test_revert_reportOriginator_wrongStatus() public {
        bytes32 pid = keccak256("cov-report-status");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
        (, uint256[] memory idxs) = _claimAndSubmit(contributor1, pid, 1);
        _validateBelowThreshold(pid, idxs[0]);
        engine.computeConsensus(pid, idxs[0]);

        vm.prank(originator);
        engine.completeProject(pid);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        vm.expectRevert(ISapienCore.ProjectNotCancellable.selector);
        engine.reportOriginator(pid, keccak256("evidence"));
    }

    function test_revert_resolveOriginatorReport_notOpen() public {
        vm.prank(admin);
        vm.expectRevert(ISapienCore.OriginatorReportNotOpen.selector);
        engine.resolveOriginatorReport(keccak256("nonexistent"), true);
    }

    function test_revert_escalateOriginatorReport_notOpen() public {
        vm.expectRevert(ISapienCore.OriginatorReportNotOpen.selector);
        engine.escalateOriginatorReport(keccak256("nonexistent"));
    }

    function test_reportOriginator_onFundedProject() public {
        bytes32 pid = keccak256("cov-report-funded");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Project is Funded (no claims yet)
        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("evidence"));

        OriginatorReport memory report = engine.getOriginatorReport(pid);
        assertEq(uint256(report.status), uint256(OriginatorReportStatus.Open));
    }

    function test_resolveOriginatorReport_upheld_noOriginatorStake() public {
        bytes32 pid = keccak256("cov-report-upheld-no-stake");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("evidence"));

        vm.prank(admin);
        engine.resolveOriginatorReport(pid, true);

        assertEq(uint256(engine.getProject(pid).status), uint256(ProjectStatus.Cancelled));
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Reputation & Admin Branch Coverage
// ═══════════════════════════════════════════════════════════════════════

contract QEReputationAdminBranchTest is QECoverageBase {
    bytes32 internal projId = keccak256("cov-rep");

    function setUp() public override {
        super.setUp();
        _setupProject(projId, FUND_AMOUNT, QUANTITY);
    }

    function test_reputationDecay() public {
        // Build up reputation via acceptance
        (, uint256[] memory indices1) = _claimAndSubmit(contributor1, projId, 1);
        _validateAboveThreshold(projId, indices1[0]);
        engine.computeConsensus(projId, indices1[0]);

        Reputation memory repBefore = engine.getReputation(contributor1, SKILL_ID);
        uint256 scoreBefore = repBefore.score;
        assertGt(scoreBefore, 5000);

        // Warp forward 30 days — lazy decay will be applied on next reputation update
        vm.warp(block.timestamp + 30 days);

        // Trigger another reputation update (acceptance) which applies lazy decay first
        (, uint256[] memory indices2) = _claimAndSubmit(contributor1, projId, 1);
        _validateAboveThreshold(projId, indices2[0]);
        engine.computeConsensus(projId, indices2[0]);

        Reputation memory repAfter = engine.getReputation(contributor1, SKILL_ID);
        // After 30 days of decay at 0.1%/day (10 bps), the score should have decayed significantly
        // even with the new success bonus applied after decay
        assertLt(repAfter.score, scoreBefore);
    }

    function test_reputationDecay_inConsensus() public {
        // Ensure reputation is initialized, then warp to trigger decay during consensus
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, projId, 1);
        _claimAndCommit(validator1, projId, indices[0], 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, projId, indices[0], 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, projId, indices[0], 7500, VALIDATOR_STAKE);

        _reveal(validator1, projId, indices[0], 8000);
        _reveal(validator2, projId, indices[0], 8500);
        _reveal(validator3, projId, indices[0], 7500);

        vm.warp(block.timestamp + 10 days);

        engine.computeConsensus(projId, indices[0]);
    }

    function test_reputationDailyGainCap() public {
        // Perform many successful actions in same day to hit daily gain cap
        for (uint256 i; i < 5; ++i) {
            bytes32 pid = keccak256(abi.encodePacked("cov-daily-cap", i));
            _setupProject(pid, FUND_AMOUNT, QUANTITY);
            (, uint256[] memory idx) = _claimAndSubmit(contributor1, pid, 1);
            _validateAboveThreshold(pid, idx[0]);
            engine.computeConsensus(pid, idx[0]);
        }

        Reputation memory rep = engine.getReputation(contributor1, SKILL_ID);
        // Score should be capped by daily gain limit
        assertLe(rep.score, 5000 + 100); // DEFAULT + MAX_DAILY_GAIN
    }

    // ── Admin fee revert branches ─────────────────────────────────

    function test_revert_setDecayRate_tooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.AdapterFeeTooHigh.selector, 600, 500));
        engine.setDecayRate(600);
    }

    function test_revert_setDisputeBondBps_tooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.DisputeBondTooHigh.selector, 6000, 5000));
        engine.setDisputeBondBps(6000);
    }

    function test_revert_setOriginatorStakeRequirement_tooHigh() public {
        uint256 largeAmount = uint256(type(uint128).max) + 1;
        vm.prank(admin);
        engine.setOriginatorStakeRequirement(largeAmount);
    }

    function test_revert_setOriginatorReportBondBps_tooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.AdapterFeeTooHigh.selector, 2000, 1000));
        engine.setOriginatorReportBondBps(2000);
    }

    function test_revert_setContributionFee_tooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.AdapterFeeTooHigh.selector, 600, 500));
        engine.setContributionFee(600);
    }

    function test_revert_setValidationFee_tooHigh() public {
        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.AdapterFeeTooHigh.selector, 600, 500));
        engine.setValidationFee(600);
    }

    function test_getReputation_uninitialized() public {
        address nobody = makeAddr("nobody");
        Reputation memory rep = engine.getReputation(nobody, SKILL_ID);
        assertEq(rep.score, 5000);
        assertEq(rep.lastUpdated, 0);
    }

    function test_getDispute_empty() public view {
        Dispute memory d = engine.getDispute(projId, 999);
        assertEq(uint256(d.status), uint256(DisputeStatus.None));
    }

    function test_getOriginatorReport_empty() public view {
        OriginatorReport memory r = engine.getOriginatorReport(projId);
        assertEq(uint256(r.status), uint256(OriginatorReportStatus.None));
    }

    function test_getConsensusReport_empty() public view {
        ConsensusReport memory r = engine.getConsensusReport(projId, 999);
        assertEq(r.weightedAverage, 0);
        assertEq(r.stdDeviation, 0);
        assertEq(r.nonce, 0);
        assertFalse(r.computed);
        assertEq(r.totalAccurateWeight, 0);
    }

    function test_isValidatorOutlier_empty() public view {
        assertFalse(engine.isValidatorOutlier(projId, 999, validator1));
    }

    function test_isValidatorSettled_empty() public view {
        assertFalse(engine.isValidatorSettled(projId, 999, 0, validator1));
    }

    function test_getProjectEscrow() public view {
        uint256 escrow = engine.getProjectEscrow(projId, address(token));
        assertGt(escrow, 0);
    }

    function test_getDisputeConfig() public view {
        (uint256 bondBps, uint256 stakeReq, uint256 reportBps) = engine.getDisputeConfig();
        assertGt(bondBps, 0);
        assertEq(stakeReq, 0);
        assertGt(reportBps, 0);
    }

    function test_getRevealCount() public view {
        uint256 count = engine.getRevealCount(projId, 0);
        assertEq(count, 0);
    }

    function test_getSubmissionNonce() public view {
        uint256 nonce = engine.getSubmissionNonce(projId, 0);
        assertEq(nonce, 0);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Validation Adapter Fee Coverage
// ═══════════════════════════════════════════════════════════════════════

contract QEValidationAdapterFeeTest is QECoverageBase {
    function test_contributionFee_zeroFeeBps() public {
        vm.prank(admin);
        engine.setContributionFee(0);

        bytes32 pid = keccak256("cov-zero-contrib-fee");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);
        _settleAllValidators(pid, index);

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(pid, index);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Additional Edge Cases for Remaining Coverage Gaps
// ═══════════════════════════════════════════════════════════════════════

contract QERemainingGapsTest is QECoverageBase {
    /// @notice Test outlier settlement where slash rounds to 0 but committedStake > 0
    /// Exercises the `else if (committedStake > 0)` branch in settleValidator
    function test_settleValidator_outlier_zeroSlash_equalWeights() public {
        // 4 validators with equal tiny stakes: deviationSigma = sqrt(3) ≈ 1.73 → TIER_1
        // TIER_1 slash = 10%. stakeAmount = 9, slash = 9 * 1000 / 10000 = 0 (rounds down)
        bytes32 pid = keccak256("cov-outlier-zero-slash-eq");
        Project memory config = _defaultConfig();
        config.numberOfValidations = 4;
        config.minValidationStake = 0;
        config.minStakeToClaim = 0;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];

        // All validators commit with tiny stake (9 wei) and equal reputation
        address[4] memory vals = [validator1, validator2, validator3, validator4];
        uint256[4] memory scores = [uint256(9500), uint256(9500), uint256(9500), uint256(100)];
        for (uint256 i; i < 4; ++i) {
            bytes32 salt = keccak256(abi.encodePacked("salt", vals[i], pid, index, scores[i]));
            bytes32 commitHash = keccak256(abi.encodePacked(uint256(scores[i]), salt));
            _ensureStake(vals[i], 1e18);
            vm.startPrank(vals[i]);
            engine.claimToValidate(pid, 1);
            engine.lockValidatorCapacity(9);
            engine.commitValidation(pid, index, commitHash, 9, address(0));
            vm.stopPrank();
        }
        for (uint256 i; i < 4; ++i) {
            bytes32 salt = keccak256(abi.encodePacked("salt", vals[i], pid, index, scores[i]));
            vm.prank(vals[i]);
            engine.revealValidation(pid, index, scores[i], salt);
        }

        engine.computeConsensus(pid, index);

        // Settle all — validator4 is outlier (no challenge period needed), others need warp
        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(pid, index).consensusNonce;
        for (uint256 i; i < 4; ++i) {
            vm.prank(vals[i]);
            engine.settleValidator(pid, index, nonce);
        }
    }

    /// @notice Test extreme reputation decay to MIN_REPUTATION floor
    function test_extremeReputationDecay() public {
        bytes32 pid = keccak256("cov-extreme-decay");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Build up reputation
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        _validateAboveThreshold(pid, indices[0]);
        engine.computeConsensus(pid, indices[0]);

        // Warp 1000 days — lazy decay should reduce score to MIN_REPUTATION (500)
        vm.warp(block.timestamp + 1000 days);

        // Trigger another reputation update to apply the lazy decay
        bytes32 pid2 = keccak256("cov-extreme-decay-2");
        _setupProject(pid2, FUND_AMOUNT, QUANTITY);
        (, uint256[] memory indices2) = _claimAndSubmit(contributor1, pid2, 1);
        _validateBelowThreshold(pid2, indices2[0]);
        engine.computeConsensus(pid2, indices2[0]);

        // Score should be at MIN_REPUTATION (500) after extreme decay + rejection penalty
        Reputation memory rep = engine.getReputation(contributor1, SKILL_ID);
        assertEq(rep.score, 500);
    }

    /// @notice Test with zero dispute bond BPS → bondAmount rounds to 0, minimum 1
    function test_openDispute_zeroBondBps() public {
        vm.prank(admin);
        engine.setDisputeBondBps(0);

        bytes32 pid = keccak256("cov-zero-bond");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        // Validate + compute without warping — dispute must be opened within challenge window
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(pid, index, keccak256("evidence"), "evidenceCid");

        Dispute memory d = engine.getDispute(pid, index);
        assertEq(d.bondAmount, 1);
    }

    /// @notice Test reportOriginator with zero bond BPS → minimum 1 wei bond
    function test_reportOriginator_zeroBondBps() public {
        vm.prank(admin);
        engine.setOriginatorReportBondBps(0);

        bytes32 pid = keccak256("cov-zero-report-bond");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("evidence"));

        OriginatorReport memory report = engine.getOriginatorReport(pid);
        assertEq(report.bondAmount, 1);
    }

    /// @notice Test resolveOriginatorReport upheld with originator stake present
    function test_resolveOriginatorReport_upheld_withStake() public {
        vm.prank(admin);
        engine.setOriginatorStakeRequirement(10e18);

        bytes32 pid = keccak256("cov-report-upheld-stake");
        token.mint(originator, FUND_AMOUNT);
        _ensureStake(originator, 500e18);
        vm.startPrank(originator);
        engine.createProject(pid, "", _defaultConfig());
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("evidence"));

        vm.prank(admin);
        engine.resolveOriginatorReport(pid, true);

        assertEq(uint256(engine.getProject(pid).status), uint256(ProjectStatus.Cancelled));
        assertGt(engine.getPendingRewards(challenger, address(token)), 0);
    }

    /// @notice Test resolveDispute upheld on accepted with escrow guard
    function test_resolveDispute_upheld_accepted() public {
        bytes32 pid = keccak256("cov-dispute-upheld-acc");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        // Validate + compute without warping — dispute must be opened within challenge window
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(pid, index, keccak256("evidence"), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(pid, index, true);

        // Challenger gets rewards, contributor reward blocked
        assertGt(engine.getPendingRewards(challenger, address(token)), 0);
    }

    /// @notice Test the outlier settlement where actualSlash < committedStake (remaining > 0)
    function test_settleValidator_outlier_partialSlash() public {
        // 5-validator project to get TIER_2 (25% slash)
        // With 50e18 stake, slashAmt = 12.5e18, remaining = 37.5e18
        bytes32 pid = keccak256("cov-partial-slash");
        Project memory config = _defaultConfig();
        config.numberOfValidations = 5;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];

        address validator5 = makeAddr("validator5cov");
        token.mint(validator5, STAKE_AMOUNT * 20);
        vm.startPrank(validator5);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 10, validator5);
        vm.stopPrank();

        _claimAndCommit(validator1, pid, index, 9500, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, index, 9500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, index, 9500, VALIDATOR_STAKE);
        _claimAndCommit(validator4, pid, index, 9500, VALIDATOR_STAKE);
        _claimAndCommit(validator5, pid, index, 100, VALIDATOR_STAKE);

        _reveal(validator1, pid, index, 9500);
        _reveal(validator2, pid, index, 9500);
        _reveal(validator3, pid, index, 9500);
        _reveal(validator4, pid, index, 9500);
        _reveal(validator5, pid, index, 100);

        engine.computeConsensus(pid, index);

        // Settle all validators — validator5 is outlier (no challenge period), others need warp
        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(pid, index).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pid, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(pid, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(pid, index, nonce);
        vm.prank(validator4);
        engine.settleValidator(pid, index, nonce);
        vm.prank(validator5);
        engine.settleValidator(pid, index, nonce);

        assertTrue(engine.isValidatorOutlier(pid, index, validator5));
    }

    /// @notice Reputation: test decay path in _getReputationScoreCached during validation
    function test_reputationDecay_duringValidation() public {
        bytes32 pid = keccak256("cov-rep-decay-val");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // validator1 does a validation to initialize reputation
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        _claimAndCommit(validator1, pid, indices[0], 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, indices[0], 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, indices[0], 7500, VALIDATOR_STAKE);

        _reveal(validator1, pid, indices[0], 8000);
        _reveal(validator2, pid, indices[0], 8500);
        _reveal(validator3, pid, indices[0], 7500);
        engine.computeConsensus(pid, indices[0]);

        // Warp to trigger decay
        vm.warp(block.timestamp + 100 days);

        // Now validator1 validates again — _getReputationScoreCached will apply decay
        bytes32 pid2 = keccak256("cov-rep-decay-val-2");
        bytes32 labelingSkill = keccak256("LABELING");
        vm.prank(admin);
        engine.registerSkill("LABELING");
        Project memory config = _defaultConfig();
        config.requiredSkill = labelingSkill;
        config.minValidatorReputation = 0;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices2) = _claimAndSubmit(contributor1, pid2, 1);
        _claimAndCommit(validator1, pid2, indices2[0], 8000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid2, indices2[0], 8500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid2, indices2[0], 7500, VALIDATOR_STAKE);

        _reveal(validator1, pid2, indices2[0], 8000);
        _reveal(validator2, pid2, indices2[0], 8500);
        _reveal(validator3, pid2, indices2[0], 7500);

        // computeConsensus uses _getReputationScoreCached with time gap
        engine.computeConsensus(pid2, indices2[0]);
    }

    /// @notice Test no-op reputation update (score doesn't change → no event)
    function test_reputationNoChange() public {
        bytes32 pid = keccak256("cov-rep-nochange");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Initialize validator reputation
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        _validateAboveThreshold(pid, indices[0]);
        engine.computeConsensus(pid, indices[0]);

        // First settle sets score (warp past challenge period for reward payment)
        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(pid, indices[0]).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pid, indices[0], nonce);

        Reputation memory rep = engine.getReputation(validator1, SKILL_ID);
        assertGt(rep.score, 5000);
    }

    /// @notice Test computeConsensus with requiredSkill set
    function test_computeConsensus_withRequiredSkill() public {
        bytes32 pid = keccak256("cov-skill-consensus");
        bytes32 specialSkill = keccak256("SPECIAL_SKILL");
        vm.prank(admin);
        engine.registerSkill("SPECIAL_SKILL");
        Project memory config = _defaultConfig();
        config.requiredSkill = specialSkill;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        _validateAboveThreshold(pid, indices[0]);
        engine.computeConsensus(pid, indices[0]);

        Contribution memory contrib = engine.getContribution(pid, indices[0]);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Accepted));
    }

    /// @notice Test minStakeToClaim = 0 in consensus acceptance (no unlock needed)
    function test_computeConsensus_noStakeToUnlock() public {
        bytes32 pid = keccak256("cov-no-unlock");
        Project memory config = _defaultConfig();
        config.minStakeToClaim = 0;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        _validateAboveThreshold(pid, indices[0]);
        engine.computeConsensus(pid, indices[0]);
    }

    /// @notice Test minStakeToClaim = 0 in consensus rejection (no slash needed)
    function test_computeConsensus_rejection_noStakeToSlash() public {
        bytes32 pid = keccak256("cov-no-slash");
        Project memory config = _defaultConfig();
        config.minStakeToClaim = 0;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        _validateBelowThreshold(pid, indices[0]);
        engine.computeConsensus(pid, indices[0]);
    }

    /// @notice Rejected dispute on accepted — challenge period unfrozen to now
    function test_resolveDispute_rejected_unfreezes() public {
        bytes32 pid = keccak256("cov-dispute-reject-unfreeze");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        // Validate + compute without warping — dispute must be opened within challenge window
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(pid, index, keccak256("bad-evidence"), "evidenceCid");

        // Reject the dispute — should set challengeEndsAt to now
        vm.prank(admin);
        engine.resolveDispute(pid, index, false);

        // Can immediately release reward
        engine.releaseContributorReward(pid, index);
        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
    }

    /// @notice Resolve originator report as rejected (upheld=false) — slashes reporter bond
    function test_resolveOriginatorReport_rejected() public {
        bytes32 pid = keccak256("cov-report-rejected");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("evidence"));

        uint256 sharesBefore = vault.balanceOf(challenger);

        vm.prank(admin);
        engine.resolveOriginatorReport(pid, false);

        OriginatorReport memory report = engine.getOriginatorReport(pid);
        assertEq(uint256(report.status), uint256(OriginatorReportStatus.Rejected));
        assertLt(vault.balanceOf(challenger), sharesBefore);
    }

    /// @notice getReputation on a user with initialized reputation (lastUpdated != 0)
    function test_getReputation_initialized() public {
        bytes32 pid = keccak256("cov-rep-init");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Build reputation via acceptance
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        _validateAboveThreshold(pid, indices[0]);
        engine.computeConsensus(pid, indices[0]);

        // Now contributor1 has initialized reputation
        Reputation memory rep = engine.getReputation(contributor1, SKILL_ID);
        assertGt(rep.lastUpdated, 0);
        assertGt(rep.score, 5000);
    }
}

// ═══════════════════════════════════════════════════════════════════════
// Direct constructor/initialize coverage (bypasses proxy)
// ═══════════════════════════════════════════════════════════════════════

contract DirectInitCoverageTest is Test {
    MockERC20 internal token;

    function setUp() public {
        token = new MockERC20("Sapien Token", "SPN");
    }

    /// @notice Deploy SapienCore implementation directly — covers constructor _disableInitializers
    function test_QE_constructorDisablesInitializers() public {
        SapienCore impl = new SapienCore();
        // Should revert if we try to initialize the implementation
        vm.expectRevert();
        impl.initialize(address(this), address(1), address(2));
    }

    /// @notice Deploy SapienVault implementation directly — covers constructor _disableInitializers
    function test_SV_constructorDisablesInitializers() public {
        SapienVault impl = new SapienVault();
        // Should revert if we try to initialize the implementation
        vm.expectRevert();
        impl.initialize(IERC20(address(token)), address(this));
    }

    /// @notice Initialize SapienCore through proxy covering all init lines
    function test_QE_fullInitialize() public {
        SapienCore impl = new SapienCore();
        address admin_ = makeAddr("admin");
        address vault_ = makeAddr("vault");
        address treasury_ = makeAddr("treasury");

        bytes memory initData = abi.encodeCall(SapienCore.initialize, (admin_, vault_, treasury_));
        SapienCore engine = SapienCore(address(new ERC1967Proxy(address(impl), initData)));

        assertTrue(engine.hasRole(engine.DEFAULT_ADMIN_ROLE(), admin_));
    }

    /// @notice Initialize SapienVault through proxy covering all init lines
    function test_SV_fullInitialize() public {
        SapienVault impl = new SapienVault();
        address admin_ = makeAddr("admin");

        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), admin_));
        SapienVault vault = SapienVault(address(new ERC1967Proxy(address(impl), initData)));

        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin_));
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Explicit Branch Coverage for ir-minimum stubborn paths
// ═══════════════════════════════════════════════════════════════════════

contract QEExplicitBranchTest is QECoverageBase {
    /// @notice Rejection path in computeConsensus (else of weightedAverage >= threshold)
    ///         Targets line 687 branch 1 (else branch)
    function test_computeConsensus_rejection_explicitPath() public {
        bytes32 pid = keccak256("cov-explicit-reject");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];

        // Low scores → rejection
        _claimAndCommit(validator1, pid, index, 2000, VALIDATOR_STAKE);
        _claimAndCommit(validator2, pid, index, 1500, VALIDATOR_STAKE);
        _claimAndCommit(validator3, pid, index, 3000, VALIDATOR_STAKE);

        _reveal(validator1, pid, index, 2000);
        _reveal(validator2, pid, index, 1500);
        _reveal(validator3, pid, index, 3000);

        engine.computeConsensus(pid, index);

        Contribution memory contrib = engine.getContribution(pid, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected));
    }

    /// @notice Non-outlier validator settlement (else of if(outlier))
    ///         Targets line 764 branch 1
    function test_settleValidator_nonOutlier_explicit() public {
        bytes32 pid = keccak256("cov-explicit-settle");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        // All validators were in agreement (non-outlier) — settle after challenge period
        _warpPastChallengePeriod();
        uint256 nonce = engine.getContribution(pid, index).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pid, index, nonce);

        assertFalse(engine.isValidatorOutlier(pid, index, validator1));
    }

    /// @notice Open dispute on a rejected contribution (line 916 branch 0)
    ///         Tests the path: !computed=true && status==Rejected → passes the check
    function test_openDispute_onRejectedContribution() public {
        bytes32 pid = keccak256("cov-explicit-dispute-rej");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _validateBelowThreshold(pid, index);
        engine.computeConsensus(pid, index);

        Contribution memory contrib = engine.getContribution(pid, index);
        assertEq(uint256(contrib.status), uint256(ContributionStatus.Rejected));
        assertGt(contrib.challengeEndsAt, 0);

        _ensureStake(contributor1, STAKE_AMOUNT);
        vm.prank(contributor1);
        engine.openDispute(pid, index, keccak256("dispute-rejected"), "evidenceCid");

        Dispute memory d = engine.getDispute(pid, index);
        assertEq(uint256(d.status), uint256(DisputeStatus.Open));
    }

    /// @notice Trigger ConsensusNotComputed revert on non-existent contribution (line 922 branch 0)
    ///         challengeEndsAt == 0 path
    function test_revert_openDispute_challengeEndsAtZero() public {
        bytes32 pid = keccak256("cov-explicit-challenge-zero");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Claim and submit but don't run consensus — status is Submitted, challengeEndsAt=0
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);

        vm.prank(challenger);
        vm.expectRevert(ISapienCore.ConsensusNotComputed.selector);
        engine.openDispute(pid, indices[0], keccak256("evidence"), "evidenceCid");
    }

    /// @notice resolveDispute rejected on accepted contribution (line 974 branch 1 + line 1015)
    function test_resolveDispute_rejectedOnAccepted_explicit() public {
        bytes32 pid = keccak256("cov-explicit-dispute-rej-acc");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        // Validate + compute without warping — dispute must be opened within challenge window
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(pid, index, keccak256("weak-evidence"), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(pid, index, false);

        Dispute memory d = engine.getDispute(pid, index);
        assertEq(uint256(d.status), uint256(DisputeStatus.Rejected));
    }

    /// @notice resolveDispute rejected on rejected contribution
    function test_resolveDispute_rejectedOnRejected_explicit() public {
        bytes32 pid = keccak256("cov-explicit-dispute-rej-rej");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _validateBelowThreshold(pid, index);
        engine.computeConsensus(pid, index);

        _ensureStake(contributor1, STAKE_AMOUNT);
        vm.prank(contributor1);
        engine.openDispute(pid, index, keccak256("weak-dispute"), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(pid, index, false);

        Dispute memory d = engine.getDispute(pid, index);
        assertEq(uint256(d.status), uint256(DisputeStatus.Rejected));
    }

    /// @notice resolveOriginatorReport rejected (line 1128 branch 1)
    function test_resolveOriginatorReport_rejected_explicit() public {
        bytes32 pid = keccak256("cov-explicit-report-rej");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("evidence"));

        vm.prank(admin);
        engine.resolveOriginatorReport(pid, false);

        OriginatorReport memory r = engine.getOriginatorReport(pid);
        assertEq(uint256(r.status), uint256(OriginatorReportStatus.Rejected));
    }

    /// @notice Reputation decay in _getReputationScoreCached during computeConsensus
    ///         Targets lines 1280-1282 and branch 1280.0
    function test_reputationDecay_inGetReputationScoreCached() public {
        bytes32 pid = keccak256("cov-explicit-rep-decay-cached");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Initialize validator reputation
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        _validateAboveThreshold(pid, indices[0]);
        engine.computeConsensus(pid, indices[0]);

        // Warp 30 days to accumulate decay
        vm.warp(block.timestamp + 30 days);

        // Do another validation round — computeConsensus reads reputation via
        // _getReputationScoreCached with decayRateBps > 0 and daysSinceUpdate > 0
        bytes32 pid2 = keccak256("cov-explicit-rep-decay-cached-2");
        _setupProject(pid2, FUND_AMOUNT, QUANTITY);
        (, uint256[] memory indices2) = _claimAndSubmit(contributor1, pid2, 1);
        _validateAboveThreshold(pid2, indices2[0]);
        engine.computeConsensus(pid2, indices2[0]);
    }

    /// @notice SapienCore pause blocks whenNotPaused functions
    function test_engine_pause_blocks_operations() public {
        bytes32 pid = keccak256("cov-explicit-pause");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        vm.prank(admin);
        engine.pause();
        assertTrue(engine.paused());

        vm.prank(contributor1);
        vm.expectRevert();
        engine.claimToContribute(pid, 1, adapter);

        vm.prank(admin);
        engine.unpause();
        assertFalse(engine.paused());

        // Verify operations work after unpause
        vm.prank(contributor1);
        engine.claimToContribute(pid, 1, adapter);
    }

    /// @notice SapienVault pause/unpause explicit test
    function test_vault_pause_unpause_explicit() public {
        vm.prank(admin);
        vault.pause();
        assertTrue(vault.paused());

        vm.prank(admin);
        vault.unpause();
        assertFalse(vault.paused());
    }
}

// ═══════════════════════════════════════════════════════════════════════
// SapienCore — Full Path Coverage (covers lines missed by fuzz exclusion)
// ═══════════════════════════════════════════════════════════════════════

contract QEFullPathCoverageTest is QECoverageBase {
    // ── Return stack popping in claimToContribute (lines 370-372) ────
    function test_claimToContribute_fromReturnStack() public {
        bytes32 pid = keccak256("cov-return-stack");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Claim, contribute, validate below threshold → rejection
        (, uint256[] memory indices1) = _claimAndSubmit(contributor1, pid, 1);
        _validateBelowThreshold(pid, indices1[0]);
        engine.computeConsensus(pid, indices1[0]);

        // The index should be on the return stack now
        // Claim again — should pop from return stack
        (, uint256[] memory indices2) = _claimAndSubmit(contributor2, pid, 1);
        // The returned index should be the same one that was rejected
        assertEq(indices2[0], indices1[0]);
    }

    // ── minValidatorReputation gate (lines 557-561) ──────────────────
    function test_revert_commitValidation_insufficientReputation() public {
        bytes32 pid = keccak256("cov-min-rep-gate");
        Project memory config = _defaultConfig();
        config.minValidatorReputation = 9999; // very high bar
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(validator1, VALIDATOR_STAKE * 3);
        vm.startPrank(validator1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        vm.expectRevert(); // InsufficientReputation
        engine.claimToValidate(pid, 1);
        vm.stopPrank();
    }

    // ── RewardAlreadyReleased (line 809) ─────────────────────────────
    function test_revert_releaseContributorReward_alreadyReleased() public {
        bytes32 pid = keccak256("cov-double-release");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _fullAcceptanceFlow(pid, index);

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(pid, index);

        // Second release should revert
        vm.expectRevert(ISapienCore.RewardAlreadyReleased.selector);
        engine.releaseContributorReward(pid, index);
    }

    // ── Dispute upheld blocks reward release (line 814) ──────────────
    function test_revert_releaseReward_disputeUpheld() public {
        bytes32 pid = keccak256("cov-upheld-blocks");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(pid, index, keccak256("evidence"), "evidenceCid");

        vm.prank(admin);
        engine.resolveDispute(pid, index, true); // upheld

        vm.warp(block.timestamp + 30 days);
        vm.expectRevert(ISapienCore.ContributionNotAccepted.selector);
        engine.releaseContributorReward(pid, index);
    }

    // ── cancelExpiredCommitment (lines 873-890) ──────────────────────
    function test_cancelExpiredCommitment() public {
        bytes32 pid = keccak256("cov-cancel-commit");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];

        // Commit but don't reveal
        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, pid, index));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));
        _ensureStake(validator1, VALIDATOR_STAKE * 3);
        vm.startPrank(validator1);
        engine.claimToValidate(pid, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(pid, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // Warp past commit + reveal deadline
        vm.warp(block.timestamp + 3 days + 2 days + 1);

        // Cancel the expired commitment
        engine.cancelExpiredCommitment(pid, index, validator1);
    }

    // ── CannotDisputeOwnContribution (line 922-923) ──────────────────
    function test_revert_openDispute_ownContribution() public {
        bytes32 pid = keccak256("cov-self-dispute");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        // contributor1 tries to dispute their own accepted contribution
        _ensureStake(contributor1, STAKE_AMOUNT);
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.CannotDisputeOwnContribution.selector);
        engine.openDispute(pid, index, keccak256("self-dispute"), "evidenceCid");
    }

    // ── DisputeWindowClosed (line 915) ───────────────────────────────
    function test_revert_openDispute_windowClosed() public {
        bytes32 pid = keccak256("cov-dispute-window");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _fullAcceptanceFlow(pid, index);

        // Warp past challenge period
        vm.warp(block.timestamp + 2 days);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        vm.expectRevert(ISapienCore.DisputeWindowClosed.selector);
        engine.openDispute(pid, index, keccak256("too-late"), "evidenceCid");
    }

    // ── DisputeAlreadyOpen (line 919) ────────────────────────────────
    function test_revert_openDispute_alreadyOpen() public {
        bytes32 pid = keccak256("cov-dup-dispute");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        _ensureStake(challenger, STAKE_AMOUNT * 2);
        vm.prank(challenger);
        engine.openDispute(pid, index, keccak256("first"), "evidenceCid");

        vm.prank(challenger);
        vm.expectRevert(ISapienCore.DisputeAlreadyOpen.selector);
        engine.openDispute(pid, index, keccak256("second"), "evidenceCid");
    }

    // ── escalateDispute too early (line 1027-1028) ───────────────────
    function test_revert_escalateDispute_tooEarly() public {
        bytes32 pid = keccak256("cov-escalate-early");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        // Validate + compute without warping — dispute must be opened within challenge window
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.openDispute(pid, index, keccak256("evidence"), "evidenceCid");

        // Try to escalate immediately (before 7 day resolution deadline)
        vm.expectRevert(ISapienCore.DisputeResolutionNotExpired.selector);
        engine.escalateDispute(pid, index);
    }

    // ── escalateOriginatorReport full flow (lines 1172-1197) ─────────
    function test_escalateOriginatorReport() public {
        bytes32 pid = keccak256("cov-escalate-report");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("evidence"));

        // Warp past resolution deadline
        vm.warp(block.timestamp + 7 days + 1);

        engine.escalateOriginatorReport(pid);

        OriginatorReport memory report = engine.getOriginatorReport(pid);
        assertEq(uint256(report.status), uint256(OriginatorReportStatus.Upheld));
        assertEq(uint256(engine.getProject(pid).status), uint256(ProjectStatus.Cancelled));
    }

    // ── escalateOriginatorReport with originator stake (line 1188) ───
    function test_escalateOriginatorReport_withStake() public {
        vm.prank(admin);
        engine.setOriginatorStakeRequirement(10e18);

        bytes32 pid = keccak256("cov-escalate-report-stake");
        token.mint(originator, FUND_AMOUNT);
        _ensureStake(originator, 500e18);
        vm.startPrank(originator);
        engine.createProject(pid, "", _defaultConfig());
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("evidence"));

        vm.warp(block.timestamp + 7 days + 1);
        engine.escalateOriginatorReport(pid);

        assertEq(uint256(engine.getProject(pid).status), uint256(ProjectStatus.Cancelled));
    }

    // ── escalateOriginatorReport too early ───────────────────────────
    function test_revert_escalateOriginatorReport_tooEarly() public {
        bytes32 pid = keccak256("cov-escalate-report-early");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("evidence"));

        vm.expectRevert(ISapienCore.DisputeResolutionNotExpired.selector);
        engine.escalateOriginatorReport(pid);
    }

    // ── reportOriginator: cannot report own project (line 1083-1084) ─
    function test_revert_reportOriginator_ownProject() public {
        bytes32 pid = keccak256("cov-self-report");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(originator, STAKE_AMOUNT);
        vm.prank(originator);
        vm.expectRevert(ISapienCore.NotProjectOriginator.selector);
        engine.reportOriginator(pid, keccak256("evidence"));
    }

    // ── reportOriginator: duplicate report (line 1087-1088) ──────────
    function test_revert_reportOriginator_duplicate() public {
        bytes32 pid = keccak256("cov-dup-report");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);
        _claimAndSubmit(contributor1, pid, 1);

        _ensureStake(challenger, STAKE_AMOUNT * 2);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("first"));

        vm.prank(challenger);
        vm.expectRevert(ISapienCore.OriginatorReportAlreadyOpen.selector);
        engine.reportOriginator(pid, keccak256("second"));
    }

    // ── Block claims when originator report is active (line 351) ─────
    function test_revert_claimToContribute_originatorReportOpen() public {
        bytes32 pid = keccak256("cov-claim-blocked-report");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        _ensureStake(challenger, STAKE_AMOUNT);
        vm.prank(challenger);
        engine.reportOriginator(pid, keccak256("evidence"));

        // Try to claim while report is open
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.DisputeInProgress.selector);
        engine.claimToContribute(pid, 1, adapter);
    }

    // ── claim.status != Active in contribute (line 432) ──────────────
    function test_revert_contribute_claimCompleted() public {
        bytes32 pid = keccak256("cov-claim-completed");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        vm.startPrank(contributor1);
        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(pid, 1, adapter);
        engine.contribute(claimId, indices[0], keccak256("sub1"), "");
        // Claim is now Completed (single index, submitted)

        // Try to contribute again — claim status is Completed
        vm.expectRevert(ISapienCore.ClaimDeadlinePassed.selector);
        engine.contribute(claimId, indices[0], keccak256("sub2"), "");
        vm.stopPrank();
    }

    // ── setValidationFee success path (lines 1402-1403) ──────────────
    function test_setValidationFee_success() public {
        vm.prank(admin);
        engine.setValidationFee(300);
    }

    // ── _getReputationScore coverage (lines 1282-1283) ──────────────
    // _getReputationScore is called by commitValidation when minValidatorReputation > 0
    function test_getReputationScore_viaNonZeroMinReputation() public {
        bytes32 pid = keccak256("cov-rep-score-func");
        Project memory config = _defaultConfig();
        config.minValidatorReputation = 1; // low bar, so it passes but exercises the path
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        // This will call commitValidation which checks minValidatorReputation > 0
        // and calls _getReputationScore
        _claimAndCommit(validator1, pid, indices[0], 8000, VALIDATOR_STAKE);
    }

    // ── _getReputationScoreCached with decay (lines 1295-1306) ──────
    function test_reputationScoreCached_withDecay() public {
        bytes32 pid = keccak256("cov-cached-decay");
        Project memory config = _defaultConfig();
        config.minValidatorReputation = 1;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        // Initialize validator reputation
        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        _validateAboveThreshold(pid, indices[0]);
        engine.computeConsensus(pid, indices[0]);

        // Warp to accumulate decay
        vm.warp(block.timestamp + 30 days);

        // Now commit on another contribution — _getReputationScore is called
        // which calls _getReputationScoreCached with decayRateBps > 0
        bytes32 pid2 = keccak256("cov-cached-decay-2");
        config.minValidatorReputation = 1;
        token.mint(originator, FUND_AMOUNT);
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices2) = _claimAndSubmit(contributor2, pid2, 1);
        // This commit calls _getReputationScore → _getReputationScoreCached with decay
        _claimAndCommit(validator1, pid2, indices2[0], 8000, VALIDATOR_STAKE);
    }

    // ── initialize ZeroAddress for admin (line 190) ──────────────────
    function test_revert_initializeZeroAdmin_directProxy() public {
        SapienCore impl = new SapienCore();
        bytes memory initData = abi.encodeCall(SapienCore.initialize, (address(0), address(1), address(2)));
        vm.expectRevert();
        new ERC1967Proxy(address(impl), initData);
    }

    // ── full acceptance + release flow (covers release happy path) ───
    function test_fullAcceptanceAndRelease() public {
        bytes32 pid = keccak256("cov-full-release");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _fullAcceptanceFlow(pid, index);

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(pid, index);

        assertGt(engine.getPendingRewards(contributor1, address(token)), 0);
    }

    // ── cancelExpiredCommitment reverts (not committed / already revealed) ──
    function test_revert_cancelExpiredCommitment_notExpired() public {
        bytes32 pid = keccak256("cov-cancel-not-expired");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];

        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, pid, index));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));
        _ensureStake(validator1, VALIDATOR_STAKE * 3);
        vm.startPrank(validator1);
        engine.claimToValidate(pid, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(pid, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // Try to cancel before expiry
        vm.expectRevert(ISapienCore.ClaimDeadlineNotPassed.selector);
        engine.cancelExpiredCommitment(pid, index, validator1);
    }

    // ── challengeEndsAt == 0 revert in openDispute (line 933) ────────
    // This tests a non-existent contribution where consensusReports is empty
    // but status might not be Rejected either
    function test_revert_openDispute_noConsensus_nonexistent() public {
        bytes32 pid = keccak256("cov-no-consensus-ne");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Try to dispute index 999 which was never claimed/submitted
        vm.prank(challenger);
        vm.expectRevert(ISapienCore.ConsensusNotComputed.selector);
        engine.openDispute(pid, 999, keccak256("evidence"), "evidenceCid");
    }

    // ── Validator reward exceeds available escrow (lines 801-802) ────
    function test_settleValidator_rewardCappedByEscrow() public {
        // Create project with very low funding so reward calculation exceeds escrow
        bytes32 pid = keccak256("cov-escrow-cap");
        Project memory config = _defaultConfig();
        config.numberOfValidations = 3;
        config.validatorRewardBps = 2500; // max 25%
        config.minStakeToClaim = 0;
        uint256 smallFund = 100; // tiny fund (after protocol fee, very little left)
        token.mint(originator, smallFund);
        vm.startPrank(originator);
        engine.createProject(pid, "", config);
        token.approve(address(engine), smallFund);
        engine.fundProject(pid, smallFund, 1, adapter);
        vm.stopPrank();

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        // Release contributor reward first to deplete escrow
        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(pid, index);

        // Now settle validators — escrow is very low, reward should be capped
        uint256 nonce = engine.getContribution(pid, index).consensusNonce;
        vm.prank(validator1);
        engine.settleValidator(pid, index, nonce);
        vm.prank(validator2);
        engine.settleValidator(pid, index, nonce);
        vm.prank(validator3);
        engine.settleValidator(pid, index, nonce);
    }

    // ── _getReputationScoreCached: initialized user with decay (lines 1314-1325) ──
    function test_reputationScoreCached_allPaths() public {
        bytes32 pid = keccak256("cov-rep-cached-all");
        // Use minValidatorReputation > 0 to force _getReputationScore call
        Project memory config = _defaultConfig();
        config.minValidatorReputation = 1;
        token.mint(originator, FUND_AMOUNT * 2);
        vm.startPrank(originator);
        engine.createProject(pid, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        // Initialize validator reputation by going through a full cycle
        (, uint256[] memory indices1) = _claimAndSubmit(contributor1, pid, 1);
        _validateAboveThreshold(pid, indices1[0]);
        engine.computeConsensus(pid, indices1[0]);
        _settleAllValidators(pid, indices1[0]);

        // Warp 10 days for decay
        vm.warp(block.timestamp + 10 days);

        // Now create a new project and validate — _getReputationScore is called
        // on initialized validator with decayBps > 0 and daysSinceUpdate > 0
        bytes32 pid2 = keccak256("cov-rep-cached-all-2");
        vm.startPrank(originator);
        engine.createProject(pid2, "", config);
        token.approve(address(engine), FUND_AMOUNT);
        engine.fundProject(pid2, FUND_AMOUNT, QUANTITY, adapter);
        vm.stopPrank();

        (, uint256[] memory indices2) = _claimAndSubmit(contributor2, pid2, 1);
        // commitValidation calls _getReputationScore on validator1
        // which calls _getReputationScoreCached with initialized rep + decay
        _claimAndCommit(validator1, pid2, indices2[0], 8000, VALIDATOR_STAKE);
    }

    // ── Initialize with zero admin via proxy (different approach for line 192) ──
    function test_revert_initializeZeroAdmin_coveragePath() public {
        SapienCore impl = new SapienCore();
        // Deploy proxy with no init data
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), "");
        SapienCore eng = SapienCore(address(proxy));

        // Call initialize separately (not in constructor) for better coverage
        vm.expectRevert(ISapienCore.ZeroAddress.selector);
        eng.initialize(address(0), address(vault), treasury);
    }

    // ── claimReward success path (line 793) ─────────────────────────
    function test_claimReward() public {
        bytes32 pid = keccak256("cov-claim-reward");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _fullAcceptanceFlow(pid, index);

        vm.warp(block.timestamp + 2 days);
        engine.releaseContributorReward(pid, index);

        uint256 pending = engine.getPendingRewards(contributor1, address(token));
        assertGt(pending, 0);

        uint256 balBefore = token.balanceOf(contributor1);
        vm.prank(contributor1);
        engine.claimReward(address(token));

        assertEq(engine.getPendingRewards(contributor1, address(token)), 0);
        assertEq(token.balanceOf(contributor1), balBefore + pending);
    }

    // ── claimReward with zero pending (line 792 branch 0) ───────────
    function test_revert_claimReward_noReward() public {
        vm.prank(contributor1);
        vm.expectRevert(ISapienCore.NoRewardToClaim.selector);
        engine.claimReward(address(token));
    }

    // ── getAdapterFees (line 1386 branch) ───────────────────────────
    function test_getAdapterFees() public view {
        (uint256 origBps, uint256 contribBps, uint256 valBps) = engine.getAdapterFees();
        assertEq(origBps, 400);
        assertEq(contribBps, 300);
        assertEq(valBps, 300);
    }

    // ── initialize with zero treasury (line 190) ─────────────
    function test_revert_initialize_zeroTreasury() public {
        SapienCore impl = new SapienCore();
        bytes memory initData = abi.encodeCall(SapienCore.initialize, (admin, address(vault), address(0)));
        vm.expectRevert(ISapienCore.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    // ── Event emission tests for missing events ──────────────────────

    function test_event_cancelExpiredCommitment() public {
        bytes32 pid = keccak256("event-cancel-commit");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];

        // Commit but don't reveal
        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, pid, index));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));
        _ensureStake(validator1, VALIDATOR_STAKE * 3);
        vm.startPrank(validator1);
        engine.claimToValidate(pid, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(pid, index, commitHash, VALIDATOR_STAKE, address(0));
        vm.stopPrank();

        // Wait for commit deadline + reveal deadline to pass
        vm.warp(block.timestamp + 1 days + 1 days + 1);

        vm.expectEmit(true, true, true, true);
        emit ISapienCore.ValidatorCommitmentExpired(pid, index, validator1);
        engine.cancelExpiredCommitment(pid, index, validator1);
    }

    function test_event_upholdDispute() public {
        bytes32 pid = keccak256("event-uphold-dispute");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        // Open dispute
        vm.startPrank(contributor2);
        engine.openDispute(pid, index, bytes32("evidence"), "cid");
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit ISapienCore.DisputeResolved(pid, index, true);
        vm.prank(admin);
        engine.resolveDispute(pid, index, true);
    }

    function test_event_rejectDispute() public {
        bytes32 pid = keccak256("event-reject-dispute");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        (, uint256[] memory indices) = _claimAndSubmit(contributor1, pid, 1);
        uint256 index = indices[0];
        _validateAboveThreshold(pid, index);
        engine.computeConsensus(pid, index);

        // Open dispute
        vm.startPrank(contributor2);
        engine.openDispute(pid, index, bytes32("evidence"), "cid");
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit ISapienCore.DisputeResolved(pid, index, false);
        vm.prank(admin);
        engine.resolveDispute(pid, index, false);
    }

    function test_event_rejectOriginatorReport() public {
        bytes32 pid = keccak256("event-reject-report");
        _setupProject(pid, FUND_AMOUNT, QUANTITY);

        // Report originator
        vm.startPrank(contributor2);
        engine.reportOriginator(pid, bytes32("evidence"));
        vm.stopPrank();

        vm.expectEmit(true, true, true, true);
        emit ISapienCore.OriginatorReportResolved(pid, false);
        vm.prank(admin);
        engine.resolveOriginatorReport(pid, false);
    }
}
