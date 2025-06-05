// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SapienToken} from "src/SapienToken.sol";
import {Constants as Const} from "src/utils/Constants.sol";

/**
 * @title TenderlyTokenIntegrationTest
 * @notice Integration tests for SapienToken against Tenderly deployed contracts
 * @dev Tests all token operations, ERC20 functionality, and edge cases on Base mainnet fork
 */
contract TenderlyTokenIntegrationTest is Test {
    // Tenderly deployed contract addresses
    address public constant SAPIEN_TOKEN = 0xd3a8f3e472efB7246a5C3c604Aa034b6CDbE702F;
    address public constant TREASURY = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    
    SapienToken public sapienToken;
    
    // Test users
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public charlie = makeAddr("charlie");
    address public dave = makeAddr("dave");
    
    // Test constants
    uint256 public constant TRANSFER_AMOUNT = 1000 * 1e18;
    uint256 public constant LARGE_AMOUNT = 100_000 * 1e18;
    uint256 public constant USER_INITIAL_BALANCE = 500_000 * 1e18;
    
    function setUp() public {
        // Setup fork to use Tenderly Base mainnet virtual testnet
        string memory rpcUrl = vm.envString("TENDERLY_VIRTUAL_TESTNET_RPC_URL");
        vm.createSelectFork(rpcUrl);
        
        // Initialize contract interface
        sapienToken = SapienToken(SAPIEN_TOKEN);
        
        // Setup test users with initial balances
        setupTestUsers();
    }
    
    function setupTestUsers() internal {
        address[] memory users = new address[](4);
        users[0] = alice;
        users[1] = bob;
        users[2] = charlie;
        users[3] = dave;
        
        // Transfer tokens from treasury to test users
        vm.startPrank(TREASURY);
        for (uint256 i = 0; i < users.length; i++) {
            sapienToken.transfer(users[i], USER_INITIAL_BALANCE);
        }
        vm.stopPrank();
    }
    
    /**
     * @notice Test basic ERC20 functionality
     */
    function test_Token_BasicERC20Operations() public {
        // Test balanceOf
        assertEq(sapienToken.balanceOf(alice), USER_INITIAL_BALANCE);
        
        // Test transfer
        vm.prank(alice);
        sapienToken.transfer(bob, TRANSFER_AMOUNT);
        
        assertEq(sapienToken.balanceOf(alice), USER_INITIAL_BALANCE - TRANSFER_AMOUNT);
        assertEq(sapienToken.balanceOf(bob), USER_INITIAL_BALANCE + TRANSFER_AMOUNT);
        
        // Test approve and allowance
        vm.prank(alice);
        sapienToken.approve(bob, TRANSFER_AMOUNT * 2);
        
        assertEq(sapienToken.allowance(alice, bob), TRANSFER_AMOUNT * 2);
        
        // Test transferFrom
        vm.prank(bob);
        sapienToken.transferFrom(alice, charlie, TRANSFER_AMOUNT);
        
        assertEq(sapienToken.balanceOf(alice), USER_INITIAL_BALANCE - TRANSFER_AMOUNT * 2);
        assertEq(sapienToken.balanceOf(charlie), USER_INITIAL_BALANCE + TRANSFER_AMOUNT);
        assertEq(sapienToken.allowance(alice, bob), TRANSFER_AMOUNT);
        
        console.log("[PASS] Basic ERC20 operations validated");
    }
    
    /**
     * @notice Test ERC20 Permit functionality for gasless approvals
     */
    function test_Token_ERC20Permit() public {
        uint256 alicePrivateKey = 0x1234;
        address alicePermit = vm.addr(alicePrivateKey);
        
        // Fund alice for permit testing
        vm.prank(TREASURY);
        sapienToken.transfer(alicePermit, USER_INITIAL_BALANCE);
        
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = sapienToken.nonces(alicePermit);
        
        // Create permit signature
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
            alicePermit,
            bob,
            TRANSFER_AMOUNT,
            nonce,
            deadline
        ));
        
        bytes32 domainSeparator = sapienToken.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        
        // Execute permit
        sapienToken.permit(alicePermit, bob, TRANSFER_AMOUNT, deadline, v, r, s);
        
        // Verify approval was set
        assertEq(sapienToken.allowance(alicePermit, bob), TRANSFER_AMOUNT);
        
        // Use the approval
        vm.prank(bob);
        sapienToken.transferFrom(alicePermit, charlie, TRANSFER_AMOUNT);
        
        assertEq(sapienToken.balanceOf(charlie), USER_INITIAL_BALANCE + TRANSFER_AMOUNT * 2);
        
        console.log("[PASS] ERC20 Permit functionality validated");
    }
    
    /**
     * @notice Test batch transfer operations
     */
    function test_Token_BatchTransfers() public {
        address[] memory recipients = new address[](5);
        recipients[0] = bob;
        recipients[1] = charlie;
        recipients[2] = dave;
        recipients[3] = makeAddr("user5");
        recipients[4] = makeAddr("user6");
        
        uint256 transferAmount = 10_000 * 1e18;
        
        vm.startPrank(alice);
        
        // Perform batch transfers
        for (uint256 i = 0; i < recipients.length; i++) {
            sapienToken.transfer(recipients[i], transferAmount);
        }
        
        vm.stopPrank();
        
        // Verify all transfers succeeded
        uint256 expectedAliceBalance = USER_INITIAL_BALANCE - (transferAmount * recipients.length);
        assertEq(sapienToken.balanceOf(alice), expectedAliceBalance);
        
        for (uint256 i = 0; i < 3; i++) {
            uint256 expectedBalance = USER_INITIAL_BALANCE + transferAmount;
            if (i == 1) expectedBalance += TRANSFER_AMOUNT * 2; // Charlie received extra in previous tests
            assertEq(sapienToken.balanceOf(recipients[i]), expectedBalance);
        }
        
        console.log("[PASS] Batch transfer operations validated");
    }
    
    /**
     * @notice Test maximum approval patterns
     */
    function test_Token_MaxApprovalPatterns() public {
        vm.startPrank(alice);
        
        // Test maximum approval
        sapienToken.approve(bob, type(uint256).max);
        assertEq(sapienToken.allowance(alice, bob), type(uint256).max);
        
        // Transfer should not decrease max allowance
        vm.stopPrank();
        vm.prank(bob);
        sapienToken.transferFrom(alice, charlie, TRANSFER_AMOUNT);
        
        assertEq(sapienToken.allowance(alice, bob), type(uint256).max);
        
        // Reset approval to zero
        vm.prank(alice);
        sapienToken.approve(bob, 0);
        assertEq(sapienToken.allowance(alice, bob), 0);
        
        console.log("[PASS] Maximum approval patterns validated");
    }
    
    /**
     * @notice Test edge cases and error conditions
     */
    function test_Token_EdgeCasesAndErrors() public {
        // Test insufficient balance transfer
        vm.prank(alice);
        vm.expectRevert();
        sapienToken.transfer(bob, USER_INITIAL_BALANCE * 2);
        
        // Test insufficient allowance transferFrom
        vm.prank(alice);
        sapienToken.approve(bob, TRANSFER_AMOUNT);
        
        vm.prank(bob);
        vm.expectRevert();
        sapienToken.transferFrom(alice, charlie, TRANSFER_AMOUNT * 2);
        
        // Test zero amount operations (should succeed)
        vm.prank(alice);
        bool success = sapienToken.transfer(bob, 0);
        assertTrue(success);
        
        vm.prank(alice);
        success = sapienToken.approve(bob, 0);
        assertTrue(success);
        
        // Test self transfer
        uint256 balanceBefore = sapienToken.balanceOf(alice);
        vm.prank(alice);
        sapienToken.transfer(alice, TRANSFER_AMOUNT);
        assertEq(sapienToken.balanceOf(alice), balanceBefore);
        
        console.log("[PASS] Edge cases and error conditions validated");
    }
    
    /**
     * @notice Test token metadata and constants
     */
    function test_Token_MetadataAndConstants() public {
        // Test token metadata
        assertEq(sapienToken.name(), "Sapien");
        assertEq(sapienToken.symbol(), "SAPIEN");
        assertEq(sapienToken.decimals(), 18);
        
        // Test total supply
        assertEq(sapienToken.totalSupply(), Const.TOTAL_SUPPLY);
        
        // Test initial distribution to treasury
        uint256 treasuryBalance = sapienToken.balanceOf(TREASURY);
        assertGt(treasuryBalance, 0);
        
        console.log("[PASS] Token metadata and constants validated");
    }
    
    /**
     * @notice Test high-volume token operations
     */
    function test_Token_HighVolumeOperations() public {
        uint256 numOperations = 50;
        uint256 operationAmount = 1000 * 1e18;
        
        // Create multiple users for high-volume testing
        address[] memory users = new address[](numOperations);
        for (uint256 i = 0; i < numOperations; i++) {
            users[i] = makeAddr(string(abi.encodePacked("volumeUser", i)));
        }
        
        // Fund users from treasury
        vm.startPrank(TREASURY);
        for (uint256 i = 0; i < numOperations; i++) {
            sapienToken.transfer(users[i], operationAmount * 2);
        }
        vm.stopPrank();
        
        // Perform rapid transfers between users
        for (uint256 i = 0; i < numOperations - 1; i++) {
            vm.prank(users[i]);
            sapienToken.transfer(users[i + 1], operationAmount);
        }
        
        // Verify final balances
        assertEq(sapienToken.balanceOf(users[0]), operationAmount);
        assertEq(sapienToken.balanceOf(users[numOperations - 1]), operationAmount * 3);
        
        console.log("[PASS] High-volume operations validated with", numOperations, "transactions");
    }
    
    /**
     * @notice Test token conservation across all operations
     */
    function test_Token_TokenConservation() public {
        uint256 totalSupplyBefore = sapienToken.totalSupply();
        
        // Perform various operations
        vm.startPrank(alice);
        sapienToken.transfer(bob, TRANSFER_AMOUNT);
        sapienToken.approve(charlie, TRANSFER_AMOUNT);
        vm.stopPrank();
        
        vm.prank(charlie);
        sapienToken.transferFrom(alice, dave, TRANSFER_AMOUNT);
        
        // Total supply should remain unchanged
        uint256 totalSupplyAfter = sapienToken.totalSupply();
        assertEq(totalSupplyBefore, totalSupplyAfter);
        
        console.log("[PASS] Token conservation validated");
    }
    
    /**
     * @notice Test permit with expired deadline
     */
    function test_Token_ExpiredPermit() public {
        uint256 alicePrivateKey = 0x5678;
        address alicePermit = vm.addr(alicePrivateKey);
        
        vm.prank(TREASURY);
        sapienToken.transfer(alicePermit, USER_INITIAL_BALANCE);
        
        uint256 deadline = block.timestamp - 1; // Expired deadline
        uint256 nonce = sapienToken.nonces(alicePermit);
        
        bytes32 structHash = keccak256(abi.encode(
            keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
            alicePermit,
            bob,
            TRANSFER_AMOUNT,
            nonce,
            deadline
        ));
        
        bytes32 domainSeparator = sapienToken.DOMAIN_SEPARATOR();
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        
        // Should revert due to expired deadline
        vm.expectRevert();
        sapienToken.permit(alicePermit, bob, TRANSFER_AMOUNT, deadline, v, r, s);
        
        console.log("[PASS] Expired permit rejection validated");
    }
    
    /**
     * @notice Test multiple approvals and resets
     */
    function test_Token_MultipleApprovals() public {
        vm.startPrank(alice);
        
        // Set initial approval
        sapienToken.approve(bob, TRANSFER_AMOUNT);
        assertEq(sapienToken.allowance(alice, bob), TRANSFER_AMOUNT);
        
        // Increase approval
        sapienToken.approve(bob, TRANSFER_AMOUNT * 2);
        assertEq(sapienToken.allowance(alice, bob), TRANSFER_AMOUNT * 2);
        
        // Reset to zero
        sapienToken.approve(bob, 0);
        assertEq(sapienToken.allowance(alice, bob), 0);
        
        // Set new approval
        sapienToken.approve(bob, TRANSFER_AMOUNT / 2);
        assertEq(sapienToken.allowance(alice, bob), TRANSFER_AMOUNT / 2);
        
        vm.stopPrank();
        
        console.log("[PASS] Multiple approvals and resets validated");
    }
}