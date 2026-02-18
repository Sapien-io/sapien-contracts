// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Constants as C} from "src/Constants.sol";
import {IQualityEngine} from "src/interfaces/IQualityEngine.sol";
import {IStakeVault} from "src/interfaces/IStakeVault.sol";
import {ContributionLib} from "src/libraries/ContributionLib.sol";
import {DisputeLib} from "src/libraries/DisputeLib.sol";
import {FinalizationLib} from "src/libraries/FinalizationLib.sol";
import {OriginationLib} from "src/libraries/OriginationLib.sol";
import {ValidationLib} from "src/libraries/ValidationLib.sol";
import {
    EngineStorage,
    Project,
    Claim,
    IndexState,
    Contribution,
    ConsensusReport,
    Reputation,
    Dispute,
    DisputeStatus,
    OriginatorReport,
    OriginatorReportStatus
} from "src/Types.sol";

/**
 *     @title QualityEngine
 *     @notice Unified contract for Sapien PoQ v0.5
 *     - Project management, claims, contributions, validations, consensus, reputation, and reward distribution.
 *     - Deployed behind an ERC-1967 proxy.
 *     - Uses ERC-7201 namespaced storage with separate namespaces per logical module.
 *     - Only external call target is StakeVault for stake operations.
 */

contract QualityEngine is
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuard,
    UUPSUpgradeable,
    IQualityEngine
{
    // ════════════════════════════════════════════════════════════════════
    // ERC-7201 Namespaced Storage
    // ════════════════════════════════════════════════════════════════════

    // keccak256(abi.encode(uint256(keccak256("sapien.storage.QualityEngine")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0x93ae96f70dc96ca851a79b6bf630e034298e11be62b3174b3a3408302fc00900
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Initializer
    // ════════════════════════════════════════════════════════════════════

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin_, address vault_, address treasury_, address consensusAlgorithm_)
        external
        initializer
    {
        if (admin_ == address(0)) revert ZeroAddress();
        if (vault_ == address(0)) revert ZeroAddress();
        if (treasury_ == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __Pausable_init();

        // SEC-C-02: manually initialize ReentrancyGuard storage in the proxy.
        // OZ v5 ReentrancyGuard uses namespaced storage but only initializes via constructor
        // (which runs on the implementation, not the proxy). Set _status = NOT_ENTERED (1).
        bytes32 reentrancySlot = _reentrancyGuardStorageSlot();
        assembly {
            sstore(reentrancySlot, 1)
        }

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(C.OPERATOR_ROLE, admin_);

        EngineStorage storage $ = _getStorage();
        $.vault = IStakeVault(vault_);
        $.treasury = treasury_;
        $.consensusAlgorithm = consensusAlgorithm_;
        $.nextClaimId = 1;

        // Default fee configuration (all packed in 1 slot)
        $.protocolFeeBps = 100; // 1%
        $.originationFeeBps = 200; // 2%
        $.contributionFeeBps = 200; // 2%
        $.validationFeeBps = 200; // 2%
        $.decayRateBps = 10; // 0.1% per day

        // Default dispute configuration (packed in slot 1 and slot 3)
        $.disputeBondBps = 1000; // 10% of rewardRate
        $.originatorReportBondBps = 100; // 1% of totalRewards
        $.originatorStakeRequirement = 0; // disabled by default
    }

    // ════════════════════════════════════════════════════════════════════
    // Origintation
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc IQualityEngine
    function createProject(bytes32 projectId, Project calldata config) external whenNotPaused {
        OriginationLib.createProject(projectId, config);
    }

    /// @inheritdoc IQualityEngine
    function fundProject(bytes32 projectId, uint256 amount, uint256 quantity, address adapter)
        external
        whenNotPaused
        nonReentrant
    {
        OriginationLib.fundProject(projectId, amount, quantity, adapter);
    }

    // ════════════════════════════════════════════════════════════════════
    // Contribution
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc IQualityEngine
    function claimToContribute(bytes32 projectId, uint256 quantity, address adapter)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 claimId, uint256[] memory indices)
    {
        return ContributionLib.claimToContribute(projectId, quantity, adapter);
    }

    /// @inheritdoc IQualityEngine
    function contribute(uint256 claimId, uint256 index, bytes32 submissionHash) external whenNotPaused {
        ContributionLib.contribute(claimId, index, submissionHash);
    }

    /// @inheritdoc IQualityEngine
    function expireClaim(uint256 claimId, uint256[] calldata indices) external whenNotPaused nonReentrant {
        ContributionLib.expireClaim(claimId, indices);
    }

    // ════════════════════════════════════════════════════════════════════
    // Validation
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc IQualityEngine
    function setValidatorCapacity(uint256 amount) external whenNotPaused {
        ValidationLib.setValidatorCapacity(amount);
    }

    /// @inheritdoc IQualityEngine
    /// @dev H-04: Allows validators to reduce their committed capacity and unlock stake.
    function reduceValidatorCapacity(uint256 amount) external whenNotPaused {
        ValidationLib.reduceValidatorCapacity(amount);
    }

    // TODO: claimToContribute?

    /// @inheritdoc IQualityEngine
    function commitValidation(bytes32 projectId, uint256 index, bytes32 commitHash, uint128 stakeAmount)
        external
        whenNotPaused
        nonReentrant
    {
        ValidationLib.commitValidation(projectId, index, commitHash, stakeAmount);
    }

    /// @inheritdoc IQualityEngine
    function revealValidation(bytes32 projectId, uint256 index, uint16 score, bytes32 salt)
        external
        whenNotPaused
        nonReentrant
    {
        ValidationLib.revealValidation(projectId, index, score, salt);
    }

    // ════════════════════════════════════════════════════════════════════
    // Finalization — Phase 1: Compute Consensus
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc IQualityEngine
    function computeConsensus(bytes32 projectId, uint256 index) external whenNotPaused nonReentrant {
        ValidationLib.computeConsensus(projectId, index);
    }

    // ════════════════════════════════════════════════════════════════════
    // Finalization — Phase 2: Settle Validator
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc IQualityEngine
    function settleValidator(bytes32 projectId, uint256 index, uint256 nonce) external whenNotPaused nonReentrant {
        FinalizationLib.settleValidator(projectId, index, nonce);
    }

    /// @inheritdoc IQualityEngine
    function forceSettleValidator(bytes32 projectId, uint256 index, uint256 nonce, address validator)
        external
        whenNotPaused
        nonReentrant
    {
        FinalizationLib.forceSettleValidator(projectId, index, nonce, validator);
    }

    // ════════════════════════════════════════════════════════════════════
    // Finalization — Phase 3: Reward Claims
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc IQualityEngine
    function releaseContributorReward(bytes32 projectId, uint256 index) external whenNotPaused nonReentrant {
        FinalizationLib.releaseContributorReward(projectId, index);
    }

    /// @inheritdoc IQualityEngine
    function claimReward(address token) external whenNotPaused nonReentrant {
        FinalizationLib.claimReward(token);
    }

    // ════════════════════════════════════════════════════════════════════
    // Keeper Functions (Permissionless)
    // ════════════════════════════════════════════════════════════════════

    /// @notice Cancel an expired validation commitment and slash the ghost validator
    function cancelExpiredCommitment(bytes32 projectId, uint256 index, address validator)
        external
        whenNotPaused
        nonReentrant
    {
        FinalizationLib.cancelExpiredCommitment(projectId, index, validator);
    }

    // ════════════════════════════════════════════════════════════════════
    // Disputes — Consensus Outcome Challenges
    // ════════════════════════════════════════════════════════════════════

    /// @notice Open a dispute on a consensus outcome during the challenge period.
    function openDispute(bytes32 projectId, uint256 index, bytes32 evidenceHash) external whenNotPaused nonReentrant {
        DisputeLib.openDispute(projectId, index, evidenceHash);
    }

    /// @notice Resolve an open dispute. Operator reviews off-chain evidence and decides.
    function resolveDispute(bytes32 projectId, uint256 index, bool upheld)
        external
        onlyRole(C.OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.contributions[projectId][index].consensusNonce;
        if ($.disputes[projectId][index][nonce].status != DisputeStatus.Open) {
            revert DisputeNotOpen();
        }

        if (upheld) {
            DisputeLib.upholdDispute(projectId, index, nonce);
        } else {
            DisputeLib.rejectDispute(projectId, index, nonce);
        }

        emit DisputeResolved(projectId, index, upheld);
    }

    /// @notice Escalate an unresolved dispute after the resolution deadline.
    function escalateDispute(bytes32 projectId, uint256 index) external whenNotPaused nonReentrant {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.contributions[projectId][index].consensusNonce;
        Dispute storage dispute = $.disputes[projectId][index][nonce];
        if (dispute.status != DisputeStatus.Open) revert DisputeNotOpen();

        if (block.timestamp <= dispute.openedAt + C.DISPUTE_RESOLUTION_DEADLINE) {
            revert DisputeResolutionNotExpired();
        }

        DisputeLib.upholdDispute(projectId, index, nonce);

        emit DisputeEscalated(projectId, index);
    }

    // TODO: Do we need this? Can this be handled by the dispute system?
    // ════════════════════════════════════════════════════════════════════
    // Originator Accountability
    // ════════════════════════════════════════════════════════════════════

    /// @notice Report an originator for misconduct.
    function reportOriginator(bytes32 projectId, bytes32 evidenceHash) external whenNotPaused nonReentrant {
        DisputeLib.reportOriginator(projectId, evidenceHash);
    }

    /// @notice Resolve an originator misconduct report.
    function resolveOriginatorReport(bytes32 projectId, bool upheld)
        external
        onlyRole(C.OPERATOR_ROLE)
        whenNotPaused
        nonReentrant
    {
        if (_getStorage().originatorReports[projectId].status != OriginatorReportStatus.Open) {
            revert OriginatorReportNotOpen();
        }

        if (upheld) {
            DisputeLib.upholdOriginatorReport(projectId, true);
        } else {
            DisputeLib.rejectOriginatorReport(projectId);
        }

        emit OriginatorReportResolved(projectId, upheld);
    }

    /// @notice Escalate an unresolved originator report after the resolution deadline.
    function escalateOriginatorReport(bytes32 projectId) external whenNotPaused nonReentrant {
        EngineStorage storage $ = _getStorage();
        OriginatorReport storage report = $.originatorReports[projectId];
        if (report.status != OriginatorReportStatus.Open) revert OriginatorReportNotOpen();

        if (block.timestamp <= report.reportedAt + C.DISPUTE_RESOLUTION_DEADLINE) {
            revert DisputeResolutionNotExpired();
        }

        DisputeLib.upholdOriginatorReport(projectId, false);

        emit OriginatorReportEscalated(projectId);
        emit ProjectCancelled(projectId);
    }

    // ════════════════════════════════════════════════════════════════════
    // Project Completion (M-03)
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc IQualityEngine
    function completeProject(bytes32 projectId) external whenNotPaused nonReentrant {
        FinalizationLib.completeProject(projectId);
    }

    /// @inheritdoc IQualityEngine
    function refundEscrow(bytes32 projectId) external whenNotPaused nonReentrant {
        FinalizationLib.refundEscrow(projectId);
    }

    // ════════════════════════════════════════════════════════════════════
    // Admin Functions
    // ════════════════════════════════════════════════════════════════════

    function setProtocolFee(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_PROTOCOL_FEE_BPS) revert AdapterFeeTooHigh(bps, C.MAX_PROTOCOL_FEE_BPS);
        _getStorage().protocolFeeBps = uint16(bps);
        emit ProtocolFeeUpdated(bps);
    }

    function setOriginationFee(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_ADAPTER_FEE_BPS) revert AdapterFeeTooHigh(bps, C.MAX_ADAPTER_FEE_BPS);
        _getStorage().originationFeeBps = uint16(bps);
        emit OriginationFeeUpdated(bps);
    }

    function setContributionFee(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_ADAPTER_FEE_BPS) revert AdapterFeeTooHigh(bps, C.MAX_ADAPTER_FEE_BPS);
        _getStorage().contributionFeeBps = uint16(bps);
        emit ContributionFeeUpdated(bps);
    }

    function setValidationFee(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_ADAPTER_FEE_BPS) revert AdapterFeeTooHigh(bps, C.MAX_ADAPTER_FEE_BPS);
        _getStorage().validationFeeBps = uint16(bps);
        emit ValidationFeeUpdated(bps);
    }

    function setDecayRate(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_DECAY_RATE_BPS) revert AdapterFeeTooHigh(bps, C.MAX_DECAY_RATE_BPS);
        _getStorage().decayRateBps = uint16(bps);
        emit DecayRateUpdated(bps);
    }

    function setDisputeBondBps(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_DISPUTE_BOND_BPS) revert DisputeBondTooHigh(bps, C.MAX_DISPUTE_BOND_BPS);
        _getStorage().disputeBondBps = uint16(bps);
        emit DisputeBondBpsUpdated(bps);
    }

    function setOriginatorStakeRequirement(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount > type(uint128).max) revert InvalidProjectConfig("amount exceeds uint128");
        _getStorage().originatorStakeRequirement = uint128(amount);
        emit OriginatorStakeRequirementUpdated(amount);
    }

    function setOriginatorReportBondBps(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_ORIGINATOR_REPORT_BOND_BPS) revert AdapterFeeTooHigh(bps, C.MAX_ORIGINATOR_REPORT_BOND_BPS);
        _getStorage().originatorReportBondBps = uint16(bps);
        emit OriginatorReportBondBpsUpdated(bps);
    }

    function setMinValidationStake(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (amount > type(uint128).max) revert InvalidProjectConfig("amount exceeds uint128");
        _getStorage().minValidationStake = uint128(amount);
        emit MinValidationStakeUpdated(amount);
    }

    function setConsensusAlgorithm(address algorithm) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (algorithm == address(0)) revert ZeroAddress();
        _getStorage().consensusAlgorithm = algorithm;
        emit ConsensusAlgorithmUpdated(algorithm);
    }

    function setTreasury(address treasury_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury_ == address(0)) revert ZeroAddress();
        _getStorage().treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function setMinClaimAmount(uint64 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getStorage().minClaimAmount = amount;
        emit MinClaimAmountUpdated(amount);
    }

    function setClaimCooldown(uint64 cooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getStorage().claimCooldown = cooldown;
        emit ClaimCooldownUpdated(cooldown);
    }

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ════════════════════════════════════════════════════════════════════
    // View Functions
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc IQualityEngine
    function getProject(bytes32 projectId) external view returns (Project memory) {
        return _getStorage().projects[projectId];
    }

    /// @inheritdoc IQualityEngine
    function getClaim(uint256 claimId) external view returns (Claim memory) {
        return _getStorage().claims[claimId];
    }

    /// @notice Get the return stack top for a project (useful for debugging)
    function getReturnStackTop(bytes32 projectId) external view returns (uint256) {
        return _getStorage().returnStackTop[projectId];
    }

    /// @inheritdoc IQualityEngine
    function getIndexState(bytes32 projectId, uint256 index) external view returns (IndexState memory) {
        return _getStorage().indexStates[projectId][index];
    }

    /// @inheritdoc IQualityEngine
    function getContribution(bytes32 projectId, uint256 index) external view returns (Contribution memory) {
        return _getStorage().contributions[projectId][index];
    }

    /// @inheritdoc IQualityEngine
    function getReputation(address user, bytes32 role) external view returns (Reputation memory) {
        EngineStorage storage $ = _getStorage();
        Reputation memory rep = $.reputation[user][role];
        if (rep.lastUpdated == 0) {
            rep.score = uint64(C.DEFAULT_REPUTATION);
        }
        return rep;
    }

    /// @inheritdoc IQualityEngine
    function getPendingRewards(address user, address token) external view returns (uint256) {
        return _getStorage().pendingRewards[user][token];
    }

    /// @inheritdoc IQualityEngine
    function getAdapterFees()
        external
        view
        returns (uint256 originationBps, uint256 contributionBps, uint256 validationBps)
    {
        EngineStorage storage $ = _getStorage();
        return (uint256($.originationFeeBps), uint256($.contributionFeeBps), uint256($.validationFeeBps));
    }

    /// @inheritdoc IQualityEngine
    function getOriginationAdapter(bytes32 projectId) external view returns (address) {
        return _getStorage().originationAdapter[projectId];
    }

    /// @inheritdoc IQualityEngine
    function getContributionAdapter(uint256 claimId) external view returns (address) {
        return _getStorage().contributionAdapter[claimId];
    }

    /// @notice Get the current submission nonce for a project index
    function getSubmissionNonce(bytes32 projectId, uint256 index) external view returns (uint256) {
        return _getStorage().submissionNonce[projectId][index];
    }

    /// @notice Get consensus report data for a project index
    function getConsensusReport(bytes32 projectId, uint256 index) external view returns (ConsensusReport memory) {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.contributions[projectId][index].consensusNonce;
        return $.consensusReports[projectId][index][nonce];
    }

    /// @notice Check if a validator is an outlier for a given consensus
    function isValidatorOutlier(bytes32 projectId, uint256 index, address validator) external view returns (bool) {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.contributions[projectId][index].consensusNonce;
        return $.validatorConsensus[projectId][index][nonce][validator].isOutlier;
    }

    /// @notice Check if a validator has been settled for a given consensus (keyed by nonce per H-03)
    function isValidatorSettled(bytes32 projectId, uint256 index, uint256 nonce, address validator)
        external
        view
        returns (bool)
    {
        return _getStorage().validatorCommits[projectId][index][nonce][validator].settled;
    }

    /// @notice Get the vault address
    function vault() external view returns (address) {
        return address(_getStorage().vault);
    }

    /// @notice Get the treasury address
    function treasury() external view returns (address) {
        return _getStorage().treasury;
    }

    /// @notice Get the project escrow balance
    function getProjectEscrow(bytes32 projectId, address token) external view returns (uint256) {
        return _getStorage().projectEscrow[projectId][token];
    }

    /// @inheritdoc IQualityEngine
    function getDispute(bytes32 projectId, uint256 index) external view returns (Dispute memory) {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.contributions[projectId][index].consensusNonce;
        return $.disputes[projectId][index][nonce];
    }

    /// @inheritdoc IQualityEngine
    function getOriginatorReport(bytes32 projectId) external view returns (OriginatorReport memory) {
        return _getStorage().originatorReports[projectId];
    }

    /// @notice Get the originator's locked stake for a project
    function getOriginatorLockedStake(bytes32 projectId) external view returns (uint256) {
        return _getStorage().originatorLockedStake[projectId];
    }

    /// @notice Get the dispute configuration
    function getDisputeConfig()
        external
        view
        returns (uint256 disputeBondBps_, uint256 originatorStakeReq_, uint256 originatorReportBondBps_)
    {
        EngineStorage storage $ = _getStorage();
        return (uint256($.disputeBondBps), uint256($.originatorStakeRequirement), uint256($.originatorReportBondBps));
    }

    /// @notice Get the reveal count for a project index at the current nonce
    function getRevealCount(bytes32 projectId, uint256 index) external view returns (uint256) {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.submissionNonce[projectId][index];
        return uint256($.validationCounters[projectId][index][nonce].revealCount);
    }

    // ── UUPS ───────────────────────────────────────────────────────────

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
