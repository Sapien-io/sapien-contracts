// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Deploy SapienVault to Base mainnet.
/// @dev Requires: SAPIEN_TOKEN, ADMIN (proxy admin, e.g. Safe). Use --account for deployer.
contract DeployBase is Script {
    function run() external returns (address vaultProxy) {
        address token = vm.envAddress("SAPIEN_TOKEN");
        address admin = vm.envAddress("ADMIN");

        vm.startBroadcast();

        SapienVault impl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(token), admin));
        vaultProxy = address(new ERC1967Proxy(address(impl), initData));

        vm.stopBroadcast();

        console.log("SapienVault impl:  ", address(impl));
        console.log("SapienVault proxy:", vaultProxy);
    }
}
