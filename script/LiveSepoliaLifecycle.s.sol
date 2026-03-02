// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {Project, ProjectStatus, Contribution, ContributionStatus, ConsensusReport, StakeAccount} from "src/Types.sol";

/// @title LiveSepoliaLifecycle
/// @notice Runs a complete PoQ lifecycle against deployed Base Sepolia contracts.
///         Split into phases because settlement requires the challenge period to elapse.
///         Assumes DATA_ANNOTATION skill is already registered via the Safe admin.
///
///     Phase 1 - fund accounts, create project, contribute, validate, consensus:
///       forge script script/LiveSepoliaLifecycle.s.sol --sig "phase1()" \
///         --rpc-url $BASE_SEPOLIA_RPC_URL --account deployer --broadcast
///
///     Phase 2 - settle validators, release rewards, claim, cleanup (run after challenge period):
///       forge script script/LiveSepoliaLifecycle.s.sol --sig "phase2()" \
///         --rpc-url $BASE_SEPOLIA_RPC_URL --account deployer --broadcast
///
///     Override the project seed for repeated runs:
///       PROJECT_SEED=v2 forge script ... --sig "phase1()" ...
contract LiveSepoliaLifecycle is Script {
    uint256 constant BASE_SEPOLIA_CHAIN_ID = 84532;

    // ── Deployed addresses (deployments/base-sepolia.json) ───────────────
    address constant SAPIEN_CORE = 0xDFFEc0D8F9DF05bf3DecbdFefD650779D6481077;
    address constant SAPIEN_VAULT = 0xf0E3C676b277Ce31C2E72Cd473684FA4C8866029;
    address constant SAPIEN_TOKEN = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6;
    address constant DEPLOYER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;

    SapienCore engine = SapienCore(SAPIEN_CORE);
    SapienVault vault = SapienVault(SAPIEN_VAULT);
    IERC20 token = IERC20(SAPIEN_TOKEN);

    // ── Test account private keys (deterministic, testnet ONLY) ──────────
    uint256 constant CONTRIBUTOR_PK = uint256(keccak256("sapien-live-test-contributor-v1"));
    uint256 constant VALIDATOR1_PK = uint256(keccak256("sapien-live-test-validator1-v1"));
    uint256 constant VALIDATOR2_PK = uint256(keccak256("sapien-live-test-validator2-v1"));
    uint256 constant VALIDATOR3_PK = uint256(keccak256("sapien-live-test-validator3-v1"));

    // ── Derived addresses ────────────────────────────────────────────────
    address immutable contributorAddr = vm.addr(CONTRIBUTOR_PK);
    address immutable validator1Addr = vm.addr(VALIDATOR1_PK);
    address immutable validator2Addr = vm.addr(VALIDATOR2_PK);
    address immutable validator3Addr = vm.addr(VALIDATOR3_PK);

    // ── Constants ────────────────────────────────────────────────────────
    bytes32 constant SKILL_ID = keccak256("DATA_ANNOTATION");
    uint256 constant FUND_AMOUNT = 10_000e18;
    uint256 constant QUANTITY = 5;
    uint256 constant STAKE_AMOUNT = 100e18;
    uint256 constant VALIDATOR_STAKE = 50e18;
    uint256 constant ETH_FOR_GAS = 0.005 ether;

    // Total SAPIEN the deployer needs to distribute
    // Project funding + contributor stake + 3 validator stakes
    uint256 constant CONTRIBUTOR_TOKENS = STAKE_AMOUNT * 5;
    uint256 constant VALIDATOR_TOKENS = VALIDATOR_STAKE * 10;
    uint256 constant TOTAL_TOKENS_NEEDED = FUND_AMOUNT + CONTRIBUTOR_TOKENS + (VALIDATOR_TOKENS * 3);

    // ── Project ID (deterministic, overridable via PROJECT_SEED env var) ─
    bytes32 public projectId;

    function setUp() public {
        string memory seed = vm.envOr("PROJECT_SEED", string("sapien-live-v1"));
        projectId = keccak256(abi.encodePacked("live-lifecycle-", seed));
    }

    // ═════════════════════════════════════════════════════════════════════
    // Phase 1 - Everything up through consensus computation
    // ═════════════════════════════════════════════════════════════════════

    function phase1() external {
        require(block.chainid == BASE_SEPOLIA_CHAIN_ID, "Not Base Sepolia");

        console2.log("========================================");
        console2.log("  PHASE 1: Setup & Lifecycle");
        console2.log("========================================");
        console2.log("Project ID :", vm.toString(projectId));
        console2.log("Contributor:", contributorAddr);
        console2.log("Validator1 :", validator1Addr);
        console2.log("Validator2 :", validator2Addr);
        console2.log("Validator3 :", validator3Addr);
        console2.log("");

        uint256 deployerBal = token.balanceOf(DEPLOYER);
        console2.log("Deployer SAPIEN balance:", deployerBal);
        console2.log("Total SAPIEN needed    :", TOTAL_TOKENS_NEEDED);
        require(deployerBal >= TOTAL_TOKENS_NEEDED, "Deployer lacks SAPIEN - need more tokens");

        // ── 1a. Deployer: transfer tokens + send ETH + create & fund project
        vm.startBroadcast(); // uses --account (deployer)

        token.transfer(contributorAddr, CONTRIBUTOR_TOKENS);
        token.transfer(validator1Addr, VALIDATOR_TOKENS);
        token.transfer(validator2Addr, VALIDATOR_TOKENS);
        token.transfer(validator3Addr, VALIDATOR_TOKENS);
        console2.log("[deployer] Transferred SAPIEN to all participants");

        _sendEth(contributorAddr, ETH_FOR_GAS);
        _sendEth(validator1Addr, ETH_FOR_GAS);
        _sendEth(validator2Addr, ETH_FOR_GAS);
        _sendEth(validator3Addr, ETH_FOR_GAS);
        console2.log("[deployer] Sent ETH for gas to all participants");

        token.approve(address(engine), FUND_AMOUNT);

        engine.createProject(projectId, "ipfs://live-lifecycle-test", _projectConfig());
        engine.fundProject(projectId, FUND_AMOUNT, QUANTITY, DEPLOYER);
        console2.log("[deployer] Project created and funded (deployer = adapter)");

        vm.stopBroadcast();

        // ── 1b. Contributor: deposit stake, claim slot, submit work ──────
        vm.startBroadcast(CONTRIBUTOR_PK);

        token.approve(address(vault), type(uint256).max);
        vault.deposit(STAKE_AMOUNT * 3, contributorAddr);

        (uint256 claimId, uint256[] memory indices) = engine.claimToContribute(projectId, 1, address(0));
        uint256 index = indices[0];

        bytes32 submissionHash = keccak256("live-lifecycle-submission-data");
        engine.contribute(claimId, index, submissionHash, "ipfs://live-submission");
        console2.log("[contributor] Claimed and submitted. Index:", index);

        vm.stopBroadcast();

        // ── 1c. Validators: deposit, lock capacity, commit then reveal ──
        _validatorClaimAndCommit(VALIDATOR1_PK, validator1Addr, index, 8000);
        _validatorClaimAndCommit(VALIDATOR2_PK, validator2Addr, index, 8500);
        _validatorClaimAndCommit(VALIDATOR3_PK, validator3Addr, index, 7500);
        console2.log("[validators] All 3 committed");

        _validatorReveal(VALIDATOR1_PK, validator1Addr, index, 8000);
        _validatorReveal(VALIDATOR2_PK, validator2Addr, index, 8500);
        _validatorReveal(VALIDATOR3_PK, validator3Addr, index, 7500);
        console2.log("[validators] All 3 revealed");

        // ── 1d. Compute consensus ────────────────────────────────────────
        vm.startBroadcast(); // deployer
        engine.computeConsensus(projectId, index);
        vm.stopBroadcast();

        Contribution memory contrib = engine.getContribution(projectId, index);
        ConsensusReport memory report = engine.getConsensusReport(projectId, index);

        console2.log("");
        console2.log("========================================");
        console2.log("  PHASE 1 COMPLETE");
        console2.log("========================================");
        console2.log("Contribution status:", uint256(contrib.status));
        console2.log("Weighted average   :", report.weightedAverage);
        console2.log("Challenge ends at  :", contrib.challengeEndsAt);
        console2.log("Current timestamp  :", block.timestamp);
        console2.log("");
        console2.log(">> Wait until block.timestamp >", contrib.challengeEndsAt);
        console2.log(">> Then run phase2()");
    }

    // ═════════════════════════════════════════════════════════════════════
    // Phase 2 - Settle, release rewards, claim, cleanup
    // ═════════════════════════════════════════════════════════════════════

    function phase2() external {
        require(block.chainid == BASE_SEPOLIA_CHAIN_ID, "Not Base Sepolia");

        console2.log("========================================");
        console2.log("  PHASE 2: Settlement & Cleanup");
        console2.log("========================================");

        uint256 index = _findContributionIndex();
        Contribution memory contrib = engine.getContribution(projectId, index);

        require(
            uint256(contrib.status) == uint256(ContributionStatus.Accepted),
            "Contribution not accepted - check phase1 completed correctly"
        );
        require(block.timestamp > contrib.challengeEndsAt, "Challenge period not elapsed - wait longer");

        uint256 nonce = contrib.consensusNonce;
        console2.log("Contribution index:", index);
        console2.log("Consensus nonce   :", nonce);

        // ── 2a. Validators settle ────────────────────────────────────────
        vm.startBroadcast(VALIDATOR1_PK);
        engine.settleValidator(projectId, index, nonce);
        vm.stopBroadcast();

        vm.startBroadcast(VALIDATOR2_PK);
        engine.settleValidator(projectId, index, nonce);
        vm.stopBroadcast();

        vm.startBroadcast(VALIDATOR3_PK);
        engine.settleValidator(projectId, index, nonce);
        vm.stopBroadcast();

        console2.log("[validators] All 3 settled");

        // ── 2b. Release contributor reward ───────────────────────────────
        vm.startBroadcast(); // deployer (permissionless call)
        engine.releaseContributorReward(projectId, index);
        vm.stopBroadcast();

        console2.log("[deployer] Contributor reward released");

        // ── 2c. Claim rewards ────────────────────────────────────────────
        _claimRewardIfPending(CONTRIBUTOR_PK, contributorAddr, "contributor");
        _claimRewardIfPending(VALIDATOR1_PK, validator1Addr, "validator1");
        _claimRewardIfPending(VALIDATOR2_PK, validator2Addr, "validator2");
        _claimRewardIfPending(VALIDATOR3_PK, validator3Addr, "validator3");

        uint256 deployerPending = engine.getPendingRewards(DEPLOYER, SAPIEN_TOKEN);
        if (deployerPending > 0) {
            vm.startBroadcast();
            engine.claimReward(SAPIEN_TOKEN);
            vm.stopBroadcast();
            console2.log("[deployer] Claimed adapter reward:", deployerPending);
        }

        // ── 2d. Cleanup: unlock, withdraw, return tokens ─────────────────
        console2.log("");
        console2.log("--- Cleanup ---");

        _cleanupAccount(VALIDATOR1_PK, validator1Addr, "validator1", true);
        _cleanupAccount(VALIDATOR2_PK, validator2Addr, "validator2", true);
        _cleanupAccount(VALIDATOR3_PK, validator3Addr, "validator3", true);
        _cleanupAccount(CONTRIBUTOR_PK, contributorAddr, "contributor", false);

        console2.log("");
        console2.log("========================================");
        console2.log("  PHASE 2 COMPLETE");
        console2.log("========================================");
        console2.log("SAPIEN recovered to deployer:", token.balanceOf(DEPLOYER));
    }

    // ═════════════════════════════════════════════════════════════════════
    // Internal Helpers
    // ═════════════════════════════════════════════════════════════════════

    function _projectConfig() internal pure returns (Project memory) {
        return Project({
            originator: address(0),
            rewardToken: SAPIEN_TOKEN,
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

    function _sendEth(address to, uint256 amount) internal {
        (bool ok,) = payable(to).call{value: amount}("");
        require(ok, "ETH transfer failed");
    }

    function _validatorClaimAndCommit(uint256 pk, address val, uint256 index, uint256 score) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, index));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.startBroadcast(pk);

        token.approve(address(vault), type(uint256).max);
        vault.deposit(VALIDATOR_STAKE * 5, val);

        engine.claimToValidate(projectId, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(projectId, index, commitHash, VALIDATOR_STAKE, address(0));

        vm.stopBroadcast();
    }

    function _validatorReveal(uint256 pk, address val, uint256 index, uint256 score) internal {
        bytes32 salt = keccak256(abi.encodePacked("salt", val, index));

        vm.startBroadcast(pk);
        engine.revealValidation(projectId, index, score, salt);
        vm.stopBroadcast();
    }

    function _claimRewardIfPending(uint256 pk, address account, string memory label) internal {
        uint256 pending = engine.getPendingRewards(account, SAPIEN_TOKEN);
        if (pending == 0) return;

        vm.startBroadcast(pk);
        engine.claimReward(SAPIEN_TOKEN);
        vm.stopBroadcast();

        console2.log(string.concat("[", label, "] Claimed reward:"), pending);
    }

    /// @dev Scan project contributions to find the one submitted by our contributor.
    function _findContributionIndex() internal view returns (uint256) {
        for (uint256 i = 0; i < QUANTITY; i++) {
            Contribution memory c = engine.getContribution(projectId, i);
            if (c.contributor == contributorAddr) return i;
        }
        revert("No contribution found for contributor - did phase1 run?");
    }

    function _cleanupAccount(uint256 pk, address account, string memory label, bool isValidator) internal {
        vm.startBroadcast(pk);

        if (isValidator) {
            StakeAccount memory acct = vault.getStakeAccount(account);
            if (acct.validatorCapacity > 0) {
                engine.unlockValidatorCapacity(acct.validatorCapacity);
            }
        }

        uint256 redeemable = vault.maxRedeem(account);
        if (redeemable > 0) {
            vault.redeem(redeemable, account, account);
        }

        uint256 tokenBal = token.balanceOf(account);
        if (tokenBal > 0) {
            token.transfer(DEPLOYER, tokenBal);
        }

        vm.stopBroadcast();

        console2.log(string.concat("[", label, "] Cleaned up. Returned SAPIEN:"), tokenBal);
    }
}
