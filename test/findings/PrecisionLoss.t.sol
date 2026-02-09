// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";

contract PrecisionLossTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");

    function setUp() public override {
        super.setUp();
    }

    function _calculateReward(uint256 totalRewards, uint256 totalQuantity, uint256 validatorBasisPoints)
        internal
        pure
        returns (uint256)
    {
        if (totalQuantity == 0) return 0;
        return (totalRewards * (10000 - validatorBasisPoints)) / (10000 * totalQuantity);
    }

    function testRewardPrecisionLoss_FixVerification() public {
        uint256 rewardAmount = 1000;
        uint256 quantity = 10000;

        vm.prank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "test-project", 0, 0, 3, 2000, "test");

        vm.startPrank(originator);
        rewardToken.approve(address(core), rewardAmount);

        // Issue #4 fix: MIN_REWARD_PER_SLOT prevents funding with inadequate rewards
        vm.expectRevert("Reward per slot too low");
        core.fundProject(PROJECT_ID, rewardAmount, quantity);
        vm.stopPrank();

        console.log("FIX VERIFIED: Small reward/large quantity funding blocked");
    }

    function testLargeRewardPrecisionLoss() public {
        uint256 rewardAmount = 1 ether;
        uint256 quantity = 3;

        vm.prank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "test-project", 0, 0, 3, 2000, "test");

        vm.startPrank(originator);
        rewardToken.approve(address(core), rewardAmount);
        core.fundProject(PROJECT_ID, rewardAmount, quantity);
        vm.stopPrank();

        uint256 validatorBasisPoints = 2000;
        uint256 num = rewardAmount * (10000 - validatorBasisPoints);
        uint256 den = 10000 * quantity;
        uint256 reward = num / den;
        console.log("Reward per contributor (1 token, 3 quantity):", reward);

        uint256 expected = (uint256(1 ether) * 8000) / (10000 * 3);
        assertEq(reward, expected);

        uint256 totalDistributed = reward * 3;
        uint256 intendedTotal = 0.8 ether;
        uint256 lost = intendedTotal - totalDistributed;
        console.log("Total intended:", intendedTotal);
        console.log("Total distributed:", totalDistributed);
        console.log("Total lost (wei):", lost);
    }
}
