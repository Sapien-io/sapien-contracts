// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import { Test } from "lib/forge-std/src/Test.sol";
import { SapienToken } from "src/SapienToken.sol";

contract SapienTokenIntegrationTest is Test {
    SapienToken public token;

    address public treasury;
    address public user1;
    address public user2;
    address public user3;

    // Token allocation constants (from CSV)
    uint256 public constant INVESTORS_ALLOCATION = 304_500_000 * 10 ** 18;
    uint256 public constant TEAM_ADVISORS_ALLOCATION = 165_500_000 * 10 ** 18;
    uint256 public constant TRAINER_COMP_ALLOCATION = 150_000_000 * 10 ** 18;
    uint256 public constant AIRDROPS_ALLOCATION = 130_000_000 * 10 ** 18;
    uint256 public constant FOUNDATION_TREASURY_ALLOCATION = 130_000_000 * 10 ** 18;
    uint256 public constant LIQUIDITY_ALLOCATION = 120_000_000 * 10 ** 18;
    uint256 public constant MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    function setUp() public {
        treasury = makeAddr("treasury");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");

        // Deploy token with treasury
        token = new SapienToken(treasury);
    }

    // ============ Token Distribution Simulation ============

    function test_TokenDistribution_Simulation() public {
        vm.startPrank(treasury);

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

        // treasury should have no tokens left
        assertEq(token.balanceOf(treasury), 0);

        // Total supply should remain constant
        assertEq(token.totalSupply(), MAX_SUPPLY);

        vm.stopPrank();
    }

    // ============ Permit Integration Tests ============

    function test_Permit_IntegrationWithTransfers() public {
        uint256 amount = 1000 * 10 ** 18;
        uint256 deadline = block.timestamp + 1 hours;

        // Create permit signature
        uint256 privateKey = 0x1234;
        address owner = vm.addr(privateKey);

        // Give owner some tokens
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

        // Now user1 can transfer from owner
        vm.prank(user1);
        bool success = token.transferFrom(owner, user2, amount);
        assertTrue(success);
        assertEq(token.balanceOf(user2), amount);
        assertEq(token.balanceOf(owner), 0);
    }

    // ============ Gas Optimization Tests ============

    function test_BatchTransfers_GasEfficiency() public {
        uint256 amount = 1000 * 10 ** 18;
        address[] memory recipients = new address[](5);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;
        recipients[3] = makeAddr("user4");
        recipients[4] = makeAddr("user5");

        vm.startPrank(treasury);

        // Simulate batch transfers
        for (uint256 i = 0; i < recipients.length; i++) {
            token.transfer(recipients[i], amount);
        }

        // Verify all transfers
        for (uint256 i = 0; i < recipients.length; i++) {
            assertEq(token.balanceOf(recipients[i]), amount);
        }

        vm.stopPrank();
    }

    // ============ Edge Cases ============

    function test_MaxApproval() public {
        vm.startPrank(treasury);

        // Test maximum uint256 approval
        bool success = token.approve(user1, type(uint256).max);
        assertTrue(success);
        assertEq(token.allowance(treasury, user1), type(uint256).max);

        vm.stopPrank();
    }

    function test_ZeroValueTransfers() public {
        vm.startPrank(treasury);

        // Zero value transfers should succeed
        bool success = token.transfer(user1, 0);
        assertTrue(success);

        success = token.approve(user1, 0);
        assertTrue(success);

        vm.stopPrank();

        vm.startPrank(user1);
        success = token.transferFrom(treasury, user2, 0);
        assertTrue(success);
        vm.stopPrank();
    }

    function test_SelfTransfer() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.startPrank(treasury);

        uint256 balanceBefore = token.balanceOf(treasury);
        bool success = token.transfer(treasury, amount);
        assertTrue(success);

        // Balance should remain the same
        assertEq(token.balanceOf(treasury), balanceBefore);

        vm.stopPrank();
    }

    // ============ Stress Tests ============

    function test_ManySmallTransfers() public {
        uint256 smallAmount = 1 * 10 ** 18; // 1 token

        vm.startPrank(treasury);

        // Make 100 small transfers
        for (uint256 i = 0; i < 100; i++) {
            address recipient = address(uint160(i + 1000)); // Generate unique addresses
            token.transfer(recipient, smallAmount);
            assertEq(token.balanceOf(recipient), smallAmount);
        }

        vm.stopPrank();
    }

    // ============ Invariant Tests ============

    function test_TotalSupplyInvariant() public {
        uint256 amount = 1000 * 10 ** 18;

        vm.startPrank(treasury);

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
