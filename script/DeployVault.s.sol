// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {SapienVault} from "src/SapienVault.sol";
import {SapienToken} from "src/SapienToken.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {Actors, AllActors} from "script/Actors.sol";

contract DeployVault is Script {
    function run() external {
        // Get necessary addresses
        AllActors memory actors = Actors.getAllActors();

        address tokenAddress = vm.envAddress("SAPIEN_TOKEN");
        address multiplierAddress = vm.envAddress("SAPIEN_MULTIPLIER");
        address qaAddress = vm.envAddress("SAPIEN_QA");

        vm.startBroadcast();

        // Deploy the implementation
        SapienVault vaultImpl = new SapienVault();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            ISapienVault.initialize.selector,
            tokenAddress,
            multiplierAddress,
            qaAddress,
            actors.foundationSafe1,
            actors.foundationSafe1 // treasury address, same as admin for now
        );

        // Deploy the proxy with initialization
        ERC1967Proxy vaultProxy = new ERC1967Proxy(address(vaultImpl), initData);

        console.log("Timelock:", vm.envAddress("SAPIEN_TIMELOCK"));
        console.log("SapienToken:", tokenAddress);
        console.log("Multiplier:", multiplierAddress);
        console.log("SapienQA:", qaAddress);
        console.log("Admin:", actors.foundationSafe1);
        console.log("Treasury:", actors.foundationSafe1);
        console.log("SapienVault implementation deployed at:", address(vaultImpl));
        console.log("Vault Proxy deployed at:", address(vaultProxy));
        console.log("ProxyAdmin at:", vm.envAddress("PROXY_ADMIN"));

        vm.stopBroadcast();
    }
}
