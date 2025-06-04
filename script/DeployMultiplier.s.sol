// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Multiplier} from "src/Multiplier.sol";

contract DeployMultiplier is Script {
    function run() external {
        vm.startBroadcast();

        Multiplier multiplier = new Multiplier();
        console.log("Multiplier deployed at:", address(multiplier));

        vm.stopBroadcast();
    }
}
