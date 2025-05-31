// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {ECDSA} from "src/utils/Common.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SapienRewards} from "src/SapienRewards.sol";
import {ISapienRewards} from "src/interfaces/ISapienRewards.sol";
import {Constants as Const} from "src/utils/Constants.sol";

contract SapienRewardsScenariosTest is Test {
    using ECDSA for bytes32;

    SapienRewards public sapienRewards;
    MockERC20 public rewardToken;
    MockERC20 public newRewardToken;

    // Test accounts
    address public admin = makeAddr("admin");
    address public rewardSafe = makeAddr("rewardSafe");

    // Multiple users for scenarios
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public diana = makeAddr("diana");
    address public eve = makeAddr("eve");

    // Reward managers
    uint256 public rewardManager1PrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 public rewardManager2PrivateKey = 0x2222222222222222222222222222222222222222222222222222222222222222;
    address public rewardManager1 = vm.addr(rewardManager1PrivateKey);
    address public rewardManager2 = vm.addr(rewardManager2PrivateKey);

    // Test constants
    uint256 public constant INITIAL_SUPPLY = 10000000 * 10 ** 18; // 10M tokens
    uint256 public constant LARGE_REWARD = 50000 * 10 ** 18; // 50K tokens
    uint256 public constant MEDIUM_REWARD = 10000 * 10 ** 18; // 10K tokens
    uint256 public constant SMALL_REWARD = 1000 * 10 ** 18; // 1K tokens

    // Order IDs for scenarios
    bytes32 public constant ALICE_ORDER_1 = keccak256("alice_contribution_1");
    bytes32 public constant ALICE_ORDER_2 = keccak256("alice_contribution_2");
    bytes32 public constant BOB_ORDER_1 = keccak256("bob_development_1");
    bytes32 public constant CHARLIE_ORDER_1 = keccak256("charlie_research_1");
    bytes32 public constant DIANA_ORDER_1 = keccak256("diana_community_1");
    bytes32 public constant EVE_ORDER_1 = keccak256("eve_marketing_1");

    function setUp() public {
        // Deploy reward tokens
        rewardToken = new MockERC20("Reward Token", "REWARD", 18);
        newRewardToken = new MockERC20("New Reward Token", "NEWREWARD", 18);

        // Deploy SapienRewards with proxy
        SapienRewards sapienRewardsImpl = new SapienRewards();
        bytes memory initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector, admin, rewardManager1, rewardSafe, address(rewardToken)
        );
        ERC1967Proxy sapienRewardsProxy = new ERC1967Proxy(address(sapienRewardsImpl), initData);
        sapienRewards = SapienRewards(address(sapienRewardsProxy));

        // Set up additional reward manager
        vm.prank(admin);
        sapienRewards.grantRole(Const.REWARD_MANAGER_ROLE, rewardManager2);

        // Mint tokens to reward safe
        rewardToken.mint(rewardSafe, INITIAL_SUPPLY);
        newRewardToken.mint(rewardSafe, INITIAL_SUPPLY);

        // Approve contract to spend tokens
        vm.prank(rewardSafe);
        rewardToken.approve(address(sapienRewards), INITIAL_SUPPLY);

        vm.prank(rewardSafe);
        newRewardToken.approve(address(sapienRewards), INITIAL_SUPPLY);
    }

    // ============================================
    // Complete Rewards Distribution Lifecycle
    // ============================================

    function test_Rewards_Scenario_CompleteRewardsLifecycle() public {
        console.log("=== Complete Rewards Distribution Lifecycle ===");

        // Phase 1: Initial setup and deposit
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(INITIAL_SUPPLY / 2); // Deposit 5M tokens

        uint256 totalDeposited = INITIAL_SUPPLY / 2;
        assertEq(sapienRewards.getAvailableRewards(), totalDeposited);
        console.log("Phase 1: Deposited", totalDeposited / 10 ** 18, "tokens");

        // Phase 2: Multiple users claim rewards over time
        uint256 totalClaimed = 0;

        // Alice claims large reward for major contribution
        bytes memory aliceSignature = _createSignature(alice, LARGE_REWARD, ALICE_ORDER_1, rewardManager1PrivateKey);
        vm.prank(alice);
        sapienRewards.claimReward(LARGE_REWARD, ALICE_ORDER_1, aliceSignature);
        totalClaimed += LARGE_REWARD;

        // Advance time and Bob claims medium reward
        vm.warp(block.timestamp + 1 days);
        bytes memory bobSignature = _createSignature(bob, MEDIUM_REWARD, BOB_ORDER_1, rewardManager2PrivateKey);
        vm.prank(bob);
        sapienRewards.claimReward(MEDIUM_REWARD, BOB_ORDER_1, bobSignature);
        totalClaimed += MEDIUM_REWARD;

        // Multiple small claims
        vm.warp(block.timestamp + 2 days);
        bytes memory charlieSignature =
            _createSignature(charlie, SMALL_REWARD, CHARLIE_ORDER_1, rewardManager1PrivateKey);
        vm.prank(charlie);
        sapienRewards.claimReward(SMALL_REWARD, CHARLIE_ORDER_1, charlieSignature);
        totalClaimed += SMALL_REWARD;

        console.log("Phase 2: Total claimed", totalClaimed / 10 ** 18, "tokens");

        // Phase 3: Partial withdrawal by admin
        uint256 withdrawAmount = 1000000 * 10 ** 18; // 1M tokens
        vm.prank(rewardSafe);
        sapienRewards.withdrawRewards(withdrawAmount);

        console.log("Phase 3: Withdrew", withdrawAmount / 10 ** 18, "tokens");

        // Phase 4: Additional deposit and more claims
        vm.warp(block.timestamp + 7 days);
        uint256 additionalDeposit = 2000000 * 10 ** 18; // 2M tokens
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(additionalDeposit);

        // Diana and Eve claim rewards
        bytes memory dianaSignature = _createSignature(diana, MEDIUM_REWARD, DIANA_ORDER_1, rewardManager2PrivateKey);
        vm.prank(diana);
        sapienRewards.claimReward(MEDIUM_REWARD, DIANA_ORDER_1, dianaSignature);

        bytes memory eveSignature = _createSignature(eve, SMALL_REWARD, EVE_ORDER_1, rewardManager1PrivateKey);
        vm.prank(eve);
        sapienRewards.claimReward(SMALL_REWARD, EVE_ORDER_1, eveSignature);

        totalClaimed += MEDIUM_REWARD + SMALL_REWARD;

        // Phase 5: Final state verification
        uint256 expectedRemaining = totalDeposited + additionalDeposit - withdrawAmount - totalClaimed;
        assertEq(sapienRewards.getAvailableRewards(), expectedRemaining);

        // Verify all users received their rewards
        assertEq(rewardToken.balanceOf(alice), LARGE_REWARD);
        assertEq(rewardToken.balanceOf(bob), MEDIUM_REWARD);
        assertEq(rewardToken.balanceOf(charlie), SMALL_REWARD);
        assertEq(rewardToken.balanceOf(diana), MEDIUM_REWARD);
        assertEq(rewardToken.balanceOf(eve), SMALL_REWARD);

        console.log("Phase 5: Lifecycle completed successfully");
        console.log("Final available rewards:", sapienRewards.getAvailableRewards() / 10 ** 18, "tokens");
    }

    // ============================================
    // High Volume Operations Scenario
    // ============================================

    function test_Rewards_Scenario_HighVolumeOperations() public {
        console.log("=== High Volume Operations Scenario ===");

        // Deposit large amount
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(INITIAL_SUPPLY);

        // Create many users and process many claims
        address[] memory users = new address[](20);
        uint256[] memory amounts = new uint256[](20);
        bytes32[] memory orderIds = new bytes32[](20);

        uint256 totalClaims = 0;

        for (uint256 i = 0; i < 20; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
            amounts[i] = (i + 1) * 5000 * 10 ** 18; // Varying amounts from 5K to 100K
            orderIds[i] = keccak256(abi.encodePacked("batch_order", i));

            // Alternate between reward managers
            uint256 managerKey = (i % 2 == 0) ? rewardManager1PrivateKey : rewardManager2PrivateKey;
            bytes memory signature = _createSignature(users[i], amounts[i], orderIds[i], managerKey);

            vm.prank(users[i]);
            sapienRewards.claimReward(amounts[i], orderIds[i], signature);

            totalClaims += amounts[i];

            // Verify order is marked as redeemed
            assertTrue(sapienRewards.getOrderRedeemedStatus(users[i], orderIds[i]));
        }

        console.log("Processed", users.length, "high-volume claims");
        console.log("Total claimed:", totalClaims / 10 ** 18, "tokens");

        // Verify final state
        assertEq(sapienRewards.getAvailableRewards(), INITIAL_SUPPLY - totalClaims);

        // Verify all users received correct amounts
        for (uint256 i = 0; i < users.length; i++) {
            assertEq(rewardToken.balanceOf(users[i]), amounts[i]);
        }
    }

    // ============================================
    // Emergency Recovery Scenario
    // ============================================

    function test_Rewards_Scenario_EmergencyRecoveryWorkflow() public {
        console.log("=== Emergency Recovery Workflow ===");

        // Phase 1: Normal operations
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(LARGE_REWARD * 4);

        // Some users claim rewards
        bytes memory aliceSignature = _createSignature(alice, LARGE_REWARD, ALICE_ORDER_1, rewardManager1PrivateKey);
        vm.prank(alice);
        sapienRewards.claimReward(LARGE_REWARD, ALICE_ORDER_1, aliceSignature);

        // Phase 2: Emergency pause
        console.log("Emergency detected - pausing contract");
        vm.prank(admin);
        sapienRewards.pause();

        // Verify claims are blocked when paused
        bytes memory bobSignature = _createSignature(bob, MEDIUM_REWARD, BOB_ORDER_1, rewardManager1PrivateKey);
        vm.prank(bob);
        vm.expectRevert();
        sapienRewards.claimReward(MEDIUM_REWARD, BOB_ORDER_1, bobSignature);

        // Phase 3: Someone accidentally sends tokens directly to contract
        uint256 accidentalTransfer = 100000 * 10 ** 18;
        rewardToken.mint(address(sapienRewards), accidentalTransfer);

        (uint256 available, uint256 total) = sapienRewards.getRewardTokenBalances();
        console.log("Available:", available / 10 ** 18, "Total:", total / 10 ** 18);
        assertEq(total - available, accidentalTransfer);

        // Phase 4: Recovery operations while paused
        // Reconcile balance to account for accidental transfer
        vm.prank(rewardSafe);
        sapienRewards.reconcileBalance();

        (available, total) = sapienRewards.getRewardTokenBalances();
        assertEq(available, total); // Now balanced

        // Phase 5: Partial recovery of excess tokens
        // The reconcileBalance() added the accidental transfer to available rewards
        // We need to recover from the available balance, not unaccounted balance
        uint256 recoveryAmount = accidentalTransfer / 2;
        vm.prank(rewardSafe);
        sapienRewards.withdrawRewards(recoveryAmount); // Use withdraw instead of recoverUnaccountedTokens

        // Phase 6: Resume operations
        console.log("Emergency resolved - resuming operations");
        vm.prank(admin);
        sapienRewards.unpause();

        // Verify claims work again
        vm.prank(bob);
        sapienRewards.claimReward(MEDIUM_REWARD, BOB_ORDER_1, bobSignature);

        assertEq(rewardToken.balanceOf(bob), MEDIUM_REWARD);
        console.log("Emergency recovery completed successfully");
    }

    // ============================================
    // Multi-Manager Coordination Scenario
    // ============================================

    function test_Rewards_Scenario_MultiManagerCoordination() public {
        console.log("=== Multi-Manager Coordination Scenario ===");

        // Setup large reward pool
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(INITIAL_SUPPLY / 2);

        // Manager 1 handles development rewards
        bytes memory devReward1 = _createSignature(alice, LARGE_REWARD, ALICE_ORDER_1, rewardManager1PrivateKey);
        bytes memory devReward2 = _createSignature(bob, MEDIUM_REWARD, BOB_ORDER_1, rewardManager1PrivateKey);

        // Manager 2 handles community rewards
        bytes memory communityReward1 =
            _createSignature(charlie, MEDIUM_REWARD, CHARLIE_ORDER_1, rewardManager2PrivateKey);
        bytes memory communityReward2 = _createSignature(diana, SMALL_REWARD, DIANA_ORDER_1, rewardManager2PrivateKey);

        // Verify hash generation works for both managers
        vm.prank(rewardManager1);
        bytes32 hash1 = sapienRewards.validateAndGetHashToSign(eve, SMALL_REWARD, EVE_ORDER_1);

        vm.prank(rewardManager2);
        bytes32 hash2 = sapienRewards.validateAndGetHashToSign(eve, SMALL_REWARD, EVE_ORDER_1);

        // Hashes should be the same (same parameters, different signers)
        assertEq(hash1, hash2);

        // Process claims from both managers
        vm.prank(alice);
        sapienRewards.claimReward(LARGE_REWARD, ALICE_ORDER_1, devReward1);

        vm.prank(bob);
        sapienRewards.claimReward(MEDIUM_REWARD, BOB_ORDER_1, devReward2);

        vm.prank(charlie);
        sapienRewards.claimReward(MEDIUM_REWARD, CHARLIE_ORDER_1, communityReward1);

        vm.prank(diana);
        sapienRewards.claimReward(SMALL_REWARD, DIANA_ORDER_1, communityReward2);

        // Verify all claims successful
        uint256 totalDistributed = LARGE_REWARD + MEDIUM_REWARD + MEDIUM_REWARD + SMALL_REWARD;
        assertEq(sapienRewards.getAvailableRewards(), (INITIAL_SUPPLY / 2) - totalDistributed);

        console.log("Multi-manager coordination successful");
        console.log("Total distributed:", totalDistributed / 10 ** 18, "tokens");
    }

    // ============================================
    // Stress Test: Maximum Concurrent Operations
    // ============================================

    function test_Rewards_Scenario_StressTestConcurrentOperations() public {
        console.log("=== Stress Test: Concurrent Operations ===");

        // Setup maximum reward pool
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(INITIAL_SUPPLY);

        uint256 iterations = 30; // Reduced for efficiency
        uint256 totalProcessed = 0;

        for (uint256 i = 0; i < iterations; i++) {
            address user = makeAddr(string(abi.encodePacked("stressUser", i)));
            uint256 amount = ((i % 10) + 1) * 1000 * 10 ** 18; // 1K to 10K tokens
            bytes32 orderId = keccak256(abi.encodePacked("stress_order", i));

            // Alternate operations
            if (i % 10 == 0) {
                // Every 10th iteration, do admin operations
                if (i % 20 == 0 && sapienRewards.getAvailableRewards() > LARGE_REWARD) {
                    // Withdraw some rewards
                    vm.prank(rewardSafe);
                    sapienRewards.withdrawRewards(SMALL_REWARD);
                } else {
                    // Deposit more rewards
                    rewardToken.mint(rewardSafe, SMALL_REWARD);
                    vm.prank(rewardSafe);
                    rewardToken.approve(address(sapienRewards), SMALL_REWARD);
                    vm.prank(rewardSafe);
                    sapienRewards.depositRewards(SMALL_REWARD);
                }
            } else {
                // Regular claim operations
                uint256 managerKey = (i % 3 == 0) ? rewardManager1PrivateKey : rewardManager2PrivateKey;
                bytes memory signature = _createSignature(user, amount, orderId, managerKey);

                vm.prank(user);
                sapienRewards.claimReward(amount, orderId, signature);

                totalProcessed += amount;
                assertEq(rewardToken.balanceOf(user), amount);
            }

            // Advance time slightly
            vm.warp(block.timestamp + 1 hours);
        }

        console.log("Stress test completed:");
        console.log("- Processed", iterations, "operations");
        console.log("- Total rewards claimed:", totalProcessed / 10 ** 18, "tokens");
        console.log("- Remaining rewards:", sapienRewards.getAvailableRewards() / 10 ** 18, "tokens");

        // Verify contract state is still consistent
        (uint256 available, uint256 total) = sapienRewards.getRewardTokenBalances();
        assertEq(available, sapienRewards.getAvailableRewards());
        assertGt(total, 0); // Ensure total balance is positive
    }

    // ============================================
    // Helper Functions
    // ============================================

    function _createSignature(address user, uint256 amount, bytes32 orderId, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(Const.REWARD_CLAIM_TYPEHASH, user, amount, orderId));
        bytes32 domainSeparator = sapienRewards.getDomainSeparator();
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }
}
