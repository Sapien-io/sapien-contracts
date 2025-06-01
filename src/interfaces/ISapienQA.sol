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

    // -------------------------------------------------------------
    // Functions
    // -------------------------------------------------------------

    function processQualityAssessment(
        address userAddress,
        QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string calldata reason,
        bytes calldata signature
    ) external;

    function getUserQAHistory(address userAddress) external view returns (QARecord[] memory);
    function getUserQARecordCount(address userAddress) external view returns (uint256);
    function isDecisionProcessed(bytes32 decisionId) external view returns (bool);
    function getQAStatistics() external view returns (uint256 totalPenalties, uint256 totalWarnings);
}
