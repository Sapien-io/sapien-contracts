// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {TransparentUpgradeableProxy as TUP, TimelockController} from "src/utils/Common.sol";

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienRewards} from "src/SapienRewards.sol";
import {Actors} from "script/Actors.sol";
import {Contracts} from "script/Contracts.sol";

contract DeployRewards is Script {
    function run() external {
        (,, address SECURITY_COUNCIL_SAFE, address REWARDS_SAFE, address REWARDS_MANAGER,,,,,) = Actors.get();

        (address SAPIEN_TOKEN,,,, address MULTIPLIER, address TIMELOCK) = Contracts.get();

        vm.startBroadcast();

        console.log("Timelock:", TIMELOCK);
        console.log("SapienToken:", SAPIEN_TOKEN);
        console.log("Multiplier:", MULTIPLIER);
        console.log("RewardsSafe:", REWARDS_SAFE);
        console.log("RewardsManager:", REWARDS_MANAGER);
        console.log("SecurityCouncilSafe:", SECURITY_COUNCIL_SAFE);

        SapienRewards rewardsImpl = new SapienRewards();
        console.log("SapienRewards deployed at:", address(rewardsImpl));

        bytes memory rewardsInitData = abi.encodeWithSelector(
            SapienRewards.initialize.selector, SECURITY_COUNCIL_SAFE, REWARDS_MANAGER, REWARDS_SAFE, SAPIEN_TOKEN
        );

        TUP rewardsProxy = new TUP(address(rewardsImpl), address(TIMELOCK), rewardsInitData);

        console.log("Rewards Proxy deployed at:", address(rewardsProxy));

        vm.stopBroadcast();
    }
}
