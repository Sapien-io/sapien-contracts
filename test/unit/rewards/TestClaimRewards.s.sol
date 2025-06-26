// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SapienRewards} from "src/SapienRewards.sol";
import {Constants as Const} from "src/utils/Constants.sol";

contract TestClaimRewards is Script {
    // Localhost deployment addresses
    address constant SAPIEN_REWARDS_PROXY = 0x5FC8d32690cc91D4c39d9d3abcBD16989F875707;
    address constant SAPIEN_TOKEN = 0x5FbDB2315678afecb367f032d93F642f64180aa3;

    // Test accounts from localhost deployment
    address constant REWARDS_SAFE = 0x09F4897735f3Ec9Af6C2dda49d97D454B7dD1e59;
    address constant REWARDS_MANAGER = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;

    // Test user account (you can change this to any address you want)
    address constant TEST_USER = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;

    // Test parameters - you can modify these
    uint256 constant REWARD_AMOUNT = 100; // 1000 tokens
    bytes32 constant ORDER_ID = keccak256("test_order_1234");

    function run() external {
        // Get the rewards manager private key from environment
        uint256 rewardsManagerPrivateKey = vm.envUint("REWARDS_MANAGER_PRIVATE_KEY");

        // Verify the private key matches the expected rewards manager address
        address derivedAddress = vm.addr(rewardsManagerPrivateKey);
        require(derivedAddress == REWARDS_MANAGER, "Private key does not match rewards manager address");

        // Get contract instances
        SapienRewards sapienRewards = SapienRewards(SAPIEN_REWARDS_PROXY);
        IERC20 rewardToken = IERC20(SAPIEN_TOKEN);

        console.log("=== Testing Claim Rewards on Localhost ===");
        console.log("Rewards Contract:", address(sapienRewards));
        console.log("Reward Token:", address(rewardToken));
        console.log("Test User:", TEST_USER);
        console.log("Rewards Manager:", REWARDS_MANAGER);
        console.log("Derived Address from PK:", derivedAddress);
        console.log("Reward Amount:", REWARD_AMOUNT);
        console.log("Order ID:", vm.toString(ORDER_ID));

        // Step 1: Check initial balances
        console.log("\n=== Initial State ===");
        uint256 userBalanceBefore = rewardToken.balanceOf(TEST_USER);
        uint256 availableRewardsBefore = sapienRewards.getAvailableRewards();
        bool isOrderRedeemedBefore = sapienRewards.getOrderRedeemedStatus(TEST_USER, ORDER_ID);

        console.log("User balance before:", userBalanceBefore);
        console.log("Available rewards before:", availableRewardsBefore);
        console.log("Order redeemed before:", isOrderRedeemedBefore);

        // Step 2: Deposit rewards if needed (as rewards safe)
        console.log("\n=== Depositing Rewards ===");
        if (availableRewardsBefore < REWARD_AMOUNT) {
            uint256 depositAmount = REWARD_AMOUNT - availableRewardsBefore + (1000 * 10 ** 18); // Add extra buffer
            console.log("Need to deposit additional rewards:", depositAmount);

            // First check if rewards safe has enough balance
            uint256 rewardsSafeBalance = rewardToken.balanceOf(REWARDS_SAFE);
            console.log("Rewards safe balance:", rewardsSafeBalance);

            if (rewardsSafeBalance < depositAmount) {
                console.log("WARNING: Rewards safe has insufficient balance for deposit");
                console.log("Consider minting more tokens to the rewards safe first");
            }

            vm.startBroadcast(vm.envUint("PRIVATE_KEY")); // Should be rewards safe's private key
            sapienRewards.depositRewards(depositAmount);
            vm.stopBroadcast();

            uint256 availableRewardsAfterDeposit = sapienRewards.getAvailableRewards();
            console.log("Available rewards after deposit:", availableRewardsAfterDeposit);
        } else {
            console.log("Sufficient rewards already available, skipping deposit");
        }

        // Step 3: Create signature for claim
        console.log("\n=== Creating Signature ===");
        bytes32 hash = sapienRewards.validateAndGetHashToSign(TEST_USER, REWARD_AMOUNT, ORDER_ID);
        console.log("Hash to sign:", vm.toString(hash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(rewardsManagerPrivateKey, hash);
        bytes memory signature = abi.encodePacked(r, s, v);
        console.log("Signature created, length:", signature.length);

        // Step 4: Claim reward (as test user)
        console.log("\n=== Claiming Reward ===");
        vm.startBroadcast(vm.envUint("TEST_USER_PRIVATE_KEY")); // Use test user's private key

        bool success = sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);

        vm.stopBroadcast();

        // Step 5: Verify results
        console.log("\n=== Results ===");
        uint256 userBalanceAfter = rewardToken.balanceOf(TEST_USER);
        uint256 availableRewardsAfter = sapienRewards.getAvailableRewards();
        bool isOrderRedeemedAfter = sapienRewards.getOrderRedeemedStatus(TEST_USER, ORDER_ID);

        console.log("Claim success:", success);
        console.log("User balance after:", userBalanceAfter);
        console.log("Available rewards after:", availableRewardsAfter);
        console.log("Order redeemed after:", isOrderRedeemedAfter);
        console.log("Balance increase:", userBalanceAfter - userBalanceBefore);

        // Assertions
        require(success, "Claim should have succeeded");
        require(userBalanceAfter == userBalanceBefore + REWARD_AMOUNT, "User balance should increase by reward amount");
        require(isOrderRedeemedAfter, "Order should be marked as redeemed");
        require(availableRewardsAfter <= availableRewardsBefore, "Available rewards should decrease or stay same");

        console.log("\nAll assertions passed! Claim rewards test successful!");
    }

    // Helper function to check what address corresponds to a private key
    function checkPrivateKey() external view {
        uint256 pk = vm.envUint("REWARDS_MANAGER_PRIVATE_KEY");
        address addr = vm.addr(pk);
        console.log("Private key corresponds to address:", addr);
        console.log("Expected rewards manager address:", REWARDS_MANAGER);
        console.log("Match:", addr == REWARDS_MANAGER);
    }
}
