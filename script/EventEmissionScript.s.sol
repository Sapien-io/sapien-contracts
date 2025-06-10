// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SapienVault} from "src/SapienVault.sol";
import {SapienQA} from "src/SapienQA.sol";
import {SapienRewards} from "src/SapienRewards.sol";
import {SapienToken} from "src/SapienToken.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {ISapienQA} from "src/interfaces/ISapienQA.sol";
import {Constants as Const} from "src/utils/Constants.sol";
import {Contracts, DeployedContracts, LocalContracts} from "script/Contracts.sol";
import {Actors, AllActors} from "script/Actors.sol";

/**
 * @title EventEmissionScript
 * @notice Comprehensive script to emit all events in the Sapien ecosystem for indexer testing
 * @dev Runs multiple user journeys to trigger all event types:
 *      - ERC20 Transfer/Approval events
 *      - Staking events (stake, increase amount/lockup, unstake, early unstake)
 *      - Reward claiming events
 *      - QA penalty events
 *      - Administrative events
 */
contract EventEmissionScript is Script {
    // System accounts (using anvil default accounts)
    address public ADMIN;
    address public TREASURY;
    address public QA_MANAGER;
    address public QA_ADMIN;
    address public REWARDS_MANAGER;

    // Anvil default private keys (accounts 0-9)
    uint256 public constant ADMIN_PRIVATE_KEY = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a; // Account 2
    uint256 public constant TREASURY_PRIVATE_KEY = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6; // Account 3
    uint256 public constant QA_MANAGER_PRIVATE_KEY = 0x8b3a350cf5c34c9194ca85829a2df0ec3153be0318b5e2d3348e872092edffba; // Account 5
    uint256 public constant QA_ADMIN_PRIVATE_KEY = 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e; // Account 6
    uint256 public constant REWARDS_MANAGER_PRIVATE_KEY =
        0x47e179ec197488593b187f80a00eb0da91f1b9d0b13f8733639f19c30a34926a; // Account 4

    // User private keys for test accounts
    uint256 public constant USER1_PRIVATE_KEY = 0x92db14e403b83dfe3df233f83dfa3a0d7096f21ca9b0d6d6b8d88b2b4ec1564e; // Account 6
    uint256 public constant USER2_PRIVATE_KEY = 0x4bbbf85ce3377467afe5d46f804f221813b2bb87f24d81f60f1fcdbf7cbf4356; // Account 7
    uint256 public constant USER3_PRIVATE_KEY = 0xdbda1821b80551c9d65939329250298aa3472ba22feea921c0cf5d620ea67b97; // Account 8
    uint256 public constant USER4_PRIVATE_KEY = 0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6; // Account 9
    uint256 public constant USER5_PRIVATE_KEY = 0x8166f546bab6da521a8369cab06c5d2b9e46670292d85c875ee9ec20e84ffb61; // Account 10
    uint256 public constant USER6_PRIVATE_KEY = 0xea6c44ac03bff858b476bba40716402b03e41b8e97e276d1baec7c37d42484a0; // Account 11

    // Contract interfaces
    SapienToken public sapienToken;
    SapienVault public sapienVault;
    SapienQA public sapienQA;
    SapienRewards public sapienRewards;
    AllActors public actors;

    // Test users (using remaining anvil accounts)
    address public user1 = 0x976EA74026E726554dB657fA54763abd0C3a0aa9; // Account 6
    address public user2 = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955; // Account 7
    address public user3 = 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f; // Account 8
    address public user4 = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720; // Account 9
    address public user5 = address(10);
    address public user6 = address(11);

    // Test constants
    uint256 public constant INITIAL_USER_BALANCE = 1_000_000 * 1e18; // 1M tokens per user
    uint256 public constant SMALL_STAKE = 5_000 * 1e18;
    uint256 public constant MEDIUM_STAKE = 25_000 * 1e18;
    uint256 public constant LARGE_STAKE = 100_000 * 1e18;

    // EIP-712 setup for signatures
    bytes32 public constant REWARD_CLAIM_TYPEHASH =
        keccak256("RewardClaim(address userWallet,uint256 amount,bytes32 orderId)");
    bytes32 public constant QA_DECISION_TYPEHASH = keccak256(
        "QADecision(address userAddress,uint8 actionType,uint256 penaltyAmount,bytes32 decisionId,bytes32 reason)"
    );

    function run() public {
        console.log("====== Starting Event Emission Script ======");
        console.log("Chain ID:", block.chainid);
        require(block.chainid == 31337, "EventEmissionScript: Must run on Anvil (chain ID 31337)");

        actors = Actors.getAllActors();

        ADMIN = actors.securityCouncil;
        TREASURY = actors.rewardsSafe;
        QA_MANAGER = actors.qaManager;
        REWARDS_MANAGER = actors.rewardsManager;
        QA_ADMIN = actors.qaAdmin;

        // Setup contracts and users
        setupContracts();
        setupUsers();

        console.log("\n====== Emitting ERC20 Events ======");
        emitERC20Events();

        console.log("\n====== Emitting Staking Events ======");
        emitStakingEvents();

        console.log("\n====== Emitting Reward Events ======");
        emitRewardEvents();

        console.log("\n====== Emitting QA Events ======");
        emitQAEvents();

        console.log("\n====== Emitting Administrative Events ======");
        emitAdminEvents();

        console.log("\n====== Emitting Complex User Journey Events ======");
        emitComplexJourneyEvents();

        console.log("\n====== Event Emission Script Completed ======");
        console.log("All events have been emitted for indexer testing");
    }

    function setupContracts() internal {
        // Try to use existing deployed contracts first, deploy if they don't exist
        bool contractsExist = checkIfContractsExist();

        if (contractsExist) {
            console.log("Using existing deployed contracts");
            setupExistingContracts();
        } else {
            console.log("Deploying contracts for event emission");
            deployContracts();
        }

        console.log("Contracts setup completed:");
        console.log("  SapienToken:", address(sapienToken));
        console.log("  SapienVault:", address(sapienVault));
        console.log("  SapienQA:", address(sapienQA));
        console.log("  SapienRewards:", address(sapienRewards));
    }

    function checkIfContractsExist() internal view returns (bool) {
        return (
            LocalContracts.SAPIEN_TOKEN.code.length > 0 && LocalContracts.SAPIEN_VAULT.code.length > 0
                && LocalContracts.SAPIEN_QA.code.length > 0 && LocalContracts.SAPIEN_REWARDS.code.length > 0
                && LocalContracts.MULTIPLIER.code.length > 0
        );
    }

    function setupExistingContracts() internal {
        DeployedContracts memory deployedContracts = Contracts.get();

        sapienToken = SapienToken(deployedContracts.sapienToken);
        sapienVault = SapienVault(deployedContracts.sapienVault);
        sapienQA = SapienQA(deployedContracts.sapienQA);
        sapienRewards = SapienRewards(deployedContracts.sapienRewards);
    }

    function deployContracts() internal {
        vm.startBroadcast();

        // Deploy SapienToken first (it mints all tokens to TREASURY)
        sapienToken = new SapienToken(TREASURY);

        // Deploy SapienVault implementation and proxy
        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInitData =
            abi.encodeWithSelector(SapienVault.initialize.selector, address(sapienToken), ADMIN, TREASURY, QA_MANAGER);
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), vaultInitData);
        sapienVault = SapienVault(address(vaultProxy));

        // Deploy SapienQA
        sapienQA = new SapienQA(TREASURY, address(sapienVault), QA_MANAGER, ADMIN);

        // Deploy SapienRewards implementation and proxy
        SapienRewards rewardsImpl = new SapienRewards();
        bytes memory rewardsInitData = abi.encodeWithSelector(
            SapienRewards.initialize.selector, ADMIN, REWARDS_MANAGER, TREASURY, address(sapienToken)
        );
        ERC1967Proxy rewardsProxy = new ERC1967Proxy(address(rewardsImpl), rewardsInitData);
        sapienRewards = SapienRewards(address(rewardsProxy));

        vm.stopBroadcast();

        // Grant necessary roles using private key
        vm.startBroadcast(ADMIN_PRIVATE_KEY);
        sapienQA.grantRole(Const.QA_ADMIN_ROLE, QA_ADMIN);
        vm.stopBroadcast();
    }

    function setupUsers() internal {
        address[] memory users = new address[](6);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        users[3] = user4;
        users[4] = user5;
        users[5] = user6;

        // Debug treasury balance
        uint256 treasuryBalance = sapienToken.balanceOf(TREASURY);
        console.log("Treasury balance:", treasuryBalance);
        console.log("Treasury address:", TREASURY);
        console.log("Total supply:", sapienToken.totalSupply());

        // Find who actually has the tokens
        console.log("Token holder check:");
        console.log("  Address(0) balance:", sapienToken.balanceOf(address(0)));
        console.log("  Address(1) balance:", sapienToken.balanceOf(address(1)));
        console.log("  ADMIN balance:", sapienToken.balanceOf(ADMIN));
        console.log("  TREASURY balance:", sapienToken.balanceOf(TREASURY));

        // If treasury doesn't have tokens, find who does and transfer from them
        uint256 tokenHolderKey = TREASURY_PRIVATE_KEY;
        if (treasuryBalance == 0) {
            // Check common addresses and use corresponding private key
            if (sapienToken.balanceOf(address(1)) > 0) {
                tokenHolderKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d; // Account 1
                console.log("Found tokens in address(1)");
            } else if (sapienToken.balanceOf(ADMIN) > 0) {
                tokenHolderKey = ADMIN_PRIVATE_KEY;
                console.log("Found tokens in ADMIN");
            }
        }

        // Transfer tokens to test users from actual token holder
        vm.startBroadcast(tokenHolderKey);
        for (uint256 i = 0; i < users.length; i++) {
            sapienToken.transfer(users[i], INITIAL_USER_BALANCE);
        }

        // Fund rewards contract
        uint256 rewardsFunding = 10_000_000 * 1e18;
        sapienToken.approve(address(sapienRewards), rewardsFunding);
        sapienRewards.depositRewards(rewardsFunding);
        vm.stopBroadcast();

        console.log("Users setup completed with initial balances");
    }

    function emitERC20Events() internal {
        console.log("Emitting ERC20 Transfer and Approval events...");

        // Basic transfers between users
        vm.startBroadcast(USER1_PRIVATE_KEY);
        sapienToken.transfer(user2, 1000 * 1e18); // Transfer event
        sapienToken.approve(user3, 5000 * 1e18); // Approval event
        vm.stopBroadcast();

        // User 2 transfers to user 3
        vm.startBroadcast(USER2_PRIVATE_KEY);
        sapienToken.transfer(user3, 500 * 1e18);
        vm.stopBroadcast();

        // User 3 uses allowance from user 1
        vm.startBroadcast(USER3_PRIVATE_KEY);
        sapienToken.transferFrom(user1, user4, 2000 * 1e18); // TransferFrom event
        vm.stopBroadcast();

        console.log("ERC20 events emitted successfully");
    }

    function emitStakingEvents() internal {
        console.log("Emitting Staking events...");

        // User 1: Basic staking flow
        vm.startBroadcast(USER1_PRIVATE_KEY);
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(MEDIUM_STAKE, Const.LOCKUP_90_DAYS); // Staked event
        vm.stopBroadcast();

        // User 2: Stake with different lockup
        vm.startBroadcast(USER2_PRIVATE_KEY);
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(SMALL_STAKE, Const.LOCKUP_30_DAYS); // Staked event
        vm.stopBroadcast();

        // User 3: Stake and then increase amount
        vm.startBroadcast(USER3_PRIVATE_KEY);
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(SMALL_STAKE, Const.LOCKUP_180_DAYS); // Staked event
        sapienVault.increaseAmount(SMALL_STAKE); // AmountIncreased event
        vm.stopBroadcast();

        // User 4: Stake and then increase lockup
        vm.startBroadcast(USER4_PRIVATE_KEY);
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(MEDIUM_STAKE, Const.LOCKUP_30_DAYS); // Staked event
        sapienVault.increaseLockup(Const.LOCKUP_90_DAYS); // LockupIncreased event
        vm.stopBroadcast();

        // // User 5: Early unstake scenario
        // vm.startBroadcast(USER5_PRIVATE_KEY);
        // console.log("User 5 balance:", sapienToken.balanceOf(user5));
        // sapienToken.approve(address(sapienVault), LARGE_STAKE);
        // sapienVault.stake(SMALL_STAKE, Const.LOCKUP_180_DAYS); // Staked event
        // vm.warp(block.timestamp + 30 days); // Wait 30 days
        // sapienVault.earlyUnstake(SMALL_STAKE / 2); // EarlyUnstake event
        // vm.stopBroadcast();

        // // User 6: Demonstrating unstaking initiation (skip actual unstake to avoid timing issues)
        // vm.startBroadcast(USER6_PRIVATE_KEY);
        // sapienToken.approve(address(sapienVault), LARGE_STAKE);
        // sapienVault.stake(MEDIUM_STAKE, Const.LOCKUP_30_DAYS); // Staked event
        // // Note: In real scenarios, would wait 30+ days, then initiate unstake, then wait cooldown, then unstake
        // // For demo purposes, we'll just show the early unstake path to avoid complex timing
        // vm.warp(block.timestamp + 15 days); // Wait 15 days (still locked)
        // sapienVault.earlyUnstake(MEDIUM_STAKE / 4); // EarlyUnstake event (shows penalty mechanism)
        // vm.stopBroadcast();

        console.log("Staking events emitted successfully");
    }

    function emitRewardEvents() internal {
        console.log("Emitting Reward events...");

        // User 1: Claim reward
        bytes32 orderId1 = keccak256("reward_order_1");
        uint256 rewardAmount1 = 1000 * 1e18;
        bytes32 digest1 = createRewardClaimDigest(user1, rewardAmount1, orderId1);
        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(REWARDS_MANAGER_PRIVATE_KEY, digest1);
        bytes memory signature1 = abi.encodePacked(r1, s1, v1);

        vm.startBroadcast(USER1_PRIVATE_KEY);
        sapienRewards.claimReward(rewardAmount1, orderId1, signature1); // RewardClaimed event
        vm.stopBroadcast();

        // User 2: Claim larger reward
        bytes32 orderId2 = keccak256("reward_order_2");
        uint256 rewardAmount2 = 5000 * 1e18;
        bytes32 digest2 = createRewardClaimDigest(user2, rewardAmount2, orderId2);
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(REWARDS_MANAGER_PRIVATE_KEY, digest2);
        bytes memory signature2 = abi.encodePacked(r2, s2, v2);

        vm.startBroadcast(USER2_PRIVATE_KEY);
        sapienRewards.claimReward(rewardAmount2, orderId2, signature2); // RewardClaimed event
        vm.stopBroadcast();

        // User 3: Claim medium reward
        bytes32 orderId3 = keccak256("reward_order_3");
        uint256 rewardAmount3 = 2500 * 1e18;
        bytes32 digest3 = createRewardClaimDigest(user3, rewardAmount3, orderId3);
        (uint8 v3, bytes32 r3, bytes32 s3) = vm.sign(REWARDS_MANAGER_PRIVATE_KEY, digest3);
        bytes memory signature3 = abi.encodePacked(r3, s3, v3);

        vm.startBroadcast(USER3_PRIVATE_KEY);
        sapienRewards.claimReward(rewardAmount3, orderId3, signature3); // RewardClaimed event
        vm.stopBroadcast();

        console.log("Reward events emitted successfully");
    }

    function emitQAEvents() internal {
        console.log("Emitting QA events...");

        // Setup: User 4 needs a stake for penalty
        vm.startBroadcast(USER4_PRIVATE_KEY);
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(LARGE_STAKE, Const.LOCKUP_90_DAYS);
        vm.stopBroadcast();

        // Warning for user 4 (no penalty)
        bytes32 decisionId1 = keccak256("qa_warning_1");
        bytes32 digest4 = createQADecisionDigest(
            decisionId1,
            user4,
            0, // WARNING
            0, // No penalty for warning
            "Community guideline reminder"
        );
        (uint8 v4, bytes32 r4, bytes32 s4) = vm.sign(QA_ADMIN_PRIVATE_KEY, digest4);
        bytes memory signature4 = abi.encodePacked(r4, s4, v4);

        vm.startBroadcast(QA_MANAGER_PRIVATE_KEY);
        sapienQA.processQualityAssessment(
            user4, ISapienQA.QAActionType.WARNING, 0, decisionId1, "Community guideline reminder", signature4
        ); // QualityAssessmentProcessed event
        vm.stopBroadcast();

        // Minor penalty for user 5
        bytes32 decisionId2 = keccak256("qa_minor_penalty_1");
        uint256 penaltyAmount = 1000 * 1e18;
        bytes32 digest5 = createQADecisionDigest(
            decisionId2,
            user5,
            1, // MINOR_PENALTY
            penaltyAmount,
            "Minor rule violation"
        );
        (uint8 v5, bytes32 r5, bytes32 s5) = vm.sign(QA_ADMIN_PRIVATE_KEY, digest5);
        bytes memory signature5 = abi.encodePacked(r5, s5, v5);

        vm.startBroadcast(QA_MANAGER_PRIVATE_KEY);
        sapienQA.processQualityAssessment(
            user5, ISapienQA.QAActionType.MINOR_PENALTY, penaltyAmount, decisionId2, "Minor rule violation", signature5
        ); // QualityAssessmentProcessed + QAPenaltyProcessed events
        vm.stopBroadcast();

        console.log("QA events emitted successfully");
    }

    function emitAdminEvents() internal {
        console.log("Emitting Administrative events...");

        // Treasury update event
        address newTreasury = vm.addr(1234); // Random new treasury
        vm.startBroadcast(ADMIN_PRIVATE_KEY);
        sapienVault.setTreasury(newTreasury); // SapienTreasuryUpdated event
        vm.stopBroadcast();

        // Revert treasury back
        vm.startBroadcast(ADMIN_PRIVATE_KEY);
        sapienVault.setTreasury(TREASURY); // SapienTreasuryUpdated event
        vm.stopBroadcast();

        // Deposit more rewards using Treasury private key
        vm.startBroadcast(TREASURY_PRIVATE_KEY);
        sapienToken.approve(address(sapienRewards), 1_000_000 * 1e18);
        sapienRewards.depositRewards(1_000_000 * 1e18); // RewardsDeposited event
        vm.stopBroadcast();

        console.log("Administrative events emitted successfully");
    }

    function emitComplexJourneyEvents() internal {
        console.log("Emitting Complex User Journey events...");

        // Complex user journey with multiple event types
        uint256 complexUserKey = 0x829e924fdf021ba3dbbc4225edfece9aca04b929d6e75613329ca6f1d31c0bb4; // Random key
        address complexUser = vm.addr(complexUserKey);

        // Give user tokens using Treasury private key
        vm.startBroadcast(TREASURY_PRIVATE_KEY);
        sapienToken.transfer(complexUser, INITIAL_USER_BALANCE);
        vm.stopBroadcast();

        // User journey: stake -> claim reward -> increase stake -> partial early unstake
        vm.startBroadcast(complexUserKey);

        // 1. Initial stake
        sapienToken.approve(address(sapienVault), LARGE_STAKE * 2);
        sapienVault.stake(MEDIUM_STAKE, Const.LOCKUP_90_DAYS); // Staked event

        vm.stopBroadcast();

        // 2. Claim reward
        bytes32 complexOrderId = keccak256("complex_user_reward");
        uint256 complexRewardAmount = 3000 * 1e18;
        bytes32 complexDigest = createRewardClaimDigest(complexUser, complexRewardAmount, complexOrderId);
        (uint8 cV, bytes32 cR, bytes32 cS) = vm.sign(REWARDS_MANAGER_PRIVATE_KEY, complexDigest);
        bytes memory complexSignature = abi.encodePacked(cR, cS, cV);

        vm.startBroadcast(complexUserKey);
        sapienRewards.claimReward(complexRewardAmount, complexOrderId, complexSignature); // RewardClaimed event

        // 3. Increase stake amount
        sapienVault.increaseAmount(SMALL_STAKE); // AmountIncreased event

        // 4. Wait some time and early unstake part
        vm.warp(block.timestamp + 45 days);
        sapienVault.earlyUnstake(SMALL_STAKE); // EarlyUnstake event

        vm.stopBroadcast();

        console.log("Complex journey events emitted successfully");
    }

    // Helper function to create reward claim digest
    function createRewardClaimDigest(address userWallet, uint256 amount, bytes32 orderId)
        internal
        view
        returns (bytes32)
    {
        bytes32 domainSeparator = sapienRewards.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(REWARD_CLAIM_TYPEHASH, userWallet, amount, orderId));
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    // Helper function to create QA decision digest
    function createQADecisionDigest(
        bytes32 decisionId,
        address user,
        uint8 actionType,
        uint256 penaltyAmount,
        string memory reason
    ) internal view returns (bytes32) {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("SapienQA"),
                keccak256("1"),
                block.chainid,
                address(sapienQA)
            )
        );
        bytes32 structHash = keccak256(
            abi.encode(QA_DECISION_TYPEHASH, user, actionType, penaltyAmount, decisionId, keccak256(bytes(reason)))
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }
}
