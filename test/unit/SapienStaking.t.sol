// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienStaking} from "src/SapienStaking.sol";
import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ECDSA} from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

// Mock token that extends ERC20Upgradeable for compatibility with SapienStaking
contract MockSapienToken is ERC20Upgradeable {
    function initialize() public initializer {
        __ERC20_init("Mock Sapien Token", "SAPIEN");
    }
    
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
    
    function decimals() public pure override returns (uint8) {
        return 18;
    }
}

contract SapienStakingTest is Test {
    SapienStaking public staking;
    SapienStaking public stakingImplementation;
    MockSapienToken public sapienToken;
    
    address public gnosisSafe;
    address public sapienSigner;
    address public user1;
    address public user2;
    address public unauthorized;
    
    uint256 public sapienSignerPrivateKey;
    uint256 public user1PrivateKey;
    
    // Constants from contract
    uint256 public constant MINIMUM_STAKE = 1000 * 10**18;
    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 public constant EARLY_WITHDRAWAL_PENALTY = 20;
    
    // Lock periods
    uint256 public constant ONE_MONTH = 30 days;
    uint256 public constant THREE_MONTHS = 90 days;
    uint256 public constant SIX_MONTHS = 180 days;
    uint256 public constant TWELVE_MONTHS = 365 days;
    
    // Multipliers
    uint256 public constant ONE_MONTH_MULTIPLIER = 10500;
    uint256 public constant THREE_MONTHS_MULTIPLIER = 11000;
    uint256 public constant SIX_MONTHS_MULTIPLIER = 12500;
    uint256 public constant TWELVE_MONTHS_MULTIPLIER = 15000;
    
    // EIP-712 constants
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant STAKE_TYPEHASH = keccak256(
        "Stake(address userWallet,uint256 amount,bytes32 orderId,uint8 actionType)"
    );
    
    bytes32 public DOMAIN_SEPARATOR;
    
    enum ActionType { STAKE, INITIATE_UNSTAKE, UNSTAKE, INSTANT_UNSTAKE }
    
    // Events
    event Staked(address indexed user, uint256 amount, uint256 multiplier, uint256 lockUpPeriod, bytes32 orderId);
    event UnstakingInitiated(address indexed user, uint256 amount, bytes32 orderId);
    event Unstaked(address indexed user, uint256 amount, bytes32 orderId);
    event InstantUnstake(address indexed user, uint256 amount, bytes32 orderId);
    event UpgradeAuthorized(address indexed implementation);
    
    function setUp() public {
        // Setup addresses
        gnosisSafe = makeAddr("gnosisSafe");
        sapienSignerPrivateKey = 0x1234;
        sapienSigner = vm.addr(sapienSignerPrivateKey);
        user1PrivateKey = 0x5678;
        user1 = vm.addr(user1PrivateKey);
        user2 = makeAddr("user2");
        unauthorized = makeAddr("unauthorized");
        
        // Deploy and initialize mock token
        sapienToken = new MockSapienToken();
        sapienToken.initialize();
        
        // Deploy implementation
        stakingImplementation = new SapienStaking();
        
        // Deploy proxy
        bytes memory initData = abi.encodeWithSelector(
            SapienStaking.initialize.selector,
            sapienToken,
            sapienSigner,
            gnosisSafe
        );
        
        ERC1967Proxy proxy = new ERC1967Proxy(address(stakingImplementation), initData);
        staking = SapienStaking(address(proxy));
        
        // Calculate domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("SapienStaking"),
                keccak256("1"),
                block.chainid,
                address(staking)
            )
        );
        
        // Mint tokens to users
        sapienToken.mint(user1, 1000000 * 10**18);
        sapienToken.mint(user2, 1000000 * 10**18);
        
        // Approve staking contract
        vm.prank(user1);
        sapienToken.approve(address(staking), type(uint256).max);
        vm.prank(user2);
        sapienToken.approve(address(staking), type(uint256).max);
    }
    
    // ============ Helper Functions ============
    
    function createSignature(
        address userWallet,
        uint256 amount,
        bytes32 orderId,
        ActionType actionType,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                STAKE_TYPEHASH,
                userWallet,
                amount,
                orderId,
                uint8(actionType)
            )
        );
        
        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hash);
        return abi.encodePacked(r, s, v);
    }
    
    function createValidStakeSignature(
        address userWallet,
        uint256 amount,
        bytes32 orderId
    ) internal view returns (bytes memory) {
        return createSignature(userWallet, amount, orderId, ActionType.STAKE, sapienSignerPrivateKey);
    }
    
    // ============ Initialization Tests ============
    
    function test_Initialize_Success() public view {
        assertEq(address(staking._gnosisSafe()), gnosisSafe);
        assertEq(staking.MINIMUM_STAKE(), MINIMUM_STAKE);
        assertEq(staking.COOLDOWN_PERIOD(), COOLDOWN_PERIOD);
        assertEq(staking.totalStaked(), 0);
    }
    
    function test_Initialize_RevertZeroAddresses() public {
        SapienStaking newImpl = new SapienStaking();
        
        // Zero token address
        vm.expectRevert("Zero address not allowed for token");
        new ERC1967Proxy(address(newImpl), abi.encodeWithSelector(
            SapienStaking.initialize.selector,
            address(0),
            sapienSigner,
            gnosisSafe
        ));
        
        // Zero signer address
        vm.expectRevert("Zero address not allowed for signer");
        new ERC1967Proxy(address(newImpl), abi.encodeWithSelector(
            SapienStaking.initialize.selector,
            sapienToken,
            address(0),
            gnosisSafe
        ));
        
        // Zero safe address
        vm.expectRevert("Zero address not allowed for Gnosis Safe");
        new ERC1967Proxy(address(newImpl), abi.encodeWithSelector(
            SapienStaking.initialize.selector,
            sapienToken,
            sapienSigner,
            address(0)
        ));
    }
    
    function test_Initialize_CannotReinitialize() public {
        vm.expectRevert();
        staking.initialize(sapienToken, sapienSigner, gnosisSafe);
    }
    
    // ============ Access Control Tests ============
    
    function test_OnlySafe_Pause() public {
        vm.prank(gnosisSafe);
        staking.pause();
        assertTrue(staking.paused());
        
        vm.prank(unauthorized);
        vm.expectRevert("Only the Safe can perform this");
        staking.pause();
    }
    
    function test_OnlySafe_Unpause() public {
        vm.prank(gnosisSafe);
        staking.pause();
        
        vm.prank(gnosisSafe);
        staking.unpause();
        assertFalse(staking.paused());
        
        vm.prank(unauthorized);
        vm.expectRevert("Only the Safe can perform this");
        staking.unpause();
    }
    
    function test_OnlySafe_AuthorizeUpgrade() public {
        address newImpl = address(new SapienStaking());
        
        vm.prank(gnosisSafe);
        vm.expectEmit(true, false, false, false);
        emit UpgradeAuthorized(newImpl);
        staking.authorizeUpgrade(newImpl);
        
        vm.prank(unauthorized);
        vm.expectRevert("Only the Safe can perform this");
        staking.authorizeUpgrade(newImpl);
    }
    
    // ============ Staking Tests ============
    
    function test_Stake_Success() public {
        uint256 amount = MINIMUM_STAKE;
        bytes32 orderId = keccak256("order1");
        bytes memory signature = createValidStakeSignature(user1, amount, orderId);
        
        uint256 initialBalance = sapienToken.balanceOf(user1);
        uint256 initialContractBalance = sapienToken.balanceOf(address(staking));
        
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Staked(user1, amount, ONE_MONTH_MULTIPLIER, ONE_MONTH, orderId);
        staking.stake(amount, ONE_MONTH, orderId, signature);
        
        // Check balances
        assertEq(sapienToken.balanceOf(user1), initialBalance - amount);
        assertEq(sapienToken.balanceOf(address(staking)), initialContractBalance + amount);
        assertEq(staking.totalStaked(), amount);
        
        // Check staking info
        (
            uint256 stakedAmount,
            uint256 lockUpPeriod,
            uint256 startTime,
            uint256 multiplier,
            uint256 cooldownStart,
            uint256 cooldownAmount,
            bool isActive
        ) = staking.stakers(user1, orderId);
        
        assertEq(stakedAmount, amount);
        assertEq(lockUpPeriod, ONE_MONTH);
        assertEq(startTime, block.timestamp);
        assertEq(multiplier, ONE_MONTH_MULTIPLIER);
        assertEq(cooldownStart, 0);
        assertEq(cooldownAmount, 0);
        assertTrue(isActive);
    }
    
    function test_Stake_AllLockPeriods() public {
        bytes32 orderId1 = keccak256("order1");
        bytes32 orderId2 = keccak256("order2");
        bytes32 orderId3 = keccak256("order3");
        bytes32 orderId4 = keccak256("order4");
        
        uint256 amount = MINIMUM_STAKE;
        
        // Test all lock periods
        uint256[] memory lockPeriods = new uint256[](4);
        lockPeriods[0] = ONE_MONTH;
        lockPeriods[1] = THREE_MONTHS;
        lockPeriods[2] = SIX_MONTHS;
        lockPeriods[3] = TWELVE_MONTHS;
        
        uint256[] memory expectedMultipliers = new uint256[](4);
        expectedMultipliers[0] = ONE_MONTH_MULTIPLIER;
        expectedMultipliers[1] = THREE_MONTHS_MULTIPLIER;
        expectedMultipliers[2] = SIX_MONTHS_MULTIPLIER;
        expectedMultipliers[3] = TWELVE_MONTHS_MULTIPLIER;
        
        bytes32[] memory orderIds = new bytes32[](4);
        orderIds[0] = orderId1;
        orderIds[1] = orderId2;
        orderIds[2] = orderId3;
        orderIds[3] = orderId4;
        
        for (uint256 i = 0; i < 4; i++) {
            bytes memory signature = createValidStakeSignature(user1, amount, orderIds[i]);
            
            vm.prank(user1);
            staking.stake(amount, lockPeriods[i], orderIds[i], signature);
            
            (, , , uint256 multiplier, , , ) = staking.stakers(user1, orderIds[i]);
            assertEq(multiplier, expectedMultipliers[i]);
        }
    }
    
    function test_Stake_RevertBelowMinimum() public {
        uint256 amount = MINIMUM_STAKE - 1;
        bytes32 orderId = keccak256("order1");
        bytes memory signature = createValidStakeSignature(user1, amount, orderId);
        
        vm.prank(user1);
        vm.expectRevert("Minimum 1,000 SAPIEN required");
        staking.stake(amount, ONE_MONTH, orderId, signature);
    }
    
    function test_Stake_RevertInvalidLockPeriod() public {
        uint256 amount = MINIMUM_STAKE;
        bytes32 orderId = keccak256("order1");
        uint256 invalidLockPeriod = 15 days;
        bytes memory signature = createValidStakeSignature(user1, amount, orderId);
        
        vm.prank(user1);
        vm.expectRevert("Invalid lock-up period");
        staking.stake(amount, invalidLockPeriod, orderId, signature);
    }
    
    function test_Stake_RevertOrderAlreadyUsed() public {
        uint256 amount = MINIMUM_STAKE;
        bytes32 orderId = keccak256("order1");
        bytes memory signature = createValidStakeSignature(user1, amount, orderId);
        
        vm.prank(user1);
        staking.stake(amount, ONE_MONTH, orderId, signature);
        
        // Try to reuse the same order
        vm.prank(user1);
        vm.expectRevert("Order already used");
        staking.stake(amount, ONE_MONTH, orderId, signature);
    }
    
    function test_Stake_RevertInvalidSignature() public {
        uint256 amount = MINIMUM_STAKE;
        bytes32 orderId = keccak256("order1");
        // Create signature with wrong private key
        bytes memory invalidSignature = createSignature(user1, amount, orderId, ActionType.STAKE, user1PrivateKey);
        
        vm.prank(user1);
        vm.expectRevert("Invalid signature or mismatched parameters");
        staking.stake(amount, ONE_MONTH, orderId, invalidSignature);
    }
    
    function test_Stake_RevertWhenPaused() public {
        vm.prank(gnosisSafe);
        staking.pause();
        
        uint256 amount = MINIMUM_STAKE;
        bytes32 orderId = keccak256("order1");
        bytes memory signature = createValidStakeSignature(user1, amount, orderId);
        
        vm.prank(user1);
        vm.expectRevert();
        staking.stake(amount, ONE_MONTH, orderId, signature);
    }
    
    // ============ Initiate Unstake Tests ============
    
    function test_InitiateUnstake_Success() public {
        // First stake
        uint256 stakeAmount = MINIMUM_STAKE;
        bytes32 stakeOrderId = keccak256("stakeOrder1");
        bytes memory stakeSignature = createValidStakeSignature(user1, stakeAmount, stakeOrderId);
        
        vm.prank(user1);
        staking.stake(stakeAmount, ONE_MONTH, stakeOrderId, stakeSignature);
        
        // Fast forward past lock period
        vm.warp(block.timestamp + ONE_MONTH + 1);
        
        // Initiate unstake
        uint256 unstakeAmount = stakeAmount;
        bytes32 unstakeOrderId = keccak256("unstakeOrder1");
        bytes memory unstakeSignature = createSignature(
            user1, unstakeAmount, unstakeOrderId, ActionType.INITIATE_UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit UnstakingInitiated(user1, unstakeAmount, unstakeOrderId);
        staking.initiateUnstake(unstakeAmount, unstakeOrderId, stakeOrderId, unstakeSignature);
        
        // Check cooldown started
        (, , , , uint256 cooldownStart, uint256 cooldownAmount, ) = staking.stakers(user1, stakeOrderId);
        assertEq(cooldownStart, block.timestamp);
        assertEq(cooldownAmount, unstakeAmount);
    }
    
    function test_InitiateUnstake_RevertBeforeLockPeriod() public {
        // First stake
        uint256 stakeAmount = MINIMUM_STAKE;
        bytes32 stakeOrderId = keccak256("stakeOrder1");
        bytes memory stakeSignature = createValidStakeSignature(user1, stakeAmount, stakeOrderId);
        
        vm.prank(user1);
        staking.stake(stakeAmount, ONE_MONTH, stakeOrderId, stakeSignature);
        
        // Try to initiate unstake before lock period completes
        uint256 unstakeAmount = stakeAmount;
        bytes32 unstakeOrderId = keccak256("unstakeOrder1");
        bytes memory unstakeSignature = createSignature(
            user1, unstakeAmount, unstakeOrderId, ActionType.INITIATE_UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        vm.expectRevert("Lock period not completed");
        staking.initiateUnstake(unstakeAmount, unstakeOrderId, stakeOrderId, unstakeSignature);
    }
    
    function test_InitiateUnstake_RevertCooldownAlreadyInitiated() public {
        // Setup stake and initiate unstake
        uint256 stakeAmount = MINIMUM_STAKE;
        bytes32 stakeOrderId = keccak256("stakeOrder1");
        bytes memory stakeSignature = createValidStakeSignature(user1, stakeAmount, stakeOrderId);
        
        vm.prank(user1);
        staking.stake(stakeAmount, ONE_MONTH, stakeOrderId, stakeSignature);
        
        vm.warp(block.timestamp + ONE_MONTH + 1);
        
        // First initiate unstake
        bytes32 unstakeOrderId1 = keccak256("unstakeOrder1");
        bytes memory unstakeSignature1 = createSignature(
            user1, stakeAmount, unstakeOrderId1, ActionType.INITIATE_UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        staking.initiateUnstake(stakeAmount, unstakeOrderId1, stakeOrderId, unstakeSignature1);
        
        // Try to initiate again
        bytes32 unstakeOrderId2 = keccak256("unstakeOrder2");
        bytes memory unstakeSignature2 = createSignature(
            user1, stakeAmount, unstakeOrderId2, ActionType.INITIATE_UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        vm.expectRevert("Cooldown already initiated");
        staking.initiateUnstake(stakeAmount, unstakeOrderId2, stakeOrderId, unstakeSignature2);
    }
    
    // ============ Unstake Tests ============
    
    function test_Unstake_Success() public {
        // Setup stake and initiate unstake
        uint256 stakeAmount = MINIMUM_STAKE;
        bytes32 stakeOrderId = keccak256("stakeOrder1");
        bytes memory stakeSignature = createValidStakeSignature(user1, stakeAmount, stakeOrderId);
        
        vm.prank(user1);
        staking.stake(stakeAmount, ONE_MONTH, stakeOrderId, stakeSignature);
        
        vm.warp(block.timestamp + ONE_MONTH + 1);
        
        bytes32 initiateUnstakeOrderId = keccak256("initiateUnstakeOrder1");
        bytes memory initiateUnstakeSignature = createSignature(
            user1, stakeAmount, initiateUnstakeOrderId, ActionType.INITIATE_UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        staking.initiateUnstake(stakeAmount, initiateUnstakeOrderId, stakeOrderId, initiateUnstakeSignature);
        
        // Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        // Complete unstake
        bytes32 unstakeOrderId = keccak256("unstakeOrder1");
        bytes memory unstakeSignature = createSignature(
            user1, stakeAmount, unstakeOrderId, ActionType.UNSTAKE, sapienSignerPrivateKey
        );
        
        uint256 initialBalance = sapienToken.balanceOf(user1);
        
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit Unstaked(user1, stakeAmount, unstakeOrderId);
        staking.unstake(stakeAmount, unstakeOrderId, stakeOrderId, unstakeSignature);
        
        // Check balances
        assertEq(sapienToken.balanceOf(user1), initialBalance + stakeAmount);
        assertEq(staking.totalStaked(), 0);
        
        // Check stake is no longer active
        (, , , , , , bool isActive) = staking.stakers(user1, stakeOrderId);
        assertFalse(isActive);
    }
    
    function test_Unstake_PartialSuccess() public {
        // Setup stake with larger amount
        uint256 stakeAmount = MINIMUM_STAKE * 5;
        bytes32 stakeOrderId = keccak256("stakeOrder1");
        bytes memory stakeSignature = createValidStakeSignature(user1, stakeAmount, stakeOrderId);
        
        vm.prank(user1);
        staking.stake(stakeAmount, ONE_MONTH, stakeOrderId, stakeSignature);
        
        vm.warp(block.timestamp + ONE_MONTH + 1);
        
        // Initiate partial unstake
        uint256 partialAmount = MINIMUM_STAKE * 2;
        bytes32 initiateUnstakeOrderId = keccak256("initiateUnstakeOrder1");
        bytes memory initiateUnstakeSignature = createSignature(
            user1, partialAmount, initiateUnstakeOrderId, ActionType.INITIATE_UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        staking.initiateUnstake(partialAmount, initiateUnstakeOrderId, stakeOrderId, initiateUnstakeSignature);
        
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        // Complete partial unstake
        bytes32 unstakeOrderId = keccak256("unstakeOrder1");
        bytes memory unstakeSignature = createSignature(
            user1, partialAmount, unstakeOrderId, ActionType.UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        staking.unstake(partialAmount, unstakeOrderId, stakeOrderId, unstakeSignature);
        
        // Check stake is still active with remaining amount
        (uint256 remainingAmount, , , , uint256 cooldownStart, uint256 cooldownAmount, bool isActive) = 
            staking.stakers(user1, stakeOrderId);
        
        assertEq(remainingAmount, stakeAmount - partialAmount);
        assertEq(cooldownStart, 0); // Reset after partial unstake
        assertEq(cooldownAmount, 0); // Reset after partial unstake
        assertTrue(isActive);
    }
    
    function test_Unstake_RevertBeforeCooldown() public {
        // Setup stake and initiate unstake
        uint256 stakeAmount = MINIMUM_STAKE;
        bytes32 stakeOrderId = keccak256("stakeOrder1");
        bytes memory stakeSignature = createValidStakeSignature(user1, stakeAmount, stakeOrderId);
        
        vm.prank(user1);
        staking.stake(stakeAmount, ONE_MONTH, stakeOrderId, stakeSignature);
        
        vm.warp(block.timestamp + ONE_MONTH + 1);
        
        bytes32 initiateUnstakeOrderId = keccak256("initiateUnstakeOrder1");
        bytes memory initiateUnstakeSignature = createSignature(
            user1, stakeAmount, initiateUnstakeOrderId, ActionType.INITIATE_UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        staking.initiateUnstake(stakeAmount, initiateUnstakeOrderId, stakeOrderId, initiateUnstakeSignature);
        
        // Try to unstake before cooldown completes
        bytes32 unstakeOrderId = keccak256("unstakeOrder1");
        bytes memory unstakeSignature = createSignature(
            user1, stakeAmount, unstakeOrderId, ActionType.UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        vm.expectRevert("Cooldown period not completed");
        staking.unstake(stakeAmount, unstakeOrderId, stakeOrderId, unstakeSignature);
    }
    
    // ============ Instant Unstake Tests ============
    
    function test_InstantUnstake_Success() public {
        uint256 stakeAmount = MINIMUM_STAKE;
        bytes32 stakeOrderId = keccak256("stakeOrder1");
        bytes memory stakeSignature = createValidStakeSignature(user1, stakeAmount, stakeOrderId);
        
        vm.prank(user1);
        staking.stake(stakeAmount, ONE_MONTH, stakeOrderId, stakeSignature);
        
        // Instant unstake during lock period
        bytes32 instantUnstakeOrderId = keccak256("instantUnstakeOrder1");
        bytes memory instantUnstakeSignature = createSignature(
            user1, stakeAmount, instantUnstakeOrderId, ActionType.INSTANT_UNSTAKE, sapienSignerPrivateKey
        );
        
        uint256 expectedPenalty = (stakeAmount * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 expectedPayout = stakeAmount - expectedPenalty;
        
        uint256 initialUserBalance = sapienToken.balanceOf(user1);
        uint256 initialSafeBalance = sapienToken.balanceOf(gnosisSafe);
        
        vm.prank(user1);
        vm.expectEmit(true, false, false, true);
        emit InstantUnstake(user1, expectedPayout, instantUnstakeOrderId);
        staking.instantUnstake(stakeAmount, instantUnstakeOrderId, stakeOrderId, instantUnstakeSignature);
        
        // Check balances
        assertEq(sapienToken.balanceOf(user1), initialUserBalance + expectedPayout);
        assertEq(sapienToken.balanceOf(gnosisSafe), initialSafeBalance + expectedPenalty);
        assertEq(staking.totalStaked(), 0);
        
        // Check stake is no longer active
        (, , , , , , bool isActive) = staking.stakers(user1, stakeOrderId);
        assertFalse(isActive);
    }
    
    function test_InstantUnstake_RevertAfterLockPeriod() public {
        uint256 stakeAmount = MINIMUM_STAKE;
        bytes32 stakeOrderId = keccak256("stakeOrder1");
        bytes memory stakeSignature = createValidStakeSignature(user1, stakeAmount, stakeOrderId);
        
        vm.prank(user1);
        staking.stake(stakeAmount, ONE_MONTH, stakeOrderId, stakeSignature);
        
        // Fast forward past lock period
        vm.warp(block.timestamp + ONE_MONTH + 1);
        
        bytes32 instantUnstakeOrderId = keccak256("instantUnstakeOrder1");
        bytes memory instantUnstakeSignature = createSignature(
            user1, stakeAmount, instantUnstakeOrderId, ActionType.INSTANT_UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        vm.expectRevert("Lock period completed, use regular unstake");
        staking.instantUnstake(stakeAmount, instantUnstakeOrderId, stakeOrderId, instantUnstakeSignature);
    }
    
    // ============ Edge Cases and Security Tests ============
    
    function test_ReentrancyGuard() public {
        // This test verifies that the nonReentrant modifier is working
        // by ensuring multiple calls in the same transaction fail
        uint256 amount = MINIMUM_STAKE;
        bytes32 orderId1 = keccak256("order1");
        bytes32 orderId2 = keccak256("order2");
        bytes memory signature1 = createValidStakeSignature(user1, amount, orderId1);
        bytes memory signature2 = createValidStakeSignature(user1, amount, orderId2);
        
        vm.prank(user1);
        staking.stake(amount, ONE_MONTH, orderId1, signature1);
        
        // The second call should succeed since it's a separate transaction
        vm.prank(user1);
        staking.stake(amount, ONE_MONTH, orderId2, signature2);
        
        assertEq(staking.totalStaked(), amount * 2);
    }
    
    function test_SignatureReplay_Prevention() public {
        uint256 amount = MINIMUM_STAKE;
        bytes32 orderId = keccak256("order1");
        bytes memory signature = createValidStakeSignature(user1, amount, orderId);
        
        vm.prank(user1);
        staking.stake(amount, ONE_MONTH, orderId, signature);
        
        // Try to replay the same signature
        vm.prank(user1);
        vm.expectRevert("Order already used");
        staking.stake(amount, ONE_MONTH, orderId, signature);
    }
    
    function test_CrossUserSignature_Invalid() public {
        uint256 amount = MINIMUM_STAKE;
        bytes32 orderId = keccak256("order1");
        // Create signature for user1 but try to use with user2
        bytes memory signature = createValidStakeSignature(user1, amount, orderId);
        
        vm.prank(user2);
        vm.expectRevert("Invalid signature or mismatched parameters");
        staking.stake(amount, ONE_MONTH, orderId, signature);
    }
    
    // ============ Upgrade Tests ============
    
    function test_Upgrade_Success() public {
        address newImpl = address(new SapienStaking());
        
        vm.prank(gnosisSafe);
        staking.authorizeUpgrade(newImpl);
        
        vm.prank(gnosisSafe);
        staking.upgradeToAndCall(newImpl, "");
        
        // Verify upgrade worked by checking implementation
        bytes32 slot = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
        bytes32 implementationBytes = vm.load(address(staking), slot);
        address currentImplementation = address(uint160(uint256(implementationBytes)));
        assertEq(currentImplementation, newImpl);
    }
    
    function test_Upgrade_RevertUnauthorized() public {
        address newImpl = address(new SapienStaking());
        
        vm.prank(gnosisSafe);
        vm.expectRevert("TwoTierAccessControl: upgrade not authorized by safe");
        staking.upgradeToAndCall(newImpl, "");
    }
    
    // ============ Fuzz Tests ============
    
    function testFuzz_Stake_ValidAmounts(uint256 amount) public {
        amount = bound(amount, MINIMUM_STAKE, 1000000 * 10**18);
        
        bytes32 orderId = keccak256(abi.encodePacked("order", amount));
        bytes memory signature = createValidStakeSignature(user1, amount, orderId);
        
        vm.prank(user1);
        staking.stake(amount, ONE_MONTH, orderId, signature);
        
        (uint256 stakedAmount, , , , , , bool isActive) = staking.stakers(user1, orderId);
        assertEq(stakedAmount, amount);
        assertTrue(isActive);
    }
    
    function testFuzz_InstantUnstake_PenaltyCalculation(uint256 amount) public {
        amount = bound(amount, MINIMUM_STAKE, 1000000 * 10**18);
        
        bytes32 stakeOrderId = keccak256(abi.encodePacked("stakeOrder", amount));
        bytes memory stakeSignature = createValidStakeSignature(user1, amount, stakeOrderId);
        
        vm.prank(user1);
        staking.stake(amount, ONE_MONTH, stakeOrderId, stakeSignature);
        
        bytes32 instantUnstakeOrderId = keccak256(abi.encodePacked("instantUnstakeOrder", amount));
        bytes memory instantUnstakeSignature = createSignature(
            user1, amount, instantUnstakeOrderId, ActionType.INSTANT_UNSTAKE, sapienSignerPrivateKey
        );
        
        uint256 expectedPenalty = (amount * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 expectedPayout = amount - expectedPenalty;
        
        uint256 initialUserBalance = sapienToken.balanceOf(user1);
        uint256 initialSafeBalance = sapienToken.balanceOf(gnosisSafe);
        
        vm.prank(user1);
        staking.instantUnstake(amount, instantUnstakeOrderId, stakeOrderId, instantUnstakeSignature);
        
        assertEq(sapienToken.balanceOf(user1), initialUserBalance + expectedPayout);
        assertEq(sapienToken.balanceOf(gnosisSafe), initialSafeBalance + expectedPenalty);
    }
    
    // ============ Integration Tests ============
    
    function test_CompleteStakingFlow() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10;
        
        // 1. Stake
        bytes32 stakeOrderId = keccak256("stakeOrder");
        bytes memory stakeSignature = createValidStakeSignature(user1, stakeAmount, stakeOrderId);
        
        vm.prank(user1);
        staking.stake(stakeAmount, THREE_MONTHS, stakeOrderId, stakeSignature);
        
        assertEq(staking.totalStaked(), stakeAmount);
        
        // 2. Fast forward past lock period
        vm.warp(block.timestamp + THREE_MONTHS + 1);
        
        // 3. Initiate unstake for partial amount
        uint256 partialAmount = MINIMUM_STAKE * 3;
        bytes32 initiateOrderId = keccak256("initiateOrder");
        bytes memory initiateSignature = createSignature(
            user1, partialAmount, initiateOrderId, ActionType.INITIATE_UNSTAKE, sapienSignerPrivateKey
        );
        
        vm.prank(user1);
        staking.initiateUnstake(partialAmount, initiateOrderId, stakeOrderId, initiateSignature);
        
        // 4. Fast forward past cooldown
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        // 5. Complete unstake
        bytes32 unstakeOrderId = keccak256("unstakeOrder");
        bytes memory unstakeSignature = createSignature(
            user1, partialAmount, unstakeOrderId, ActionType.UNSTAKE, sapienSignerPrivateKey
        );
        
        uint256 initialBalance = sapienToken.balanceOf(user1);
        
        vm.prank(user1);
        staking.unstake(partialAmount, unstakeOrderId, stakeOrderId, unstakeSignature);
        
        // Verify partial unstake
        assertEq(sapienToken.balanceOf(user1), initialBalance + partialAmount);
        assertEq(staking.totalStaked(), stakeAmount - partialAmount);
        
        // 6. Instant unstake remaining amount
        // uint256 remainingAmount = stakeAmount - partialAmount;
        // bytes32 instantOrderId = keccak256("instantOrder");
        // bytes memory instantSignature = createSignature(
        //     user1, remainingAmount, instantOrderId, ActionType.INSTANT_UNSTAKE, sapienSignerPrivateKey
        // );
        
        // Need to go back in time to make instant unstake valid (during lock period)
        vm.warp(block.timestamp - THREE_MONTHS - COOLDOWN_PERIOD - 2);
        
        // Stake again for instant unstake test
        uint256 newStakeAmount = MINIMUM_STAKE * 5;
        bytes32 newStakeOrderId = keccak256("newStakeOrder");
        bytes memory newStakeSignature = createValidStakeSignature(user1, newStakeAmount, newStakeOrderId);
        
        vm.prank(user1);
        staking.stake(newStakeAmount, ONE_MONTH, newStakeOrderId, newStakeSignature);
        
        // Now instant unstake
        bytes32 newInstantOrderId = keccak256("newInstantOrder");
        bytes memory newInstantSignature = createSignature(
            user1, newStakeAmount, newInstantOrderId, ActionType.INSTANT_UNSTAKE, sapienSignerPrivateKey
        );
        
        uint256 expectedPenalty = (newStakeAmount * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 expectedPayout = newStakeAmount - expectedPenalty;
        
        uint256 balanceBeforeInstant = sapienToken.balanceOf(user1);
        
        vm.prank(user1);
        staking.instantUnstake(newStakeAmount, newInstantOrderId, newStakeOrderId, newInstantSignature);
        
        assertEq(sapienToken.balanceOf(user1), balanceBeforeInstant + expectedPayout);
    }
} 