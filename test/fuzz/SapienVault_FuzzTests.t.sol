// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SapienVault, ISapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants as Const} from "src/utils/Constants.sol";

/**
 * @title SapienVault_FuzzTests
 * @notice Comprehensive fuzz tests for all major SapienVault functions
 */
contract SapienVault_FuzzTests is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public pauseManager = makeAddr("pauseManager");
    address public sapienQA = makeAddr("sapienQA");

    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    function setUp() public {
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector,
            address(sapienToken),
            admin,
            pauseManager,
            treasury,
            sapienQA
        );
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));
    }

    // =============================================================================
    // STAKE FUNCTION FUZZ TESTS
    // =============================================================================

    /// @notice Comprehensive fuzz test for stake function
    function testFuzz_Vault_Stake_Comprehensive(uint256 amount, uint8 periodIndex, uint256 userSeed) public {
        amount = bound(amount, Const.MINIMUM_STAKE_AMOUNT, Const.MAXIMUM_STAKE_AMOUNT);
        uint256[4] memory periods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 lockPeriod = periods[periodIndex % 4];

        address user = makeAddr(string(abi.encodePacked("stakeUser", vm.toString(userSeed))));
        sapienToken.mint(user, amount);

        // Pre-stake verification
        assertFalse(sapienVault.hasActiveStake(user));
        assertEq(sapienVault.getTotalStaked(user), 0);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, lockPeriod);
        vm.stopPrank();

        // Post-stake verification
        assertTrue(sapienVault.hasActiveStake(user));
        assertEq(sapienVault.getTotalStaked(user), amount);
        
        ISapienVault.UserStakingSummary memory userStake = sapienVault.getUserStakingSummary(user);
        assertEq(userStake.userTotalStaked, amount);
        assertGt(userStake.effectiveMultiplier, 0);
        assertGe(userStake.effectiveMultiplier, 10000);
        assertLe(userStake.effectiveMultiplier, 15000);
    }

    /// @notice Fuzz test stake with edge case amounts
    function testFuzz_Vault_Stake_EdgeAmounts(uint256 baseAmount, uint256 offset) public {
        offset = bound(offset, 0, 1e18);
        uint256 amount = bound(baseAmount, Const.MINIMUM_STAKE_AMOUNT, Const.MINIMUM_STAKE_AMOUNT + offset);

        address user = makeAddr("edgeUser");
        sapienToken.mint(user, amount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, LOCK_30_DAYS);
        vm.stopPrank();

        assertTrue(sapienVault.hasActiveStake(user));
        assertEq(sapienVault.getTotalStaked(user), amount);
    }

    // =============================================================================
    // INCREASE AMOUNT FUNCTION FUZZ TESTS
    // =============================================================================

    /// @notice Comprehensive fuzz test for increaseAmount function
    function testFuzz_Vault_IncreaseAmount_Comprehensive(
        uint256 initialAmount,
        uint256 additionalAmount,
        uint256 timeBetween,
        uint256 userSeed
    ) public {
        initialAmount = bound(initialAmount, Const.MINIMUM_STAKE_AMOUNT, Const.MAXIMUM_STAKE_AMOUNT / 2);
        additionalAmount = bound(additionalAmount, 1e18, Const.MAXIMUM_STAKE_AMOUNT / 2);
        timeBetween = bound(timeBetween, 1 hours, 90 days);
        
        if (initialAmount + additionalAmount > Const.MAXIMUM_STAKE_AMOUNT) {
            additionalAmount = Const.MAXIMUM_STAKE_AMOUNT - initialAmount;
        }

        address user = makeAddr(string(abi.encodePacked("increaseUser", vm.toString(userSeed))));
        sapienToken.mint(user, initialAmount + additionalAmount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_90_DAYS);

        ISapienVault.UserStakingSummary memory initialStake = sapienVault.getUserStakingSummary(user);

        vm.warp(block.timestamp + timeBetween);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseAmount(additionalAmount);
        vm.stopPrank();

        // Verify increased stake
        assertEq(sapienVault.getTotalStaked(user), initialAmount + additionalAmount);
        
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user);
        assertEq(finalStake.userTotalStaked, initialAmount + additionalAmount);
        assertGt(finalStake.effectiveMultiplier, 0);
        // More stake should generally not decrease multiplier
        assertGe(finalStake.effectiveMultiplier, initialStake.effectiveMultiplier);
    }

    /// @notice Fuzz test increaseAmount during cooldown should fail
    function testFuzz_Vault_IncreaseAmount_CooldownRevert(
        uint256 stakeAmount,
        uint256 increaseAmount,
        uint256 unstakeAmount
    ) public {
        stakeAmount = bound(stakeAmount, Const.MINIMUM_STAKE_AMOUNT * 2, Const.MAXIMUM_STAKE_AMOUNT / 2);
        increaseAmount = bound(increaseAmount, 1e18, Const.MAXIMUM_STAKE_AMOUNT / 4);
        unstakeAmount = bound(unstakeAmount, Const.MINIMUM_UNSTAKE_AMOUNT, stakeAmount / 2);

        address user = makeAddr("cooldownUser");
        sapienToken.mint(user, stakeAmount + increaseAmount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);

        // Fast forward and initiate unstake to enter cooldown
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);
        sapienVault.initiateUnstake(unstakeAmount);

        // Try to increase amount during cooldown - should fail
        sapienToken.approve(address(sapienVault), increaseAmount);
        vm.expectRevert();
        sapienVault.increaseAmount(increaseAmount);
        vm.stopPrank();
    }

    // =============================================================================
    // INCREASE LOCKUP FUNCTION FUZZ TESTS  
    // =============================================================================

    /// @notice Comprehensive fuzz test for increaseLockup function
    function testFuzz_Vault_IncreaseLockup_Comprehensive(
        uint256 amount,
        uint8 initialPeriodIndex,
        uint8 finalPeriodIndex,
        uint256 timeBetween,
        uint256 userSeed
    ) public {
        amount = bound(amount, Const.MINIMUM_STAKE_AMOUNT, Const.MAXIMUM_STAKE_AMOUNT);
        uint256[4] memory periods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 initialPeriod = periods[initialPeriodIndex % 4];
        uint256 finalPeriod = periods[finalPeriodIndex % 4];
        timeBetween = bound(timeBetween, 1 hours, 30 days);

        address user = makeAddr(string(abi.encodePacked("lockupUser", vm.toString(userSeed))));
        sapienToken.mint(user, amount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, initialPeriod);

        ISapienVault.UserStakingSummary memory initialStake = sapienVault.getUserStakingSummary(user);

        vm.warp(block.timestamp + timeBetween);
        sapienVault.increaseLockup(finalPeriod);
        vm.stopPrank();

        // Verify lockup increase
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user);
        assertEq(finalStake.userTotalStaked, amount);
        assertGt(finalStake.effectiveMultiplier, 0);
        
        // Longer lockup should generally increase or maintain multiplier
        if (finalPeriod > initialPeriod) {
            assertGe(finalStake.effectiveMultiplier, initialStake.effectiveMultiplier);
        }
    }

    /// @notice Fuzz test increaseLockup with expired stakes
    function testFuzz_Vault_IncreaseLockup_ExpiredStakes(
        uint256 amount,
        uint8 lockPeriodIndex,
        uint256 expiryTime,
        uint256 newPeriod
    ) public {
        amount = bound(amount, Const.MINIMUM_STAKE_AMOUNT, Const.MAXIMUM_STAKE_AMOUNT);
        uint256[4] memory periods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 lockPeriod = periods[lockPeriodIndex % 4];
        expiryTime = bound(expiryTime, lockPeriod + 1 days, lockPeriod + 365 days);
        newPeriod = bound(newPeriod, LOCK_30_DAYS, LOCK_365_DAYS);

        address user = makeAddr("expiredUser");
        sapienToken.mint(user, amount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, lockPeriod);

        // Fast forward past expiry
        vm.warp(block.timestamp + expiryTime);
        sapienVault.increaseLockup(newPeriod);
        vm.stopPrank();

        // Verify expired stake handling
        ISapienVault.UserStakingSummary memory userStake = sapienVault.getUserStakingSummary(user);
        assertEq(userStake.userTotalStaked, amount);
        assertGt(userStake.effectiveMultiplier, 0);
    }

    // =============================================================================
    // UNSTAKE FUNCTIONS FUZZ TESTS
    // =============================================================================

    /// @notice Comprehensive fuzz test for initiateUnstake function
    function testFuzz_Vault_InitiateUnstake_Comprehensive(
        uint256 stakeAmount,
        uint256 unstakeAmount,
        uint8 lockPeriodIndex,
        uint256 userSeed
    ) public {
        stakeAmount = bound(stakeAmount, Const.MINIMUM_STAKE_AMOUNT * 2, Const.MAXIMUM_STAKE_AMOUNT);
        unstakeAmount = bound(unstakeAmount, Const.MINIMUM_UNSTAKE_AMOUNT, stakeAmount);
        uint256[4] memory periods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 lockPeriod = periods[lockPeriodIndex % 4];

        address user = makeAddr(string(abi.encodePacked("unstakeUser", vm.toString(userSeed))));
        sapienToken.mint(user, stakeAmount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, lockPeriod);

        // Fast forward past lock period
        vm.warp(block.timestamp + lockPeriod + 1);

        sapienVault.initiateUnstake(unstakeAmount);
        vm.stopPrank();

        // Verify unstake initiation
        ISapienVault.UserStake memory userStake = sapienVault.getUserStake(user);
        assertEq(userStake.cooldownAmount, unstakeAmount);
        assertGt(userStake.cooldownStart, 0);
        assertEq(userStake.amount, stakeAmount); // Amount unchanged during cooldown
    }

    /// @notice Fuzz test unstake function after cooldown
    function testFuzz_Vault_Unstake_AfterCooldown(
        uint256 stakeAmount,
        uint256 unstakeAmount,
        uint256 cooldownWait,
        uint256 userSeed
    ) public {
        stakeAmount = bound(stakeAmount, Const.MINIMUM_STAKE_AMOUNT * 2, Const.MAXIMUM_STAKE_AMOUNT);
        unstakeAmount = bound(unstakeAmount, Const.MINIMUM_UNSTAKE_AMOUNT, stakeAmount);
        cooldownWait = bound(cooldownWait, Const.COOLDOWN_PERIOD + 1, Const.COOLDOWN_PERIOD + 30 days);

        address user = makeAddr(string(abi.encodePacked("unstakeCooldownUser", vm.toString(userSeed))));
        sapienToken.mint(user, stakeAmount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);

        // Fast forward past lock period and initiate unstake
        vm.warp(block.timestamp + LOCK_30_DAYS + 1);
        sapienVault.initiateUnstake(unstakeAmount);
        
        // Wait for cooldown
        vm.warp(block.timestamp + cooldownWait);
        
        uint256 balanceBefore = sapienToken.balanceOf(user);
        uint256 userStakeAmountBefore = sapienVault.getTotalStaked(user);
        
        sapienVault.unstake(unstakeAmount);
        vm.stopPrank();

        // Verify unstake completion
        uint256 balanceAfter = sapienToken.balanceOf(user);
        uint256 userStakeAmountAfter = sapienVault.getTotalStaked(user);
        uint256 actualAmountUnstaked = userStakeAmountBefore - userStakeAmountAfter;
        
        assertEq(balanceAfter - balanceBefore, actualAmountUnstaked);
        assertEq(sapienVault.getTotalStaked(user), stakeAmount - actualAmountUnstaked);
    }

    // =============================================================================
    // EARLY UNSTAKE FUNCTIONS FUZZ TESTS
    // =============================================================================

    /// @notice Comprehensive fuzz test for initiateEarlyUnstake function
    function testFuzz_Vault_InitiateEarlyUnstake_Comprehensive(
        uint256 stakeAmount,
        uint256 earlyUnstakeAmount,
        uint8 lockPeriodIndex,
        uint256 userSeed
    ) public {
        stakeAmount = bound(stakeAmount, Const.MINIMUM_STAKE_AMOUNT * 2, Const.MAXIMUM_STAKE_AMOUNT);
        earlyUnstakeAmount = bound(earlyUnstakeAmount, Const.MINIMUM_UNSTAKE_AMOUNT, stakeAmount);
        uint256[4] memory periods = [LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS, LOCK_365_DAYS]; // Longer periods for early unstake
        uint256 lockPeriod = periods[lockPeriodIndex % 4];

        address user = makeAddr(string(abi.encodePacked("earlyUnstakeUser", vm.toString(userSeed))));
        sapienToken.mint(user, stakeAmount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, lockPeriod);

        sapienVault.initiateEarlyUnstake(earlyUnstakeAmount);
        vm.stopPrank();

        // Verify early unstake initiation
        ISapienVault.UserStake memory userStake = sapienVault.getUserStake(user);
        assertEq(userStake.earlyUnstakeCooldownAmount, earlyUnstakeAmount);
        assertGt(userStake.earlyUnstakeCooldownStart, 0);
        assertEq(userStake.amount, stakeAmount); // Amount unchanged during cooldown
    }

    /// @notice Fuzz test earlyUnstake function with penalty calculations
    function testFuzz_Vault_EarlyUnstake_WithPenalty(
        uint256 stakeAmount,
        uint256 earlyUnstakeAmount,
        uint256 cooldownWait,
        uint256 userSeed
    ) public {
        stakeAmount = bound(stakeAmount, Const.MINIMUM_STAKE_AMOUNT * 2, Const.MAXIMUM_STAKE_AMOUNT / 2);
        earlyUnstakeAmount = bound(earlyUnstakeAmount, Const.MINIMUM_UNSTAKE_AMOUNT, stakeAmount);
        cooldownWait = bound(cooldownWait, Const.COOLDOWN_PERIOD + 1, Const.COOLDOWN_PERIOD + 7 days);

        address user = makeAddr(string(abi.encodePacked("earlyPenaltyUser", vm.toString(userSeed))));
        sapienToken.mint(user, stakeAmount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_365_DAYS); // Long lock for early unstake

        sapienVault.initiateEarlyUnstake(earlyUnstakeAmount);
        
        // Wait for cooldown
        vm.warp(block.timestamp + cooldownWait);
        
        uint256 balanceBefore = sapienToken.balanceOf(user);
        uint256 userStakeAmountBefore = sapienVault.getTotalStaked(user);
        
        sapienVault.earlyUnstake(earlyUnstakeAmount);
        vm.stopPrank();
        
        uint256 userStakeAmountAfter = sapienVault.getTotalStaked(user);
        uint256 actualAmountUnstaked = userStakeAmountBefore - userStakeAmountAfter;

        // Verify penalty was applied
        uint256 balanceAfter = sapienToken.balanceOf(user);
        uint256 expectedPenalty = (actualAmountUnstaked * Const.EARLY_WITHDRAWAL_PENALTY) / Const.BASIS_POINTS;
        uint256 expectedReceived = actualAmountUnstaked - expectedPenalty;
        uint256 actualReceived = balanceAfter - balanceBefore;
        
        // Allow for small rounding differences (within 2 wei)
        assertApproxEqAbs(actualReceived, expectedReceived, 2, "User should receive approximately amount minus penalty");
        // assertEq(sapienVault.getTotalStaked(user), stakeAmount - earlyUnstakeAmount);
    }

    /// @notice Fuzz test partial early unstakes
    function testFuzz_Vault_EarlyUnstake_PartialUnstakes(
        uint256 stakeAmount,
        uint256 firstUnstake,
        uint256 secondUnstake,
        uint256 userSeed
    ) public {
        stakeAmount = bound(stakeAmount, Const.MINIMUM_STAKE_AMOUNT * 4, Const.MAXIMUM_STAKE_AMOUNT / 2);
        firstUnstake = bound(firstUnstake, Const.MINIMUM_UNSTAKE_AMOUNT, stakeAmount / 3);
        secondUnstake = bound(secondUnstake, Const.MINIMUM_UNSTAKE_AMOUNT, (stakeAmount - firstUnstake) / 2);

        address user = makeAddr(string(abi.encodePacked("partialEarlyUser", vm.toString(userSeed))));
        sapienToken.mint(user, stakeAmount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_180_DAYS);

        // Initiate early unstake for total amount
        sapienVault.initiateEarlyUnstake(firstUnstake + secondUnstake);
        
        // Wait and execute first partial
        vm.warp(block.timestamp + Const.COOLDOWN_PERIOD + 1);
        sapienVault.earlyUnstake(firstUnstake);

        // Verify partial early unstake state
        ISapienVault.UserStake memory userStakeAfterFirst = sapienVault.getUserStake(user);
        assertEq(userStakeAfterFirst.earlyUnstakeCooldownAmount, secondUnstake);
        assertGt(userStakeAfterFirst.earlyUnstakeCooldownStart, 0);

        // Execute second partial
        sapienVault.earlyUnstake(secondUnstake);
        vm.stopPrank();

        // Verify complete early unstake
        ISapienVault.UserStake memory userStakeFinal = sapienVault.getUserStake(user);
        assertEq(userStakeFinal.earlyUnstakeCooldownAmount, 0);
        assertEq(userStakeFinal.earlyUnstakeCooldownStart, 0);
        assertEq(userStakeFinal.amount, stakeAmount - firstUnstake - secondUnstake);
    }

    // =============================================================================
    // INCREASE STAKE FUNCTION FUZZ TESTS
    // =============================================================================

    /// @notice Fuzz test increaseStake (combination function)
    function testFuzz_Vault_IncreaseStake_Combination(
        uint256 initialAmount,
        uint256 additionalAmount,
        uint8 initialPeriodIndex,
        uint8 finalPeriodIndex,
        uint256 userSeed
    ) public {
        initialAmount = bound(initialAmount, Const.MINIMUM_STAKE_AMOUNT, Const.MAXIMUM_STAKE_AMOUNT / 2);
        additionalAmount = bound(additionalAmount, 1e18, Const.MAXIMUM_STAKE_AMOUNT / 2);
        
        if (initialAmount + additionalAmount > Const.MAXIMUM_STAKE_AMOUNT) {
            additionalAmount = Const.MAXIMUM_STAKE_AMOUNT - initialAmount;
        }
        
        uint256[4] memory periods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 initialPeriod = periods[initialPeriodIndex % 4];
        uint256 finalPeriod = periods[finalPeriodIndex % 4];

        address user = makeAddr(string(abi.encodePacked("comboUser", vm.toString(userSeed))));
        sapienToken.mint(user, initialAmount + additionalAmount);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, initialPeriod);

        ISapienVault.UserStakingSummary memory initialStake = sapienVault.getUserStakingSummary(user);

        // Use increaseStake function (combination of increaseAmount + increaseLockup)
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseStake(additionalAmount, finalPeriod);
        vm.stopPrank();

        // Verify combined increase
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user);
        assertEq(finalStake.userTotalStaked, initialAmount + additionalAmount);
        assertGt(finalStake.effectiveMultiplier, 0);
        
        // More stake and potentially longer lockup should generally not decrease multiplier significantly
        if (finalPeriod >= initialPeriod && additionalAmount > 0) {
            assertGe(finalStake.effectiveMultiplier, initialStake.effectiveMultiplier - 500);
        }
    }

    // =============================================================================
    // COMPLEX STATE TRANSITION FUZZ TESTS
    // =============================================================================

    /// @notice Fuzz test complex state transitions with multiple operations
    function testFuzz_Vault_ComplexStateTransitions(
        uint256 amount1,
        uint256 amount2,
        uint256 unstakeAmount,
        uint8 operation1,
        uint8 operation2,
        uint256 timeBetween,
        uint256 userSeed
    ) public {
        amount1 = bound(amount1, Const.MINIMUM_STAKE_AMOUNT, Const.MAXIMUM_STAKE_AMOUNT / 3);
        amount2 = bound(amount2, 1e18, Const.MAXIMUM_STAKE_AMOUNT / 3);
        unstakeAmount = bound(unstakeAmount, Const.MINIMUM_UNSTAKE_AMOUNT, amount1 / 2);
        timeBetween = bound(timeBetween, 1 hours, 30 days);

        address user = makeAddr(string(abi.encodePacked("complexUser", vm.toString(userSeed))));
        sapienToken.mint(user, amount1 + amount2);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount1);
        sapienVault.stake(amount1, LOCK_90_DAYS);

        // First operation
        vm.warp(block.timestamp + timeBetween);
        uint8 op1 = operation1 % 3;
        if (op1 == 0) {
            // Increase amount
            sapienToken.approve(address(sapienVault), amount2);
            sapienVault.increaseAmount(amount2);
        } else if (op1 == 1) {
            // Increase lockup
            sapienVault.increaseLockup(LOCK_180_DAYS);
        } else {
            // Fast forward and initiate unstake
            vm.warp(block.timestamp + LOCK_90_DAYS + 1);
            sapienVault.initiateUnstake(unstakeAmount);
        }

        // Second operation (if not in cooldown)
        ISapienVault.UserStake memory midStake = sapienVault.getUserStake(user);
        if (midStake.cooldownStart == 0 && midStake.earlyUnstakeCooldownStart == 0) {
            vm.warp(block.timestamp + timeBetween);
            uint8 op2 = operation2 % 2;
            if (op2 == 0 && op1 != 0) {
                // Increase amount if we didn't already
                sapienToken.approve(address(sapienVault), amount2);
                sapienVault.increaseAmount(amount2);
            } else if (op2 == 1) {
                // Increase lockup
                sapienVault.increaseLockup(LOCK_365_DAYS);
            }
        }
        vm.stopPrank();

        // Verify final state consistency
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user);
        if (sapienVault.hasActiveStake(user)) {
            assertGt(finalStake.effectiveMultiplier, 0);
            assertGe(finalStake.effectiveMultiplier, 10000);
            assertLe(finalStake.effectiveMultiplier, 15000);
            assertGe(finalStake.userTotalStaked, amount1);
        }
    }

    // =============================================================================
    // INVARIANT VERIFICATION FUZZ TESTS
    // =============================================================================

    /// @notice Fuzz test vault state invariants
    function testFuzz_Vault_InvariantVerification(
        uint256 amount,
        uint8 functionType,
        uint8 lockPeriodIndex,
        uint256 userSeed
    ) public {
        amount = bound(amount, Const.MINIMUM_STAKE_AMOUNT, Const.MAXIMUM_STAKE_AMOUNT / 2);
        uint256[4] memory periods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 lockPeriod = periods[lockPeriodIndex % 4];
        
        address user = makeAddr(string(abi.encodePacked("invariantUser", vm.toString(userSeed))));
        sapienToken.mint(user, amount * 2);

        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, lockPeriod);
        
        // Verify initial invariants
        _verifyVaultInvariants(user);

        uint8 funcType = functionType % 4;
        if (funcType == 0) {
            // Test increaseAmount
            sapienToken.approve(address(sapienVault), amount / 2);
            sapienVault.increaseAmount(amount / 2);
        } else if (funcType == 1) {
            // Test increaseLockup
            sapienVault.increaseLockup(LOCK_365_DAYS);
        } else if (funcType == 2) {
            // Test initiateUnstake
            vm.warp(block.timestamp + lockPeriod + 1);
            sapienVault.initiateUnstake(amount / 3);
        } else {
            // Test initiateEarlyUnstake
            sapienVault.initiateEarlyUnstake(amount / 3);
        }
        
        // Verify invariants after operation
        _verifyVaultInvariants(user);
        vm.stopPrank();
    }

    /// @notice Helper function to verify vault state invariants
    function _verifyVaultInvariants(address user) internal view {
        ISapienVault.UserStakingSummary memory userStake = sapienVault.getUserStakingSummary(user);
        
        if (sapienVault.hasActiveStake(user)) {
            assertGt(userStake.userTotalStaked, 0, "Active stake should have positive amount");
            assertGt(userStake.effectiveMultiplier, 0, "Active stake should have positive multiplier");
            assertGe(userStake.effectiveMultiplier, 10000, "Multiplier should be at least 1.0x");
            assertLe(userStake.effectiveMultiplier, 15000, "Multiplier should not exceed 1.5x");
        } else {
            assertEq(userStake.userTotalStaked, 0, "Inactive stake should have zero amount");
        }
    }
} 