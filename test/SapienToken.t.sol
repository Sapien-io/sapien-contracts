// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import { Test, console } from "forge-std/Test.sol";
import { SapienToken } from "../src/SapienToken.sol";
import { ISapienToken } from "../src/interfaces/ISapienToken.sol";
import { IERC20 } from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import { IERC20Permit } from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/IERC20Permit.sol";
import { IAccessControl } from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";

contract SapienTokenTest is Test {
    SapienToken public token;
    
    address public admin;
    address public pauser;
    address public user1;
    address public user2;
    address public zeroAddress = address(0);
    
    // Constants
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10**18;
    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    
    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);
    event Paused(address account);
    event Unpaused(address account);
    
    // Custom errors
    error ZeroAddressOwner();
    
    function setUp() public {
        admin = makeAddr("admin");
        pauser = makeAddr("pauser");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        
        // Deploy token with admin
        token = new SapienToken(admin);
    }
    
    // ============ Constructor Tests ============
    
    function test_Constructor_Success() public view {
        // Check basic ERC20 properties
        assertEq(token.name(), "Sapien Token");
        assertEq(token.symbol(), "SAPIEN");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), MAX_SUPPLY);
        assertEq(token.maxSupply(), MAX_SUPPLY);
        
        // Check admin received all tokens
        assertEq(token.balanceOf(admin), MAX_SUPPLY);
        
        // Check roles
        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertTrue(token.hasRole(PAUSER_ROLE, admin));
        
        // Check initial state
        assertFalse(token.paused());
    }
    
    function test_Constructor_RevertZeroAddress() public {
        vm.expectRevert(ZeroAddressOwner.selector);
        new SapienToken(zeroAddress);
    }
    
    // ============ ERC20 Basic Functionality Tests ============
    
    function test_Transfer_Success() public {
        uint256 amount = 1000 * 10**18;
        
        vm.startPrank(admin);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(admin, user1, amount);
        
        bool success = token.transfer(user1, amount);
        assertTrue(success);
        
        assertEq(token.balanceOf(user1), amount);
        assertEq(token.balanceOf(admin), MAX_SUPPLY - amount);
        
        vm.stopPrank();
    }
    
    function test_Approve_Success() public {
        uint256 amount = 1000 * 10**18;
        
        vm.startPrank(admin);
        
        vm.expectEmit(true, true, false, true);
        emit Approval(admin, user1, amount);
        
        bool success = token.approve(user1, amount);
        assertTrue(success);
        
        assertEq(token.allowance(admin, user1), amount);
        
        vm.stopPrank();
    }
    
    function test_TransferFrom_Success() public {
        uint256 amount = 1000 * 10**18;
        
        // Admin approves user1 to spend tokens
        vm.prank(admin);
        token.approve(user1, amount);
        
        // User1 transfers from admin to user2
        vm.startPrank(user1);
        
        vm.expectEmit(true, true, false, true);
        emit Transfer(admin, user2, amount);
        
        bool success = token.transferFrom(admin, user2, amount);
        assertTrue(success);
        
        assertEq(token.balanceOf(user2), amount);
        assertEq(token.balanceOf(admin), MAX_SUPPLY - amount);
        assertEq(token.allowance(admin, user1), 0);
        
        vm.stopPrank();
    }
    
    // ============ AccessControl Tests ============
    
    function test_AccessControl_DefaultAdminRole() public view {
        assertTrue(token.hasRole(DEFAULT_ADMIN_ROLE, admin));
        assertEq(token.getRoleAdmin(PAUSER_ROLE), DEFAULT_ADMIN_ROLE);
    }
    
    function test_AccessControl_GrantRole() public {
        vm.startPrank(admin);
        
        vm.expectEmit(true, true, true, true);
        emit RoleGranted(PAUSER_ROLE, user1, admin);
        
        token.grantRole(PAUSER_ROLE, user1);
        assertTrue(token.hasRole(PAUSER_ROLE, user1));
        
        vm.stopPrank();
    }
    
    function test_AccessControl_RevokeRole() public {
        // First grant role
        vm.prank(admin);
        token.grantRole(PAUSER_ROLE, user1);
        
        // Then revoke it
        vm.startPrank(admin);
        
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(PAUSER_ROLE, user1, admin);
        
        token.revokeRole(PAUSER_ROLE, user1);
        assertFalse(token.hasRole(PAUSER_ROLE, user1));
        
        vm.stopPrank();
    }
    
    function test_AccessControl_RenounceRole() public {
        vm.startPrank(admin);
        
        vm.expectEmit(true, true, true, true);
        emit RoleRevoked(PAUSER_ROLE, admin, admin);
        
        token.renounceRole(PAUSER_ROLE, admin);
        assertFalse(token.hasRole(PAUSER_ROLE, admin));
        
        vm.stopPrank();
    }
    
    function test_AccessControl_UnauthorizedGrantRole() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        token.grantRole(PAUSER_ROLE, user2);
        
        vm.stopPrank();
    }
    
    // ============ Pausable Tests ============
    
    function test_Pause_Success() public {
        vm.startPrank(admin);
        
        vm.expectEmit(true, false, false, true);
        emit Paused(admin);
        
        token.pause();
        assertTrue(token.paused());
        
        vm.stopPrank();
    }
    
    function test_Unpause_Success() public {
        // First pause
        vm.prank(admin);
        token.pause();
        
        // Then unpause
        vm.startPrank(admin);
        
        vm.expectEmit(true, false, false, true);
        emit Unpaused(admin);
        
        token.unpause();
        assertFalse(token.paused());
        
        vm.stopPrank();
    }
    
    function test_Pause_UnauthorizedUser() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        token.pause();
        
        vm.stopPrank();
    }
    
    function test_Unpause_UnauthorizedUser() public {
        vm.prank(admin);
        token.pause();
        
        vm.startPrank(user1);
        
        vm.expectRevert();
        token.unpause();
        
        vm.stopPrank();
    }
    
    function test_Transfer_WhenPaused() public {
        uint256 amount = 1000 * 10**18;
        
        vm.prank(admin);
        token.pause();
        
        vm.startPrank(admin);
        
        vm.expectRevert();
        token.transfer(user1, amount);
        
        vm.stopPrank();
    }
    
    function test_PauseUnpause_WithSeparateRoles() public {
        // Grant PAUSER_ROLE to user1
        vm.prank(admin);
        token.grantRole(PAUSER_ROLE, user1);
        
        // User1 can pause
        vm.prank(user1);
        token.pause();
        assertTrue(token.paused());
        
        // User1 can also unpause (same role)
        vm.prank(user1);
        token.unpause();
        assertFalse(token.paused());
    }
    
    // ============ ERC20Permit Tests ============
    
    function test_Permit_Success() public {
        uint256 amount = 1000 * 10**18;
        uint256 deadline = block.timestamp + 1 hours;
        
        // Create permit signature
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        
        // Give owner some tokens first
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
        
        assertEq(token.allowance(owner, user1), amount);
        assertEq(token.nonces(owner), nonce + 1);
    }
    
    function test_Permit_ExpiredDeadline() public {
        uint256 amount = 1000 * 10**18;
        uint256 deadline = block.timestamp - 1; // Expired
        
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);
        
        uint256 nonce = token.nonces(owner);
        
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
        
        vm.expectRevert();
        token.permit(owner, user1, amount, deadline, v, r, s);
    }
    
    // ============ Interface Support Tests ============
    
    function test_SupportsInterface() public view {
        // ERC165
        assertTrue(token.supportsInterface(0x01ffc9a7));
        // AccessControl
        assertTrue(token.supportsInterface(0x7965db0b));
    }
    
    // ============ Edge Cases and Security Tests ============
    
    function test_MaxSupply_Immutable() public view {
        assertEq(token.maxSupply(), MAX_SUPPLY);
        assertEq(token.totalSupply(), MAX_SUPPLY);
    }
    
    function test_Transfer_InsufficientBalance() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        token.transfer(user2, 1);
        
        vm.stopPrank();
    }
    
    function test_TransferFrom_InsufficientAllowance() public {
        vm.startPrank(user1);
        
        vm.expectRevert();
        token.transferFrom(admin, user2, 1);
        
        vm.stopPrank();
    }
    
    function test_RoleConstants() public view {
        assertEq(token.PAUSER_ROLE(), PAUSER_ROLE);
    }
    
    // ============ Fuzz Tests ============
    
    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 0, MAX_SUPPLY);
        
        vm.startPrank(admin);
        
        if (amount <= token.balanceOf(admin)) {
            bool success = token.transfer(user1, amount);
            assertTrue(success);
            assertEq(token.balanceOf(user1), amount);
        } else {
            vm.expectRevert();
            token.transfer(user1, amount);
        }
        
        vm.stopPrank();
    }
    
    function testFuzz_Approve(uint256 amount) public {
        vm.startPrank(admin);
        
        bool success = token.approve(user1, amount);
        assertTrue(success);
        assertEq(token.allowance(admin, user1), amount);
        
        vm.stopPrank();
    }
} 