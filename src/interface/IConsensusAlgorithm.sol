// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IConsensusAlgorithm
 * @author Sapien Team
 * @notice Interface for pluggable consensus algorithms
 * @dev Implementations calculate weighted consensus from validator inputs
 */
interface IConsensusAlgorithm {
    // ============================================
    // STRUCTS
    // ============================================

    struct ValidationInput {
        address validator;
        uint256 score; // 0-10000 (0-100%)
        uint256 stakeAmount; // Amount staked by validator
        uint256 reputation; // 0-10000 from SapienPoQ
    }

    struct ConsensusResult {
        uint256 weightedAverage; // Final consensus score (0-10000)
        uint256 stdDev; // Standard deviation
        address[] validatorsToSlash; // Validators identified as outliers
        uint256[] slashAmounts; // Corresponding slash amounts
        uint256[] validatorWeights; // Weight assigned to each validator
    }

    // ============================================
    // ERRORS
    // ============================================

    error NoValidations();
    error InvalidScore(uint256 score);
    error InvalidStakeAmount();
    error InvalidReputation(uint256 reputation);

    // ============================================
    // CORE FUNCTIONS
    // ============================================

    /**
     * @notice Calculate consensus from validator inputs
     * @param validations Array of validator inputs
     * @return result Consensus calculation result
     */
    function calculateConsensus(ValidationInput[] calldata validations)
        external
        view
        returns (ConsensusResult memory result);

    /**
     * @notice Get algorithm name
     * @return Algorithm identifier
     */
    function getName() external pure returns (string memory);

    /**
     * @notice Get security grade based on vulnerability analysis
     * @return Security grade (A-, B+, C+, etc.)
     */
    function getSecurityGrade() external pure returns (string memory);

    /**
     * @notice Get algorithm description
     * @return Human-readable description
     */
    function getDescription() external pure returns (string memory);
}
