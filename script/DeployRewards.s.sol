// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienRewards} from "src/SapienRewards.sol";
import {ISapienRewards} from "src/interfaces/ISapienRewards.sol";
import {Actors, AllActors} from "script/Actors.sol";

contract DeployRewards is Script {
    function run() external {
        // Get all actors from the deployed configuration
        AllActors memory actors = Actors.getAllActors();

        address multiplierAddress = vm.envAddress("SAPIEN_MULTIPLIER");

        vm.startBroadcast();

        console.log("Timelock:", vm.envAddress("SAPIEN_TIMELOCK"));
        console.log("SapienToken:", vm.envAddress("SAPIEN_TOKEN"));
        console.log("Multiplier:", multiplierAddress);
        console.log("RewardsSafe:", actors.rewardsSafe);
        console.log("RewardsManager:", actors.rewardsManager);
        console.log("SecurityCouncilSafe:", actors.securityCouncil);

        // Deploy the implementation
        SapienRewards rewardsImpl = new SapienRewards();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            ISapienRewards.initialize.selector,
            vm.envAddress("SAPIEN_TOKEN"),
            multiplierAddress,
            actors.rewardsSafe,
            actors.rewardsManager,
            actors.securityCouncil
        );

        // Deploy the proxy with initialization
        ERC1967Proxy rewardsProxy = new ERC1967Proxy(address(rewardsImpl), initData);

        console.log("SapienRewards deployed at:", address(rewardsImpl));
        console.log("Rewards Proxy deployed at:", address(rewardsProxy));
        console.log("ProxyAdmin at:", vm.envAddress("PROXY_ADMIN"));

        vm.stopBroadcast();
    }
}
