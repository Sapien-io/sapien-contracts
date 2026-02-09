// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "./BaseTest.t.sol";
import {console} from "forge-std/Test.sol";

contract FrontendFuzzTest is BaseTest {
    address public treasury = makeAddr("treasury");
    address public frontendOperator = makeAddr("frontendOperator");

    function setUp() public override {
        super.setUp();
        vm.prank(admin);
        core.setTreasury(treasury);
    }

    /**
     * @notice Fuzz test for the complete protocol flow with randomized fees and rewards
     * @param rewardAmount Total reward amount for the project
     * @param protocolFeeBps Protocol fee in basis points (0 to 300)
     * @param operatorFeeBps Operator fee in basis points (0 to 200)
     * @param claimFeeBps Operator fee on claim in basis points (0 to 400)
     * @param quantity Number of contribution slots (1 to 100)
     */
    function test_FuzzProtocolFlow(
        uint256 rewardAmount,
        uint16 protocolFeeBps,
        uint16 operatorFeeBps,
        uint16 claimFeeBps,
        uint8 quantity
    ) public {
        // Bound inputs to reasonable ranges
        rewardAmount = bound(rewardAmount, 1e18, 1_000_000 ether); // 1 to 1M tokens
        protocolFeeBps = uint16(bound(protocolFeeBps, 0, 300));
        operatorFeeBps = uint16(bound(operatorFeeBps, 0, 200));
        claimFeeBps = uint16(bound(claimFeeBps, 0, 400));
        quantity = uint8(bound(quantity, 1, 100));

        string memory cid = string(abi.encodePacked("fuzz-project-", vm.toString(rewardAmount)));
        bytes32 projectId = keccak256(abi.encodePacked(cid));

        // 1. Setup Protocol Fee
        vm.prank(admin);
        core.setProtocolFeeBasisPoints(protocolFeeBps);

        // 2. Create and Fund Project
        vm.startPrank(originator);
        core.createProject(
            projectId,
            address(rewardToken),
            cid,
            10 ether, // minStakeToClaim
            5 ether, // minStakeToContribute
            3, // minValidations
            1000, // 10% validator rewards
            "" // no skill
        );

        rewardToken.mint(originator, rewardAmount);
        rewardToken.approve(address(core), rewardAmount);

        uint256 treasuryBalanceBefore = rewardToken.balanceOf(treasury);
        uint256 operatorBalanceBefore = rewardToken.balanceOf(frontendOperator);

        core.fundProject(projectId, rewardAmount, quantity, frontendOperator, operatorFeeBps);
        vm.stopPrank();

        // 3. Verify Fee Collection
        {
            uint256 expectedProtocolFee = (rewardAmount * protocolFeeBps) / 10000;
            uint256 expectedOperatorFee = ((rewardAmount - expectedProtocolFee) * operatorFeeBps) / 10000;

            assertEq(
                rewardToken.balanceOf(treasury) - treasuryBalanceBefore, expectedProtocolFee, "Protocol fee mismatch"
            );
            assertEq(
                rewardToken.balanceOf(frontendOperator) - operatorBalanceBefore,
                expectedOperatorFee,
                "Operator fee mismatch"
            );
        }

        uint256 expectedProjectRewards = core.getProject(projectId).state.totalRewardsAvailable;

        // 4. Contributor Workflow
        vm.startPrank(contributor);
        core.contribute(projectId, core.claimToContribute(projectId, 1), 0, keccak256("submission1"));
        vm.stopPrank();

        // 5. Validator Workflow
        _setValidatorCapacity(validator1, 1000 ether);
        _setValidatorCapacity(validator2, 1000 ether);
        _setValidatorCapacity(validator3, 1000 ether);
        _commitAndRevealValidators(projectId);

        // 6. Finalize
        core.finalizeContribution(projectId, 0);

        // 7-9. Verify & claim rewards (extracted to avoid stack too deep)
        _verifyAndClaimRewards(projectId, expectedProjectRewards, quantity, frontendOperator, claimFeeBps);
    }

    function _verifyAndClaimRewards(
        bytes32 projectId,
        uint256 expectedProjectRewards,
        uint256 quantity,
        address frontendOperator,
        uint256 claimFeeBps
    ) internal {
        uint256 contributorEarned = rewards.getAvailableRewards(contributor, projectId, address(rewardToken));

        uint256 validatorPool = (expectedProjectRewards * 1000) / 10000;
        uint256 contributorPool = expectedProjectRewards - validatorPool;
        uint256 expectedContributorReward = contributorPool / quantity;

        assertApproxEqAbs(contributorEarned, expectedContributorReward, 1, "Contributor reward mismatch");

        uint256 operatorBalanceBeforeClaim = rewardToken.balanceOf(frontendOperator);
        uint256 contributorBalanceBeforeClaim = rewardToken.balanceOf(contributor);

        vm.startPrank(contributor);
        rewards.claimRewards(projectId, address(rewardToken), frontendOperator, claimFeeBps);
        vm.stopPrank();

        {
            uint256 expectedClaimFee = (contributorEarned * claimFeeBps) / 10000;
            uint256 expectedNetReward = contributorEarned - expectedClaimFee;

            assertEq(
                rewardToken.balanceOf(frontendOperator) - operatorBalanceBeforeClaim,
                expectedClaimFee,
                "Claim fee mismatch"
            );
            assertEq(
                rewardToken.balanceOf(contributor) - contributorBalanceBeforeClaim,
                expectedNetReward,
                "Net reward mismatch"
            );
        }

        _verifyValidatorClaim(projectId);
    }

    function test_GhostValidatorSlashing(uint256 stakeAmount) public {
        stakeAmount = bound(stakeAmount, 100 ether, 1000 ether);
        bytes32 projectId = keccak256("ghost-project");

        // Create project
        vm.prank(originator);
        core.createProject(projectId, address(rewardToken), "ghost-project", 10 ether, 5 ether, 3, 1000, "");

        // Fund project
        rewardToken.mint(originator, 1000 ether);
        vm.startPrank(originator);
        rewardToken.approve(address(core), 1000 ether);
        core.fundProject(projectId, 1000 ether, 10);
        vm.stopPrank();

        // Contributor work
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(projectId, 1);
        core.contribute(projectId, claimId, 0, keccak256("sub"));
        vm.stopPrank();

        // Validator setup
        _setValidatorCapacity(validator1, 1000 ether);

        vm.startPrank(validator1);
        uint256 vClaimId = oracle.claimToValidate(projectId);
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), stakeAmount, keccak256("salt")));
        oracle.commitValidationWithStake(projectId, vClaimId, 0, stakeAmount, commitHash);
        vm.stopPrank();

        // Fast forward past reveal deadline
        vm.warp(block.timestamp + 10 days);

        uint256 validatorBalanceBefore = vault.getStake(validator1);

        // Anyone can cancel
        oracle.cancelExpiredCommitment(projectId, 0, validator1);

        uint256 validatorBalanceAfter = vault.getStake(validator1);

        // Should be slashed
        assertTrue(validatorBalanceAfter < validatorBalanceBefore, "Validator should be slashed");
        // NOTE: Economic Finding - Slashed users who retain stake benefit from their own slash
        // because the vault only burns shares and keeps assets, redistributing value to all
        // remaining share holders (including the slashed user).
        // A validator with 20% of total shares will effectively only lose 80% of their stake.
        assertApproxEqRel(
            validatorBalanceBefore - validatorBalanceAfter, stakeAmount, 0.25e18, "Slash amount mismatch too large"
        );
    }

    function test_UnauthorizedRoles(uint256 rewardAmount) public {
        rewardAmount = bound(rewardAmount, 1e18, 1000 ether);
        bytes32 projectId = keccak256("unauthorized-project");

        // 1. Originator cannot contribute
        vm.startPrank(originator);
        core.createProject(projectId, address(rewardToken), "unauthorized-project", 10 ether, 5 ether, 3, 1000, "");
        rewardToken.mint(originator, rewardAmount);
        rewardToken.approve(address(core), rewardAmount);
        core.fundProject(projectId, rewardAmount, 10);

        vm.expectRevert();
        core.claimToContribute(projectId, 1);
        vm.stopPrank();

        // 2. Contributor cannot validate their own work
        vm.startPrank(contributor);
        uint256 claimId = core.claimToContribute(projectId, 1);
        core.contribute(projectId, claimId, 0, keccak256("sub"));
        vm.stopPrank();

        // Contributor tries to validate their own work
        _setValidatorCapacity(contributor, 100 ether);

        vm.startPrank(contributor);
        uint256 vClaimId = oracle.claimToValidate(projectId);
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), uint256(10 ether), keccak256("salt")));
        vm.expectRevert();
        oracle.commitValidationWithStake(projectId, vClaimId, 0, 10 ether, commitHash);
        vm.stopPrank();

        // 3. Originator cannot validate
        _setValidatorCapacity(originator, 100 ether);
        vm.startPrank(originator);
        uint256 origVClaimId = oracle.claimToValidate(projectId);
        bytes32 origCommitHash = keccak256(abi.encodePacked(uint256(8000), uint256(10 ether), keccak256("salt")));
        vm.expectRevert(); // Should fail at commit, not claim
        oracle.commitValidationWithStake(projectId, origVClaimId, 0, 10 ether, origCommitHash);
        vm.stopPrank();
    }

    function _verifyValidatorClaim(bytes32 projectId) internal {
        uint256 validator1Earned = rewards.getAvailableValidatorRewards(validator1, projectId, address(rewardToken));
        uint256 validator1BalanceBefore = rewardToken.balanceOf(validator1);

        vm.prank(validator1);
        rewards.claimValidatorRewards(projectId, address(rewardToken), address(0), 0);

        assertEq(
            rewardToken.balanceOf(validator1) - validator1BalanceBefore,
            validator1Earned,
            "Validator reward claim mismatch"
        );
    }

    function _commitAndRevealValidators(bytes32 projectId) internal {
        address[3] memory validators = [validator1, validator2, validator3];
        uint256[3] memory scores = [uint256(8000), uint256(8500), uint256(9000)];
        bytes32[3] memory salts = [keccak256("s1"), keccak256("s2"), keccak256("s3")];

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(validators[i]);
            uint256 vClaimId = oracle.claimToValidate(projectId);
            vm.prank(validators[i]);
            oracle.commitValidationWithStake(
                projectId, vClaimId, 0, 100 ether, keccak256(abi.encodePacked(scores[i], uint256(100 ether), salts[i]))
            );
        }

        vm.warp(block.timestamp + 1 hours + 1);

        for (uint256 i = 0; i < 3; i++) {
            vm.prank(validators[i]);
            oracle.revealValidation(projectId, 0, scores[i], salts[i]);
        }
    }
}
