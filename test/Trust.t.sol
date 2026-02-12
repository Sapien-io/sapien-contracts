// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "./BaseTest.t.sol";
import {VALIDATOR_ROLE, UPDATER_ROLE} from "../src/interface/ISharedTypes.sol";
import {ISapienTrust} from "../src/interface/ISapienTrust.sol";

contract TrustTest is BaseTest {
    function testInitialReputation() public view {
        assertEq(trust.getTrustScore(validator1, VALIDATOR_ROLE), 5000);
    }

    function testUpdateReputation() public {
        vm.prank(admin);
        trust.grantRole(UPDATER_ROLE, admin);

        vm.startPrank(admin);

        // Success increase
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 8000);
        uint256 score = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        assertTrue(score > 5000);

        // Rejection decrease
        trust.updateReputation(validator2, VALIDATOR_ROLE, false, 2000);
        score = trust.getTrustScore(validator2, VALIDATOR_ROLE);
        assertTrue(score < 5000);

        // Slash decrease (qualityScore = 0)
        trust.updateReputation(validator3, VALIDATOR_ROLE, false, 0);
        score = trust.getTrustScore(validator3, VALIDATOR_ROLE);
        assertTrue(score < 5000);

        vm.stopPrank();
    }

    function testReputationDecay() public {
        vm.prank(admin);
        trust.grantRole(UPDATER_ROLE, admin);

        vm.startPrank(admin);
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 9000);
        uint256 scoreBefore = trust.getTrustScore(validator1, VALIDATOR_ROLE);

        // Advance time by 10 days
        vm.warp(block.timestamp + 10 days);

        uint256 scoreAfter = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        assertTrue(scoreAfter < scoreBefore);

        vm.stopPrank();
    }

    function testRoleMinStake() public {
        vm.startPrank(admin);
        trust.setRoleMinStake(VALIDATOR_ROLE, 2000 ether);

        vm.expectRevert(abi.encodeWithSelector(ISapienTrust.InsufficientStake.selector, VALIDATOR_ROLE, 2000 ether, 1000 ether));
        trust.hasEnoughStakeForRole(validator1, VALIDATOR_ROLE);

        // Stake more
        _setupUser(validator1, 1000 ether);
        trust.hasEnoughStakeForRole(validator1, VALIDATOR_ROLE);

        vm.stopPrank();
    }

    function testValidateSkill() public {
        vm.prank(admin);
        trust.grantRole(UPDATER_ROLE, admin);

        vm.startPrank(admin);
        string memory skill = "Solidity";
        assertFalse(trust.hasValidatedSkill(contributor, skill));

        trust.validateSkill(contributor, skill);
        assertTrue(trust.hasValidatedSkill(contributor, skill));

        // Test increment - must warp time due to cooldown
        vm.warp(block.timestamp + 1 days);
        trust.validateSkill(contributor, skill);
        vm.stopPrank();
    }

    function testHasRequiredStake() public {
        assertTrue(trust.hasRequiredStake(validator1)); // 1000 ether staked

        vm.prank(admin);
        trust.setMinStakeRequired(5000 ether);
        assertFalse(trust.hasRequiredStake(validator1));
    }

    function testAdminFunctions() public {
        vm.startPrank(admin);
        trust.setReputationDecay(20);
        assertEq(trust.reputationDecayPerDay(), 20);

        trust.setMinStakeRequired(100 ether);
        assertEq(trust.minStakeRequired(), 100 ether);
        vm.stopPrank();
    }

    function testTrustScoreBoundaries() public {
        vm.prank(admin);
        trust.grantRole(UPDATER_ROLE, admin);

        vm.startPrank(admin);
        // Test MAX_REPUTATION
        // Each update gives 10 base + 20 bonus = 30 bps max, but daily limit is 100 bps
        // To go from 5000 to 10000, we need 5000 bps
        // With daily limit of 100 bps, we need 50 days minimum
        // Warp to start of a new day to ensure clean day boundaries
        uint256 startOfDay = block.timestamp - (block.timestamp % 1 days);
        vm.warp(startOfDay);
        // Do 80 days to ensure we reach max (allowing for some inefficiency in daily limit application)
        for (uint256 i = 0; i < 80; i++) {
            // Each day, do 4 updates to reach the daily limit (4 * 30 = 120, capped at 100)
            for (uint256 j = 0; j < 4; j++) {
                trust.updateReputation(validator1, VALIDATOR_ROLE, true, 10000);
            }
            // Warp to start of next day to reset daily gain counter
            // Add 1 second to ensure we're in a new day (avoid same-day edge cases)
            vm.warp(startOfDay + (i + 1) * 1 days + 1);
        }
        // Do one final update to push it over if needed
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 10000);
        uint256 finalScore = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        // Should reach 10000 (5000 start + 5000 gain = 10000 max)
        assertGe(finalScore, 10000, "Score should reach MAX_REPUTATION");
        if (finalScore > 10000) {
            assertEq(finalScore, 10000, "Score should not exceed MAX_REPUTATION");
        }
        // Clamp to max if it exceeds
        if (finalScore > 10000) {
            // This shouldn't happen due to _min() in updateReputation, but check anyway
            assertEq(finalScore, 10000);
        }

        // Test MIN_REPUTATION
        // Penalty is 100 for slash. 5000 -> 500 (MIN_REPUTATION). Need (5000-500)/100 = 45 iterations
        for (uint256 i = 0; i < 50; i++) {
            trust.updateReputation(validator2, VALIDATOR_ROLE, false, 0);
        }
        assertEq(trust.getTrustScore(validator2, VALIDATOR_ROLE), 500); // MIN_REPUTATION
        vm.stopPrank();
    }

    error InvalidInitialization();

    function testTrustInitializeReverts() public {
        vm.expectRevert(InvalidInitialization.selector);
        trust.initialize(address(vault), 100, 10, admin);
    }

    function testUpdateReputationLowQualityScore() public {
        vm.prank(admin);
        trust.grantRole(UPDATER_ROLE, admin);

        vm.startPrank(admin);
        // Quality score <= 5000 should not get bonus
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 4000);
        uint256 score = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        assertEq(score, 5000 + 10); // Only base SUCCESS_INCREASE, no bonus
        vm.stopPrank();
    }

    function testUpdateReputationScoreBelowPenalty() public {
        vm.prank(admin);
        trust.grantRole(UPDATER_ROLE, admin);

        vm.startPrank(admin);
        // Set score to MIN_REPUTATION (500)
        // Starting from 5000, need 45 slashes: (5000 - 500) / 100 = 45
        for (uint256 i = 0; i < 45; i++) {
            trust.updateReputation(validator1, VALIDATOR_ROLE, false, 0);
        }

        // Now score should be at MIN_REPUTATION (500)
        assertEq(trust.getTrustScore(validator1, VALIDATOR_ROLE), 500);

        // One more slash should still keep it at MIN_REPUTATION (clamped)
        trust.updateReputation(validator1, VALIDATOR_ROLE, false, 0);
        assertEq(trust.getTrustScore(validator1, VALIDATOR_ROLE), 500);
        vm.stopPrank();
    }

    function testHasEnoughStakeZeroRequirements() public {
        vm.startPrank(admin);
        // Set both to zero
        trust.setMinStakeRequired(0);
        trust.setRoleMinStake(VALIDATOR_ROLE, 0);

        // Should not revert for any user
        address newUser = makeAddr("newUser");
        trust.hasEnoughStakeForRole(newUser, VALIDATOR_ROLE);
        vm.stopPrank();
    }

    function testHasRequiredStakeZero() public {
        vm.startPrank(admin);
        trust.setMinStakeRequired(0);

        // Should return true for any user
        address newUser = makeAddr("newUser");
        assertTrue(trust.hasRequiredStake(newUser));
        vm.stopPrank();
    }

    function testApplyDecayZeroDecayRate() public {
        vm.prank(admin);
        trust.grantRole(UPDATER_ROLE, admin);

        vm.startPrank(admin);
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 9000);
        uint256 scoreBefore = trust.getTrustScore(validator1, VALIDATOR_ROLE);

        // Set decay to zero
        trust.setReputationDecay(0);

        vm.warp(block.timestamp + 10 days);

        // Score should not decay
        uint256 scoreAfter = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        assertEq(scoreAfter, scoreBefore);
        vm.stopPrank();
    }

    function testApplyDecayNoLastUpdate() public {
        // User with no reputation should return DEFAULT_REPUTATION
        address newUser = makeAddr("newUser");
        assertEq(trust.getTrustScore(newUser, VALIDATOR_ROLE), 5000);
    }

    function testApplyDecayZeroDaysPassed() public {
        vm.prank(admin);
        trust.grantRole(UPDATER_ROLE, admin);

        vm.startPrank(admin);
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 9000);
        uint256 score = trust.getTrustScore(validator1, VALIDATOR_ROLE);

        // No time passed, score should be same
        uint256 scoreAgain = trust.getTrustScore(validator1, VALIDATOR_ROLE);
        assertEq(score, scoreAgain);
        vm.stopPrank();
    }

    function testApplyDecayLargeDecay() public {
        vm.prank(admin);
        trust.grantRole(UPDATER_ROLE, admin);

        vm.startPrank(admin);
        trust.updateReputation(validator1, VALIDATOR_ROLE, true, 9000);

        // Set very high decay rate
        trust.setReputationDecay(10000); // 100% per day

        vm.warp(block.timestamp + 1 days);

        // Should clamp to MIN_REPUTATION
        assertEq(trust.getTrustScore(validator1, VALIDATOR_ROLE), 500);
        vm.stopPrank();
    }

    function testRoleMinStakeOverridesGlobal() public {
        vm.startPrank(admin);
        trust.setMinStakeRequired(100 ether);
        trust.setRoleMinStake(VALIDATOR_ROLE, 2000 ether); // Higher than validator1's stake (1000 ether)

        // Should use role-specific stake (2000 ether)
        vm.expectRevert(abi.encodeWithSelector(ISapienTrust.InsufficientStake.selector, VALIDATOR_ROLE, 2000 ether, 1000 ether));
        trust.hasEnoughStakeForRole(validator1, VALIDATOR_ROLE);

        // Set role stake to 0, should use global (100 ether)
        trust.setRoleMinStake(VALIDATOR_ROLE, 0);
        trust.hasEnoughStakeForRole(validator1, VALIDATOR_ROLE);
        vm.stopPrank();
    }
}

