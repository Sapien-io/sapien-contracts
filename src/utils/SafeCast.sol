// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/**
 * @title SafeCast
 * @notice Library for safely casting uint256 to smaller uint types
 * @dev Provides overflow protection when downcasting integers for optimized storage
 */
library SafeCast {
    /**
     * @notice Safely casts uint256 to uint128, reverting on overflow
     * @param value The value to cast
     * @return The safely cast value
     * @dev Reverts with "SafeCast: value doesn't fit in 128 bits" if overflow occurs
     */
    function toUint128(uint256 value) internal pure returns (uint128) {
        require(value <= type(uint128).max, "SafeCast: value doesn't fit in 128 bits");
        return uint128(value);
    }

    /**
     * @notice Safely casts uint256 to uint64, reverting on overflow
     * @param value The value to cast
     * @return The safely cast value
     * @dev Reverts with "SafeCast: value doesn't fit in 64 bits" if overflow occurs
     */
    function toUint64(uint256 value) internal pure returns (uint64) {
        require(value <= type(uint64).max, "SafeCast: value doesn't fit in 64 bits");
        return uint64(value);
    }

    /**
     * @notice Safely casts uint256 to uint32, reverting on overflow
     * @param value The value to cast
     * @return The safely cast value
     * @dev Reverts with "SafeCast: value doesn't fit in 32 bits" if overflow occurs
     */
    function toUint32(uint256 value) internal pure returns (uint32) {
        require(value <= type(uint32).max, "SafeCast: value doesn't fit in 32 bits");
        return uint32(value);
    }

    /**
     * @notice Safely casts uint256 to uint16, reverting on overflow
     * @param value The value to cast
     * @return The safely cast value
     * @dev Reverts with "SafeCast: value doesn't fit in 16 bits" if overflow occurs
     */
    function toUint16(uint256 value) internal pure returns (uint16) {
        require(value <= type(uint16).max, "SafeCast: value doesn't fit in 16 bits");
        return uint16(value);
    }

    /**
     * @notice Safely casts uint256 to uint8, reverting on overflow
     * @param value The value to cast
     * @return The safely cast value
     * @dev Reverts with "SafeCast: value doesn't fit in 8 bits" if overflow occurs
     */
    function toUint8(uint256 value) internal pure returns (uint8) {
        require(value <= type(uint8).max, "SafeCast: value doesn't fit in 8 bits");
        return uint8(value);
    }
}
