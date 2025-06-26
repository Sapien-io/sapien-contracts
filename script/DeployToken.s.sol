// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {SapienToken} from "src/SapienToken.sol";
import {Actors, CoreActors} from "script/Actors.sol";

contract DeployToken is Script {
    function run() external {
        // Get foundation safe address for token ownership
        CoreActors memory actors = Actors.getActors();

        vm.startBroadcast();

        SapienToken token = new SapienToken(actors.foundationSafe1);
        console.log("SapienToken deployed at:", address(token));

        vm.stopBroadcast();
    }
}
