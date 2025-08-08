// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {BatchRewards} from "src/BatchRewards.sol";
import {ISapienRewards} from "src/interfaces/ISapienRewards.sol";
import {Actors, AllActors} from "script/Actors.sol";
import {Contracts, DeployedContracts} from "script/Contracts.sol";

/**
 * @title DeployBatchRewards
 * @notice Script to deploy the BatchRewards contract
 * @dev This script deploys BatchRewards with the existing Sapien and USDC rewards contracts
 */
contract DeployBatchRewards is Script {
    /**
     * @notice Main deployment function
     * @dev Deploys BatchRewards contract with Sapien and USDC rewards contracts
     *      Set environment variables for custom addresses:
     *      - SAPIEN_REWARDS_ADDRESS: Override default Sapien rewards contract address
     *      - USDC_REWARDS_ADDRESS: Override default USDC rewards contract address
     */
    function run() external {
        // Get contract addresses from configuration
        DeployedContracts memory contracts = Contracts.get();

        // Get Sapien rewards address
        address sapienRewardsAddress = contracts.sapienRewards;
        address usdcRewardsAddress = contracts.usdcRewards;

        // Validate addresses
        require(sapienRewardsAddress != address(0), "DeployBatchRewards: Sapien rewards address cannot be zero");
        require(usdcRewardsAddress != address(0), "DeployBatchRewards: USDC rewards address cannot be zero");

        console.log("\n=== BATCH REWARDS DEPLOYMENT ===");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("Sapien Rewards:", sapienRewardsAddress);
        console.log("USDC Rewards:", usdcRewardsAddress);

        vm.startBroadcast();

        // Deploy BatchRewards contract
        BatchRewards batchRewards =
            new BatchRewards(ISapienRewards(sapienRewardsAddress), ISapienRewards(usdcRewardsAddress));

        vm.stopBroadcast();

        console.log("\n=== DEPLOYMENT SUCCESSFUL ===");
        console.log("BatchRewards deployed at:", address(batchRewards));
        console.log("Gas used: Approximately 500,000-700,000 gas");

        // Verify the deployment
        console.log("\n=== DEPLOYMENT VERIFICATION ===");
        console.log("BatchRewards.sapienRewards():", address(batchRewards.sapienRewards()));
        console.log("BatchRewards.usdcRewards():", address(batchRewards.usdcRewards()));

        // Post-deployment instructions
        console.log("\n=== POST-DEPLOYMENT ACTIONS REQUIRED ===");
        console.log("1. Grant BATCH_CLAIMER_ROLE to BatchRewards contract:");
        console.log("   - Sapien Rewards: Grant role to", address(batchRewards));
        console.log("   - USDC Rewards: Grant role to", address(batchRewards));
        console.log("2. Use the UpdateRole script to generate multisig transaction data:");
        console.log("   export TARGET_ADDRESS=", address(batchRewards));
        console.log("   export CONTRACT_ADDRESS=", sapienRewardsAddress);
        console.log("   make generate-role-tx");
        console.log("3. Repeat for USDC rewards contract:");
        console.log("   export CONTRACT_ADDRESS=", usdcRewardsAddress);
        console.log("   make generate-role-tx");

        // Output contract info for integration
        console.log("\n=== INTEGRATION INFO ===");
        console.log("Contract ABI includes:");
        console.log("- batchClaimRewards(uint256,bytes32,bytes,uint256,bytes32,bytes)");
        console.log("- sapienRewards() view returns (address)");
        console.log("- usdcRewards() view returns (address)");
    }

    // /**
    //  * @notice Helper function to check if addresses are valid rewards contracts
    //  * @dev Calls a simple view function to verify the contracts implement ISapienRewards
    //  */
    // function verifyRewardsContracts() external view {
    //     address sapienRewardsAddress;
    //     address usdcRewardsAddress;

    //     // Get addresses from env vars or defaults
    //     try vm.envAddress("SAPIEN_REWARDS_ADDRESS") returns (address addr) {
    //         sapienRewardsAddress = addr;
    //     } catch {
    //         DeployedContracts memory contracts = Contracts.get();
    //         sapienRewardsAddress = contracts.sapienRewards;
    //     }

    //     try vm.envAddress("USDC_REWARDS_ADDRESS") returns (address addr) {
    //         usdcRewardsAddress = addr;
    //     } catch {
    //         if (block.chainid == 84532) {
    //             usdcRewardsAddress = 0x798Fc8E87AfD496b8a16b436120cc6A456d3AC48;
    //         } else {
    //             revert("USDC_REWARDS_ADDRESS required");
    //         }
    //     }

    //     console.log("=== REWARDS CONTRACTS VERIFICATION ===");
    //     console.log("Sapien Rewards Address:", sapienRewardsAddress);
    //     console.log("USDC Rewards Address:", usdcRewardsAddress);

    //     // Try to call view functions to verify the contracts
    //     if (sapienRewardsAddress.code.length > 0) {
    //         console.log("[OK] Sapien Rewards contract has code");
    //         try ISapienRewards(sapienRewardsAddress).version() returns (string memory version) {
    //             console.log("Sapien Rewards version:", version);
    //         } catch {
    //             console.log("[WARN] Could not get Sapien Rewards version");
    //         }
    //     } else {
    //         console.log("[ERROR] Sapien Rewards contract has no code");
    //     }

    //     if (usdcRewardsAddress.code.length > 0) {
    //         console.log("[OK] USDC Rewards contract has code");
    //         try ISapienRewards(usdcRewardsAddress).version() returns (string memory version) {
    //             console.log("USDC Rewards version:", version);
    //         } catch {
    //             console.log("[WARN] Could not get USDC Rewards version");
    //         }
    //     } else {
    //         console.log("[ERROR] USDC Rewards contract has no code");
    //     }
    // }

    // /**
    //  * @notice Function to generate role update transaction data for both rewards contracts
    //  * @dev Calls the UpdateRole script functions to generate multisig transaction data
    //  */
    // function generateRoleUpdates() external view {
    //     address batchRewardsAddress = vm.envAddress("BATCH_REWARDS_ADDRESS");

    //     console.log("=== GENERATING ROLE UPDATE TRANSACTIONS ===");
    //     console.log("BatchRewards Address:", batchRewardsAddress);

    //     // Get contract addresses
    //     DeployedContracts memory contracts = Contracts.get();
    //     address usdcRewardsAddress;

    //     try vm.envAddress("USDC_REWARDS_ADDRESS") returns (address addr) {
    //         usdcRewardsAddress = addr;
    //     } catch {
    //         if (block.chainid == 84532) {
    //             usdcRewardsAddress = 0x798Fc8E87AfD496b8a16b436120cc6A456d3AC48;
    //         } else {
    //             revert("USDC_REWARDS_ADDRESS required");
    //         }
    //     }

    //     console.log("\n1. Grant BATCH_CLAIMER_ROLE on Sapien Rewards:");
    //     console.log("   To:", contracts.sapienRewards);
    //     console.log("   Function: grantRole(bytes32,address)");
    //     console.log("   Target Address:", batchRewardsAddress);

    //     console.log("\n2. Grant BATCH_CLAIMER_ROLE on USDC Rewards:");
    //     console.log("   To:", usdcRewardsAddress);
    //     console.log("   Function: grantRole(bytes32,address)");
    //     console.log("   Target Address:", batchRewardsAddress);

    //     console.log("\nNote: Use these in your multisig wallet to grant the necessary roles.");
    // }
}
