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
    address public rewardAdmin = makeAddr("rewardAdmin");
    address public pauseManager = makeAddr("pauseManager");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public unauthorizedUser = makeAddr("unauthorizedUser");

    // Reward manager private key for signing
    uint256 public rewardManagerPrivateKey = 0x1234567890123456789012345678901234567890123456789012345678901234;
    address public rewardManagerSigner = vm.addr(rewardManagerPrivateKey);

    // Test constants
    uint256 public constant INITIAL_REWARD_BALANCE = 1000000 * 10 ** 18; // 1M tokens
    uint256 public constant REWARD_AMOUNT = 1000 * 10 ** 18; // 1K tokens

    bytes32 public ORDER_ID;
    bytes32 public ORDER_ID_2;

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
            rewardAdmin,
            rewardManagerSigner,
            pauseManager,
            address(rewardToken)
        );
        ERC1967Proxy sapienRewardsProxy = new ERC1967Proxy(address(sapienRewardsImpl), initData);
        sapienRewards = SapienRewards(address(sapienRewardsProxy));

        // Mint tokens to reward safe
        rewardToken.mint(rewardAdmin, INITIAL_REWARD_BALANCE);

        // Approve contract to spend tokens from reward safe
        vm.prank(rewardAdmin);
        rewardToken.approve(address(sapienRewards), INITIAL_REWARD_BALANCE);

        ORDER_ID = createOrderIdWithExpiry("order_id_string", uint64(block.timestamp + 2 * 60)); // 2 minutes
        ORDER_ID_2 = createOrderIdWithExpiry("order_id_string", uint64(block.timestamp + 3 * 60)); // 3 minutes
    }

    function createOrderIdWithExpiry(string memory identifier, uint64 expiryTimestamp)
        internal
        pure
        returns (bytes32)
    {
        bytes24 randomPart = bytes24(keccak256(abi.encodePacked(identifier, expiryTimestamp)));
        return bytes32(abi.encodePacked(randomPart, expiryTimestamp));
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
            rewardAdmin,
            rewardManagerSigner,
            makeAddr("pauseManager"),
            address(rewardToken)
        );
        ERC1967Proxy newProxy = new ERC1967Proxy(address(newImpl), initData);
        SapienRewards newContract = SapienRewards(address(newProxy));

        // Check roles
        assertTrue(newContract.hasRole(newContract.DEFAULT_ADMIN_ROLE(), admin));
        assertTrue(newContract.hasRole(Const.PAUSER_ROLE, makeAddr("pauseManager")));
        assertTrue(newContract.hasRole(Const.REWARD_ADMIN_ROLE, rewardAdmin));
        assertTrue(newContract.hasRole(Const.REWARD_MANAGER_ROLE, rewardManagerSigner));

        // Check token is set
        assertEq(address(newContract.rewardToken()), address(rewardToken));

        // Check version
        assertEq(newContract.version(), "1");
    }

    function test_Rewards_InitializeRevertsOnZeroAddresses() public {
        SapienRewards newImpl = new SapienRewards();

        // Test zero admin
        bytes memory initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            address(0),
            rewardAdmin,
            rewardManagerSigner,
            makeAddr("pauseManager"),
            address(rewardToken)
        );
        vm.expectRevert(ISapienRewards.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);

        // Test zero reward manager
        initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            admin,
            rewardAdmin,
            address(0),
            makeAddr("pauseManager"),
            address(rewardToken)
        );
        vm.expectRevert(ISapienRewards.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);

        // Test zero pause manager
        initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector, admin, rewardAdmin, rewardManagerSigner, address(0), address(rewardToken)
        );
        vm.expectRevert(ISapienRewards.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);

        // Test zero reward safe
        initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            admin,
            address(0),
            rewardManagerSigner,
            makeAddr("pauseManager"),
            address(rewardToken)
        );
        vm.expectRevert(ISapienRewards.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);

        // Test zero reward token
        initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            admin,
            rewardAdmin,
            rewardManagerSigner,
            makeAddr("pauseManager"),
            address(0)
        );
        vm.expectRevert(ISapienRewards.ZeroAddress.selector);
        new ERC1967Proxy(address(newImpl), initData);
    }

    function test_Rewards_CannotInitializeTwice() public {
        vm.expectRevert();
        sapienRewards.initialize(
            admin, rewardManagerSigner, makeAddr("pauseManager"), rewardAdmin, address(rewardToken)
        );
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
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")), unauthorizedUser, bytes32(0)
            )
        );
        sapienRewards.setRewardToken(address(newToken));
    }

    function test_Rewards_OnlyPauserCanPause() public {
        vm.prank(pauseManager);
        sapienRewards.pause();
        assertTrue(sapienRewards.paused());
    }

    function test_Rewards_OnlyPauserCanUnpause() public {
        // First pause the contract
        vm.prank(pauseManager);
        sapienRewards.pause();
        assertTrue(sapienRewards.paused());

        // Then unpause it
        vm.prank(pauseManager);
        sapienRewards.unpause();
        assertFalse(sapienRewards.paused());
    }

    function test_Rewards_NonPauserCannotPause() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                unauthorizedUser,
                Const.PAUSER_ROLE
            )
        );
        sapienRewards.pause();
    }

    function test_Rewards_NonPauserCannotUnpause() public {
        // First pause the contract
        vm.prank(pauseManager);
        sapienRewards.pause();

        // Unauthorized user cannot unpause
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                unauthorizedUser,
                Const.PAUSER_ROLE
            )
        );
        sapienRewards.unpause();
    }

    function test_Rewards_OnlyRewardSafeCanDeposit() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        assertEq(sapienRewards.getAvailableRewards(), REWARD_AMOUNT);
    }

    function test_Rewards_NonRewardSafeCannotDeposit() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                unauthorizedUser,
                Const.REWARD_ADMIN_ROLE
            )
        );
        sapienRewards.depositRewards(REWARD_AMOUNT);
    }

    // ============================================
    // Deposit/Withdraw Tests
    // ============================================

    function test_Rewards_DepositRewards() public {
        vm.expectEmit(true, false, false, true);
        emit RewardsDeposited(rewardAdmin, REWARD_AMOUNT, REWARD_AMOUNT);

        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        assertEq(sapienRewards.getAvailableRewards(), REWARD_AMOUNT);
        assertEq(rewardToken.balanceOf(address(sapienRewards)), REWARD_AMOUNT);
    }

    function test_Rewards_DepositRevertsOnZeroAmount() public {
        vm.prank(rewardAdmin);
        vm.expectRevert(ISapienRewards.InvalidAmount.selector);
        sapienRewards.depositRewards(0);
    }

    function test_Rewards_WithdrawRewards() public {
        // First deposit
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        uint256 withdrawAmount = REWARD_AMOUNT / 2;

        vm.expectEmit(true, false, false, true);
        emit RewardsWithdrawn(rewardAdmin, withdrawAmount, REWARD_AMOUNT - withdrawAmount);

        vm.prank(rewardAdmin);
        sapienRewards.withdrawRewards(withdrawAmount);

        assertEq(sapienRewards.getAvailableRewards(), REWARD_AMOUNT - withdrawAmount);
    }

    function test_Rewards_WithdrawRevertsOnInsufficientBalance() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        vm.prank(rewardAdmin);
        vm.expectRevert(ISapienRewards.InsufficientAvailableRewards.selector);
        sapienRewards.withdrawRewards(REWARD_AMOUNT + 1);
    }

    function test_Rewards_ReconcileBalance() public {
        // Deposit rewards normally
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Send tokens directly to contract (simulating untracked deposit)
        uint256 untrackedAmount = 500 * 10 ** 18;
        rewardToken.mint(address(sapienRewards), untrackedAmount);

        uint256 expectedTotal = REWARD_AMOUNT + untrackedAmount;

        vm.expectEmit(false, false, false, true);
        emit RewardsReconciled(untrackedAmount, expectedTotal);

        vm.prank(rewardAdmin);
        sapienRewards.reconcileBalance();

        assertEq(sapienRewards.getAvailableRewards(), expectedTotal);
    }

    function test_Rewards_RecoverUnaccountedTokens() public {
        // Deposit normally
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Send tokens directly
        uint256 untrackedAmount = 500 * 10 ** 18;
        rewardToken.mint(address(sapienRewards), untrackedAmount);

        uint256 recoverAmount = 200 * 10 ** 18;

        vm.expectEmit(true, false, false, true);
        emit UnaccountedTokensRecovered(rewardAdmin, recoverAmount);

        vm.prank(rewardAdmin);
        sapienRewards.recoverUnaccountedTokens(recoverAmount);

        assertEq(rewardToken.balanceOf(rewardAdmin), INITIAL_REWARD_BALANCE - REWARD_AMOUNT + recoverAmount);
    }

    // ============================================
    // EIP-712 Signature Tests
    // ============================================

    function test_Rewards_ClaimRewardWithValidSignature() public {
        // Deposit rewards
        vm.prank(rewardAdmin);
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
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create signature with wrong private key
        uint256 wrongPrivateKey = 0x9876543210987654321098765432109876543210987654321098765432109876;
        bytes memory wrongSignature = _createSignatureWithKey(user1, REWARD_AMOUNT, ORDER_ID, wrongPrivateKey);

        vm.prank(user1);
        vm.expectRevert();
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, wrongSignature);
    }

    function test_Rewards_ClaimRewardRevertsOnMalformedSignature() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create malformed signature (wrong length)
        bytes memory malformedSignature = new bytes(32); // Too short, should be 65 bytes

        vm.prank(user1);
        vm.expectRevert();
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, malformedSignature);
    }

    function test_Rewards_ClaimRewardRevertsOnInvalidSignatureFormat() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create signature with invalid format (all zeros)
        bytes memory invalidSignature = new bytes(65);

        vm.prank(user1);
        vm.expectRevert();
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, invalidSignature);
    }

    function test_Rewards_ClaimRewardRevertsOnECDSARecoveryError() public {
        vm.prank(rewardAdmin);
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
        vm.prank(rewardAdmin);
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
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        vm.prank(pauseManager);
        sapienRewards.pause();

        bytes memory signature = _createSignature(user1, REWARD_AMOUNT, ORDER_ID);

        vm.prank(user1);
        vm.expectRevert();
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);
    }

    function test_Rewards_RewardManagerCannotClaim() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // The validation happens in validateAndGetHashToSign, so we test that directly
        vm.expectRevert(ISapienRewards.RewardsManagerCannotClaim.selector);
        sapienRewards.validateAndGetHashToSign(rewardManagerSigner, REWARD_AMOUNT, ORDER_ID);
    }

    // ============================================
    // Validation Tests
    // ============================================

    function test_Rewards_ValidateAndGetHashToSign() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        vm.prank(rewardManagerSigner);
        bytes32 hash = sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, ORDER_ID);

        assertNotEq(hash, bytes32(0));
    }

    function test_Rewards_ValidateAndGetHashToSignAccessibleToAll() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Should work for any user (no access control)
        vm.prank(unauthorizedUser);
        bytes32 hash = sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, ORDER_ID);

        // Hash should be non-zero
        assertNotEq(hash, bytes32(0));
    }

    function test_Rewards_ValidateAndGetHashToSignWorksWhenPaused() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        vm.prank(pauseManager);
        sapienRewards.pause();

        // Should work even when paused (view function)
        vm.prank(rewardManagerSigner);
        bytes32 hash = sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, ORDER_ID);

        // Hash should be non-zero
        assertNotEq(hash, bytes32(0));
    }

    // ============================================
    // View Function Tests
    // ============================================

    function test_Rewards_GetAvailableRewards() public {
        assertEq(sapienRewards.getAvailableRewards(), 0);

        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        assertEq(sapienRewards.getAvailableRewards(), REWARD_AMOUNT);
    }

    function test_Rewards_GetRewardTokenBalances() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        (uint256 availableBalance, uint256 totalContractBalance) = sapienRewards.getRewardTokenBalances();

        assertEq(availableBalance, REWARD_AMOUNT);
        assertEq(totalContractBalance, REWARD_AMOUNT);

        // Send tokens directly to contract
        rewardToken.mint(address(sapienRewards), 500 * 10 ** 18);

        (availableBalance, totalContractBalance) = sapienRewards.getRewardTokenBalances();

        assertEq(availableBalance, REWARD_AMOUNT);
        assertEq(totalContractBalance, REWARD_AMOUNT + 500 * 10 ** 18);
    }

    function test_Rewards_GetOrderRedeemedStatus() public {
        assertFalse(sapienRewards.getOrderRedeemedStatus(user1, ORDER_ID));

        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        bytes memory signature = _createSignature(user1, REWARD_AMOUNT, ORDER_ID);

        vm.prank(user1);
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);

        assertTrue(sapienRewards.getOrderRedeemedStatus(user1, ORDER_ID));
    }

    function test_Rewards_VersionIsCorrect() public view {
        assertEq(sapienRewards.version(), "1");
    }

    // ============================================
    // Edge Case Tests
    // ============================================

    function test_Rewards_MultipleUsersCanClaimDifferentOrders() public {
        vm.prank(rewardAdmin);
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
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        bytes memory signature = _createSignature(user1, REWARD_AMOUNT, ORDER_ID);

        vm.prank(user1);
        sapienRewards.claimReward(REWARD_AMOUNT, ORDER_ID, signature);

        assertEq(sapienRewards.getAvailableRewards(), 0);
        assertEq(rewardToken.balanceOf(user1), REWARD_AMOUNT);
    }

    function test_Rewards_SetRewardTokenResetsAvailableRewards() public {
        vm.prank(rewardAdmin);
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
        rewardToken.mint(rewardAdmin, excessiveAmount);

        // Approve the excessive amount
        vm.prank(rewardAdmin);
        rewardToken.approve(address(sapienRewards), excessiveAmount);

        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(excessiveAmount);

        // Test that validateAndGetHashToSign rejects excessive amounts
        vm.expectRevert(
            abi.encodeWithSelector(
                ISapienRewards.RewardExceedsMaxAmount.selector, excessiveAmount, Const.MAX_REWARD_AMOUNT
            )
        );
        sapienRewards.validateAndGetHashToSign(user1, excessiveAmount, ORDER_ID);
    }

    function test_Rewards_RecoverTokensRevertsOnInsufficientUnaccounted() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Try to recover more than available untracked tokens
        vm.prank(rewardAdmin);
        vm.expectRevert(ISapienRewards.InsufficientUnaccountedTokens.selector);
        sapienRewards.recoverUnaccountedTokens(1);
    }

    function test_Rewards_ReconcileBalanceDoesNothingWhenBalancesMatch() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        uint256 balanceBefore = sapienRewards.getAvailableRewards();

        vm.prank(rewardAdmin);
        sapienRewards.reconcileBalance();

        // Should remain the same
        assertEq(sapienRewards.getAvailableRewards(), balanceBefore);
    }

    // ============================================
    // Error Condition Tests
    // ============================================

    function test_Rewards_WithdrawRevertsOnZeroAmount() public {
        vm.prank(rewardAdmin);
        vm.expectRevert(ISapienRewards.InvalidAmount.selector);
        sapienRewards.withdrawRewards(0);
    }

    function test_Rewards_RecoverTokensOnlyByRewardSafe() public {
        // Send tokens directly
        rewardToken.mint(address(sapienRewards), 100 * 10 ** 18);

        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                unauthorizedUser,
                Const.REWARD_ADMIN_ROLE
            )
        );
        sapienRewards.recoverUnaccountedTokens(50 * 10 ** 18);
    }

    function test_Rewards_ReconcileBalanceOnlyByRewardSafe() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(
            abi.encodeWithSelector(
                bytes4(keccak256("AccessControlUnauthorizedAccount(address,bytes32)")),
                unauthorizedUser,
                Const.REWARD_ADMIN_ROLE
            )
        );
        sapienRewards.reconcileBalance();
    }

    // ============================================
    // Fuzz Tests
    // ============================================

    function test_Rewards_FuzzClaimReward(uint256 amount, uint64 expiryOffset) public {
        vm.assume(amount > 0 && amount <= Const.MAX_REWARD_AMOUNT && amount <= INITIAL_REWARD_BALANCE);
        vm.assume(expiryOffset >= Const.MIN_ORDER_EXPIRY_DURATION && expiryOffset <= Const.MAX_ORDER_EXPIRY_DURATION);

        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(amount);

        // Create a valid orderId with proper expiry timestamp
        uint64 validExpiry = uint64(block.timestamp + expiryOffset);
        bytes32 orderId = createOrderIdWithExpiry("order_id_string", validExpiry);

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

        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(depositAmount);

        assertEq(sapienRewards.getAvailableRewards(), depositAmount);

        vm.prank(rewardAdmin);
        sapienRewards.withdrawRewards(withdrawAmount);

        assertEq(sapienRewards.getAvailableRewards(), depositAmount - withdrawAmount);
    }

    // ============================================
    // Expiry Edge Case Tests
    // ============================================

    function test_Rewards_OrderExpiryTooSoon() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create an order that expires too soon (less than MIN_ORDER_EXPIRY_DURATION)
        uint64 tooSoonExpiry = uint64(block.timestamp + Const.MIN_ORDER_EXPIRY_DURATION - 1);
        bytes32 tooSoonOrderId = createOrderIdWithExpiry("order_id_string", tooSoonExpiry);

        vm.expectRevert(abi.encodeWithSelector(ISapienRewards.ExpiryTooSoon.selector, tooSoonOrderId, tooSoonExpiry));
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, tooSoonOrderId);
    }

    function test_Rewards_OrderExpiryTooFar() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create an order that expires too far in the future (more than MAX_ORDER_EXPIRY_DURATION)
        uint64 tooFarExpiry = uint64(block.timestamp + Const.MAX_ORDER_EXPIRY_DURATION + 1);
        bytes32 tooFarOrderId = createOrderIdWithExpiry("order_id_string", tooFarExpiry);

        vm.expectRevert(abi.encodeWithSelector(ISapienRewards.ExpiryTooFar.selector, tooFarOrderId, tooFarExpiry));
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, tooFarOrderId);
    }

    function test_Rewards_OrderExpired() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create an order that has already expired but is after the "too soon" threshold
        // This needs to be expired but not caught by the "too soon" check
        uint64 expiredTimestamp = uint64(block.timestamp + Const.MIN_ORDER_EXPIRY_DURATION);
        bytes32 expiredOrderId = createOrderIdWithExpiry("order_id_string", expiredTimestamp);

        // Advance time past the expiry
        vm.warp(expiredTimestamp + 1);

        vm.expectRevert(abi.encodeWithSelector(ISapienRewards.OrderExpired.selector, expiredOrderId, expiredTimestamp));
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, expiredOrderId);
    }

    function test_Rewards_OrderExpiryAtMinBoundary() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create an order at exactly the minimum expiry duration
        uint64 minValidExpiry = uint64(block.timestamp + Const.MIN_ORDER_EXPIRY_DURATION);
        bytes32 minValidOrderId = createOrderIdWithExpiry("order_id_string", minValidExpiry);

        // Should not revert
        bytes32 hash = sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, minValidOrderId);
        assertNotEq(hash, bytes32(0));
    }

    function test_Rewards_OrderExpiryAtMaxBoundary() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create an order at exactly the maximum expiry duration
        uint64 maxValidExpiry = uint64(block.timestamp + Const.MAX_ORDER_EXPIRY_DURATION);
        bytes32 maxValidOrderId = createOrderIdWithExpiry("order_id_string", maxValidExpiry);

        // Should not revert
        bytes32 hash = sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, maxValidOrderId);
        assertNotEq(hash, bytes32(0));
    }

    function test_Rewards_OrderExpiryExactlyAtCurrentTime() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create an order that expires exactly at current block timestamp
        uint64 currentTimestamp = uint64(block.timestamp);
        bytes32 currentTimeOrderId = createOrderIdWithExpiry("order_id_string", currentTimestamp);

        // Since the expiry is at current time, it's expired
        // The "expired" check happens first now, so expect that error
        vm.expectRevert(
            abi.encodeWithSelector(ISapienRewards.OrderExpired.selector, currentTimeOrderId, currentTimestamp)
        );
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, currentTimeOrderId);
    }

    function test_Rewards_ClaimRewardFailsWithExpiredOrder() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create an order that will expire
        uint64 expiredTimestamp = uint64(block.timestamp + Const.MIN_ORDER_EXPIRY_DURATION);
        bytes32 expiredOrderId = createOrderIdWithExpiry("order_id_string", expiredTimestamp);

        // Advance time past the expiry
        vm.warp(expiredTimestamp + 1);

        // Creating signature should fail because validation fails
        vm.expectRevert(abi.encodeWithSelector(ISapienRewards.OrderExpired.selector, expiredOrderId, expiredTimestamp));
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, expiredOrderId);
    }

    function test_Rewards_ClaimRewardSucceedsWithValidExpiry() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create a valid order (2 minutes from now)
        uint64 validExpiry = uint64(block.timestamp + 2 * 60);
        bytes32 validOrderId = createOrderIdWithExpiry("order_id_string", validExpiry);

        bytes memory signature = _createSignature(user1, REWARD_AMOUNT, validOrderId);

        vm.prank(user1);
        bool success = sapienRewards.claimReward(REWARD_AMOUNT, validOrderId, signature);

        assertTrue(success);
        assertEq(rewardToken.balanceOf(user1), REWARD_AMOUNT);
    }

    function test_Rewards_TimeProgressionCausesExpiry() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create an order that expires in 2 minutes
        uint64 futureExpiry = uint64(block.timestamp + 2 * 60);
        bytes32 futureOrderId = createOrderIdWithExpiry("order_id_string", futureExpiry);

        // Should work initially
        bytes32 hash = sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, futureOrderId);
        assertNotEq(hash, bytes32(0));

        // Advance time past expiry
        vm.warp(futureExpiry + 1);

        // Should now fail
        vm.expectRevert(abi.encodeWithSelector(ISapienRewards.OrderExpired.selector, futureOrderId, futureExpiry));
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, futureOrderId);
    }

    function test_Rewards_ExpiryValidationWorksWithZeroOrderId() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Zero orderId should fail before expiry validation
        vm.expectRevert(abi.encodeWithSelector(ISapienRewards.InvalidOrderId.selector, bytes32(0)));
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, bytes32(0));
    }

    function test_Rewards_ExpiryValidationWithMaxUint64() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create an order with max uint64 timestamp (far future)
        uint64 maxTimestamp = type(uint64).max;
        bytes32 maxOrderId = createOrderIdWithExpiry("order_id_string", maxTimestamp);

        // Should fail as too far in future
        vm.expectRevert(abi.encodeWithSelector(ISapienRewards.ExpiryTooFar.selector, maxOrderId, maxTimestamp));
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, maxOrderId);
    }

    function test_Rewards_ExpiryValidationWithMinUint64() public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        // Create an order with timestamp 0 (definitely expired)
        uint64 minTimestamp = 0;
        bytes32 minOrderId = createOrderIdWithExpiry("order_id_string", minTimestamp);

        // Should fail as expired (this check happens first now)
        vm.expectRevert(abi.encodeWithSelector(ISapienRewards.OrderExpired.selector, minOrderId, minTimestamp));
        sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, minOrderId);
    }

    function test_Rewards_FuzzExpiryValidation(uint64 expiryTimestamp) public {
        vm.prank(rewardAdmin);
        sapienRewards.depositRewards(REWARD_AMOUNT);

        bytes32 orderId = createOrderIdWithExpiry("order_id_string", expiryTimestamp);

        if (expiryTimestamp < block.timestamp) {
            // Should fail as expired (this check happens first)
            vm.expectRevert(abi.encodeWithSelector(ISapienRewards.OrderExpired.selector, orderId, expiryTimestamp));
            sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, orderId);
        } else if (expiryTimestamp == block.timestamp) {
            // Should fail as expired (exactly at current time)
            vm.expectRevert(abi.encodeWithSelector(ISapienRewards.OrderExpired.selector, orderId, expiryTimestamp));
            sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, orderId);
        } else if (expiryTimestamp < block.timestamp + Const.MIN_ORDER_EXPIRY_DURATION) {
            // Should fail as too soon
            vm.expectRevert(abi.encodeWithSelector(ISapienRewards.ExpiryTooSoon.selector, orderId, expiryTimestamp));
            sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, orderId);
        } else if (expiryTimestamp > block.timestamp + Const.MAX_ORDER_EXPIRY_DURATION) {
            // Should fail as too far
            vm.expectRevert(abi.encodeWithSelector(ISapienRewards.ExpiryTooFar.selector, orderId, expiryTimestamp));
            sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, orderId);
        } else {
            // Should succeed (valid range)
            bytes32 hash = sapienRewards.validateAndGetHashToSign(user1, REWARD_AMOUNT, orderId);
            assertNotEq(hash, bytes32(0));
        }
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
        bytes32 hash = sapienRewards.validateAndGetHashToSign(user, amount, orderId);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }

    function _mintAndApproveTokens(address to, uint256 amount) internal {
        rewardToken.mint(to, amount);
        vm.prank(to);
        rewardToken.approve(address(sapienRewards), amount);
    }

    function test_Rewards_Roles() public view {
        assertEq(sapienRewards.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
        assertEq(sapienRewards.REWARD_ADMIN_ROLE(), keccak256("REWARD_ADMIN_ROLE"));
        assertEq(sapienRewards.REWARD_MANAGER_ROLE(), keccak256("REWARD_MANAGER_ROLE"));
    }
}
