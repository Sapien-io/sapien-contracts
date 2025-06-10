// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants} from "src/utils/Constants.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract SapienVault_QADoubleCountingTest is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public qaContract = makeAddr("qaContract");
    address public user1 = makeAddr("user1");

    uint256 public constant MINIMUM_STAKE = 1000 * 1e18;
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant COOLDOWN_PERIOD = 2 days;

    function setUp() public {
        // Deploy token
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        // Deploy SapienVault with proxy
        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector, address(sapienToken), admin, makeAddr("pauseManager"), treasury, qaContract
        );
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        // Grant QA role to the mock QA contract
        vm.prank(admin);
        sapienVault.grantRole(Constants.SAPIEN_QA_ROLE, qaContract);

        // Setup tokens for user and treasury (need enough tokens to show the issue)
        sapienToken.mint(user1, 10_000 * 1e18);
        sapienToken.mint(address(sapienVault), 10_000 * 1e18); // Mint to vault so it can transfer penalties
    }

    /**
     * @notice Test demonstrating the double counting issue in QA penalty calculation
     * @dev This test shows that cooldownAmount is incorrectly added to amount in _calculateApplicablePenalty
     */
    function test_QA_DoubleCounting_Issue() public {
        uint256 stakeAmount = 5000 * 1e18;

        // User stakes tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Wait for unlock period
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // User initiates cooldown for part of their stake
        uint256 cooldownAmount = 2000 * 1e18;
        vm.prank(user1);
        sapienVault.initiateUnstake(cooldownAmount);

        // At this point:
        // - userStake.amount = 5000 * 1e18 (total staked)
        // - userStake.cooldownAmount = 2000 * 1e18 (subset of amount)
        // - Available for penalties should be 5000 * 1e18 (not 7000 * 1e18)

        console.log("=== BEFORE QA PENALTY ===");
        console.log("Total staked amount:", sapienVault.getTotalStaked(user1) / 1e18);
        console.log("Amount in cooldown:", sapienVault.getTotalInCooldown(user1) / 1e18);
        console.log(
            "Active (non-cooldown) amount:",
            (sapienVault.getTotalStaked(user1) - sapienVault.getTotalInCooldown(user1)) / 1e18
        );

        // The issue: Request penalty equal to total staked + some cooldown amount
        // This should NOT be possible, but current implementation allows it due to double counting
        uint256 penaltyAmount = 5500 * 1e18; // Between staked (5000) and staked+cooldown (7000 with bug)

        uint256 treasuryBalanceBefore = sapienToken.balanceOf(treasury);

        // Current implementation incorrectly calculates totalAvailable as:
        // uint256 totalAvailable = uint256(userStake.amount) + uint256(userStake.cooldownAmount);
        // = 5000 + 2000 = 7000 (WRONG - double counting cooldown tokens)

        vm.prank(qaContract);
        uint256 actualPenalty = sapienVault.processQAPenalty(user1, penaltyAmount);

        uint256 treasuryBalanceAfter = sapienToken.balanceOf(treasury);

        console.log("=== AFTER QA PENALTY ===");
        console.log("Requested penalty amount:", penaltyAmount / 1e18);
        console.log("Actual penalty applied:", actualPenalty / 1e18);
        console.log("Treasury received:", (treasuryBalanceAfter - treasuryBalanceBefore) / 1e18);
        console.log("Remaining staked amount:", sapienVault.getTotalStaked(user1) / 1e18);
        console.log("Remaining in cooldown:", sapienVault.getTotalInCooldown(user1) / 1e18);

        // The bug: actualPenalty allows more than actual staked amount
        // With the bug, the penalty can be up to 5500 even though only 5000 tokens are actually staked
        // This demonstrates double counting: cooldown tokens counted as both part of amount AND additional

        console.log("=== PROBLEM ANALYSIS ===");
        console.log("Bug: Penalty allowed:", actualPenalty / 1e18);
        console.log("Correct: Should be max:", stakeAmount / 1e18);
        console.log("The difference shows double counting of cooldown tokens");

        // The actual penalty applied should never exceed the original staked amount
        assertLe(actualPenalty, stakeAmount, "Penalty should not exceed original staked amount");

        // However, with the current bug, it can be up to stakeAmount + cooldownAmount
        // This test will show that actualPenalty = 5500, proving the bug exists
    }

    /**
     * @notice Test showing a specific scenario where the double counting causes incorrect behavior
     */
    function test_QA_DoubleCounting_ProofOfBug() public {
        uint256 stakeAmount = 3000 * 1e18;

        // User stakes tokens
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Wait for unlock and initiate cooldown for ALL tokens
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);
        vm.prank(user1);
        sapienVault.initiateUnstake(stakeAmount); // All 3000 tokens in cooldown

        console.log("=== SCENARIO: ALL TOKENS IN COOLDOWN ===");
        console.log("Total staked:", sapienVault.getTotalStaked(user1) / 1e18);
        console.log("All in cooldown:", sapienVault.getTotalInCooldown(user1) / 1e18);

        // With the bug, the calculation would be:
        // totalAvailable = amount + cooldownAmount = 3000 + 3000 = 6000
        // This is WRONG because cooldownAmount is the same tokens as amount!

        uint256 penaltyAmount = 4000 * 1e18; // More than staked but less than "calculated available"

        vm.prank(qaContract);
        uint256 actualPenalty = sapienVault.processQAPenalty(user1, penaltyAmount);

        console.log("Requested penalty:", penaltyAmount / 1e18);
        console.log("Actual penalty applied:", actualPenalty / 1e18);
        console.log("Remaining stake:", sapienVault.getTotalStaked(user1) / 1e18);

        // The actual penalty should be limited to 3000 (the real staked amount)
        // But with the bug, it tries to apply 4000, which is impossible
        // The function should only allow penalties up to the actual staked amount
        assertEq(actualPenalty, stakeAmount, "Penalty should be capped at actual staked amount");
    }
}
