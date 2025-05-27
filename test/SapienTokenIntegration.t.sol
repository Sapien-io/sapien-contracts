// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { SapienToken } from "../src/SapienToken.sol";

contract SapienTokenIntegrationTest is Test {
    SapienToken public token;
    
    address public admin;
    address public multisig;
    address public pauser1;
    address public pauser2;
    address public user1;
    address public user2;
    address public user3;
    
    // Token allocation constants (from CSV)
    uint256 public constant INVESTORS_ALLOCATION = 304_500_000 * 10**18;
    uint256 public constant TEAM_ADVISORS_ALLOCATION = 165_500_000 * 10**18;
    uint256 public constant TRAINER_COMP_ALLOCATION = 150_000_000 * 10**18;
    uint256 public constant AIRDROPS_ALLOCATION = 130_000_000 * 10**18;
    uint256 public constant FOUNDATION_TREASURY_ALLOCATION = 130_000_000 * 10**18;
    uint256 public constant LIQUIDITY_ALLOCATION = 120_000_000 * 10**18;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    
    function setUp() public {
        admin = makeAddr("admin");
        multisig = makeAddr("multisig");
        pauser1 = makeAddr("pauser1");
        pauser2 = makeAddr("pauser2");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        
        // Deploy token with admin
        token = new SapienToken(admin);
    }
    
    // ============ Token Distribution Simulation ============
    
    function test_TokenDistribution_Simulation() public {
        vm.startPrank(admin);
        
        // Simulate token distribution according to allocations
        address investorsWallet = makeAddr("investors");
        address teamWallet = makeAddr("team");
        address trainerWallet = makeAddr("trainer");
        address airdropWallet = makeAddr("airdrop");
        address foundationWallet = makeAddr("foundation");
        address liquidityWallet = makeAddr("liquidity");
        
        // Distribute tokens
        token.transfer(investorsWallet, INVESTORS_ALLOCATION);
        token.transfer(teamWallet, TEAM_ADVISORS_ALLOCATION);
        token.transfer(trainerWallet, TRAINER_COMP_ALLOCATION);
        token.transfer(airdropWallet, AIRDROPS_ALLOCATION);
        token.transfer(foundationWallet, FOUNDATION_TREASURY_ALLOCATION);
        token.transfer(liquidityWallet, LIQUIDITY_ALLOCATION);
        
        // Verify allocations
        assertEq(token.balanceOf(investorsWallet), INVESTORS_ALLOCATION);
        assertEq(token.balanceOf(teamWallet), TEAM_ADVISORS_ALLOCATION);
        assertEq(token.balanceOf(trainerWallet), TRAINER_COMP_ALLOCATION);
        assertEq(token.balanceOf(airdropWallet), AIRDROPS_ALLOCATION);
        assertEq(token.balanceOf(foundationWallet), FOUNDATION_TREASURY_ALLOCATION);
        assertEq(token.balanceOf(liquidityWallet), LIQUIDITY_ALLOCATION);
        
        // Admin should have no tokens left
        assertEq(token.balanceOf(admin), 0);
        
        // Total supply should remain constant
        assertEq(token.totalSupply(), MAX_SUPPLY);
        
        vm.stopPrank();
    }
    
    // ============ Multi-Role Management ============
    
    function test_MultiRoleManagement() public {
        vm.startPrank(admin);
        
        // Grant PAUSER_ROLE to multiple addresses
        token.grantRole(PAUSER_ROLE, pauser1);
        token.grantRole(PAUSER_ROLE, pauser2);
        
        // Verify roles
        assertTrue(token.hasRole(PAUSER_ROLE, admin));
        assertTrue(token.hasRole(PAUSER_ROLE, pauser1));
        assertTrue(token.hasRole(PAUSER_ROLE, pauser2));
        
        vm.stopPrank();
        
        // Test that any pauser can pause
        vm.prank(pauser1);
        token.pause();
        assertTrue(token.paused());
        
        // Test that any pauser can unpause
        vm.prank(pauser2);
        token.unpause();
        assertFalse(token.paused());
        
        // Test role revocation
        vm.prank(admin);
        token.revokeRole(PAUSER_ROLE, pauser1);
        assertFalse(token.hasRole(PAUSER_ROLE, pauser1));
        
        // Revoked pauser can't pause anymore
        vm.startPrank(pauser1);
        vm.expectRevert();
        token.pause();
        vm.stopPrank();
    }
    
    // ============ Emergency Scenarios ============
    
    function test_EmergencyPause_DuringTransfers() public {
        uint256 amount = 1000 * 10**18;
        
        // Setup: Admin transfers some tokens to user1
        vm.prank(admin);
        token.transfer(user1, amount);
        
        // User1 approves user2 to spend tokens
        vm.prank(user1);
        token.approve(user2, amount);
        
        // Admin pauses the contract
        vm.prank(admin);
        token.pause();
        
        // All transfers should fail when paused
        vm.startPrank(user1);
        vm.expectRevert();
        token.transfer(user2, 100);
        vm.stopPrank();
        
        vm.startPrank(user2);
        vm.expectRevert();
        token.transferFrom(user1, user3, 100);
        vm.stopPrank();
        
        // Unpause and transfers should work again
        vm.prank(admin);
        token.unpause();
        
        vm.prank(user1);
        bool success = token.transfer(user2, 100);
        assertTrue(success);
        assertEq(token.balanceOf(user2), 100);
    }
    
    // ============ Permit Integration Tests ============
    
    function test_Permit_IntegrationWithTransfers() public {
        uint256 amount = 1000 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Create permit signature
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        
        // Give owner some tokens
        vm.prank(admin);
        token.transfer(owner, amount);
        
        uint256 nonce = token.nonces(owner);
        
        // Create permit hash
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner,
                user1,
                amount,
                nonce,
                deadline
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        
        // Execute permit
        token.permit(owner, user1, amount, deadline, v, r, s);
        
        // Now user1 can transfer from owner
        vm.prank(user1);
        bool success = token.transferFrom(owner, user2, amount);
        assertTrue(success);
        assertEq(token.balanceOf(user2), amount);
        assertEq(token.balanceOf(owner), 0);
    }
    
    // ============ Gas Optimization Tests ============
    
    function test_BatchTransfers_GasEfficiency() public {
        uint256 amount = 1000 * 10**18;
        address[] memory recipients = new address[](5);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;
        recipients[3] = makeAddr("user4");
        recipients[4] = makeAddr("user5");
        
        vm.startPrank(admin);
        
        uint256 gasBefore = gasleft();
        
        // Simulate batch transfers
        for (uint256 i = 0; i < recipients.length; i++) {
            token.transfer(recipients[i], amount);
        }
        
        uint256 gasUsed = gasBefore - gasleft();
        console.log("Gas used for 5 transfers:", gasUsed);
        
        // Verify all transfers
        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(token.balanceOf(recipients[i]), amount);
        }
        
        vm.stopPrank();
    }
    
    // ============ Role Transition Scenarios ============
    
    function test_AdminRoleTransition() public {
        address newAdmin = makeAddr("newAdmin");
        
        vm.startPrank(admin);
        
        // Grant admin role to new admin
        token.grantRole(DEFAULT_ADMIN_ROLE, newAdmin);
        
        // New admin can now grant roles
        vm.stopPrank();
        vm.startPrank(newAdmin);
        
        token.grantRole(PAUSER_ROLE, user1);
        assertTrue(token.hasRole(PAUSER_ROLE, user1));
        
        // Original admin can renounce their role
        vm.stopPrank();
        vm.startPrank(admin);
        
        token.renounceRole(DEFAULT_ADMIN_ROLE, admin);
        assertFalse(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
        
        // Original admin can no longer grant roles
        vm.expectRevert();
        token.grantRole(PAUSER_ROLE, user2);
        
        vm.stopPrank();
    }
    
    // ============ Edge Cases ============
    
    function test_MaxApproval() public {
        vm.startPrank(admin);
        
        // Test maximum uint256 approval
        bool success = token.approve(user1, type(uint256).max);
        assertTrue(success);
        assertEq(token.allowance(admin, user1), type(uint256).max);
        
        vm.stopPrank();
    }
    
    function test_ZeroValueTransfers() public {
        vm.startPrank(admin);
        
        // Zero value transfers should succeed
        bool success = token.transfer(user1, 0);
        assertTrue(success);
        
        success = token.approve(user1, 0);
        assertTrue(success);
        
        vm.stopPrank();
        
        vm.startPrank(user1);
        success = token.transferFrom(admin, user2, 0);
        assertTrue(success);
        vm.stopPrank();
    }
    
    function test_SelfTransfer() public {
        uint256 amount = 1000 * 10**18;
        
        vm.startPrank(admin);
        
        uint256 balanceBefore = token.balanceOf(admin);
        bool success = token.transfer(admin, amount);
        assertTrue(success);
        
        // Balance should remain the same
        assertEq(token.balanceOf(admin), balanceBefore);
        
        vm.stopPrank();
    }
    
    // ============ Stress Tests ============
    
    function test_ManySmallTransfers() public {
        uint256 smallAmount = 1 * 10**18; // 1 token
        
        vm.startPrank(admin);
        
        // Make 100 small transfers
        for (uint256 i = 0; i < 100; i++) {
            address recipient = address(uint160(i + 1000)); // Generate unique addresses
            token.transfer(recipient, smallAmount);
            assertEq(token.balanceOf(recipient), smallAmount);
        }
        
        vm.stopPrank();
    }
    
    function test_PauseUnpauseCycle() public {
        vm.startPrank(admin);
        
        // Rapid pause/unpause cycles
        for (uint256 i = 0; i < 10; i++) {
            token.pause();
            assertTrue(token.paused());
            
            token.unpause();
            assertFalse(token.paused());
        }
        
        vm.stopPrank();
    }
    
    // ============ Invariant Tests ============
    
    function test_TotalSupplyInvariant() public {
        uint256 amount = 1000 * 10**18;
        
        vm.startPrank(admin);
        
        // Initial total supply
        uint256 initialSupply = token.totalSupply();
        
        // Make various transfers
        token.transfer(user1, amount);
        token.transfer(user2, amount);
        
        vm.stopPrank();
        
        vm.prank(user1);
        token.transfer(user3, amount / 2);
        
        // Total supply should never change
        assertEq(token.totalSupply(), initialSupply);
        assertEq(token.totalSupply(), MAX_SUPPLY);
    }
} 