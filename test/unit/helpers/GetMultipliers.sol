// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "src/Multiplier.sol";
import "forge-std/console.sol";
import "forge-std/Test.sol";

contract GetMultipliers is Test {
    function run() external view {
        one();
        ten();
        one_hundred();
        two_fifty();
        five_hundred();
        thousand();
        twenthy_five_hundred();
        ten_thousand();
    }

    function one() public view returns (uint256) {
        uint256 amount = 1 ether;
        console.log("--------------------------------");
        console.log("1 token multipliers:");
        console.log("30 days:", Multiplier.calculateMultiplier(amount, 30 days));
        console.log("90 days:", Multiplier.calculateMultiplier(amount, 90 days));
        console.log("180 days:", Multiplier.calculateMultiplier(amount, 180 days));
        console.log("365 days:", Multiplier.calculateMultiplier(amount, 365 days));
    }

    function ten() public view returns (uint256) {
        uint256 amount = 10 ether;
        console.log("--------------------------------");
        console.log("10 token multipliers:");
        console.log("30 days:", Multiplier.calculateMultiplier(amount, 30 days));
        console.log("90 days:", Multiplier.calculateMultiplier(amount, 90 days));
        console.log("180 days:", Multiplier.calculateMultiplier(amount, 180 days));
        console.log("365 days:", Multiplier.calculateMultiplier(amount, 365 days));
    }

    function one_hundred() public view returns (uint256) {
        uint256 amount = 100 ether;
        console.log("--------------------------------");
        console.log("100 token multipliers:");
        console.log("30 days:", Multiplier.calculateMultiplier(amount, 30 days));
        console.log("90 days:", Multiplier.calculateMultiplier(amount, 90 days));
        console.log("180 days:", Multiplier.calculateMultiplier(amount, 180 days));
        console.log("365 days:", Multiplier.calculateMultiplier(amount, 365 days));
    }

    function two_fifty() public view returns (uint256) {
        uint256 amount = 250 ether;
        console.log("--------------------------------");
        console.log("250 token multipliers:");
        console.log("30 days:", Multiplier.calculateMultiplier(amount, 30 days));
        console.log("90 days:", Multiplier.calculateMultiplier(amount, 90 days));
        console.log("180 days:", Multiplier.calculateMultiplier(amount, 180 days));
        console.log("365 days:", Multiplier.calculateMultiplier(amount, 365 days));
    }

    function five_hundred() public view returns (uint256) {
        uint256 amount = 500 ether;
        console.log("--------------------------------");
        console.log("500 token multipliers:");
        console.log("30 days:", Multiplier.calculateMultiplier(amount, 30 days));
        console.log("90 days:", Multiplier.calculateMultiplier(amount, 90 days));
        console.log("180 days:", Multiplier.calculateMultiplier(amount, 180 days));
        console.log("365 days:", Multiplier.calculateMultiplier(amount, 365 days));
    }

    function thousand() public view returns (uint256) {
        uint256 amount = 1000 ether;
        console.log("--------------------------------");
        console.log("1000 token multipliers:");
        console.log("30 days:", Multiplier.calculateMultiplier(amount, 30 days));
        console.log("90 days:", Multiplier.calculateMultiplier(amount, 90 days));
        console.log("180 days:", Multiplier.calculateMultiplier(amount, 180 days));
        console.log("365 days:", Multiplier.calculateMultiplier(amount, 365 days));
    }

    function twenthy_five_hundred() public view returns (uint256) {
        uint256 amount = 2500 ether;
        console.log("--------------------------------");
        console.log("2500 token multipliers:");
        console.log("30 days:", Multiplier.calculateMultiplier(amount, 30 days));
        console.log("90 days:", Multiplier.calculateMultiplier(amount, 90 days));
        console.log("180 days:", Multiplier.calculateMultiplier(amount, 180 days));
        console.log("365 days:", Multiplier.calculateMultiplier(amount, 365 days));
    }

    function ten_thousand() public view returns (uint256) {
        uint256 amount = 5_000 ether;
        console.log("--------------------------------");
        console.log("5000 token multipliers:");
        console.log("30 days:", Multiplier.calculateMultiplier(amount, 30 days));
        console.log("90 days:", Multiplier.calculateMultiplier(amount, 90 days));
        console.log("180 days:", Multiplier.calculateMultiplier(amount, 180 days));
        console.log("365 days:", Multiplier.calculateMultiplier(amount, 365 days));
    }
}
