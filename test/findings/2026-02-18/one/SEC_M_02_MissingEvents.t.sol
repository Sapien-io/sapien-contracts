// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title SEC-M-02 FIX VERIFICATION: Events emitted for critical admin setters
/// @notice Verifies that setTreasury now properly emits events,
///         enabling off-chain monitoring of critical parameter changes.
contract SEC_M_02_MissingEvents is BaseTest {
    function test_setTreasuryEmitsEvent() public {
        address newTreasury = makeAddr("newTreasury");

        vm.recordLogs();
        vm.prank(admin);
        engine.setTreasury(newTreasury);

        // FIX VERIFIED: event IS now emitted
        assertTrue(vm.getRecordedLogs().length > 0, "should emit TreasuryUpdated event");

        assertEq(engine.treasury(), newTreasury, "treasury changed with event");
    }

    function test_otherAdminSettersStillEmitEvents() public {
        vm.recordLogs();
        vm.prank(admin);
        engine.setProtocolFee(50);

        assertTrue(vm.getRecordedLogs().length > 0, "setProtocolFee still emits event");
    }
}
