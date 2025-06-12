// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {ECDSA} from "src/utils/Common.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SapienRewards} from "src/SapienRewards.sol";
import {ISapienRewards} from "src/interfaces/ISapienRewards.sol";
import {Constants as Const} from "src/utils/Constants.sol";

contract SapienRewardsEndToEndTest is Test {
    using ECDSA for bytes32;

    // Core contracts
    SapienRewards public sapienRewards;
    MockERC20 public rewardToken;

    // Test accounts
    address public admin = makeAddr("admin");
    address public rewardsAdmin = makeAddr("rewardsAdmin");

    // User personas for comprehensive testing
    address public regularUser = makeAddr("regularUser"); // Standard user with regular claims
    address public heavyUser = makeAddr("heavyUser"); // High-volume user
    address public earlyUser = makeAddr("earlyUser"); // Early adopter
    address public irregularUser = makeAddr("irregularUser"); // Sporadic usage
    address public powerUser = makeAddr("powerUser"); // Maximum limit tester
    address public newUser = makeAddr("newUser"); // Late joiner

    // Reward managers with different permission levels
    uint256 public manager1PrivateKey = 0x1111111111111111111111111111111111111111111111111111111111111111;
    uint256 public manager2PrivateKey = 0x2222222222222222222222222222222222222222222222222222222222222222;
    uint256 public manager3PrivateKey = 0x3333333333333333333333333333333333333333333333333333333333333333;
    address public manager1 = vm.addr(manager1PrivateKey);
    address public manager2 = vm.addr(manager2PrivateKey);
    address public manager3 = vm.addr(manager3PrivateKey);

    // Test parameters
    uint256 public constant INITIAL_FUND = 50_000_000 * 10 ** 18; // 50M tokens
    uint256 public constant LARGE_REWARD = 100_000 * 10 ** 18; // 100K tokens
    uint256 public constant MEDIUM_REWARD = 25_000 * 10 ** 18; // 25K tokens
    uint256 public constant SMALL_REWARD = 1_000 * 10 ** 18; // 1K tokens
    uint256 public constant MICRO_REWARD = 100 * 10 ** 18; // 100 tokens

    // Tracking variables for comprehensive verification
    uint256 public totalClaimed;
    uint256 public totalDeposited;
    uint256 public totalWithdrawn;
    uint256 public orderCounter;

    function setUp() public {
        // Deploy reward token
        rewardToken = new MockERC20("Sapien Reward Token", "SRT", 18);

        // Deploy SapienRewards with proxy pattern
        SapienRewards sapienRewardsImpl = new SapienRewards();
        bytes memory initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            admin,
            rewardsAdmin,
            manager1,
            makeAddr("pauseManager"),
            address(rewardToken)
        );
        ERC1967Proxy sapienRewardsProxy = new ERC1967Proxy(address(sapienRewardsImpl), initData);
        sapienRewards = SapienRewards(address(sapienRewardsProxy));

        // Grant roles to additional managers
        vm.startPrank(admin);
        sapienRewards.grantRole(Const.REWARD_MANAGER_ROLE, manager2);
        sapienRewards.grantRole(Const.REWARD_MANAGER_ROLE, manager3);
        vm.stopPrank();

        // Setup initial funding
        rewardToken.mint(rewardsAdmin, INITIAL_FUND);
        vm.prank(rewardsAdmin);
        rewardToken.approve(address(sapienRewards), INITIAL_FUND);

        // Initial deposit
        vm.prank(rewardsAdmin);
        sapienRewards.depositRewards(INITIAL_FUND);
        totalDeposited = INITIAL_FUND;

        console.log("=== Setup Complete ===");
        console.log("Initial funding:", INITIAL_FUND / 10 ** 18, "tokens");
        console.log("Available rewards:", sapienRewards.getAvailableRewards() / 10 ** 18, "tokens");
    }

    // ============================================
    // COMPLETE END-TO-END USER JOURNEY TEST
    // ============================================

    function test_EndToEnd_CompleteUserJourney() public {
        console.log("\n=== COMPLETE END-TO-END USER JOURNEY ===");

        // Phase 1: Early adoption phase (Day 0-30)
        console.log("\n--- Phase 1: Early Adoption (Day 0-30) ---");
        _phaseEarlyAdoption();

        // Phase 2: Growth phase (Day 30-90)
        console.log("\n--- Phase 2: Growth Phase (Day 30-90) ---");
        _phaseGrowth();

        // Phase 3: Scale phase (Day 90-180)
        console.log("\n--- Phase 3: Scale Phase (Day 90-180) ---");
        _phaseScale();

        // Phase 4: Maturity phase (Day 180-365)
        console.log("\n--- Phase 4: Maturity Phase (Day 180-365) ---");
        _phaseMaturity();

        // Phase 5: Stress test phase (Day 365+)
        console.log("\n--- Phase 5: Stress Test Phase (Day 365+) ---");
        _phaseStressTest();

        // Phase 6: Emergency scenarios
        console.log("\n--- Phase 6: Emergency Scenarios ---");
        _phaseEmergencyScenarios();

        // Final verification
        _finalVerification();
    }

    function _phaseEarlyAdoption() internal {
        // Early user gets in first with a substantial reward
        bytes32 orderId = _generateOrderId("early_user_milestone_1");
        bytes memory signature = _createSignature(earlyUser, LARGE_REWARD, orderId, manager1PrivateKey);

        vm.prank(earlyUser);
        sapienRewards.claimReward(LARGE_REWARD, orderId, signature);
        totalClaimed += LARGE_REWARD;

        console.log("Early user claimed:", LARGE_REWARD / 10 ** 18, "tokens");

        // Regular user starts with smaller rewards
        orderId = _generateOrderId("regular_user_task_1");
        signature = _createSignature(regularUser, MEDIUM_REWARD, orderId, manager1PrivateKey);

        vm.prank(regularUser);
        sapienRewards.claimReward(MEDIUM_REWARD, orderId, signature);
        totalClaimed += MEDIUM_REWARD;

        // Advance time - simulate first month
        vm.warp(block.timestamp + 30 days);

        // Multiple small claims by different users
        for (uint256 i = 0; i < 5; i++) {
            address user = address(uint160(1000 + i));
            orderId = _generateOrderId(string(abi.encodePacked("batch_user_", i, "_task_1")));
            signature = _createSignature(user, SMALL_REWARD, orderId, manager2PrivateKey);

            vm.prank(user);
            sapienRewards.claimReward(SMALL_REWARD, orderId, signature);
            totalClaimed += SMALL_REWARD;
        }

        console.log("Phase 1 total claimed:", totalClaimed / 10 ** 18, "tokens");
        console.log("Remaining rewards:", sapienRewards.getAvailableRewards() / 10 ** 18, "tokens");
    }

    function _phaseGrowth() internal {
        // Heavy user emerges with consistent large claims
        for (uint256 i = 0; i < 3; i++) {
            bytes32 weekOrderId = _generateOrderId(string(abi.encodePacked("heavy_user_week_", i)));
            bytes memory weekSignature = _createSignature(heavyUser, LARGE_REWARD, weekOrderId, manager2PrivateKey);

            vm.prank(heavyUser);
            sapienRewards.claimReward(LARGE_REWARD, weekOrderId, weekSignature);
            totalClaimed += LARGE_REWARD;

            // Time progression
            vm.warp(block.timestamp + 1 weeks);
        }

        // Regular user continues with medium rewards
        for (uint256 i = 0; i < 4; i++) {
            bytes32 monthOrderId = _generateOrderId(string(abi.encodePacked("regular_user_month2_", i)));
            bytes memory monthSignature = _createSignature(regularUser, MEDIUM_REWARD, monthOrderId, manager1PrivateKey);

            vm.prank(regularUser);
            sapienRewards.claimReward(MEDIUM_REWARD, monthOrderId, monthSignature);
            totalClaimed += MEDIUM_REWARD;

            vm.warp(block.timestamp + 1 weeks);
        }

        // Irregular user makes sporadic claims
        bytes32 sporadicOrderId = _generateOrderId("irregular_user_sporadic_1");
        bytes memory sporadicSignature =
            _createSignature(irregularUser, SMALL_REWARD, sporadicOrderId, manager3PrivateKey);

        vm.prank(irregularUser);
        sapienRewards.claimReward(SMALL_REWARD, sporadicOrderId, sporadicSignature);
        totalClaimed += SMALL_REWARD;

        // Admin operations during growth phase
        uint256 withdrawAmount = 500_000 * 10 ** 18; // 500K withdrawal
        vm.prank(rewardsAdmin);
        sapienRewards.withdrawRewards(withdrawAmount);
        totalWithdrawn += withdrawAmount;

        console.log("Phase 2 total claimed:", totalClaimed / 10 ** 18, "tokens");
        console.log("Admin withdrew:", withdrawAmount / 10 ** 18, "tokens");
    }

    function _phaseScale() internal {
        // Add more funding due to high demand
        uint256 additionalFunding = 10_000_000 * 10 ** 18; // 10M tokens
        rewardToken.mint(rewardsAdmin, additionalFunding);
        vm.prank(rewardsAdmin);
        rewardToken.approve(address(sapienRewards), additionalFunding);

        vm.prank(rewardsAdmin);
        sapienRewards.depositRewards(additionalFunding);
        totalDeposited += additionalFunding;

        console.log("Additional funding added:", additionalFunding / 10 ** 18, "tokens");

        // Power user emerges, testing maximum limits
        bytes32 orderId = _generateOrderId("power_user_max_reward");
        uint256 maxAllowedReward = Const.MAX_REWARD_AMOUNT; // Maximum single claim
        bytes memory signature = _createSignature(powerUser, maxAllowedReward, orderId, manager1PrivateKey);

        vm.prank(powerUser);
        sapienRewards.claimReward(maxAllowedReward, orderId, signature);
        totalClaimed += maxAllowedReward;

        console.log("Power user claimed maximum:", maxAllowedReward / 10 ** 18, "tokens");

        // High-frequency claims simulation
        for (uint256 i = 0; i < 20; i++) {
            address user = address(uint160(2000 + i));
            orderId = _generateOrderId(string(abi.encodePacked("scale_user_", i)));
            signature = _createSignature(user, MEDIUM_REWARD, orderId, manager3PrivateKey);

            vm.prank(user);
            sapienRewards.claimReward(MEDIUM_REWARD, orderId, signature);
            totalClaimed += MEDIUM_REWARD;

            // Micro time advancement for realistic simulation
            vm.warp(block.timestamp + 1 hours);
        }

        // Late adopter joins with new user pattern
        orderId = _generateOrderId("new_user_onboarding");
        signature = _createSignature(newUser, SMALL_REWARD, orderId, manager2PrivateKey);

        vm.prank(newUser);
        sapienRewards.claimReward(SMALL_REWARD, orderId, signature);
        totalClaimed += SMALL_REWARD;

        console.log("Phase 3 total claimed:", totalClaimed / 10 ** 18, "tokens");
    }

    function _phaseMaturity() internal {
        // Simulate consistent ecosystem usage
        address[5] memory ecosystemUsers = [earlyUser, regularUser, heavyUser, powerUser, newUser];

        for (uint256 week = 0; week < 26; week++) {
            // 6 months
            for (uint256 u = 0; u < ecosystemUsers.length; u++) {
                address user = ecosystemUsers[u];
                uint256 rewardAmount = _getUserRewardPattern(user, week);

                if (rewardAmount > 0 && sapienRewards.getAvailableRewards() >= rewardAmount) {
                    bytes32 orderId = _generateOrderId(string(abi.encodePacked("maturity_", u, "_week_", week)));
                    uint256 managerKey = _getManagerKey(week % 3);
                    bytes memory signature = _createSignature(user, rewardAmount, orderId, managerKey);

                    vm.prank(user);
                    sapienRewards.claimReward(rewardAmount, orderId, signature);
                    totalClaimed += rewardAmount;
                }
            }

            // Weekly time advancement
            vm.warp(block.timestamp + 1 weeks);

            // Monthly admin operations
            if (week % 4 == 0) {
                _performAdminMaintenance();
            }
        }

        console.log("Phase 4 total claimed:", totalClaimed / 10 ** 18, "tokens");
        console.log("Remaining after maturity phase:", sapienRewards.getAvailableRewards() / 10 ** 18, "tokens");
    }

    function _phaseStressTest() internal {
        console.log("Starting stress test with rapid claims...");

        // Rapid-fire claims from multiple users
        for (uint256 i = 0; i < 50; i++) {
            address user = address(uint160(5000 + i));
            uint256 amount = (i % 3 == 0) ? LARGE_REWARD : (i % 2 == 0) ? MEDIUM_REWARD : SMALL_REWARD;

            if (sapienRewards.getAvailableRewards() >= amount) {
                bytes32 stressOrderId = _generateOrderId(string(abi.encodePacked("stress_", i)));
                uint256 managerKey = _getManagerKey(i % 3);
                bytes memory stressSignature = _createSignature(user, amount, stressOrderId, managerKey);

                vm.prank(user);
                sapienRewards.claimReward(amount, stressOrderId, stressSignature);
                totalClaimed += amount;
            }

            // Minimal time advancement for stress testing
            vm.warp(block.timestamp + 10 minutes);
        }

        console.log("Stress test completed. Claims processed: 50");
    }

    function _phaseEmergencyScenarios() internal {
        console.log("Testing emergency scenarios...");

        // Scenario 1: Emergency pause during high activity
        vm.prank(makeAddr("pauseManager"));
        sapienRewards.pause();

        // Verify claims are blocked
        bytes32 emergencyOrderId = _generateOrderId("emergency_blocked_claim");
        bytes memory emergencySignature =
            _createSignature(regularUser, SMALL_REWARD, emergencyOrderId, manager1PrivateKey);

        vm.prank(regularUser);
        vm.expectRevert();
        sapienRewards.claimReward(SMALL_REWARD, emergencyOrderId, emergencySignature);

        // Scenario 2: Accidental token transfer during pause
        uint256 accidentalAmount = 1_000_000 * 10 ** 18;
        rewardToken.mint(address(sapienRewards), accidentalAmount);

        // Scenario 3: Balance reconciliation while paused
        vm.prank(rewardsAdmin);
        sapienRewards.reconcileBalance();

        (uint256 available, uint256 total) = sapienRewards.getRewardTokenBalances();
        console.log("After reconciliation - Available:", available / 10 ** 18, "Total:", total / 10 ** 18);

        // Scenario 4: Recovery of excess tokens
        uint256 recoveryAmount = accidentalAmount / 2;
        vm.prank(rewardsAdmin);
        sapienRewards.withdrawRewards(recoveryAmount);
        totalWithdrawn += recoveryAmount;

        // Scenario 5: Resume operations
        vm.prank(makeAddr("pauseManager"));
        sapienRewards.unpause();

        // Verify normal operations resume
        bytes32 postEmergencyOrderId = _generateOrderId("post_emergency_claim");
        bytes memory postEmergencySignature =
            _createSignature(regularUser, SMALL_REWARD, postEmergencyOrderId, manager1PrivateKey);

        vm.prank(regularUser);
        bool success = sapienRewards.claimReward(SMALL_REWARD, postEmergencyOrderId, postEmergencySignature);
        assertTrue(success);
        totalClaimed += SMALL_REWARD;

        console.log("Emergency scenarios completed successfully");
    }

    function _finalVerification() internal view {
        console.log("\n=== FINAL VERIFICATION ===");

        // Balance verification
        (uint256 available, uint256 total) = sapienRewards.getRewardTokenBalances();
        console.log("Final available rewards:", available / 10 ** 18, "tokens");
        console.log("Total contract balance:", total / 10 ** 18, "tokens");
        console.log("Total claimed throughout test:", totalClaimed / 10 ** 18, "tokens");
        console.log("Total deposited:", totalDeposited / 10 ** 18, "tokens");
        console.log("Total withdrawn by admin:", totalWithdrawn / 10 ** 18, "tokens");

        // Mathematical verification
        uint256 expectedAvailable = totalDeposited - totalClaimed - totalWithdrawn;
        console.log("Expected available:", expectedAvailable / 10 ** 18, "tokens");

        // The available balance should match our calculation (with some tolerance for reconciliation)
        assertApproxEqAbs(available, expectedAvailable, 1_000_000 * 10 ** 18, "Final balance mismatch");

        // Verify contract state is consistent
        assertEq(available, sapienRewards.getAvailableRewards(), "Available rewards mismatch");
        assertGe(total, available, "Total balance should be >= available");

        // Verify no funds are stuck
        assertGt(total, 0, "Contract should have positive balance");

        console.log("All verifications passed successfully!");
        console.log("End-to-end test completed with", orderCounter, "total orders processed");
    }

    // ============================================
    // HELPER FUNCTIONS
    // ============================================

    function _generateOrderId(string memory identifier) internal returns (bytes32) {
        orderCounter++;
        return keccak256(abi.encodePacked(identifier, orderCounter, block.timestamp));
    }

    function _createSignature(address user, uint256 amount, bytes32 orderId, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 hash = sapienRewards.validateAndGetHashToSign(user, amount, orderId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _getUserRewardPattern(address user, uint256 week) internal view returns (uint256) {
        // Different user patterns based on persona
        if (user == regularUser) {
            return MEDIUM_REWARD; // Consistent medium rewards
        } else if (user == heavyUser) {
            return (week % 2 == 0) ? LARGE_REWARD : MEDIUM_REWARD; // High activity
        } else if (user == earlyUser) {
            return (week % 3 == 0) ? LARGE_REWARD : 0; // Sporadic large rewards
        } else if (user == powerUser) {
            return (week % 4 == 0) ? LARGE_REWARD * 2 : SMALL_REWARD; // Burst pattern
        } else if (user == newUser) {
            return SMALL_REWARD; // Consistent small rewards
        }
        return 0;
    }

    function _getManagerKey(uint256 index) internal view returns (uint256) {
        if (index == 0) return manager1PrivateKey;
        if (index == 1) return manager2PrivateKey;
        return manager3PrivateKey;
    }

    function _performAdminMaintenance() internal {
        // Simulate monthly maintenance operations
        if (sapienRewards.getAvailableRewards() < 1_000_000 * 10 ** 18) {
            // Add funding if running low
            uint256 topUpAmount = 5_000_000 * 10 ** 18;
            rewardToken.mint(rewardsAdmin, topUpAmount);
            vm.prank(rewardsAdmin);
            rewardToken.approve(address(sapienRewards), topUpAmount);
            vm.prank(rewardsAdmin);
            sapienRewards.depositRewards(topUpAmount);
            totalDeposited += topUpAmount;

            console.log("Admin topped up rewards:", topUpAmount / 10 ** 18, "tokens");
        }
    }

    // ============================================
    // EDGE CASE TESTS
    // ============================================

    function test_EndToEnd_EdgeCases() public {
        console.log("\n=== EDGE CASE TESTING ===");

        // Test maximum single claim
        bytes32 orderId = _generateOrderId("max_claim_test");
        bytes memory signature = _createSignature(powerUser, Const.MAX_REWARD_AMOUNT, orderId, manager1PrivateKey);

        vm.prank(powerUser);
        bool success = sapienRewards.claimReward(Const.MAX_REWARD_AMOUNT, orderId, signature);
        assertTrue(success);

        // Test claim exactly equal to available rewards (but respect max limit)
        uint256 remaining = sapienRewards.getAvailableRewards();
        uint256 claimAmount = remaining > Const.MAX_REWARD_AMOUNT ? Const.MAX_REWARD_AMOUNT : remaining;

        orderId = _generateOrderId("exact_remaining_claim");
        signature = _createSignature(regularUser, claimAmount, orderId, manager1PrivateKey);

        vm.prank(regularUser);
        success = sapienRewards.claimReward(claimAmount, orderId, signature);
        assertTrue(success);

        console.log("Edge case tests passed");
        console.log("Claimed amount:", claimAmount / 10 ** 18, "tokens");
        console.log("Remaining after edge cases:", sapienRewards.getAvailableRewards() / 10 ** 18, "tokens");
    }

    function test_EndToEnd_ErrorConditions() public {
        console.log("\n=== ERROR CONDITION TESTING ===");

        // First, exhaust most of the available rewards to create insufficient funds scenario
        uint256 largeWithdrawal = sapienRewards.getAvailableRewards() - (LARGE_REWARD / 2);
        vm.prank(rewardsAdmin);
        sapienRewards.withdrawRewards(largeWithdrawal);

        // Test claim with insufficient rewards - validation happens in validateAndGetHashToSign
        bytes32 orderId = _generateOrderId("insufficient_funds_test");
        vm.expectRevert(ISapienRewards.InsufficientAvailableRewards.selector);
        sapienRewards.validateAndGetHashToSign(regularUser, LARGE_REWARD, orderId);

        // Add back funds for duplicate order test
        uint256 additionalFunds = LARGE_REWARD * 2;
        rewardToken.mint(rewardsAdmin, additionalFunds);
        vm.prank(rewardsAdmin);
        rewardToken.approve(address(sapienRewards), additionalFunds);
        vm.prank(rewardsAdmin);
        sapienRewards.depositRewards(additionalFunds);

        // Create a valid order and use it
        bytes32 duplicateOrderId = _generateOrderId("duplicate_order_test");
        bytes memory duplicateSignature =
            _createSignature(regularUser, LARGE_REWARD, duplicateOrderId, manager1PrivateKey);

        vm.prank(regularUser);
        sapienRewards.claimReward(LARGE_REWARD, duplicateOrderId, duplicateSignature);

        // Attempt to use same order ID again
        vm.prank(regularUser);
        vm.expectRevert(ISapienRewards.OrderAlreadyUsed.selector);
        sapienRewards.claimReward(LARGE_REWARD, duplicateOrderId, duplicateSignature);

        // Test zero amount claim - validation happens in validateAndGetHashToSign
        bytes32 zeroAmountOrderId = _generateOrderId("zero_amount_test");
        vm.expectRevert(ISapienRewards.InvalidAmount.selector);
        sapienRewards.validateAndGetHashToSign(regularUser, 0, zeroAmountOrderId);

        // Test claim exceeding maximum allowed amount - validation happens in validateAndGetHashToSign
        // First ensure we have enough available rewards to trigger the max amount check
        uint256 excessiveAmount = Const.MAX_REWARD_AMOUNT + 1;
        uint256 currentAvailable = sapienRewards.getAvailableRewards();
        if (currentAvailable < excessiveAmount) {
            uint256 topUpForTest = excessiveAmount - currentAvailable + (1000 * 10 ** 18); // Extra buffer
            rewardToken.mint(rewardsAdmin, topUpForTest);
            vm.prank(rewardsAdmin);
            rewardToken.approve(address(sapienRewards), topUpForTest);
            vm.prank(rewardsAdmin);
            sapienRewards.depositRewards(topUpForTest);
        }

        bytes32 excessiveOrderId = _generateOrderId("excessive_amount_test");
        vm.expectRevert(
            abi.encodeWithSelector(
                ISapienRewards.RewardExceedsMaxAmount.selector, excessiveAmount, Const.MAX_REWARD_AMOUNT
            )
        );
        sapienRewards.validateAndGetHashToSign(regularUser, excessiveAmount, excessiveOrderId);

        console.log("Error condition tests passed");
    }

    function test_EndToEnd_MultiManagerCoordination() public {
        console.log("\n=== MULTI-MANAGER COORDINATION ===");

        uint256 testAmount = MEDIUM_REWARD;
        address testUser = regularUser;

        // Test all managers can sign valid rewards
        for (uint256 i = 0; i < 3; i++) {
            uint256 managerKey = _getManagerKey(i);
            bytes32 orderId = _generateOrderId(string(abi.encodePacked("manager_", i, "_test")));
            bytes memory signature = _createSignature(testUser, testAmount, orderId, managerKey);

            vm.prank(testUser);
            bool success = sapienRewards.claimReward(testAmount, orderId, signature);
            assertTrue(success);

            console.log("Manager", i + 1, "successfully processed reward");
        }

        console.log("Multi-manager coordination tests passed");
    }
}
