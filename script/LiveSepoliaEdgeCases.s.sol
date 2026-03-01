// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {
    Project,
    ProjectStatus,
    Contribution,
    ContributionStatus,
    ConsensusReport,
    Claim,
    ClaimStatus,
    Dispute,
    DisputeStatus,
    StakeAccount,
    ValidationClaim,
    ValidationClaimStatus,
    Reputation
} from "src/Types.sol";
import {Constants as C} from "src/Constants.sol";

/// @title LiveSepoliaEdgeCases
/// @notice Exercises edge cases and slashing scenarios on deployed Base Sepolia contracts.
///         Covers: contribution rejection, claim expiration, dispute bond locking,
///         and validation claim expiry.
///
///     Phase 1 (immediate actions):
///       forge script script/LiveSepoliaEdgeCases.s.sol --sig "phase1()" \
///         --rpc-url $BASE_SEPOLIA_RPC_URL --account deployer --broadcast
///
///     Phase 2 (after 1+ hour - time-dependent actions + cleanup):
///       forge script script/LiveSepoliaEdgeCases.s.sol --sig "phase2()" \
///         --rpc-url $BASE_SEPOLIA_RPC_URL --account deployer --broadcast
///
///     Override seed for repeated runs:
///       PROJECT_SEED=v2 forge script ...
contract LiveSepoliaEdgeCases is Script {
    uint256 constant BASE_SEPOLIA_CHAIN_ID = 84532;

    // ── Deployed addresses ───────────────────────────────────────────────
    address constant SAPIEN_CORE = 0xDFFEc0D8F9DF05bf3DecbdFefD650779D6481077;
    address constant SAPIEN_VAULT = 0xf0E3C676b277Ce31C2E72Cd473684FA4C8866029;
    address constant SAPIEN_TOKEN = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6;
    address constant DEPLOYER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;

    SapienCore engine = SapienCore(SAPIEN_CORE);
    SapienVault vault = SapienVault(SAPIEN_VAULT);
    IERC20 token = IERC20(SAPIEN_TOKEN);

    // ── Test account private keys (deterministic, testnet ONLY) ──────────
    uint256 constant CONTRIBUTOR_PK = uint256(keccak256("sapien-edge-contributor-v1"));
    uint256 constant CHALLENGER_PK = uint256(keccak256("sapien-edge-challenger-v1"));
    uint256 constant VALIDATOR1_PK = uint256(keccak256("sapien-edge-validator1-v1"));
    uint256 constant VALIDATOR2_PK = uint256(keccak256("sapien-edge-validator2-v1"));
    uint256 constant VALIDATOR3_PK = uint256(keccak256("sapien-edge-validator3-v1"));

    address immutable contributorAddr = vm.addr(CONTRIBUTOR_PK);
    address immutable challengerAddr = vm.addr(CHALLENGER_PK);
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

    // Token distribution amounts
    uint256 constant CONTRIBUTOR_TOKENS = STAKE_AMOUNT * 20;
    uint256 constant CHALLENGER_TOKENS = STAKE_AMOUNT * 5;
    uint256 constant VALIDATOR_TOKENS = VALIDATOR_STAKE * 20;

    // ── Project IDs ──────────────────────────────────────────────────────
    bytes32 public projRejection;
    bytes32 public projDispute;
    bytes32 public projClaimExpiry;
    bytes32 public projValExpiry;

    function setUp() public {
        string memory seed = vm.envOr("PROJECT_SEED", string("sapien-edge-v1"));
        projRejection = keccak256(abi.encodePacked("edge-rejection-", seed));
        projDispute = keccak256(abi.encodePacked("edge-dispute-", seed));
        projClaimExpiry = keccak256(abi.encodePacked("edge-claim-expiry-", seed));
        projValExpiry = keccak256(abi.encodePacked("edge-val-expiry-", seed));
    }

    // ═════════════════════════════════════════════════════════════════════
    // Phase 1 - Immediate actions
    // ═════════════════════════════════════════════════════════════════════

    function phase1() external {
        require(block.chainid == BASE_SEPOLIA_CHAIN_ID, "Not Base Sepolia");

        _logHeader("PHASE 1: Edge Cases Setup");
        console2.log("Contributor:", contributorAddr);
        console2.log("Challenger :", challengerAddr);
        console2.log("Validator1 :", validator1Addr);
        console2.log("Validator2 :", validator2Addr);
        console2.log("Validator3 :", validator3Addr);
        console2.log("");

        uint256 totalNeeded =
            (FUND_AMOUNT * 4) + CONTRIBUTOR_TOKENS + CHALLENGER_TOKENS + (VALIDATOR_TOKENS * 3);
        uint256 deployerBal = token.balanceOf(DEPLOYER);
        console2.log("Deployer SAPIEN balance:", deployerBal);
        console2.log("Total SAPIEN needed    :", totalNeeded);
        require(deployerBal >= totalNeeded, "Deployer lacks SAPIEN");

        // ── Fund all accounts ────────────────────────────────────────────
        vm.startBroadcast();
        token.transfer(contributorAddr, CONTRIBUTOR_TOKENS);
        token.transfer(challengerAddr, CHALLENGER_TOKENS);
        token.transfer(validator1Addr, VALIDATOR_TOKENS);
        token.transfer(validator2Addr, VALIDATOR_TOKENS);
        token.transfer(validator3Addr, VALIDATOR_TOKENS);
        _sendEth(contributorAddr, ETH_FOR_GAS);
        _sendEth(challengerAddr, ETH_FOR_GAS);
        _sendEth(validator1Addr, ETH_FOR_GAS);
        _sendEth(validator2Addr, ETH_FOR_GAS);
        _sendEth(validator3Addr, ETH_FOR_GAS);
        console2.log("[deployer] Funded all accounts with SAPIEN + ETH");
        vm.stopBroadcast();

        // ── Deposit stakes ───────────────────────────────────────────────
        _depositStake(CONTRIBUTOR_PK, contributorAddr, CONTRIBUTOR_TOKENS / 2);
        _depositStake(CHALLENGER_PK, challengerAddr, CHALLENGER_TOKENS / 2);
        _depositStake(VALIDATOR1_PK, validator1Addr, VALIDATOR_TOKENS / 2);
        _depositStake(VALIDATOR2_PK, validator2Addr, VALIDATOR_TOKENS / 2);
        _depositStake(VALIDATOR3_PK, validator3Addr, VALIDATOR_TOKENS / 2);
        console2.log("[all] Deposited stakes into vault");

        // ── Create and fund all 4 projects ───────────────────────────────
        vm.startBroadcast();
        _createAndFundProject(projRejection, "rejection");
        _createAndFundProject(projDispute, "dispute");
        _createAndFundProject(projClaimExpiry, "claim-expiry");
        _createAndFundProject(projValExpiry, "val-expiry");
        console2.log("[deployer] Created and funded 4 test projects");
        vm.stopBroadcast();

        console2.log("");

        // ══════════════════════════════════════════════════════════════════
        // Scenario A: Contribution Rejection (contributor slashed)
        // ══════════════════════════════════════════════════════════════════
        _logHeader("Scenario A: Contribution Rejection");

        uint256 contribBalBefore = vault.availableBalance(contributorAddr);

        // Contributor submits
        uint256 indexA;
        vm.startBroadcast(CONTRIBUTOR_PK);
        {
            (uint256 claimId, uint256[] memory indices) =
                engine.claimToContribute(projRejection, 1, address(0));
            indexA = indices[0];
            engine.contribute(claimId, indexA, keccak256("rejection-submission"), "");
        }
        vm.stopBroadcast();
        console2.log("  Contributor submitted at index:", indexA);

        // Validators score LOW (below 7000 threshold)
        _validatorCommitReveal(VALIDATOR1_PK, validator1Addr, projRejection, indexA, 2500);
        _validatorCommitReveal(VALIDATOR2_PK, validator2Addr, projRejection, indexA, 3000);
        _validatorCommitReveal(VALIDATOR3_PK, validator3Addr, projRejection, indexA, 2000);
        console2.log("  Validators scored LOW (2500, 3000, 2000)");

        // Consensus: REJECTED
        vm.startBroadcast();
        engine.computeConsensus(projRejection, indexA);
        vm.stopBroadcast();

        Contribution memory contribA = engine.getContribution(projRejection, indexA);
        ConsensusReport memory reportA = engine.getConsensusReport(projRejection, indexA);
        console2.log("  Consensus result   :", uint256(contribA.status), "(3=Accepted, 4=Rejected)");
        console2.log("  Weighted average   :", reportA.weightedAverage);

        // For rejected contributions, validators can settle immediately (no challenge wait)
        uint256 nonceA = contribA.consensusNonce;
        _settleValidator(VALIDATOR1_PK, projRejection, indexA, nonceA);
        _settleValidator(VALIDATOR2_PK, projRejection, indexA, nonceA);
        _settleValidator(VALIDATOR3_PK, projRejection, indexA, nonceA);
        console2.log("  Validators settled (stake returned, no reward for rejected)");

        uint256 contribBalAfter = vault.availableBalance(contributorAddr);
        uint256 slashed = contribBalBefore > contribBalAfter ? contribBalBefore - contribBalAfter : 0;
        console2.log("  Contributor stake slashed:", slashed);

        Reputation memory rep = engine.getReputation(contributorAddr, SKILL_ID);
        console2.log("  Contributor reputation   :", rep.score);

        // ══════════════════════════════════════════════════════════════════
        // Scenario B: Dispute Bond Locking
        // ══════════════════════════════════════════════════════════════════
        _logHeader("Scenario B: Dispute Bond Locking");

        uint256 challengerAvailBefore = vault.availableBalance(challengerAddr);

        // Contributor submits
        uint256 indexB;
        vm.startBroadcast(CONTRIBUTOR_PK);
        {
            (uint256 claimId, uint256[] memory indices) =
                engine.claimToContribute(projDispute, 1, address(0));
            indexB = indices[0];
            engine.contribute(claimId, indexB, keccak256("dispute-submission"), "");
        }
        vm.stopBroadcast();
        console2.log("  Contributor submitted at index:", indexB);

        // Validators score HIGH (above threshold)
        _validatorCommitReveal(VALIDATOR1_PK, validator1Addr, projDispute, indexB, 8000);
        _validatorCommitReveal(VALIDATOR2_PK, validator2Addr, projDispute, indexB, 8500);
        _validatorCommitReveal(VALIDATOR3_PK, validator3Addr, projDispute, indexB, 7500);
        console2.log("  Validators scored HIGH (8000, 8500, 7500)");

        // Consensus: ACCEPTED
        vm.startBroadcast();
        engine.computeConsensus(projDispute, indexB);
        vm.stopBroadcast();

        console2.log("  Consensus: ACCEPTED (weighted avg:", engine.getConsensusReport(projDispute, indexB).weightedAverage, ")");

        // Challenger opens dispute during challenge window
        vm.startBroadcast(CHALLENGER_PK);
        engine.openDispute(projDispute, indexB, keccak256("dispute-evidence"), "ipfs://evidence");
        vm.stopBroadcast();

        Dispute memory dispute = engine.getDispute(projDispute, indexB);
        uint256 challengerAvailAfter = vault.availableBalance(challengerAddr);
        console2.log("  Dispute opened! Status:", uint256(dispute.status), "(1=Open)");
        console2.log("  Bond amount locked:", dispute.bondAmount);
        console2.log("  Challenger available balance reduced by:", challengerAvailBefore - challengerAvailAfter);
        console2.log("  NOTE: Resolution requires OPERATOR_ROLE (Safe). Validators cannot settle while dispute is open.");

        // ══════════════════════════════════════════════════════════════════
        // Scenario C: Claim Expiration Setup (contributor claims but only partially submits)
        // ══════════════════════════════════════════════════════════════════
        _logHeader("Scenario C: Claim Expiration (setup)");

        vm.startBroadcast(CONTRIBUTOR_PK);
        {
            // Claim 2 slots but only submit 1
            (uint256 claimId, uint256[] memory indices) =
                engine.claimToContribute(projClaimExpiry, 2, address(0));
            console2.log("  Claimed 2 slots. Indices:", indices[0], indices[1]);
            console2.log("  Claim ID:", claimId);

            // Submit only the first index
            engine.contribute(claimId, indices[0], keccak256("partial-submission"), "");
            console2.log("  Submitted only index", indices[0]);
            console2.log("  Left unsubmitted index", indices[1]);
        }
        vm.stopBroadcast();

        uint256 claimDeadline_ = engine.claimDeadline();
        console2.log("  Claim deadline duration:", claimDeadline_, "seconds");
        console2.log("  Expiration available after:", block.timestamp + claimDeadline_);

        // ══════════════════════════════════════════════════════════════════
        // Scenario D: Validation Claim Expiry Setup
        // ══════════════════════════════════════════════════════════════════
        _logHeader("Scenario D: Validation Claim Expiry (setup)");

        // Contributor submits work
        uint256 indexD;
        vm.startBroadcast(CONTRIBUTOR_PK);
        {
            (uint256 claimId, uint256[] memory indices) =
                engine.claimToContribute(projValExpiry, 1, address(0));
            indexD = indices[0];
            engine.contribute(claimId, indexD, keccak256("val-expiry-submission"), "");
        }
        vm.stopBroadcast();
        console2.log("  Contributor submitted at index:", indexD);

        // Validator1 claims to validate but does NOT commit
        vm.startBroadcast(VALIDATOR1_PK);
        uint256 valClaimId = engine.claimToValidate(projValExpiry, 1);
        vm.stopBroadcast();
        console2.log("  Validator1 claimed to validate (claimId:", valClaimId, ") but did NOT commit");
        console2.log("  Validation claim deadline: 1 hour (fixed constant)");

        // ══════════════════════════════════════════════════════════════════
        // Summary
        // ══════════════════════════════════════════════════════════════════
        console2.log("");
        _logHeader("PHASE 1 COMPLETE");
        console2.log("Scenario A: Contributor REJECTED and SLASHED (complete)");
        console2.log("Scenario B: Dispute OPENED, challenger bond LOCKED (complete)");
        console2.log("Scenario C: Claim with partial submission (awaiting expiration)");
        console2.log("Scenario D: Validation claim without commit (awaiting expiration)");
        console2.log("");
        console2.log(">> Wait 1+ hour for claim/validation deadlines to expire");
        console2.log(">> Then run phase2()");
    }

    // ═════════════════════════════════════════════════════════════════════
    // Phase 2 - Time-dependent actions + Cleanup
    // ═════════════════════════════════════════════════════════════════════

    function phase2() external {
        require(block.chainid == BASE_SEPOLIA_CHAIN_ID, "Not Base Sepolia");

        _logHeader("PHASE 2: Time-Dependent Actions & Cleanup");

        // ══════════════════════════════════════════════════════════════════
        // Scenario C: Expire claim and slash contributor
        // ══════════════════════════════════════════════════════════════════
        _logHeader("Scenario C: Claim Expiration");

        (uint256 claimIdC, uint256[] memory indicesC) = _findClaimForExpiry(projClaimExpiry, contributorAddr, 2);
        Claim memory claimC = engine.getClaim(claimIdC);

        console2.log("  Claim ID:", claimIdC);
        console2.log("  Claim deadline:", claimC.deadline, "| Current time:", block.timestamp);
        require(block.timestamp > claimC.deadline, "Claim deadline not passed - wait longer");
        require(uint256(claimC.status) == uint256(ClaimStatus.Active), "Claim not Active (already expired?)");

        uint256 contribAvailBefore = vault.availableBalance(contributorAddr);

        // Anyone can call expireClaim (permissionless keeper)
        vm.startBroadcast();
        engine.expireClaim(claimIdC, indicesC);
        vm.stopBroadcast();

        Claim memory claimCAfter = engine.getClaim(claimIdC);
        uint256 contribAvailAfter = vault.availableBalance(contributorAddr);

        console2.log("  Claim status after:", uint256(claimCAfter.status), "(2=Expired)");
        console2.log("  1 unsubmitted slot: contributor SLASHED", STAKE_AMOUNT);
        console2.log("  1 submitted slot  : contributor stake UNLOCKED", STAKE_AMOUNT);
        console2.log("  Available balance change:", _signedDiff(contribAvailAfter, contribAvailBefore));

        // ══════════════════════════════════════════════════════════════════
        // Scenario D: Cancel expired validation claim
        // ══════════════════════════════════════════════════════════════════
        _logHeader("Scenario D: Validation Claim Expiry");

        uint256 valClaimIdD = _findValidationClaim(projValExpiry, validator1Addr);
        ValidationClaim memory vclaim = engine.getValidationClaim(valClaimIdD);

        console2.log("  Validation claim ID:", valClaimIdD);
        console2.log("  Claim deadline:", vclaim.deadline, "| Current time:", block.timestamp);
        require(block.timestamp > vclaim.deadline, "Validation claim deadline not passed - wait longer");
        require(
            uint256(vclaim.status) == uint256(ValidationClaimStatus.Active),
            "Validation claim not Active (already expired?)"
        );

        Reputation memory repBefore = engine.getReputation(validator1Addr, SKILL_ID);

        vm.startBroadcast();
        engine.cancelExpiredValidationClaim(valClaimIdD);
        vm.stopBroadcast();

        ValidationClaim memory vclaimAfter = engine.getValidationClaim(valClaimIdD);
        Reputation memory repAfter = engine.getReputation(validator1Addr, SKILL_ID);

        console2.log("  Validation claim status:", uint256(vclaimAfter.status), "(2=Expired)");
        console2.log("  No stake slashed (validator never committed)");
        console2.log("  Validator1 reputation before:", repBefore.score, "-> after:", repAfter.score);
        console2.log("  Validation slot released for other validators");

        // ══════════════════════════════════════════════════════════════════
        // Scenario B: Check dispute status
        // ══════════════════════════════════════════════════════════════════
        _logHeader("Scenario B: Dispute Status Check");

        uint256 indexB = _findContributionIndex(projDispute, contributorAddr);
        Dispute memory disputeB = engine.getDispute(projDispute, indexB);
        console2.log("  Dispute status:", uint256(disputeB.status), "(1=Open)");
        console2.log("  Challenger bond still locked:", disputeB.bondAmount);
        console2.log("  Validators cannot settle while dispute is Open");
        console2.log("  Resolution options:");
        console2.log("    - OPERATOR_ROLE (Safe) calls resolveDispute(upheld/rejected)");
        console2.log("    - After 7 days: anyone calls escalateDispute (auto-upholds)");

        // ══════════════════════════════════════════════════════════════════
        // Cleanup
        // ══════════════════════════════════════════════════════════════════
        _logHeader("Cleanup");

        // Claim any pending rewards
        _claimRewardIfPending(CONTRIBUTOR_PK, contributorAddr, "contributor");
        _claimRewardIfPending(CHALLENGER_PK, challengerAddr, "challenger");
        _claimRewardIfPending(VALIDATOR1_PK, validator1Addr, "validator1");
        _claimRewardIfPending(VALIDATOR2_PK, validator2Addr, "validator2");
        _claimRewardIfPending(VALIDATOR3_PK, validator3Addr, "validator3");

        uint256 deployerPending = engine.getPendingRewards(DEPLOYER, SAPIEN_TOKEN);
        if (deployerPending > 0) {
            vm.startBroadcast();
            engine.claimReward(SAPIEN_TOKEN);
            vm.stopBroadcast();
            console2.log("[deployer] Claimed pending reward:", deployerPending);
        }

        // Cleanup accounts (unlock capacity, withdraw, return tokens)
        // NOTE: Project B validators have in-flight stake locked by open dispute
        _cleanupAccount(VALIDATOR1_PK, validator1Addr, "validator1", true);
        _cleanupAccount(VALIDATOR2_PK, validator2Addr, "validator2", true);
        _cleanupAccount(VALIDATOR3_PK, validator3Addr, "validator3", true);
        _cleanupAccount(CONTRIBUTOR_PK, contributorAddr, "contributor", false);
        _cleanupAccount(CHALLENGER_PK, challengerAddr, "challenger", false);

        console2.log("");
        _logHeader("PHASE 2 COMPLETE");
        console2.log("SAPIEN recovered to deployer:", token.balanceOf(DEPLOYER));
        console2.log("");
        console2.log("NOTE: Some tokens remain locked in the open dispute (project B).");
        console2.log("Resolve dispute via Safe to fully unlock.");
    }

    // ═════════════════════════════════════════════════════════════════════
    // Internal Helpers
    // ═════════════════════════════════════════════════════════════════════

    function _logHeader(string memory title) internal pure {
        console2.log("========================================");
        console2.log(string.concat("  ", title));
        console2.log("========================================");
    }

    function _sendEth(address to, uint256 amount) internal {
        (bool ok,) = payable(to).call{value: amount}("");
        require(ok, "ETH transfer failed");
    }

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

    function _createAndFundProject(bytes32 pid, string memory label) internal {
        token.approve(address(engine), FUND_AMOUNT);
        engine.createProject(pid, string.concat("ipfs://edge-", label), _projectConfig());
        engine.fundProject(pid, FUND_AMOUNT, QUANTITY, DEPLOYER);
    }

    function _depositStake(uint256 pk, address account, uint256 amount) internal {
        vm.startBroadcast(pk);
        token.approve(address(vault), type(uint256).max);
        vault.deposit(amount, account);
        vm.stopBroadcast();
    }

    function _validatorCommitReveal(
        uint256 pk,
        address val,
        bytes32 pid,
        uint256 index,
        uint256 score
    ) internal {
        bytes32 salt = keccak256(abi.encodePacked("edge-salt", val, pid, index));
        bytes32 commitHash = keccak256(abi.encodePacked(score, salt));

        vm.startBroadcast(pk);
        engine.claimToValidate(pid, 1);
        engine.lockValidatorCapacity(VALIDATOR_STAKE);
        engine.commitValidation(pid, index, commitHash, VALIDATOR_STAKE, address(0));
        engine.revealValidation(pid, index, score, salt);
        vm.stopBroadcast();
    }

    function _settleValidator(uint256 pk, bytes32 pid, uint256 index, uint256 nonce) internal {
        vm.startBroadcast(pk);
        engine.settleValidator(pid, index, nonce);
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

    function _findContributionIndex(bytes32 pid, address contrib) internal view returns (uint256) {
        for (uint256 i = 0; i < QUANTITY; i++) {
            Contribution memory c = engine.getContribution(pid, i);
            if (c.contributor == contrib) return i;
        }
        revert("Contribution not found");
    }

    /// @dev Find a claim and reconstruct its indices for expireClaim.
    function _findClaimForExpiry(bytes32 pid, address claimant, uint256 totalCount)
        internal
        view
        returns (uint256 claimId, uint256[] memory indices)
    {
        indices = new uint256[](totalCount);
        uint256 found = 0;
        for (uint256 i = 0; i < QUANTITY && found < totalCount; i++) {
            Contribution memory c = engine.getContribution(pid, i);
            if (c.contributor == claimant && c.claimId != 0) {
                if (found == 0) claimId = c.claimId;
                if (c.claimId == claimId) {
                    indices[found++] = i;
                }
            }
        }
        require(found == totalCount, "Could not find all claim indices");
    }

    /// @dev Scan for a validation claim by validator + project.
    function _findValidationClaim(bytes32 pid, address validator) internal view returns (uint256) {
        for (uint256 id = 1; id <= 200; id++) {
            ValidationClaim memory vc = engine.getValidationClaim(id);
            if (vc.validator == validator && vc.projectId == pid && vc.status == ValidationClaimStatus.Active) {
                return id;
            }
        }
        revert("Validation claim not found");
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

    function _signedDiff(uint256 after_, uint256 before_) internal pure returns (string memory) {
        if (after_ >= before_) {
            return string.concat("+", vm.toString(after_ - before_));
        } else {
            return string.concat("-", vm.toString(before_ - after_));
        }
    }
}
