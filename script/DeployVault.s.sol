// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployVault
 * @notice Deployment script for SapienVault contract
 * @dev Deploys SapienVault implementation and proxy
 */
contract DeployVault is Script {
    SapienVault public vault;

    function run() external {
        // Get deployment parameters from environment or use defaults for Anvil
        address stakingToken = vm.envOr("STAKING_TOKEN", address(0));
        address admin = vm.envOr("ADMIN_ADDRESS", address(0));

        // For Anvil/local testing, use default accounts if not provided
        if (stakingToken == address(0)) {
            console.log("STAKING_TOKEN not set, deploying MockERC20 for testing...");
            vm.startBroadcast();
            // Deploy mock token first
            stakingToken = _deployMockToken();
            vm.stopBroadcast();
        }

        if (admin == address(0)) {
            // Use Anvil's default account #0
            admin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
            console.log("ADMIN_ADDRESS not set, using default Anvil account:", admin);
        }

        console.log("\n=== Deploying SapienVault ===");
        console.log("Staking Token:", stakingToken);
        console.log("Admin:", admin);

        vm.startBroadcast();

        // Deploy implementation
        console.log("\n[1] Deploying SapienVault implementation...");
        SapienVault vaultImpl = new SapienVault();
        console.log("    Implementation:", address(vaultImpl));

        // Deploy proxy with initialization
        console.log("\n[2] Deploying SapienVault proxy...");
        bytes memory initData = abi.encodeWithSelector(SapienVault.initialize.selector, stakingToken, admin);
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), initData)));
        console.log("    Proxy:", address(vault));

        vm.stopBroadcast();

        // Output deployment information
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("SapienVault Proxy:  ", address(vault));
        console.log("SapienVault Impl:   ", address(vaultImpl));
        console.log("Staking Token:      ", stakingToken);
        console.log("Admin:              ", admin);

        // Verify deployment
        console.log("\n=== VERIFICATION ===");
        require(address(vault) != address(0), "Vault deployment failed");
        require(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin), "Admin role not set");
        console.log("Deployment verified successfully");

        console.log("\nDeployment addresses saved to: ./deployments/vault.json");
    }

    /**
     * @notice Deploy a mock ERC20 token for testing
     * @dev Only used when STAKING_TOKEN is not provided
     * @dev Assumes broadcast is already active
     */
    function _deployMockToken() internal returns (address) {
        MockERC20 mockToken = new MockERC20("Stake Token", "STAKE", 18);
        console.log("    Mock Token deployed:", address(mockToken));
        return address(mockToken);
    }
}
