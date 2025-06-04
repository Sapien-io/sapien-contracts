// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {TransparentUpgradeableProxy as TUP, TimelockController} from "src/utils/Common.sol";

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienVault} from "src/SapienVault.sol";
import {Multiplier} from "src/Multiplier.sol";
import {Actors} from "script/Actors.sol";
import {Contracts} from "script/Contracts.sol";

contract DeployVault is Script {
    function run() external {
        // TODO: Validate the actors
        (address ADMIN, address TREASURY,,,,,,,,) = Actors.get();

        (address SAPIEN_TOKEN,,, address SAPIEN_QA, address MULTIPLIER, address TIMELOCK) = Contracts.get();

        vm.startBroadcast();

        console.log("Timelock:", TIMELOCK);
        console.log("SapienToken:", SAPIEN_TOKEN);
        console.log("Multiplier:", MULTIPLIER);
        console.log("SapienQA:", SAPIEN_QA);
        console.log("Admin:", ADMIN);
        console.log("Treasury:", TREASURY);

        SapienVault vaultImpl = new SapienVault();
        console.log("SapienVault implementation deployed at:", address(vaultImpl));

        bytes memory vaultInitData = abi.encodeWithSelector(
            SapienVault.initialize.selector, SAPIEN_TOKEN, ADMIN, TREASURY, MULTIPLIER, SAPIEN_QA
        );

        TUP vaultProxy = new TUP(address(vaultImpl), address(TIMELOCK), vaultInitData);
        console.log("Vault Proxy deployed at:", address(vaultProxy));

        vm.stopBroadcast();
    }
}
