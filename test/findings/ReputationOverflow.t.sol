// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

contract ReputationOverflowTest is BaseTest {
    function setUp() public override {
        super.setUp();
    }

    function testReputationDecayOverflow() public {
        address user = address(0x123);

        vm.startPrank(admin);
        // Initial setup - default score is 5000
        trust.updateReputation(user, VALIDATOR_ROLE, true, 8000);

        // Set a high decay rate (10%)
        trust.setReputationDecay(1000);
        vm.stopPrank();

        // Warp far into the future (100 days = 100% decay)
        vm.warp(block.timestamp + 100 days);

        // This should NOT revert now, but return MIN_REPUTATION
        uint256 score = trust.getTrustScore(user, VALIDATOR_ROLE);
        console.log("Score after decay (100 days):", score);
        assertEq(score, trust.MIN_REPUTATION());

        // Warp even further
        vm.warp(block.timestamp + 10000 days);
        score = trust.getTrustScore(user, VALIDATOR_ROLE);
        console.log("Score after decay (10000 days):", score);
        assertEq(score, trust.MIN_REPUTATION());
    }
}
