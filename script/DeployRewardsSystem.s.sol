// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import { Script } from "lib/forge-std/src/Script.sol";
import { console } from "lib/forge-std/src/console.sol";
import { StakingVault } from "src/StakingVault.sol";
import { RewardsDistributor } from "src/RewardsDistributor.sol";
import { ERC1967Proxy } from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployRewardsSystem is Script {
    // Configuration
    address public constant SAPIEN_TOKEN = 0x1234567890123456789012345678901234567890; // Replace with actual SAPIEN token address
    address public constant ADMIN_MULTISIG = 0x1234567890123456789012345678901234567890; // Replace with actual admin multisig
    address public constant TREASURY_MULTISIG = 0x1234567890123456789012345678901234567890; // Replace with actual treasury multisig
    
    // Base reward rate: 0.1 SAPIEN per second per 1 SAPIEN staked (scaled by 1e18)
    // This equals ~10% APY for 1x multiplier
    uint256 public constant BASE_REWARD_RATE = uint256(1e17) / uint256(365 days); // ~3.17e9 wei per second

    function run() external {
        vm.startBroadcast();

        // Deploy StakingVault implementation
        StakingVault stakingVaultImpl = new StakingVault();
        console.log("StakingVault implementation deployed at:", address(stakingVaultImpl));

        // Deploy StakingVault proxy
        bytes memory stakingInitData = abi.encodeWithSelector(
            StakingVault.initialize.selector,
            SAPIEN_TOKEN,
            ADMIN_MULTISIG,
            TREASURY_MULTISIG
        );
        
        ERC1967Proxy stakingVaultProxy = new ERC1967Proxy(
            address(stakingVaultImpl),
            stakingInitData
        );
        console.log("StakingVault proxy deployed at:", address(stakingVaultProxy));

        // Deploy RewardsDistributor implementation
        RewardsDistributor rewardsDistributorImpl = new RewardsDistributor();
        console.log("RewardsDistributor implementation deployed at:", address(rewardsDistributorImpl));

        // Deploy RewardsDistributor proxy
        bytes memory rewardsInitData = abi.encodeWithSelector(
            RewardsDistributor.initialize.selector,
            address(stakingVaultProxy),
            SAPIEN_TOKEN,
            ADMIN_MULTISIG,
            BASE_REWARD_RATE
        );
        
        ERC1967Proxy rewardsDistributorProxy = new ERC1967Proxy(
            address(rewardsDistributorImpl),
            rewardsInitData
        );
        console.log("RewardsDistributor proxy deployed at:", address(rewardsDistributorProxy));

        vm.stopBroadcast();
    }
} 