// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {MockUSDC} from "./mocks/MockUSDC.sol";

contract MockUSDCTest is Test {
    function test_decimals_isSix() public {
        MockUSDC t = new MockUSDC();
        assertEq(t.decimals(), uint8(6));
    }

    function test_mint() public {
        MockUSDC t = new MockUSDC();
        address a = address(0xbeef);
        t.mint(a, 1_000_000);
        assertEq(t.balanceOf(a), 1_000_000);
    }
}
