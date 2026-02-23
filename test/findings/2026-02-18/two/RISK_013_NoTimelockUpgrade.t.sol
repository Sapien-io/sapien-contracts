// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";

/// @title RISK-013 VERIFIED: No Timelock on UUPS Upgrades
/// @notice Both SapienCore and SapienVault can be upgraded instantly by DEFAULT_ADMIN_ROLE
///         with no timelock delay, enabling instant protocol takeover if admin key is compromised.
contract RISK_013_NoTimelockUpgrade is BaseTest {
    function test_instantCoreUpgrade() public {
        SapienCore newImpl = new SapienCore();

        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");
    }

    function test_instantVaultUpgrade() public {
        SapienVault newImpl = new SapienVault();

        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");
    }

    function test_upgradePreservesStateAcrossInstantUpgrade() public {
        bytes32 projectId = _createAndFundProject();

        SapienCore newImpl = new SapienCore();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        // State persists across instant upgrade — including active projects with user funds
        assertEq(engine.getProject(projectId).originator, originator, "state persisted");
        assertGt(engine.getProjectEscrow(projectId, address(token)), 0, "escrow intact");
    }

    function test_nonAdminCannotUpgrade() public {
        SapienCore newImpl = new SapienCore();

        vm.prank(contributor1);
        vm.expectRevert();
        engine.upgradeToAndCall(address(newImpl), "");
    }
}
