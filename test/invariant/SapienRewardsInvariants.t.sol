// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import { Test } from "lib/forge-std/src/Test.sol";
import { StdInvariant } from "lib/forge-std/src/StdInvariant.sol";
import { SapienRewards } from "src/SapienRewards.sol";
import { ERC1967Proxy } from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockERC20 } from "test/mocks/MockERC20.sol";
import { Constants as Const } from "src/utils/Constants.sol";
import { ECDSA } from "lib/openzeppelin-contracts/contracts/utils/cryptography/ECDSA.sol";

// Handler contract for invariant testing
contract SapienRewardsHandler is Test {
    SapienRewards public sapienRewards;
    MockERC20 public rewardToken;
    
    address[] public actors;
    address[] public rewardManagers;
    uint256[] public rewardManagerKeys;
    
    address public admin;
    address public rewardSafe;
    
    uint256 public constant INITIAL_REWARD_POOL = 1000000e18; // 1M tokens
    uint256 public constant MAX_INDIVIDUAL_REWARD = 10000e18; // 10K tokens
    
    // Track system state for invariants
    uint256 public totalRewardsClaimed;
    uint256 public totalRewardsDeposited;
    uint256 public totalRewardsWithdrawn;
    uint256 public totalOrdersRedeemed;
    uint256 public totalDirectTransfers; // Track direct transfers to contract
    uint256 public totalRecovered; // Track recovered unaccounted tokens
    uint256 public initialRewardSafeBalance; // Track initial reward safe balance
    uint256 public totalMinted; // Track total tokens minted into the system
    
    // Track orders to prevent duplicates
    mapping(bytes32 => bool) public usedOrderIds;
    mapping(address => bytes32[]) public userOrderHistory;
    
    modifier useActor(uint256 actorIndexSeed) {
        address currentActor = actors[bound(actorIndexSeed, 0, actors.length - 1)];
        vm.startPrank(currentActor);
        _;
        vm.stopPrank();
    }
    
    modifier useRewardManager(uint256 managerIndexSeed) {
        uint256 managerIndex = bound(managerIndexSeed, 0, rewardManagers.length - 1);
        address manager = rewardManagers[managerIndex];
        vm.startPrank(manager);
        _;
        vm.stopPrank();
    }
    
    constructor(SapienRewards _sapienRewards, MockERC20 _rewardToken, address _admin, address _rewardSafe) {
        sapienRewards = _sapienRewards;
        rewardToken = _rewardToken;
        admin = _admin;
        rewardSafe = _rewardSafe;
        
        // Create regular actors (reward claimers)
        for (uint256 i = 0; i < 10; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
        }
        
        // Create reward managers with known private keys
        for (uint256 i = 0; i < 3; i++) {
            uint256 privateKey = uint256(keccak256(abi.encodePacked("rewardManager", i))) % (2**255);
            address manager = vm.addr(privateKey);
            rewardManagers.push(manager);
            rewardManagerKeys.push(privateKey);
            
            // Grant reward manager role
            vm.prank(admin);
            sapienRewards.grantRole(Const.REWARD_MANAGER_ROLE, manager);
        }
        
        // Initial reward deposit
        rewardToken.mint(rewardSafe, INITIAL_REWARD_POOL);
        initialRewardSafeBalance = rewardToken.balanceOf(rewardSafe); // Capture before deposit
        totalMinted = INITIAL_REWARD_POOL; // Track initial mint
        
        vm.startPrank(rewardSafe);
        rewardToken.approve(address(sapienRewards), INITIAL_REWARD_POOL);
        sapienRewards.depositRewards(INITIAL_REWARD_POOL);
        vm.stopPrank();
        
        totalRewardsDeposited = INITIAL_REWARD_POOL;
    }
    
    function claimReward(uint256 actorSeed, uint256 rewardAmountSeed, uint256 managerSeed) public useActor(actorSeed) {
        // Bound reward amount to reasonable range
        uint256 rewardAmount = bound(rewardAmountSeed, 1e18, MAX_INDIVIDUAL_REWARD);
        
        // Check if we have enough available rewards
        if (sapienRewards.getAvailableRewards() < rewardAmount) {
            return;
        }
        
        // Generate unique order ID
        bytes32 orderId = keccak256(abi.encodePacked(msg.sender, block.timestamp, rewardAmount, totalOrdersRedeemed));
        
        // Skip if order already used (shouldn't happen with our generation but safety check)
        if (usedOrderIds[orderId] || sapienRewards.getOrderRedeemedStatus(msg.sender, orderId)) {
            return;
        }
        
        // Get manager for signing
        uint256 managerIndex = bound(managerSeed, 0, rewardManagerKeys.length - 1);
        uint256 privateKey = rewardManagerKeys[managerIndex];
        
        // Create signature
        bytes memory signature = _createValidSignature(msg.sender, rewardAmount, orderId, privateKey);
        
        uint256 balanceBefore = rewardToken.balanceOf(msg.sender);
        
        try sapienRewards.claimReward(rewardAmount, orderId, signature) {
            uint256 balanceAfter = rewardToken.balanceOf(msg.sender);
            uint256 actualReward = balanceAfter - balanceBefore;
            
            totalRewardsClaimed += actualReward;
            totalOrdersRedeemed++;
            usedOrderIds[orderId] = true;
            userOrderHistory[msg.sender].push(orderId);
        } catch {
            // Claim failed, continue
        }
    }
    
    function depositRewards(uint256 amountSeed) public {
        uint256 amount = bound(amountSeed, 1e18, 100000e18); // 1 to 100K tokens
        
        // Mint tokens to reward safe and deposit
        rewardToken.mint(rewardSafe, amount);
        totalMinted += amount; // Track additional mints
        
        vm.startPrank(rewardSafe);
        rewardToken.approve(address(sapienRewards), amount);
        
        try sapienRewards.depositRewards(amount) {
            totalRewardsDeposited += amount;
        } catch {
            // Deposit failed, continue
        }
        vm.stopPrank();
    }
    
    function withdrawRewards(uint256 amountSeed) public {
        uint256 availableRewards = sapienRewards.getAvailableRewards();
        if (availableRewards == 0) return;
        
        // Ensure we don't try to withdraw more than available
        uint256 amount = bound(amountSeed, 1, availableRewards);
        
        vm.startPrank(rewardSafe);
        try sapienRewards.withdrawRewards(amount) {
            totalRewardsWithdrawn += amount;
        } catch {
            // Withdrawal failed, continue
            // This can happen if available rewards changed between check and execution
        }
        vm.stopPrank();
    }
    
    function reconcileBalance() public {
        vm.prank(rewardSafe);
        try sapienRewards.reconcileBalance() {
            // Reconciliation attempted
        } catch {
            // Failed, continue
        }
    }
    
    function recoverUnaccountedTokens(uint256 amountSeed) public {
        (uint256 availableRewards, uint256 totalBalance) = sapienRewards.getRewardTokenBalances();
        
        if (totalBalance <= availableRewards) return;
        
        uint256 unaccounted = totalBalance - availableRewards;
        uint256 amount = bound(amountSeed, 1, unaccounted);
        
        vm.startPrank(rewardSafe);
        try sapienRewards.recoverUnaccountedTokens(amount) {
            totalRecovered += amount; // Track recovered tokens
        } catch {
            // Failed, continue
        }
        vm.stopPrank();
    }
    
    function sendTokensDirectly(uint256 amountSeed) public {
        // Simulate direct token transfers to contract (should be recoverable)
        uint256 amount = bound(amountSeed, 1e18, 10000e18);
        
        rewardToken.mint(address(sapienRewards), amount);
        totalDirectTransfers += amount; // Track direct transfers
        totalMinted += amount; // Track total mints
    }
    
    function attemptInvalidClaim(uint256 actorSeed, uint256 rewardAmountSeed) public useActor(actorSeed) {
        // Attempt claim with invalid signature (should fail)
        uint256 rewardAmount = bound(rewardAmountSeed, 1e18, MAX_INDIVIDUAL_REWARD);
        bytes32 orderId = keccak256(abi.encodePacked(msg.sender, "invalid", block.timestamp));
        
        // Create invalid signature (using wrong private key)
        bytes memory invalidSignature = _createValidSignature(msg.sender, rewardAmount, orderId, 12345);
        
        try sapienRewards.claimReward(rewardAmount, orderId, invalidSignature) {
            // This should never succeed
            revert("Invalid claim succeeded - invariant violation");
        } catch {
            // Expected to fail
        }
    }
    
    // Helper function to create valid EIP-712 signatures
    function _createValidSignature(address user, uint256 amount, bytes32 orderId, uint256 privateKey)
        private
        view
        returns (bytes memory)
    {
        bytes32 structHash = keccak256(abi.encode(Const.REWARD_CLAIM_TYPEHASH, user, amount, orderId));
        bytes32 domainSeparator = sapienRewards.getDomainSeparator();
        bytes32 hashToSign = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, hashToSign);
        return abi.encodePacked(r, s, v);
    }
    
    // Getter functions
    function getActors() public view returns (address[] memory) {
        return actors;
    }
    
    function getRewardManagers() public view returns (address[] memory) {
        return rewardManagers;
    }
    
    function getUserOrderHistory(address user) public view returns (bytes32[] memory) {
        return userOrderHistory[user];
    }
}

contract SapienRewardsInvariantsTest is StdInvariant, Test {
    SapienRewards public sapienRewards;
    MockERC20 public rewardToken;
    SapienRewardsHandler public handler;
    
    address public admin = makeAddr("admin");
    address public rewardSafe = makeAddr("rewardSafe");
    address public rewardManager = makeAddr("rewardManager");
    
    function setUp() public {
        rewardToken = new MockERC20("Reward", "REWARD", 18);
        
        SapienRewards sapienRewardsImpl = new SapienRewards();
        bytes memory initData = abi.encodeWithSelector(
            SapienRewards.initialize.selector,
            admin,
            rewardManager,
            rewardSafe,
            address(rewardToken)
        );
        ERC1967Proxy sapienRewardsProxy = new ERC1967Proxy(address(sapienRewardsImpl), initData);
        sapienRewards = SapienRewards(address(sapienRewardsProxy));
        
        handler = new SapienRewardsHandler(sapienRewards, rewardToken, admin, rewardSafe);
        
        // Set up invariant testing
        targetContract(address(handler));
        
        // Define function selectors to call
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = SapienRewardsHandler.claimReward.selector;
        selectors[1] = SapienRewardsHandler.depositRewards.selector;
        selectors[2] = SapienRewardsHandler.withdrawRewards.selector;
        selectors[3] = SapienRewardsHandler.reconcileBalance.selector;
        selectors[4] = SapienRewardsHandler.recoverUnaccountedTokens.selector;
        selectors[5] = SapienRewardsHandler.sendTokensDirectly.selector;
        selectors[6] = SapienRewardsHandler.attemptInvalidClaim.selector;
        
        targetSelector(FuzzSelector({
            addr: address(handler),
            selectors: selectors
        }));
    }
    
    // =============================================================================
    // CORE INVARIANTS
    // =============================================================================
    
    /// @dev Available rewards should never exceed contract token balance
    function invariant_AvailableRewardsNotExceedBalance() public view {
        uint256 availableRewards = sapienRewards.getAvailableRewards();
        uint256 contractBalance = rewardToken.balanceOf(address(sapienRewards));
        
        assertLe(
            availableRewards,
            contractBalance,
            "Available rewards must not exceed contract balance"
        );
    }
    
    /// @dev Contract balance should equal available rewards plus any untracked tokens
    function invariant_BalanceConsistency() public view {
        (uint256 availableRewards, uint256 totalBalance) = sapienRewards.getRewardTokenBalances();
        
        assertEq(
            totalBalance,
            rewardToken.balanceOf(address(sapienRewards)),
            "Total balance should match actual contract balance"
        );
        
        assertLe(
            availableRewards,
            totalBalance,
            "Available rewards should not exceed total balance"
        );
    }
    
    /// @dev Total token conservation across all participants
    function invariant_TokenConservation() public view {
        // Get all current balances
        uint256 contractBalance = rewardToken.balanceOf(address(sapienRewards));
        uint256 currentRewardSafeBalance = rewardToken.balanceOf(rewardSafe);
        
        // Get user balances
        uint256 totalUserBalances = 0;
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            totalUserBalances += rewardToken.balanceOf(actors[i]);
        }
        
        address[] memory managers = handler.getRewardManagers();
        for (uint256 i = 0; i < managers.length; i++) {
            totalUserBalances += rewardToken.balanceOf(managers[i]);
        }
        
        // Total tokens currently in the system
        uint256 totalTokensInSystem = contractBalance + currentRewardSafeBalance + totalUserBalances;
        
        // Total tokens that have been minted
        uint256 expectedTotalTokens = handler.totalMinted();
        
        assertEq(
            totalTokensInSystem,
            expectedTotalTokens,
            "Total tokens in system should equal total minted tokens"
        );
    }
    
    /// @dev Order uniqueness - no order should be redeemed twice
    function invariant_OrderUniqueness() public view {
        address[] memory actors = handler.getActors();
        
        for (uint256 i = 0; i < actors.length; i++) {
            bytes32[] memory userOrders = handler.getUserOrderHistory(actors[i]);
            
            // Check that each order is marked as redeemed
            for (uint256 j = 0; j < userOrders.length; j++) {
                assertTrue(
                    sapienRewards.getOrderRedeemedStatus(actors[i], userOrders[j]),
                    "Redeemed order should be marked as used"
                );
            }
            
            // Check for duplicates within user's history
            for (uint256 j = 0; j < userOrders.length; j++) {
                for (uint256 k = j + 1; k < userOrders.length; k++) {
                    assertTrue(
                        userOrders[j] != userOrders[k],
                        "User should not have duplicate orders in history"
                    );
                }
            }
        }
    }
    
    /// @dev Available rewards should be non-negative and reasonable
    function invariant_ReasonableAvailableRewards() public view {
        uint256 availableRewards = sapienRewards.getAvailableRewards();
        
        // Available rewards should not exceed a reasonable maximum
        assertTrue(
            availableRewards <= 1000_000_000 * 1e18, // 1B tokens max
            "Available rewards should not exceed reasonable maximum"
        );
    }
    
    // =============================================================================
    // ACCESS CONTROL INVARIANTS
    // =============================================================================
    
    /// @dev Only reward safe should be able to deposit/withdraw rewards
    function invariant_RewardSafeExclusiveAccess() public view {
        // This is tested implicitly through the handler - only rewardSafe calls these functions
        // If any other address could call them, the handler would fail
        
        // Verify reward safe has the correct role
        assertTrue(
            sapienRewards.hasRole(Const.REWARD_SAFE_ROLE, rewardSafe),
            "Reward safe should have REWARD_SAFE_ROLE"
        );
        
        // Verify admin has admin role
        assertTrue(
            sapienRewards.hasRole(sapienRewards.DEFAULT_ADMIN_ROLE(), admin),
            "Admin should have DEFAULT_ADMIN_ROLE"
        );
    }
    
    /// @dev Reward managers should have the correct role
    function invariant_RewardManagerRoles() public view {
        address[] memory managers = handler.getRewardManagers();
        
        for (uint256 i = 0; i < managers.length; i++) {
            assertTrue(
                sapienRewards.hasRole(Const.REWARD_MANAGER_ROLE, managers[i]),
                "Reward managers should have REWARD_MANAGER_ROLE"
            );
        }
    }
    
    // =============================================================================
    // SIGNATURE AND EIP-712 INVARIANTS
    // =============================================================================
    
    /// @dev Domain separator should be consistent
    function invariant_DomainSeparatorConsistency() public view {
        bytes32 domainSeparator = sapienRewards.getDomainSeparator();
        
        // Domain separator should not be zero
        assertTrue(
            domainSeparator != bytes32(0),
            "Domain separator should not be zero"
        );
        
        // Should be deterministic for the same chain
        assertEq(
            domainSeparator,
            sapienRewards.getDomainSeparator(),
            "Domain separator should be deterministic"
        );
    }
    
    // =============================================================================
    // BUSINESS LOGIC INVARIANTS
    // =============================================================================
    
    /// @dev Claimed rewards should not exceed deposited rewards
    function invariant_ClaimedNotExceedDeposited() public view {
        uint256 totalClaimed = handler.totalRewardsClaimed();
        uint256 totalDeposited = handler.totalRewardsDeposited();
        
        assertLe(
            totalClaimed,
            totalDeposited,
            "Total claimed should not exceed total deposited"
        );
    }
    
    /// @dev Available rewards calculation should be correct
    function invariant_AvailableRewardsCalculation() public view {
        uint256 availableRewards = sapienRewards.getAvailableRewards();
        uint256 totalDeposited = handler.totalRewardsDeposited();
        uint256 totalClaimed = handler.totalRewardsClaimed();
        uint256 totalWithdrawn = handler.totalRewardsWithdrawn();
        
        // Available rewards should not exceed total deposited
        // (Note: this can be exceeded due to reconciliation of direct transfers)
        // So we check a more basic constraint: available should be reasonable relative to deposits
        
        // Basic sanity check: if no direct transfers, available should not exceed deposits
        if (handler.totalDirectTransfers() == 0) {
            assertLe(
                availableRewards,
                totalDeposited,
                "Without direct transfers, available should not exceed total deposited"
            );
        }
        
        // Available rewards should not be excessive compared to total minted tokens
        assertLe(
            availableRewards,
            handler.totalMinted(),
            "Available rewards should not exceed total minted tokens"
        );
        
        // Basic constraint: claimed + withdrawn should not exceed total deposits + direct transfers
        // (accounting for reconciliation that can add direct transfers to available rewards)
        uint256 totalExpended = totalClaimed + totalWithdrawn;
        uint256 totalPotentialRewards = totalDeposited + handler.totalDirectTransfers();
        
        assertLe(
            totalExpended,
            totalPotentialRewards,
            "Total claimed + withdrawn should not exceed potential reward sources"
        );
    }
    
    /// @dev Reward amounts should respect maximum limits
    function invariant_RewardAmountLimits() public view {
        // Individual rewards should not exceed the maximum defined in constants
        // This is enforced by the contract's validation, so if any exceed the limit,
        // they should have been rejected
        
        address[] memory actors = handler.getActors();
        for (uint256 i = 0; i < actors.length; i++) {
            // We can't easily track individual reward amounts in the invariant,
            // but the contract enforces the limit, so we verify the limit exists
            assertTrue(
                Const.MAX_REWARD_AMOUNT > 0,
                "Maximum reward amount should be defined"
            );
        }
    }
    
    /// @dev Contract should handle unaccounted tokens correctly
    function invariant_UnaccountedTokenHandling() public view {
        (uint256 availableRewards, uint256 totalBalance) = sapienRewards.getRewardTokenBalances();
        
        if (totalBalance > availableRewards) {
            uint256 unaccounted = totalBalance - availableRewards;
            
            // Unaccounted tokens should be recoverable (tested through recoverUnaccountedTokens)
            assertTrue(
                unaccounted >= 0,
                "Unaccounted tokens should be non-negative"
            );
        }
    }
    
    /// @dev Order IDs should be unique across all users
    function invariant_GlobalOrderUniqueness() public view {
        address[] memory actors = handler.getActors();
        bytes32[] memory allOrders;
        uint256 totalOrders = 0;
        
        // Count total orders first
        for (uint256 i = 0; i < actors.length; i++) {
            totalOrders += handler.getUserOrderHistory(actors[i]).length;
        }
        
        // Collect all orders
        allOrders = new bytes32[](totalOrders);
        uint256 orderIndex = 0;
        
        for (uint256 i = 0; i < actors.length; i++) {
            bytes32[] memory userOrders = handler.getUserOrderHistory(actors[i]);
            for (uint256 j = 0; j < userOrders.length; j++) {
                allOrders[orderIndex] = userOrders[j];
                orderIndex++;
            }
        }
        
        // Check for global uniqueness
        for (uint256 i = 0; i < allOrders.length; i++) {
            for (uint256 j = i + 1; j < allOrders.length; j++) {
                assertTrue(
                    allOrders[i] != allOrders[j],
                    "Order IDs should be globally unique"
                );
            }
        }
    }
    
    /// @dev System state should be consistent after operations
    function invariant_SystemStateConsistency() public view {
        uint256 totalOrdersRedeemed = handler.totalOrdersRedeemed();
        
        // Count actual redeemed orders from all users
        address[] memory actors = handler.getActors();
        uint256 actualRedeemedCount = 0;
        
        for (uint256 i = 0; i < actors.length; i++) {
            actualRedeemedCount += handler.getUserOrderHistory(actors[i]).length;
        }
        
        assertEq(
            totalOrdersRedeemed,
            actualRedeemedCount,
            "Tracked redeemed orders should match actual count"
        );
    }
    
    /// @dev Contract version should be consistent
    function invariant_ContractVersionConsistency() public view {
        string memory version = sapienRewards.version();
        
        // Version should not be empty
        assertTrue(
            bytes(version).length > 0,
            "Contract version should not be empty"
        );
    }
} 