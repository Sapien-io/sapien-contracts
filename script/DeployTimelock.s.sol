// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {TimelockController as TC} from "src/utils/Common.sol";

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienRewards} from "src/SapienRewards.sol";

import {Actors, AllActors} from "script/Actors.sol";

contract DeployTimelock is Script {
    function run() external {
        // Get all actors from the deployed configuration
        AllActors memory actors = Actors.getAllActors();

        vm.startBroadcast();

        address[] memory proposers = new address[](1);
        proposers[0] = actors.timelockProposer;

        address[] memory executors = new address[](1);
        executors[0] = actors.timelockExecutor;

        TC timelock = new TC(48 hours, proposers, executors, actors.timelockAdmin);

        console.log("Timelock deployed at:", address(timelock));
        console.log("Proposer:", actors.timelockProposer);
        console.log("Executor:", actors.timelockExecutor);
        console.log("Admin:", actors.timelockAdmin);
        vm.stopBroadcast();
    }
}
