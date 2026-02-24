// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {Project, ProjectStatus} from "src/Types.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title SEC-L-01 FIX VERIFICATION: createProject rejects mismatched originator
/// @notice Verifies that createProject now reverts with InvalidProjectConfig when
///         config.originator is set to a non-zero address that differs from msg.sender,
///         instead of silently overwriting it.
contract SEC_L_01_OriginatorIgnored is BaseTest {
    function test_mismatchedOriginatorReverts() public {
        bytes32 projectId = keccak256("originator-test");
        address intendedOriginator = makeAddr("intendedOriginator");

        // FIX VERIFIED: passing a different originator now reverts
        vm.prank(originator);
        vm.expectRevert(
            abi.encodeWithSelector(ISapienCore.InvalidProjectConfig.selector, "originator must be msg.sender or zero")
        );
        engine.createProject(
            projectId,
            "",
            Project({
                originator: intendedOriginator,
                rewardToken: address(token),
                totalRewards: 0,
                totalQuantity: 0,
                availableSlots: 0,
                consensusThreshold: 7000,
                minStakeToClaim: STAKE_AMOUNT,
                validatorRewardBps: 2000,
                numberOfValidations: 3,
                requiredSkill: bytes32(0),
                minValidatorReputation: 0,
                minValidationStake: 0,
                status: ProjectStatus.Created,
                activatedAt: 0,
                completedAt: 0,
                cancelledAt: 0
            })
        );
    }

    function test_zeroOriginatorStillAllowed() public {
        bytes32 projectId = keccak256("originator-zero");

        // Passing address(0) is still valid — contract sets originator to msg.sender
        vm.prank(originator);
        engine.createProject(
            projectId,
            "",
            Project({
                originator: address(0),
                rewardToken: address(token),
                totalRewards: 0,
                totalQuantity: 0,
                availableSlots: 0,
                consensusThreshold: 7000,
                minStakeToClaim: STAKE_AMOUNT,
                validatorRewardBps: 2000,
                numberOfValidations: 3,
                requiredSkill: bytes32(0),
                minValidatorReputation: 0,
                minValidationStake: 0,
                status: ProjectStatus.Created,
                activatedAt: 0,
                completedAt: 0,
                cancelledAt: 0
            })
        );

        Project memory proj = engine.getProject(projectId);
        assertEq(proj.originator, originator, "originator is msg.sender when config.originator is zero");
    }

    function test_matchingOriginatorAllowed() public {
        bytes32 projectId = keccak256("originator-match");

        // Passing msg.sender explicitly is also valid
        vm.prank(originator);
        engine.createProject(
            projectId,
            "",
            Project({
                originator: originator,
                rewardToken: address(token),
                totalRewards: 0,
                totalQuantity: 0,
                availableSlots: 0,
                consensusThreshold: 7000,
                minStakeToClaim: STAKE_AMOUNT,
                validatorRewardBps: 2000,
                numberOfValidations: 3,
                requiredSkill: bytes32(0),
                minValidatorReputation: 0,
                minValidationStake: 0,
                status: ProjectStatus.Created,
                activatedAt: 0,
                completedAt: 0,
                cancelledAt: 0
            })
        );

        Project memory proj = engine.getProject(projectId);
        assertEq(proj.originator, originator, "originator matches msg.sender");
    }
}
