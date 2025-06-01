// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {console} from "lib/forge-std/src/console.sol";
import {Multiplier} from "src/Multiplier.sol";
import {Constants as Const} from "src/utils/Constants.sol";

contract MultiplierTest is Test {
    Multiplier public multiplier;

    // Test constants for lockup periods
    uint256 public constant LOCK_30_DAYS = 30 days;
    uint256 public constant LOCK_60_DAYS = 60 days;
    uint256 public constant LOCK_90_DAYS = 90 days;
    uint256 public constant LOCK_180_DAYS = 180 days;
    uint256 public constant LOCK_365_DAYS = 365 days;

    // Expected multiplier values from constants
    uint256 public constant EXPECTED_30_DAY = Const.MIN_MULTIPLIER; // 10500 (1.05x)
    uint256 public constant EXPECTED_90_DAY = Const.MULTIPLIER_90_DAYS; // 11000 (1.10x)
    uint256 public constant EXPECTED_180_DAY = Const.MULTIPLIER_180_DAYS; // 12500 (1.25x)
    uint256 public constant EXPECTED_365_DAY = Const.MAX_MULTIPLIER; // 15000 (1.50x)

    function setUp() public {
        multiplier = new Multiplier();
    }

    // =============================================================================
    // DISCRETE LOCKUP PERIOD TESTS
    // =============================================================================

    function test_getMultiplierForPeriod_30Days() public view {
        uint256 actualMultiplier = multiplier.getMultiplierForPeriod(LOCK_30_DAYS);
        
        assertEq(
            actualMultiplier,
            EXPECTED_30_DAY,
            "30-day lockup should return MIN_MULTIPLIER (10500)"
        );
        
        console.log("30 days multiplier:", actualMultiplier);
    }

    function test_getMultiplierForPeriod_90Days() public view {
        uint256 actualMultiplier = multiplier.getMultiplierForPeriod(LOCK_90_DAYS);
        
        assertEq(
            actualMultiplier,
            EXPECTED_90_DAY,
            "90-day lockup should return MULTIPLIER_90_DAYS (11000)"
        );
        
        console.log("90 days multiplier:", actualMultiplier);
    }

    function test_getMultiplierForPeriod_180Days() public view {
        uint256 actualMultiplier = multiplier.getMultiplierForPeriod(LOCK_180_DAYS);
        
        assertEq(
            actualMultiplier,
            EXPECTED_180_DAY,
            "180-day lockup should return MULTIPLIER_180_DAYS (12500)"
        );
        
        console.log("180 days multiplier:", actualMultiplier);
    }

    function test_getMultiplierForPeriod_365Days() public view {
        uint256 actualMultiplier = multiplier.getMultiplierForPeriod(LOCK_365_DAYS);
        
        assertEq(
            actualMultiplier,
            EXPECTED_365_DAY,
            "365-day lockup should return MAX_MULTIPLIER (15000)"
        );
        
        console.log("365 days multiplier:", actualMultiplier);
    }

    function test_getMultiplierForPeriod_60Days_LinearInterpolation() public view {
        uint256 actualMultiplier = multiplier.getMultiplierForPeriod(LOCK_60_DAYS);
        
        // Calculate expected value using linear interpolation between 30 and 90 days
        // Formula: min + (period - minPeriod) * (max - min) / (maxPeriod - minPeriod)
        // For 60 days between 30 and 365 days total range:
        uint256 numerator = (LOCK_60_DAYS - LOCK_30_DAYS) * (EXPECTED_365_DAY - EXPECTED_30_DAY);
        uint256 denominator = LOCK_365_DAYS - LOCK_30_DAYS;
        uint256 expectedMultiplier = EXPECTED_30_DAY + (numerator / denominator);
        
        assertEq(
            actualMultiplier,
            expectedMultiplier,
            "60-day lockup should be linearly interpolated between 30 and 365 days"
        );
        
        console.log("60 days multiplier (actual):", actualMultiplier);
        console.log("60 days multiplier (expected):", expectedMultiplier);
        
        // Verify it's between 30 and 90 day values
        assertGt(actualMultiplier, EXPECTED_30_DAY, "60-day should be greater than 30-day");
        assertLt(actualMultiplier, EXPECTED_90_DAY, "60-day should be less than 90-day");
    }

    // =============================================================================
    // COMPREHENSIVE TIER VERIFICATION TESTS
    // =============================================================================

    function test_getMultiplierForPeriod_AllDiscreteTiers() public view {
        console.log("=== MULTIPLIER TIER VERIFICATION ===");
        
        uint256[] memory lockupPeriods = new uint256[](5);
        lockupPeriods[0] = LOCK_30_DAYS;
        lockupPeriods[1] = LOCK_60_DAYS;
        lockupPeriods[2] = LOCK_90_DAYS;
        lockupPeriods[3] = LOCK_180_DAYS;
        lockupPeriods[4] = LOCK_365_DAYS;

        uint256[] memory expectedMultipliers = new uint256[](5);
        expectedMultipliers[0] = EXPECTED_30_DAY;
        expectedMultipliers[1] = _calculateExpectedMultiplier(LOCK_60_DAYS);
        expectedMultipliers[2] = EXPECTED_90_DAY;
        expectedMultipliers[3] = EXPECTED_180_DAY;
        expectedMultipliers[4] = EXPECTED_365_DAY;

        for (uint256 i = 0; i < lockupPeriods.length; i++) {
            uint256 actualMultiplier = multiplier.getMultiplierForPeriod(lockupPeriods[i]);
            
            assertEq(
                actualMultiplier,
                expectedMultipliers[i],
                string(abi.encodePacked("Multiplier mismatch for period: ", _toString(lockupPeriods[i] / 1 days), " days"))
            );
            
            console.log(
                string(abi.encodePacked(
                    _toString(lockupPeriods[i] / 1 days),
                    " days: ",
                    _toString(actualMultiplier),
                    " (expected: ",
                    _toString(expectedMultipliers[i]),
                    ")"
                ))
            );
        }
    }

    function test_getMultiplierForPeriod_ProgressiveIncrease() public view {
        console.log("=== PROGRESSIVE MULTIPLIER INCREASE ===");
        
        uint256[] memory periods = new uint256[](5);
        periods[0] = LOCK_30_DAYS;
        periods[1] = LOCK_60_DAYS;
        periods[2] = LOCK_90_DAYS;
        periods[3] = LOCK_180_DAYS;
        periods[4] = LOCK_365_DAYS;

        uint256 previousMultiplier = 0;
        
        for (uint256 i = 0; i < periods.length; i++) {
            uint256 currentMultiplier = multiplier.getMultiplierForPeriod(periods[i]);
            
            if (i > 0) {
                assertGt(
                    currentMultiplier,
                    previousMultiplier,
                    "Multiplier should increase with longer lockup periods"
                );
                
                console.log(
                    string(abi.encodePacked(
                        _toString(periods[i] / 1 days),
                        " days (",
                        _toString(currentMultiplier),
                        ") > ",
                        _toString(periods[i-1] / 1 days),
                        " days (",
                        _toString(previousMultiplier),
                        ")"
                    ))
                );
            }
            
            previousMultiplier = currentMultiplier;
        }
    }

    // =============================================================================
    // BOUNDARY AND EDGE CASE TESTS
    // =============================================================================

    function test_getMultiplierForPeriod_InvalidPeriods() public view {
        // Test periods below minimum
        assertEq(
            multiplier.getMultiplierForPeriod(LOCK_30_DAYS - 1),
            0,
            "Period below 30 days should return 0"
        );
        
        assertEq(
            multiplier.getMultiplierForPeriod(15 days),
            0,
            "15-day period should return 0"
        );
        
        // Test periods above maximum
        assertEq(
            multiplier.getMultiplierForPeriod(LOCK_365_DAYS + 1),
            0,
            "Period above 365 days should return 0"
        );
        
        assertEq(
            multiplier.getMultiplierForPeriod(400 days),
            0,
            "400-day period should return 0"
        );
    }

    function test_getMultiplierForPeriod_BoundaryValues() public view {
        // Test exact boundary values
        assertEq(
            multiplier.getMultiplierForPeriod(LOCK_30_DAYS),
            EXPECTED_30_DAY,
            "Exact 30-day boundary should work"
        );
        
        assertEq(
            multiplier.getMultiplierForPeriod(LOCK_365_DAYS),
            EXPECTED_365_DAY,
            "Exact 365-day boundary should work"
        );
        
        // Test just inside boundaries (use a meaningful increment)
        uint256 multiplierAbove30Days = multiplier.getMultiplierForPeriod(LOCK_30_DAYS + 1 days);
        assertGt(
            multiplierAbove30Days,
            EXPECTED_30_DAY,
            "31 days should be greater than 30-day multiplier"
        );
        
        assertEq(
            multiplier.getMultiplierForPeriod(LOCK_365_DAYS - 1),
            _calculateExpectedMultiplier(LOCK_365_DAYS - 1),
            "Just below 365 days should use interpolation"
        );
    }

    function test_getMultiplierForPeriod_29Point9Days_NotMoreThan30Days() public view {
        // Calculate 29.9 days (29 days + 21.6 hours = 29 days + 21 hours + 36 minutes)
        uint256 period29Point9Days = 29 days + 21 hours + 36 minutes;
        
        // Verify this is actually less than 30 days
        assertLt(period29Point9Days, LOCK_30_DAYS, "29.9 days should be less than 30 days");
        
        // Get multipliers
        uint256 multiplier29Point9Days = multiplier.getMultiplierForPeriod(period29Point9Days);
        uint256 multiplier30Days = multiplier.getMultiplierForPeriod(LOCK_30_DAYS);
        
        // 29.9 days should return 0 (invalid period)
        assertEq(
            multiplier29Point9Days,
            0,
            "29.9 days should return 0 (below minimum)"
        );
        
        // 30 days should return the expected minimum multiplier
        assertEq(
            multiplier30Days,
            EXPECTED_30_DAY,
            "30 days should return MIN_MULTIPLIER"
        );
        
        // Verify 29.9 days is NOT more than 30 days
        assertLe(
            multiplier29Point9Days,
            multiplier30Days,
            "29.9 days multiplier should NOT be more than 30 days multiplier"
        );
        
        console.log("29.9 days multiplier:", multiplier29Point9Days);
        console.log("30.0 days multiplier:", multiplier30Days);
        console.log("29.9 days period (seconds):", period29Point9Days);
        console.log("30.0 days period (seconds):", LOCK_30_DAYS);
    }

    function test_getMultiplierForPeriod_30DayBoundaryComprehensive() public view {
        console.log("=== 30-DAY BOUNDARY COMPREHENSIVE TEST ===");
        
        // Test various periods around the 30-day boundary
        uint256[] memory testPeriods = new uint256[](6);
        testPeriods[0] = LOCK_30_DAYS - 1 hours;    // 29 days 23 hours
        testPeriods[1] = LOCK_30_DAYS - 1 minutes;  // 29 days 23 hours 59 minutes
        testPeriods[2] = LOCK_30_DAYS - 1;          // 29 days 23 hours 59 minutes 59 seconds
        testPeriods[3] = LOCK_30_DAYS;              // Exactly 30 days
        testPeriods[4] = LOCK_30_DAYS + 1 days;     // 31 days (more meaningful increment)
        testPeriods[5] = LOCK_30_DAYS + 7 days;     // 37 days (even more meaningful)
        
        string[] memory descriptions = new string[](6);
        descriptions[0] = "29d 23h";
        descriptions[1] = "29d 23h 59m";
        descriptions[2] = "29d 23h 59m 59s";
        descriptions[3] = "30d exactly";
        descriptions[4] = "31d";
        descriptions[5] = "37d";
        
        for (uint256 i = 0; i < testPeriods.length; i++) {
            uint256 currentMultiplier = multiplier.getMultiplierForPeriod(testPeriods[i]);
            
            if (i < 3) {
                // Periods before 30 days should return 0
                assertEq(
                    currentMultiplier,
                    0,
                    string(abi.encodePacked(descriptions[i], " should return 0"))
                );
            } else if (i == 3) {
                // Exactly 30 days should return MIN_MULTIPLIER
                assertEq(
                    currentMultiplier,
                    EXPECTED_30_DAY,
                    "Exactly 30 days should return MIN_MULTIPLIER"
                );
            } else {
                // Periods after 30 days should be greater than MIN_MULTIPLIER
                assertGt(
                    currentMultiplier,
                    EXPECTED_30_DAY,
                    string(abi.encodePacked(descriptions[i], " should be greater than MIN_MULTIPLIER"))
                );
            }
            
            console.log(
                string(abi.encodePacked(
                    descriptions[i],
                    ": ",
                    _toString(currentMultiplier),
                    " (period: ",
                    _toString(testPeriods[i]),
                    "s)"
                ))
            );
        }
    }

    function test_isValidLockupPeriod() public view {
        // Valid periods
        assertTrue(
            multiplier.isValidLockupPeriod(LOCK_30_DAYS),
            "30 days should be valid"
        );
        
        assertTrue(
            multiplier.isValidLockupPeriod(LOCK_90_DAYS),
            "90 days should be valid"
        );
        
        assertTrue(
            multiplier.isValidLockupPeriod(LOCK_365_DAYS),
            "365 days should be valid"
        );
        
        // Invalid periods
        assertFalse(
            multiplier.isValidLockupPeriod(15 days),
            "15 days should be invalid"
        );
        
        assertFalse(
            multiplier.isValidLockupPeriod(400 days),
            "400 days should be invalid"
        );
    }

    // =============================================================================
    // HELPER FUNCTIONS
    // =============================================================================

    function _calculateExpectedMultiplier(uint256 lockUpPeriod) internal pure returns (uint256) {
        if (lockUpPeriod < LOCK_30_DAYS || lockUpPeriod > LOCK_365_DAYS) {
            return 0;
        }
        
        uint256 numerator = (lockUpPeriod - LOCK_30_DAYS) * (EXPECTED_365_DAY - EXPECTED_30_DAY);
        uint256 denominator = LOCK_365_DAYS - LOCK_30_DAYS;
        
        return EXPECTED_30_DAY + (numerator / denominator);
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
} 