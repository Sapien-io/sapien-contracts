## Foundry Setup and Configuration

### **Installation**
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Initialize new project
forge init sapien-contracts-foundry
cd sapien-contracts-foundry

# Install dependencies
forge install OpenZeppelin/openzeppelin-contracts-upgradeable@v4.9.0
forge install OpenZeppelin/openzeppelin-contracts@v4.9.0
```

### **Project Structure**
```
sapien-contracts-foundry/
├── src/                          # Smart contracts
│   ├── SapienToken.sol
│   ├── SapienRewards.sol
│   ├── SapienStaking.sol
│   └── VestingManager.sol
├── test/                         # All tests
│   ├── unit/                     # Unit tests
│   │   ├── SapienToken.t.sol
│   │   ├── SapienRewards.t.sol
│   │   └── SapienStaking.t.sol
│   ├── integration/              # Integration tests
│   │   ├── TokenRewardsIntegration.t.sol
│   │   └── StakingRewardsIntegration.t.sol
│   ├── scenario/                 # End-to-end scenarios
│   │   ├── UserJourney.t.sol
│   │   └── AdminOperations.t.sol
│   ├── invariant/                # Invariant tests
│   │   ├── TokenInvariants.t.sol
│   │   └── StakingInvariants.t.sol
│   └── utils/                    # Test utilities
│       ├── BaseTest.sol
│       └── TestHelpers.sol
├── script/                       # Deployment scripts
├── foundry.toml                  # Configuration
└── .env                         # Environment variables
```

### **Configuration (foundry.toml)**
```toml
[profile.default]
src = "src"
out = "out"
libs = ["lib"]
solc_version = "0.8.24"
optimizer = true
optimizer_runs = 200
via_ir = true

[profile.ci]
fuzz = { runs = 10000 }
invariant = { runs = 1000, depth = 100 }

[profile.intense]
fuzz = { runs = 100000 }
invariant = { runs = 10000, depth = 1000 }

[rpc_endpoints]
mainnet = "${MAINNET_RPC_URL}"
sepolia = "${SEPOLIA_RPC_URL}"
polygon = "${POLYGON_RPC_URL}"

[etherscan]
mainnet = { key = "${ETHERSCAN_API_KEY}" }
sepolia = { key = "${ETHERSCAN_API_KEY}" }
polygon = { key = "${POLYGONSCAN_API_KEY}" }
```

## 🧪 Test Implementation Strategy

### **1. Unit Tests**

#### **Base Test Contract**
```solidity
// test/utils/BaseTest.sol
pragma solidity 0.8.24;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../src/SapienToken.sol";
import "../src/SapienRewards.sol";
import "../src/SapienStaking.sol";

contract BaseTest is Test {
    // Common test addresses
    address public deployer = makeAddr("deployer");
    address public gnosisSafe = makeAddr("gnosisSafe");
    address public authorizedSigner = makeAddr("authorizedSigner");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    
    // Common test amounts
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 10**18;
    uint256 public constant MINIMUM_STAKE = 1000 * 10**18;
    
    // Events for testing
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Staked(address indexed user, uint256 amount, uint256 multiplier, uint256 lockUpPeriod, bytes32 orderId);
    
    function setUp() public virtual {
        vm.label(deployer, "Deployer");
        vm.label(gnosisSafe, "GnosisSafe");
        vm.label(user1, "User1");
        vm.label(user2, "User2");
        vm.label(user3, "User3");
    }
    
    // Helper functions
    function dealTokens(address token, address to, uint256 amount) internal {
        deal(token, to, amount);
    }
    
    function expectRevertWithMessage(bytes4 selector, string memory message) internal {
        vm.expectRevert(abi.encodeWithSelector(selector, message));
    }
}
```

#### **SapienToken Unit Tests**
```solidity
// test/unit/SapienToken.t.sol
pragma solidity 0.8.24;

import "../utils/BaseTest.sol";

contract SapienTokenTest is BaseTest {
    SapienToken public token;
    
    function setUp() public override {
        super.setUp();
        
        vm.startPrank(deployer);
        token = new SapienToken();
        token.initialize(gnosisSafe, TOTAL_SUPPLY);
        vm.stopPrank();
    }
    
    function test_InitialState() public {
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(deployer), TOTAL_SUPPLY);
        assertEq(token._gnosisSafe(), gnosisSafe);
        assertEq(token.name(), "SapienToken");
        assertEq(token.symbol(), "SPN");
    }
    
    function test_VestingScheduleCreation() public {
        // Test that initial vesting schedules are created correctly
        (uint256 cliff, uint256 start, uint256 duration, uint256 amount, uint256 released, address safe) = 
            token.vestingSchedules(SapienToken.AllocationType.INVESTORS);
            
        assertEq(cliff, 365 days);
        assertEq(duration, 48 * 30 days);
        assertEq(amount, token.INVESTORS_ALLOCATION());
        assertEq(released, 0);
        assertEq(safe, gnosisSafe);
    }
    
    function testFuzz_UpdateVestingSchedule(
        uint256 cliff,
        uint256 start,
        uint256 duration,
        uint256 amount
    ) public {
        // Bound inputs to reasonable ranges
        cliff = bound(cliff, 0, 730 days);
        start = bound(start, block.timestamp + 1, block.timestamp + 365 days);
        duration = bound(duration, cliff, 1460 days); // Max 4 years
        amount = bound(amount, 1e18, 1e9 * 1e18);
        
        vm.startPrank(gnosisSafe);
        
        // Should not revert with valid parameters
        token.updateVestingSchedule(
            SapienToken.AllocationType.INVESTORS,
            cliff,
            start,
            duration,
            amount,
            gnosisSafe
        );
        
        vm.stopPrank();
        
        // Verify the schedule was updated
        (uint256 updatedCliff, uint256 updatedStart, uint256 updatedDuration, uint256 updatedAmount,,) = 
            token.vestingSchedules(SapienToken.AllocationType.INVESTORS);
            
        assertEq(updatedCliff, cliff);
        assertEq(updatedStart, start);
        assertEq(updatedDuration, duration);
        assertEq(updatedAmount, amount);
    }
    
    function test_RevertWhen_UnauthorizedUpdateVesting() public {
        vm.startPrank(user1);
        
        vm.expectRevert("Only the Safe can perform this");
        token.updateVestingSchedule(
            SapienToken.AllocationType.INVESTORS,
            0,
            block.timestamp + 1,
            365 days,
            1000e18,
            user1
        );
        
        vm.stopPrank();
    }
    
    function test_ReleaseTokens() public {
        // Transfer tokens to gnosis safe first
        vm.prank(deployer);
        token.transfer(gnosisSafe, TOTAL_SUPPLY);
        
        // Fast forward past cliff period
        vm.warp(block.timestamp + 365 days + 30 days);
        
        vm.startPrank(gnosisSafe);
        
        // Should emit TokensReleased event
        vm.expectEmit(true, false, false, true);
        emit SapienToken.TokensReleased(SapienToken.AllocationType.INVESTORS, 0); // Amount will be calculated
        
        token.releaseTokens(SapienToken.AllocationType.INVESTORS);
        
        vm.stopPrank();
        
        // Check that tokens were released
        (, , , , uint256 released,) = token.vestingSchedules(SapienToken.AllocationType.INVESTORS);
        assertGt(released, 0);
    }
}
```

#### **SapienStaking Unit Tests**
```solidity
// test/unit/SapienStaking.t.sol
pragma solidity 0.8.24;

import "../utils/BaseTest.sol";

contract SapienStakingTest is BaseTest {
    SapienToken public token;
    SapienStaking public staking;
    
    uint256 public signerPrivateKey;
    address public signer;
    
    function setUp() public override {
        super.setUp();
        
        signerPrivateKey = 0x1234;
        signer = vm.addr(signerPrivateKey);
        
        vm.startPrank(deployer);
        
        // Deploy contracts
        token = new SapienToken();
        token.initialize(gnosisSafe, TOTAL_SUPPLY);
        
        staking = new SapienStaking();
        staking.initialize(token, signer, gnosisSafe);
        
        // Transfer tokens to users for testing
        token.transfer(user1, 10000e18);
        token.transfer(user2, 10000e18);
        
        vm.stopPrank();
        
        // Users approve staking contract
        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);
        
        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);
    }
    
    function test_InitialState() public {
        assertEq(address(staking._sapienToken()), address(token));
        assertEq(staking._gnosisSafe(), gnosisSafe);
        assertEq(staking.totalStaked(), 0);
        assertEq(staking.MINIMUM_STAKE(), MINIMUM_STAKE);
    }
    
    function test_Stake_ValidParameters() public {
        uint256 stakeAmount = 2000e18;
        uint256 lockPeriod = 90 days;
        bytes32 orderId = keccak256("order1");
        
        // Create signature
        bytes memory signature = _createStakeSignature(
            user1,
            stakeAmount,
            orderId,
            SapienStaking.ActionType.STAKE,
            signerPrivateKey
        );
        
        vm.startPrank(user1);
        
        uint256 balanceBefore = token.balanceOf(user1);
        
        // Expect Staked event
        vm.expectEmit(true, false, false, true);
        emit Staked(user1, stakeAmount, staking.THREE_MONTHS_MAX_MULTIPLIER(), lockPeriod, orderId);
        
        staking.stake(stakeAmount, lockPeriod, orderId, signature);
        
        vm.stopPrank();
        
        // Check state changes
        assertEq(token.balanceOf(user1), balanceBefore - stakeAmount);
        assertEq(token.balanceOf(address(staking)), stakeAmount);
        assertEq(staking.totalStaked(), stakeAmount);
        
        // Check staking info
        (uint256 amount, uint256 lockUpPeriod, uint256 startTime, uint256 multiplier, , , bool isActive) = 
            staking.stakers(user1, orderId);
            
        assertEq(amount, stakeAmount);
        assertEq(lockUpPeriod, lockPeriod);
        assertEq(startTime, block.timestamp);
        assertEq(multiplier, staking.THREE_MONTHS_MAX_MULTIPLIER());
        assertTrue(isActive);
    }
    
    function testFuzz_Stake_DifferentAmountsAndPeriods(
        uint256 amount,
        uint8 periodIndex
    ) public {
        // Bound amount to reasonable range
        amount = bound(amount, MINIMUM_STAKE, 100000e18);
        
        // Valid lock periods
        uint256[4] memory validPeriods = [30 days, 90 days, 180 days, 365 days];
        uint256 lockPeriod = validPeriods[periodIndex % 4];
        
        bytes32 orderId = keccak256(abi.encode(amount, lockPeriod, block.timestamp));
        
        // Ensure user has enough tokens
        vm.prank(deployer);
        token.transfer(user1, amount);
        
        vm.prank(user1);
        token.approve(address(staking), amount);
        
        bytes memory signature = _createStakeSignature(
            user1,
            amount,
            orderId,
            SapienStaking.ActionType.STAKE,
            signerPrivateKey
        );
        
        vm.prank(user1);
        staking.stake(amount, lockPeriod, orderId, signature);
        
        // Verify stake was created
        (uint256 stakedAmount, , , , , , bool isActive) = staking.stakers(user1, orderId);
        assertEq(stakedAmount, amount);
        assertTrue(isActive);
    }
    
    function test_RevertWhen_StakeBelowMinimum() public {
        uint256 stakeAmount = MINIMUM_STAKE - 1;
        uint256 lockPeriod = 30 days;
        bytes32 orderId = keccak256("small_order");
        
        bytes memory signature = _createStakeSignature(
            user1,
            stakeAmount,
            orderId,
            SapienStaking.ActionType.STAKE,
            signerPrivateKey
        );
        
        vm.startPrank(user1);
        
        vm.expectRevert("Minimum 1,000 SAPIEN required");
        staking.stake(stakeAmount, lockPeriod, orderId, signature);
        
        vm.stopPrank();
    }
    
    // Helper function to create EIP-712 signatures
    function _createStakeSignature(
        address userWallet,
        uint256 amount,
        bytes32 orderId,
        SapienStaking.ActionType actionType,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                staking.STAKE_TYPEHASH(),
                userWallet,
                amount,
                orderId,
                uint8(actionType)
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", staking.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
```

### **2. Integration Tests**

#### **Token-Rewards Integration**
```solidity
// test/integration/TokenRewardsIntegration.t.sol
pragma solidity 0.8.24;

import "../utils/BaseTest.sol";

contract TokenRewardsIntegrationTest is BaseTest {
    SapienToken public token;
    SapienRewards public rewards;
    
    uint256 public signerPrivateKey;
    address public signer;
    
    function setUp() public override {
        super.setUp();
        
        signerPrivateKey = 0x5678;
        signer = vm.addr(signerPrivateKey);
        
        vm.startPrank(deployer);
        
        // Deploy contracts
        token = new SapienToken();
        token.initialize(gnosisSafe, TOTAL_SUPPLY);
        
        rewards = new SapienRewards();
        rewards.initialize(signer, gnosisSafe);
        
        // Setup rewards contract
        rewards.setRewardToken(address(token));
        
        // Transfer tokens to gnosis safe and then to rewards contract
        token.transfer(gnosisSafe, TOTAL_SUPPLY / 2);
        
        vm.stopPrank();
        
        vm.startPrank(gnosisSafe);
        token.approve(address(rewards), type(uint256).max);
        rewards.depositTokens(1000000e18); // Deposit 1M tokens for rewards
        vm.stopPrank();
    }
    
    function test_FullRewardClaimFlow() public {
        uint256 rewardAmount = 1000e18;
        bytes32 orderId = keccak256("reward_order_1");
        
        // Create reward signature
        bytes memory signature = _createRewardSignature(
            user1,
            rewardAmount,
            orderId,
            signerPrivateKey
        );
        
        uint256 balanceBefore = token.balanceOf(user1);
        uint256 contractBalanceBefore = token.balanceOf(address(rewards));
        
        vm.startPrank(user1);
        
        // Claim reward
        bool success = rewards.claimReward(rewardAmount, orderId, signature);
        assertTrue(success);
        
        vm.stopPrank();
        
        // Verify state changes
        assertEq(token.balanceOf(user1), balanceBefore + rewardAmount);
        assertEq(token.balanceOf(address(rewards)), contractBalanceBefore - rewardAmount);
        
        // Verify order is marked as redeemed
        assertTrue(rewards.isOrderRedeemed(user1, orderId));
    }
    
    function test_RewardsContractIntegrationWithVesting() public {
        // Set rewards contract in token
        vm.prank(gnosisSafe);
        token.proposeRewardsContract(address(rewards));
        
        vm.prank(gnosisSafe);
        token.acceptRewardsContract();
        
        assertEq(token.rewardsContract(), address(rewards));
        
        // Fast forward past cliff and release tokens via rewards contract
        vm.warp(block.timestamp + 365 days + 30 days);
        
        vm.prank(address(rewards));
        token.releaseTokens(SapienToken.AllocationType.TRAINER_COMP);
        
        // Verify tokens were released
        (, , , , uint256 released,) = token.vestingSchedules(SapienToken.AllocationType.TRAINER_COMP);
        assertGt(released, 0);
    }
    
    function _createRewardSignature(
        address userWallet,
        uint256 amount,
        bytes32 orderId,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                rewards.REWARD_CLAIM_TYPEHASH(),
                userWallet,
                amount,
                orderId
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", rewards.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
```

### **3. Scenario Tests**

#### **User Journey Scenarios**
```solidity
// test/scenario/UserJourney.t.sol
pragma solidity 0.8.24;

import "../utils/BaseTest.sol";

contract UserJourneyTest is BaseTest {
    SapienToken public token;
    SapienRewards public rewards;
    SapienStaking public staking;
    
    uint256 public stakingSignerKey;
    uint256 public rewardsSignerKey;
    address public stakingSigner;
    address public rewardsSigner;
    
    function setUp() public override {
        super.setUp();
        
        stakingSignerKey = 0x1111;
        rewardsSignerKey = 0x2222;
        stakingSigner = vm.addr(stakingSignerKey);
        rewardsSigner = vm.addr(rewardsSignerKey);
        
        vm.startPrank(deployer);
        
        // Deploy all contracts
        token = new SapienToken();
        token.initialize(gnosisSafe, TOTAL_SUPPLY);
        
        rewards = new SapienRewards();
        rewards.initialize(rewardsSigner, gnosisSafe);
        rewards.setRewardToken(address(token));
        
        staking = new SapienStaking();
        staking.initialize(token, stakingSigner, gnosisSafe);
        
        // Setup initial balances
        token.transfer(user1, 50000e18);
        token.transfer(user2, 30000e18);
        token.transfer(gnosisSafe, 100000e18);
        
        vm.stopPrank();
        
        // Setup approvals
        vm.prank(user1);
        token.approve(address(staking), type(uint256).max);
        
        vm.prank(user2);
        token.approve(address(staking), type(uint256).max);
        
        // Fund rewards contract
        vm.startPrank(gnosisSafe);
        token.approve(address(rewards), type(uint256).max);
        rewards.depositTokens(50000e18);
        vm.stopPrank();
    }
    
    function test_CompleteUserJourney_StakeEarnUnstake() public {
        // === User 1: Long-term staker ===
        
        // 1. User stakes for 12 months
        uint256 stakeAmount1 = 10000e18;
        bytes32 stakeOrderId1 = keccak256("stake_user1_1");
        
        bytes memory stakeSignature1 = _createStakeSignature(
            user1, stakeAmount1, stakeOrderId1, SapienStaking.ActionType.STAKE, stakingSignerKey
        );
        
        vm.prank(user1);
        staking.stake(stakeAmount1, 365 days, stakeOrderId1, stakeSignature1);
        
        // 2. User earns rewards over time
        vm.warp(block.timestamp + 30 days);
        
        uint256 rewardAmount1 = 500e18;
        bytes32 rewardOrderId1 = keccak256("reward_user1_1");
        
        bytes memory rewardSignature1 = _createRewardSignature(
            user1, rewardAmount1, rewardOrderId1, rewardsSignerKey
        );
        
        vm.prank(user1);
        rewards.claimReward(rewardAmount1, rewardOrderId1, rewardSignature1);
        
        // 3. User waits full lock period and unstakes
        vm.warp(block.timestamp + 335 days); // Total 365 days
        
        // Initiate unstake
        bytes32 initiateOrderId1 = keccak256("initiate_user1_1");
        bytes memory initiateSignature1 = _createStakeSignature(
            user1, stakeAmount1, initiateOrderId1, SapienStaking.ActionType.INITIATE_UNSTAKE, stakingSignerKey
        );
        
        vm.prank(user1);
        staking.initiateUnstake(stakeAmount1, initiateOrderId1, stakeOrderId1, initiateSignature1);
        
        // Wait cooldown period
        vm.warp(block.timestamp + 2 days);
        
        // Complete unstake
        bytes32 unstakeOrderId1 = keccak256("unstake_user1_1");
        bytes memory unstakeSignature1 = _createStakeSignature(
            user1, stakeAmount1, unstakeOrderId1, SapienStaking.ActionType.UNSTAKE, stakingSignerKey
        );
        
        uint256 balanceBeforeUnstake = token.balanceOf(user1);
        
        vm.prank(user1);
        staking.unstake(stakeAmount1, unstakeOrderId1, stakeOrderId1, unstakeSignature1);
        
        // Verify user got all tokens back plus previous rewards
        assertEq(token.balanceOf(user1), balanceBeforeUnstake + stakeAmount1);
        
        // === User 2: Early unstaker ===
        
        // 1. User stakes for 6 months but unstakes early
        uint256 stakeAmount2 = 5000e18;
        bytes32 stakeOrderId2 = keccak256("stake_user2_1");
        
        bytes memory stakeSignature2 = _createStakeSignature(
            user2, stakeAmount2, stakeOrderId2, SapienStaking.ActionType.STAKE, stakingSignerKey
        );
        
        vm.prank(user2);
        staking.stake(stakeAmount2, 180 days, stakeOrderId2, stakeSignature2);
        
        // 2. User tries to unstake early (after 30 days)
        vm.warp(block.timestamp + 30 days);
        
        bytes32 instantOrderId2 = keccak256("instant_user2_1");
        bytes memory instantSignature2 = _createStakeSignature(
            user2, stakeAmount2, instantOrderId2, SapienStaking.ActionType.INSTANT_UNSTAKE, stakingSignerKey
        );
        
        uint256 balanceBeforeInstant = token.balanceOf(user2);
        
        vm.prank(user2);
        staking.instantUnstake(stakeAmount2, instantOrderId2, stakeOrderId2, instantSignature2);
        
        // Verify user paid penalty (20%)
        uint256 expectedPayout = stakeAmount2 * 80 / 100;
        assertEq(token.balanceOf(user2), balanceBeforeInstant + expectedPayout);
        
        // Verify penalty went to gnosis safe
        assertEq(token.balanceOf(gnosisSafe), 100000e18 - 50000e18 + (stakeAmount2 * 20 / 100));
    }
    
    function test_AdminOperationsScenario() public {
        // 1. Admin pauses staking contract
        vm.prank(gnosisSafe);
        staking.pause();
        
        // 2. Users cannot stake while paused
        bytes32 orderId = keccak256("paused_stake");
        bytes memory signature = _createStakeSignature(
            user1, 2000e18, orderId, SapienStaking.ActionType.STAKE, stakingSignerKey
        );
        
        vm.prank(user1);
        vm.expectRevert("Pausable: paused");
        staking.stake(2000e18, 90 days, orderId, signature);
        
        // 3. Admin unpauses
        vm.prank(gnosisSafe);
        staking.unpause();
        
        // 4. Users can stake again
        vm.prank(user1);
        staking.stake(2000e18, 90 days, orderId, signature);
        
        // Verify stake succeeded
        (uint256 amount,,,,,, bool isActive) = staking.stakers(user1, orderId);
        assertEq(amount, 2000e18);
        assertTrue(isActive);
    }
    
    // Helper functions (same as in unit tests)
    function _createStakeSignature(
        address userWallet,
        uint256 amount,
        bytes32 orderId,
        SapienStaking.ActionType actionType,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        // Implementation same as unit tests
        bytes32 structHash = keccak256(
            abi.encode(
                staking.STAKE_TYPEHASH(),
                userWallet,
                amount,
                orderId,
                uint8(actionType)
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", staking.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
    
    function _createRewardSignature(
        address userWallet,
        uint256 amount,
        bytes32 orderId,
        uint256 privateKey
    ) internal view returns (bytes memory) {
        bytes32 structHash = keccak256(
            abi.encode(
                rewards.REWARD_CLAIM_TYPEHASH(),
                userWallet,
                amount,
                orderId
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", rewards.DOMAIN_SEPARATOR(), structHash)
        );
        
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, digest);
        return abi.encodePacked(r, s, v);
    }
}
```

### **4. Invariant Tests**

#### **Token Supply Invariants**
```solidity
// test/invariant/TokenInvariants.t.sol
pragma solidity 0.8.24;

import "../utils/BaseTest.sol";

contract TokenInvariantsTest is BaseTest {
    SapienToken public token;
    SapienRewards public rewards;
    SapienStaking public staking;
    
    // Actor contracts for invariant testing
    TokenActor public actor;
    
    function setUp() public override {
        super.setUp();
        
        vm.startPrank(deployer);
        
        token = new SapienToken();
        token.initialize(gnosisSafe, TOTAL_SUPPLY);
        
        rewards = new SapienRewards();
        rewards.initialize(makeAddr("rewardsSigner"), gnosisSafe);
        rewards.setRewardToken(address(token));
        
        staking = new SapienStaking();
        staking.initialize(token, makeAddr("stakingSigner"), gnosisSafe);
        
        vm.stopPrank();
        
        // Create actor contract
        actor = new TokenActor(token, rewards, staking, gnosisSafe);
        
        // Setup token balances
        vm.prank(deployer);
        token.transfer(address(actor), TOTAL_SUPPLY / 4);
        
        vm.prank(gnosisSafe);
        token.transfer(address(rewards), TOTAL_SUPPLY / 4);
        
        // Target the actor contract for invariant testing
        targetContract(address(actor));
        
        // Define function selectors to fuzz
        bytes4[] memory selectors = new bytes4[](3);
        selectors[0] = TokenActor.transfer.selector;
        selectors[1] = TokenActor.approve.selector;
        selectors[2] = TokenActor.transferFrom.selector;
        
        targetSelector(FuzzSelector({
            addr: address(actor),
            selectors: selectors
        }));
    }
    
    /// @notice Total supply must never change after initialization
    function invariant_TotalSupplyConstant() public {
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
    }
    
    /// @notice Sum of all balances must equal total supply
    function invariant_BalancesSumToTotalSupply() public {
        uint256 sumOfBalances = token.balanceOf(deployer) +
                               token.balanceOf(gnosisSafe) +
                               token.balanceOf(address(rewards)) +
                               token.balanceOf(address(staking)) +
                               token.balanceOf(address(actor)) +
                               token.balanceOf(user1) +
                               token.balanceOf(user2) +
                               token.balanceOf(user3);
        
        assertEq(sumOfBalances, TOTAL_SUPPLY);
    }
    
    /// @notice Vesting allocations must never exceed their defined constants
    function invariant_VestingAllocationsWithinLimits() public {
        (, , , uint256 investorsAmount,,) = token.vestingSchedules(SapienToken.AllocationType.INVESTORS);
        (, , , uint256 teamAmount,,) = token.vestingSchedules(SapienToken.AllocationType.TEAM);
        (, , , uint256 trainerAmount,,) = token.vestingSchedules(SapienToken.AllocationType.TRAINER_COMP);
        
        assertLe(investorsAmount, token.INVESTORS_ALLOCATION());
        assertLe(teamAmount, token.TEAM_ADVISORS_ALLOCATION());
        assertLe(trainerAmount, token.TRAINER_COMP_ALLOCATION());
    }
    
    /// @notice Released tokens must never exceed allocated amounts
    function invariant_ReleasedNeverExceedsAllocated() public {
        (, , , uint256 investorsAmount, uint256 investorsReleased,) = token.vestingSchedules(SapienToken.AllocationType.INVESTORS);
        (, , , uint256 teamAmount, uint256 teamReleased,) = token.vestingSchedules(SapienToken.AllocationType.TEAM);
        
        assertLe(investorsReleased, investorsAmount);
        assertLe(teamReleased, teamAmount);
    }
}

// Actor contract for invariant testing
contract TokenActor {
    SapienToken public token;
    SapienRewards public rewards;
    SapienStaking public staking;
    address public gnosisSafe;
    
    address[] public actors;
    
    constructor(SapienToken _token, SapienRewards _rewards, SapienStaking _staking, address _gnosisSafe) {
        token = _token;
        rewards = _rewards;
        staking = _staking;
        gnosisSafe = _gnosisSafe;
        
        actors.push(address(this));
        actors.push(_gnosisSafe);
        actors.push(address(_rewards));
        actors.push(address(_staking));
    }
    
    function transfer(uint256 actorIndex, uint256 amount) public {
        address to = actors[actorIndex % actors.length];
        amount = bound(amount, 0, token.balanceOf(address(this)));
        
        if (amount > 0) {
            token.transfer(to, amount);
        }
    }
    
    function approve(uint256 actorIndex, uint256 amount) public {
        address spender = actors[actorIndex % actors.length];
        token.approve(spender, amount);
    }
    
    function transferFrom(uint256 fromIndex, uint256 toIndex, uint256 amount) public {
        address from = actors[fromIndex % actors.length];
        address to = actors[toIndex % actors.length];
        
        uint256 allowance = token.allowance(from, address(this));
        amount = bound(amount, 0, allowance);
        
        if (amount > 0 && token.balanceOf(from) >= amount) {
            token.transferFrom(from, to, amount);
        }
    }
}
```

#### **Staking Invariants**
```solidity
// test/invariant/StakingInvariants.t.sol
pragma solidity 0.8.24;

import "../utils/BaseTest.sol";

contract StakingInvariantsTest is BaseTest {
    SapienToken public token;
    SapienStaking public staking;
    
    StakingActor public actor;
    
    function setUp() public override {
        super.setUp();
        
        vm.startPrank(deployer);
        
        token = new SapienToken();
        token.initialize(gnosisSafe, TOTAL_SUPPLY);
        
        staking = new SapienStaking();
        staking.initialize(token, makeAddr("stakingSigner"), gnosisSafe);
        
        vm.stopPrank();
        
        actor = new StakingActor(token, staking);
        
        // Fund actor
        vm.prank(deployer);
        token.transfer(address(actor), 1000000e18);
        
        targetContract(address(actor));
    }
    
    /// @notice Total staked must equal sum of all individual stakes
    function invariant_TotalStakedEqualsIndividualStakes() public {
        assertEq(staking.totalStaked(), actor.sumOfAllStakes());
    }
    
    /// @notice Contract token balance must be >= total staked
    function invariant_ContractBalanceCoversStaked() public {
        assertGe(token.balanceOf(address(staking)), staking.totalStaked());
    }
    
    /// @notice No stake can have amount greater than what was originally staked
    function invariant_StakeAmountsValid() public {
        assertTrue(actor.allStakeAmountsValid());
    }
    
    /// @notice User's total token balance + staked amount should be conserved
    function invariant_UserTokenConservation() public {
        assertTrue(actor.checkUserTokenConservation());
    }
}

contract StakingActor {
    SapienToken public token;
    SapienStaking public staking;
    
    struct UserStake {
        address user;
        bytes32 orderId;
        uint256 originalAmount;
        uint256 currentAmount;
    }
    
    UserStake[] public stakes;
    mapping(address => uint256) public originalBalances;
    address[] public users;
    
    constructor(SapienToken _token, SapienStaking _staking) {
        token = _token;
        staking = _staking;
        
        // Create test users
        for (uint i = 0; i < 5; i++) {
            address user = address(uint160(0x1000 + i));
            users.push(user);
            
            // Fund users
            token.transfer(user, 100000e18);
            originalBalances[user] = 100000e18;
            
            // Approve staking
            vm.prank(user);
            token.approve(address(staking), type(uint256).max);
        }
    }
    
    function stake(uint256 userIndex, uint256 amount, uint256 periodIndex) public {
        address user = users[userIndex % users.length];
        amount = bound(amount, staking.MINIMUM_STAKE(), token.balanceOf(user));
        
        uint256[4] memory periods = [30 days, 90 days, 180 days, 365 days];
        uint256 period = periods[periodIndex % 4];
        
        bytes32 orderId = keccak256(abi.encode(user, amount, period, block.timestamp, stakes.length));
        
        // Mock signature (simplified for invariant testing)
        bytes memory signature = abi.encode("mock");
        
        vm.prank(user);
        try staking.stake(amount, period, orderId, signature) {
            stakes.push(UserStake({
                user: user,
                orderId: orderId,
                originalAmount: amount,
                currentAmount: amount
            }));
        } catch {
            // Stake failed, ignore
        }
    }
    
    function sumOfAllStakes() public view returns (uint256) {
        uint256 sum = 0;
        for (uint i = 0; i < stakes.length; i++) {
            (, , , , , , bool isActive) = staking.stakers(stakes[i].user, stakes[i].orderId);
            if (isActive) {
                (uint256 amount, , , , , ,) = staking.stakers(stakes[i].user, stakes[i].orderId);
                sum += amount;
            }
        }
        return sum;
    }
    
    function allStakeAmountsValid() public view returns (bool) {
        for (uint i = 0; i < stakes.length; i++) {
            (uint256 amount, , , , , ,) = staking.stakers(stakes[i].user, stakes[i].orderId);
            if (amount > stakes[i].originalAmount) {
                return false;
            }
        }
        return true;
    }
    
    function checkUserTokenConservation() public view returns (bool) {
        for (uint i = 0; i < users.length; i++) {
            address user = users[i];
            uint256 currentBalance = token.balanceOf(user);
            uint256 stakedAmount = getUserTotalStaked(user);
            
            // Allow for small rounding errors
            if (currentBalance + stakedAmount + 1e18 < originalBalances[user]) {
                return false;
            }
        }
        return true;
    }
    
    function getUserTotalStaked(address user) public view returns (uint256) {
        uint256 total = 0;
        for (uint i = 0; i < stakes.length; i++) {
            if (stakes[i].user == user) {
                (uint256 amount, , , , , , bool isActive) = staking.stakers(user, stakes[i].orderId);
                if (isActive) {
                    total += amount;
                }
            }
        }
        return total;
    }
}
```

## 🚀 Running Tests

### **Basic Test Commands**
```bash
# Run all tests
forge test

# Run specific test file
forge test --match-path test/unit/SapienToken.t.sol

# Run with gas reports
forge test --gas-report

# Run with verbosity for debugging
forge test -vvv

# Run specific test function
forge test --match-test test_Stake_ValidParameters

# Run fuzz tests with custom runs
forge test --fuzz-runs 10000

# Run invariant tests
forge test --match-path test/invariant/
```

### **Advanced Testing**
```bash
# Run tests on specific fork
forge test --fork-url $MAINNET_RPC_URL

# Run tests with coverage
forge coverage

# Run tests with specific profile
forge test --profile ci

# Debug specific test
forge test --match-test test_FailingTest --debug
```
