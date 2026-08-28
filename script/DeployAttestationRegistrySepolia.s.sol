// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {stdJson} from "lib/forge-std/src/StdJson.sol";
import {SapienAttestationRegistry} from "src/SapienAttestationRegistry.sol";

/// @title DeployAttestationRegistrySepolia
/// @notice CREATE2-deploy `SapienAttestationRegistry` on Base Sepolia only.
/// @dev Does not touch `SapienVault`. Constructor args are fixed so the
///      predicted address is independent of the broadcasting EOA:
///        admin  = Sepolia Safe `0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC`
///        issuer = address(0)  — Safe grants `ISSUER_ROLE` after deploy
///        salt   = keccak256("sapien.attestation.registry.m4.base-sepolia")
///
///      Env:
///        BASE_SEPOLIA_RPC_URL — required for broadcast
///        DEPLOYER             — cast wallet account (broadcast)
///        WRITE_DEPLOYMENTS    — optional ("true"): update
///                               deployments/base-sepolia.json after deploy
contract DeployAttestationRegistrySepolia is Script {
    using stdJson for string;

    uint256 internal constant SEPOLIA_CHAIN_ID = 84532;
    address internal constant SEPOLIA_SAFE = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address internal constant SEPOLIA_VAULT = 0x58E72Fa7fb92B100f2c652377465EEEe2642544C;
    bytes32 internal constant SALT = keccak256("sapien.attestation.registry.m4.base-sepolia");

    /// @notice Print the CREATE2 address. Safe to run on any chain (no broadcast).
    function predict() external returns (address predicted) {
        predicted = _predicted();
        console.log("Predicted registry:", predicted);
        console.log("CREATE2 salt:      ", vm.toString(SALT));
        console.log("Admin (Safe):      ", SEPOLIA_SAFE);
        console.log("Vault (unchanged): ", SEPOLIA_VAULT);
    }

    function run() external returns (address registry) {
        require(block.chainid == SEPOLIA_CHAIN_ID, "DeployAttestationRegistry: not Base Sepolia");

        address predicted = _predicted();

        console.log("Predicted registry:", predicted);
        console.log("CREATE2 salt:      ", vm.toString(SALT));
        console.log("Admin (Safe):      ", SEPOLIA_SAFE);
        console.log("Vault (unchanged): ", SEPOLIA_VAULT);

        if (predicted.code.length > 0) {
            console.log("Already deployed; skipping CREATE2");
            registry = predicted;
        } else {
            vm.startBroadcast();
            SapienAttestationRegistry deployed = new SapienAttestationRegistry{salt: SALT}(SEPOLIA_SAFE, address(0));
            vm.stopBroadcast();
            registry = address(deployed);
            require(registry == predicted, "DeployAttestationRegistry: CREATE2 mismatch");
        }

        require(registry != SEPOLIA_VAULT, "DeployAttestationRegistry: must not be the vault");

        if (vm.envOr("WRITE_DEPLOYMENTS", false)) {
            _writeDeployments(registry);
        }
    }

    /// @dev Adds registry fields only. `vaultAddress` is re-asserted, never replaced.
    function _writeDeployments(address registry) internal {
        string memory path = "deployments/base-sepolia.json";
        string memory json = vm.readFile(path);
        address vault = json.readAddress(".vaultAddress");
        require(vault == SEPOLIA_VAULT, "DeployAttestationRegistry: vaultAddress drifted");

        vm.writeJson(vm.toString(registry), path, ".attestationRegistryAddress");
        vm.writeJson(vm.toString(SALT), path, ".attestationRegistrySalt");
        vm.writeJson(vm.toString(SEPOLIA_SAFE), path, ".attestationRegistryAdmin");

        console.log("Wrote", path);
    }

    function _predicted() internal view returns (address) {
        bytes memory initCode =
            abi.encodePacked(type(SapienAttestationRegistry).creationCode, abi.encode(SEPOLIA_SAFE, address(0)));
        return vm.computeCreate2Address(SALT, keccak256(initCode));
    }
}
