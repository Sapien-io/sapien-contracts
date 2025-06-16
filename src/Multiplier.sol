// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

library Multiplier {
    // Constants - matching test expectations
    uint256 public constant BASIS_POINTS = 10000; // 100% = 10000 basis points
    uint256 public constant BASE_MULTIPLIER = 10000; // Base multiplier (1.00x)
    uint256 public constant MAX_TOKENS = 2500 ether; // Maximum token stake (2500 tokens)
    uint256 public constant MAX_LOCKUP = 365 days; // Maximum lockup period in seconds
    uint256 public constant MAX_BONUS = 5000; // 50%

    function calculateMultiplier(uint256 amount, uint256 lockupPeriod) external pure returns (uint256) {
        // Clamp inputs to valid ranges
        if (amount > MAX_TOKENS) amount = MAX_TOKENS;
        if (lockupPeriod > MAX_LOCKUP) lockupPeriod = MAX_LOCKUP;

        // Normalize to basis points (0-10000)
        uint256 normalizedAmount = (amount * BASIS_POINTS) / MAX_TOKENS;
        uint256 normalizedLockup = (lockupPeriod * BASIS_POINTS) / MAX_LOCKUP;

        // Calculate combined effect (both amount and time contribute)
        uint256 x = (normalizedLockup * normalizedAmount) / BASIS_POINTS;

        // Apply bonus based on combined effect
        uint256 bonus = (x * MAX_BONUS) / BASIS_POINTS;

        return BASE_MULTIPLIER + bonus;
    }
}
