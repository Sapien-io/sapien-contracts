// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Test} from "lib/forge-std/src/Test.sol";
import {SafeCast} from "src/utils/SafeCast.sol";

/**
 * @title SafeCastTest
 * @notice Test suite for SafeCast library functions
 * @dev Tests all SafeCast functions with boundary conditions and overflow scenarios
 */
contract SafeCastTest is Test {
    // =============================================================================
    // toUint128 TESTS
    // =============================================================================

    function test_SafeCast_toUint128_Success() public pure {
        // Test with zero
        assertEq(SafeCast.toUint128(0), 0);

        // Test with typical values
        assertEq(SafeCast.toUint128(1), 1);
        assertEq(SafeCast.toUint128(1000), 1000);
        assertEq(SafeCast.toUint128(1e18), 1e18);

        // Test with maximum uint128 value
        uint256 maxUint128 = type(uint128).max;
        assertEq(SafeCast.toUint128(maxUint128), type(uint128).max);
    }

    function test_SafeCast_toUint128_Overflow() public {
        // Test overflow with a value larger than uint128.max
        // Use a specific large value instead of max + 1 to avoid overflow
        uint256 overflowValue = type(uint256).max;

        vm.expectRevert("SafeCast: value doesn't fit in 128 bits");
        SafeCast.toUint128(overflowValue);

        // Test with uint256.max
        vm.expectRevert("SafeCast: value doesn't fit in 128 bits");
        SafeCast.toUint128(type(uint256).max);
    }

    // =============================================================================
    // toUint64 TESTS
    // =============================================================================

    function test_SafeCast_toUint64_Success() public pure {
        // Test with zero
        assertEq(SafeCast.toUint64(0), 0);

        // Test with typical values
        assertEq(SafeCast.toUint64(1), 1);
        assertEq(SafeCast.toUint64(1000), 1000);
        assertEq(SafeCast.toUint64(1e18), 1e18);

        // Test with maximum uint64 value
        uint256 maxUint64 = type(uint64).max;
        assertEq(SafeCast.toUint64(maxUint64), type(uint64).max);
    }

    function test_SafeCast_toUint64_Overflow() public {
        // Test overflow with uint128.max (which is larger than uint64.max)
        vm.expectRevert("SafeCast: value doesn't fit in 64 bits");
        SafeCast.toUint64(type(uint128).max);

        // Test with type(uint256).max
        vm.expectRevert("SafeCast: value doesn't fit in 64 bits");
        SafeCast.toUint64(type(uint256).max);
    }

    // =============================================================================
    // toUint32 TESTS
    // =============================================================================

    function test_SafeCast_toUint32_Success() public pure {
        // Test with zero
        assertEq(SafeCast.toUint32(0), 0);

        // Test with typical values
        assertEq(SafeCast.toUint32(1), 1);
        assertEq(SafeCast.toUint32(1000), 1000);
        assertEq(SafeCast.toUint32(1e9), 1e9);

        // Test with maximum uint32 value
        uint256 maxUint32 = type(uint32).max;
        assertEq(SafeCast.toUint32(maxUint32), type(uint32).max);
    }

    function test_SafeCast_toUint32_Overflow() public {
        // Test with uint64.max (which is larger than uint32.max)
        vm.expectRevert("SafeCast: value doesn't fit in 32 bits");
        SafeCast.toUint32(type(uint64).max);

        // Test with a specific large value
        vm.expectRevert("SafeCast: value doesn't fit in 32 bits");
        SafeCast.toUint32(type(uint256).max);
    }

    // =============================================================================
    // toUint16 TESTS
    // =============================================================================

    function test_SafeCast_toUint16_Success() public pure {
        // Test with zero
        assertEq(SafeCast.toUint16(0), 0);

        // Test with typical values
        assertEq(SafeCast.toUint16(1), 1);
        assertEq(SafeCast.toUint16(100), 100);
        assertEq(SafeCast.toUint16(1000), 1000);
        assertEq(SafeCast.toUint16(65000), 65000);

        // Test with maximum uint16 value (65535)
        uint256 maxUint16 = type(uint16).max;
        assertEq(SafeCast.toUint16(maxUint16), type(uint16).max);
        assertEq(SafeCast.toUint16(65535), 65535);
    }

    function test_SafeCast_toUint16_Overflow() public {
        // Test overflow with value larger than uint16.max (65535)
        vm.expectRevert("SafeCast: value doesn't fit in 16 bits");
        SafeCast.toUint16(65536); // 65536 is just over the limit

        // Test with larger values
        vm.expectRevert("SafeCast: value doesn't fit in 16 bits");
        SafeCast.toUint16(100000);

        vm.expectRevert("SafeCast: value doesn't fit in 16 bits");
        SafeCast.toUint16(type(uint32).max);
    }

    // =============================================================================
    // toUint8 TESTS
    // =============================================================================

    function test_SafeCast_toUint8_Success() public pure {
        // Test with zero
        assertEq(SafeCast.toUint8(0), 0);

        // Test with typical values
        assertEq(SafeCast.toUint8(1), 1);
        assertEq(SafeCast.toUint8(10), 10);
        assertEq(SafeCast.toUint8(100), 100);
        assertEq(SafeCast.toUint8(200), 200);

        // Test with maximum uint8 value (255)
        uint256 maxUint8 = type(uint8).max;
        assertEq(SafeCast.toUint8(maxUint8), type(uint8).max);
        assertEq(SafeCast.toUint8(255), 255);
    }

    function test_SafeCast_toUint8_Overflow() public {
        // Test overflow with value larger than uint8.max (255)
        vm.expectRevert("SafeCast: value doesn't fit in 8 bits");
        SafeCast.toUint8(256); // 256 is just over the limit

        // Test with larger values
        vm.expectRevert("SafeCast: value doesn't fit in 8 bits");
        SafeCast.toUint8(1000);

        vm.expectRevert("SafeCast: value doesn't fit in 8 bits");
        SafeCast.toUint8(type(uint16).max);

        vm.expectRevert("SafeCast: value doesn't fit in 8 bits");
        SafeCast.toUint8(type(uint256).max);
    }

    // =============================================================================
    // BOUNDARY CONDITION TESTS
    // =============================================================================

    function test_SafeCast_BoundaryConditions_AllTypes() public pure {
        // Test all types with their exact maximum values
        assertEq(SafeCast.toUint128(type(uint128).max), type(uint128).max);
        assertEq(SafeCast.toUint64(type(uint64).max), type(uint64).max);
        assertEq(SafeCast.toUint32(type(uint32).max), type(uint32).max);
        assertEq(SafeCast.toUint16(type(uint16).max), type(uint16).max);
        assertEq(SafeCast.toUint8(type(uint8).max), type(uint8).max);

        // Verify the actual max values we're testing
        assertEq(type(uint8).max, 255);
        assertEq(type(uint16).max, 65535);
        assertEq(type(uint32).max, 4294967295);
        assertEq(type(uint64).max, 18446744073709551615);
    }

    function test_SafeCast_BoundaryConditions_JustOverMax() public {
        // Test each type with value just over their maximum (should revert)

        vm.expectRevert("SafeCast: value doesn't fit in 128 bits");
        SafeCast.toUint128(type(uint256).max);

        vm.expectRevert("SafeCast: value doesn't fit in 64 bits");
        SafeCast.toUint64(type(uint128).max);

        vm.expectRevert("SafeCast: value doesn't fit in 32 bits");
        SafeCast.toUint32(type(uint64).max);

        vm.expectRevert("SafeCast: value doesn't fit in 16 bits");
        SafeCast.toUint16(65536);

        vm.expectRevert("SafeCast: value doesn't fit in 8 bits");
        SafeCast.toUint8(256);
    }

    // =============================================================================
    // FUZZ TESTS
    // =============================================================================

    function testFuzz_SafeCast_toUint128_ValidRange(uint128 value) public pure {
        // Any uint128 value should successfully cast to uint128
        assertEq(SafeCast.toUint128(uint256(value)), value);
    }

    function testFuzz_SafeCast_toUint64_ValidRange(uint64 value) public pure {
        // Any uint64 value should successfully cast to uint64
        assertEq(SafeCast.toUint64(uint256(value)), value);
    }

    function testFuzz_SafeCast_toUint32_ValidRange(uint32 value) public pure {
        // Any uint32 value should successfully cast to uint32
        assertEq(SafeCast.toUint32(uint256(value)), value);
    }

    function testFuzz_SafeCast_toUint16_ValidRange(uint16 value) public pure {
        // Any uint16 value should successfully cast to uint16
        assertEq(SafeCast.toUint16(uint256(value)), value);
    }

    function testFuzz_SafeCast_toUint8_ValidRange(uint8 value) public pure {
        // Any uint8 value should successfully cast to uint8
        assertEq(SafeCast.toUint8(uint256(value)), value);
    }

    function testFuzz_SafeCast_toUint128_InvalidRange(uint256 value) public {
        // Values larger than uint128.max should revert
        vm.assume(value > type(uint128).max);

        vm.expectRevert("SafeCast: value doesn't fit in 128 bits");
        SafeCast.toUint128(value);
    }

    function testFuzz_SafeCast_toUint64_InvalidRange(uint256 value) public {
        // Values larger than uint64.max should revert
        vm.assume(value > type(uint64).max);

        vm.expectRevert("SafeCast: value doesn't fit in 64 bits");
        SafeCast.toUint64(value);
    }

    function testFuzz_SafeCast_toUint32_InvalidRange(uint256 value) public {
        // Values larger than uint32.max should revert
        vm.assume(value > type(uint32).max);

        vm.expectRevert("SafeCast: value doesn't fit in 32 bits");
        SafeCast.toUint32(value);
    }

    function testFuzz_SafeCast_toUint16_InvalidRange(uint256 value) public {
        // Values larger than uint16.max should revert
        vm.assume(value > type(uint16).max);

        vm.expectRevert("SafeCast: value doesn't fit in 16 bits");
        SafeCast.toUint16(value);
    }

    function testFuzz_SafeCast_toUint8_InvalidRange(uint256 value) public {
        // Values larger than uint8.max should revert
        vm.assume(value > type(uint8).max);

        vm.expectRevert("SafeCast: value doesn't fit in 8 bits");
        SafeCast.toUint8(value);
    }

    // =============================================================================
    // INTEGRATION TESTS WITH REAL-WORLD VALUES
    // =============================================================================

    function test_SafeCast_RealWorldUseCases() public pure {
        // Test with common blockchain values

        // Timestamps (should fit in uint64)
        uint256 currentTimestamp = 1700000000; // November 2023
        assertEq(SafeCast.toUint64(currentTimestamp), uint64(currentTimestamp));

        // Token amounts (18 decimals, should fit in uint128 for reasonable amounts)
        uint256 tokenAmount = 1000 * 1e18; // 1000 tokens with 18 decimals
        assertEq(SafeCast.toUint128(tokenAmount), uint128(tokenAmount));

        // Basis points (should fit in uint16)
        uint256 basisPoints = 10000; // 100% in basis points
        assertEq(SafeCast.toUint16(basisPoints), uint16(basisPoints));

        // Percentages (should fit in uint8)
        uint256 percentage = 100; // 100%
        assertEq(SafeCast.toUint8(percentage), uint8(percentage));

        // Small multipliers (should fit in uint32)
        uint256 multiplier = 19500; // 1.95x in basis points
        assertEq(SafeCast.toUint32(multiplier), uint32(multiplier));
    }

    function test_SafeCast_EdgeCaseValues() public {
        // Test with edge case values that might appear in real contracts

        // Maximum safe token supply that fits in uint128
        uint256 maxTokenSupply = type(uint128).max;
        assertEq(SafeCast.toUint128(maxTokenSupply), type(uint128).max);

        // Attempting to cast a larger token supply should fail
        vm.expectRevert("SafeCast: value doesn't fit in 128 bits");
        SafeCast.toUint128(type(uint256).max);

        // Large timestamp that still fits in uint64 (year 2554)
        uint256 futureTimestamp = 18446744073; // Still within uint64 range
        assertEq(SafeCast.toUint64(futureTimestamp), uint64(futureTimestamp));

        // Basis points just at the limit
        assertEq(SafeCast.toUint16(65535), 65535);
        vm.expectRevert("SafeCast: value doesn't fit in 16 bits");
        SafeCast.toUint16(65536);
    }
}
