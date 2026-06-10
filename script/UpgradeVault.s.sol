// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";
import {SapienVault} from "src/SapienVault.sol";

/// @title UpgradeVault
/// @notice Upgrade helper for a live SapienVault ERC-1967 (UUPS) proxy.
/// @dev Three modes, selected by env flags:
///
///        1. Calldata (default) — deploy the new implementation and print the
///           `upgradeToAndCall(newImpl, initializeV2(admin))` calldata for the
///           `DEFAULT_ADMIN_ROLE` holder (governance Safe) to execute. Nothing
///           is broadcast to the proxy.
///        2. Execute (`EXECUTE=true`) — additionally broadcast the upgrade from
///           the configured account. Only valid when that account holds the
///           admin role; runs post-upgrade verification before returning.
///        3. Verify (`VERIFY_ONLY=true`) — read-only. Deploys nothing; asserts
///           the proxy is already in the expected post-upgrade state. Use this
///           after the Safe executes the calldata from mode 1.
///
///      `initializeV2(admin)` seeds the `AccessControlDefaultAdminRules` storage
///      to the existing admin (which must already hold the role) and the SAP-5
///      `minDepositAge` default. Per-user balances/ages migrate lazily on first
///      touch, so there is no batch migration payload.
///
///      Env:
///        VAULT_PROXY  - address of the ERC-1967 proxy to upgrade
///        VAULT_ADMIN  - the current `DEFAULT_ADMIN_ROLE` holder (governance Safe)
///        EXECUTE      - optional ("true"): broadcast the upgrade directly
///        VERIFY_ONLY  - optional ("true"): read-only post-upgrade verification
contract UpgradeVault is Script {
    /// @dev ERC-1967 implementation slot: `keccak256("eip1967.proxy.implementation") - 1`.
    bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @notice Run the upgrade helper in the mode selected by env flags.
    /// @return newImpl Address of the newly deployed implementation (or the
    ///         currently installed one in `VERIFY_ONLY` mode).
    function run() external returns (address newImpl) {
        address proxy = vm.envAddress("VAULT_PROXY");
        address admin = vm.envAddress("VAULT_ADMIN");

        // Mode 3: read-only verification of an already-upgraded proxy.
        if (vm.envOr("VERIFY_ONLY", false)) {
            return _verify(proxy, admin, address(0));
        }

        bool execute = vm.envOr("EXECUTE", false);

        vm.startBroadcast();
        newImpl = address(new SapienVault());
        bytes memory initData = abi.encodeCall(SapienVault.initializeV2, (admin));
        bytes memory upgradeCalldata = abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImpl, initData);
        if (execute) {
            SapienVault(proxy).upgradeToAndCall(newImpl, initData);
        }
        vm.stopBroadcast();

        console.log("Proxy:             ", proxy);
        console.log("New implementation:", newImpl);
        console.log("Executed directly: ", execute);

        if (execute) {
            // Mode 2: confirm the live upgrade landed correctly.
            _verify(proxy, admin, newImpl);
        } else {
            // Mode 1: hand the calldata to the admin Safe.
            console.log("Submit this upgradeToAndCall calldata from the admin Safe (target = proxy):");
            console.logBytes(upgradeCalldata);
        }
    }

    /// @notice Assert the proxy is in the expected post-upgrade state.
    /// @dev Reverts the script on any mismatch so a bad upgrade surfaces
    ///      immediately. `expectedImpl == address(0)` skips the implementation
    ///      check (used in `VERIFY_ONLY` mode where the runner may not know the
    ///      freshly deployed address).
    /// @param proxy The ERC-1967 proxy address.
    /// @param admin The expected `DEFAULT_ADMIN_ROLE` holder.
    /// @param expectedImpl Expected implementation address, or zero to skip.
    /// @return impl The implementation address currently installed on the proxy.
    function _verify(address proxy, address admin, address expectedImpl) internal view returns (address impl) {
        SapienVault v = SapienVault(proxy);
        require(v.verifyStorageLocation(), "verify: ERC-7201 storage slot mismatch");
        require(v.defaultAdmin() == admin, "verify: defaultAdmin not seeded to admin");
        require(v.owner() == admin, "verify: owner() mismatch");
        require(v.minDepositAge() > 0, "verify: minDepositAge not seeded (SAP-5)");

        impl = address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
        if (expectedImpl != address(0)) {
            require(impl == expectedImpl, "verify: implementation slot != new impl");
        }

        console.log("Post-upgrade verification passed:");
        console.log("  implementation: ", impl);
        console.log("  defaultAdmin:   ", v.defaultAdmin());
        console.log("  minDepositAge:  ", v.minDepositAge());
        console.log("  adminDelay (s): ", uint256(v.defaultAdminDelay()));
    }
}
