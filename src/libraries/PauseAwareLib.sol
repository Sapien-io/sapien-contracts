// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {EngineStorage} from "src/Types.sol";

/// @title PauseAwareLib
/// @notice Library for pause-aware time calculations (POQ-11 Fix)
/// @dev Implements the fix for Quantstamp audit finding POQ-11:
///      "Protocol Pausability Creates Slash and Reputation Exposure for Honest Participants"
///
/// PROBLEM:
/// While the protocol is paused, all user actions are blocked via `whenNotPaused` modifiers,
/// but internal timers continue to advance. This creates unfair slash exposure:
/// - A 1-hour pause makes contributor claim deadlines expire early
/// - A 2-hour pause makes validator commit/reveal windows close prematurely
/// - Honest participants who couldn't act during pause get slashed through no fault of their own
///
/// SOLUTION:
/// Track cumulative paused duration and calculate "effective time" for all deadline checks.
/// effectiveTime = block.timestamp - totalPausedDuration
///
/// This means:
/// - If deadline was set at T=100 for 1 day (expires at T=86500)
/// - Protocol pauses for 2 hours (7200 seconds)
/// - At T=86500, effectiveTime = 86500 - 7200 = 79300
/// - Deadline check: 79300 < 86500 ✓ Still valid!
/// - Participants get their full allocated time despite the pause
///
/// IMPLEMENTATION DETAILS:
/// - Storage: totalPausedDuration accumulates all pause time
/// - Storage: lastPauseTimestamp tracks current pause start (0 if not paused)
/// - On pause(): record start time
/// - On unpause(): add elapsed time to total, reset start time to 0
/// - All deadline checks use effectiveTimestamp() instead of block.timestamp
///
// Quantstamp Initial Audit (2026-02-25 to 2026-03-06)
// Finding: POQ-11 (Medium Severity)
// Recommendation: Track cumulative paused duration and subtract from deadline calculations
library PauseAwareLib {
    /// @notice Returns the current effective block timestamp for deadline comparisons.
    ///         This is block.timestamp minus the total time the protocol has been paused.
    /// @param $ The engine storage reference
    /// @return Effective current timestamp accounting for pauses
    function effectiveTimestamp(EngineStorage storage $) internal view returns (uint256) {
        uint256 totalPause = $.totalPausedDuration;

        // If currently paused (lastPauseTimestamp != 0), add ongoing pause duration
        if ($.lastPauseTimestamp > 0) {
            totalPause += block.timestamp - $.lastPauseTimestamp;
        }

        // Effective time = real time - paused time
        // This means deadlines set before pause are effectively extended
        return block.timestamp - totalPause;
    }

    /// @notice Checks if current effective time is after a deadline (strict >)
    /// @param $ The engine storage reference
    /// @param deadlineTimestamp The absolute deadline timestamp
    /// @return True if current effective time > deadline
    function isAfterDeadline(EngineStorage storage $, uint256 deadlineTimestamp) internal view returns (bool) {
        return effectiveTimestamp($) > deadlineTimestamp;
    }

    /// @notice Checks if current effective time is before a deadline (strict <)
    /// @param $ The engine storage reference
    /// @param deadlineTimestamp The absolute deadline timestamp
    /// @return True if current effective time < deadline
    function isBeforeDeadline(EngineStorage storage $, uint256 deadlineTimestamp) internal view returns (bool) {
        return effectiveTimestamp($) < deadlineTimestamp;
    }

    /// @notice Checks if current effective time is at or before a deadline (<=)
    /// @param $ The engine storage reference
    /// @param deadlineTimestamp The absolute deadline timestamp
    /// @return True if current effective time <= deadline
    function isBeforeOrAtDeadline(EngineStorage storage $, uint256 deadlineTimestamp) internal view returns (bool) {
        return effectiveTimestamp($) <= deadlineTimestamp;
    }

    /// @notice Checks if a duration has strictly elapsed (effective time > start + duration)
    /// @param $ The engine storage reference
    /// @param startTimestamp When the period started
    /// @param duration How long the period should last
    /// @return True if current effective time is strictly after the period end
    function hasStrictlyElapsed(EngineStorage storage $, uint256 startTimestamp, uint256 duration)
        internal
        view
        returns (bool)
    {
        return effectiveTimestamp($) > startTimestamp + duration;
    }

    /// @notice Checks if a duration has elapsed or is exactly at the end (effective time >= start + duration)
    /// @param $ The engine storage reference
    /// @param startTimestamp When the period started
    /// @param duration How long the period should last
    /// @return True if current effective time >= period end
    function hasElapsed(EngineStorage storage $, uint256 startTimestamp, uint256 duration)
        internal
        view
        returns (bool)
    {
        return effectiveTimestamp($) >= startTimestamp + duration;
    }

    /// @notice Checks if a duration has NOT elapsed yet (effective time < start + duration)
    /// @param $ The engine storage reference
    /// @param startTimestamp When the period started
    /// @param duration How long the period should last
    /// @return True if current effective time is before the period end
    function hasNotElapsed(EngineStorage storage $, uint256 startTimestamp, uint256 duration)
        internal
        view
        returns (bool)
    {
        return effectiveTimestamp($) < startTimestamp + duration;
    }

    /// @notice Checks if a duration has NOT strictly elapsed (effective time <= start + duration)
    /// @param $ The engine storage reference
    /// @param startTimestamp When the period started
    /// @param duration How long the period should last
    /// @return True if current effective time is at or before the period end
    function hasNotStrictlyElapsed(EngineStorage storage $, uint256 startTimestamp, uint256 duration)
        internal
        view
        returns (bool)
    {
        return effectiveTimestamp($) <= startTimestamp + duration;
    }

    /// @notice Returns the total cumulative paused duration
    /// @param $ The engine storage reference
    /// @param isPaused Whether the protocol is currently paused (from Pausable state)
    /// @return The total paused duration in seconds
    function getTotalPausedDuration(EngineStorage storage $, bool isPaused) internal view returns (uint256) {
        uint256 totalPause = $.totalPausedDuration;

        // If currently paused, include the ongoing pause duration
        if ($.lastPauseTimestamp > 0 && isPaused) {
            totalPause += block.timestamp - $.lastPauseTimestamp;
        }

        return totalPause;
    }
}

