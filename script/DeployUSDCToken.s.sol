// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

contract DeployUSDCToken is Script {
    function run() external {
        vm.startBroadcast();

        MockERC20 usdcToken = new MockERC20("USDC", "USDC", 6);
        console.log("USDC deployed at:", address(usdcToken));

        vm.stopBroadcast();
    }
}
