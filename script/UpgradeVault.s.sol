// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {SapienVault} from "src/SapienVault.sol";

/// @notice Upgrade a live SapienVault proxy to the SAP-1 tranche implementation.
/// @dev Deploys the new implementation and prints the `upgradeToAndCall` calldata
///      that the `DEFAULT_ADMIN_ROLE` holder (the governance Safe) must execute
///      on the proxy. Per-user balances/ages migrate lazily on first touch, so
///      `initializeV2()` carries no migration payload.
///
///      Env:
///        VAULT_PROXY  - address of the ERC-1967 proxy to upgrade
///        EXECUTE      - optional ("true"): broadcast the upgrade directly,
///                       only valid when the broadcaster holds the admin role.
contract UpgradeVault is Script {
    function run() external returns (address newImpl) {
        address proxy = vm.envAddress("VAULT_PROXY");
        bool execute = vm.envOr("EXECUTE", false);

        vm.startBroadcast();
        newImpl = address(new SapienVault());

        bytes memory initData = abi.encodeCall(SapienVault.initializeV2, ());
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, initData);

        if (execute) {
            SapienVault(proxy).upgradeToAndCall(newImpl, initData);
        }
        vm.stopBroadcast();

        console.log("Proxy:            ", proxy);
        console.log("New implementation:", newImpl);
        console.log("Executed directly: ", execute);
        console.log("upgradeToAndCall calldata (submit from admin Safe if not executed):");
        console.logBytes(upgradeCalldata);
    }
}
