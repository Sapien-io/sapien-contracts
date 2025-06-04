// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Actors} from "script/Actors.sol";
import {Contracts} from "script/Contracts.sol";
import {SapienQA} from "src/SapienQA.sol";

contract DeployQA is Script {
    function run() external {
        (address FOUNDATION_SAFE_1,,,,, address QA_MANAGER, address QA_ADMIN,,,) = Actors.get();

        vm.startBroadcast();

        address _vaultContract = address(1); // call SapienQA.updateVaultContract() to set the vault contract

        SapienQA qa = new SapienQA(FOUNDATION_SAFE_1, _vaultContract, QA_MANAGER, QA_ADMIN);

        console.log("SapienQA deployed at:", address(qa));

        vm.stopBroadcast();
    }
}
