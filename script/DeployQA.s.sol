// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {SapienQA} from "src/SapienQA.sol";
import {Actors, AllActors, CoreActors} from "script/Actors.sol";
import {Contracts, DeployedContracts} from "script/Contracts.sol";
import {TransparentUpgradeableProxy as TUP} from "src/utils/Common.sol";

contract DeployQA is Script {
    function run() external {
        // Get necessary actors from the deployed configuration
        AllActors memory actors = Actors.getAllActors();
        CoreActors memory coreActors = Actors.getActors();
        DeployedContracts memory contracts = Contracts.get();

        vm.startBroadcast();

        // Deploy the implementation contract
        SapienQA qaImpl = new SapienQA();

        // The ProxyAdmin admin is the timelock contracts. All upgrades performed via timelock
        address timelock = contracts.timelock;

        // Create initialization data
        bytes memory initData = abi.encodeWithSelector(
            SapienQA.initialize.selector,
            coreActors.sapienLabs, // treasury
            address(1), // vaultContract (placeholder - update later)
            actors.qaManager, // qaManager
            actors.qaSigner, // qaSigner
            coreActors.sapienLabs // admin
        );

        // Deploy proxy
        TUP proxy = new TUP(address(qaImpl), address(timelock), initData);

        console.log("SapienQA implementation deployed at:", address(qaImpl));
        console.log("ProxyAdmin admin is timelock deployed at:", address(timelock));
        console.log("SapienQA proxy deployed at:", address(proxy));
        console.log("QA Manager:", actors.qaManager);
        console.log("QA Signer:", actors.qaSigner);
        console.log("Vault Contract (placeholder):", address(1));
        console.log("Admin:", coreActors.sapienLabs);
        console.log("Treasury:", coreActors.sapienLabs);
        vm.stopBroadcast();
    }
}
