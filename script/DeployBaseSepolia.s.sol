// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice Deploy SapienVault to Base Sepolia.
/// @dev Testnet token and dev-team Safe are hardcoded below. Use --account for deployer.
contract DeployBaseSepolia is Script {
    function run() external returns (address vaultProxy) {
        address token = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6; // sapien token
        address admin = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC; // dev team safe

        vm.startBroadcast();

        SapienVault impl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(token), admin));
        vaultProxy = address(new ERC1967Proxy(address(impl), initData));

        vm.stopBroadcast();

        console.log("SapienVault impl:  ", address(impl));
        console.log("SapienVault proxy:", vaultProxy);
    }
}
