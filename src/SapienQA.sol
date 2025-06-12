// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/**
 * @title SapienQA - Quality Assurance Management Contract
 * @notice Manages quality assurance decisions for the Sapien protocol through signature-based verification
 * @dev This contract handles QA assessments including warnings and penalties, using EIP-712 for secure
 *      off-chain decision authorization. It integrates with SapienVault to apply financial penalties
 *      while maintaining comprehensive audit trails of all QA actions.
 *
 * KEY FEATURES:
 * - EIP-712 signature verification for authorized QA decisions
 * - Multiple action types: warnings, minor penalties, major penalties, severe penalties
 * - Integration with SapienVault for penalty enforcement
 * - Comprehensive audit trail with detailed QA history per user
 * - Role-based access control for QA managers and signers
 * - Protection against replay attacks through unique decision IDs
 * - Graceful handling of insufficient stakes during penalty application
 *
 * WORKFLOW:
 * 1. QA team identifies quality issue requiring intervention
 * 2. Authorized signer creates EIP-712 signature for the QA decision
 * 3. QA manager calls processQualityAssessment() with decision details and signature
 * 4. Contract verifies signature authenticity and checks for replay attacks
 * 5. If penalty required, attempts to deduct from user's staked tokens via SapienVault
 * 6. Records complete QA decision in user's history regardless of penalty success
 * 7. Updates global statistics and emits relevant events
 *
 * SECURITY CONSIDERATIONS:
 * - All QA decisions require valid EIP-712 signatures from authorized signers
 * - Decision IDs prevent replay attacks and ensure one-time processing
 * - Signature expiration prevents stale decision execution
 * - Role separation between QA managers (executors) and QA signers (authorizers)
 * - Graceful degradation when penalties cannot be fully applied due to insufficient stakes
 */
import {ECDSA, EIP712Upgradeable, AccessControlUpgradeable} from "src/utils/Common.sol";

import {ISapienQA} from "./interfaces/ISapienQA.sol";
import {ISapienVault} from "./interfaces/ISapienVault.sol";
import {Constants as Const} from "src/utils/Constants.sol";

using ECDSA for bytes32;

contract SapienQA is ISapienQA, AccessControlUpgradeable, EIP712Upgradeable {
    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    address public treasury;
    address public vault;

    uint256 public totalPenalties;
    uint256 public totalWarnings;

    mapping(address => QARecord[]) private userQAHistory;
    mapping(bytes32 => bool) private processedDecisions;

    // -------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function version() public pure returns (string memory) {
        return Const.QA_VERSION;
    }

    /**
     * @notice Initializes the SapienQA contract
     * @param _treasury The treasury address
     * @param vaultContract The vault contract address
     * @param qaManager The QA manager address
     * @param qaSigner The QA signer address
     * @param admin The admin address
     */
    function initialize(address _treasury, address vaultContract, address qaManager, address qaSigner, address admin)
        public
        initializer
    {
        if (_treasury == address(0)) revert ZeroAddress();
        if (vaultContract == address(0)) revert ZeroAddress();
        if (qaManager == address(0)) revert ZeroAddress();
        if (qaSigner == address(0)) revert ZeroAddress();
        if (admin == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __EIP712_init("SapienQA", version());
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(Const.QA_MANAGER_ROLE, qaManager);
        _grantRole(Const.QA_SIGNER_ROLE, qaSigner);

        treasury = _treasury;
        vault = vaultContract;
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
        uint256 expiration,
        bytes calldata signature
    ) public onlyQaManager {
        // Step 1: Validate all inputs
        _validateQAInputs(userAddress, actionType, penaltyAmount, decisionId, reason);

        // Step 2: Verify signature authorization and expiration
        verifySignature(userAddress, actionType, penaltyAmount, decisionId, reason, expiration, signature);

        // Step 3: Mark decision as processed (prevents replay attacks)
        processedDecisions[decisionId] = true;

        // Step 4: Process penalty if required
        uint256 actualPenaltyApplied = _processPenaltyIfRequired(userAddress, penaltyAmount);

        // Step 5: Record the decision
        _recordQADecision(userAddress, actionType, actualPenaltyApplied, decisionId, reason);

        // Step 6: Update statistics
        if (actionType == QAActionType.WARNING) {
            totalWarnings++;
        } else if (actualPenaltyApplied > 0) {
            totalPenalties += actualPenaltyApplied;
        }

        // Step 7: Emit final event
        emit QualityAssessmentProcessed(userAddress, actionType, actualPenaltyApplied, decisionId, reason, msg.sender);
    }

    // -------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------

    /**
     * @notice Get complete QA history for a user
     * @param user The user's address
     * @return qaHistory Array of QA records for the user
     */
    function getUserQAHistory(address user) external view override returns (QARecord[] memory qaHistory) {
        return userQAHistory[user];
    }

    /**
     * @notice Get the number of QA records for a user
     * @param user The user's address
     * @return recordCount Number of QA records
     */
    function getUserQARecordCount(address user) external view override returns (uint256 recordCount) {
        return userQAHistory[user].length;
    }

    /**
     * @notice Check if a decision ID has been processed
     * @param decisionId The decision ID to check
     * @return isProcessed True if the decision has been processed
     */
    function isDecisionProcessed(bytes32 decisionId) external view override returns (bool isProcessed) {
        return processedDecisions[decisionId];
    }

    /**
     * @notice Get overall QA statistics
     * @return penaltiesTotal Total amount of penalties processed
     * @return warningsTotal Total number of warnings issued
     */
    function getQAStatistics() external view override returns (uint256 penaltiesTotal, uint256 warningsTotal) {
        return (totalPenalties, totalWarnings);
    }

    /**
     * @notice Returns the domain separator for EIP-712 signatures
     * @dev Used by external systems to verify they're building signatures for the correct contract/chain
     * @return domainSeparator The current domain separator
     */
    function getDomainSeparator() external view override returns (bytes32 domainSeparator) {
        return _domainSeparatorV4();
    }

    // -------------------------------------------------------------
    // Admin Functions
    // -------------------------------------------------------------

    /**
     * @notice Set the treasury address
     * @param newTreasury The new treasury address
     */
    function setTreasury(address newTreasury) external onlyAdmin {
        if (newTreasury == address(0)) revert ZeroAddress();

        address oldTreasury = treasury;
        treasury = newTreasury;

        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Set the vault contract address
     * @param newVaultContract The new vault contract address
     */
    function setVault(address newVaultContract) external onlyAdmin {
        if (newVaultContract == address(0)) revert ZeroAddress();

        address oldVault = vault;
        vault = newVaultContract;

        emit VaultContractUpdated(oldVault, newVaultContract);
    }

    // -------------------------------------------------------------
    // Internal Helper Functions
    // -------------------------------------------------------------

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

        if (actionType == QAActionType.WARNING) {
            if (penaltyAmount != 0) revert InvalidPenaltyForWarning();
        } else {
            if (penaltyAmount == 0) revert PenaltyAmountRequired();
        }
    }

    /**
     * @notice Process penalty if required, returning actual amount applied
     */
    function _processPenaltyIfRequired(address userAddress, uint256 penaltyAmount) private returns (uint256) {
        if (penaltyAmount == 0) {
            return 0;
        }

        try ISapienVault(vault).processQAPenalty(userAddress, penaltyAmount) returns (uint256 actualPenalty) {
            if (actualPenalty < penaltyAmount) {
                emit QAPenaltyPartial(userAddress, penaltyAmount, actualPenalty, Const.INSUFFICIENT_STAKE_REASON);
            }
            return actualPenalty;
        } catch Error(string memory reason) {
            emit QAPenaltyFailed(userAddress, penaltyAmount, reason);
            return 0;
        } catch {
            emit QAPenaltyFailed(userAddress, penaltyAmount, "Unknown error processing penalty");
            return 0;
        }
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
     * @notice Creates a hash of the QA decision parameters for EIP-712 signature verification
     * @param decisionId Unique identifier for the QA decision
     * @param user Address of the user being assessed
     * @param actionType Type of QA action (WARNING, MINOR_PENALTY, etc.)
     * @param penaltyAmount Amount to penalize (0 for warnings)
     * @param reason Human-readable reason for the assessment
     * @param expiration Timestamp when the signature expires
     * @return structHash The keccak256 hash of the encoded parameters
     */
    function createQADecisionHash(
        bytes32 decisionId,
        address user,
        uint8 actionType,
        uint256 penaltyAmount,
        string memory reason,
        uint256 expiration
    ) public pure returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                Const.QA_DECISION_TYPEHASH,
                user,
                actionType,
                penaltyAmount,
                decisionId,
                keccak256(bytes(reason)),
                expiration
            )
        );

        return structHash;
    }

    /**
     * @notice Verify EIP-712 signature for QA decision with expiration check
     * @param userAddress The user being assessed
     * @param actionType The type of QA action
     * @param penaltyAmount The penalty amount
     * @param decisionId The unique decision identifier
     * @param reason The reason for the assessment
     * @param expiration The expiration timestamp for the signature
     * @param signature The signature to verify from the QA admin
     */
    function verifySignature(
        address userAddress,
        QAActionType actionType,
        uint256 penaltyAmount,
        bytes32 decisionId,
        string calldata reason,
        uint256 expiration,
        bytes calldata signature
    ) public view {
        // Check signature expiration first
        if (block.timestamp > expiration) revert ExpiredSignature(expiration);

        if (signature.length != 65) revert InvalidSignatureLength();

        bytes32 structHash = keccak256(
            abi.encode(
                Const.QA_DECISION_TYPEHASH,
                userAddress,
                uint8(actionType),
                penaltyAmount,
                decisionId,
                keccak256(bytes(reason)),
                expiration
            )
        );

        bytes32 hash = _hashTypedDataV4(structHash);
        address signer = hash.recover(signature);

        if (!hasRole(Const.QA_SIGNER_ROLE, signer)) revert UnauthorizedSigner(signer);
    }
}
