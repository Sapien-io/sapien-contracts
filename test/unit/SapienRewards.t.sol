// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {SapienRewards} from "src/SapienRewards.sol";
import {ISapienRewards} from "src/interfaces/ISapienRewards.sol";
import {Constants as Const} from "src/utils/Constants.sol";

contract SapienRewardsTest is Test {
    using ECDSA for bytes32;

    SapienRewards public sapienRewards;
    MockERC20 public rewardToken;
    
    // Test accounts
    address public admin = makeAddr("admin");
    address public rewardManager = makeAddr("rewardManager");
    address public rewardSafe = makeAddr("rewardSafe");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public unauthorizedUser = makeAddr("unauthorizedUser");
    
    // Reward manager private key for signing
    uint256 public rewardManagerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address public rewardManagerSigner = vm.addr(rewardManagerPrivateKey);
    
    // Test constants
    uint256 public constant INITIAL_REWARD_BALANCE = 1000000 * 10**18; // 1M tokens
    uint256 public constant REWARD_AMOUNT = 1000 * 10**18; // 1K tokens
    bytes32 public constant ORDER_ID = keccak256("order_1");
    bytes32 public constant ORDER_ID_2 = keccak256("order_2");

    // Events for testing
    event RewardClaimed(address indexed user, uint256 amount, bytes32 indexed orderId);
    event RewardsDeposited(address indexed depositor, uint256 amount, uint256 newBalance);
    event RewardsWithdrawn(address indexed withdrawer, uint256 amount, uint256 newBalance);
    event RewardTokenSet(address indexed newRewardToken);
    event RewardsReconciled(uint256 untrackedAmount, uint256 newAvailableBalance);
    event UnaccountedTokensRecovered(address indexed recipient, uint256 amount);

    function setUp() public {
        // Deploy mock ERC20 token
        rewardToken = new MockERC20("Reward Token", "REWARD", 18);
        
        // Deploy SapienRewards implementation
        SapienRewards sapienRewardsImpl = new SapienRewards();
        
        // Deploy proxy with initialization
        bytes memory initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            admin,
            rewardManagerSigner,
            rewardSafe,
            address(rewardToken)
        );
        ERC1967Proxy sapienRewardsProxy = new ERC1967Proxy(address(sapienRewardsImpl), initData);
        sapienRewards = SapienRewards(address(sapienRewardsProxy));
        
        // Mint tokens to reward safe
        rewardToken.mint(rewardSafe, INITIAL_REWARD_BALANCE);
        
        // Approve contract to spend tokens from reward safe
        vm.prank(rewardSafe);
        rewardToken.approve(address(sapienRewards), INITIAL_REWARD_BALANCE);
    }

    // ============================================
    // Initialization Tests
    // ============================================

    function test_Rewards_Initialize() public {
        // Deploy new implementation and proxy for testing initialization
        SapienRewards newImpl = new SapienRewards();
        bytes memory initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            admin,
            rewardManagerSigner,
            rewardSafe,
            address(rewardToken)
        );
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImpl), initData);
        SapienRewards newContract = SapienRewards(address(newProxy));
        
        // Check roles
        assertTrue(newContract.hasRole(newContract.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(newContract.hasRole(Const.PAUSER_ROLE, admin));
        assertTrue(newContract.hasRole(Const.REWARD_SAFE_ROLE, rewardSafe));
        assertTrue(newContract.hasRole(Const.REWARD_MANAGER_ROLE, rewardManagerSigner));
        
        // Check token is set
        assertEq(address(newContract.rewardToken()), address(rewardToken));
        
        // Check version
        assertEq(newContract.version(), "0.1.2");
    }

    function test_Rewards_InitializeRevertsOnZeroAddresses() public {
        SapienRewards newImpl = new SapienRewards();
        
        // Test zero admin
        bytes memory initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            address(0),
            rewardManagerSigner,
            rewardSafe,
            address(rewardToken)
        );
        vm.expectRevert(ISapienRewards.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
        
        // Test zero reward manager
        initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            admin,
            address(0),
            rewardSafe,
            address(rewardToken)
        );
        vm.expectRevert(ISapienRewards.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
        
        // Test zero reward safe
        initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            admin,
            rewardManagerSigner,
            address(0),
            address(rewardToken)
        );
        vm.expectRevert(ISapienRewards.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
        
        // Test zero reward token
        initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            admin,
            rewardManagerSigner,
            rewardSafe,
            address(0)
        );
        vm.expectRevert(ISapienRewards.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_Rewards_CannotInitializeTwice() public {
        vm.expectRevert();
        sapienRewards.initialize(admin, rewardManagerSigner, rewardSafe, address(rewardToken));
    }

    // ============================================
    // Access Control Tests
    // ============================================

    function test_Rewards_OnlyAdminCanSetRewardToken() public {
        MockERC20 newToken = new MockERC20("New Reward Token", "NEWREWARD", 18);
        
        vm.prank(admin);
        sapienRewards.setRewardToken(address(newToken));
        
        assertEq(address(sapienRewards.rewardToken()), address(newToken));
    }

    function test_Rewards_NonAdminCannotSetRewardToken() public {
        MockERC20 newToken = new MockERC20("New Reward Token", "NEWREWARD", 18);
        
        vm.prank(unauthorizedUser);
        vm.expectRevert("Only the Admin can perform this");
        sapienRewards.setRewardToken(address(newToken));
    }

    function test_Rewards_OnlyPauserCanPause() public {
        vm.prank(admin);
        sapienRewards.pause();
        assertTrue(sapienRewards.paused());
    }

    function test_Rewards_OnlyPauserCanUnpause() public {
        // First pause the contract
        vm.prank(admin);
        sapienRewards.pause();
        assertTrue(sapienRewards.paused());
        
        // Then unpause it
        vm.prank(admin);
        sapienRewards.unpause();
        assertFalse(sapienRewards.paused());
    }

    function test_Rewards_NonPauserCannotPause() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert("Only the Pauser can perform this");
        sapienRewards.pause();
    }

    function test_Rewards_NonPauserCannotUnpause() public {
        // First pause the contract
        vm.prank(admin);
        sapienRewards.pause();
        
        // Unauthorized user cannot unpause
        vm.prank(unauthorizedUser);
        vm.expectRevert("Only the Pauser can perform this");
        sapienRewards.unpause();
    }

    function test_Rewards_OnlyRewardSafeCanDeposit() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        assertEq(sapienRewards.getAvailableRewards(), REWARD_AMOUNT);
    }

    function test_Rewards_NonRewardSafeCannotDeposit() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert("Only the Reward Safe can perform this");
        sapienRewards.depositRewards(REWARD_AMOUNT);
    }

    // ============================================
    // Deposit/Withdraw Tests
    // ============================================

    function test_Rewards_DepositRewards() public {
        vm.expectEmit(true, false, false, true);
        emit RewardsDeposited(rewardSafe, REWARD_AMOUNT, REWARD_AMOUNT);
        
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        assertEq(sapienRewards.getAvailableRewards(), REWARD_AMOUNT);
        assertEq(rewardToken.balanceOf(address(sapienRewards)), REWARD_AMOUNT);
    }

    function test_Rewards_DepositRevertsOnZeroAmount() public {
        vm.prank(rewardSafe);
        vm.expectRevert(ISapienRewards.InvalidAmount.selector);
        sapienRewards.depositRewards(0);
    }

    function test_Rewards_WithdrawRewards() public {
        // First deposit
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        uint256 withdrawAmount = REWARD_AMOUNT / 2;
        
        vm.expectEmit(true, false, false, true);
        emit RewardsWithdrawn(rewardSafe, withdrawAmount, REWARD_AMOUNT - withdrawAmount);
        
        vm.prank(rewardSafe);
        sapienRewards.withdrawRewards(withdrawAmount);
        
        assertEq(sapienRewards.getAvailableRewards(), REWARD_AMOUNT - withdrawAmount);
    }

    function test_Rewards_WithdrawRevertsOnInsufficientBalance() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        vm.prank(rewardSafe);
        vm.expectRevert(ISapienRewards.InsufficientAvailableRewards.selector);
        sapienRewards.withdrawRewards(REWARD_AMOUNT + 1);
    }

    function test_Rewards_ReconcileBalance() public {
        // Deposit rewards normally
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        // Send tokens directly to contract (simulating untracked deposit)
        uint256 untrackedAmount = 500 * 10**18;
        rewardToken.mint(address(sapienRewards), untrackedAmount);
        
        uint256 expectedTotal = REWARD_AMOUNT + untrackedAmount;
        
        vm.expectEmit(false, false, false, true);
        emit RewardsReconciled(untrackedAmount, expectedTotal);
        
        vm.prank(rewardSafe);
        sapienRewards.reconcileBalance();
        
        assertEq(sapienRewards.getAvailableRewards(), expectedTotal);
    }

    function test_Rewards_RecoverUnaccountedTokens() public {
        // Deposit normally
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        // Send tokens directly
        uint256 untrackedAmount = 500 * 10**18;
        rewardToken.mint(address(sapienRewards), untrackedAmount);
        
        uint256 recoverAmount = 200 * 10**18;
        
        vm.expectEmit(true, false, false, true);
        emit UnaccountedTokensRecovered(rewardSafe, recoverAmount);
        
        vm.prank(rewardSafe);
        sapienRewards.recoverUnaccountedTokens(recoverAmount);
        
        assertEq(rewardToken.balanceOf(rewardSafe), INITIAL_REWARD_BALANCE - REWARD_AMOUNT + recoverAmount);
    }

    // ============================================
    // EIP-712 Signature Tests
    // ============================================

    function test_Rewards_ClaimRewardWithValidSignature() public {
        // Deposit rewards
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT * 2);
        
        // Create signature
        bytes memory signature = _createSignature(user1, REWARD_AMOUNT, ORDER_ID);
        
        vm.expectEmit(true, false, true, true);
        emit RewardClaimed(user1, REWARD_AMOUNT, ORDER_ID);
        
        vm.prank(user1);
        bool success = sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);
        
        assertTrue(success);
        assertEq(rewardToken.balanceOf(user1), REWARD_AMOUNT);
        assertEq(sapienRewards.getAvailableRewards(), REWARD_AMOUNT);
        assertTrue(sapienRewards.getOrderRedeemedStatus(user1, ORDER_ID));
    }

    function test_Rewards_ClaimRewardRevertsOnInvalidSignature() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        // Create signature with wrong private key
        uint256 wrongPrivateKey = 0x9876543210987654321098765432109876543210987654321098765432109876;
        bytes memory wrongSignature = _createSignatureWithKey(user1, REWARD_AMOUNT, ORDER_ID, wrongPrivateKey);
        
        vm.prank(user1);
        vm.expectRevert();
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, wrongSignature);
    }

    function test_Rewards_ClaimRewardRevertsOnMalformedSignature() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        // Create malformed signature (wrong length)
        bytes memory malformedSignature = new bytes(32); // Too short, should be 65 bytes
        
        vm.prank(user1);
        vm.expectRevert();
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, malformedSignature);
    }

    function test_Rewards_ClaimRewardRevertsOnInvalidSignatureFormat() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        // Create signature with invalid format (all zeros)
        bytes memory invalidSignature = new bytes(65);
        
        vm.prank(user1);
        vm.expectRevert();
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, invalidSignature);
    }

    function test_Rewards_ClaimRewardRevertsOnECDSARecoveryError() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        // Create a signature with invalid s value (too high)
        bytes32 r = 0x1234567890123456789012345678901234567890123456789012345678901234;
        bytes32 s = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364142; // Invalid s value
        uint8 v = 27;
        
        bytes memory invalidSignature = abi.encodePacked(r, s, v);
        
        vm.prank(user1);
        vm.expectRevert();
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, invalidSignature);
    }

    function test_Rewards_ClaimRewardRevertsOnDoubleSpend() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT * 2);
        
        bytes memory signature = _createSignature(user1, REWARD_AMOUNT, ORDER_ID);
        
        // First claim
        vm.prank(user1);
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);
        
        // Second claim with same order ID should fail
        vm.prank(user1);
        vm.expectRevert(ISapienRewards.OrderAlreadyUsed.selector);
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);
    }

    function test_Rewards_ClaimRewardRevertsWhenPaused() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        vm.prank(admin);
        sapienRewards.pause();
        
        bytes memory signature = _createSignature(user1, REWARD_AMOUNT, ORDER_ID);
        
        vm.prank(user1);
        vm.expectRevert();
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);
    }

    function test_Rewards_RewardManagerCannotClaim() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        bytes memory signature = _createSignature(rewardManagerSigner, REWARD_AMOUNT, ORDER_ID);
        
        vm.prank(rewardManagerSigner);
        vm.expectRevert(ISapienRewards.RewardsManagerCannotClaim.selector);
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);
    }

    // ============================================
    // Validation Tests
    // ============================================

    function test_Rewards_ValidateRewardParameters() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        // Valid parameters should not revert
        sapienRewards.validateRewardParameters(user1, REWARD_AMOUNT, ORDER_ID);
    }

    function test_Rewards_ValidateRewardParametersRevertsOnZeroAmount() public {
        vm.expectRevert(ISapienRewards.InvalidAmount.selector);
        sapienRewards.validateRewardParameters(user1, 0, ORDER_ID);
    }

    function test_Rewards_ValidateRewardParametersRevertsOnZeroOrderId() public {
        vm.expectRevert();
        sapienRewards.validateRewardParameters(user1, REWARD_AMOUNT, bytes32(0));
    }

    function test_Rewards_ValidateRewardParametersRevertsOnInsufficientRewards() public {
        vm.expectRevert(ISapienRewards.InsufficientAvailableRewards.selector);
        sapienRewards.validateRewardParameters(user1, REWARD_AMOUNT, ORDER_ID);
    }

    function test_Rewards_ValidateRewardParametersRevertsOnAlreadyRedeemed() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT * 2);
        
        bytes memory signature = _createSignature(user1, REWARD_AMOUNT, ORDER_ID);
        
        vm.prank(user1);
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);
        
        vm.expectRevert(ISapienRewards.OrderAlreadyUsed.selector);
        sapienRewards.validateRewardParameters(user1, REWARD_AMOUNT, ORDER_ID);
    }

    function test_Rewards_ValidateAndGetHashToSign() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        vm.prank(rewardManagerSigner);
        bytes32 hash = sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, ORDER_ID);
        
        assertNotEq(hash, bytes32(0));
    }

    function test_Rewards_ValidateAndGetHashToSignRevertsForNonManager() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        vm.prank(unauthorizedUser);
        vm.expectRevert("Only the Reward Manager can perform this");
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, ORDER_ID);
    }

    function test_Rewards_ValidateAndGetHashToSignRevertsWhenPaused() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        vm.prank(admin);
        sapienRewards.pause();
        
        vm.prank(rewardManagerSigner);
        vm.expectRevert();
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, ORDER_ID);
    }

    // ============================================
    // View Function Tests
    // ============================================

    function test_Rewards_GetAvailableRewards() public {
        assertEq(sapienRewards.getAvailableRewards(), 0);
        
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        assertEq(sapienRewards.getAvailableRewards(), REWARD_AMOUNT);
    }

    function test_Rewards_GetRewardTokenBalances() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        (uint256 available, uint256 total) = sapienRewards.getRewardTokenBalances();
        
        assertEq(available, REWARD_AMOUNT);
        assertEq(total, REWARD_AMOUNT);
        
        // Send tokens directly to contract
        rewardToken.mint(address(sapienRewards), 500 * 10**18);
        
        (available, total) = sapienRewards.getRewardTokenBalances();
        
        assertEq(available, REWARD_AMOUNT);
        assertEq(total, REWARD_AMOUNT + 500 * 10**18);
    }

    function test_Rewards_GetOrderRedeemedStatus() public {
        assertFalse(sapienRewards.getOrderRedeemedStatus(user1, ORDER_ID));
        
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        bytes memory signature = _createSignature(user1, REWARD_AMOUNT, ORDER_ID);
        
        vm.prank(user1);
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);
        
        assertTrue(sapienRewards.getOrderRedeemedStatus(user1, ORDER_ID));
    }

    function test_Rewards_GetDomainSeparator() public view {
        bytes32 domainSeparator = sapienRewards.getDomainSeparator();
        assertNotEq(domainSeparator, bytes32(0));
    }

    function test_Rewards_VersionIsCorrect() public view {
        assertEq(sapienRewards.version(), "0.1.2");
    }

    // ============================================
    // Edge Case Tests
    // ============================================

    function test_Rewards_MultipleUsersCanClaimDifferentOrders() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT * 2);
        
        bytes memory signature1 = _createSignature(user1, REWARD_AMOUNT, ORDER_ID);
        bytes memory signature2 = _createSignature(user2, REWARD_AMOUNT, ORDER_ID_2);
        
        vm.prank(user1);
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature1);
        
        vm.prank(user2);
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID_2, signature2);
        
        assertEq(rewardToken.balanceOf(user1), REWARD_AMOUNT);
        assertEq(rewardToken.balanceOf(user2), REWARD_AMOUNT);
        assertEq(sapienRewards.getAvailableRewards(), 0);
    }

    function test_Rewards_ClaimExactlyAllAvailableRewards() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        bytes memory signature = _createSignature(user1, REWARD_AMOUNT, ORDER_ID);
        
        vm.prank(user1);
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);
        
        assertEq(sapienRewards.getAvailableRewards(), 0);
        assertEq(rewardToken.balanceOf(user1), REWARD_AMOUNT);
    }

    function test_Rewards_SetRewardTokenResetsAvailableRewards() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        assertEq(sapienRewards.getAvailableRewards(), REWARD_AMOUNT);
        
        MockERC20 newToken = new MockERC20("New Reward Token", "NEWREWARD", 18);
        
        vm.expectEmit(true, false, false, false);
        emit RewardTokenSet(address(newToken));
        
        vm.prank(admin);
        sapienRewards.setRewardToken(address(newToken));
        
        assertEq(sapienRewards.getAvailableRewards(), 0);
        assertEq(address(sapienRewards.rewardToken()), address(newToken));
    }

    function test_Rewards_SetRewardTokenRevertsOnZeroAddress() public {
        vm.prank(admin);
        vm.expectRevert(ISapienRewards.ZeroAddress.selector);
        sapienRewards.setRewardToken(address(0));
    }

    function test_Rewards_ClaimRewardRevertsOnExceedingMaxAmount() public {
        uint256 excessiveAmount = Const.MAX_REWARD_AMOUNT + 1;
        
        // Mint extra tokens to reward safe to cover the excessive amount
        rewardToken.mint(rewardSafe, excessiveAmount);
        
        // Approve the excessive amount
        vm.prank(rewardSafe);
        rewardToken.approve(address(sapienRewards), excessiveAmount);
        
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(excessiveAmount);
        
        bytes memory signature = _createSignature(user1, excessiveAmount, ORDER_ID);
        
        vm.prank(user1);
        vm.expectRevert();
        sapienRewards.claimReward(excessiveAmount, ORDER_ID, signature);
    }

    function test_Rewards_RecoverTokensRevertsOnInsufficientUnaccounted() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        // Try to recover more than available untracked tokens
        vm.prank(rewardSafe);
        vm.expectRevert(ISapienRewards.InsufficientUnaccountedTokens.selector);
        sapienRewards.recoverUnaccountedTokens(1);
    }

    function test_Rewards_ReconcileBalanceDoesNothingWhenBalancesMatch() public {
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(REWARD_AMOUNT);
        
        uint256 balanceBefore = sapienRewards.getAvailableRewards();
        
        vm.prank(rewardSafe);
        sapienRewards.reconcileBalance();
        
        // Should remain the same
        assertEq(sapienRewards.getAvailableRewards(), balanceBefore);
    }

    function test_Rewards_DomainSeparatorRecalculationOnChainFork() public {
        bytes32 originalDomainSeparator = sapienRewards.getDomainSeparator();
        
        // Simulate chain fork by changing chain ID
        vm.chainId(999);
        
        bytes32 newDomainSeparator = sapienRewards.getDomainSeparator();
        
        // Domain separator should be different after chain ID change
        assertNotEq(originalDomainSeparator, newDomainSeparator);
    }

    // ============================================
    // Error Condition Tests
    // ============================================

    function test_Rewards_WithdrawRevertsOnZeroAmount() public {
        vm.prank(rewardSafe);
        vm.expectRevert(ISapienRewards.InvalidAmount.selector);
        sapienRewards.withdrawRewards(0);
    }

    function test_Rewards_RecoverTokensOnlyByRewardSafe() public {
        // Send tokens directly
        rewardToken.mint(address(sapienRewards), 100 * 10**18);
        
        vm.prank(unauthorizedUser);
        vm.expectRevert("Only the Reward Safe can perform this");
        sapienRewards.recoverUnaccountedTokens(50 * 10**18);
    }

    function test_Rewards_ReconcileBalanceOnlyByRewardSafe() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert("Only the Reward Safe can perform this");
        sapienRewards.reconcileBalance();
    }

    // ============================================
    // Fuzz Tests
    // ============================================

    function test_Rewards_FuzzClaimReward(uint256 amount, bytes32 orderId) public {
        vm.assume(amount > 0 && amount <= Const.MAX_REWARD_AMOUNT && amount <= INITIAL_REWARD_BALANCE);
        vm.assume(orderId != bytes32(0));
        
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(amount);
        
        bytes memory signature = _createSignature(user1, amount, orderId);
        
        vm.prank(user1);
        bool success = sapienRewards.claimReward(amount, orderId, signature);
        
        assertTrue(success);
        assertEq(rewardToken.balanceOf(user1), amount);
        assertTrue(sapienRewards.getOrderRedeemedStatus(user1, orderId));
    }

    function test_Rewards_FuzzDepositAndWithdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        vm.assume(depositAmount > 0 && depositAmount <= INITIAL_REWARD_BALANCE);
        vm.assume(withdrawAmount > 0 && withdrawAmount <= depositAmount);
        
        vm.prank(rewardSafe);
        sapienRewards.depositRewards(depositAmount);
        
        assertEq(sapienRewards.getAvailableRewards(), depositAmount);
        
        vm.prank(rewardSafe);
        sapienRewards.withdrawRewards(withdrawAmount);
        
        assertEq(sapienRewards.getAvailableRewards(), depositAmount - withdrawAmount);
    }

    // ============================================
    // Helper Functions
    // ============================================

    function _createSignature(address user, uint256 amount, bytes32 orderId) internal view returns (bytes memory) {
        return _createSignatureWithKey(user, amount, orderId, rewardManagerPrivateKey);
    }

    function _createSignatureWithKey(address user, uint256 amount, bytes32 orderId, uint256 privateKey)
        internal
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(Const.REWARD_CLAIM_TYPEHASH, user, amount, orderId));
        bytes32 domainSeparator = sapienRewards.getDomainSeparator();
        bytes32 hash = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _mintAndApproveTokens(address to, uint256 amount) internal {
        rewardToken.mint(to, amount);
        vm.prank(to);
        rewardToken.approve(address(sapienRewards), amount);
    }
} 