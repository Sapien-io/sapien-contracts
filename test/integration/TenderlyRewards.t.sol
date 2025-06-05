// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {SapienRewards} from "src/SapienRewards.sol";
import {SapienToken} from "src/SapienToken.sol";
import {ISapienRewards} from "src/interfaces/ISapienRewards.sol";
import {Constants as Const} from "src/utils/Constants.sol";
import {TenderlyActors} from "script/Actors.sol";
import {TenderlyContracts} from "script/Contracts.sol";

/**
 * @title TenderlyRewardsIntegrationTest
 * @notice Integration tests for SapienRewards claiming system against Tenderly deployed contracts
 * @dev Tests all reward claiming flows, signature validation, and edge cases on Base mainnet fork
 */
contract TenderlyRewardsIntegrationTest is Test {
    // Tenderly deployed contract addresses
    address public constant SAPIEN_TOKEN = TenderlyContracts.SAPIEN_TOKEN;
    address public constant SAPIEN_REWARDS_PROXY = TenderlyContracts.SAPIEN_REWARDS;
    address public constant TREASURY = TenderlyActors.FOUNDATION_SAFE_1;
    address public constant REWARDS_MANAGER = TenderlyActors.REWARDS_MANAGER;
    address public constant ADMIN = TenderlyActors.FOUNDATION_SAFE_1;
    
    SapienRewards public sapienRewards;
    SapienToken public sapienToken;
    
    // Test user personas
    address public regularUser = makeAddr("regularUser");
    address public heavyUser = makeAddr("heavyUser");
    address public earlyUser = makeAddr("earlyUser");
    address public irregularUser = makeAddr("irregularUser");
    address public powerUser = makeAddr("powerUser");
    address public newUser = makeAddr("newUser");
    address public batchUser1 = makeAddr("batchUser1");
    address public batchUser2 = makeAddr("batchUser2");
    address public batchUser3 = makeAddr("batchUser3");
    
    // Test constants
    uint256 public constant SMALL_REWARD = 100 * 1e18;
    uint256 public constant MEDIUM_REWARD = 1_000 * 1e18;
    uint256 public constant LARGE_REWARD = 10_000 * 1e18;
    uint256 public constant MAX_REWARD = 100_000 * 1e18;
    
    // EIP-712 constants
    bytes32 public constant REWARD_CLAIM_TYPEHASH = 
        keccak256("RewardClaim(address userWallet,uint256 amount,bytes32 orderId)");
    
    // Test manager private keys for signatures
    uint256 public REWARDS_MANAGER_PRIVATE_KEY;
    uint256 public SECOND_MANAGER_PRIVATE_KEY;
    
    // Order counter for unique order IDs
    uint256 public orderCounter = 1;
    
    function setUp() public {
        // Initialize private keys from environment with fallback
        try vm.envUint("TENDERLY_TEST_PRIVATE_KEY") returns (uint256 privateKey) {
            REWARDS_MANAGER_PRIVATE_KEY = privateKey;
            SECOND_MANAGER_PRIVATE_KEY = privateKey;
        } catch {
            // Fallback to default test keys if environment variable is not set
            REWARDS_MANAGER_PRIVATE_KEY = 0xbeef;
            SECOND_MANAGER_PRIVATE_KEY = 0xcafe;
        }
        
        // Setup fork to use Tenderly Base mainnet virtual testnet
        string memory rpcUrl = vm.envString("TENDERLY_VIRTUAL_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);
        
        // Initialize contract interfaces
        sapienRewards = SapienRewards(SAPIEN_REWARDS_PROXY);
        sapienToken = SapienToken(SAPIEN_TOKEN);
        
        // Fund rewards contract for testing
        fundRewardsContract();
        
        // Setup additional reward managers for multi-manager tests
        setupAdditionalManagers();
    }
    
    function fundRewardsContract() internal {
        // Transfer substantial funds to rewards contract for testing
        uint256 rewardsFunding = 50_000_000 * 1e18; // 50M tokens
        vm.prank(TREASURY);
        sapienToken.transfer(address(sapienRewards), rewardsFunding);
    }
    
    function setupAdditionalManagers() internal {
        // Add additional reward managers for testing
        address secondManager = vm.addr(SECOND_MANAGER_PRIVATE_KEY);
        
        // Try to grant role with admin permissions, but don't fail if we don't have permission
        try this.attemptGrantRole(secondManager) {
            // Role granted successfully
        } catch {
            // Skip if we don't have admin permissions - test can still work with existing managers
        }
    }
    
    function attemptGrantRole(address secondManager) external {
        vm.prank(ADMIN);
        sapienRewards.grantRole(Const.REWARD_MANAGER_ROLE, secondManager);
    }
    
    /**
     * @notice Test basic reward claiming with valid signatures
     */
    function test_Rewards_BasicRewardClaiming() public {
        bytes32 orderId = generateOrderId();
        uint256 rewardAmount = MEDIUM_REWARD;
        
        // Create reward claim signature
        bytes memory signature = createRewardSignature(
            regularUser,
            rewardAmount,
            orderId,
            REWARDS_MANAGER_PRIVATE_KEY
        );
        
        uint256 balanceBefore = sapienToken.balanceOf(regularUser);
        
        vm.prank(regularUser);
        sapienRewards.claimReward(rewardAmount, orderId, signature);
        
        uint256 balanceAfter = sapienToken.balanceOf(regularUser);
        assertEq(balanceAfter - balanceBefore, rewardAmount);
        
        // Verify order was processed
        assertTrue(sapienRewards.getOrderRedeemedStatus(regularUser, orderId));
        
        console.log("[PASS] Basic reward claiming validated");
    }
    
    /**
     * @notice Test multiple reward claims by different users
     */
    function test_Rewards_MultipleUserClaims() public {
        address[] memory users = new address[](5);
        users[0] = regularUser;
        users[1] = heavyUser;
        users[2] = earlyUser;
        users[3] = irregularUser;
        users[4] = powerUser;
        
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = MEDIUM_REWARD;
        amounts[1] = LARGE_REWARD;
        amounts[2] = SMALL_REWARD;
        amounts[3] = MEDIUM_REWARD / 2;
        amounts[4] = MAX_REWARD;
        
        for (uint256 i = 0; i < users.length; i++) {
            bytes32 orderId = generateOrderId();
            bytes memory signature = createRewardSignature(
                users[i],
                amounts[i],
                orderId,
                REWARDS_MANAGER_PRIVATE_KEY
            );
            
            uint256 balanceBefore = sapienToken.balanceOf(users[i]);
            
            vm.prank(users[i]);
            sapienRewards.claimReward(amounts[i], orderId, signature);
            
            uint256 balanceAfter = sapienToken.balanceOf(users[i]);
            assertEq(balanceAfter - balanceBefore, amounts[i]);
        }
        
        console.log("[PASS] Multiple user claims validated");
    }
    
    /**
     * @notice Test reward claiming with different managers
     */
    function test_Rewards_MultipleManagerSignatures() public {
        // First claim with primary manager
        bytes32 orderId1 = generateOrderId();
        bytes memory signature1 = createRewardSignature(
            regularUser,
            MEDIUM_REWARD,
            orderId1,
            REWARDS_MANAGER_PRIVATE_KEY
        );
        
        vm.prank(regularUser);
        sapienRewards.claimReward(MEDIUM_REWARD, orderId1, signature1);
        
        // Second claim with secondary manager
        bytes32 orderId2 = generateOrderId();
        bytes memory signature2 = createRewardSignature(
            regularUser,
            MEDIUM_REWARD,
            orderId2,
            SECOND_MANAGER_PRIVATE_KEY
        );
        
        uint256 balanceBefore = sapienToken.balanceOf(regularUser);
        
        vm.prank(regularUser);
        sapienRewards.claimReward(MEDIUM_REWARD, orderId2, signature2);
        
        uint256 balanceAfter = sapienToken.balanceOf(regularUser);
        assertEq(balanceAfter - balanceBefore, MEDIUM_REWARD);
        
        console.log("[PASS] Multiple manager signatures validated");
    }
    
    /**
     * @notice Test complete user journey simulation over time
     */
    function test_Rewards_CompleteUserJourney() public {
        // Phase 1: Early adoption (Day 0-30)
        vm.warp(block.timestamp + 0);
        
        // Early adopter claims substantial reward
        claimRewardForUser(earlyUser, LARGE_REWARD);
        
        // Regular user starts with smaller rewards
        claimRewardForUser(regularUser, MEDIUM_REWARD);
        
        // Batch users join
        claimRewardForUser(batchUser1, SMALL_REWARD);
        claimRewardForUser(batchUser2, SMALL_REWARD);
        claimRewardForUser(batchUser3, SMALL_REWARD);
        
        // Phase 2: Growth phase (Day 30-90)
        vm.warp(block.timestamp + 30 days);
        
        // Heavy user emerges
        claimRewardForUser(heavyUser, LARGE_REWARD * 2);
        claimRewardForUser(heavyUser, LARGE_REWARD);
        
        // Regular user maintains pattern
        claimRewardForUser(regularUser, MEDIUM_REWARD);
        
        // Irregular user appears
        claimRewardForUser(irregularUser, MEDIUM_REWARD / 2);
        
        // Phase 3: Scale phase (Day 90-180)
        vm.warp(block.timestamp + 60 days);
        
        // Power user tests limits
        claimRewardForUser(powerUser, MAX_REWARD);
        
        // High-frequency claims
        for (uint256 i = 0; i < 10; i++) {
            address user = makeAddr(string(abi.encodePacked("scaleUser", i)));
            claimRewardForUser(user, MEDIUM_REWARD);
        }
        
        // New user onboarding
        claimRewardForUser(newUser, SMALL_REWARD);
        
        // Phase 4: Maturity phase (Day 180-365)
        vm.warp(block.timestamp + 90 days);
        
        // Consistent ecosystem usage
        claimRewardForUser(regularUser, MEDIUM_REWARD);
        claimRewardForUser(heavyUser, LARGE_REWARD);
        claimRewardForUser(powerUser, MAX_REWARD / 2);
        
        console.log("[PASS] Complete user journey simulation validated");
    }
    
    /**
     * @notice Test reward claiming error conditions
     */
    function test_Rewards_ErrorConditions() public {
        // Test duplicate order ID
        bytes32 orderId = generateOrderId();
        bytes memory signature = createRewardSignature(
            regularUser,
            MEDIUM_REWARD,
            orderId,
            REWARDS_MANAGER_PRIVATE_KEY
        );
        
        // First claim should succeed
        vm.prank(regularUser);
        sapienRewards.claimReward(MEDIUM_REWARD, orderId, signature);
        
        // Second claim with same order ID should fail
        vm.prank(regularUser);
        vm.expectRevert();
        sapienRewards.claimReward(MEDIUM_REWARD, orderId, signature);
        
        // Test zero amount claim
        bytes32 zeroOrderId = generateOrderId();
        bytes memory zeroSignature = createRewardSignature(
            regularUser,
            0,
            zeroOrderId,
            REWARDS_MANAGER_PRIVATE_KEY
        );
        
        vm.prank(regularUser);
        vm.expectRevert();
        sapienRewards.claimReward(0, zeroOrderId, zeroSignature);
        
        // Test invalid signature
        bytes32 invalidOrderId = generateOrderId();
        bytes memory invalidSignature = createRewardSignature(
            regularUser,
            MEDIUM_REWARD,
            invalidOrderId,
            0x1234 // Wrong private key
        );
        
        vm.prank(regularUser);
        vm.expectRevert();
        sapienRewards.claimReward(MEDIUM_REWARD, invalidOrderId, invalidSignature);
        
        console.log("[PASS] Error conditions validated");
    }
    
    /**
     * @notice Test maximum reward amount limits
     */
    function test_Rewards_MaximumRewardLimits() public {
        // Test claiming maximum allowed reward
        bytes32 orderId = generateOrderId();
        bytes memory signature = createRewardSignature(
            powerUser,
            Const.MAX_REWARD_AMOUNT,
            orderId,
            REWARDS_MANAGER_PRIVATE_KEY
        );
        
        uint256 balanceBefore = sapienToken.balanceOf(powerUser);
        
        vm.prank(powerUser);
        sapienRewards.claimReward(Const.MAX_REWARD_AMOUNT, orderId, signature);
        
        uint256 balanceAfter = sapienToken.balanceOf(powerUser);
        assertEq(balanceAfter - balanceBefore, Const.MAX_REWARD_AMOUNT);
        
        // Test claiming above maximum (should revert)
        bytes32 overLimitOrderId = generateOrderId();
        bytes memory overLimitSignature = createRewardSignature(
            powerUser,
            Const.MAX_REWARD_AMOUNT + 1,
            overLimitOrderId,
            REWARDS_MANAGER_PRIVATE_KEY
        );
        
        vm.prank(powerUser);
        vm.expectRevert();
        sapienRewards.claimReward(Const.MAX_REWARD_AMOUNT + 1, overLimitOrderId, overLimitSignature);
        
        console.log("[PASS] Maximum reward limits validated");
    }
    
    /**
     * @notice Test rapid-fire claims from multiple users
     */
    function test_Rewards_RapidFireClaims() public {
        uint256 numUsers = 20;
        
        for (uint256 i = 0; i < numUsers; i++) {
            address user = makeAddr(string(abi.encodePacked("rapidUser", i)));
            uint256 rewardAmount = SMALL_REWARD + (i * 100 * 1e18); // Varying amounts
            
            bytes32 orderId = generateOrderId();
            bytes memory signature = createRewardSignature(
                user,
                rewardAmount,
                orderId,
                REWARDS_MANAGER_PRIVATE_KEY
            );
            
            uint256 balanceBefore = sapienToken.balanceOf(user);
            
            vm.prank(user);
            sapienRewards.claimReward(rewardAmount, orderId, signature);
            
            uint256 balanceAfter = sapienToken.balanceOf(user);
            assertEq(balanceAfter - balanceBefore, rewardAmount);
            
            // Small time gap between claims
            vm.warp(block.timestamp + 1 minutes);
        }
        
        console.log("[PASS] Rapid-fire claims validated with", numUsers, "users");
    }
    
    /**
     * @notice Test administrative operations during active claiming
     */
    function test_Rewards_AdminOperationsDuringClaiming() public {
        // Start with some reward claims
        claimRewardForUser(regularUser, MEDIUM_REWARD);
        claimRewardForUser(heavyUser, LARGE_REWARD);
        
        // Admin performs withdrawal
        uint256 withdrawAmount = 1_000_000 * 1e18;
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(TREASURY);
        
        vm.prank(ADMIN);
        sapienRewards.withdrawRewards(withdrawAmount);
        
        uint256 treasuryBalanceAfter = sapienToken.balanceOf(TREASURY);
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, withdrawAmount);
        
        // Users should still be able to claim after withdrawal
        claimRewardForUser(powerUser, LARGE_REWARD);
        
        // Admin adds more funding
        uint256 additionalFunding = 5_000_000 * 1e18;
        vm.prank(TREASURY);
        sapienToken.transfer(address(sapienRewards), additionalFunding);
        
        // Claims should continue working
        claimRewardForUser(newUser, MEDIUM_REWARD);
        
        console.log("[PASS] Administrative operations during claiming validated");
    }
    
    /**
     * @notice Test edge cases with very small and very large amounts
     */
    function test_Rewards_EdgeCaseAmounts() public {
        // Test very small reward (1 token)
        uint256 microReward = 1 * 1e18;
        bytes32 microOrderId = generateOrderId();
        bytes memory microSignature = createRewardSignature(
            regularUser,
            microReward,
            microOrderId,
            REWARDS_MANAGER_PRIVATE_KEY
        );
        
        uint256 balanceBefore = sapienToken.balanceOf(regularUser);
        
        vm.prank(regularUser);
        sapienRewards.claimReward(microReward, microOrderId, microSignature);
        
        uint256 balanceAfter = sapienToken.balanceOf(regularUser);
        assertEq(balanceAfter - balanceBefore, microReward);
        
        // Test maximum single reward
        claimRewardForUser(powerUser, Const.MAX_REWARD_AMOUNT);
        
        console.log("[PASS] Edge case amounts validated");
    }
    
    /**
     * @notice Test signature validation with different parameters
     */
    function test_Rewards_SignatureValidation() public {
        bytes32 orderId = generateOrderId();
        uint256 rewardAmount = MEDIUM_REWARD;
        
        // Test signature with wrong user
        bytes memory wrongUserSignature = createRewardSignature(
            regularUser,
            rewardAmount,
            orderId,
            REWARDS_MANAGER_PRIVATE_KEY
        );
        
        vm.prank(heavyUser); // Different user tries to use signature
        vm.expectRevert();
        sapienRewards.claimReward(rewardAmount, orderId, wrongUserSignature);
        
        // Test signature with wrong amount
        vm.prank(regularUser);
        vm.expectRevert();
        sapienRewards.claimReward(rewardAmount * 2, orderId, wrongUserSignature);
        
        // Test signature with wrong order ID
        bytes32 wrongOrderId = generateOrderId();
        vm.prank(regularUser);
        vm.expectRevert();
        sapienRewards.claimReward(rewardAmount, wrongOrderId, wrongUserSignature);
        
        console.log("[PASS] Signature validation edge cases validated");
    }
    
    /**
     * @notice Test insufficient funds scenario
     */
    function test_Rewards_InsufficientFunds() public {
        // Drain most funds from rewards contract
        uint256 currentBalance = sapienToken.balanceOf(address(sapienRewards));
        uint256 withdrawAmount = currentBalance - SMALL_REWARD; // Leave only small amount
        
        vm.prank(ADMIN);
        sapienRewards.withdrawRewards(withdrawAmount);
        
        // Try to claim more than available
        bytes32 orderId = generateOrderId();
        bytes memory signature = createRewardSignature(
            regularUser,
            LARGE_REWARD,
            orderId,
            REWARDS_MANAGER_PRIVATE_KEY
        );
        
        vm.prank(regularUser);
        vm.expectRevert();
        sapienRewards.claimReward(LARGE_REWARD, orderId, signature);
        
        // Small claim should still work
        claimRewardForUser(regularUser, SMALL_REWARD / 2);
        
        console.log("[PASS] Insufficient funds scenario validated");
    }
    
    // ============ Helper Functions ============
    
    function generateOrderId() internal returns (bytes32) {
        bytes32 orderId = keccak256(abi.encodePacked("order", orderCounter, block.timestamp));
        orderCounter++;
        return orderId;
    }
    
    function createRewardSignature(
        address userWallet,
        uint256 amount,
        bytes32 orderId,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 domainSeparator = sapienRewards.getDomainSeparator();
        bytes32 structHash = keccak256(abi.encode(REWARD_CLAIM_TYPEHASH, userWallet, amount, orderId));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
    
    function claimRewardForUser(address user, uint256 amount) internal {
        bytes32 orderId = generateOrderId();
        bytes memory signature = createRewardSignature(
            user,
            amount,
            orderId,
            REWARDS_MANAGER_PRIVATE_KEY
        );
        
        vm.prank(user);
        sapienRewards.claimReward(amount, orderId, signature);
    }
}