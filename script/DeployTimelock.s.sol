// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {TimelockController as TC} from "src/utils/Common.sol";

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienRewards} from "src/SapienRewards.sol";

import {Actors} from "script/Actors.sol";

contract DeployTimelock is Script {
    function run() external {
        // TODO: Validate the actors
        (address FOUNDATION_SAFE_1, address FOUNDATION_SAFE_2, address SECURITY_COUNCIL,,) = Actors.get();

        vm.startBroadcast();

        address[] memory proposers = new address[](1);
        proposers[0] = FOUNDATION_SAFE_1;

        address[] memory executors = new address[](1);
        executors[0] = FOUNDATION_SAFE_2;

        TC timelock = new TC(48 hours, proposers, executors, SECURITY_COUNCIL);

        console.log("Timelock deployed at:", address(timelock));
        console.log("Proposer:", FOUNDATION_SAFE_1);
        console.log("Executor:", FOUNDATION_SAFE_2);
        console.log("Admin:", SECURITY_COUNCIL);
        vm.stopBroadcast();
    }
}
