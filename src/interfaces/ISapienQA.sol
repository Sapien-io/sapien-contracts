// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

interface ISapienQA {
    // -------------------------------------------------------------
    // Enums
    // -------------------------------------------------------------

    enum QAActionType {
        WARNING, // No penalty, just a warning
        MINOR_PENALTY, // Small penalty (1-5% of stake)
        MAJOR_PENALTY, // Medium penalty (5-15% of stake)
        SEVERE_PENALTY // Large penalty (15-25% of stake)

    }

    // -------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------

    struct QARecord {
        QAActionType actionType;
        uint256 penaltyAmount;
        bytes32 decisionId;
        string reason;
        uint256 timestamp;
        address processor;
    }

    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    event QualityAssessmentProcessed(
        address indexed userAddress,
        QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string reason,
        address processor
    );

    event TreasuryUpdated(address oldTreasury, address newTreasury);
    event VaultContractUpdated(address oldVault, address newVault);
    event QAPenaltyFailed(address userAddress, uint256 amount, string reason);
    event QAPenaltyPartial(address indexed userAddress, uint256 requestedAmount, uint256 actualAmount, string reason);

    // -------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------

    error ZeroAddress();
    error InvalidDecisionId();
    error DecisionAlreadyProcessed();
    error EmptyReason();
    error UnauthorizedSigner(address signer);
    error UnauthorizedCaller();
    error InvalidAmount();
    error InvalidPenaltyForWarning();
    error PenaltyAmountRequired();
    error InvalidSignatureLength();
    error InvalidSignatureV();
    error InvalidSignature();
    error ExpiredSignature(uint256 expiration);

    // -------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------

    function createQADecisionHash(
        bytes32 decisionId,
        address user,
        uint8 actionType,
        uint256 penaltyAmount,
        string memory reason,
        uint256 expiration
    ) external pure returns (bytes32);

    function version() external view returns (string memory);

    function processQualityAssessment(
        address userAddress,
        QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string calldata reason,
        uint256 expiration,
        bytes calldata signature
    ) external;

    function getDomainSeparator() external view returns (bytes32);
    function getUserQAHistory(address userAddress) external view returns (QARecord[] memory);
    function getUserQARecordCount(address userAddress) external view returns (uint256);
    function isDecisionProcessed(bytes32 decisionId) external view returns (bool);
    function getQAStatistics() external view returns (uint256 totalPenalties, uint256 totalWarnings);
}
