// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {QualityEngine} from "src/QualityEngine.sol";

/// @title SEC-C-02 FIX VERIFICATION: ReentrancyGuard properly initialized in proxy
/// @notice Verifies that the proxy's ReentrancyGuard storage slot is now properly
///         initialized to NOT_ENTERED (1) during initialize(), rather than relying
///         on the coincidental behavior of uninitialized storage (0).
contract SEC_C_02_ReentrancyGuardStorage is BaseTest {
    // OZ v5.5.0 namespaced slot
    bytes32 constant REENTRANCY_GUARD_SLOT = 0x9b779b17422d0df92223018b32b4d1fa46e071723d6817e2486d003becc55f00;

    uint256 constant NOT_ENTERED = 1;

    function test_proxyReentrancyStatusProperlyInitialized() public view {
        // FIX VERIFIED: initialize() now explicitly sets _status = NOT_ENTERED (1)
        bytes32 status = vm.load(address(engine), REENTRANCY_GUARD_SLOT);
        assertEq(uint256(status), NOT_ENTERED, "proxy _status should be NOT_ENTERED (1) after initialize()");
    }

    function test_implementationHasConstructorInitializedStatus() public {
        QualityEngine impl = new QualityEngine();
        bytes32 status = vm.load(address(impl), REENTRANCY_GUARD_SLOT);
        assertEq(uint256(status), NOT_ENTERED, "implementation _status should be NOT_ENTERED (1)");
    }

    function test_proxyStatusRemainsNotEnteredAfterGuardedCall() public {
        // Before any nonReentrant call, status is already properly initialized
        bytes32 statusBefore = vm.load(address(engine), REENTRANCY_GUARD_SLOT);
        assertEq(uint256(statusBefore), NOT_ENTERED, "should be NOT_ENTERED before call");

        _createAndFundProject();

        // After the call, _status is still NOT_ENTERED — no behavioral change
        bytes32 statusAfter = vm.load(address(engine), REENTRANCY_GUARD_SLOT);
        assertEq(uint256(statusAfter), NOT_ENTERED, "should be NOT_ENTERED after call");
    }

    function test_initializerProperlyInitializesReentrancyGuard() public view {
        // FIX VERIFIED: The proxy now has _status = NOT_ENTERED (1), meaning
        // initialize() correctly set up the ReentrancyGuard storage.
        bytes32 status = vm.load(address(engine), REENTRANCY_GUARD_SLOT);
        assertEq(uint256(status), NOT_ENTERED, "reentrancy guard IS properly initialized in the proxy");
    }
}
