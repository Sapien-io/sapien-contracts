// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Script, console} from "forge-std/Script.sol";
import {SapienVault} from "src/SapienVault.sol";

/// @title GrantEngineRole
/// @notice Print (or execute) `grantRole(ENGINE_ROLE, engine)` for the **Sepolia**
///         vault. The mainnet vault is refused — this script will not target it.
///
/// @dev Three modes, matching `UpgradeVault`:
///
///        1. Calldata (default) — print Safe calldata. Nothing is broadcast
///           to the proxy. Submit from the `DEFAULT_ADMIN_ROLE` Safe with
///           target = the Sepolia vault proxy.
///        2. Execute (`EXECUTE=true`) — broadcast `grantRole` from the
///           configured account (must hold `DEFAULT_ADMIN_ROLE`).
///        3. Verify (`VERIFY_ONLY=true`) — read-only. Asserts `engine` already
///           holds `ENGINE_ROLE` on the Sepolia vault.
///
///      Env:
///        SEPOLIA_ENGINE  - staging engine signer to grant (required)
///        VAULT_PROXY     - optional; defaults to the live Sepolia UUPS proxy
///        EXECUTE         - optional ("true"): broadcast the grant
///        VERIFY_ONLY     - optional ("true"): read-only role check
///
///      Run: see `script/README.md` / `make grant-engine-sepolia-calldata`.
contract GrantEngineRole is Script {
    /// @dev Live Base Sepolia proxy (`deployments/base-sepolia.json`).
    address internal constant SEPOLIA_VAULT = 0x58E72Fa7fb92B100f2c652377465EEEe2642544C;

    /// @dev Live Base mainnet proxy. Untouchable — this script reverts if aimed here.
    address internal constant MAINNET_VAULT = 0x60Bf63729f688287a450299962b36Cef0aFfaa42;

    /// @notice Print, execute, or verify the Sepolia `ENGINE_ROLE` grant.
    function run() external {
        address proxy = vm.envOr("VAULT_PROXY", SEPOLIA_VAULT);
        address engine = vm.envAddress("SEPOLIA_ENGINE");

        _requireSepolia(proxy);

        SapienVault vault = SapienVault(proxy);

        if (vm.envOr("VERIFY_ONLY", false)) {
            _verify(vault, engine);
            return;
        }

        bytes memory grantCalldata = abi.encodeCall(vault.grantRole, (vault.ENGINE_ROLE(), engine));

        bool execute = vm.envOr("EXECUTE", false);
        if (execute) {
            vm.startBroadcast();
            vault.grantRole(vault.ENGINE_ROLE(), engine);
            vm.stopBroadcast();
            _verify(vault, engine);
            return;
        }

        console.log("Network:           Base Sepolia (84532)");
        console.log("Vault proxy:       ", proxy);
        console.log("Engine signer:     ", engine);
        console.log("Submit this grantRole calldata from the admin Safe (target = proxy):");
        console.logBytes(grantCalldata);
    }

    /// @dev Refuse the mainnet vault and any proxy that is not the Sepolia UUPS.
    function _requireSepolia(address proxy) internal pure {
        require(proxy != MAINNET_VAULT, "GrantEngineRole: mainnet vault is untouchable");
        require(proxy == SEPOLIA_VAULT, "GrantEngineRole: VAULT_PROXY is not the Sepolia vault");
    }

    /// @dev Reverts if `engine` does not hold `ENGINE_ROLE` on `vault`.
    function _verify(SapienVault vault, address engine) internal view {
        require(address(vault) == SEPOLIA_VAULT, "verify: not the Sepolia vault");
        require(vault.hasRole(vault.ENGINE_ROLE(), engine), "verify: engine missing ENGINE_ROLE");
        console.log("ENGINE_ROLE verified on Sepolia vault:");
        console.log("  vault:  ", address(vault));
        console.log("  engine: ", engine);
    }
}
