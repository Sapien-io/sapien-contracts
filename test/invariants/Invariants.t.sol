// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "test/BaseTest.t.sol";
import {ProtocolHandler} from "test/handlers/ProtocolHandler.sol";
import {SapienCore} from "../../src/SapienCore.sol";
import {CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

/**
 * @title ProtocolInvariants
 * @notice Stateful invariant tests for the Sapien V2 protocol
 * @dev Uses a Handler pattern to perform random protocol actions and verify
 *      global properties after every state transition.
 */
contract ProtocolInvariantsTest is BaseTest {
    ProtocolHandler public handler;
    bytes32 public constant PROJECT_ID = keccak256("invariant-test-project");

    function setUp() public override {
        super.setUp();

        // Setup Project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "invariant-test-project", 100 ether, 50 ether, 3, 1000, "");
        rewardToken.mint(originator, 10000 ether);
        rewardToken.approve(address(core), 10000 ether);
        core.fundProject(PROJECT_ID, 10000 ether, 100);
        vm.stopPrank();

        handler = new ProtocolHandler(core, oracle, trust, vault, rewards, rewardToken, stakeToken, PROJECT_ID);

        // Add initial actors
        handler.addContributor(makeAddr("c1"));
        handler.addContributor(makeAddr("c2"));
        handler.addValidator(makeAddr("v1"));
        handler.addValidator(makeAddr("v2"));
        handler.addValidator(makeAddr("v3"));

        targetContract(address(handler));
    }

    /**
     * @notice INVARIANT: Rewards contract balance >= total allocated rewards
     */
    function invariant_RewardsSolvency() public view {
        uint256 balance = rewardToken.balanceOf(address(rewards));
        uint256 allocated = rewards.totalAllocated(address(rewardToken));
        assertGe(balance, allocated, "Rewards contract must be solvent");
    }

    /**
     * @notice INVARIANT: Vault total assets >= total shares value & locked <= total
     */
    function invariant_VaultStakeIntegrity() public {
        address[] memory actors = new address[](5);
        actors[0] = makeAddr("c1");
        actors[1] = makeAddr("c2");
        actors[2] = makeAddr("v1");
        actors[3] = makeAddr("v2");
        actors[4] = makeAddr("v3");

        for (uint256 i = 0; i < actors.length; i++) {
            uint256 total = vault.getStake(actors[i]);
            uint256 locked = vault.getLockedStake(actors[i]);
            assertLe(locked, total, "Locked stake cannot exceed total stake");
        }
    }

    /**
     * @notice INVARIANT: Reputation must always stay within [500, 10000]
     */
    function invariant_ReputationBounds() public {
        address[] memory actors = new address[](5);
        actors[0] = makeAddr("c1");
        actors[1] = makeAddr("c2");
        actors[2] = makeAddr("v1");
        actors[3] = makeAddr("v2");
        actors[4] = makeAddr("v3");

        for (uint256 i = 0; i < actors.length; i++) {
            uint256 cRep = trust.getTrustScore(actors[i], CONTRIBUTOR_ROLE);
            uint256 vRep = trust.getTrustScore(actors[i], VALIDATOR_ROLE);

            assertGe(cRep, 500, "Contributor reputation below minimum");
            assertLe(cRep, 10000, "Contributor reputation above maximum");
            assertGe(vRep, 500, "Validator reputation below minimum");
            assertLe(vRep, 10000, "Validator reputation above maximum");
        }
    }

    /**
     * @notice INVARIANT: Project slot state must remain consistent
     */
    function invariant_ProjectSlotAccounting() public view {
        SapienCore.Project memory p = core.getProject(PROJECT_ID);
        uint256 total = p.state.totalQuantityAvailable;
        uint256 submitted = p.state.submittedQuantity;
        uint256 active = p.state.activeClaimedQuantity;
        uint256 rewarded = p.state.rewardedQuantity;

        assertLe(submitted + active, total, "Sum of submitted and active exceeds total");
        assertLe(rewarded, submitted, "Rewarded exceeds submitted");
    }

    /**
     * @notice INVARIANT: Project remaining rewards + distributed rewards = funded amount
     */
    function invariant_RewardConservation() public {
        SapienCore.Project memory p = core.getProject(PROJECT_ID);
        uint256 rewardsFunded = p.state.totalRewardsAvailable;

        uint256 currentProjectRewards = rewards.getRemainingProjectRewards(PROJECT_ID, address(rewardToken));

        address[] memory actors = new address[](5);
        actors[0] = makeAddr("c1");
        actors[1] = makeAddr("c2");
        actors[2] = makeAddr("v1");
        actors[3] = makeAddr("v2");
        actors[4] = makeAddr("v3");

        uint256 totalEarned = 0;
        for (uint256 i = 0; i < actors.length; i++) {
            totalEarned += rewards.getTotalRewardsEarned(actors[i], PROJECT_ID, address(rewardToken));
            totalEarned += rewards.getTotalValidatorRewardsEarned(actors[i], PROJECT_ID, address(rewardToken));
        }

        assertEq(currentProjectRewards + totalEarned, rewardsFunded, "Rewards must be conserved");
    }
}
