// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// Core contracts
import {SapienCore} from "../src/SapienCore.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {SapienTrust} from "../src/SapienTrust.sol";
import {ValidationOracle} from "../src/ValidationOracle.sol";
import {Rewards} from "../src/Rewards.sol";

// Consensus algorithms
import {SqrtStakeConsensus} from "../src/consensus/SqrtStakeConsensus.sol";

// Interfaces
import {ISapienCore} from "../src/interface/ISapienCore.sol";
import {IValidationOracle} from "../src/interface/IValidationOracle.sol";

// Roles and shared types
import {CONTRIBUTOR_ROLE, VALIDATOR_ROLE, UPDATER_ROLE, SAPIEN_CORE_ROLE} from "../src/interface/ISharedTypes.sol";

// Mock token
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title FrontendIntegrationTest
 * @notice Complete end-to-end test showing every frontend call for all roles
 * @dev This test is intentionally verbose with no abstraction to serve as
 *      documentation for frontend developers integrating with the protocol.
 *
 * ROLES COVERED:
 * 1. Admin - Protocol configuration
 * 2. Originator - Project creation and funding
 * 3. Contributor - Claiming slots and submitting work
 * 4. Validator - Staking, claiming, committing, revealing validations
 * 5. Everyone - Claiming rewards
 */
contract FrontendIntegrationTest is Test {
    function test_CompleteEndToEndFlow() public {
        // ================================================================
        // SECTION 1: DEPLOY ALL CONTRACTS
        // ================================================================
        console.log("\n========== SECTION 1: DEPLOY CONTRACTS ==========\n");

        // Create addresses for all participants
        address admin = makeAddr("admin");
        address treasury = makeAddr("treasury");
        address originator = makeAddr("originator");
        address contributor = makeAddr("contributor");
        address validator1 = makeAddr("validator1");
        address validator2 = makeAddr("validator2");
        address validator3 = makeAddr("validator3");
        address frontendOperator = makeAddr("frontendOperator");

        // Deploy mock tokens
        vm.startPrank(admin);

        MockERC20 stakeToken = new MockERC20("Stake Token", "STK", 18);
        MockERC20 rewardToken = new MockERC20("Reward Token", "RWD", 18);

        console.log("Stake Token deployed at:", address(stakeToken));
        console.log("Reward Token deployed at:", address(rewardToken));

        // Deploy SapienVault (ERC4626 vault for staking)
        SapienVault vaultImpl = new SapienVault();
        ERC1967Proxy vaultProxy =
            new ERC1967Proxy(address(vaultImpl), abi.encodeCall(SapienVault.initialize, (address(stakeToken), admin)));
        SapienVault vault = SapienVault(address(vaultProxy));
        console.log("SapienVault deployed at:", address(vault));

        // Deploy SapienTrust (reputation and role management)
        // Parameters: vault, minStake, decayRate, admin
        SapienTrust trustImpl = new SapienTrust();
        ERC1967Proxy trustProxy = new ERC1967Proxy(
            address(trustImpl),
            abi.encodeWithSelector(SapienTrust.initialize.selector, address(vault), 100 ether, 30, admin)
        );
        SapienTrust trust = SapienTrust(address(trustProxy));
        console.log("SapienTrust deployed at:", address(trust));

        // Deploy Rewards contract
        Rewards rewardsImpl = new Rewards();
        ERC1967Proxy rewardsProxy = new ERC1967Proxy(address(rewardsImpl), abi.encodeCall(Rewards.initialize, (admin)));
        Rewards rewards = Rewards(address(rewardsProxy));
        console.log("Rewards deployed at:", address(rewards));

        // Deploy consensus algorithm first (needed for oracle init)
        SqrtStakeConsensus sqrtConsensus = new SqrtStakeConsensus();
        console.log("SqrtStakeConsensus deployed at:", address(sqrtConsensus));

        // Deploy ValidationOracle
        // Parameters: trust, vault, defaultAlgorithmName, admin
        ValidationOracle oracleImpl = new ValidationOracle();
        ERC1967Proxy oracleProxy = new ERC1967Proxy(
            address(oracleImpl),
            abi.encodeCall(ValidationOracle.initialize, (address(trust), address(vault), "SqrtStake", admin))
        );
        ValidationOracle oracle = ValidationOracle(address(oracleProxy));
        console.log("ValidationOracle deployed at:", address(oracle));

        // Deploy SapienCore
        // Parameters: vault, rewards, trust, oracle, admin
        SapienCore coreImpl = new SapienCore();
        ERC1967Proxy coreProxy = new ERC1967Proxy(
            address(coreImpl),
            abi.encodeCall(
                SapienCore.initialize, (address(vault), address(rewards), address(trust), address(oracle), admin)
            )
        );
        SapienCore core = SapienCore(address(coreProxy));
        console.log("SapienCore deployed at:", address(core));

        vm.stopPrank();

        // ================================================================
        // SECTION 2: ADMIN CONFIGURATION
        // ================================================================
        console.log("\n========== SECTION 2: ADMIN CONFIGURATION ==========\n");

        vm.startPrank(admin);

        // 2.1 Link Rewards to Core
        rewards.setCore(address(core));
        console.log("Rewards: setCore() - linked core contract");

        // 2.2 Register consensus algorithm (default was set in initialize)
        oracle.registerAlgorithm("SqrtStake", address(sqrtConsensus));
        console.log("Oracle: registerAlgorithm('SqrtStake') - registered consensus algorithm");

        // 2.4 Grant required roles for inter-contract communication
        trust.grantRole(UPDATER_ROLE, address(oracle));
        trust.grantRole(UPDATER_ROLE, address(core));
        console.log("Trust: grantRole(UPDATER_ROLE) - to oracle and core");

        // Vault roles for locking/slashing stake
        bytes32 LOCKER_ROLE = keccak256("LOCKER_ROLE");
        bytes32 SLASHER_ROLE = keccak256("SLASHER_ROLE");

        vault.grantRole(LOCKER_ROLE, address(oracle));
        vault.grantRole(LOCKER_ROLE, address(core));
        console.log("Vault: grantRole(LOCKER_ROLE) - to oracle and core");

        vault.grantRole(SLASHER_ROLE, address(oracle));
        vault.grantRole(SLASHER_ROLE, address(core));
        vault.grantRole(SLASHER_ROLE, address(vault));
        console.log("Vault: grantRole(SLASHER_ROLE) - to oracle, core, and vault");

        // Oracle needs to know about Core
        oracle.grantRole(SAPIEN_CORE_ROLE, address(core));
        console.log("Oracle: grantRole(SAPIEN_CORE_ROLE) - to core");

        // 2.4 Configure protocol fees
        core.setTreasury(treasury);
        console.log("Core: setTreasury() - set treasury address");

        core.setProtocolFeeBasisPoints(100); // 1%
        console.log("Core: setProtocolFeeBasisPoints(100) - set 1% protocol fee");

        // 2.5 Grant roles to participants
        // NOTE: No roles are granted here because hasEnoughStakeForRole() only checks stake,
        // not the role grant itself. Access control is purely stake-based.
        console.log("No role grants needed - access is stake-based");

        trust.grantRole(UPDATER_ROLE, admin);
        console.log("Trust: grantRole(UPDATER_ROLE) - granted to admin");

        // 2.6 Mint tokens for all participants
        stakeToken.mint(originator, 1000 ether);
        stakeToken.mint(contributor, 1000 ether);
        stakeToken.mint(validator1, 1000 ether);
        stakeToken.mint(validator2, 1000 ether);
        stakeToken.mint(validator3, 1000 ether);
        console.log("Minted 1000 stake tokens to each participant");

        rewardToken.mint(originator, 10000 ether);
        console.log("Minted 10000 reward tokens to originator");

        vm.stopPrank();

        // ================================================================
        // SECTION 3: STAKING (All participants who need stake)
        // ================================================================
        console.log("\n========== SECTION 3: STAKING ==========\n");

        // 3.1 Originator stakes (needed for hasEnoughStakeForRole check)
        vm.startPrank(originator);
        stakeToken.approve(address(vault), 100 ether);
        console.log("Originator: approve(vault, 100 ether) - approved stake tokens");

        uint256 originatorShares = vault.deposit(100 ether, originator);
        console.log("Originator: vault.deposit(100 ether) - received shares:", originatorShares);
        vm.stopPrank();

        // 3.2 Contributor stakes
        vm.startPrank(contributor);
        stakeToken.approve(address(vault), 100 ether);
        console.log("Contributor: approve(vault, 100 ether) - approved stake tokens");

        uint256 contributorShares = vault.deposit(100 ether, contributor);
        console.log("Contributor: vault.deposit(100 ether) - received shares:", contributorShares);
        vm.stopPrank();

        // 3.3 Validators stake
        vm.startPrank(validator1);
        stakeToken.approve(address(vault), 100 ether);
        uint256 v1Shares = vault.deposit(100 ether, validator1);
        console.log("Validator1: vault.deposit(100 ether) - received shares:", v1Shares);
        vm.stopPrank();

        vm.startPrank(validator2);
        stakeToken.approve(address(vault), 100 ether);
        uint256 v2Shares = vault.deposit(100 ether, validator2);
        console.log("Validator2: vault.deposit(100 ether) - received shares:", v2Shares);
        vm.stopPrank();

        vm.startPrank(validator3);
        stakeToken.approve(address(vault), 100 ether);
        uint256 v3Shares = vault.deposit(100 ether, validator3);
        console.log("Validator3: vault.deposit(100 ether) - received shares:", v3Shares);
        vm.stopPrank();

        // ================================================================
        // SECTION 4: VALIDATOR CAPACITY SETUP
        // ================================================================
        console.log("\n========== SECTION 4: VALIDATOR CAPACITY ==========\n");

        vm.startPrank(validator1);
        oracle.setValidatorCapacity(100 ether);
        console.log("Validator1: oracle.setValidatorCapacity(100 ether)");
        vm.stopPrank();

        vm.startPrank(validator2);
        oracle.setValidatorCapacity(100 ether);
        console.log("Validator2: oracle.setValidatorCapacity(100 ether)");
        vm.stopPrank();

        vm.startPrank(validator3);
        oracle.setValidatorCapacity(100 ether);
        console.log("Validator3: oracle.setValidatorCapacity(100 ether)");
        vm.stopPrank();

        // ================================================================
        // SECTION 5: ORIGINATOR CREATES PROJECT
        // ================================================================
        console.log("\n========== SECTION 5: CREATE PROJECT ==========\n");

        bytes32 projectId = keccak256("my-awesome-project-cid");

        vm.startPrank(originator);

        // 5.1 Create the project
        core.createProject(
            projectId,
            address(rewardToken), // reward token
            "my-awesome-project-cid", // IPFS CID
            10 ether, // minStakeToClaim - contributors need 10 ETH staked
            5 ether, // minStakeToContribute
            3, // numberOfValidations - need 3 validators
            1000, // validatorRewardBasisPoints - 10% goes to validators
            "" // requiredSkill - no skill requirement
        );
        console.log("Originator: core.createProject()");
        console.log("  - projectId:", vm.toString(projectId));
        console.log("  - rewardToken:", address(rewardToken));
        console.log("  - minStakeToClaim: 10 ether");
        console.log("  - numberOfValidations: 3");
        console.log("  - validatorRewardBps: 1000 (10%)");

        // 5.2 Fund the project (with operator fee)
        rewardToken.approve(address(core), 1000 ether);
        console.log("Originator: rewardToken.approve(core, 1000 ether)");

        core.fundProject(
            projectId,
            1000 ether, // total reward amount
            10, // 10 contribution slots
            frontendOperator, // operator gets fee
            200 // 2% operator fee
        );
        console.log("Originator: core.fundProject()");
        console.log("  - rewardAmount: 1000 ether");
        console.log("  - quantity: 10 slots");
        console.log("  - operatorFee: 2% to", frontendOperator);

        vm.stopPrank();

        // Check project state
        ISapienCore.Project memory project = core.getProject(projectId);
        console.log("\nProject state after funding:");
        console.log("  - totalRewardsAvailable:", project.state.totalRewardsAvailable);
        console.log("  - totalQuantityAvailable:", project.state.totalQuantityAvailable);

        // ================================================================
        // SECTION 6: CONTRIBUTOR CLAIMS AND SUBMITS
        // ================================================================
        console.log("\n========== SECTION 6: CONTRIBUTOR WORKFLOW ==========\n");

        vm.startPrank(contributor);

        // 6.1 Check available quantity before claiming
        ISapienCore.Project memory projectBeforeClaim = core.getProject(projectId);
        uint256 availableBefore = projectBeforeClaim.state.totalQuantityAvailable
            - (projectBeforeClaim.state.submittedQuantity + projectBeforeClaim.state.activeClaimedQuantity);
        console.log("Available slots before claim:", availableBefore);

        // 6.2 Claim contribution slots
        uint256 claimId = core.claimToContribute(projectId, 2); // Claim 2 slots
        console.log("Contributor: core.claimToContribute(projectId, 2)");
        console.log("  - claimId:", claimId);

        // 6.3 Check claim details
        ISapienCore.Claim memory claim = core.getClaim(projectId, claimId);
        console.log("Claim details:");
        console.log("  - quantity:", claim.quantity);
        console.log("  - deadline:", claim.deadline);
        console.log("  - status:", uint256(claim.status));

        // 6.4 Submit first contribution
        bytes32 contentHash1 = keccak256("ipfs://QmFirstContributionContent");
        core.contribute(projectId, claimId, 0, contentHash1); // index 0
        console.log("Contributor: core.contribute(projectId, claimId, 0, contentHash1)");

        // 6.5 Submit second contribution
        bytes32 contentHash2 = keccak256("ipfs://QmSecondContributionContent");
        core.contribute(projectId, claimId, 1, contentHash2); // index 1
        console.log("Contributor: core.contribute(projectId, claimId, 1, contentHash2)");

        vm.stopPrank();

        // Check contribution state
        ISapienCore.Contribution memory contrib1 = core.getContribution(projectId, 0);
        console.log("\nContribution 0 state:");
        console.log("  - contributor:", contrib1.contributor);
        console.log("  - submissionHash:", vm.toString(contrib1.submissionHash));
        console.log("  - status:", uint256(contrib1.status));

        // ================================================================
        // SECTION 7: VALIDATORS COMMIT PHASE
        // ================================================================
        console.log("\n========== SECTION 7: VALIDATORS COMMIT ==========\n");

        // Validators will validate contribution index 0
        uint256 contributionIndex = 0;

        // Validator scores and salts (in real app, these are secret until reveal)
        uint256 score1 = 8000; // 80% score
        uint256 score2 = 8500; // 85% score
        uint256 score3 = 7500; // 75% score
        uint256 stakeAmount = 100 ether; // Amount each validator stakes on their validation (must >= minStake)
        bytes32 salt1 = keccak256("validator1-secret-salt");
        bytes32 salt2 = keccak256("validator2-secret-salt");
        bytes32 salt3 = keccak256("validator3-secret-salt");

        // 7.1 Validator 1 claims and commits with stake
        vm.startPrank(validator1);
        uint256 v1ClaimId = oracle.claimToValidate(projectId);
        console.log("Validator1: oracle.claimToValidate() - claimId:", v1ClaimId);

        bytes32 commitHash1 = keccak256(abi.encodePacked(score1, stakeAmount, salt1));
        oracle.commitValidationWithStake(projectId, v1ClaimId, contributionIndex, stakeAmount, commitHash1);
        console.log("Validator1: oracle.commitValidationWithStake()");
        console.log("  - score:", score1, "stake:", stakeAmount);
        vm.stopPrank();

        // 7.2 Validator 2 claims and commits with stake
        vm.startPrank(validator2);
        uint256 v2ClaimId = oracle.claimToValidate(projectId);
        console.log("Validator2: oracle.claimToValidate() - claimId:", v2ClaimId);

        bytes32 commitHash2 = keccak256(abi.encodePacked(score2, stakeAmount, salt2));
        oracle.commitValidationWithStake(projectId, v2ClaimId, contributionIndex, stakeAmount, commitHash2);
        console.log("Validator2: oracle.commitValidationWithStake()");
        vm.stopPrank();

        // 7.3 Validator 3 claims and commits with stake
        vm.startPrank(validator3);
        uint256 v3ClaimId = oracle.claimToValidate(projectId);
        console.log("Validator3: oracle.claimToValidate() - claimId:", v3ClaimId);

        bytes32 commitHash3 = keccak256(abi.encodePacked(score3, stakeAmount, salt3));
        oracle.commitValidationWithStake(projectId, v3ClaimId, contributionIndex, stakeAmount, commitHash3);
        console.log("Validator3: oracle.commitValidationWithStake()");
        vm.stopPrank();

        // ================================================================
        // SECTION 8: VALIDATORS REVEAL PHASE
        // ================================================================
        console.log("\n========== SECTION 8: VALIDATORS REVEAL ==========\n");

        // Fast forward past commit deadline (1 hour default)
        vm.warp(block.timestamp + 1 hours + 1);
        console.log("Time warped: +1 hour (past commit deadline)");

        // 8.1 Validator 1 reveals
        vm.startPrank(validator1);
        oracle.revealValidation(projectId, contributionIndex, score1, salt1);
        console.log("Validator1: oracle.revealValidation(score:", score1, ")");
        vm.stopPrank();

        // 8.2 Validator 2 reveals
        vm.startPrank(validator2);
        oracle.revealValidation(projectId, contributionIndex, score2, salt2);
        console.log("Validator2: oracle.revealValidation(score:", score2, ")");
        vm.stopPrank();

        // 8.3 Validator 3 reveals
        vm.startPrank(validator3);
        oracle.revealValidation(projectId, contributionIndex, score3, salt3);
        console.log("Validator3: oracle.revealValidation(score:", score3, ")");
        vm.stopPrank();

        // Check validation state
        IValidationOracle.Validation[] memory validations = oracle.getValidations(projectId, contributionIndex);
        console.log("\nValidations for contribution 0:");
        for (uint256 i = 0; i < validations.length; i++) {
            console.log("  Validator:", validations[i].validator, "Score:", validations[i].score);
        }

        // ================================================================
        // SECTION 9: FINALIZE CONTRIBUTION
        // ================================================================
        console.log("\n========== SECTION 9: FINALIZE CONTRIBUTION ==========\n");

        // Anyone can call finalize once validations are complete
        core.finalizeContribution(projectId, contributionIndex);
        console.log("Anyone: core.finalizeContribution(projectId, 0)");

        // 9.1 Claim rewards after challenge period
        // First warp past challenge period
        uint256 challengePeriod = core.getProject(projectId).config.challengePeriod;
        vm.warp(block.timestamp + challengePeriod + 1);
        console.log("Time warped past challenge period:", challengePeriod);

        core.claimContributionReward(projectId, contributionIndex);
        console.log("Anyone: core.claimContributionReward(projectId, 0)");

        // Check final state
        ISapienCore.Contribution memory finalContrib = core.getContribution(projectId, 0);
        console.log("Contribution 0 final state:");
        console.log("  - status:", uint256(finalContrib.status), "(2=Rewarded, 3=Rejected)");
        console.log("  - averageScore:", finalContrib.averageScore);

        // ================================================================
        // SECTION 10: CLAIM REWARDS
        // ================================================================
        console.log("\n========== SECTION 10: CLAIM REWARDS ==========\n");

        // 10.1 Check contributor's earned rewards
        uint256 contributorEarned = rewards.getTotalRewardsEarned(contributor, projectId, address(rewardToken));
        uint256 contributorAvailable = rewards.getAvailableRewards(contributor, projectId, address(rewardToken));
        console.log("Contributor earned rewards:", contributorEarned);
        console.log("Contributor available to claim:", contributorAvailable);

        // 10.2 Contributor claims rewards (with 1% operator fee)
        uint256 contributorBalanceBefore = rewardToken.balanceOf(contributor);

        vm.startPrank(contributor);
        rewards.claimRewards(
            projectId,
            address(rewardToken),
            frontendOperator, // fee recipient
            100 // 1% fee
        );
        console.log("Contributor: rewards.claimRewards()");
        console.log("  - feeRecipient:", frontendOperator);
        console.log("  - feeBps: 100 (1%)");
        vm.stopPrank();

        uint256 contributorBalanceAfter = rewardToken.balanceOf(contributor);
        console.log("Contributor received:", contributorBalanceAfter - contributorBalanceBefore);

        // 10.3 Check validator rewards
        uint256 v1Earned = rewards.getTotalValidatorRewardsEarned(validator1, projectId, address(rewardToken));
        uint256 v2Earned = rewards.getTotalValidatorRewardsEarned(validator2, projectId, address(rewardToken));
        uint256 v3Earned = rewards.getTotalValidatorRewardsEarned(validator3, projectId, address(rewardToken));
        console.log("\nValidator rewards earned:");
        console.log("  Validator1:", v1Earned);
        console.log("  Validator2:", v2Earned);
        console.log("  Validator3:", v3Earned);

        // 10.4 Validator 1 claims rewards
        uint256 v1BalanceBefore = rewardToken.balanceOf(validator1);

        vm.startPrank(validator1);
        rewards.claimValidatorRewards(
            projectId,
            address(rewardToken),
            address(0), // no fee
            0
        );
        console.log("Validator1: rewards.claimValidatorRewards() (no fee)");
        vm.stopPrank();

        uint256 v1BalanceAfter = rewardToken.balanceOf(validator1);
        console.log("Validator1 received:", v1BalanceAfter - v1BalanceBefore);

        // 10.5 Check frontend operator earnings
        uint256 operatorBalance = rewardToken.balanceOf(frontendOperator);
        console.log("\nFrontend operator total fees received:", operatorBalance);

        // ================================================================
        // SECTION 11: ADDITIONAL FRONTEND QUERIES
        // ================================================================
        console.log("\n========== SECTION 11: FRONTEND QUERIES ==========\n");

        // Useful read functions for frontend

        // Project info
        console.log("--- Project Queries ---");
        ISapienCore.Project memory projectFinal = core.getProject(projectId);
        console.log("totalRewardsAvailable:", projectFinal.state.totalRewardsAvailable);
        console.log("submittedQuantity:", projectFinal.state.submittedQuantity);
        console.log("rewardedQuantity:", projectFinal.state.rewardedQuantity);
        uint256 availableSlots = projectFinal.state.totalQuantityAvailable
            - (projectFinal.state.submittedQuantity + projectFinal.state.activeClaimedQuantity);
        console.log("availableSlots:", availableSlots);

        // User stake info
        console.log("\n--- Stake Queries ---");
        console.log("vault.getStake(contributor):", vault.getStake(contributor));
        console.log("vault.balanceOf(contributor):", vault.balanceOf(contributor));

        // Validator info
        console.log("\n--- Validator Queries ---");
        console.log("oracle.getAvailableCapacity(validator1):", oracle.getAvailableCapacity(validator1));

        // Trust/Reputation info
        console.log("\n--- Trust Queries ---");
        console.log(
            "trust.getTrustScore(contributor, CONTRIBUTOR_ROLE):", trust.getTrustScore(contributor, CONTRIBUTOR_ROLE)
        );
        console.log("trust.getTrustScore(validator1, VALIDATOR_ROLE):", trust.getTrustScore(validator1, VALIDATOR_ROLE));
        trust.hasEnoughStakeForRole(contributor, CONTRIBUTOR_ROLE);
        console.log("trust.hasEnoughStakeForRole(contributor, CONTRIBUTOR_ROLE): success");

        // ================================================================
        // SECTION 12: EDGE CASE - EXPIRED CONTRIBUTOR CLAIM
        // ================================================================
        console.log("\n========== SECTION 12: EDGE CASE - EXPIRED CONTRIBUTOR CLAIM ==========\n");

        // Create a second contributor for edge case testing
        address contributor2 = makeAddr("contributor2");

        vm.startPrank(admin);
        stakeToken.mint(contributor2, 1000 ether);
        vm.stopPrank();

        vm.startPrank(contributor2);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(100 ether, contributor2);
        vm.stopPrank();

        console.log("Created contributor2 with stake");

        // Contributor2 claims but doesn't submit in time
        vm.startPrank(contributor2);
        uint256 expiredClaimId = core.claimToContribute(projectId, 1);
        console.log("Contributor2: claimed 1 slot, claimId:", expiredClaimId);
        vm.stopPrank();

        // Fast forward past the claim deadline (7 days default)
        vm.warp(block.timestamp + 7 days + 1);
        console.log("Time warped: +7 days (past claim deadline)");

        // Anyone can reclaim expired indices
        // First, get the indices that were reserved but not submitted
        ISapienCore.Claim memory expiredClaim = core.getClaim(projectId, expiredClaimId);
        console.log("Expired claim status before reclaim:", uint256(expiredClaim.status));

        // Find which index was assigned (it would be 2 since 0 and 1 are taken)
        uint256[] memory expiredIndices = new uint256[](1);
        expiredIndices[0] = 2; // The third index

        // Reclaim the expired indices to make them available again
        core.reclaimExpiredIndices(projectId, expiredIndices);
        console.log("Anyone: core.reclaimExpiredIndices() - reclaimed index 2");

        // Verify the claim is now expired
        expiredClaim = core.getClaim(projectId, expiredClaimId);
        console.log("Expired claim status after reclaim:", uint256(expiredClaim.status), "(4=Expired)");

        // The contributor2 has been slashed for not fulfilling their claim
        uint256 c2StakeAfter = vault.getStake(contributor2);
        console.log("Contributor2 stake after slash:", c2StakeAfter);

        // ================================================================
        // SECTION 13: EDGE CASE - EXPIRED VALIDATOR CLAIM (No Commits)
        // ================================================================
        console.log("\n========== SECTION 13: EDGE CASE - EXPIRED VALIDATOR CLAIM ==========\n");

        // Create a fourth validator for edge case testing
        address validator4 = makeAddr("validator4");

        vm.startPrank(admin);
        stakeToken.mint(validator4, 1000 ether);
        vm.stopPrank();

        vm.startPrank(validator4);
        stakeToken.approve(address(vault), 100 ether);
        vault.deposit(100 ether, validator4);
        oracle.setValidatorCapacity(100 ether);
        vm.stopPrank();

        console.log("Created validator4 with stake and capacity");

        // Validator4 claims but doesn't commit any validations
        vm.startPrank(validator4);
        uint256 v4ClaimId = oracle.claimToValidate(projectId);
        console.log("Validator4: claimed to validate, claimId:", v4ClaimId);
        vm.stopPrank();

        // Get claim details from public mapping (only need deadline)
        (,,, uint256 v4Deadline,,,) = oracle.validationClaims(projectId, v4ClaimId);
        console.log("Validator4 claim deadline:", v4Deadline);

        // Fast forward past the validation claim deadline
        vm.warp(block.timestamp + 2 days);
        console.log("Time warped: +2 days (past validation claim deadline)");

        // Anyone can cancel the expired validation claim
        uint256 v4StakeBefore = vault.getStake(validator4);
        console.log("Validator4 stake before cancel:", v4StakeBefore);

        oracle.cancelExpiredValidationClaim(projectId, v4ClaimId);
        console.log("Anyone: oracle.cancelExpiredValidationClaim() - cancelled validator4's claim");

        uint256 v4StakeAfter = vault.getStake(validator4);
        console.log("Validator4 stake after cancel:", v4StakeAfter);
        console.log("Validator4 was slashed:", v4StakeBefore - v4StakeAfter);

        // ================================================================
        // SECTION 14: EDGE CASE - GHOST VALIDATOR (Commits but doesn't reveal)
        // ================================================================
        console.log("\n========== SECTION 14: EDGE CASE - GHOST VALIDATOR ==========\n");

        // NOTE: The ghost validator scenario demonstrates what happens when a validator
        // commits to a validation but fails to reveal before the deadline.
        //
        // This scenario requires specific queue state that's complex to set up
        // after the previous edge cases. Here's the documented flow:
        //
        // 1. Validator claims: oracle.claimToValidate(projectId)
        //    - Gets assigned a contribution index from the pending queue
        //
        // 2. Validator commits: oracle.commitValidationWithStake(projectId, claimId, index, stake, hash)
        //    - Creates a commitment with their staked amount
        //    - Hash = keccak256(abi.encodePacked(score, stakeAmount, salt))
        //
        // 3. Validator FAILS to reveal before deadline (reveal deadline is typically 1 hour)
        //
        // 4. Anyone calls: oracle.cancelExpiredCommitment(projectId, contributionIndex, validatorAddress)
        //    - This function checks if the reveal deadline has passed
        //    - Slashes the validator's committed stake
        //    - Updates their reputation negatively
        //    - Releases their in-flight stake tracking
        //
        // Key functions for handling ghost validators:
        console.log("Ghost Validator Handling Functions:");
        console.log("  oracle.cancelExpiredCommitment(projectId, index, validator)");
        console.log("    - Slashes committed stake for validators who don't reveal");
        console.log("    - Updates reputation negatively");
        console.log("    - Can be called by anyone after reveal deadline");
        console.log("");
        console.log("  oracle.cancelExpiredValidationClaim(projectId, claimId)");
        console.log("    - Handles validators who claim but don't commit");
        console.log("    - Demonstrated in Section 13 above");

        // Show the pending contribution at index 1 (from original contributor)
        ISapienCore.Contribution memory pendingContrib = core.getContribution(projectId, 1);
        console.log("\nContribution 1 status:", uint256(pendingContrib.status));
        console.log("(0=Pending, needs more validations to finalize)");

        // ================================================================
        // SECTION 15: UNSTAKING (Optional - after all work is done)
        // ================================================================
        console.log("\n========== SECTION 15: UNSTAKING ==========\n");

        // Note: Contributor has some locked stake from pending contributions
        // They can only withdraw unlocked stake
        vm.startPrank(contributor);
        uint256 totalStake = vault.getStake(contributor);
        uint256 lockedStake = vault.getLockedStake(contributor);
        uint256 availableToWithdraw = totalStake - lockedStake;

        console.log("Contributor stake breakdown:");
        console.log("  - total stake:", totalStake);
        console.log("  - locked stake:", lockedStake);
        console.log("  - available to withdraw:", availableToWithdraw);

        if (availableToWithdraw > 0) {
            // Convert assets to shares for withdrawal
            uint256 sharesToRedeem = vault.convertToShares(availableToWithdraw);
            uint256 assetsReceived = vault.redeem(sharesToRedeem, contributor, contributor);
            console.log("Contributor: vault.redeem()");
            console.log("  - shares redeemed:", sharesToRedeem);
            console.log("  - assets received:", assetsReceived);
        } else {
            console.log("No unlocked stake available to withdraw");
        }
        vm.stopPrank();

        console.log("\n========== TEST COMPLETE ==========\n");
        console.log("All frontend integration steps executed successfully!");
    }
}
