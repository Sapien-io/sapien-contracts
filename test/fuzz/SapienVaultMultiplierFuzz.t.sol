// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {Vm} from "lib/forge-std/src/Vm.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienVault, ISapienVault} from "src/SapienVault.sol";
import {Multiplier} from "src/Multiplier.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {Constants as Const} from "src/utils/Constants.sol";
import {SafeCast} from "src/utils/SafeCast.sol";

/**
 * @title SapienVaultMultiplierFuzz
 * @notice Fuzzing tests for SapienVault multiplier storage and calculation
 * @dev Focuses on identifying storage corruption issues with effectiveMultiplier
 */
contract SapienVaultMultiplierFuzz is Test {
    SapienVault public sapienVault;
    MockERC20 public sapienToken;

    // Test constants
    address public admin = makeAddr("admin");
    address public treasury = makeAddr("treasury");
    address public pauseManager = makeAddr("pauseManager");
    address public sapienQA = makeAddr("sapienQA");

    uint256 public constant MINIMUM_STAKE = Const.MINIMUM_STAKE_AMOUNT; // Use constant from contracts
    uint256 public constant MAXIMUM_STAKE = Const.MAXIMUM_STAKE_AMOUNT; // Use constant from contracts

    // Lock periods
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    // Key test boundaries for the new multiplicative model (in tokens with 18 decimals)
    uint256 public constant LOW_AMOUNT = 250e18; // 250 tokens - low multiplier range
    uint256 public constant MID_AMOUNT = 1250e18; // 1250 tokens - mid multiplier range  
    uint256 public constant HIGH_AMOUNT = 2500e18; // 2500 tokens - maximum multiplier cap

    // Events for debugging
    event MultiplierMismatch(
        address indexed user,
        uint256 amount,
        uint256 period,
        uint256 expected,
        uint256 actual,
        string context
    );

    event StorageCorruption(
        address indexed user,
        uint256 amount,
        uint256 period,
        uint256 calculateResult,
        uint256 storedResult,
        uint256 retrievedResult
    );

    function setUp() public {
        // Deploy mock SAPIEN token
        sapienToken = new MockERC20("Sapien", "SAPIEN", 18);

        // Deploy SapienVault
        SapienVault sapienVaultImpl = new SapienVault();
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector, address(sapienToken), admin, pauseManager, treasury, sapienQA
        );
        ERC1967Proxy sapienVaultProxy = new ERC1967Proxy(address(sapienVaultImpl), initData);
        sapienVault = SapienVault(address(sapienVaultProxy));

        // Setup for new multiplicative model testing
    }

    // =============================================================================
    // BASIC MULTIPLIER CALCULATION FUZZING
    // =============================================================================

    /// @notice Fuzz test calculateMultiplier function across all valid ranges
    function testFuzz_CalculateMultiplier_AllTiers(uint256 amount, uint8 periodIndex) public view {
        // Bound amount to valid staking range
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE);
        
        // Map periodIndex to valid periods
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        
        // Calculate multiplier
        uint256 multiplier = sapienVault.calculateMultiplier(amount, period);
        
        // Verify basic properties
        assertGt(multiplier, 0, "Multiplier must be positive");
        assertGe(multiplier, 10000, "Multiplier must be at least 1.00x (10000 bp)");
        assertLe(multiplier, 15000, "Multiplier must not exceed 1.50x (15000 bp)");
        
        // Verify it fits in uint32 (storage type)
        assertLe(multiplier, type(uint32).max, "Multiplier must fit in uint32");
        
        // Test SafeCast doesn't revert
        uint32 castedMultiplier = SafeCast.toUint32(multiplier);
        assertEq(uint256(castedMultiplier), multiplier, "SafeCast should preserve value");
    }

    /// @notice Fuzz test that multiplier increases continuously with amount
    function testFuzz_MultiplierIncreasesWithinTier(uint256 baseAmount, uint256 increment, uint8 periodIndex) public view {
        // Use continuous range instead of discrete tiers
        baseAmount = bound(baseAmount, MINIMUM_STAKE, HIGH_AMOUNT - 500e18);
        increment = bound(increment, 1e18, 500e18); // Increment to test continuous scaling
        
        uint256 higherAmount = baseAmount + increment;
        if (higherAmount > MAXIMUM_STAKE) higherAmount = MAXIMUM_STAKE; // Stay within limits
        
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        
        uint256 baseMultiplier = sapienVault.calculateMultiplier(baseAmount, period);
        uint256 higherMultiplier = sapienVault.calculateMultiplier(higherAmount, period);
        
        // Higher amounts should always yield equal or higher multipliers (monotonic)
        assertLe(baseMultiplier, higherMultiplier, "Higher amounts should have equal or higher multipliers");
        
        // The difference should be reasonable for the amount increase
        uint256 diff = higherMultiplier - baseMultiplier;
        assertLe(diff, 1000, "Multiplier increase should be reasonable for the amount increase");
    }

    /// @notice Fuzz test that multiplier increases with lock period for same amount
    function testFuzz_MultiplierIncreasesWithPeriod(uint256 amount) public view {
        // Use meaningful amounts where the time effect is visible
        // For very small amounts in the multiplicative model, time has minimal effect
        amount = bound(amount, 100 * 1e18, MAXIMUM_STAKE); // Start from 100 tokens minimum
        
        uint256 mult30 = sapienVault.calculateMultiplier(amount, LOCK_30_DAYS);
        uint256 mult90 = sapienVault.calculateMultiplier(amount, LOCK_90_DAYS);
        uint256 mult180 = sapienVault.calculateMultiplier(amount, LOCK_180_DAYS);
        uint256 mult365 = sapienVault.calculateMultiplier(amount, LOCK_365_DAYS);
        
        // Multipliers should increase with longer periods (when amount is meaningful)
        assertGe(mult90, mult30, "90-day multiplier should be >= 30-day");
        assertGe(mult180, mult90, "180-day multiplier should be >= 90-day");
        assertGt(mult365, mult180, "365-day multiplier should exceed 180-day");
    }

    // =============================================================================
    // STORAGE CORRUPTION DETECTION FUZZING
    // =============================================================================

    /// @notice Fuzz test to detect storage corruption in effectiveMultiplier
    function testFuzz_StorageCorruption_EffectiveMultiplier(uint256 amount, uint8 periodIndex, uint256 timestamp) public {
        // Bound inputs
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE);
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        timestamp = bound(timestamp, 1000, type(uint32).max / 2); // Reasonable timestamp range
        
        // Ensure all parameters are within reasonable ranges
        if (amount < MINIMUM_STAKE || amount > MAXIMUM_STAKE) return;
        if (period < LOCK_30_DAYS || period > LOCK_365_DAYS) return;
        if (timestamp < 1000) return;
        
        // Set timestamp
        vm.warp(timestamp);
        
        // Create user and fund - use a simple incremental approach to avoid conflicts
        address user = address(33);
        
        // Ensure user doesn't already have a stake (defensive check)
        if (sapienVault.hasActiveStake(user)) return;
        
        sapienToken.mint(user, amount);
        
        // Calculate expected multiplier before staking
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(amount, period);
        if (expectedMultiplier == 0) return; // Skip if multiplier calculation fails
        
        // Record logs to capture Staked event
        vm.recordLogs();
        
        // Perform staking with better error handling
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        
        // Verify approval was successful
        if (sapienToken.allowance(user, address(sapienVault)) < amount) {
            vm.stopPrank();
            return;
        }
        
        // Attempt staking with try-catch to handle edge cases gracefully
        bool stakingSuccessful = false;
        try sapienVault.stake(amount, period) {
            stakingSuccessful = true;
        } catch {
            // If staking fails, skip the storage corruption test
            // This handles edge cases where specific parameter combinations
            // might cause legitimate reverts due to edge conditions
            vm.stopPrank();
            return;
        }
        
        vm.stopPrank();
        
        // Only proceed with storage corruption testing if staking was successful
        if (!stakingSuccessful) return;
        
        // Extract multiplier from Staked event
        // Vm.Log[] memory logs = vm.getRecordedLogs();
        // uint256 eventMultiplier = 0;
        // bool foundStakedEvent = false;
        
        // for (uint256 i = 0; i < logs.length; i++) {
        //     if (logs[i].topics[0] == keccak256("Staked(address,uint256,uint256,uint256)")) {
        //         foundStakedEvent = true;
        //         (, , uint256 eventEffectiveMultiplier, ) = 
        //             abi.decode(logs[i].data, (uint256, uint256, uint256, uint256));
        //         eventMultiplier = eventEffectiveMultiplier;
        //         break;
        //     }
        // }
        
        // // Skip if we didn't find the staked event - this shouldn't happen in normal cases
        // // but might occur in edge cases we want to handle gracefully
        // if (!foundStakedEvent) return;
        
        // Get stored multiplier from getUserStakingSummary
        ISapienVault.UserStakingSummary memory userStake = sapienVault.getUserStakingSummary(user);
        uint256 storedMultiplier = userStake.effectiveMultiplier;
        
        // Critical checks for storage corruption - these are the main goals of this test
        if (expectedMultiplier > 0 && storedMultiplier == 0) {
            emit StorageCorruption(user, amount, period, expectedMultiplier, 0, storedMultiplier);
            revert("STORAGE CORRUPTION: calculateMultiplier > 0 but stored multiplier is 0");
        }
        
        // Verify all values match - if they don't, this indicates a real issue
        if (storedMultiplier != expectedMultiplier) {
            emit StorageCorruption(user, amount, period, expectedMultiplier, 0, storedMultiplier);
            revert("MULTIPLIER MISMATCH: Stored does not match calculated");
        }
    }

    /// @notice Fuzz test multiple stakes to detect storage corruption in combination scenarios
    function testFuzz_StorageCorruption_MultipleStakes(
        uint256 amount1, uint8 period1Index,
        uint256 amount2, uint8 period2Index,
        uint256 timeBetween
    ) public {
        // Bound inputs
        amount1 = bound(amount1, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        amount2 = bound(amount2, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        timeBetween = bound(timeBetween, 1 days, 30 days);
        
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period1 = validPeriods[period1Index % 4];
        uint256 period2 = validPeriods[period2Index % 4];
        
        address user = makeAddr("multiStakeUser");
        sapienToken.mint(user, amount1 + amount2);
        
        // First stake
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount1);
        sapienVault.stake(amount1, period1);
        
        // Verify first stake
        ISapienVault.UserStakingSummary memory userStakeFirst = sapienVault.getUserStakingSummary(user);
        assertGt(userStakeFirst.effectiveMultiplier, 0, "First stake multiplier must be positive");
        
        // Wait and add second stake
        vm.warp(block.timestamp + timeBetween);
        sapienToken.approve(address(sapienVault), amount2);
        sapienVault.stake(amount2, period2);
        vm.stopPrank();
        
        // Verify combined stake maintains positive multiplier
        ISapienVault.UserStakingSummary memory userStakeFinal = sapienVault.getUserStakingSummary(user);
        
        assertEq(userStakeFinal.userTotalStaked, amount1 + amount2, "Total stake should be sum");
        assertGt(userStakeFinal.effectiveMultiplier, 0, "Final multiplier must be positive");
        
        // The effective multiplier should be reasonable (not corrupted)
        assertGe(userStakeFinal.effectiveMultiplier, 10000, "Final multiplier should be at least 1.00x");
        assertLe(userStakeFinal.effectiveMultiplier, 15000, "Final multiplier should not exceed 1.50x");
    }

    // =============================================================================
    // TIER BOUNDARY FUZZING
    // =============================================================================

    /// @notice Fuzz test around key amount boundaries to detect calculation issues
    function testFuzz_TierBoundaries_Consistency(uint256 offset) public view {
        // Test around key boundaries in the new model
        offset = bound(offset, 0, 100e18); // Small offset around boundaries
        
        uint256[3] memory boundaries = [LOW_AMOUNT, MID_AMOUNT, HIGH_AMOUNT];
        
        for (uint256 i = 0; i < boundaries.length; i++) {
            uint256 boundary = boundaries[i];
            
            // Test just below boundary
            if (boundary > offset && boundary - offset >= MINIMUM_STAKE) {
                uint256 belowAmount = boundary - offset;
                uint256 belowMultiplier = sapienVault.calculateMultiplier(belowAmount, LOCK_365_DAYS);
                assertGt(belowMultiplier, 0, "Below boundary multiplier must be positive");
            }
            
            // Test at boundary
            uint256 atMultiplier = sapienVault.calculateMultiplier(boundary, LOCK_365_DAYS);
            assertGt(atMultiplier, 0, "At boundary multiplier must be positive");
            
            // Test just above boundary
            if (boundary + offset <= MAXIMUM_STAKE) {
                uint256 aboveAmount = boundary + offset;
                uint256 aboveMultiplier = sapienVault.calculateMultiplier(aboveAmount, LOCK_365_DAYS);
                assertGt(aboveMultiplier, 0, "Above boundary multiplier must be positive");
                
                // Higher amounts should have higher or equal multiplier (continuous scaling)
                assertGe(aboveMultiplier, atMultiplier, "Higher amounts should have higher or equal multiplier");
            }
        }
    }

    /// @notice Fuzz test exact key boundary values for edge case detection
    function testFuzz_ExactTierBoundaries_EdgeCases(uint8 boundaryIndex, uint8 periodIndex) public {
        uint256[5] memory exactBoundaries = [
            MINIMUM_STAKE,  // 1e18
            LOW_AMOUNT,     // 250e18
            MID_AMOUNT,     // 1250e18
            HIGH_AMOUNT,    // 2500e18
            MAXIMUM_STAKE   // 10000e18
        ];
        
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        
        uint256 amount = exactBoundaries[boundaryIndex % 5];
        uint256 period = validPeriods[periodIndex % 4];
        
        // Test calculation
        uint256 multiplier = sapienVault.calculateMultiplier(amount, period);
        assertGt(multiplier, 0, "Boundary multiplier must be positive");
        
        // Test storage
        address user = makeAddr(string(abi.encodePacked("boundaryUser", vm.toString(boundaryIndex), vm.toString(periodIndex))));
        sapienToken.mint(user, amount);
        
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, period);
        vm.stopPrank();
        
        ISapienVault.UserStakingSummary memory userStakeBoundary = sapienVault.getUserStakingSummary(user);
        assertEq(userStakeBoundary.effectiveMultiplier, multiplier, "Stored multiplier should match calculated at boundary");
    }

    // =============================================================================
    // SAFECAST AND OVERFLOW FUZZING
    // =============================================================================

    /// @notice Fuzz test SafeCast operations with multiplier values
    function testFuzz_SafeCast_MultiplierValues(uint256 amount, uint8 periodIndex) public view {
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE);
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        
        uint256 multiplier = sapienVault.calculateMultiplier(amount, period);
        
        // Verify multiplier fits in uint32
        assertLe(multiplier, type(uint32).max, "Multiplier must fit in uint32 storage");
        
        // Test SafeCast operation
        uint32 castedMultiplier = SafeCast.toUint32(multiplier);
        assertEq(uint256(castedMultiplier), multiplier, "SafeCast must preserve multiplier value");
        
        // Test round-trip conversion
        uint256 backToUint256 = uint256(castedMultiplier);
        assertEq(backToUint256, multiplier, "Round-trip conversion must be lossless");
    }

    /// @notice Fuzz test near uint32 maximum to detect overflow issues
    function testFuzz_Uint32Overflow_Detection(uint256 testValue) public {
        // Skip if testValue is 0 to avoid any potential issues
        vm.assume(testValue > 0);
        
        // Test values near uint32.max - ensure we have a valid range
        uint256 maxUint32 = type(uint32).max; // 4,294,967,295
        
        // For very small values (much smaller than uint32.max), just test them directly
        if (testValue < maxUint32 / 1000) {
            // These small values should always fit in uint32
            uint32 casted = SafeCast.toUint32(testValue);
            assertEq(uint256(casted), testValue, "Valid small uint32 cast should preserve value");
            return;
        }
        
        // For larger values, test near uint32 boundaries
        uint256 lowerBound = maxUint32 >= 1000 ? maxUint32 - 1000 : 0;
        uint256 upperBound = maxUint32 + 1000;
        
        // Bound to the range near uint32.max
        testValue = bound(testValue, lowerBound, upperBound);
        
        if (testValue <= maxUint32) {
            // Should succeed
            uint32 casted = SafeCast.toUint32(testValue);
            assertEq(uint256(casted), testValue, "Valid uint32 cast should preserve value");
        } else {
            // Should revert
            vm.expectRevert();
            SafeCast.toUint32(testValue);
        }
    }

    // =============================================================================
    // TIMESTAMP AND WEIGHTED CALCULATION FUZZING
    // =============================================================================

    /// @notice Fuzz test weighted calculations with various timestamps
    function testFuzz_WeightedCalculations_Timestamps(
        uint256 amount1, uint256 amount2,
        uint256 timestamp1, uint256 timestamp2,
        uint8 period1Index, uint8 period2Index
    ) public {
        // Bound inputs
        amount1 = bound(amount1, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        amount2 = bound(amount2, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        timestamp1 = bound(timestamp1, 1000, 2**31 - 1);
        timestamp2 = bound(timestamp2, timestamp1 + 1, timestamp1 + 365 days);
        
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period1 = validPeriods[period1Index % 4];
        uint256 period2 = validPeriods[period2Index % 4];
        
        address user = makeAddr("weightedUser");
        sapienToken.mint(user, amount1 + amount2);
        
        // First stake at timestamp1
        vm.warp(timestamp1);
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount1);
        sapienVault.stake(amount1, period1);
        
        // Verify first stake storage
        ISapienVault.UserStakingSummary memory userStakeFirst = sapienVault.getUserStakingSummary(user);
        assertGt(userStakeFirst.effectiveMultiplier, 0, "First stake multiplier must be positive");
        
        // Second stake at timestamp2
        vm.warp(timestamp2);
        sapienToken.approve(address(sapienVault), amount2);
        sapienVault.stake(amount2, period2);
        vm.stopPrank();
        
        // Verify combined stake
        ISapienVault.UserStakingSummary memory userStakeFinal = sapienVault.getUserStakingSummary(user);
        
        assertEq(userStakeFinal.userTotalStaked, amount1 + amount2, "Total stake should be combined");
        assertGt(userStakeFinal.effectiveMultiplier, 0, "Final multiplier must be positive after weighted calculation");
        
        // Check for reasonable bounds
        assertGe(userStakeFinal.effectiveMultiplier, 10000, "Final multiplier should be at least minimum");
        assertLe(userStakeFinal.effectiveMultiplier, 15000, "Final multiplier should not exceed maximum");
    }

    // =============================================================================
    // COMPREHENSIVE MATRIX VALIDATION FUZZING
    // =============================================================================

    /// @notice Fuzz test to validate multiplicative model behavior
    function testFuzz_MultiplierMatrix_Validation(uint256 amount, uint8 periodIndex) public view {
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE);
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        
        uint256 actualMultiplier = sapienVault.calculateMultiplier(amount, period);
        
        // Validate the new multiplicative model properties
        assertGe(actualMultiplier, 10000, "Should be at least minimum multiplier (1.00x)");
        assertLe(actualMultiplier, 15000, "Should not exceed maximum multiplier (1.50x)");
        
        // Test key edge cases for the multiplicative model
        if (amount == MINIMUM_STAKE && period == LOCK_30_DAYS) {
            // Minimum amount + minimum time should produce minimum multiplier
            assertEq(actualMultiplier, 10000, "Min amount + min time should equal base multiplier");
        }
        
        if (amount >= 2500 * 1e18 && period == LOCK_365_DAYS) {
            // Maximum amount + maximum time should produce maximum multiplier
            assertEq(actualMultiplier, 15000, "Max amount + max time should equal max multiplier");
        }
        
        // Verify continuous scaling property
        if (amount < 2500 * 1e18) {
            uint256 higherAmountMultiplier = sapienVault.calculateMultiplier(amount + 100 * 1e18, period);
            assertGe(higherAmountMultiplier, actualMultiplier, "Higher amount should have equal or higher multiplier");
        }
    }

    // =============================================================================
    // STORAGE CONSISTENCY FUZZING
    // =============================================================================

    /// @notice Fuzz test storage consistency across operations
    function testFuzz_StorageConsistency_Operations(
        uint256 stakeAmount,
        uint256 increaseAmount,
        uint256 timeDelay,
        uint8 stakePeriodIndex,
        uint8 operationType
    ) public {
        // Bound inputs
        stakeAmount = bound(stakeAmount, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        increaseAmount = bound(increaseAmount, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        timeDelay = bound(timeDelay, 1 hours, 30 days);
        
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 stakePeriod = validPeriods[stakePeriodIndex % 4];
        
        address user = makeAddr("consistencyUser");
        sapienToken.mint(user, stakeAmount + increaseAmount);
        
        // Initial stake
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), stakeAmount);
        sapienVault.stake(stakeAmount, stakePeriod);
        
        // Verify initial storage
        ISapienVault.UserStakingSummary memory userStakeInitial = sapienVault.getUserStakingSummary(user);
        assertGt(userStakeInitial.effectiveMultiplier, 0, "Initial multiplier must be positive");
        
        // Wait and perform operation based on operationType
        vm.warp(block.timestamp + timeDelay);
        
        uint8 opType = operationType % 3;
        if (opType == 0) {
            // Increase amount
            sapienToken.approve(address(sapienVault), increaseAmount);
            sapienVault.increaseAmount(increaseAmount);
        } else if (opType == 1) {
            // Increase lockup
            uint256 additionalLockup = bound(timeDelay, 30 days, 90 days);
            sapienVault.increaseLockup(additionalLockup);
        } else {
            // Add new stake
            sapienToken.approve(address(sapienVault), increaseAmount);
            sapienVault.stake(increaseAmount, stakePeriod);
        }
        vm.stopPrank();
        
        // Verify storage consistency after operation
        ISapienVault.UserStakingSummary memory userStakeAfterOp = sapienVault.getUserStakingSummary(user);
        
        // For increaseLockup (opType == 1), total stake doesn't increase - only lockup period extends
        if (opType == 1) {
            // increaseLockup operation - total stake should remain the same
            assertEq(userStakeAfterOp.userTotalStaked, stakeAmount, "Total stake should remain same for lockup increase");
        } else {
            // increaseAmount (opType == 0) or additional stake (opType == 2) - total stake should increase
            assertGt(userStakeAfterOp.userTotalStaked, stakeAmount, "Total stake should increase");
        }
        
        assertGt(userStakeAfterOp.effectiveMultiplier, 0, "Final multiplier must remain positive");
        assertGe(userStakeAfterOp.effectiveMultiplier, 10000, "Final multiplier should be at least minimum");
        assertLe(userStakeAfterOp.effectiveMultiplier, 15000, "Final multiplier should not exceed maximum");
    }

    // =============================================================================
    // HELPER FUNCTIONS FOR DEBUGGING
    // =============================================================================

    /// @notice Debug function to log multiplier details
    function _logMultiplierDetails(
        address user,
        uint256 amount,
        uint256 period,
        uint256 calculated,
        uint256 stored,
        string memory context
    ) internal {
        if (calculated != stored) {
            emit MultiplierMismatch(user, amount, period, calculated, stored, context);
            console.log("=== MULTIPLIER MISMATCH ===");
            console.log("User:", user);
            console.log("Amount:", amount);
            console.log("Period:", period);
            console.log("Calculated:", calculated);
            console.log("Stored:", stored);
            console.log("Context:", context);
        }
    }

    /// @notice Test individual storage corruption scenario
    function testFuzz_Specific_StorageCorruption(uint256 seed) public {
        // Use seed to generate reproducible "random" values for debugging
        uint256 amount = (seed % (MAXIMUM_STAKE - MINIMUM_STAKE)) + MINIMUM_STAKE;
        uint256 period = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS][seed % 4];
        uint256 timestamp = (seed % 1000000) + 1000;
        
        vm.warp(timestamp);
        
        address user = makeAddr(string(abi.encodePacked("seedUser", vm.toString(seed))));
        sapienToken.mint(user, amount);
        
        // Calculate expected
        uint256 expected = sapienVault.calculateMultiplier(amount, period);
        
        // Stake
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, period);
        vm.stopPrank();
        
        // Check storage
        ISapienVault.UserStakingSummary memory userStakeStored = sapienVault.getUserStakingSummary(user);
        uint256 stored = userStakeStored.effectiveMultiplier;
        
        _logMultiplierDetails(user, amount, period, expected, stored, "Fuzz specific corruption test");
        
        assertEq(stored, expected, "Storage should match calculation");
        assertGt(stored, 0, "Stored multiplier must be positive");
    }

    // =============================================================================
    // ADVANCED STORAGE SLOT CORRUPTION FUZZING
    // =============================================================================

    /// @notice Fuzz test for storage slot corruption with user address variations
    /// @dev This test specifically targets the issue where different user addresses
    ///      might cause storage corruption in the effectiveMultiplier field
    function testFuzz_UserAddressStorageCorruption(uint256 addressSeed, uint256 amount, uint8 periodIndex) public {
        // Bound inputs
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE);
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        
        // Generate different user address patterns to test storage corruption
        address[5] memory userPatterns = [
            makeAddr(string(abi.encodePacked("user", vm.toString(addressSeed)))),
            makeAddr(string(abi.encodePacked("fuzzUser", vm.toString(addressSeed)))),
            makeAddr(string(abi.encodePacked("testUser", vm.toString(addressSeed % 1000)))),
            makeAddr(string(abi.encodePacked("u", vm.toString(addressSeed)))),
            address(uint160(uint256(keccak256(abi.encodePacked(addressSeed)))))
        ];
        
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(amount, period);
        assertGt(expectedMultiplier, 0, "Expected multiplier must be positive");
        
        // Test each user pattern
        for (uint256 i = 0; i < userPatterns.length; i++) {
            address user = userPatterns[i];
            
            // Skip if user somehow already has a stake (very unlikely but defensive)
            if (sapienVault.hasActiveStake(user)) continue;
            
            sapienToken.mint(user, amount);
            
            vm.startPrank(user);
            sapienToken.approve(address(sapienVault), amount);
            sapienVault.stake(amount, period);
            vm.stopPrank();
            
            // Check for storage corruption
            ISapienVault.UserStakingSummary memory userStakeStorage = sapienVault.getUserStakingSummary(user);
            uint256 storedMultiplier = userStakeStorage.effectiveMultiplier;
            
            if (storedMultiplier == 0) {
                emit StorageCorruption(user, amount, period, expectedMultiplier, 0, storedMultiplier);
                revert(string(abi.encodePacked("STORAGE CORRUPTION: User pattern ", vm.toString(i), " caused zero multiplier")));
            }
            
            assertEq(storedMultiplier, expectedMultiplier, string(abi.encodePacked("Pattern ", vm.toString(i), " multiplier mismatch")));
        }
    }

    /// @notice Fuzz test for storage corruption during struct field reassignment
    /// @dev Tests the specific scenario where effectiveMultiplier gets corrupted during storage operations
    function testFuzz_StructFieldReassignmentCorruption(
        uint256 amount1, uint256 amount2,
        uint8 period1Index, uint8 period2Index,
        uint256 timeBetween,
        uint256 userSeed
    ) public {
        // Bound inputs
        amount1 = bound(amount1, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        amount2 = bound(amount2, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        timeBetween = bound(timeBetween, 1 hours, 90 days);
        
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period1 = validPeriods[period1Index % 4];
        uint256 period2 = validPeriods[period2Index % 4];
        
        address user = makeAddr(string(abi.encodePacked("structUser", vm.toString(userSeed))));
        sapienToken.mint(user, amount1 + amount2);
        
        // First stake - record expected multiplier
        uint256 expectedMultiplier1 = sapienVault.calculateMultiplier(amount1, period1);
        
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount1);
        sapienVault.stake(amount1, period1);
        vm.stopPrank();
        
        // Verify first stake didn't corrupt
        ISapienVault.UserStakingSummary memory userStakeFirst = sapienVault.getUserStakingSummary(user);
        if (userStakeFirst.effectiveMultiplier == 0) {
            emit StorageCorruption(user, amount1, period1, expectedMultiplier1, 0, userStakeFirst.effectiveMultiplier);
            revert("STORAGE CORRUPTION: First stake resulted in zero multiplier");
        }
        assertEq(userStakeFirst.effectiveMultiplier, expectedMultiplier1, "First stake multiplier should match");
        
        // Wait and perform second operation that modifies the UserStake struct
        vm.warp(block.timestamp + timeBetween);
        
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount2);
        
        // This will trigger _combineStakes which modifies all UserStake fields
        sapienVault.stake(amount2, period2);
        vm.stopPrank();
        
        // Check for corruption after struct modification
        ISapienVault.UserStakingSummary memory userStakeFinal = sapienVault.getUserStakingSummary(user);
        
        uint256 expectedTotal = amount1 + amount2;
        assertEq(userStakeFinal.userTotalStaked, expectedTotal, "Total stake should combine correctly");
        
                    if (userStakeFinal.effectiveMultiplier == 0) {
                emit StorageCorruption(user, expectedTotal, period2, expectedMultiplier1, 0, userStakeFinal.effectiveMultiplier);
                revert("STORAGE CORRUPTION: Combined stake resulted in zero multiplier");
            }
        
        assertGt(userStakeFinal.effectiveMultiplier, 0, "Final multiplier must be positive after struct modification");
        assertGe(userStakeFinal.effectiveMultiplier, 10000, "Final multiplier should be at least minimum");
        assertLe(userStakeFinal.effectiveMultiplier, 15000, "Final multiplier should not exceed maximum");
    }

    /// @notice Fuzz test for SafeCast corruption in different contexts
    /// @dev Tests whether SafeCast.toUint32 behaves differently in different execution contexts
    function testFuzz_SafeCastContextCorruption(uint256 amount, uint8 periodIndex, uint256 timestamp, uint256 blockNumber) public {
        // Bound inputs
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE);
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        timestamp = bound(timestamp, 1000, type(uint32).max); // Use uint32 max for timestamp
        blockNumber = bound(blockNumber, 1, type(uint32).max);
        
        // Set different execution contexts
        vm.warp(timestamp);
        vm.roll(blockNumber);
        
        address user = makeAddr(string(abi.encodePacked("contextUser", vm.toString(timestamp), vm.toString(blockNumber))));
        sapienToken.mint(user, amount);
        
        // Calculate multiplier in this context
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(amount, period);
        assertGt(expectedMultiplier, 0, "Expected multiplier must be positive");
        
        // Test SafeCast in isolation
        uint32 directCast = SafeCast.toUint32(expectedMultiplier);
        assertEq(uint256(directCast), expectedMultiplier, "Direct SafeCast should work");
        
        // Perform staking which uses SafeCast internally
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, period);
        vm.stopPrank();
        
        // Check if context affected SafeCast behavior
        ISapienVault.UserStakingSummary memory contextStake = sapienVault.getUserStakingSummary(user);
        uint256 storedMultiplier = contextStake.effectiveMultiplier;
        
        if (storedMultiplier != expectedMultiplier) {
            emit StorageCorruption(user, amount, period, expectedMultiplier, uint256(directCast), storedMultiplier);
            console.log("Context corruption detected:");
            console.log("  Timestamp:", timestamp);
            console.log("  Block number:", blockNumber);
            console.log("  Expected:", expectedMultiplier);
            console.log("  Direct cast:", uint256(directCast));
            console.log("  Stored:", storedMultiplier);
            revert("CONTEXT CORRUPTION: SafeCast behaved differently in context");
        }
        
        assertEq(storedMultiplier, expectedMultiplier, "Stored multiplier should match in any context");
    }

    /// @notice Fuzz test for memory corruption during complex operations
    /// @dev Tests whether memory layout affects storage operations
    function testFuzz_MemoryLayoutCorruption(
        uint256 amount,
        uint8 periodIndex,
        uint256 memoryPadding,
        bool useIncreaseAmount
    ) public {
        // Bound inputs - ensure amount is at least 2x MINIMUM_STAKE so amount/2 is valid
        amount = bound(amount, MINIMUM_STAKE * 2, MAXIMUM_STAKE / 2);
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        
        // Create memory padding to potentially affect memory layout
        bytes memory padding = new bytes(memoryPadding % 1000);
        for (uint256 i = 0; i < padding.length; i++) {
            padding[i] = bytes1(uint8(i % 256));
        }
        
        address user = makeAddr(string(abi.encodePacked("memoryUser", vm.toString(memoryPadding))));
        sapienToken.mint(user, amount * 2);
        
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(amount, period);
        assertGt(expectedMultiplier, 0, "Expected multiplier must be positive");
        
        // Use the padding to ensure it's not optimized away
        uint256 paddingHash = uint256(keccak256(padding));
        
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount * 2);
        
        if (useIncreaseAmount) {
            // First stake then increase (more complex memory operations)
            // amount / 2 is now guaranteed to be >= MINIMUM_STAKE
            sapienVault.stake(amount / 2, period);
            
            // Verify intermediate state
            ISapienVault.UserStakingSummary memory intermediateStake = sapienVault.getUserStakingSummary(user);
            uint256 intermediateMultiplier = intermediateStake.effectiveMultiplier;
            assertGt(intermediateMultiplier, 0, "Intermediate multiplier must be positive");
            
            // Use paddingHash to ensure memory layout is affected
            if (paddingHash % 2 == 0) {
                vm.warp(block.timestamp + 1);
            }
            
            sapienVault.increaseAmount(amount - (amount / 2));
        } else {
            // Single stake operation
            if (paddingHash % 2 == 0) {
                vm.warp(block.timestamp + 1);
            }
            sapienVault.stake(amount, period);
        }
        vm.stopPrank();
        
        // Check final state
        ISapienVault.UserStakingSummary memory finalStake = sapienVault.getUserStakingSummary(user);
        uint256 totalStaked = finalStake.userTotalStaked;
        uint256 finalMultiplier = finalStake.effectiveMultiplier;
        
        assertEq(totalStaked, amount, "Total stake should match");
        
        if (finalMultiplier == 0) {
            emit StorageCorruption(user, amount, period, expectedMultiplier, paddingHash, finalMultiplier);
            revert("MEMORY CORRUPTION: Memory layout affected storage");
        }
        
        assertGt(finalMultiplier, 0, "Final multiplier must be positive despite memory layout");
    }

    /// @notice Fuzz test for storage corruption with extreme timestamp values
    /// @dev Tests whether very large timestamps cause calculation or storage issues
    function testFuzz_ExtremeTimestampCorruption(uint256 amount, uint8 periodIndex, uint256 extremeTimestamp) public {
        // Bound inputs
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE);
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        
        // Test extreme timestamp values that might cause overflow in weighted calculations
        extremeTimestamp = bound(extremeTimestamp, type(uint32).max / 2, type(uint32).max - 1);
        
        vm.warp(extremeTimestamp);
        
        address user = makeAddr(string(abi.encodePacked("extremeUser", vm.toString(extremeTimestamp))));
        sapienToken.mint(user, amount);
        
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(amount, period);
        assertGt(expectedMultiplier, 0, "Expected multiplier must be positive");
        
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, period);
        vm.stopPrank();
        
        // Check for corruption with extreme timestamps
        ISapienVault.UserStakingSummary memory extremeStake = sapienVault.getUserStakingSummary(user);
        uint256 storedMultiplier = extremeStake.effectiveMultiplier;
        
        if (storedMultiplier == 0) {
            emit StorageCorruption(user, amount, period, expectedMultiplier, extremeTimestamp, storedMultiplier);
            console.log("Extreme timestamp corruption:");
            console.log("  Timestamp:", extremeTimestamp);
            console.log("  Expected multiplier:", expectedMultiplier);
            console.log("  Stored multiplier:", storedMultiplier);
            revert("EXTREME TIMESTAMP CORRUPTION: Large timestamp caused zero multiplier");
        }
        
        assertEq(storedMultiplier, expectedMultiplier, "Extreme timestamps should not corrupt storage");
    }

    /// @notice Fuzz test for gas-related storage corruption
    /// @dev Tests whether different gas limits affect storage operations
    function testFuzz_GasLimitCorruption(uint256 amount, uint8 periodIndex, uint256 gasLimit) public {
        // Bound inputs
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE);
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        gasLimit = bound(gasLimit, 1_000_000, 30_000_000); // Reasonable gas range
        
        address user = makeAddr(string(abi.encodePacked("gasUser", vm.toString(gasLimit))));
        sapienToken.mint(user, amount);
        
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(amount, period);
        assertGt(expectedMultiplier, 0, "Expected multiplier must be positive");
        
        // Set gas limit for the transaction
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        
        // Perform stake with specific gas limit
        (bool success,) = address(sapienVault).call{gas: gasLimit}(
            abi.encodeWithSignature("stake(uint256,uint256)", amount, period)
        );
        
        if (!success) {
            // If gas limit too low, skip this test iteration
            vm.stopPrank();
            return;
        }
        
        vm.stopPrank();
        
        // Check for gas-related corruption
        ISapienVault.UserStakingSummary memory gasStake = sapienVault.getUserStakingSummary(user);
        uint256 storedMultiplier = gasStake.effectiveMultiplier;
        
        if (storedMultiplier == 0) {
            emit StorageCorruption(user, amount, period, expectedMultiplier, gasLimit, storedMultiplier);
            revert("GAS CORRUPTION: Gas limit affected storage");
        }
        
        assertEq(storedMultiplier, expectedMultiplier, "Gas limits should not affect storage");
    }

    /// @notice Fuzz test for storage slot collision detection
    /// @dev Tests whether multiple users with similar addresses cause storage collisions
    function testFuzz_StorageSlotCollision(uint256 baseSeed, uint256 amount, uint8 periodIndex) public {
        // Bound inputs
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE / 10); // Smaller amounts for multiple users
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];
        
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(amount, period);
        assertGt(expectedMultiplier, 0, "Expected multiplier must be positive");
        
        // Create multiple users with potentially colliding addresses
        address[10] memory users;
        for (uint256 i = 0; i < 10; i++) {
            // Prevent arithmetic overflow by using modulo operation with a reasonable bound
            uint256 safeSeed = (baseSeed % (type(uint256).max / 100)) + i;
            users[i] = makeAddr(string(abi.encodePacked("collision", vm.toString(safeSeed))));
            sapienToken.mint(users[i], amount);
        }
        
        // Stake with all users
        for (uint256 i = 0; i < 10; i++) {
            vm.startPrank(users[i]);
            sapienToken.approve(address(sapienVault), amount);
            sapienVault.stake(amount, period);
            vm.stopPrank();
        }
        
        // Verify all users have correct multipliers (no collision)
        for (uint256 i = 0; i < 10; i++) {
            ISapienVault.UserStakingSummary memory userCollisionStake = sapienVault.getUserStakingSummary(users[i]);
            uint256 storedMultiplier = userCollisionStake.effectiveMultiplier;
            
            if (storedMultiplier == 0) {
                emit StorageCorruption(users[i], amount, period, expectedMultiplier, i, storedMultiplier);
                revert(string(abi.encodePacked("STORAGE COLLISION: User ", vm.toString(i), " has zero multiplier")));
            }
            
            assertEq(storedMultiplier, expectedMultiplier, string(abi.encodePacked("User ", vm.toString(i), " multiplier mismatch")));
        }
    }

    /// @notice Comprehensive stress test for storage corruption
    /// @dev Combines multiple potential corruption vectors in a single test
    function testFuzz_ComprehensiveStorageStress(
        uint256 amount1, uint256 amount2,
        uint8 period1Index, uint8 period2Index,
        uint256 timestamp1, uint256 timestamp2,
        uint256 userSeed
    ) public {
        // Bound all inputs
        amount1 = bound(amount1, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        amount2 = bound(amount2, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period1 = validPeriods[period1Index % 4];
        uint256 period2 = validPeriods[period2Index % 4];
        
        timestamp1 = bound(timestamp1, 1000, type(uint32).max / 2);
        timestamp2 = bound(timestamp2, timestamp1 + 1, timestamp1 + 180 days);
        
        address user = makeAddr(string(abi.encodePacked("stressUser", vm.toString(userSeed))));
        uint256 totalAmount = amount1 + amount2;
        sapienToken.mint(user, totalAmount);
        
        // Complex sequence of operations with different timestamps
        vm.warp(timestamp1);
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount1);
        sapienVault.stake(amount1, period1);
        
        ISapienVault.UserStakingSummary memory stressStake1 = sapienVault.getUserStakingSummary(user);
        uint256 multiplier1 = stressStake1.effectiveMultiplier;
        assertGt(multiplier1, 0, "First multiplier must be positive");
        
        vm.warp(timestamp2);
        sapienToken.approve(address(sapienVault), amount2);
        sapienVault.stake(amount2, period2);
        vm.stopPrank();
        
        // Final comprehensive check
        ISapienVault.UserStakingSummary memory finalStressStake = sapienVault.getUserStakingSummary(user);
        uint256 totalStaked = finalStressStake.userTotalStaked;
        uint256 finalMultiplier = finalStressStake.effectiveMultiplier;
        
        assertEq(totalStaked, totalAmount, "Total stake should be sum of all amounts");
        
        if (finalMultiplier == 0) {
            emit StorageCorruption(user, totalStaked, period2, multiplier1, userSeed, finalMultiplier);
            revert("COMPREHENSIVE STRESS: Final multiplier is zero after complex operations");
        }
        
        assertGt(finalMultiplier, 0, "Final multiplier must be positive after stress test");
        assertGe(finalMultiplier, 10000, "Final multiplier should be at least minimum");
        assertLe(finalMultiplier, 15000, "Final multiplier should not exceed maximum");
    }

    // =============================================================================
    // FOCUSED DEBUGGING FOR SPECIFIC FAILURE CASES
    // =============================================================================

    /// @notice Focused test to debug the specific failing case found by fuzzer
    /// @dev Tests the exact parameters that caused multiplier to become 0
    function test_DebugSpecificFailingCase() public {
        // Exact failing parameters from fuzzer:
        // args=[12427, 12436, 62, 128, 17266, 11699, 9537]
        uint256 amount1 = 12427e18;  // 12,427 tokens
        uint256 amount2 = 12436e18;  // 12,436 tokens  
        uint8 period1Index = 62;     // Maps to validPeriods[62 % 4] = validPeriods[2] = LOCK_180_DAYS
        uint8 period2Index = 128;    // Maps to validPeriods[128 % 4] = validPeriods[0] = LOCK_30_DAYS
        uint256 timestamp1 = 17266;  // Initial timestamp
        uint256 timestamp2 = 11699;  // Second timestamp (this is less than timestamp1!)
        uint256 userSeed = 9537;     // User seed
        
        // Bound all inputs as in the original test
        amount1 = bound(amount1, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        amount2 = bound(amount2, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period1 = validPeriods[period1Index % 4];  // LOCK_180_DAYS
        uint256 period2 = validPeriods[period2Index % 4];  // LOCK_30_DAYS
        
        timestamp1 = bound(timestamp1, 1000, type(uint32).max / 2);
        timestamp2 = bound(timestamp2, timestamp1 + 1, timestamp1 + 180 days);
        
        address user = makeAddr(string(abi.encodePacked("stressUser", vm.toString(userSeed))));
        uint256 totalAmount = amount1 + amount2;
        sapienToken.mint(user, totalAmount);
        
        console.log("=== DEBUGGING SPECIFIC FAILING CASE ===");
        console.log("amount1:", amount1);
        console.log("amount2:", amount2);
        console.log("period1 days:", period1 / 1 days);
        console.log("period2 days:", period2 / 1 days);
        console.log("timestamp1:", timestamp1);
        console.log("timestamp2:", timestamp2);
        
        // Test calculateMultiplier for both individual amounts
        uint256 expectedMultiplier1 = sapienVault.calculateMultiplier(amount1, period1);
        uint256 expectedMultiplier2 = sapienVault.calculateMultiplier(amount2, period2);
        uint256 expectedMultiplierCombined = sapienVault.calculateMultiplier(totalAmount, period2); // Final period
        
        console.log("Expected multiplier1:", expectedMultiplier1);
        console.log("Expected multiplier2:", expectedMultiplier2);
        console.log("Expected combined:", expectedMultiplierCombined);
        
        assertGt(expectedMultiplier1, 0, "Expected multiplier 1 must be positive");
        assertGt(expectedMultiplier2, 0, "Expected multiplier 2 must be positive");
        assertGt(expectedMultiplierCombined, 0, "Expected combined multiplier must be positive");
        
        // Complex sequence of operations with different timestamps (EXACT replication)
        vm.warp(timestamp1);
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount1);
        sapienVault.stake(amount1, period1);
        
        ISapienVault.UserStakingSummary memory debugStake1 = sapienVault.getUserStakingSummary(user);
        uint256 multiplier1 = debugStake1.effectiveMultiplier;
        console.log("After first stake:");
        console.log("stored multiplier1:", multiplier1);
        console.log("expected:", expectedMultiplier1);
        
        if (multiplier1 == 0) {
            console.log("FOUND IT: First multiplier is already 0!");
            console.log("Issue is in initial stake, not combination");
            revert("First stake already produces zero multiplier");
        }
        
        assertGt(multiplier1, 0, "First multiplier must be positive");
        
        vm.warp(timestamp2);
        sapienToken.approve(address(sapienVault), amount2);
        sapienVault.stake(amount2, period2);
        vm.stopPrank();
        
        // Final comprehensive check
        ISapienVault.UserStakingSummary memory debugFinalStake = sapienVault.getUserStakingSummary(user);
        uint256 totalStaked = debugFinalStake.userTotalStaked;
        uint256 finalMultiplier = debugFinalStake.effectiveMultiplier;
        
        console.log("After second stake:");
        console.log("totalStaked:", totalStaked);
        console.log("finalMultiplier:", finalMultiplier);
        console.log("expected combined:", expectedMultiplierCombined);
        
        if (finalMultiplier == 0) {
            console.log("CORRUPTION DETECTED in stake combination!");
            console.log("First multiplier was:", multiplier1);
            console.log("Final multiplier is 0");
            console.log("Corruption during stake combination");
            
            // Let's test the individual components again
            uint256 retestMultiplier1 = sapienVault.calculateMultiplier(amount1, period1);
            uint256 retestMultiplier2 = sapienVault.calculateMultiplier(amount2, period2);
            console.log("Retest amount1:", retestMultiplier1);
            console.log("Retest amount2:", retestMultiplier2);
            
            revert("CORRUPTION: Final multiplier became zero during combination");
        }
        
        assertEq(totalStaked, totalAmount, "Total stake should be sum of all amounts");
        assertGt(finalMultiplier, 0, "Final multiplier must be positive after stress test");
        assertGe(finalMultiplier, 10000, "Final multiplier should be at least minimum");
        assertLe(finalMultiplier, 15000, "Final multiplier should not exceed maximum");
    }


    /// @notice Reproduces the exact failing case found by the fuzzer
    function test_ReproduceExactFailingCase() public {
        // From the failing fuzzer output:
        // args=[12427, 12436, 62, 128, 17266, 11699, 9537]
        // "First multiplier is already 0!" - corruption in first stake
        
        uint256 amount = 12427e18;  // 12,427 tokens
        uint256 period = LOCK_180_DAYS;  // period1 from index 62 % 4 = 2
        uint256 timestamp = 17266;  // After bounding becomes 15563699
        uint256 userSeed = 9537;
        
        // Bound exactly as the fuzzer does
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE / 2);
        timestamp = bound(timestamp, 1000, type(uint32).max / 2);
        
        // Set the exact failing timestamp 
        vm.warp(timestamp);
        
        // Create user with the same pattern that failed
        address user = makeAddr(string(abi.encodePacked("stressUser", vm.toString(userSeed))));
        sapienToken.mint(user, amount);
        
        console.log("=== REPRODUCING EXACT FAILING CASE ===");
        console.log("amount:", amount);
        console.log("period (days):", period / 1 days);
        console.log("timestamp:", timestamp);
        console.log("user:", user);
        
        // Test calculateMultiplier first
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(amount, period);
        console.log("expectedMultiplier:", expectedMultiplier);
        assertGt(expectedMultiplier, 0, "calculateMultiplier should work");
        
        // Perform the exact same staking operation that failed
        vm.startPrank(user);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, period);
        vm.stopPrank();
        
        // Check what was actually stored
        ISapienVault.UserStakingSummary memory exactStake = sapienVault.getUserStakingSummary(user);
        uint256 storedMultiplier = exactStake.effectiveMultiplier;
        console.log("storedMultiplier:", storedMultiplier);
        
        // This is the critical test that failed in the fuzzer
        if (storedMultiplier == 0) {
            console.log("REPRODUCTION SUCCESSFUL:");
            console.log("  Same parameters as fuzzer");
            console.log("  Same context (timestamp, user creation)");
            console.log("  effectiveMultiplier corrupted to 0");
            console.log("  This confirms the storage corruption bug");
            revert("Successfully reproduced the exact failing case");
        }
        
        assertEq(storedMultiplier, expectedMultiplier, "Should store multiplier correctly");
    }

    /// @notice Deep investigation of the address-dependent storage corruption
    function test_InvestigateAddressDependentCorruption() public {
        uint256 amount = 8427e18;
        uint256 period = LOCK_180_DAYS; 
        uint256 timestamp = 17266;
        
        vm.warp(timestamp);
        
        // The corrupting address found by fuzzer
        address corruptingUser = makeAddr("stressUser9537");
        
        console.log("=== ADDRESS-DEPENDENT CORRUPTION INVESTIGATION ===");
        console.log("Corrupting address:", corruptingUser);
        console.log("Address bytes32:", uint256(uint160(corruptingUser)));
        console.log("Address hex:", vm.toString(corruptingUser));
        
        // Analyze the address bit patterns
        uint256 addressAsUint = uint256(uint160(corruptingUser));
        console.log("Address as uint256:", addressAsUint);
        console.log("Address low 32 bits:", addressAsUint & type(uint32).max);
        console.log("Address high bits:", addressAsUint >> 32);
        
        // Check for specific bit patterns that might interfere with storage
        console.log("Address & 0xFFFFFFFF:", addressAsUint & 0xFFFFFFFF);
        console.log("Address & 0xFFFFFFFF00000000:", (addressAsUint & 0xFFFFFFFF00000000) >> 32);
        
        // Test the calculation first
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(amount, period);
        console.log("Expected multiplier:", expectedMultiplier);
        console.log("Expected as uint32:", uint32(expectedMultiplier));
        console.log("Expected hex:", vm.toString(abi.encodePacked(uint32(expectedMultiplier))));
        
        // Check if this specific address triggers corruption
        sapienToken.mint(corruptingUser, amount);
        
        vm.startPrank(corruptingUser);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, period);
        vm.stopPrank();
        
        ISapienVault.UserStakingSummary memory corruptingStake = sapienVault.getUserStakingSummary(corruptingUser);
        uint256 storedMultiplier = corruptingStake.effectiveMultiplier;
        console.log("Stored multiplier:", storedMultiplier);
        
        if (storedMultiplier == 0) {
            console.log("CORRUPTION CONFIRMED for address:", corruptingUser);
            console.log("This address causes effectiveMultiplier to become 0");
            
            // Try to understand the storage collision mechanism
            console.log("HYPOTHESIS: UserStake storage slot collision");
            console.log("  Slot 3 contains:");
            console.log("    earlyUnstakeCooldownStart (uint64) - bits 0-63");
            console.log("    effectiveMultiplier (uint32) - bits 64-95"); 
            console.log("    hasStake (bool) - bit 96");
            console.log("  Address bit patterns may interfere with storage assignment");
        }
        
        // Test a working address for comparison
        address workingUser = makeAddr("debugUser");
        sapienToken.mint(workingUser, amount);
        
        vm.startPrank(workingUser);
        sapienToken.approve(address(sapienVault), amount);
        sapienVault.stake(amount, period);
        vm.stopPrank();
        
        ISapienVault.UserStakingSummary memory workingStake = sapienVault.getUserStakingSummary(workingUser);
        uint256 workingMultiplier = workingStake.effectiveMultiplier;
        
        console.log("Working address:", workingUser);
        console.log("Working multiplier:", workingMultiplier);
        console.log("Working address uint256:", uint256(uint160(workingUser)));
        
        // Compare the addresses
        console.log("=== ADDRESS COMPARISON ===");
        console.log("Corrupting addr low 32:", uint256(uint160(corruptingUser)) & type(uint32).max);
        console.log("Working addr low 32:", uint256(uint160(workingUser)) & type(uint32).max);
        
        uint256 corruptingLow = uint256(uint160(corruptingUser)) & type(uint32).max;
        uint256 expectedLow = uint32(expectedMultiplier);
        
        if (corruptingLow == expectedLow) {
            console.log("COLLISION DETECTED:");
            console.log("  User address low 32 bits:", corruptingLow);
            console.log("  Expected multiplier:", expectedLow);
            console.log("  These values collide in storage slot packing!");
        }
    }

    /// @notice Fuzz test that generates random addresses and looks for storage corruption
    function testFuzz_StorageCorruption_RandomAddresses(
        uint256 seed,
        uint256 amount,
        uint8 periodIndex
    ) public {
        // Bound inputs
        amount = bound(amount, MINIMUM_STAKE, MAXIMUM_STAKE);
        uint256[4] memory validPeriods = [LOCK_30_DAYS, LOCK_90_DAYS, LOCK_180_DAYS, LOCK_365_DAYS];
        uint256 period = validPeriods[periodIndex % 4];

        // Generate random address using seed
        address randomUser = address(uint160(uint256(keccak256(abi.encodePacked(seed)))));
        
        // Skip if user already has stake
        if (sapienVault.hasActiveStake(randomUser)) return;

        // Fund and stake
        sapienToken.mint(randomUser, amount);
        
        // Calculate expected multiplier
        uint256 expectedMultiplier = sapienVault.calculateMultiplier(amount, period);
        if (expectedMultiplier == 0) return;

        // Perform staking
        vm.startPrank(randomUser);
        sapienToken.approve(address(sapienVault), amount);
        
        try sapienVault.stake(amount, period) {
            // Get stored multiplier
            ISapienVault.UserStakingSummary memory userStake = sapienVault.getUserStakingSummary(randomUser);
            uint256 storedMultiplier = userStake.effectiveMultiplier;

            // Check for corruption
            if (expectedMultiplier > 0 && storedMultiplier == 0) {
                emit StorageCorruption(
                    randomUser,
                    amount,
                    period,
                    expectedMultiplier,
                    0,
                    storedMultiplier
                );
                revert("STORAGE CORRUPTION: Random address caused multiplier corruption");
            }

            // Verify multiplier matches
            if (storedMultiplier != expectedMultiplier) {
                emit StorageCorruption(
                    randomUser,
                    amount,
                    period,
                    expectedMultiplier,
                    0,
                    storedMultiplier
                );
                revert("MULTIPLIER MISMATCH: Random address caused multiplier mismatch");
            }
        } catch {
            // Handle legitimate reverts gracefully
        }
        vm.stopPrank();
    }

} 