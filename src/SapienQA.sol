// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {ECDSA, EIP712, IERC20, AccessControl} from "src/utils/Common.sol";

import {ISapienQA} from "./interfaces/ISapienQA.sol";
import {ISapienVault} from "./interfaces/ISapienVault.sol";
import {Constants as Const} from "src/utils/Constants.sol";

using ECDSA for bytes32;

/**
 * @title SapienQA
 * @notice Quality Assurance contract for processing user assessments with signature-based verification
 * @dev Uses EIP-712 for signature verification, similar to SapienRewards structure
 */
contract SapienQA is ISapienQA, AccessControl, EIP712 {
    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    address public treasury;
    address public vaultContract;

    uint256 public totalPenalties;
    uint256 public totalWarnings;

    mapping(address => QARecord[]) private userQAHistory;
    mapping(bytes32 => bool) private processedDecisions;

    // -------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------

    constructor(address _treasury, address _vaultContract, address qaManager, address admin) EIP712("SapienQA", "1") {
        _validateConstructorInputs(_treasury, _vaultContract, qaManager, admin);
        _initializeState(_treasury, _vaultContract);
        _setupRoles(qaManager, admin);
    }

    // -------------------------------------------------------------
    // Access Control Modifiers
    // -------------------------------------------------------------

    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, DEFAULT_ADMIN_ROLE);
        }
        _;
    }

    modifier onlyQaAdmin() {
        if (!hasRole(Const.QA_ADMIN_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, Const.QA_ADMIN_ROLE);
        }
        _;
    }

    modifier onlyQaManager() {
        if (!hasRole(Const.QA_MANAGER_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, Const.QA_MANAGER_ROLE);
        }
        _;
    }

    // -------------------------------------------------------------
    // Main Functions
    // -------------------------------------------------------------

    /**
     * @notice Process a quality assessment decision with signature verification
     * @param userAddress The address of the user being assessed
     * @param actionType The type of QA action (WARNING, MINOR_PENALTY, etc.)
     * @param penaltyAmount The amount to penalize (0 for warnings)
     * @param decisionId Unique identifier for this decision (prevents replay attacks)
     * @param reason Human-readable reason for the assessment
     * @param signature EIP-712 signature from authorized signer
     */
    function processQualityAssessment(
        address userAddress,
        QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string calldata reason,
        bytes calldata signature
    ) public onlyQaManager {
        // Step 1: Validate all inputs
        _validateQAInputs(userAddress, actionType, penaltyAmount, decisionId, reason);

        // Step 2: Verify signature authorization
        _verifySignature(userAddress, actionType, penaltyAmount, decisionId, reason, signature);

        // Step 3: Mark decision as processed (prevents replay attacks)
        _markDecisionProcessed(decisionId);

        // Step 4: Process penalty if required
        uint256 actualPenaltyApplied = _processPenaltyIfRequired(userAddress, penaltyAmount);

        // Step 5: Record the decision
        _recordQADecision(userAddress, actionType, actualPenaltyApplied, decisionId, reason);

        // Step 6: Update statistics
        _updateStatistics(actionType, actualPenaltyApplied);

        // Step 7: Emit final event
        emit QualityAssessmentProcessed(userAddress, actionType, actualPenaltyApplied, decisionId, reason, msg.sender);
    }

    // -------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------

    /**
     * @notice Get complete QA history for a user
     * @param userAddress The user's address
     * @return Array of QA records for the user
     */
    function getUserQAHistory(address userAddress) external view override returns (QARecord[] memory) {
        return userQAHistory[userAddress];
    }

    /**
     * @notice Get the number of QA records for a user
     * @param userAddress The user's address
     * @return Number of QA records
     */
    function getUserQARecordCount(address userAddress) external view override returns (uint256) {
        return userQAHistory[userAddress].length;
    }

    /**
     * @notice Check if a decision ID has been processed
     * @param decisionId The decision ID to check
     * @return True if the decision has been processed
     */
    function isDecisionProcessed(bytes32 decisionId) external view override returns (bool) {
        return processedDecisions[decisionId];
    }

    /**
     * @notice Get overall QA statistics
     * @return totalPenalties Total amount of penalties processed
     * @return totalWarnings Total number of warnings issued
     */
    function getQAStatistics() external view override returns (uint256, uint256) {
        return (totalPenalties, totalWarnings);
    }

    // -------------------------------------------------------------
    // Admin Functions
    // -------------------------------------------------------------

    /**
     * @notice Update the treasury address
     * @param newTreasury The new treasury address
     */
    function updateTreasury(address newTreasury) external onlyAdmin {
        if (newTreasury == address(0)) revert ZeroAddress();

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Update the vault contract address
     * @param newVaultContract The new vault contract address
     */
    function updateVaultContract(address newVaultContract) external onlyAdmin {
        if (newVaultContract == address(0)) revert ZeroAddress();

        address oldVault = vaultContract;
        vaultContract = newVaultContract;

        emit VaultContractUpdated(oldVault, newVaultContract);
    }

    // -------------------------------------------------------------
    // Internal Helper Functions
    // -------------------------------------------------------------

    /**
     * @notice Validate constructor inputs
     */
    function _validateConstructorInputs(address _treasury, address _vaultContract, address qaManager, address admin)
        private
        pure
    {
        if (_treasury == address(0)) revert ZeroAddress();
        if (_vaultContract == address(0)) revert ZeroAddress();
        if (qaManager == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();
    }

    /**
     * @notice Initialize contract state variables
     */
    function _initializeState(address _treasury, address _vaultContract) private {
        treasury = _treasury;
        vaultContract = _vaultContract;
    }

    /**
     * @notice Setup access control roles
     */
    function _setupRoles(address qaManager, address admin) private {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(Const.QA_MANAGER_ROLE, qaManager);
    }

    /**
     * @notice Validate all QA assessment inputs
     */
    function _validateQAInputs(
        address userAddress,
        QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string calldata reason
    ) private view {
        if (userAddress == address(0)) revert ZeroAddress();
        if (decisionId == bytes32(0)) revert InvalidDecisionId();
        if (processedDecisions[decisionId]) revert DecisionAlreadyProcessed();
        if (bytes(reason).length == 0) revert EmptyReason();

        _validatePenaltyAmount(actionType, penaltyAmount);
    }

    /**
     * @notice Validate penalty amount based on action type
     */
    function _validatePenaltyAmount(QAActionType actionType, uint256 penaltyAmount) private pure {
        if (actionType == QAActionType.WARNING) {
            if (penaltyAmount != 0) revert InvalidPenaltyForWarning();
        } else {
            if (penaltyAmount == 0) revert PenaltyAmountRequired();
        }
    }

    /**
     * @notice Mark a decision as processed to prevent replay attacks
     */
    function _markDecisionProcessed(bytes32 decisionId) private {
        processedDecisions[decisionId] = true;
    }

    /**
     * @notice Process penalty if required, returning actual amount applied
     */
    function _processPenaltyIfRequired(address userAddress, uint256 penaltyAmount) private returns (uint256) {
        if (penaltyAmount == 0) {
            return 0;
        }

        try ISapienVault(vaultContract).processQAPenalty(userAddress, penaltyAmount) returns (uint256 actualPenalty) {
            return _handleSuccessfulPenalty(userAddress, penaltyAmount, actualPenalty);
        } catch Error(string memory errorReason) {
            _handlePenaltyError(userAddress, penaltyAmount, errorReason);
            return 0;
        } catch {
            _handlePenaltyError(userAddress, penaltyAmount, Const.UNKNOWN_PENALTY_ERROR);
            return 0;
        }
    }

    /**
     * @notice Handle successful penalty processing
     */
    function _handleSuccessfulPenalty(address userAddress, uint256 requestedAmount, uint256 actualAmount)
        private
        returns (uint256)
    {
        if (actualAmount < requestedAmount) {
            emit QAPenaltyPartial(userAddress, requestedAmount, actualAmount, Const.INSUFFICIENT_STAKE_REASON);
        }
        return actualAmount;
    }

    /**
     * @notice Handle penalty processing errors
     */
    function _handlePenaltyError(address userAddress, uint256 penaltyAmount, string memory errorReason) private {
        emit QAPenaltyFailed(userAddress, penaltyAmount, errorReason);
    }

    /**
     * @notice Record the QA decision in user history
     */
    function _recordQADecision(
        address userAddress,
        QAActionType actionType,
        uint256 actualPenaltyApplied,
        bytes32 decisionId,
        string calldata reason
    ) private {
        QARecord memory record = QARecord({
            actionType: actionType,
            penaltyAmount: actualPenaltyApplied,
            decisionId: decisionId,
            reason: reason,
            timestamp: block.timestamp,
            processor: msg.sender
        });

        userQAHistory[userAddress].push(record);
    }

    /**
     * @notice Update contract statistics based on action type and penalty applied
     */
    function _updateStatistics(QAActionType actionType, uint256 actualPenaltyApplied) private {
        if (actionType == QAActionType.WARNING) {
            totalWarnings++;
        } else if (actualPenaltyApplied > 0) {
            totalPenalties += actualPenaltyApplied;
        }
    }

    /**
     * @notice Verify EIP-712 signature for QA decision
     * @param userAddress The user being assessed
     * @param actionType The type of QA action
     * @param penaltyAmount The penalty amount
     * @param decisionId The unique decision identifier
     * @param reason The reason for the assessment
     * @param signature The signature to verify from the QA admin
     */
    function _verifySignature(
        address userAddress,
        QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string calldata reason,
        bytes calldata signature
    ) internal view {
        if (signature.length != 65) revert InvalidSignatureLength();

        bytes32 structHash = keccak256(
            abi.encode(
                Const.QA_DECISION_TYPEHASH,
                userAddress,
                uint8(actionType),
                penaltyAmount,
                decisionId,
                keccak256(bytes(reason))
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);

        if (!hasRole(Const.QA_ADMIN_ROLE, signer)) revert UnauthorizedSigner(signer);
    }
}
