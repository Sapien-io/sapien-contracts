// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {TransparentUpgradeableProxy as TUP, TimelockController} from "src/utils/Common.sol";

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienVault} from "src/SapienVault.sol";
import {Multiplier} from "src/Multiplier.sol";
import {Actors} from "script/Actors.sol";

contract DeployVault is Script {
    function run() external {
        // TODO: Validate the actors
        (address ADMIN, address TREASURY,,,) = Actors.getActors();

        vm.startBroadcast();

        address TIMELOCK = vm.envAddress("TIMELOCK");
        if (TIMELOCK == address(0)) revert("TIMELOCK address not set in .env");
        console.log("Timelock:", TIMELOCK);

        address SAPIEN_TOKEN = vm.envAddress("SAPIEN_TOKEN");
        if (SAPIEN_TOKEN == address(0)) revert("SAPIEN_TOKEN address not set in .env");
        console.log("SapienToken:", SAPIEN_TOKEN);

        address MULTIPLIER = vm.envAddress("MULTIPLIER");
        if (MULTIPLIER == address(0)) revert("MULTIPLIER address not set in .env");
        console.log("Multiplier:", MULTIPLIER);

        SapienVault vaultImpl = new SapienVault();
        console.log("SapienVault implementation deployed at:", address(vaultImpl));

        Multiplier multiplier = new Multiplier();
        console.log("Multiplier implementation deployed at:", address(multiplier));

        bytes memory vaultInitData =
            abi.encodeWithSelector(SapienVault.initialize.selector, SAPIEN_TOKEN, ADMIN, TREASURY, MULTIPLIER);

        TUP vaultProxy = new TUP(address(vaultImpl), address(TIMELOCK), vaultInitData);
        console.log("Vault Proxy deployed at:", address(vaultProxy));

        vm.stopBroadcast();
    }
}
