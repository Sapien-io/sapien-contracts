// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "./BaseTest.t.sol";
import {ISapienCore} from "../src/interface/ISapienCore.sol";
import {IRewards} from "../src/interface/IRewards.sol";
import {ISharedTypes, ORIGINATOR_ROLE, UPDATER_ROLE} from "../src/interface/ISharedTypes.sol";

contract OperatorFeeTest is BaseTest {
    string public constant PROJECT_CID = "test-project";
    bytes32 public PROJECT_ID;
    address public operator;
    address public treasury = makeAddr("treasury");
    uint256 public constant INITIAL_BALANCE = 10000 ether;

    event OperatorFeePaid(bytes32 indexed projectId, address indexed operator, uint256 amount);
    event ProtocolFeeCollected(bytes32 indexed projectId, address indexed token, uint256 amount);

    function setUp() public override {
        super.setUp();
        PROJECT_ID = keccak256(abi.encodePacked(PROJECT_CID));
        operator = makeAddr("operator");

        // Setup project
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(rewardToken), "test-project", 10 ether, 0, 3, 1000, "");
        rewardToken.approve(address(core), INITIAL_BALANCE);
        vm.stopPrank();

        // Grant updater role to admin for setup
        vm.startPrank(admin);
        trust.grantRole(UPDATER_ROLE, admin);

        // Set protocol fee to 1% for clarity
        core.setProtocolFeeBasisPoints(100); // 1%

        // Ensure treasury is set
        core.setTreasury(treasury);
        vm.stopPrank();
    }

    function testFundProjectWithOperatorFee() public {
        uint256 rewardAmount = 1000 ether;
        uint256 quantity = 100;
        uint256 operatorFeeBps = 200; // 2% (max allowed)

        vm.startPrank(originator);

        uint256 balanceBefore = rewardToken.balanceOf(originator);

        // Protocol fee is taken FIRST from the original amount:
        // Protocol fee = 1% of 1000 = 10 ether
        vm.expectEmit(true, true, false, true);
        emit ProtocolFeeCollected(PROJECT_ID, address(rewardToken), 10 ether);

        // Operator fee is taken from the remainder:
        // After protocol: 1000 - 10 = 990
        // Operator fee = 2% of 990 = 19.8 ether
        vm.expectEmit(true, true, false, true);
        emit OperatorFeePaid(PROJECT_ID, operator, 19.8 ether);

        core.fundProject(PROJECT_ID, rewardAmount, quantity, operator, operatorFeeBps);

        uint256 balanceAfter = rewardToken.balanceOf(originator);

        vm.stopPrank();

        // Checks
        assertEq(balanceBefore - balanceAfter, rewardAmount, "Originator should spend full amount");
        assertEq(rewardToken.balanceOf(treasury), 10 ether, "Treasury should receive 1% of original");
        assertEq(rewardToken.balanceOf(operator), 19.8 ether, "Operator should receive 2% of remainder");

        // Project rewards = 1000 - 10 (protocol) - 19.8 (operator) = 970.2 ether
        assertEq(rewardToken.balanceOf(address(rewards)), 970.2 ether, "Rewards contract should receive remainder");
    }

    function testFundProjectLegacyStillWorks() public {
        uint256 rewardAmount = 1000 ether;
        uint256 quantity = 100;

        vm.startPrank(originator);
        core.fundProject(PROJECT_ID, rewardAmount, quantity);
        vm.stopPrank();

        // Logic:
        // Operator fee = 0.
        // Net = 1000.
        // Protocol fee = 1% of 1000 = 10.
        // Project gets 990.

        assertEq(rewardToken.balanceOf(operator), 0, "Operator receives nothing");
        assertEq(rewardToken.balanceOf(treasury), 10 ether, "Treasury receives 1% of 1000");
        assertEq(rewardToken.balanceOf(address(rewards)), 990 ether, "Rewards receives remainder");
    }

    function testExcessiveOperatorFeeReverts() public {
        uint256 rewardAmount = 1000 ether;
        uint256 quantity = 100;
        uint256 operatorFeeBps = 201; // > 2%

        vm.startPrank(originator);
        vm.expectRevert(ISapienCore.InvalidAmount.selector);
        core.fundProject(PROJECT_ID, rewardAmount, quantity, operator, operatorFeeBps);
        vm.stopPrank();
    }

    // ============================================
    // CLAIM REWARDS FEE TESTS
    // ============================================

    event OperatorFeeCollected(
        address indexed claimer, address indexed feeRecipient, address indexed token, uint256 amount
    );
    event MaxFeeBpsUpdated(uint256 newMaxFeeBps);

    function testDefaultMaxFeeBpsIs4Percent() public {
        // Verify default is 4% (400 bps)
        assertEq(rewards.maxFeeBps(), 400);
        assertEq(rewards.DEFAULT_MAX_FEE_BPS(), 400);
    }

    function testSetMaxFeeBps() public {
        vm.prank(admin);
        rewards.setMaxFeeBps(500); // 5%

        assertEq(rewards.maxFeeBps(), 500);
    }

    function testSetMaxFeeBpsEmitsEvent() public {
        vm.prank(admin);
        vm.expectEmit(false, false, false, true);
        emit MaxFeeBpsUpdated(500);
        rewards.setMaxFeeBps(500);
    }

    function testSetMaxFeeBpsUnauthorized() public {
        vm.prank(contributor);
        vm.expectRevert();
        rewards.setMaxFeeBps(500);
    }

    function testSetMaxFeeBpsExceedsCap() public {
        vm.prank(admin);
        vm.expectRevert(IRewards.InvalidFeeBps.selector);
        rewards.setMaxFeeBps(10001); // > 100%
    }

    function testClaimRewardsWithOperatorFee() public {
        uint256 amount = 100 ether;
        address claimOperator = makeAddr("claimOperator");
        uint256 feeBps = 500; // 5%

        // Setup max fee
        vm.prank(admin);
        rewards.setMaxFeeBps(1000); // 10% max

        // Setup rewards
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount);
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), amount);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount);

        // Claim with fee
        uint256 expectedFee = (amount * feeBps) / 10000; // 5 ether
        uint256 expectedNet = amount - expectedFee; // 95 ether

        vm.prank(contributor);
        vm.expectEmit(true, true, true, true);
        emit OperatorFeeCollected(contributor, claimOperator, address(rewardToken), expectedFee);
        rewards.claimRewards(PROJECT_ID, address(rewardToken), claimOperator, feeBps);

        assertEq(rewardToken.balanceOf(contributor), expectedNet, "Contributor should receive net amount");
        assertEq(rewardToken.balanceOf(claimOperator), expectedFee, "Operator should receive fee");
    }

    function testClaimRewardsWithZeroFee() public {
        uint256 amount = 100 ether;

        // Setup max fee
        vm.prank(admin);
        rewards.setMaxFeeBps(1000);

        // Setup rewards
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount);
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), amount);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount);

        // Claim with zero fee (address(0), 0)
        vm.prank(contributor);
        rewards.claimRewards(PROJECT_ID, address(rewardToken), address(0), 0);

        assertEq(rewardToken.balanceOf(contributor), amount, "Contributor should receive full amount");
    }

    function testClaimRewardsFeeTooHigh() public {
        uint256 amount = 100 ether;
        address claimOperator = makeAddr("claimOperator");

        // Default max fee is 4% (400 bps)
        assertEq(rewards.maxFeeBps(), 400);

        // Setup rewards
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount);
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), amount);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount);

        // Try to claim with 5% fee (exceeds 4% default max)
        vm.prank(contributor);
        vm.expectRevert(abi.encodeWithSelector(IRewards.FeeBpsTooHigh.selector, 500, 400));
        rewards.claimRewards(PROJECT_ID, address(rewardToken), claimOperator, 500);
    }

    function testClaimRewardsInvalidFeeRecipient() public {
        uint256 amount = 100 ether;

        // Setup max fee
        vm.prank(admin);
        rewards.setMaxFeeBps(1000);

        // Setup rewards
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount);
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), amount);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount);

        // Try to claim with non-zero fee but zero address recipient
        vm.prank(contributor);
        vm.expectRevert(IRewards.InvalidFeeRecipient.selector);
        rewards.claimRewards(PROJECT_ID, address(rewardToken), address(0), 500);
    }

    function testClaimValidatorRewardsWithOperatorFee() public {
        uint256 amount = 50 ether;
        address claimOperator = makeAddr("claimOperator");
        uint256 feeBps = 200; // 2%

        // Setup max fee
        vm.prank(admin);
        rewards.setMaxFeeBps(1000);

        // Setup rewards
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount);
        rewards.distributeValidatorReward(PROJECT_ID, validator1, address(rewardToken), amount);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount);

        // Claim with fee
        uint256 expectedFee = (amount * feeBps) / 10000; // 1 ether
        uint256 expectedNet = amount - expectedFee; // 49 ether

        vm.prank(validator1);
        rewards.claimValidatorRewards(PROJECT_ID, address(rewardToken), claimOperator, feeBps);

        assertEq(rewardToken.balanceOf(validator1), expectedNet, "Validator should receive net amount");
        assertEq(rewardToken.balanceOf(claimOperator), expectedFee, "Operator should receive fee");
    }

    function testClaimAllRewardsWithOperatorFee() public {
        uint256 amount1 = 100 ether;
        uint256 amount2 = 50 ether;
        bytes32 project2 = keccak256("project-2");
        address claimOperator = makeAddr("claimOperator");
        uint256 feeBps = 300; // 3%

        // Setup max fee
        vm.prank(admin);
        rewards.setMaxFeeBps(1000);

        // Setup rewards for both projects
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount1);
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), amount1);
        rewards.allocateRewards(project2, address(rewardToken), amount2);
        rewards.distributeReward(project2, contributor, address(rewardToken), amount2);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount1 + amount2);

        bytes32[] memory projectIds = new bytes32[](2);
        projectIds[0] = PROJECT_ID;
        projectIds[1] = project2;

        // Claim all with fee
        uint256 totalAmount = amount1 + amount2; // 150 ether
        uint256 expectedFee = (totalAmount * feeBps) / 10000; // 4.5 ether
        uint256 expectedNet = totalAmount - expectedFee; // 145.5 ether

        vm.prank(contributor);
        rewards.claimAllRewards(address(rewardToken), projectIds, claimOperator, feeBps);

        assertEq(rewardToken.balanceOf(contributor), expectedNet, "Contributor should receive net amount");
        assertEq(rewardToken.balanceOf(claimOperator), expectedFee, "Operator should receive fee");
    }

    function testClaimAllValidatorRewardsWithOperatorFee() public {
        uint256 amount1 = 30 ether;
        uint256 amount2 = 20 ether;
        bytes32 project2 = keccak256("project-2");
        address claimOperator = makeAddr("claimOperator");
        uint256 feeBps = 100; // 1%

        // Setup max fee
        vm.prank(admin);
        rewards.setMaxFeeBps(1000);

        // Setup rewards for both projects
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount1);
        rewards.distributeValidatorReward(PROJECT_ID, validator1, address(rewardToken), amount1);
        rewards.allocateRewards(project2, address(rewardToken), amount2);
        rewards.distributeValidatorReward(project2, validator1, address(rewardToken), amount2);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount1 + amount2);

        bytes32[] memory projectIds = new bytes32[](2);
        projectIds[0] = PROJECT_ID;
        projectIds[1] = project2;

        // Claim all with fee
        uint256 totalAmount = amount1 + amount2; // 50 ether
        uint256 expectedFee = (totalAmount * feeBps) / 10000; // 0.5 ether
        uint256 expectedNet = totalAmount - expectedFee; // 49.5 ether

        vm.prank(validator1);
        rewards.claimAllValidatorRewards(address(rewardToken), projectIds, claimOperator, feeBps);

        assertEq(rewardToken.balanceOf(validator1), expectedNet, "Validator should receive net amount");
        assertEq(rewardToken.balanceOf(claimOperator), expectedFee, "Operator should receive fee");
    }

    function testFeeCalculationPrecision() public {
        // Test with small amounts to verify precision (multiply before divide)
        uint256 amount = 1 ether;
        address claimOperator = makeAddr("claimOperator");
        uint256 feeBps = 333; // 3.33%

        // Setup max fee
        vm.prank(admin);
        rewards.setMaxFeeBps(1000);

        // Setup rewards
        vm.startPrank(address(core));
        rewards.allocateRewards(PROJECT_ID, address(rewardToken), amount);
        rewards.distributeReward(PROJECT_ID, contributor, address(rewardToken), amount);
        vm.stopPrank();

        rewardToken.mint(address(rewards), amount);

        // Expected: (1 ether * 333) / 10000 = 0.0333 ether = 33300000000000000 wei
        uint256 expectedFee = (amount * feeBps) / 10000;
        uint256 expectedNet = amount - expectedFee;

        vm.prank(contributor);
        rewards.claimRewards(PROJECT_ID, address(rewardToken), claimOperator, feeBps);

        assertEq(rewardToken.balanceOf(contributor), expectedNet, "Net amount should be precise");
        assertEq(rewardToken.balanceOf(claimOperator), expectedFee, "Fee should be precise");
        assertEq(expectedFee + expectedNet, amount, "Fee + Net should equal total");
    }
}
