// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {SapienQA} from "src/SapienQA.sol";
import {Actors, AllActors} from "script/Actors.sol";

contract DeployQA is Script {
    function run() external {
        // Get necessary actors from the deployed configuration
        AllActors memory actors = Actors.getAllActors();

        vm.startBroadcast();

        // SapienQA constructor takes: treasury, vaultContract, qaManager, admin
        // We'll use a placeholder for vaultContract since it's deployed later
        // TODO: remove this from contructor, make better
        address vaultContract = address(1); // Placeholder - call updateVaultContract() later

        SapienQA qa = new SapienQA(
            actors.foundationSafe1, // treasury
            vaultContract, // vaultContract (placeholder)
            actors.qaManager, // qaManager
            actors.qaSigner // qaSigner
        );

        console.log("SapienQA deployed at:", address(qa));
        console.log("QA Manager:", actors.qaManager);
        console.log("QA Signer:", actors.qaSigner);
        console.log("Vault Contract:", vaultContract);
        vm.stopBroadcast();
    }
}
