// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/// @notice ARCHIVED — DO NOT RUN (SEC-3).
/// @dev The Base mainnet vault is already deployed
///      (0x60Bf63729f688287a450299962b36Cef0aFfaa42; see
///      deployments/base-mainnet.json). This script hardcodes the token and the
///      admin key; running it with a stale admin would deploy a *second* vault
///      governed by the wrong key and overwrite deployments/base-mainnet.json.
///      The canonical, env-driven deploy path is script/DeployBase.s.sol
///      (SAPIEN_TOKEN + ADMIN env vars). Kept only as a historical record of
///      the original mainnet deployment parameters.
contract DeployBaseMainnet is Script {
    function run() external pure {
        revert("ARCHIVED: vault already deployed; use script/DeployBase.s.sol (see SEC-3)");
    }

    /// @dev Original deployment body, preserved for the historical record.
    function _originalRun() internal returns (address vaultProxy) {
        vm.startBroadcast();

        address token = 0xC729777d0470F30612B1564Fd96E8Dd26f5814E3;
        address admin = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;

        SapienVault impl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(token), admin));
        vaultProxy = address(new ERC1967Proxy(address(impl), initData));

        vm.stopBroadcast();

        console.log("SAPIEN token:", token);
        console.log("SapienVault impl:  ", address(impl));
        console.log("SapienVault proxy:", vaultProxy);
        console.log("Admin:", admin);

        // Serialize to JSON and write to deployments/base-mainnet.json
        string memory obj = "deployments";
        vm.serializeString(obj, "network", "base-mainnet");
        vm.serializeUint(obj, "chainId", block.chainid);
        vm.serializeAddress(obj, "sapienAddress", token);
        vm.serializeAddress(obj, "vaultAddress", vaultProxy);

        string memory json = vm.serializeUint(obj, "startBlock", block.number);
        string memory path = string.concat(vm.projectRoot(), "/deployments/base-mainnet.json");

        vm.writeJson(json, path);
    }
}
