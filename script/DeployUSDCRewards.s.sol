// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TransparentUpgradeableProxy as TUP} from "src/utils/Common.sol";
import {SapienRewards} from "src/SapienRewards.sol";
import {ISapienRewards} from "src/interfaces/ISapienRewards.sol";
import {Actors, AllActors, CoreActors} from "script/Actors.sol";
import {Contracts, DeployedContracts} from "script/Contracts.sol";

contract DeployUSDCRewards is Script {
    function run() external {
        // Get all actors from the deployed configuration
        AllActors memory actors = Actors.getAllActors();
        CoreActors memory coreActors = Actors.getActors();
        DeployedContracts memory contracts = Contracts.get();

        vm.startBroadcast();

        // Deploy the implementation
        SapienRewards rewardsImpl = new SapienRewards();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            ISapienRewards.initialize.selector,
            coreActors.securityCouncil, // default admin
            actors.rewardsAdmin, // rewards admin
            actors.rewardsManager, // rewards manager
            actors.pauser, // pauser
            contracts.usdcToken // newRewardToken
        );

        // NOTE: revoke default msg.sender from DEFAULT_ADMIN_ROLE after configured.

        // Deploy the proxy with initialization
        TUP rewardsProxy = new TUP(address(rewardsImpl), contracts.timelock, initData);

        console.log("USDC Rewards deployed at:", address(rewardsImpl));
        console.log("USDC Rewards proxy at:", address(rewardsProxy));
        console.log("Rewards Admin:", coreActors.sapienLabs);
        console.log("Rewards Manager:", actors.rewardsManager);
        console.log("Pauser:", actors.pauser);
        console.log("Rewards Token (USDC):", contracts.usdcToken);
        console.log("Timelock:", contracts.timelock);

        vm.stopBroadcast();
    }
}
