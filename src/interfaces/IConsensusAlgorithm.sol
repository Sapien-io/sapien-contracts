// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ValidationInput, ConsensusResult} from "src/Types.sol";

/// @title IConsensusAlgorithm
/// @notice Interface for pluggable consensus algorithms
/// @dev Implementations are called via staticcall during consensus computation
interface IConsensusAlgorithm {
    /// @notice Calculate consensus from an array of validation inputs
    /// @param inputs Array of validator scores, stakes, and reputations
    /// @return result The consensus result containing weighted average, outlier detection, slash amounts, and weights
    function calculate(ValidationInput[] calldata inputs) external pure returns (ConsensusResult memory result);
}
