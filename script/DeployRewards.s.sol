// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {TransparentUpgradeableProxy as TUP, TimelockController} from "src/utils/Common.sol";

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienRewards} from "src/SapienRewards.sol";
import {Actors} from "script/Actors.sol";

contract DeployRewards is Script {
    function run() external {
        (,,, address REWARDS_SAFE, address REWARDS_MANAGER) = Actors.getActors();

        vm.startBroadcast();

        address TIMELOCK = vm.envAddress("TIMELOCK");
        if (TIMELOCK == address(0)) revert("TIMELOCK address not set in .env");
        console.log("Timelock:", TIMELOCK);

        address SAPIEN_TOKEN = vm.envAddress("SAPIEN_TOKEN");
        if (SAPIEN_TOKEN == address(0)) revert("SAPIEN_TOKEN address not set in .env");
        console.log("SapienToken:", SAPIEN_TOKEN);

        SapienRewards rewardsImpl = new SapienRewards();
        console.log("SapienRewards deployed at:", address(rewardsImpl));

        bytes memory rewardsInitData = abi.encodeWithSelector(
            SapienRewards.initialize.selector, TIMELOCK, REWARDS_MANAGER, REWARDS_SAFE, SAPIEN_TOKEN
        );

        TUP rewardsProxy = new TUP(address(rewardsImpl), address(TIMELOCK), rewardsInitData);

        console.log("Rewards Proxy deployed at:", address(rewardsProxy));

        vm.stopBroadcast();
    }
}
