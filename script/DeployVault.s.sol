// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {TransparentUpgradeableProxy as TUP} from "src/utils/Common.sol";
import {SapienVault} from "src/SapienVault.sol";
import {SapienToken} from "src/SapienToken.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {Actors, AllActors} from "script/Actors.sol";
import {Contracts, DeployedContracts} from "script/Contracts.sol";

contract DeployVault is Script {
    function run() external {
        // Get necessary addresses
        AllActors memory actors = Actors.getAllActors();
        DeployedContracts memory contracts = Contracts.get();

        vm.startBroadcast();

        // Deploy the implementation
        SapienVault vaultImpl = new SapienVault();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            ISapienVault.initialize.selector,
            contracts.sapienToken,
            actors.securityCouncil,
            actors.rewardsSafe,
            contracts.multiplier,
            contracts.sapienQA
        );

        // NOTE: POST-DEPLOY,
        // 1. revoke default msg.sender from DEFAULT_ADMIN_ROLE after configured.
        // 2. grant DEFAULT_ADMIN_ROLE to timelock.
        // 3. grant SAPIEN_QA_ROLE to SapienQA contract.

        // Deploy the proxy with initialization
        TUP vaultProxy = new TUP(address(vaultImpl), contracts.timelock, initData);

        console.log("Timelock:", contracts.timelock);
        console.log("SapienToken:", contracts.sapienToken);
        console.log("Multiplier:", contracts.multiplier);
        console.log("SapienQA:", contracts.sapienQA);
        console.log("Admin:", actors.securityCouncil);
        console.log("Treasury:", actors.rewardsSafe);
        console.log("SapienVault implementation deployed at:", address(vaultImpl));
        console.log("Vault Proxy deployed at:", address(vaultProxy));

        vm.stopBroadcast();
    }
}
