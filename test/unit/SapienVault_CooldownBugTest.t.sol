// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Multiplier, IMultiplier} from "src/Multiplier.sol";

// Simple mock ERC20 token for testing
contract MockToken {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    uint256 public totalSupply;
    string public name = "Mock Token";
    string public symbol = "MOCK";
    uint8 public decimals = 18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        require(balanceOf[msg.sender] >= amount, "Insufficient balance");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        emit Transfer(msg.sender, to, amount);
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        require(balanceOf[from] >= amount, "Insufficient balance");
        require(allowance[from][msg.sender] >= amount, "Insufficient allowance");

        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        allowance[from][msg.sender] -= amount;

        emit Transfer(from, to, amount);
        return true;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
}

contract SapienVaultCooldownBugTest is Test {
    SapienVault public sapienVault;
    MockToken public mockToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public alice = makeAddr("alice");

    uint256 public constant MINIMUM_STAKE = 1000e18;
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant COOLDOWN_PERIOD = 2 days;

    function setUp() public {
        mockToken = new MockToken();

        // Deploy multiplier contract
        Multiplier multiplierImpl = new Multiplier();
        IMultiplier multiplierContract = IMultiplier(address(multiplierImpl));

        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector, address(mockToken), admin, treasury, address(multiplierContract)
        );
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        mockToken.mint(alice, 1000000e18);
    }

    // =============================================================================
    // SINGLE STAKE COOLDOWN TESTS
    // =============================================================================

    function test_Vault_CooldownLogic_PartialUnstakeCorrectlyTracked() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10;

        // Alice stakes tokens
        vm.startPrank(alice);
        mockToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Time passes, stake becomes unlocked
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Verify initial unlocked state
        assertEq(sapienVault.getTotalUnlocked(alice), stakeAmount, "All tokens should be unlocked");
        assertEq(sapienVault.getTotalLocked(alice), 0, "No tokens should be locked");
        assertEq(sapienVault.getTotalInCooldown(alice), 0, "No tokens should be in cooldown");

        // Alice initiates cooldown for part of the stake
        uint256 cooldownAmount = MINIMUM_STAKE * 3;
        vm.prank(alice);
        sapienVault.initiateUnstake(cooldownAmount);

        // Verify cooldown state
        assertEq(
            sapienVault.getTotalUnlocked(alice), stakeAmount - cooldownAmount, "Remaining tokens should be unlocked"
        );
        assertEq(sapienVault.getTotalLocked(alice), 0, "No tokens should be locked");
        assertEq(sapienVault.getTotalInCooldown(alice), cooldownAmount, "Cooldown amount should be tracked");
        assertEq(sapienVault.getTotalReadyForUnstake(alice), 0, "Nothing ready for unstake yet");
    }

    function test_Vault_CooldownLogic_InstantUnstakeExcludesStakesInCooldown() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10;

        // Alice stakes tokens
        vm.startPrank(alice);
        mockToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Time passes, stake becomes unlocked
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Alice initiates cooldown for part of the stake
        uint256 cooldownAmount = MINIMUM_STAKE * 3;
        vm.prank(alice);
        sapienVault.initiateUnstake(cooldownAmount);

        // CRITICAL TEST: Instant unstake should not work after lock period expires
        // Since the lock period is completed, instant unstake should fail
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("LockPeriodCompleted()"));
        sapienVault.earlyUnstake(MINIMUM_STAKE);

        // But we should be able to initiate more cooldown on remaining unlocked amounts
        vm.prank(alice);
        sapienVault.initiateUnstake(MINIMUM_STAKE * 2);

        assertEq(sapienVault.getTotalInCooldown(alice), MINIMUM_STAKE * 5, "Total cooldown should be 5000");
        assertEq(sapienVault.getTotalUnlocked(alice), MINIMUM_STAKE * 5, "Remaining unlocked should be 5000");
    }

    function test_Vault_CooldownLogic_InstantUnstakeWorksOnLockedStake() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10;

        // Alice stakes tokens
        vm.startPrank(alice);
        mockToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // While still locked, instant unstake should work
        assertEq(sapienVault.getTotalLocked(alice), stakeAmount, "All tokens should be locked");

        uint256 instantAmount = MINIMUM_STAKE * 3;
        uint256 expectedPenalty = (instantAmount * 20) / 100; // 20% penalty
        uint256 expectedPayout = instantAmount - expectedPenalty;

        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);
        uint256 treasuryBalanceBefore = mockToken.balanceOf(treasury);

        vm.prank(alice);
        sapienVault.earlyUnstake(instantAmount);

        // Verify instant unstake worked with penalty
        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore + expectedPayout, "Alice should receive reduced amount");
        assertEq(
            mockToken.balanceOf(treasury), treasuryBalanceBefore + expectedPenalty, "Treasury should receive penalty"
        );

        // Verify remaining stake
        (uint256 totalStaked,,,,,,,) = sapienVault.getUserStakingSummary(alice);
        assertEq(totalStaked, stakeAmount - instantAmount, "Remaining stake should be reduced");
    }

    function test_Vault_CooldownLogic_CannotIncreaseAmountDuringCooldown() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10;

        // Alice stakes tokens
        vm.startPrank(alice);
        mockToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Time passes, stake becomes unlocked
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Alice initiates cooldown
        vm.prank(alice);
        sapienVault.initiateUnstake(MINIMUM_STAKE * 3);

        // Alice tries to increase stake amount during cooldown - should fail
        vm.startPrank(alice);
        mockToken.approve(address(sapienVault), MINIMUM_STAKE);
        vm.expectRevert(abi.encodeWithSignature("CannotIncreaseStakeInCooldown()"));
        sapienVault.increaseAmount(MINIMUM_STAKE);
        vm.stopPrank();
    }

    function test_Vault_CooldownLogic_CannotIncreaseLockupDuringCooldown() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10;

        // Alice stakes tokens
        vm.startPrank(alice);
        mockToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Time passes, stake becomes unlocked
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Alice initiates cooldown
        vm.prank(alice);
        sapienVault.initiateUnstake(MINIMUM_STAKE * 3);

        // Alice tries to increase lockup during cooldown - should fail
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSignature("CannotIncreaseStakeInCooldown()"));
        sapienVault.increaseLockup(30 days);
    }

    function test_Vault_CooldownLogic_MultiplePartialCooldowns() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10;

        // Alice stakes tokens
        vm.startPrank(alice);
        mockToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Time passes, stake becomes unlocked
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // First partial cooldown
        vm.prank(alice);
        sapienVault.initiateUnstake(MINIMUM_STAKE * 3);

        assertEq(sapienVault.getTotalInCooldown(alice), MINIMUM_STAKE * 3, "First cooldown should be 3000");
        assertEq(sapienVault.getTotalUnlocked(alice), MINIMUM_STAKE * 7, "Remaining unlocked should be 7000");

        // Second partial cooldown
        vm.prank(alice);
        sapienVault.initiateUnstake(MINIMUM_STAKE * 2);

        assertEq(sapienVault.getTotalInCooldown(alice), MINIMUM_STAKE * 5, "Total cooldown should be 5000");
        assertEq(sapienVault.getTotalUnlocked(alice), MINIMUM_STAKE * 5, "Remaining unlocked should be 5000");

        // Third partial cooldown - all remaining
        vm.prank(alice);
        sapienVault.initiateUnstake(MINIMUM_STAKE * 5);

        assertEq(sapienVault.getTotalInCooldown(alice), MINIMUM_STAKE * 10, "All should be in cooldown");
        assertEq(sapienVault.getTotalUnlocked(alice), 0, "Nothing should be unlocked");
    }

    function test_Vault_CooldownLogic_CooldownReadyAfterPeriod() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10;

        // Alice stakes tokens
        vm.startPrank(alice);
        mockToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        // Time passes, stake becomes unlocked
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Alice initiates cooldown
        uint256 cooldownAmount = MINIMUM_STAKE * 3;
        vm.prank(alice);
        sapienVault.initiateUnstake(cooldownAmount);

        // Initially not ready for unstake
        assertEq(sapienVault.getTotalReadyForUnstake(alice), 0, "Nothing ready initially");

        // After cooldown period
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        assertEq(sapienVault.getTotalReadyForUnstake(alice), cooldownAmount, "Cooldown amount should be ready");
        assertEq(sapienVault.getTotalInCooldown(alice), cooldownAmount, "Should still show in cooldown");

        // Complete the unstake
        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);

        vm.prank(alice);
        sapienVault.unstake(cooldownAmount);

        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore + cooldownAmount, "Alice should receive tokens");
        assertEq(sapienVault.getTotalInCooldown(alice), 0, "Cooldown should be cleared");
        assertEq(sapienVault.getTotalReadyForUnstake(alice), 0, "Nothing ready after unstake");

        (uint256 totalStaked,,,,,,,) = sapienVault.getUserStakingSummary(alice);
        assertEq(totalStaked, stakeAmount - cooldownAmount, "Stake should be reduced");
    }

    function test_Vault_CooldownLogic_PartialUnstakeFromCooldown() public {
        uint256 stakeAmount = MINIMUM_STAKE * 10;
        uint256 cooldownAmount = MINIMUM_STAKE * 6;

        // Alice stakes and waits for unlock
        vm.startPrank(alice);
        mockToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);
        vm.stopPrank();

        vm.warp(block.timestamp + LOCK_30_DAYS + 1);

        // Alice initiates cooldown for most of her stake
        vm.prank(alice);
        sapienVault.initiateUnstake(cooldownAmount);

        // Wait for cooldown to complete
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);

        // Partial unstake from cooldown
        uint256 partialUnstake = MINIMUM_STAKE * 2;
        uint256 aliceBalanceBefore = mockToken.balanceOf(alice);

        vm.prank(alice);
        sapienVault.unstake(partialUnstake);

        assertEq(mockToken.balanceOf(alice), aliceBalanceBefore + partialUnstake, "Partial unstake should work");
        assertEq(sapienVault.getTotalInCooldown(alice), cooldownAmount - partialUnstake, "Remaining cooldown");
        assertEq(sapienVault.getTotalReadyForUnstake(alice), cooldownAmount - partialUnstake, "Remaining ready");

        // Complete the rest
        vm.prank(alice);
        sapienVault.unstake(cooldownAmount - partialUnstake);

        assertEq(sapienVault.getTotalInCooldown(alice), 0, "All cooldown should be cleared");

        (uint256 totalStaked,,,,,,,) = sapienVault.getUserStakingSummary(alice);
        assertEq(totalStaked, stakeAmount - cooldownAmount, "Final stake should be correct");
    }
}
