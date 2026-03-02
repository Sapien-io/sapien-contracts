// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";

/// @title UpgradeBaseSepolia
/// @notice Two-step UUPS upgrade for Safe-administered proxies.
///
///     STEP 1 — Deploy the new implementation (any funded EOA):
///
///       forge script script/upgrade/UpgradeBaseSepolia.s.sol --sig "deployCore()" \
///         --rpc-url $RPC_URL --account $ACCOUNT --broadcast --verify -vvvv
///
///       forge script script/upgrade/UpgradeBaseSepolia.s.sol --sig "deployVault()" \
///         --rpc-url $RPC_URL --account $ACCOUNT --broadcast --verify -vvvv
///
///     STEP 2 — Execute via Safe:
///       The script prints the exact calldata. Create a new transaction in the
///       Safe UI (app.safe.global) with:
///         To:    <proxy address>
///         Value: 0
///         Data:  <calldata from step 1>
///       Collect signatures and execute.
///
///     Dry-run (omit --broadcast):
///       forge script script/upgrade/UpgradeBaseSepolia.s.sol --sig "deployCore()" \
///         --rpc-url $RPC_URL --account $ACCOUNT -vvvv
contract UpgradeBaseSepolia is Script {
    // ERC-1967 implementation slot: keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant _IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // ── Deployed addresses (from deployments/base-sepolia.json) ───────
    address constant CORE_PROXY = 0xDFFEc0D8F9DF05bf3DecbdFefD650779D6481077;
    address constant VAULT_PROXY = 0xf0E3C676b277Ce31C2E72Cd473684FA4C8866029;
    address constant SAFE_ADMIN = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;

    function _readImpl(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, _IMPL_SLOT))));
    }

    /// @notice Step 1: Deploy a new SapienCore implementation and print Safe calldata.
    function deployCore() external {
        address oldImpl = _readImpl(CORE_PROXY);
        bytes memory migrationData = vm.envOr("MIGRATION_DATA", bytes(""));

        console.log("=== SapienCore Upgrade ===");
        console.log("Proxy:              ", CORE_PROXY);
        console.log("Old implementation: ", oldImpl);
        console.log("Safe admin:         ", SAFE_ADMIN);
        console.log("");

        vm.startBroadcast();
        SapienCore newImpl = new SapienCore();
        vm.stopBroadcast();

        console.log("New implementation: ", address(newImpl));
        console.log("");

        bytes memory callData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newImpl), migrationData));

        _printSafeInstructions(CORE_PROXY, callData);
        _updateDeploymentJson("SapienCore_Implementation", address(newImpl));
    }

    /// @notice Step 1: Deploy a new SapienVault implementation and print Safe calldata.
    function deployVault() external {
        address oldImpl = _readImpl(VAULT_PROXY);
        bytes memory migrationData = vm.envOr("MIGRATION_DATA", bytes(""));

        console.log("=== SapienVault Upgrade ===");
        console.log("Proxy:              ", VAULT_PROXY);
        console.log("Old implementation: ", oldImpl);
        console.log("Safe admin:         ", SAFE_ADMIN);
        console.log("");

        vm.startBroadcast();
        SapienVault newImpl = new SapienVault();
        vm.stopBroadcast();

        console.log("New implementation: ", address(newImpl));
        console.log("");

        bytes memory callData = abi.encodeCall(UUPSUpgradeable.upgradeToAndCall, (address(newImpl), migrationData));

        _printSafeInstructions(VAULT_PROXY, callData);
        _updateDeploymentJson("SapienVault_Implementation", address(newImpl));
    }

    function _printSafeInstructions(address proxy, bytes memory callData) internal pure {
        console.log("============================================================");
        console.log("  SAFE TRANSACTION - paste into app.safe.global");
        console.log("============================================================");
        console.log("");
        console.log("  To:    ", proxy);
        console.log("  Value: 0");
        console.log("  Data:");
        console.logBytes(callData);
        console.log("");
        console.log("============================================================");
    }

    function _updateDeploymentJson(string memory key, address newImpl) internal {
        string memory path = "deployments/base-sepolia.json";
        string memory existing = vm.readFile(path);
        string memory obj = "deployment";

        vm.serializeJson(obj, existing);
        string memory json = vm.serializeAddress(obj, key, newImpl);
        vm.writeJson(json, path);
        console.log("Updated", path);
    }
}
