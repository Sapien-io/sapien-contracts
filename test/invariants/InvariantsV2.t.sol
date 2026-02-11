// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {BaseTest} from "test/BaseTest.t.sol";
import {ProtocolHandler} from "test/handlers/ProtocolHandler.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {SapienCore} from "../../src/SapienCore.sol";
import {ValidationOracle} from "../../src/ValidationOracle.sol";
import {SapienTrust} from "../../src/SapienTrust.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {Rewards} from "../../src/Rewards.sol";
import {CONTRIBUTOR_ROLE, VALIDATOR_ROLE} from "../../src/interface/ISharedTypes.sol";

contract InvariantsV2Test is BaseTest {
    ProtocolHandler public handler;
    bytes32 public constant PROJECT_ID = keccak256("robust-invariant-test");

    function setUp() public override {
        super.setUp();

        // Setup Project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "robust-invariant-test", 100 ether, 50 ether, 3, 1000, "");
        rewardToken.mint(originator, 10000 ether);
        rewardToken.approve(address(core), 10000 ether);
        core.fundProject(PROJECT_ID, 10000 ether, 100);
        vm.stopPrank();

        handler = new ProtocolHandler(core, oracle, trust, vault, rewards, rewardToken, stakeToken, PROJECT_ID);

        // Add some actors
        handler.addContributor(makeAddr("c1"));
        handler.addContributor(makeAddr("c2"));
        handler.addValidator(makeAddr("v1"));
        handler.addValidator(makeAddr("v2"));
        handler.addValidator(makeAddr("v3"));

        targetContract(address(handler));
    }

    // --- Invariant: Solvency ---
    function invariant_RewardsSolvency() public {
        uint256 balance = rewardToken.balanceOf(address(rewards));
        uint256 allocated = rewards.totalAllocated(address(rewardToken));
        assertGe(balance, allocated, "Rewards contract must be solvent");
    }

    // --- Invariant: Vault Integrity ---
    function invariant_VaultStakeIntegrity() public {
        // Sample some users (in a real test we'd track all users in the handler)
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

    // --- Invariant: Reputation Bounds ---
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

    // --- Invariant: Project Accounting ---
    function invariant_ProjectSlotAccounting() public {
        SapienCore.Project memory p = core.getProject(PROJECT_ID);
        uint256 total = p.state.totalQuantityAvailable;
        uint256 submitted = p.state.submittedQuantity;
        uint256 active = p.state.activeClaimedQuantity;
        uint256 rewarded = p.state.rewardedQuantity;

        assertLe(submitted + active, total, "Sum of submitted and active exceeds total");
        assertLe(rewarded, submitted, "Rewarded exceeds submitted");
    }

    // --- Invariant: Reward Conservation ---
    function invariant_RewardConservation() public {
        // Use the actual rewards that were recorded in the project state after funding
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

        // Sum of project rewards + distributed rewards should match initially funded amount
        assertEq(currentProjectRewards + totalEarned, rewardsFunded, "Rewards must be conserved");
    }
}
