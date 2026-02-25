// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {EngineStorage, Reputation} from "src/Types.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title ReputationLib
/// @notice Deployed library for reputation system operations.
/// @dev Called via DELEGATECALL from SapienCore; operates on the caller's ERC-7201 storage.
library ReputationLib {
    // keccak256(abi.encode(uint256(keccak256("sapien.storage.SapienCore")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0xb21037e32bd67da4126ec23c3d75228183c819f055709f5aa59aa33cc3fd2b00
        }
    }

    /// @notice Get reputation score with lazy decay applied
    function getScore(address user, bytes32 role) public view returns (uint256) {
        return getScoreCached(user, role, _getStorage().decayRateBps);
    }

    /// @notice Get reputation score with pre-cached decayRateBps (avoids redundant SLOAD in loops)
    function getScoreCached(address user, bytes32 role, uint256 cachedDecayBps) public view returns (uint256) {
        Reputation storage rep = _getStorage().reputation[user][role];
        if (rep.lastUpdated == 0) return C.DEFAULT_REPUTATION;

        uint256 score = rep.score;

        if (cachedDecayBps > 0) {
            uint256 elapsed = block.timestamp - rep.lastUpdated;
            if (elapsed >= 1 days) {
                uint256 decayAmount = Math.mulDiv(score * cachedDecayBps, elapsed / 1 days, C.BPS);
                score = score > decayAmount + C.MIN_REPUTATION ? score - decayAmount : C.MIN_REPUTATION;
            }
        }

        return score;
    }

    /// @notice Update reputation after an action (success or failure with optional bonus)
    function update(address user, bytes32 role, bool success, uint256 bonus) public {
        EngineStorage storage $ = _getStorage();
        Reputation storage rep = $.reputation[user][role];

        if (rep.lastUpdated == 0) {
            rep.score = C.DEFAULT_REPUTATION;
            rep.lastUpdated = block.timestamp;
        }

        uint256 currentScore = rep.score;

        if ($.decayRateBps > 0) {
            uint256 elapsed = block.timestamp - rep.lastUpdated;
            if (elapsed >= 1 days) {
                uint256 decayAmount = Math.mulDiv(currentScore * $.decayRateBps, elapsed / 1 days, C.BPS);
                currentScore =
                    currentScore > decayAmount + C.MIN_REPUTATION ? currentScore - decayAmount : C.MIN_REPUTATION;
            }
        }

        uint256 oldScore = currentScore;

        rep.totalActions++;

        if (success) {
            rep.successfulActions++;

            uint256 today = block.timestamp / 1 days;
            if (rep.dailyGainDate != today) {
                rep.dailyGain = 0;
                rep.dailyGainDate = today;
            }

            uint256 gain = C.SUCCESS_INCREASE + bonus;
            uint256 remainingCap = C.MAX_DAILY_GAIN > rep.dailyGain ? C.MAX_DAILY_GAIN - rep.dailyGain : 0;
            if (gain > remainingCap) {
                gain = remainingCap;
            }

            if (gain > 0) {
                currentScore = currentScore + gain > C.MAX_REPUTATION ? C.MAX_REPUTATION : currentScore + gain;
                rep.dailyGain += gain;
            }
        } else {
            uint256 penalty = C.REJECTION_DECREASE;
            currentScore = currentScore > penalty + C.MIN_REPUTATION ? currentScore - penalty : C.MIN_REPUTATION;
        }

        rep.score = currentScore;
        rep.lastUpdated = block.timestamp;

        if (currentScore != oldScore) {
            emit ISapienCore.ReputationUpdated(user, role, oldScore, currentScore);
        }
    }
}
