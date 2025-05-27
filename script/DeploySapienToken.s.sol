// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import { Script, console } from "forge-std/Script.sol";
import { SapienToken } from "../src/SapienToken.sol";

contract DeploySapienToken is Script {
    // Network-specific admin addresses
    mapping(uint256 => address) public adminAddresses;
    
    // Chain IDs
    uint256 constant LOCALHOST = 31337;
    uint256 constant BASE_MAINNET = 8453;
    uint256 constant BASE_SEPOLIA = 84532;
    
    function setUp() public {
        // Set admin addresses for each network
        // For localhost, we'll use a deterministic address
        adminAddresses[LOCALHOST] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Default Anvil account
        
        // For Base networks, set your actual multisig addresses
        // These should be replaced with actual multisig addresses before mainnet deployment
        adminAddresses[BASE_MAINNET] = 0x0000000000000000000000000000000000000000; // REPLACE WITH ACTUAL MULTISIG
        adminAddresses[BASE_SEPOLIA] = 0x0000000000000000000000000000000000000000; // REPLACE WITH ACTUAL MULTISIG
    }
    
    function run() external {
        uint256 chainId = block.chainid;
        address admin = getAdminAddress(chainId);
        
        console.log("Deploying SapienToken to chain ID:", chainId);
        console.log("Admin address:", admin);
        
        // Validate admin address
        require(admin != address(0), "Admin address not set for this chain");
        
        // Start broadcasting transactions
        vm.startBroadcast();
        
        // Deploy SapienToken
        SapienToken token = new SapienToken(admin);
        
        vm.stopBroadcast();
        
        // Log deployment info
        console.log("SapienToken deployed at:", address(token));
        console.log("Token name:", token.name());
        console.log("Token symbol:", token.symbol());
        console.log("Total supply:", token.totalSupply());
        console.log("Max supply:", token.maxSupply());
        console.log("Admin balance:", token.balanceOf(admin));
        console.log("Admin has DEFAULT_ADMIN_ROLE:", token.hasRole(0x00, admin));
        console.log("Admin has PAUSER_ROLE:", token.hasRole(token.PAUSER_ROLE(), admin));
        
        // Save deployment info to file
        saveDeploymentInfo(chainId, address(token), admin);
    }
    
    function getAdminAddress(uint256 chainId) internal view returns (address) {
        address admin = adminAddresses[chainId];
        
        // If not set in mapping, try environment variables
        if (admin == address(0)) {
            if (chainId == BASE_MAINNET) {
                admin = vm.envAddress("BASE_MAINNET_ADMIN");
            } else if (chainId == BASE_SEPOLIA) {
                admin = vm.envAddress("BASE_SEPOLIA_ADMIN");
            } else if (chainId == LOCALHOST) {
                admin = adminAddresses[LOCALHOST]; // Use default Anvil account
            }
        }
        
        return admin;
    }
    
    function saveDeploymentInfo(uint256 chainId, address tokenAddress, address admin) internal {
        string memory chainName = getChainName(chainId);
        
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Network:", chainName);
        console.log("Chain ID:", chainId);
        console.log("SapienToken Address:", tokenAddress);
        console.log("Admin Address:", admin);
        console.log("Block Number:", block.number);
        console.log("Block Timestamp:", block.timestamp);
        console.log("==========================\n");
        
        // Create deployment JSON (for external tools)
        string memory json = string(abi.encodePacked(
            '{\n',
            '  "network": "', chainName, '",\n',
            '  "chainId": ', vm.toString(chainId), ',\n',
            '  "sapienToken": "', vm.toString(tokenAddress), '",\n',
            '  "admin": "', vm.toString(admin), '",\n',
            '  "blockNumber": ', vm.toString(block.number), ',\n',
            '  "timestamp": ', vm.toString(block.timestamp), '\n',
            '}'
        ));
        
        // Use absolute path for better reliability
        string memory filename = string(abi.encodePacked("./deployments/", chainName, ".json"));
        
        // Try to write the file and handle potential errors
        try vm.writeFile(filename, json) {
            console.log("Deployment info saved to:", filename);
        } catch {
            console.log("WARNING: Could not save deployment file to:", filename);
            console.log("This might be due to file permissions or path issues.");
            console.log("Manual deployment record (copy this to deployments/", chainName, ".json):");
            console.log(json);
        }
    }
    
    function getChainName(uint256 chainId) internal pure returns (string memory) {
        if (chainId == LOCALHOST) return "localhost";
        if (chainId == BASE_MAINNET) return "base";
        if (chainId == BASE_SEPOLIA) return "base-sepolia";
        return "unknown";
    }
}

// Separate script for localhost deployment with additional setup
contract DeployLocalhostSapienToken is Script {
    function run() external {
        // Use the first Anvil account as admin
        address admin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
        
        console.log("Deploying SapienToken to localhost (Anvil)");
        console.log("Admin address:", admin);
        
        vm.startBroadcast();
        
        SapienToken token = new SapienToken(admin);
        
        vm.stopBroadcast();
        
        console.log("SapienToken deployed at:", address(token));
    }
} 