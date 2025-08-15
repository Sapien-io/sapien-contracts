// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienToken} from "src/SapienToken.sol";

contract SapienTokenTest is Test {
    SapienToken public token;

    address public treasury;
    address public user1;
    address public user2;
    address public zeroAddress = address(0);

    // Constants
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    // Events
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // Custom errors
    error ZeroAddress();

    function setUp() public {
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy token with admin
        token = new SapienToken(treasury);
    }

    // ============ Constructor Tests ============

    function test_Token_Constructor_Success() public view {
        // Check basic ERC20 properties
        assertEq(token.name(), "Sapien");
        assertEq(token.symbol(), "SAPIEN");
        assertEq(token.decimals(), 18);
        assertEq(token.totalSupply(), MAX_SUPPLY);
        assertEq(token.maxSupply(), MAX_SUPPLY);

        // Check admin received all tokens
        assertEq(token.balanceOf(treasury), MAX_SUPPLY);
    }

    function test_Token_Constructor_RevertZeroAddress() public {
        vm.expectRevert(ZeroAddress.selector);
        new SapienToken(zeroAddress);
    }

    // ============ ERC20 Basic Functionality Tests ============

    function test_Token_Transfer_Success() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.startPrank(treasury);

        vm.expectEmit(true, true, false, true);
        emit Transfer(treasury, user1, amount);

        bool success = token.transfer(user1, amount);
        assertTrue(success);

        assertEq(token.balanceOf(user1), amount);
        assertEq(token.balanceOf(treasury), MAX_SUPPLY - amount);

        vm.stopPrank();
    }

    function test_Token_Approve_Success() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.startPrank(treasury);

        vm.expectEmit(true, true, false, true);
        emit Approval(treasury, user1, amount);

        bool success = token.approve(user1, amount);
        assertTrue(success);

        assertEq(token.allowance(treasury, user1), amount);

        vm.stopPrank();
    }

    function test_Token_TransferFrom_Success() public {
        uint256 amount = 1000 * 10 ** 18;

        // treasury approves user1 to spend tokens
        vm.prank(treasury);
        token.approve(user1, amount);

        // User1 transfers from treasury to user2
        vm.startPrank(user1);

        vm.expectEmit(true, true, false, true);
        emit Transfer(treasury, user2, amount);

        bool success = token.transferFrom(treasury, user2, amount);
        assertTrue(success);

        assertEq(token.balanceOf(user2), amount);
        assertEq(token.balanceOf(treasury), MAX_SUPPLY - amount);
        assertEq(token.allowance(treasury, user1), 0);

        vm.stopPrank();
    }

    // ============ ERC20Permit Tests ============

    function test_Token_Permit_Success() public {
        uint256 amount = 1000 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        // Create permit signature
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);

        // Give owner some tokens first
        vm.prank(treasury);
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

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        // Execute permit
        token.permit(owner, user1, amount, deadline, v, r, s);

        assertEq(token.allowance(owner, user1), amount);
        assertEq(token.nonces(owner), nonce + 1);
    }

    function test_Token_Permit_ExpiredDeadline() public {
        uint256 amount = 1000 * 10 ** 18;
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

        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);

        vm.expectRevert();
        token.permit(owner, user1, amount, deadline, v, r, s);
    }

    // ============ Edge Cases and Security Tests ============

    function test_Token_MaxSupply_Immutable() public view {
        assertEq(token.maxSupply(), MAX_SUPPLY);
        assertEq(token.totalSupply(), MAX_SUPPLY);
    }

    function test_Token_Transfer_InsufficientBalance() public {
        vm.startPrank(user1);

        vm.expectRevert();
        token.transfer(user2, 1);

        vm.stopPrank();
    }

    function test_Token_TransferFrom_InsufficientAllowance() public {
        vm.startPrank(user1);

        vm.expectRevert();
        token.transferFrom(treasury, user2, 1);

        vm.stopPrank();
    }

    // ============ Fuzz Tests ============

    function test_Token_Fuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 0, MAX_SUPPLY);

        vm.startPrank(treasury);

        if (amount <= token.balanceOf(treasury)) {
            bool success = token.transfer(user1, amount);
            assertTrue(success);
            assertEq(token.balanceOf(user1), amount);
        } else {
            vm.expectRevert();
            token.transfer(user1, amount);
        }

        vm.stopPrank();
    }

    function test_Token_Fuzz_Approve(uint256 amount) public {
        vm.startPrank(treasury);

        bool success = token.approve(user1, amount);
        assertTrue(success);
        assertEq(token.allowance(treasury, user1), amount);

        vm.stopPrank();
    }
}
