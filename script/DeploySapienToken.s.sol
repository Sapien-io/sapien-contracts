// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {SapienToken} from "../src/SapienToken.sol";

contract DeploySapienToken is Script {
    // Network-specific treasury addresses
    mapping(uint256 => address) public treasuryAddresses;

    // Chain IDs
    uint256 constant LOCALHOST = 31337;
    uint256 constant BASE_MAINNET = 8453;
    uint256 constant BASE_SEPOLIA = 84532;

    function setUp() public {
        // Set treasury addresses for each network
        // For localhost, we'll use a deterministic address
        treasuryAddresses[LOCALHOST] = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Default Anvil account

        // For Base networks, set your actual multisig addresses
        // These should be replaced with actual multisig addresses before mainnet deployment
        treasuryAddresses[BASE_MAINNET] = 0x0000000000000000000000000000000000000000; // REPLACE WITH ACTUAL MULTISIG
        treasuryAddresses[BASE_SEPOLIA] = 0x0000000000000000000000000000000000000000; // REPLACE WITH ACTUAL MULTISIG
    }

    function run() external {
        uint256 chainId = block.chainid;
        address treasury = getTreasuryAddress(chainId);

        console.log("Deploying SapienToken to chain ID:", chainId);
        console.log("Treasury address:", treasury);

        // Validate treasury address
        require(treasury != address(0), "Treasury address not set for this chain");

        // Start broadcasting transactions
        vm.startBroadcast();

        // Deploy SapienToken
        SapienToken token = new SapienToken(treasury);

        vm.stopBroadcast();

        // Log deployment info
        console.log("SapienToken deployed at:", address(token));
        console.log("Token name:", token.name());
        console.log("Token symbol:", token.symbol());
        console.log("Total supply:", token.totalSupply());
        console.log("Max supply:", token.maxSupply());
        console.log("Treasury balance:", token.balanceOf(treasury));

        // Save deployment info to file
        saveDeploymentInfo(chainId, address(token), treasury);
    }

    function getTreasuryAddress(uint256 chainId) internal view returns (address) {
        address treasury = treasuryAddresses[chainId];

        // If not set in mapping, try environment variables
        if (treasury == address(0)) {
            if (chainId == BASE_MAINNET) {
                treasury = vm.envAddress("BASE_MAINNET_TREASURY");
            } else if (chainId == BASE_SEPOLIA) {
                treasury = vm.envAddress("BASE_SEPOLIA_TREASURY");
            } else if (chainId == LOCALHOST) {
                treasury = treasuryAddresses[LOCALHOST]; // Use default Anvil account
            }
        }

        return treasury;
    }

    function saveDeploymentInfo(uint256 chainId, address tokenAddress, address treasury) internal {
        string memory chainName = getChainName(chainId);

        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Network:", chainName);
        console.log("Chain ID:", chainId);
        console.log("SapienToken Address:", tokenAddress);
        console.log("Treasury Address:", treasury);
        console.log("Block Number:", block.number);
        console.log("Block Timestamp:", block.timestamp);
        console.log("==========================\n");

        // Create deployment JSON (for external tools)
        string memory json = string(
            abi.encodePacked(
                "{\n",
                '  "network": "',
                chainName,
                '",\n',
                '  "chainId": ',
                vm.toString(chainId),
                ",\n",
                '  "sapienToken": "',
                vm.toString(tokenAddress),
                '",\n',
                '  "treasury": "',
                vm.toString(treasury),
                '",\n',
                '  "blockNumber": ',
                vm.toString(block.number),
                ",\n",
                '  "timestamp": ',
                vm.toString(block.timestamp),
                "\n",
                "}"
            )
        );

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
        // Use the first Anvil account as treasury
        address treasury = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

        console.log("Deploying SapienToken to localhost (Anvil)");
        console.log("Treasury address:", treasury);

        vm.startBroadcast();

        SapienToken token = new SapienToken(treasury);

        vm.stopBroadcast();

        console.log("SapienToken deployed at:", address(token));
    }
}
