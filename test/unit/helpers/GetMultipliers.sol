// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienVault} from "src/SapienVault.sol";
import {Constants as Const} from "src/utils/Constants.sol";

contract GetMultipliers is Test {
    SapienVault public sapienVault;

    function setUp() public {
        sapienVault = new SapienVault();
    }

    // Helper function to calculate multiplier using SapienVault's function
    function calculateMultiplier(uint256 amount, uint256 lockupPeriod) internal view returns (uint256) {
        return sapienVault.calculateMultiplier(amount, lockupPeriod);
    }

    function test_GetMultipliers_1000Tokens() public view {
        uint256 amount = 1000 * 1e18;

        console.log("=== 1000 Tokens ===");
        console.log("30 days:", calculateMultiplier(amount, 30 days));
        console.log("90 days:", calculateMultiplier(amount, 90 days));
        console.log("180 days:", calculateMultiplier(amount, 180 days));
        console.log("365 days:", calculateMultiplier(amount, 365 days));
    }

    function test_GetMultipliers_2500Tokens() public view {
        uint256 amount = 2500 * 1e18;

        console.log("=== 2500 Tokens ===");
        console.log("30 days:", calculateMultiplier(amount, 30 days));
        console.log("90 days:", calculateMultiplier(amount, 90 days));
        console.log("180 days:", calculateMultiplier(amount, 180 days));
        console.log("365 days:", calculateMultiplier(amount, 365 days));
    }

    function test_GetMultipliers_5000Tokens() public view {
        uint256 amount = 5000 * 1e18;

        console.log("=== 5000 Tokens ===");
        console.log("30 days:", calculateMultiplier(amount, 30 days));
        console.log("90 days:", calculateMultiplier(amount, 90 days));
        console.log("180 days:", calculateMultiplier(amount, 180 days));
        console.log("365 days:", calculateMultiplier(amount, 365 days));
    }

    function test_GetMultipliers_10000Tokens() public view {
        uint256 amount = 10000 * 1e18;

        console.log("=== 10000 Tokens ===");
        console.log("30 days:", calculateMultiplier(amount, 30 days));
        console.log("90 days:", calculateMultiplier(amount, 90 days));
        console.log("180 days:", calculateMultiplier(amount, 180 days));
        console.log("365 days:", calculateMultiplier(amount, 365 days));
    }

    function test_GetMultipliers_15000Tokens() public view {
        uint256 amount = 15000 * 1e18;

        console.log("=== 15000 Tokens ===");
        console.log("30 days:", calculateMultiplier(amount, 30 days));
        console.log("90 days:", calculateMultiplier(amount, 90 days));
        console.log("180 days:", calculateMultiplier(amount, 180 days));
        console.log("365 days:", calculateMultiplier(amount, 365 days));
    }

    function test_GetMultipliers_25000Tokens() public view {
        uint256 amount = 25000 * 1e18;

        console.log("=== 25000 Tokens ===");
        console.log("30 days:", calculateMultiplier(amount, 30 days));
        console.log("90 days:", calculateMultiplier(amount, 90 days));
        console.log("180 days:", calculateMultiplier(amount, 180 days));
        console.log("365 days:", calculateMultiplier(amount, 365 days));
    }

    function test_GetMultipliers_50000Tokens() public view {
        uint256 amount = 50000 * 1e18;

        console.log("=== 50000 Tokens ===");
        console.log("30 days:", calculateMultiplier(amount, 30 days));
        console.log("90 days:", calculateMultiplier(amount, 90 days));
        console.log("180 days:", calculateMultiplier(amount, 180 days));
        console.log("365 days:", calculateMultiplier(amount, 365 days));
    }

    function test_GetMultipliers_100000Tokens() public view {
        uint256 amount = 100000 * 1e18;

        console.log("=== 100000 Tokens ===");
        console.log("30 days:", calculateMultiplier(amount, 30 days));
        console.log("90 days:", calculateMultiplier(amount, 90 days));
        console.log("180 days:", calculateMultiplier(amount, 180 days));
        console.log("365 days:", calculateMultiplier(amount, 365 days));
    }
}
