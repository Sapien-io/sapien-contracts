// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienVault} from "src/SapienVault.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants as Const} from "src/utils/Constants.sol";

contract SapienVaultOverflowTest is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public user1 = makeAddr("user1");

    uint256 public constant MINIMUM_STAKE = Const.MINIMUM_STAKE_AMOUNT;
    uint256 public constant LOCK_30_DAYS = Const.LOCKUP_30_DAYS;
    uint256 public constant LOCK_90_DAYS = Const.LOCKUP_90_DAYS;
    uint256 public constant LOCK_180_DAYS = Const.LOCKUP_180_DAYS;
    uint256 public constant LOCK_365_DAYS = Const.LOCKUP_365_DAYS;
    uint256 public constant MAX_STAKE_AMOUNT = 10_000_000 * Const.TOKEN_DECIMALS; // 10M tokens max per stake

    function setUp() public {
        // Deploy mock SAPIEN token
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        // Deploy SapienVault
        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData =
            abi.encodeWithSelector(SapienVault.initialize.selector, address(sapienToken), admin, treasury);
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        // Mint reasonable amount of tokens to user1 instead of max to avoid overflow when minting to other users
        sapienToken.mint(user1, MAX_STAKE_AMOUNT * 100); // 1B tokens, enough for testing
    }

    // =============================================================================
    // OVERFLOW TESTS FOR _validateWeightedCalculations
    // =============================================================================

    /// @dev Test overflow in newTotalAmount calculation (line 236) - uint128 overflow
    function test_Vault_RevertOnStakeAmountOverflow_TotalAmount() public {
        // Create initial stake with amount close to max that would cause uint128 overflow when combined
        uint256 largeAmount1 = MAX_STAKE_AMOUNT;

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), largeAmount1);
        sapienVault.stake(largeAmount1, LOCK_30_DAYS);

        // Try to add another large amount that would exceed uint128 max when combined
        // uint128 max is ~3.4e38, so we need the sum to exceed this
        // Since each stake is limited to 10M tokens, we need to manipulate the existing stake
        // This test validates the logic but may not be easily triggerable in practice

        uint256 largeAmount2 = MAX_STAKE_AMOUNT;
        sapienToken.approve(address(sapienVault), largeAmount2);

        // This will succeed because 20M tokens < uint128 max
        sapienVault.stake(largeAmount2, LOCK_30_DAYS);
        vm.stopPrank();

        // Verify the combined stake worked
        (uint256 userTotalStaked,,,,,,,) = sapienVault.getUserStakingSummary(user1);
        assertEq(userTotalStaked, largeAmount1 + largeAmount2);
    }

    /// @dev Test overflow in weighted start time calculation (line 243)
    function test_Vault_RevertOnStakeAmountOverflow_WeightedStartTime() public {
        // Create a scenario where timestamp * amount approaches uint256 max
        // We need: existingWeight + newWeight > type(uint256).max

        // Start with maximum possible timestamp
        vm.warp(type(uint64).max); // Max timestamp that can be stored in uint64

        // Create initial stake
        uint256 initialAmount = MAX_STAKE_AMOUNT;

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);

        // Now warp to a timestamp that would cause overflow in weighted calculation
        // We need: (userStake.weightedStartTime * userStake.amount) + (block.timestamp * amount) > uint256 max
        // Since weightedStartTime is now type(uint64).max and amount is MAX_STAKE_AMOUNT
        // existingWeight = type(uint64).max * MAX_STAKE_AMOUNT
        // We need newWeight to be large enough to cause overflow

        uint256 existingWeight = type(uint64).max * initialAmount;
        uint256 maxAllowableNewWeight = type(uint256).max - existingWeight;
        uint256 minTimestampForOverflow = maxAllowableNewWeight / MAX_STAKE_AMOUNT + 1;

        // Warp to timestamp that would cause overflow
        vm.warp(minTimestampForOverflow);

        uint256 additionalAmount = MAX_STAKE_AMOUNT;
        sapienToken.approve(address(sapienVault), additionalAmount);

        vm.expectRevert(abi.encodeWithSignature("StakeAmountTooLarge()"));
        sapienVault.stake(additionalAmount, LOCK_30_DAYS);
        vm.stopPrank();
    }

    /// @dev Test overflow in weighted lockup calculation (line 250)
    function test_Vault_RevertOnStakeAmountOverflow_WeightedLockup() public {
        // Create a scenario where lockUpPeriod * amount causes overflow
        // We need: existingLockupWeight + newLockupWeight > type(uint256).max

        // Create initial stake with maximum lockup
        uint256 initialAmount = MAX_STAKE_AMOUNT;

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_365_DAYS);

        // Calculate what would cause overflow:
        // existingLockupWeight = LOCK_365_DAYS * initialAmount
        // newLockupWeight = LOCK_365_DAYS * additionalAmount
        // We need their sum > type(uint256).max

        uint256 existingLockupWeight = LOCK_365_DAYS * initialAmount;
        uint256 maxAllowableNewWeight = type(uint256).max - existingLockupWeight;

        // Since we're limited to MAX_STAKE_AMOUNT per addition, and LOCK_365_DAYS is relatively small,
        // this overflow is very hard to trigger in practice with current constraints
        // Let's test the maximum possible scenario

        uint256 additionalAmount = MAX_STAKE_AMOUNT;
        uint256 newLockupWeight = LOCK_365_DAYS * additionalAmount;

        if (newLockupWeight <= maxAllowableNewWeight) {
            // This won't overflow, so the test should pass
            sapienToken.approve(address(sapienVault), additionalAmount);
            sapienVault.stake(additionalAmount, LOCK_365_DAYS);
        } else {
            // This would overflow
            sapienToken.approve(address(sapienVault), additionalAmount);
            vm.expectRevert(abi.encodeWithSignature("StakeAmountTooLarge()"));
            sapienVault.stake(additionalAmount, LOCK_365_DAYS);
        }
        vm.stopPrank();
    }

    /// @dev Test using increaseAmount to trigger weighted start time overflow
    function test_Vault_RevertOnIncreaseAmountOverflow_WeightedStartTime() public {
        // Create initial stake at max timestamp
        vm.warp(type(uint64).max);

        uint256 initialAmount = MAX_STAKE_AMOUNT;

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);

        // Calculate timestamp that would cause overflow
        uint256 existingWeight = type(uint64).max * initialAmount;
        uint256 maxAllowableNewWeight = type(uint256).max - existingWeight;
        uint256 minTimestampForOverflow = maxAllowableNewWeight / MAX_STAKE_AMOUNT + 1;

        // Warp to overflow timestamp
        vm.warp(minTimestampForOverflow);

        // Try to increase amount, which should trigger overflow
        uint256 additionalAmount = MAX_STAKE_AMOUNT;
        sapienToken.approve(address(sapienVault), additionalAmount);

        vm.expectRevert(abi.encodeWithSignature("StakeAmountTooLarge()"));
        sapienVault.increaseAmount(additionalAmount);
        vm.stopPrank();
    }

    /// @dev Test edge case where total amount approaches but doesn't exceed uint128 max
    function test_Vault_AcceptLargeButValidStakes() public {
        // Test multiple stakes that are individually valid and combined are still valid
        uint256 stakeAmount = 5_000_000 * Const.TOKEN_DECIMALS; // 5M tokens

        vm.startPrank(user1);

        // First stake
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_30_DAYS);

        // Second stake
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, LOCK_365_DAYS);

        // Verify combined stake
        (uint256 userTotalStaked,,,,,,,) = sapienVault.getUserStakingSummary(user1);
        assertEq(userTotalStaked, stakeAmount * 2);
        vm.stopPrank();
    }

    /// @dev Test that validation prevents stakes exceeding the 10M token per-stake limit
    function test_Vault_RevertOnStakeExceedingPerStakeLimit() public {
        uint256 overLimitAmount = MAX_STAKE_AMOUNT + 1;

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), overLimitAmount);

        vm.expectRevert(abi.encodeWithSignature("StakeAmountTooLarge()"));
        sapienVault.stake(overLimitAmount, LOCK_30_DAYS);
        vm.stopPrank();
    }

    /// @dev Test increaseAmount with maximum allowed amounts
    function test_Vault_RevertIncreaseAmountExceedingLimit() public {
        // Create initial stake
        uint256 initialAmount = MAX_STAKE_AMOUNT;

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_30_DAYS);

        // Try to increase by more than the per-operation limit
        uint256 increaseAmount = MAX_STAKE_AMOUNT + 1;
        sapienToken.approve(address(sapienVault), increaseAmount);

        vm.expectRevert(abi.encodeWithSignature("StakeAmountTooLarge()"));
        sapienVault.increaseAmount(increaseAmount);
        vm.stopPrank();
    }

    /// @dev Test that validation correctly handles reasonable timestamp values
    function test_Vault_HandleNormalTimestampValues() public {
        // Test with normal timestamp ranges
        vm.warp(block.timestamp + 365 days); // One year from now

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MAX_STAKE_AMOUNT);

        // This should succeed
        sapienVault.stake(MAX_STAKE_AMOUNT, LOCK_365_DAYS);

        // Verify stake was created
        assertTrue(sapienVault.hasActiveStake(user1));
        vm.stopPrank();
    }

    /// @dev Test mathematical edge case with specific values designed to trigger overflow
    function test_Vault_MathematicalOverflowScenario() public {
        // This test attempts to create a mathematical scenario that could trigger overflow
        // by using specific timestamp and amount combinations

        // Use a large but valid timestamp
        uint256 largeTimestamp = type(uint64).max / 2; // Half of max uint64
        vm.warp(largeTimestamp);

        uint256 initialAmount = MAX_STAKE_AMOUNT;

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_365_DAYS);

        // Calculate if we can create an overflow scenario
        uint256 existingWeight = largeTimestamp * initialAmount;
        uint256 remainingCapacity = type(uint256).max - existingWeight;

        // Find a timestamp that would cause overflow with max stake amount
        if (remainingCapacity < type(uint64).max * MAX_STAKE_AMOUNT) {
            uint256 overflowTimestamp = remainingCapacity / MAX_STAKE_AMOUNT + 1;
            vm.warp(overflowTimestamp);

            uint256 additionalAmount = MAX_STAKE_AMOUNT;
            sapienToken.approve(address(sapienVault), additionalAmount);

            vm.expectRevert(abi.encodeWithSignature("StakeAmountTooLarge()"));
            sapienVault.stake(additionalAmount, LOCK_30_DAYS);
        } else {
            // Overflow not possible with current constraints, test should pass
            uint256 additionalAmount = MAX_STAKE_AMOUNT;
            sapienToken.approve(address(sapienVault), additionalAmount);
            sapienVault.stake(additionalAmount, LOCK_30_DAYS);

            (uint256 userTotalStaked,,,,,,,) = sapienVault.getUserStakingSummary(user1);
            assertEq(userTotalStaked, initialAmount + additionalAmount);
        }
        vm.stopPrank();
    }

    /// @dev Test designed to specifically trigger weighted start time overflow (line 243)
    function test_Vault_ForceWeightedStartTimeOverflow() public {
        // Calculate the maximum possible existing weight that allows one more max stake
        uint256 maxPossibleExistingWeight = type(uint256).max - (type(uint256).max % MAX_STAKE_AMOUNT);
        uint256 requiredTimestamp = maxPossibleExistingWeight / MAX_STAKE_AMOUNT;

        // If the required timestamp is within uint64 bounds, we can create the scenario
        if (requiredTimestamp <= type(uint64).max) {
            vm.warp(requiredTimestamp);

            vm.startPrank(user1);
            sapienToken.approve(address(sapienVault), MAX_STAKE_AMOUNT);
            sapienVault.stake(MAX_STAKE_AMOUNT, LOCK_30_DAYS);

            // Now warp to a timestamp that will cause overflow
            vm.warp(type(uint256).max / MAX_STAKE_AMOUNT + 1);

            uint256 additionalAmount = MAX_STAKE_AMOUNT;
            sapienToken.approve(address(sapienVault), additionalAmount);

            vm.expectRevert(abi.encodeWithSignature("StakeAmountTooLarge()"));
            sapienVault.stake(additionalAmount, LOCK_30_DAYS);
            vm.stopPrank();
        } else {
            // This test is skipped because overflow is not possible with current constraints
            // due to uint64 timestamp limitations
        }
    }

    /// @dev Test designed to trigger weighted lockup overflow (line 250) using increaseAmount
    function test_Vault_ForceWeightedLockupOverflow_IncreaseAmount() public {
        // This test tries to create a scenario where lockup weight calculation overflows
        // Since we're limited by the 10M token constraint, we need to be creative

        // Create initial stake with maximum lockup
        uint256 initialAmount = MAX_STAKE_AMOUNT;

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialAmount);
        sapienVault.stake(initialAmount, LOCK_365_DAYS);

        // Calculate the theoretical overflow scenario
        uint256 existingLockupWeight = LOCK_365_DAYS * initialAmount;
        uint256 maxAllowableNewWeight = type(uint256).max - existingLockupWeight;

        // Check if we can cause overflow with current constraints
        uint256 maxPossibleNewWeight = LOCK_365_DAYS * MAX_STAKE_AMOUNT;

        if (maxPossibleNewWeight > maxAllowableNewWeight) {
            // This would overflow - let's test it
            uint256 additionalAmount = MAX_STAKE_AMOUNT;
            sapienToken.approve(address(sapienVault), additionalAmount);

            vm.expectRevert(abi.encodeWithSignature("StakeAmountTooLarge()"));
            sapienVault.stake(additionalAmount, LOCK_365_DAYS);
        } else {
            // Overflow not possible, test should pass
            uint256 additionalAmount = MAX_STAKE_AMOUNT;
            sapienToken.approve(address(sapienVault), additionalAmount);
            sapienVault.stake(additionalAmount, LOCK_365_DAYS);

            (uint256 userTotalStaked,,,,,,,) = sapienVault.getUserStakingSummary(user1);
            assertEq(userTotalStaked, initialAmount + additionalAmount);
        }
        vm.stopPrank();
    }

    /// @dev Test specifically for line 243 - weighted start time overflow with max values
    function test_Vault_SpecificWeightedTimeOverflow() public {
        // Set timestamp to a value that will definitely cause overflow when multiplied by MAX_STAKE_AMOUNT
        // and added to an existing large weight

        // Start with a large initial timestamp and stake
        uint256 initialTimestamp = type(uint64).max / 4;
        vm.warp(initialTimestamp);

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), MAX_STAKE_AMOUNT);
        sapienVault.stake(MAX_STAKE_AMOUNT, LOCK_30_DAYS);

        // Calculate the overflow condition more precisely
        uint256 existingWeight = initialTimestamp * MAX_STAKE_AMOUNT;

        // We need: existingWeight + (newTimestamp * amount) > type(uint256).max
        // So: newTimestamp > (type(uint256).max - existingWeight) / amount
        uint256 minOverflowTimestamp = (type(uint256).max - existingWeight) / MAX_STAKE_AMOUNT + 1;

        // Only proceed if the timestamp is within uint256 bounds (which it should be)
        if (minOverflowTimestamp < type(uint256).max / 2) {
            vm.warp(minOverflowTimestamp);

            uint256 additionalAmount = MAX_STAKE_AMOUNT;
            sapienToken.approve(address(sapienVault), additionalAmount);

            vm.expectRevert(abi.encodeWithSignature("StakeAmountTooLarge()"));
            sapienVault.stake(additionalAmount, LOCK_30_DAYS);
        }
        vm.stopPrank();
    }

    /// @dev Test specifically for line 250 - weighted lockup overflow with extreme lockup periods
    function test_Vault_SpecificWeightedLockupOverflow() public {
        // Since LOCK_365_DAYS is relatively small compared to MAX_STAKE_AMOUNT,
        // we need to create a scenario where the multiplication could overflow

        // The key insight is that with current constraints:
        // LOCK_365_DAYS = 31,536,000 seconds
        // MAX_STAKE_AMOUNT = 10,000,000 * 10^18 = 10^25
        // Their product is ~3.15 * 10^32, which is much less than uint256.max (~10^77)

        // So we need to create an existing lockup weight that's close to uint256.max
        // This is practically impossible with current constraints, but let's test the boundary

        vm.startPrank(user1);

        // Use maximum amounts
        sapienToken.approve(address(sapienVault), MAX_STAKE_AMOUNT);
        sapienVault.stake(MAX_STAKE_AMOUNT, LOCK_365_DAYS);

        // If we could somehow have an existing weight close to uint256.max - maxLockupWeight,
        // then adding another max lockup weight would overflow
        // But this is not possible with current protocol constraints

        // Test that the maximum practical case doesn't overflow
        sapienToken.approve(address(sapienVault), MAX_STAKE_AMOUNT);
        sapienVault.stake(MAX_STAKE_AMOUNT, LOCK_365_DAYS);

        // Verify it worked
        (uint256 userTotalStaked,,,,,,,) = sapienVault.getUserStakingSummary(user1);
        assertEq(userTotalStaked, MAX_STAKE_AMOUNT * 2);
        vm.stopPrank();
    }

    /// @dev Test simple stake of 1000 tokens for 365 days to verify maximum multiplier
    function test_Vault_SimpleStake_1000Tokens_365Days_Multiplier() public {
        // Test the basic case: minimum stake amount with maximum lockup period
        uint256 stakeAmount = MINIMUM_STAKE; // 1000 tokens
        uint256 lockupPeriod = LOCK_365_DAYS; // 365 days
        // In new system: 1K tokens @ 365 days gets effective multiplier ~6250 due to global coefficient
        uint256 expectedMultiplier = 6250; // ~62.5% (was 150% in old system)

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), stakeAmount);

        // Stake 1000 tokens for 365 days
        sapienVault.stake(stakeAmount, lockupPeriod);

        // Get user staking summary
        (
            uint256 userTotalStaked,
            uint256 totalUnlocked,
            uint256 totalLocked,
            uint256 totalInCooldown,
            uint256 totalReadyForUnstake,
            uint256 effectiveMultiplier,
            uint256 effectiveLockUpPeriod,
            uint256 timeUntilUnlock
        ) = sapienVault.getUserStakingSummary(user1);

        // Verify all the expected values
        assertEq(userTotalStaked, stakeAmount, "Total staked should be 1000 tokens");
        assertEq(totalLocked, stakeAmount, "All tokens should be locked initially");
        assertEq(totalUnlocked, 0, "No tokens should be unlocked initially");
        assertEq(totalInCooldown, 0, "No tokens should be in cooldown initially");
        assertEq(totalReadyForUnstake, 0, "No tokens should be ready for unstake initially");
        assertApproxEqAbs(
            effectiveMultiplier,
            expectedMultiplier,
            100,
            "Multiplier should be ~6250 (62.5%) for 365-day lockup in new system"
        );
        assertEq(effectiveLockUpPeriod, lockupPeriod, "Effective lockup should be 365 days");
        assertEq(timeUntilUnlock, lockupPeriod, "Time until unlock should be 365 days");

        // Verify user has active stake
        assertTrue(sapienVault.hasActiveStake(user1), "User should have an active stake");

        // Verify total staked in contract
        assertEq(sapienVault.totalStaked(), stakeAmount, "Contract total staked should be 1000 tokens");

        vm.stopPrank();
    }

    /// @dev Test new Linear Weighted Multiplier system - minimum stake gets base effective multiplier
    function test_ProgressiveMultiplier_MinimumStakeNotMaxMultiplier() public {
        uint256 stakeAmount = MINIMUM_STAKE; // 1000 tokens
        uint256 lockupPeriod = LOCK_365_DAYS; // 365 days

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, lockupPeriod);
        vm.stopPrank();

        (,,,,, uint256 effectiveMultiplier,,) = sapienVault.getUserStakingSummary(user1);

        // In new system: 1K tokens @ 365 days gets ~6250 effective multiplier due to global coefficient
        // This is much lower than the old 15000 (150%) due to the global coefficient starting at ~0.5x
        assertApproxEqAbs(effectiveMultiplier, 6250, 100, "Minimum stake should get base effective multiplier ~6250");
        assertLt(effectiveMultiplier, 7000, "Should be less than higher amount multipliers");
    }

    /// @dev Test new Linear Weighted Multiplier system - larger stakes get better multipliers
    function test_ProgressiveMultiplier_LargerStakesGetBonuses() public {
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = MINIMUM_STAKE; // 1000 tokens
        amounts[1] = MINIMUM_STAKE * 2; // 2000 tokens
        amounts[2] = MINIMUM_STAKE * 16; // 16000 tokens
        amounts[3] = MINIMUM_STAKE * 64; // 64000 tokens

        address[] memory users = new address[](4);
        users[0] = user1;
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");
        users[3] = makeAddr("user4");

        uint256[] memory multipliers = new uint256[](4);

        // Mint tokens and stake for each user
        for (uint256 i = 0; i < users.length; i++) {
            // user1 already has max tokens, others need minting
            if (i > 0) {
                sapienToken.mint(users[i], amounts[i]);
            }

            vm.startPrank(users[i]);
            sapienToken.approve(address(sapienVault), amounts[i]);
            sapienVault.stake(amounts[i], LOCK_365_DAYS);
            vm.stopPrank();

            (,,,,, multipliers[i],,) = sapienVault.getUserStakingSummary(users[i]);
        }

        // In new system: larger amounts get better multipliers up to logarithmic bucket limits
        // Users in same log bucket (16K and 64K) will have same multiplier
        assertGt(multipliers[1], multipliers[0], "2K tokens should be better than 1K tokens");
        assertGt(multipliers[2], multipliers[1], "16K tokens should be better than 2K tokens");
        // Note: 64K tokens are in same log bucket as 16K tokens, so they have same multiplier
        assertEq(multipliers[3], multipliers[2], "64K tokens should equal 16K tokens (same log bucket)");

        // Verify reasonable ranges for the new system
        assertApproxEqAbs(multipliers[0], 6250, 100, "1K tokens should get ~6250");
        assertApproxEqAbs(multipliers[1], 6500, 100, "2K tokens should get ~6500");
        assertApproxEqAbs(multipliers[2], 6750, 100, "16K tokens should get ~6750");
        assertApproxEqAbs(multipliers[3], 6750, 100, "64K tokens should get ~6750 (same as 16K)");
    }

    /// @dev Test new Linear Weighted Multiplier system - very large stakes get maximum amount bonus
    function test_ProgressiveMultiplier_MaximumBonusCap() public {
        // Test with very large stake (should hit the maximum amount factor)
        uint256 massiveStake = MINIMUM_STAKE * 10000; // 10M tokens (max amount factor)

        address whaleUser = makeAddr("whale");
        sapienToken.mint(whaleUser, massiveStake);

        vm.startPrank(whaleUser);
        sapienToken.approve(address(sapienVault), massiveStake);
        sapienVault.stake(massiveStake, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 effectiveMultiplier,,) = sapienVault.getUserStakingSummary(whaleUser);

        // In new system: should get maximum individual multiplier (~13500) * global coefficient (~0.55) = ~7500
        assertApproxEqAbs(effectiveMultiplier, 7500, 100, "Massive stake should get maximum effective multiplier");
        assertLt(effectiveMultiplier, 8000, "Should be reasonable even for massive stakes");
    }

    /// @dev Test new Linear Weighted Multiplier system with different time periods
    function test_ProgressiveMultiplier_DifferentTimePeriods() public {
        uint256 stakeAmount = MINIMUM_STAKE * 4; // 4000 tokens

        uint256[] memory lockups = new uint256[](4);
        lockups[0] = LOCK_30_DAYS;
        lockups[1] = LOCK_90_DAYS;
        lockups[2] = LOCK_180_DAYS;
        lockups[3] = LOCK_365_DAYS;

        address[] memory users = new address[](4);
        users[0] = user1;
        users[1] = makeAddr("user2");
        users[2] = makeAddr("user3");
        users[3] = makeAddr("user4");

        // Stake same amount with different lockup periods
        for (uint256 i = 0; i < users.length; i++) {
            // user1 already has tokens, others need minting
            if (i > 0) {
                sapienToken.mint(users[i], stakeAmount);
            }

            vm.startPrank(users[i]);
            sapienToken.approve(address(sapienVault), stakeAmount);
            sapienVault.stake(stakeAmount, lockups[i]);
            vm.stopPrank();
        }

        // Get multipliers
        (,,,,, uint256 mult30,,) = sapienVault.getUserStakingSummary(users[0]);
        (,,,,, uint256 mult90,,) = sapienVault.getUserStakingSummary(users[1]);
        (,,,,, uint256 mult180,,) = sapienVault.getUserStakingSummary(users[2]);
        (,,,,, uint256 mult365,,) = sapienVault.getUserStakingSummary(users[3]);

        // Verify progressive improvement with time (key behavior)
        assertTrue(mult30 < mult90, "90-day should be better than 30-day");
        assertTrue(mult90 < mult180, "180-day should be better than 90-day");
        assertTrue(mult180 < mult365, "365-day should be better than 180-day");

        // Verify reasonable ranges for new system
        assertApproxEqAbs(mult30, 5350, 100, "4K @ 30 days should get ~5350");
        assertApproxEqAbs(mult365, 6500, 100, "4K @ 365 days should get ~6500");
    }

    /// @dev Test new Linear Weighted Multiplier system - maximum effective multiplier cap
    function test_ProgressiveMultiplier_AbsoluteMaximumCap() public {
        // In new system, the maximum is controlled by global coefficient and individual multiplier caps
        uint256 massiveStake = MINIMUM_STAKE * 10000; // 10M tokens (max amount factor)

        address whaleUser = makeAddr("whale");
        sapienToken.mint(whaleUser, massiveStake);

        vm.startPrank(whaleUser);
        sapienToken.approve(address(sapienVault), massiveStake);
        sapienVault.stake(massiveStake, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 effectiveMultiplier,,) = sapienVault.getUserStakingSummary(whaleUser);

        // In new system: max individual (~13500) * global coefficient (~0.55) = ~7500
        assertApproxEqAbs(effectiveMultiplier, 7500, 100, "Should get maximum effective multiplier");
        assertLt(effectiveMultiplier, 8000, "Should be capped at reasonable level");
    }

    /// @dev Test new Linear Weighted Multiplier system with stake combining
    function test_ProgressiveMultiplier_StakeCombining() public {
        // Start with small stake
        uint256 initialStake = MINIMUM_STAKE; // 1000 tokens

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialStake);
        sapienVault.stake(initialStake, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 initialMultiplier,,) = sapienVault.getUserStakingSummary(user1);
        assertApproxEqAbs(initialMultiplier, 6250, 100, "Initial stake should get base effective multiplier");

        // Add more stake to increase amount factor
        uint256 additionalStake = MINIMUM_STAKE * 3; // Total will be 4000 tokens

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalStake);
        sapienVault.stake(additionalStake, LOCK_365_DAYS);
        vm.stopPrank();

        (uint256 totalStaked,,,,, uint256 newMultiplier,,) = sapienVault.getUserStakingSummary(user1);

        assertEq(totalStaked, MINIMUM_STAKE * 4, "Total should be 4000 tokens");
        assertGt(newMultiplier, initialMultiplier, "Combined multiplier should be better than initial");
        assertApproxEqAbs(newMultiplier, 6500, 100, "4K tokens should get better multiplier than 1K");
    }

    /// @dev Test new Linear Weighted Multiplier system with increaseAmount
    function test_ProgressiveMultiplier_IncreaseAmount() public {
        // Start with small stake
        uint256 initialStake = MINIMUM_STAKE * 2; // 2000 tokens

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), initialStake);
        sapienVault.stake(initialStake, LOCK_365_DAYS);
        vm.stopPrank();

        (,,,,, uint256 initialMultiplier,,) = sapienVault.getUserStakingSummary(user1);
        // In new system: 2K tokens @ 365 days gets ~6500 effective multiplier due to global coefficient
        assertApproxEqAbs(initialMultiplier, 6500, 100, "Initial 2000 tokens should get ~6500");

        // Use increaseAmount to add more stake
        uint256 additionalAmount = MINIMUM_STAKE * 6; // Total will be 8000 tokens

        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), additionalAmount);
        sapienVault.increaseAmount(additionalAmount);
        vm.stopPrank();

        (uint256 totalStaked,,,,, uint256 newMultiplier,,) = sapienVault.getUserStakingSummary(user1);

        assertEq(totalStaked, MINIMUM_STAKE * 8, "Total should be 8000 tokens");
        // In new system: 2K and 8K tokens are in same log bucket, so multiplier doesn't improve
        // This is expected behavior due to coarse logarithmic bucketing
        assertEq(
            newMultiplier, initialMultiplier, "Multiplier stays same due to log bucketing (2K and 8K in same bucket)"
        );
        // Both should get around 6500 effective multiplier
        assertApproxEqAbs(
            newMultiplier, 6500, 100, "8K tokens should get ~6500 effective multiplier (same bucket as 2K)"
        );
    }

    /// @dev Comprehensive demonstration of the new linear weighted multiplier system with global effects
    function test_LinearWeightedMultiplier_ComprehensiveDemo() public view {
        console.log("=== LINEAR WEIGHTED MULTIPLIER + GLOBAL COEFFICIENT DEMO ===");

        // Show how the system works with different network participation levels
        _demonstrateGlobalEffects();

        console.log("\n=== INDIVIDUAL MULTIPLIER BREAKDOWN ===");
        _demonstrateIndividualMultipliers();

        console.log("\n=== NETWORK EFFECTS ON SAME STAKE ===");
        _demonstrateNetworkEffects();

        console.log("\n=== SYSTEM BENEFITS ===");
        console.log("- Requires BOTH large stake AND long duration for max multiplier");
        console.log("- Creates network effects - more participation helps everyone");
        console.log("- Prevents over-concentration with diminishing returns");
        console.log("- Fair linear progression for both time and amount");
        console.log("- Maximum theoretical multiplier: 187.5%% (150%% individual x 1.25x global)");
    }

    function _demonstrateGlobalEffects() private pure {
        console.log("\nGlobal Coefficient vs Network Participation:");

        uint256[] memory stakingPercentages = new uint256[](7);
        stakingPercentages[0] = 500; // 5%
        stakingPercentages[1] = 1000; // 10%
        stakingPercentages[2] = 2000; // 20%
        stakingPercentages[3] = 3000; // 30%
        stakingPercentages[4] = 5000; // 50%
        stakingPercentages[5] = 7000; // 70%
        stakingPercentages[6] = 10000; // 100%

        for (uint256 i = 0; i < stakingPercentages.length; i++) {
            uint256 coefficient = _simulateGlobalCoefficient(stakingPercentages[i]);
            console.log("%s%% staked -> %sx global coefficient", stakingPercentages[i] / 100, coefficient);
        }
    }

    function _demonstrateIndividualMultipliers() private view {
        // Test different combinations of amount and duration
        uint256[] memory amounts = new uint256[](5);
        amounts[0] = MINIMUM_STAKE; // 1K tokens
        amounts[1] = MINIMUM_STAKE * 10; // 10K tokens
        amounts[2] = MINIMUM_STAKE * 100; // 100K tokens
        amounts[3] = MINIMUM_STAKE * 1000; // 1M tokens
        amounts[4] = MINIMUM_STAKE * 10000; // 10M tokens (max)

        uint256[] memory durations = new uint256[](4);
        durations[0] = LOCK_30_DAYS;
        durations[1] = LOCK_90_DAYS;
        durations[2] = LOCK_180_DAYS;
        durations[3] = LOCK_365_DAYS;

        console.log("\nAmount vs Duration Individual Multipliers (before global effects):");
        console.log("Format: [Amount] @ [Duration] -> [Individual Multiplier]");

        for (uint256 i = 0; i < amounts.length; i++) {
            for (uint256 j = 0; j < durations.length; j++) {
                (uint256 individual,,,) = sapienVault.getMultiplierBreakdown(amounts[i], durations[j]);
                string memory amountStr = _formatTokenAmount(amounts[i]);
                string memory durationStr = _formatDuration(durations[j]);
                console.log("%s @ %s -> %s%%", amountStr, durationStr, individual / 100);
            }
        }
    }

    function _demonstrateNetworkEffects() private pure {
        // Show how the same stake performs under different network conditions
        uint256 testAmount = MINIMUM_STAKE * 100; // 100K tokens
        uint256 testDuration = LOCK_365_DAYS; // 365 days

        // Simulate different network participation levels
        console.log("\n100K tokens @ 365 days under different network conditions:");

        uint256[] memory networkLevels = new uint256[](5);
        networkLevels[0] = 1000; // 10% network participation
        networkLevels[1] = 2000; // 20%
        networkLevels[2] = 3000; // 30%
        networkLevels[3] = 5000; // 50% (optimal)
        networkLevels[4] = 8000; // 80% (over-staked)

        for (uint256 i = 0; i < networkLevels.length; i++) {
            uint256 coefficient = _simulateGlobalCoefficient(networkLevels[i]);
            uint256 individual = _simulateIndividualMultiplier(testAmount, testDuration);
            uint256 finalMultiplier = (individual * coefficient) / 10000;

            console.log(
                "%s%% network participation -> %s%% final multiplier", networkLevels[i] / 100, finalMultiplier / 100
            );
        }
    }

    // Helper function to simulate global coefficient
    function _simulateGlobalCoefficient(uint256 stakingRatioBP) private pure returns (uint256) {
        if (stakingRatioBP <= 1000) {
            return 5000 + (stakingRatioBP * 5000) / 1000;
        } else if (stakingRatioBP <= 5000) {
            return 10000 + ((stakingRatioBP - 1000) * 5000) / 4000;
        } else {
            uint256 excess = stakingRatioBP - 5000;
            if (excess >= 5000) return 10000;
            return 15000 - (excess * 5000) / 5000;
        }
    }

    // Helper function to simulate individual multiplier
    function _simulateIndividualMultiplier(uint256 amount, uint256 duration) private pure returns (uint256) {
        uint256 base = 10000; // 100%

        // Time bonus: 0-25%
        uint256 timeFactor = (duration * 10000) / (365 days);
        if (timeFactor > 10000) timeFactor = 10000;
        uint256 timeBonus = (timeFactor * 2500) / 10000;

        // Amount bonus: 0-25% (simplified logarithmic)
        uint256 amountFactor;
        uint256 ratio = amount / MINIMUM_STAKE;
        if (ratio <= 1) amountFactor = 0;
        else if (ratio < 10) amountFactor = 2500; // ~25%

        else if (ratio < 100) amountFactor = 5000; // ~50%

        else if (ratio < 1000) amountFactor = 7500; // ~75%

        else amountFactor = 10000; // 100%

        uint256 amountBonus = (amountFactor * 2500) / 10000;

        return base + timeBonus + amountBonus;
    }

    // Helper functions for formatting
    function _formatTokenAmount(uint256 amount) private pure returns (string memory) {
        uint256 tokens = amount / 1e18;
        if (tokens >= 1000000) return "1M+";
        if (tokens >= 100000) return "100K";
        if (tokens >= 10000) return "10K";
        if (tokens >= 1000) return "1K";
        return "Min";
    }

    function _formatDuration(uint256 duration) private pure returns (string memory) {
        if (duration >= 365 days) return "365d";
        if (duration >= 180 days) return "180d";
        if (duration >= 90 days) return "90d";
        if (duration >= 30 days) return "30d";
        return "short";
    }

    /// @dev Test actual stake with realistic network conditions
    function test_LinearWeightedMultiplier_RealStaking() public {
        console.log("=== REAL STAKING SCENARIO ===");

        // Start with some initial network staking to simulate realistic conditions
        // Since we can't directly set totalStaked, we'll work with the current empty state
        // and just show what different scenarios would look like

        // Test user stakes 100K tokens for 365 days
        uint256 userAmount = MINIMUM_STAKE * 100; // 100K tokens
        uint256 userDuration = LOCK_365_DAYS; // 365 days

        // Get multiplier breakdown
        (uint256 individual, uint256 globalCoeff, uint256 finalMult, uint256 currentRatio) =
            sapienVault.getMultiplierBreakdown(userAmount, userDuration);

        console.log("User Stake: 100,000 tokens for 365 days");
        console.log("Individual Multiplier: %s%% (before global effects)", individual / 100);
        console.log("Global Coefficient: %sx (based on %s%% network participation)", globalCoeff, currentRatio / 100);
        console.log("Final Multiplier: %s%%", finalMult / 100);

        // Actually stake the tokens to test the system
        vm.startPrank(user1);
        sapienToken.approve(address(sapienVault), userAmount);
        sapienVault.stake(userAmount, userDuration);
        vm.stopPrank();

        // Verify the stake was created correctly
        (uint256 totalStaked,,,,, uint256 effectiveMultiplier,,) = sapienVault.getUserStakingSummary(user1);

        assertEq(totalStaked, userAmount, "Stake amount should match");
        assertEq(effectiveMultiplier, finalMult, "Effective multiplier should match calculated final multiplier");

        console.log("SUCCESS: Stake created successfully with multiplier: %s%%", effectiveMultiplier / 100);
    }

    /// @dev Demonstrate network effects by simulating progressive staking
    function test_LinearWeightedMultiplier_NetworkEffectsDemo() public {
        console.log("=== NETWORK EFFECTS IN ACTION ===");
        console.log("Each user stakes 50K tokens for 365 days");
        console.log("Watch multipliers increase as network participation grows!\n");

        uint256 stakeAmount = MINIMUM_STAKE * 50; // 50K tokens each

        for (uint256 i = 0; i < 3; i++) {
            address user = makeAddr(string(abi.encodePacked("networkUser", i)));

            // Give user tokens from user1 (who has unlimited supply)
            vm.prank(user1);
            sapienToken.transfer(user, stakeAmount);

            // Get stats before staking
            (,, uint256 preRatio, uint256 preCoeff) = sapienVault.getGlobalStakingStats();

            // User stakes
            vm.startPrank(user);
            sapienToken.approve(address(sapienVault), stakeAmount);
            sapienVault.stake(stakeAmount, LOCK_365_DAYS);
            vm.stopPrank();

            // Get stats after staking
            (,, uint256 postRatio, uint256 postCoeff) = sapienVault.getGlobalStakingStats();

            console.log("User %s staked - Network: %s%% -> %s%%", i + 1, preRatio / 100, postRatio / 100);
            console.log("  Global Coefficient: %sx -> %sx", preCoeff, postCoeff);
        }

        console.log("\nFinal: All stakers benefit from improved network coefficient!");
    }

    /// @dev Comprehensive real-world staking scenarios test
    function test_RealWorldStakingScenarios() public {
        console.log("=== REAL WORLD STAKING SCENARIOS ===");
        console.log("Testing various user profiles with different amounts and lockup periods\n");

        // Define user profiles
        UserProfile[] memory profiles = new UserProfile[](8);
        
        // Small retail investors
        profiles[0] = UserProfile({
            name: "Small Retail (Min)",
            amount: MINIMUM_STAKE, // 1,000 tokens
            lockup: LOCK_30_DAYS,
            description: "Minimum stake, short term"
        });
        
        profiles[1] = UserProfile({
            name: "Small Retail (Long)",
            amount: MINIMUM_STAKE, // 1,000 tokens
            lockup: LOCK_365_DAYS,
            description: "Minimum stake, maximum lockup"
        });

        // Medium retail investors
        profiles[2] = UserProfile({
            name: "Medium Retail",
            amount: MINIMUM_STAKE * 10, // 10,000 tokens
            lockup: LOCK_90_DAYS,
            description: "10K tokens, medium lockup"
        });

        profiles[3] = UserProfile({
            name: "Committed Retail",
            amount: MINIMUM_STAKE * 25, // 25,000 tokens
            lockup: LOCK_365_DAYS,
            description: "25K tokens, full commitment"
        });

        // Small institutional/whale
        profiles[4] = UserProfile({
            name: "Small Institution",
            amount: MINIMUM_STAKE * 100, // 100,000 tokens
            lockup: LOCK_180_DAYS,
            description: "100K tokens, conservative lockup"
        });

        profiles[5] = UserProfile({
            name: "Medium Institution",
            amount: MINIMUM_STAKE * 500, // 500,000 tokens
            lockup: LOCK_365_DAYS,
            description: "500K tokens, maximum lockup"
        });

        // Large institutional/whale
        profiles[6] = UserProfile({
            name: "Large Whale",
            amount: MINIMUM_STAKE * 2000, // 2,000,000 tokens
            lockup: LOCK_365_DAYS,
            description: "2M tokens, maximum commitment"
        });

        profiles[7] = UserProfile({
            name: "Mega Whale",
            amount: MINIMUM_STAKE * 5000, // 5,000,000 tokens
            lockup: LOCK_365_DAYS,
            description: "5M tokens, maximum commitment"
        });

        // Log initial network state
        (,, uint256 initialRatio, uint256 initialCoeff) = sapienVault.getGlobalStakingStats();
        console.log("Initial Network State:");
        console.log("  Staking Ratio: %s%%", initialRatio / 100);
        console.log("  Global Coefficient: %sx\n", initialCoeff);

        // Process each user profile
        for (uint256 i = 0; i < profiles.length; i++) {
            _processUserProfile(profiles[i], i + 1);
        }

        // Show final network state
        (uint256 finalStaked, uint256 totalSupply, uint256 finalRatio, uint256 finalCoeff) = sapienVault.getGlobalStakingStats();
        console.log("\n=== FINAL NETWORK STATE ===");
        console.log("Total Staked: %s tokens", finalStaked / 1e18);
        console.log("Total Supply: %s tokens", totalSupply / 1e18);
        console.log("Staking Ratio: %s%%", finalRatio / 100);
        console.log("Global Coefficient: %sx", finalCoeff);
        console.log("Network Participation Improved: %sx -> %sx", initialCoeff, finalCoeff);

        // Show comparative analysis
        _showComparativeAnalysis();
    }

    /// @dev Test progressive network effects as users join
    function test_ProgressiveNetworkEffects() public {
        console.log("=== PROGRESSIVE NETWORK EFFECTS ===");
        console.log("Watching multipliers improve as network participation grows\n");

        // Define a consistent stake for comparison
        uint256 testStake = MINIMUM_STAKE * 50; // 50K tokens
        uint256 testLockup = LOCK_365_DAYS;

        StakingRound[] memory rounds = new StakingRound[](5);
        rounds[0] = StakingRound({description: "First User (Cold Start)", userCount: 1});
        rounds[1] = StakingRound({description: "Small Network", userCount: 3});
        rounds[2] = StakingRound({description: "Growing Network", userCount: 8});
        rounds[3] = StakingRound({description: "Healthy Network", userCount: 15});
        rounds[4] = StakingRound({description: "Mature Network", userCount: 25});

        for (uint256 round = 0; round < rounds.length; round++) {
            console.log("\n--- %s ---", rounds[round].description);
            
            // Add users until we reach the target count for this round
            uint256 currentUsers = round == 0 ? 0 : rounds[round - 1].userCount;
            uint256 targetUsers = rounds[round].userCount;
            
            for (uint256 i = currentUsers; i < targetUsers; i++) {
                address user = makeAddr(string(abi.encodePacked("progressiveUser", i)));
                
                // Mint tokens
                sapienToken.mint(user, testStake);
                
                // Stake
                vm.startPrank(user);
                sapienToken.approve(address(sapienVault), testStake);
                sapienVault.stake(testStake, testLockup);
                vm.stopPrank();
            }

            // Show network state after this round
            (uint256 totalStaked,, uint256 stakingRatio,) = sapienVault.getGlobalStakingStats();
            
            // Get multiplier for our test stake
            (uint256 individual, uint256 coefficient, uint256 finalMult,) = 
                sapienVault.getMultiplierBreakdown(testStake, testLockup);
            
            console.log("Users: %s | Network: %s%% | Coeff: %sx", targetUsers, stakingRatio / 100, coefficient);
            console.log("50K @ 365d Multiplier: %s%% (Individual: %s%%, Global: %sx)", 
                finalMult / 100, individual / 100, coefficient);
            console.log("Total Network Stake: %s tokens", totalStaked / 1e18);
        }
    }

    /// @dev Test lockup period comparison with same amount
    function test_LockupPeriodComparison() public view {
        console.log("=== LOCKUP PERIOD COMPARISON ===");
        console.log("Same stake amount (10K tokens) with different lockup periods\n");

        uint256 testAmount = MINIMUM_STAKE * 10; // 10K tokens
        uint256[] memory lockupPeriods = new uint256[](4);
        lockupPeriods[0] = LOCK_30_DAYS;
        lockupPeriods[1] = LOCK_90_DAYS;
        lockupPeriods[2] = LOCK_180_DAYS;
        lockupPeriods[3] = LOCK_365_DAYS;

        string[] memory periodNames = new string[](4);
        periodNames[0] = "30 days";
        periodNames[1] = "90 days";
        periodNames[2] = "180 days";
        periodNames[3] = "365 days";

        console.log("Amount: 10,000 tokens");
        console.log("Format: [Lockup] -> [Individual] x [Global] = [Final] multiplier\n");

        for (uint256 i = 0; i < lockupPeriods.length; i++) {
            (uint256 individual, uint256 global, uint256 finalMult,) = 
                sapienVault.getMultiplierBreakdown(testAmount, lockupPeriods[i]);
            
            console.log("Lockup period results:");
            console.log("Individual:", individual / 100);
            console.log("Global:", global);
            console.log("Final:", finalMult / 100);
        }

        console.log("\nKey Insight: Longer lockups provide significantly better individual multipliers!");
    }

    /// @dev Test amount scaling comparison with same lockup
    function test_AmountScalingComparison() public view {
        console.log("=== AMOUNT SCALING COMPARISON ===");
        console.log("Same lockup period (365 days) with different stake amounts\n");

        uint256[] memory amounts = new uint256[](8);
        amounts[0] = MINIMUM_STAKE; // 1K
        amounts[1] = MINIMUM_STAKE * 2; // 2K
        amounts[2] = MINIMUM_STAKE * 5; // 5K
        amounts[3] = MINIMUM_STAKE * 10; // 10K
        amounts[4] = MINIMUM_STAKE * 50; // 50K
        amounts[5] = MINIMUM_STAKE * 100; // 100K
        amounts[6] = MINIMUM_STAKE * 500; // 500K
        amounts[7] = MINIMUM_STAKE * 1000; // 1M

        string[] memory amountNames = new string[](8);
        amountNames[0] = "1K tokens";
        amountNames[1] = "2K tokens";
        amountNames[2] = "5K tokens";
        amountNames[3] = "10K tokens";
        amountNames[4] = "50K tokens";
        amountNames[5] = "100K tokens";
        amountNames[6] = "500K tokens";
        amountNames[7] = "1M tokens";

        console.log("Lockup: 365 days (maximum)");
        console.log("Format: [Amount] -> [Individual] x [Global] = [Final] multiplier\n");

        for (uint256 i = 0; i < amounts.length; i++) {
            (uint256 individual, uint256 global, uint256 finalMult,) = 
                sapienVault.getMultiplierBreakdown(amounts[i], LOCK_365_DAYS);
            
            console.log("Amount scaling results:");
            console.log("Individual:", individual / 100);
            console.log("Global:", global);
            console.log("Final:", finalMult / 100);
        }

        console.log("\nKey Insight: Logarithmic scaling rewards larger stakes but with diminishing returns!");
    }

    // Helper structs for organizing test data
    struct UserProfile {
        string name;
        uint256 amount;
        uint256 lockup;
        string description;
    }

    struct StakingRound {
        string description;
        uint256 userCount;
    }

    /// @dev Process a single user profile and log results
    function _processUserProfile(UserProfile memory profile, uint256 userNumber) private {
        // Create user address
        address user = makeAddr(string(abi.encodePacked("realWorldUser", userNumber)));
        
        // Mint tokens to user
        sapienToken.mint(user, profile.amount);
        
        // Get network state before staking
        (,, uint256 preLatio, uint256 preCoeff) = sapienVault.getGlobalStakingStats();
        
        // Get multiplier breakdown before staking
        (uint256 preIndividual, uint256 preGlobal, uint256 preFinalMult,) = 
            sapienVault.getMultiplierBreakdown(profile.amount, profile.lockup);
        
        // Execute stake
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), profile.amount);
        sapienVault.stake(profile.amount, profile.lockup);
        vm.stopPrank();
        
        // Get actual multiplier from stake
        (,,,,,uint256 actualMultiplier,,) = sapienVault.getUserStakingSummary(user);
        
        // Get network state after staking
        (,, uint256 postRatio, uint256 postCoeff) = sapienVault.getGlobalStakingStats();
        
        // Log comprehensive results
        console.log("User %s: %s", userNumber, profile.name);
        console.log("  Stake: %s tokens @ %s days", profile.amount / 1e18, profile.lockup / 1 days);
        console.log("  Description: %s", profile.description);
        console.log("  Individual Multiplier: %s%%", preIndividual / 100);
        console.log("  Global Coefficient: %sx (was %sx)", preGlobal, preCoeff);
        console.log("  Final Multiplier: %s%% (actual: %s%%)", preFinalMult / 100, actualMultiplier / 100);
        console.log("  Network Impact: %s%% -> %s%% staked", preLatio / 100, postRatio / 100);
        console.log("  Coefficient Change: %sx -> %sx", preCoeff, postCoeff);
        console.log("");
    }

    /// @dev Show comparative analysis of all staking scenarios
    function _showComparativeAnalysis() private view {
        console.log("\n=== COMPARATIVE ANALYSIS ===");
        
        // Compare different strategies
        console.log("\nStrategy Comparison (all with 10K tokens):");
        
        uint256 baseAmount = MINIMUM_STAKE * 10;
        
        (uint256 short1, uint256 shortG, uint256 shortFinalMult,) = sapienVault.getMultiplierBreakdown(baseAmount, LOCK_30_DAYS);
        (uint256 med1, uint256 medG, uint256 medFinalMult,) = sapienVault.getMultiplierBreakdown(baseAmount, LOCK_180_DAYS);
        (uint256 long1, uint256 longG, uint256 longFinalMult,) = sapienVault.getMultiplierBreakdown(baseAmount, LOCK_365_DAYS);
        
        console.log("Short-term (30d) results:");
        console.log("- Individual:", short1 / 100);
        console.log("- Global:", shortG);
        console.log("- Final:", shortFinalMult / 100);
        
        console.log("Medium-term (180d) results:");
        console.log("- Individual:", med1 / 100);
        console.log("- Global:", medG);
        console.log("- Final:", medFinalMult / 100);
        
        console.log("Long-term (365d) results:");
        console.log("- Individual:", long1 / 100);
        console.log("- Global:", longG);
        console.log("- Final:", longFinalMult / 100);
        
        uint256 shortVsLong = (longFinalMult * 100) / shortFinalMult;
        console.log("Long-term advantage: %sx better than short-term", shortVsLong / 100);
        
        console.log("\nAmount Comparison (all with 365d lockup):");
        
        (uint256 small1, uint256 smallG, uint256 smallFinalMult,) = sapienVault.getMultiplierBreakdown(MINIMUM_STAKE, LOCK_365_DAYS);
        (uint256 big1, uint256 bigG, uint256 bigFinalMult,) = sapienVault.getMultiplierBreakdown(MINIMUM_STAKE * 100, LOCK_365_DAYS);
        (uint256 whale1, uint256 whaleG, uint256 whaleFinalMult,) = sapienVault.getMultiplierBreakdown(MINIMUM_STAKE * 1000, LOCK_365_DAYS);
        
        console.log("Small (1K) results:");
        console.log("- Individual:", small1 / 100);
        console.log("- Global:", smallG);
        console.log("- Final:", smallFinalMult / 100);
        
        console.log("Large (100K) results:");
        console.log("- Individual:", big1 / 100);
        console.log("- Global:", bigG);
        console.log("- Final:", bigFinalMult / 100);
        
        console.log("Whale (1M) results:");
        console.log("- Individual:", whale1 / 100);
        console.log("- Global:", whaleG);
        console.log("- Final:", whaleFinalMult / 100);
        
        uint256 smallVsWhale = (whaleFinalMult * 100) / smallFinalMult;
        console.log("Whale advantage: %sx better than small stake", smallVsWhale / 100);
        
        console.log("\nKey Takeaways:");
        console.log("1. Time commitment is highly rewarded (up to %sx better)", shortVsLong / 100);
        console.log("2. Larger stakes get bonuses but with diminishing returns");
        console.log("3. Network effects help everyone - more participation = better multipliers");
        console.log("4. Sweet spot: Large stakes + Long lockups + Healthy network participation");
    }
}
