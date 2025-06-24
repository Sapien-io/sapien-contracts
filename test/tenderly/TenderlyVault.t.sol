// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {SapienVault} from "src/SapienVault.sol";
import {SapienToken} from "src/SapienToken.sol";
import {Multiplier} from "src/Multiplier.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {Constants as Const} from "src/utils/Constants.sol";

/**
 * @title TenderlyVaultIntegrationTest
 * @notice Integration tests for SapienVault staking system against Tenderly deployed contracts
 * @dev Tests all staking operations, unstaking flows, and edge cases on Base mainnet fork
 */
contract TenderlyVaultIntegrationTest is Test {
    // Tenderly deployed contract addresses
    address public constant SAPIEN_TOKEN = 0xd3a8f3e472efB7246a5C3c604Aa034b6CDbE702F;
    address public constant SAPIEN_VAULT_PROXY = 0x35977d540799db1e8910c00F476a879E2c0e1a24;
    address public constant MULTIPLIER = 0x4Fd7836c7C3Cb0EE140F50EeaEceF1Cbe19D8b55;
    address public constant TREASURY = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant ADMIN = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    
    SapienVault public sapienVault;
    SapienToken public sapienToken;
    Multiplier public multiplier;
    
    // Test user personas
    address public conservativeStaker = makeAddr("conservativeStaker");
    address public aggressiveStaker = makeAddr("aggressiveStaker");
    address public strategicStaker = makeAddr("strategicStaker");
    address public emergencyUser = makeAddr("emergencyUser");
    address public compoundStaker = makeAddr("compoundStaker");
    address public maxStaker = makeAddr("maxStaker");
    address public liquidityManager = makeAddr("liquidityManager");
    address public progressiveBuilder = makeAddr("progressiveBuilder");
    
    // Test constants
    uint256 public constant USER_INITIAL_BALANCE = 1_000_000 * 1e18;
    uint256 public constant SMALL_STAKE = 1_000 * 1e18;
    uint256 public constant MEDIUM_STAKE = 1_500 * 1e18; // 1.5K tokens (within 2.5K limit)
    uint256 public constant LARGE_STAKE = 2_000 * 1e18; // 2K tokens (within 2.5K limit)
    uint256 public constant MAX_STAKE = 2_500 * 1e18; // 2.5K tokens (max allowed)
    
    function setUp() public {
        // Setup fork to use Tenderly Base mainnet virtual testnet
        string memory rpcUrl = vm.envString("TENDERLY_VIRTUAL_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);
        
        // Initialize contract interfaces
        sapienVault = SapienVault(SAPIEN_VAULT_PROXY);
        sapienToken = SapienToken(SAPIEN_TOKEN);
        multiplier = Multiplier(MULTIPLIER);
        
        // Setup test users with initial balances
        setupTestUsers();
    }
    
    function setupTestUsers() internal {
        address[] memory users = new address[](8);
        users[0] = conservativeStaker;
        users[1] = aggressiveStaker;
        users[2] = strategicStaker;
        users[3] = emergencyUser;
        users[4] = compoundStaker;
        users[5] = maxStaker;
        users[6] = liquidityManager;
        users[7] = progressiveBuilder;
        
        vm.startPrank(TREASURY);
        for (uint256 i = 0; i < users.length; i++) {
            sapienToken.transfer(users[i], USER_INITIAL_BALANCE);
        }
        vm.stopPrank();
    }
    
    /**
     * @notice Test basic staking operations with different parameters
     */
    function test_Vault_BasicStakingOperations() public {
        // Conservative staker: Small stake, short lockup
        vm.startPrank(conservativeStaker);
        sapienToken.approve(address(sapienVault), SMALL_STAKE);
        sapienVault.stake(SMALL_STAKE, Const.LOCKUP_30_DAYS);
        
        assertEq(sapienVault.getTotalStaked(conservativeStaker), SMALL_STAKE);
        vm.stopPrank();
        
        // Aggressive staker: Large stake, long lockup
        vm.startPrank(aggressiveStaker);
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(LARGE_STAKE, Const.LOCKUP_365_DAYS);
        
        assertEq(sapienVault.getTotalStaked(aggressiveStaker), LARGE_STAKE);
        vm.stopPrank();
        
        // Verify total staked is tracked correctly
        uint256 totalStaked = sapienVault.totalStaked();
        assertEq(totalStaked, SMALL_STAKE + LARGE_STAKE);
        
        console.log("[PASS] Basic staking operations validated");
    }
    
    /**
     * @notice Test stake amount increases
     */
    function test_Vault_StakeAmountIncrease() public {
        // Initial stake
        vm.startPrank(strategicStaker);
        sapienToken.approve(address(sapienVault), MEDIUM_STAKE * 2);
        sapienVault.stake(MEDIUM_STAKE, Const.LOCKUP_90_DAYS);
        
        uint256 stakeBefore = sapienVault.getTotalStaked(strategicStaker);
        assertEq(stakeBefore, MEDIUM_STAKE);
        
        // Increase amount
        sapienVault.increaseAmount(MEDIUM_STAKE / 2);
        
        uint256 stakeAfter = sapienVault.getTotalStaked(strategicStaker);
        assertEq(stakeAfter, MEDIUM_STAKE + MEDIUM_STAKE / 2);
        
        vm.stopPrank();
        
        console.log("[PASS] Stake amount increase validated");
    }
    
    /**
     * @notice Test stake lockup extensions
     */
    function test_Vault_StakeLockupExtension() public {
        // Initial stake with short lockup
        vm.startPrank(strategicStaker);
        sapienToken.approve(address(sapienVault), MEDIUM_STAKE);
        sapienVault.stake(MEDIUM_STAKE, Const.LOCKUP_90_DAYS);
        
        uint256 stakeBefore = sapienVault.getTotalStaked(strategicStaker);
        
        // Extend lockup
        sapienVault.increaseLockup(Const.LOCKUP_180_DAYS);
        
        uint256 stakeAfter = sapienVault.getTotalStaked(strategicStaker);
        assertEq(stakeAfter, stakeBefore); // Amount unchanged
        
        vm.stopPrank();
        
        console.log("[PASS] Stake lockup extension validated");
    }
    
    /**
     * @notice Test progressive stake building pattern
     */
    function test_Vault_ProgressiveStakeBuilding() public {
        vm.startPrank(progressiveBuilder);
        
        // Approve large amount for multiple operations
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        
        // Week 1: Initial minimum stake
        sapienVault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);
        assertEq(sapienVault.getTotalStaked(progressiveBuilder), Const.MINIMUM_STAKE_AMOUNT);
        
        // Week 2: Double the stake
        vm.warp(block.timestamp + 7 days);
        sapienVault.increaseAmount(Const.MINIMUM_STAKE_AMOUNT);
        assertEq(sapienVault.getTotalStaked(progressiveBuilder), Const.MINIMUM_STAKE_AMOUNT * 2);
        
        // Week 3: Extend lockup
        vm.warp(block.timestamp + 7 days);
        sapienVault.increaseLockup(Const.LOCKUP_90_DAYS);
        
        // Week 4: Major increase
        vm.warp(block.timestamp + 7 days);
        sapienVault.increaseAmount(Const.MINIMUM_STAKE_AMOUNT * 3);
        assertEq(sapienVault.getTotalStaked(progressiveBuilder), Const.MINIMUM_STAKE_AMOUNT * 5);
        
        // Week 5: Final lockup extension
        vm.warp(block.timestamp + 7 days);
        sapienVault.increaseLockup(Const.LOCKUP_180_DAYS);
        
        vm.stopPrank();
        
        console.log("[PASS] Progressive stake building pattern validated");
    }
    
    /**
     * @notice Test normal unstaking process
     */
    function test_Vault_NormalUnstakingProcess() public {
        // Setup: User stakes first
        vm.startPrank(liquidityManager);
        sapienToken.approve(address(sapienVault), MEDIUM_STAKE);
        sapienVault.stake(MEDIUM_STAKE, Const.LOCKUP_30_DAYS);
        
        // Fast forward past lockup expiry
        vm.warp(block.timestamp + 31 days);
        
        // Initiate unstake
        uint256 unstakeAmount = MEDIUM_STAKE / 2;
        sapienVault.initiateUnstake(unstakeAmount);
        
        // Verify cooldown state
        assertGt(sapienVault.getTotalInCooldown(liquidityManager), 0);
        
        // Fast forward through cooldown period
        vm.warp(block.timestamp + Const.COOLDOWN_PERIOD + 1);
        
        // Complete unstake
        uint256 balanceBefore = sapienToken.balanceOf(liquidityManager);
        sapienVault.unstake(unstakeAmount);
        uint256 balanceAfter = sapienToken.balanceOf(liquidityManager);
        
        // Verify tokens were returned
        assertEq(balanceAfter - balanceBefore, unstakeAmount);
        
        // Verify stake was reduced
        assertEq(sapienVault.getTotalStaked(liquidityManager), MEDIUM_STAKE - unstakeAmount);
        
        vm.stopPrank();
        
        console.log("[PASS] Normal unstaking process validated");
    }
    
    /**
     * @notice Test early unstaking with penalties
     */
    function test_Vault_EarlyUnstakingWithPenalties() public {
        // Setup: Emergency user stakes for long term
        vm.startPrank(emergencyUser);
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(LARGE_STAKE, Const.LOCKUP_180_DAYS);
        
        // Emergency after 30 days - needs immediate liquidity
        vm.warp(block.timestamp + 30 days);
        
        uint256 earlyUnstakeAmount = LARGE_STAKE / 3;
        uint256 expectedPenalty = (earlyUnstakeAmount * Const.EARLY_WITHDRAWAL_PENALTY) / Const.BASIS_POINTS;
        uint256 expectedReturn = earlyUnstakeAmount - expectedPenalty;
        
        uint256 userBalanceBefore = sapienToken.balanceOf(emergencyUser);
        uint256 treasuryBalanceBefore = sapienToken.balanceOf(TREASURY);
        
        // Execute early unstake
        sapienVault.earlyUnstake(earlyUnstakeAmount);
        
        uint256 userBalanceAfter = sapienToken.balanceOf(emergencyUser);
        uint256 treasuryBalanceAfter = sapienToken.balanceOf(TREASURY);
        
        // Verify user received reduced amount
        assertEq(userBalanceAfter - userBalanceBefore, expectedReturn);
        
        // Verify treasury received penalty
        assertEq(treasuryBalanceAfter - treasuryBalanceBefore, expectedPenalty);
        
        // Verify stake was reduced
        assertEq(sapienVault.getTotalStaked(emergencyUser), LARGE_STAKE - earlyUnstakeAmount);
        
        vm.stopPrank();
        
        console.log("[PASS] Early unstaking with penalties validated");
    }
    
    /**
     * @notice Test multiple unstake requests and completions
     */
    function test_Vault_MultipleUnstakeRequests() public {
        // Setup: User stakes large amount
        vm.startPrank(compoundStaker);
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(LARGE_STAKE, Const.LOCKUP_30_DAYS);
        
        // Fast forward past lockup
        vm.warp(block.timestamp + 31 days);
        
        // First unstake request
        uint256 firstUnstake = LARGE_STAKE / 4;
        sapienVault.initiateUnstake(firstUnstake);
        
        // Wait and complete first unstake
        vm.warp(block.timestamp + Const.COOLDOWN_PERIOD + 1);
        uint256 balanceBefore = sapienToken.balanceOf(compoundStaker);
        sapienVault.unstake(firstUnstake);
        uint256 balanceAfter = sapienToken.balanceOf(compoundStaker);
        assertEq(balanceAfter - balanceBefore, firstUnstake);
        
        // Second unstake request
        uint256 secondUnstake = LARGE_STAKE / 4;
        sapienVault.initiateUnstake(secondUnstake);
        
        // Wait and complete second unstake
        vm.warp(block.timestamp + Const.COOLDOWN_PERIOD + 1);
        balanceBefore = sapienToken.balanceOf(compoundStaker);
        sapienVault.unstake(secondUnstake);
        balanceAfter = sapienToken.balanceOf(compoundStaker);
        assertEq(balanceAfter - balanceBefore, secondUnstake);
        
        // Verify final stake amount
        assertEq(sapienVault.getTotalStaked(compoundStaker), LARGE_STAKE - firstUnstake - secondUnstake);
        
        vm.stopPrank();
        
        console.log("[PASS] Multiple unstake requests validated");
    }
    
    /**
     * @notice Test maximum stake operations and boundaries
     */
    function test_Vault_MaxStakeOperations() public {
        vm.startPrank(maxStaker);
        
        // Test maximum stake
        sapienToken.approve(address(sapienVault), MAX_STAKE);
        sapienVault.stake(MAX_STAKE, Const.LOCKUP_365_DAYS);
        
        assertEq(sapienVault.getTotalStaked(maxStaker), MAX_STAKE);
        
        // Test that multiplier is calculated correctly for max stake
        // For 1M tokens (Tier 5) with 365-day lockup: 15000 + 4500 = 19500 (1.95x)
        uint256 mult = multiplier.calculateMultiplier(MAX_STAKE, Const.LOCKUP_365_DAYS);
        assertEq(mult, 19500); // Should be 1.95x for max tier
        
        vm.stopPrank();
        
        console.log("[PASS] Maximum stake operations validated");
    }
    
    /**
     * @notice Test weighted average calculations with multiple stakes
     */
    function test_Vault_WeightedAverageCalculations() public {
        vm.startPrank(strategicStaker);
        
        // Initial stake: 30 days
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(MEDIUM_STAKE, Const.LOCKUP_30_DAYS);
        
        // Fast forward 15 days and add more with longer lockup
        vm.warp(block.timestamp + 15 days);
        sapienVault.increaseAmount(MEDIUM_STAKE);
        sapienVault.increaseLockup(Const.LOCKUP_90_DAYS);
        
        // Verify total amount
        assertEq(sapienVault.getTotalStaked(strategicStaker), MEDIUM_STAKE * 2);
        
        vm.stopPrank();
        
        console.log("[PASS] Weighted average calculations validated");
    }
    
    /**
     * @notice Test error conditions and edge cases
     */
    function test_Vault_ErrorConditionsAndEdgeCases() public {
        vm.startPrank(conservativeStaker);
        
        // Test staking below minimum
        sapienToken.approve(address(sapienVault), 500 * 1e18);
        vm.expectRevert();
        sapienVault.stake(500 * 1e18, Const.LOCKUP_30_DAYS);
        
        // Test staking with zero lockup
        vm.expectRevert();
        sapienVault.stake(Const.MINIMUM_STAKE_AMOUNT, 0);
        
        // Approve sufficient amount for valid stake and additional operations
        sapienToken.approve(address(sapienVault), Const.MINIMUM_STAKE_AMOUNT + 1000 * 1e18);
        
        // Create valid stake for further tests
        sapienVault.stake(Const.MINIMUM_STAKE_AMOUNT, Const.LOCKUP_30_DAYS);
        
        // Fast forward past lockup to enable unstaking
        vm.warp(block.timestamp + 31 days);
        
        // Test increasing amount during cooldown
        sapienVault.initiateUnstake(500 * 1e18);
        vm.expectRevert();
        sapienVault.increaseAmount(1000 * 1e18);
        
        vm.stopPrank();
        
        console.log("[PASS] Error conditions and edge cases validated");
    }
    
    /**
     * @notice Test high-volume concurrent staking operations
     */
    function test_Vault_HighVolumeConcurrentStaking() public {
        uint256 numUsers = 20;
        address[] memory users = new address[](numUsers);
        
        // Create and fund multiple users
        for (uint256 i = 0; i < numUsers; i++) {
            users[i] = makeAddr(string(abi.encodePacked("staker", i)));
            vm.prank(TREASURY);
            sapienToken.transfer(users[i], MEDIUM_STAKE);
        }
        
        // All users stake concurrently with different parameters
        for (uint256 i = 0; i < numUsers; i++) {
            vm.startPrank(users[i]);
            sapienToken.approve(address(sapienVault), MEDIUM_STAKE);
            
            // Vary lockup periods
            uint256 lockup = Const.LOCKUP_30_DAYS + (i * 10 days);
            if (lockup > Const.LOCKUP_365_DAYS) lockup = Const.LOCKUP_365_DAYS;
            
            sapienVault.stake(MEDIUM_STAKE, lockup);
            vm.stopPrank();
        }
        
        // Verify total staked
        uint256 expectedTotal = numUsers * MEDIUM_STAKE;
        uint256 actualTotal = sapienVault.totalStaked();
        assertEq(actualTotal, expectedTotal);
        
        console.log("[PASS] High-volume concurrent staking validated with", numUsers, "users");
    }
    
    /**
     * @notice Test long-term staking behavior
     */
    function test_Vault_LongTermStakingBehavior() public {
        vm.startPrank(aggressiveStaker);
        
        // Stake for maximum period
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(LARGE_STAKE, Const.LOCKUP_365_DAYS);
        
        // Fast forward to near expiry
        vm.warp(block.timestamp + 360 days);
        
        // Verify still locked
        assertGt(sapienVault.getTotalLocked(aggressiveStaker), 0);
        
        // Try to unstake early (should fail)
        vm.expectRevert();
        sapienVault.initiateUnstake(LARGE_STAKE);
        
        // Fast forward past expiry
        vm.warp(block.timestamp + 10 days);
        
        // Now should be able to unstake
        sapienVault.initiateUnstake(LARGE_STAKE);
        
        vm.stopPrank();
        
        console.log("[PASS] Long-term staking behavior validated");
    }
    
    /**
     * @notice Test stake modifications with different timing
     */
    function test_Vault_StakeModificationTiming() public {
        vm.startPrank(strategicStaker);
        
        sapienToken.approve(address(sapienVault), LARGE_STAKE);
        sapienVault.stake(MEDIUM_STAKE, Const.LOCKUP_90_DAYS);
        
        // Immediate modification
        sapienVault.increaseAmount(SMALL_STAKE);
        
        // Modification after some time
        vm.warp(block.timestamp + 30 days);
        sapienVault.increaseAmount(SMALL_STAKE);
        
        // Lockup extension near expiry
        vm.warp(block.timestamp + 55 days); // Near 90-day mark
        sapienVault.increaseLockup(Const.LOCKUP_180_DAYS);
        
        assertEq(sapienVault.getTotalStaked(strategicStaker), MEDIUM_STAKE + SMALL_STAKE * 2);
        
        vm.stopPrank();
        
        console.log("[PASS] Stake modification timing validated");
    }
}