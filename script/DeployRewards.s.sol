// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TransparentUpgradeableProxy as TUP} from "src/utils/Common.sol";
import {SapienRewards} from "src/SapienRewards.sol";
import {ISapienRewards} from "src/interfaces/ISapienRewards.sol";
import {Actors, AllActors} from "script/Actors.sol";
import {Contracts, DeployedContracts} from "script/Contracts.sol";

contract DeployRewards is Script {
    function run() external {
        // Get all actors from the deployed configuration
        AllActors memory actors = Actors.getAllActors();
        DeployedContracts memory contracts = Contracts.get();

        vm.startBroadcast();

        console.log("Timelock:", contracts.timelock);
        console.log("SapienToken:", contracts.sapienToken);
        console.log("Multiplier:", contracts.multiplier);
        console.log("RewardsSafe:", actors.rewardsSafe);
        console.log("RewardsManager:", actors.rewardsManager);
        console.log("SecurityCouncil (Admin Role):", actors.securityCouncil);

        // Deploy the implementation
        SapienRewards rewardsImpl = new SapienRewards();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            ISapienRewards.initialize.selector,
            actors.securityCouncil, // admin
            actors.rewardsManager,
            actors.rewardsSafe,
            contracts.sapienToken // SAPIEN
        );

        // Deploy the proxy with initialization
        TUP rewardsProxy = new TUP(address(rewardsImpl), contracts.timelock, initData);

        console.log("SapienRewards deployed at:", address(rewardsImpl));
        console.log("Rewards Proxy deployed at:", address(rewardsProxy));

        vm.stopBroadcast();
    }
}
