// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "./BaseTest.t.sol";
import {IRewards} from "../src/interface/IRewards.sol";

contract RewardsTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");

    function testSetCore() public {
        // Core is already set in BaseTest setup, verify one-time-set restriction
        address currentCore = rewards.core();
        assertTrue(currentCore != address(0), "Core should already be set");

        // Re-setting should revert with CoreAlreadySet (Opus 4.6 L-5 fix)
        vm.prank(admin);
        vm.expectRevert(IRewards.CoreAlreadySet.selector);
        rewards.setCore(makeAddr("newCore"));

        // Unauthorized
        vm.prank(contributor);
        vm.expectRevert();
        rewards.setCore(makeAddr("other"));
    }

    function testPauseUnpause() public {
        vm.startPrank(admin);
        rewards.pause();
        assertTrue(rewards.paused());

        rewards.unpause();
        assertFalse(rewards.paused());
        vm.stopPrank();

        // Unauthorized
        vm.prank(contributor);
        vm.expectRevert();
        rewards.pause();
    }

    function testEmergencyWithdraw() public {
        rewardToken.mint(address(rewards), 100 ether);
        address recipient = makeAddr("recipient");

        vm.prank(admin);
        rewards.pause();

        vm.prank(admin);
        rewards.emergencyWithdraw(address(rewardToken), recipient, 50 ether);
        assertEq(rewardToken.balanceOf(recipient), 50 ether);
        assertEq(rewardToken.balanceOf(address(rewards)), 50 ether);

        // Fail when not paused
        vm.prank(admin);
        rewards.unpause();
        vm.prank(admin);
        vm.expectRevert();
        rewards.emergencyWithdraw(address(rewardToken), recipient, 10 ether);
    }

    function testAllocateRewardsUnauthorized() public {
        vm.prank(contributor);
        vm.expectRevert(IRewards.OnlyCore.selector);
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), 100 ether);
    }

    function testClaimRewards() public {
        uint256 amount = 10 ether;

        // Setup rewards (mimic SapienCore behavior)
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount);
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), amount);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount);

        assertEq(rewards.getAvailableRewards(contributor, PROJECT_ID, address(rewardToken)), amount);
        assertEq(rewards.getTotalRewardsEarned(contributor, PROJECT_ID, address(rewardToken)), amount);

        vm.prank(contributor);
        rewards.claimRewards(PROJECT_ID, address(rewardToken), address(0), 0);

        assertEq(rewardToken.balanceOf(contributor), amount);
        assertEq(rewards.getAvailableRewards(contributor, PROJECT_ID, address(rewardToken)), 0);
    }

    function testClaimAllRewards() public {
        uint256 amount1 = 10 ether;
        uint256 amount2 = 20 ether;
        bytes32 project2 = keccak256("project-2");
        bytes32[] memory projectIds = new bytes32[](2);
        projectIds[0] = PROJECT_ID;
        projectIds[1] = project2;

        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount1);
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), amount1);
        rewards.allocateRewards(project2, address(rewardToken), amount2);
        rewards.distributeReward(project2, contributor, address(rewardToken), amount2);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount1 + amount2);

        vm.prank(contributor);
        rewards.claimAllRewards(address(rewardToken), projectIds, address(0), 0);

        assertEq(rewardToken.balanceOf(contributor), amount1 + amount2);
    }

    function testClaimValidatorRewards() public {
        uint256 amount = 5 ether;

        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount);
        rewards.distributeValidatorReward(PROJECT_ID, validator1, address(rewardToken), amount);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount);

        assertEq(rewards.getAvailableValidatorRewards(validator1, PROJECT_ID, address(rewardToken)), amount);
        assertEq(rewards.getTotalValidatorRewardsEarned(validator1, PROJECT_ID, address(rewardToken)), amount);

        vm.prank(validator1);
        rewards.claimValidatorRewards(PROJECT_ID, address(rewardToken), address(0), 0);

        assertEq(rewardToken.balanceOf(validator1), amount);
    }

    function testClaimAllValidatorRewards() public {
        uint256 amount1 = 5 ether;
        uint256 amount2 = 15 ether;
        bytes32 project2 = keccak256("project-2");
        bytes32[] memory projectIds = new bytes32[](2);
        projectIds[0] = PROJECT_ID;
        projectIds[1] = project2;

        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount1);
        rewards.distributeValidatorReward(PROJECT_ID, validator1, address(rewardToken), amount1);
        rewards.allocateRewards(project2, address(rewardToken), amount2);
        rewards.distributeValidatorReward(project2, validator1, address(rewardToken), amount2);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount1 + amount2);

        vm.prank(validator1);
        rewards.claimAllValidatorRewards(address(rewardToken), projectIds, address(0), 0);

        assertEq(rewardToken.balanceOf(validator1), amount1 + amount2);
    }

    function testRevertNoRewardsToClaim() public {
        vm.prank(contributor);
        vm.expectRevert(IRewards.NoRewardsToClaim.selector);
        rewards.claimRewards(PROJECT_ID, address(rewardToken), address(0), 0);

        vm.prank(validator1);
        vm.expectRevert(IRewards.NoRewardsToClaim.selector);
        rewards.claimValidatorRewards(PROJECT_ID, address(rewardToken), address(0), 0);

        bytes32[] memory projectIds = new bytes32[](1);
        projectIds[0] = PROJECT_ID;

        vm.prank(contributor);
        vm.expectRevert(IRewards.NoRewardsToClaim.selector);
        rewards.claimAllRewards(address(rewardToken), projectIds, address(0), 0);

        vm.prank(validator1);
        vm.expectRevert(IRewards.NoRewardsToClaim.selector);
        rewards.claimAllValidatorRewards(address(rewardToken), projectIds, address(0), 0);
    }

    function testInsufficientProjectRewards() public {
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), 10 ether);

        vm.expectRevert(
            abi.encodeWithSelector(
                IRewards.InsufficientProjectRewards.selector, PROJECT_ID, address(rewardToken), 20 ether, 10 ether
            )
        );
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), 20 ether);
        vm.stopPrank();
    }

    function testRemainingProjectRewards() public {
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), 100 ether);
        assertEq(rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken)), 100 ether);

        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), 30 ether);
        assertEq(rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken)), 70 ether);
        vm.stopPrank();
    }

    function testInvalidAddressAndAmount() public {
        vm.startPrank(admin);

        vm.expectRevert(IRewards.InvalidAddress.selector);
        rewards.setCore(address(0));

        rewards.pause();
        vm.expectRevert(IRewards.InvalidAddress.selector);
        rewards.emergencyWithdraw(address(rewardToken), address(0), 10 ether);

        vm.expectRevert(IRewards.InvalidAmount.selector);
        rewards.emergencyWithdraw(address(rewardToken), makeAddr("to"), 0);

        rewards.unpause();
        vm.stopPrank();

        vm.startPrank(address(core));
        // allocateRewards now checks amount 0
        vm.expectRevert(IRewards.InvalidAmount.selector);
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), 0);

        rewards.allocateRewards(PROJECT_ID, address(rewardToken), 100 ether);
        vm.expectRevert(IRewards.InvalidAmount.selector);
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), 0);
        vm.stopPrank();
    }

    error EnforcedPause();

    function testPausableFunctions() public {
        vm.prank(admin);
        rewards.pause();

        vm.startPrank(address(core));
        vm.expectRevert(EnforcedPause.selector);
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), 100 ether);

        vm.expectRevert(EnforcedPause.selector);
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), 10 ether);

        vm.expectRevert(EnforcedPause.selector);
        rewards.distributeValidatorReward(PROJECT_ID, validator1, address(rewardToken), 10 ether);
        vm.stopPrank();

        vm.startPrank(contributor);
        vm.expectRevert(EnforcedPause.selector);
        rewards.claimRewards(PROJECT_ID, address(rewardToken), address(0), 0);

        bytes32[] memory projectIds = new bytes32[](1);
        projectIds[0] = PROJECT_ID;
        vm.expectRevert(EnforcedPause.selector);
        rewards.claimAllRewards(address(rewardToken), projectIds, address(0), 0);
        vm.stopPrank();

        vm.startPrank(validator1);
        vm.expectRevert(EnforcedPause.selector);
        rewards.claimValidatorRewards(PROJECT_ID, address(rewardToken), address(0), 0);

        vm.expectRevert(EnforcedPause.selector);
        rewards.claimAllValidatorRewards(address(rewardToken), projectIds, address(0), 0);
        vm.stopPrank();
    }

    error InvalidInitialization();

    function testDoubleInitialize() public {
        vm.expectRevert(InvalidInitialization.selector);
        rewards.initialize(admin);
    }
}

