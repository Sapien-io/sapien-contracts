// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Constants as C} from "src/Constants.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {ContributionLib} from "src/libraries/ContributionLib.sol";
import {DisputeLib} from "src/libraries/DisputeLib.sol";
import {FinalizationLib} from "src/libraries/FinalizationLib.sol";
import {OriginationLib} from "src/libraries/OriginationLib.sol";
import {ValidationLib} from "src/libraries/ValidationLib.sol";
import {
    EngineStorage,
    Project,
    Claim,
    Contribution,
    ConsensusReport,
    Reputation,
    Dispute,
    DisputeStatus,
    OriginatorReport,
    OriginatorReportStatus,
    ValidationClaim
} from "src/Types.sol";

/**
 *     @title SapienCore
 *     @notice Unified contract for Sapien PoQ protocol
 *     - Project management, claims, contributions, validations, consensus, reputation, and reward distribution.
 *     - Deployed behind an ERC-1967 proxy.
 *     - Uses ERC-7201 namespaced storage with separate namespaces per logical module.
 *     - Only external call target is SapienVault for stake operations.
 */

contract SapienCore is
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ISapienCore
{
    // ════════════════════════════════════════════════════════════════════
    // ERC-7201 Namespaced Storage
    // ════════════════════════════════════════════════════════════════════

    // keccak256(abi.encode(uint256(keccak256("sapien.storage.SapienCore")) - 1)) & ~bytes32(uint256(0xff))
    function _getStorage() private pure returns (EngineStorage storage $) {
        assembly {
            $.slot := 0xb21037e32bd67da4126ec23c3d75228183c819f055709f5aa59aa33cc3fd2b00
        }
    }

    // ════════════════════════════════════════════════════════════════════
    // Initializer
    // ════════════════════════════════════════════════════════════════════

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address admin_, address vault_, address treasury_) external initializer {
        if (admin_ == address(0)) revert ZeroAddress();
        if (vault_ == address(0)) revert ZeroAddress();
        if (treasury_ == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _grantRole(C.OPERATOR_ROLE, admin_);

        EngineStorage storage $ = _getStorage();
        $.vault = ISapienVault(vault_);
        $.treasury = treasury_;
        $.nextClaimId = 1;
        $.nextValidationClaimId = 1;

        $.protocolFeeBps = 1000; // 10%
        $.originationFeeBps = 400; // 4%
        $.contributionFeeBps = 300; // 3%
        $.validationFeeBps = 300; // 3%
        $.decayRateBps = 10; // 0.1% per day

        $.disputeBondBps = 1000; // 10% of rewardRate
        $.originatorReportBondBps = 100; // 1% of totalRewards
        $.originatorStakeRequirement = 0; // disabled by default

        // Configurable deadlines (default to constants)
        $.claimDeadline = C.DEFAULT_CLAIM_DEADLINE;
        $.challengePeriod = C.DEFAULT_CHALLENGE_PERIOD;
        $.commitDeadline = C.DEFAULT_COMMIT_DEADLINE;
        $.revealDeadline = C.DEFAULT_REVEAL_DEADLINE;
        $.forceSettleDelay = C.DEFAULT_FORCE_SETTLE_DELAY;
    }

    // ════════════════════════════════════════════════════════════════════
    // Origination
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc ISapienCore
    function createProject(bytes32 projectId, string calldata metadataCid, Project calldata config)
        external
        whenNotPaused
    {
        OriginationLib.createProject(projectId, metadataCid, config);
    }

    /// @inheritdoc ISapienCore
    function fundProject(bytes32 projectId, uint256 amount, uint256 quantity, address adapter)
        external
        whenNotPaused
        nonReentrant
    {
        OriginationLib.fundProject(projectId, amount, quantity, adapter);
    }

    /// @inheritdoc ISapienCore
    function removeProject(bytes32 projectId) external onlyRole(C.OPERATOR_ROLE) whenNotPaused nonReentrant {
        OriginationLib.removeProject(projectId);
    }

    // ════════════════════════════════════════════════════════════════════
    // Contribution
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc ISapienCore
    function claimToContribute(bytes32 projectId, uint256 quantity, address adapter)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 claimId, uint256[] memory indices)
    {
        return ContributionLib.claimToContribute(projectId, quantity, adapter);
    }

    /// @inheritdoc ISapienCore
    function contribute(uint256 claimId, uint256 index, bytes32 submissionHash, string calldata dataCid)
        external
        whenNotPaused
    {
        ContributionLib.contribute(claimId, index, submissionHash, dataCid);
    }

    /// @inheritdoc ISapienCore
    function batchContribute(
        uint256 claimId,
        uint256[] calldata indices,
        bytes32[] calldata submissionHashes,
        string[] calldata dataCids
    ) external whenNotPaused {
        ContributionLib.batchContribute(claimId, indices, submissionHashes, dataCids);
    }

    /// @inheritdoc ISapienCore
    function expireClaim(uint256 claimId, uint256[] calldata indices) external whenNotPaused nonReentrant {
        ContributionLib.expireClaim(claimId, indices);
    }

    // ════════════════════════════════════════════════════════════════════
    // Validation
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc ISapienCore
    function lockValidatorCapacity(uint256 amount) external whenNotPaused {
        ValidationLib.lockValidatorCapacity(amount);
    }

    /// @inheritdoc ISapienCore
    function unlockValidatorCapacity(uint256 amount) external whenNotPaused {
        ValidationLib.unlockValidatorCapacity(amount);
    }

    /// @inheritdoc ISapienCore
    function claimToValidate(bytes32 projectId, uint256[] calldata indices)
        external
        whenNotPaused
        nonReentrant
        returns (uint256 claimId)
    {
        return ValidationLib.claimToValidate(projectId, indices);
    }

    /// @inheritdoc ISapienCore
    function commitValidation(
        bytes32 projectId,
        uint256 index,
        bytes32 commitHash,
        uint256 stakeAmount,
        address adapter
    ) external whenNotPaused nonReentrant {
        ValidationLib.commitValidation(projectId, index, commitHash, stakeAmount, adapter);
    }

    /// @inheritdoc ISapienCore
    function batchCommitValidations(
        bytes32 projectId,
        uint256[] calldata indices,
        bytes32[] calldata commitHashes,
        uint256[] calldata stakeAmounts,
        address adapter
    ) external whenNotPaused nonReentrant {
        ValidationLib.batchCommitValidations(projectId, indices, commitHashes, stakeAmounts, adapter);
    }

    /// @inheritdoc ISapienCore
    function revealValidation(bytes32 projectId, uint256 index, uint256 score, bytes32 salt)
        external
        whenNotPaused
        nonReentrant
    {
        ValidationLib.revealValidation(projectId, index, score, salt);
    }

    /// @inheritdoc ISapienCore
    function batchRevealValidations(
        bytes32 projectId,
        uint256[] calldata indices,
        uint256[] calldata scores,
        bytes32[] calldata salts
    ) external whenNotPaused nonReentrant {
        ValidationLib.batchRevealValidations(projectId, indices, scores, salts);
    }

    /// @inheritdoc ISapienCore
    function cancelExpiredValidationClaim(uint256 claimId) external whenNotPaused nonReentrant {
        ValidationLib.cancelExpiredValidationClaim(claimId);
    }

    // ════════════════════════════════════════════════════════════════════
    // Finalization — Phase 1: Compute Consensus
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc ISapienCore
    function computeConsensus(bytes32 projectId, uint256 index) external whenNotPaused nonReentrant {
        ValidationLib.computeConsensus(projectId, index);
    }

    // ════════════════════════════════════════════════════════════════════
    // Finalization — Phase 2: Settle Validator
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc ISapienCore
    function settleValidator(bytes32 projectId, uint256 index, uint256 nonce) external whenNotPaused nonReentrant {
        FinalizationLib.settleValidator(projectId, index, nonce);
    }

    /// @inheritdoc ISapienCore
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

    /// @inheritdoc ISapienCore
    function releaseContributorReward(bytes32 projectId, uint256 index) external whenNotPaused nonReentrant {
        FinalizationLib.releaseContributorReward(projectId, index);
    }

    /// @inheritdoc ISapienCore
    function claimReward(address token) external whenNotPaused nonReentrant {
        FinalizationLib.claimReward(token);
    }

    // ════════════════════════════════════════════════════════════════════
    // Keeper Functions (Permissionless)
    // ════════════════════════════════════════════════════════════════════

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

    function openDispute(bytes32 projectId, uint256 index, bytes32 evidenceHash, string calldata evidenceCid)
        external
        whenNotPaused
        nonReentrant
    {
        DisputeLib.openDispute(projectId, index, evidenceHash, evidenceCid);
    }

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
    }

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

    // ════════════════════════════════════════════════════════════════════
    // Originator Accountability
    // ════════════════════════════════════════════════════════════════════

    function reportOriginator(bytes32 projectId, bytes32 evidenceHash) external whenNotPaused nonReentrant {
        DisputeLib.reportOriginator(projectId, evidenceHash);
    }

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
    }

    function escalateOriginatorReport(bytes32 projectId) external whenNotPaused nonReentrant {
        EngineStorage storage $ = _getStorage();
        OriginatorReport storage report = $.originatorReports[projectId];
        if (report.status != OriginatorReportStatus.Open) revert OriginatorReportNotOpen();

        if (block.timestamp <= report.reportedAt + C.DISPUTE_RESOLUTION_DEADLINE) {
            revert DisputeResolutionNotExpired();
        }

        DisputeLib.upholdOriginatorReport(projectId, false);

        emit OriginatorReportEscalated(projectId);
    }

    // ════════════════════════════════════════════════════════════════════
    // Project Completion
    // ════════════════════════════════════════════════════════════════════

    /// @inheritdoc ISapienCore
    function completeProject(bytes32 projectId) external whenNotPaused nonReentrant {
        FinalizationLib.completeProject(projectId);
    }

    /// @inheritdoc ISapienCore
    function refundEscrow(bytes32 projectId) external whenNotPaused nonReentrant {
        FinalizationLib.refundEscrow(projectId);
    }

    // ════════════════════════════════════════════════════════════════════
    // Admin Functions
    // ════════════════════════════════════════════════════════════════════

    function setProtocolFee(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_PROTOCOL_FEE_BPS) revert AdapterFeeTooHigh(bps, C.MAX_PROTOCOL_FEE_BPS);
        _getStorage().protocolFeeBps = bps;
        emit ProtocolFeeUpdated(bps);
    }

    function setOriginationFee(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_ADAPTER_FEE_BPS) revert AdapterFeeTooHigh(bps, C.MAX_ADAPTER_FEE_BPS);
        _getStorage().originationFeeBps = bps;
        emit OriginationFeeUpdated(bps);
    }

    function setContributionFee(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_ADAPTER_FEE_BPS) revert AdapterFeeTooHigh(bps, C.MAX_ADAPTER_FEE_BPS);
        _getStorage().contributionFeeBps = bps;
        emit ContributionFeeUpdated(bps);
    }

    function setValidationFee(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_ADAPTER_FEE_BPS) revert AdapterFeeTooHigh(bps, C.MAX_ADAPTER_FEE_BPS);
        _getStorage().validationFeeBps = bps;
        emit ValidationFeeUpdated(bps);
    }

    function setDecayRate(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_DECAY_RATE_BPS) revert AdapterFeeTooHigh(bps, C.MAX_DECAY_RATE_BPS);
        _getStorage().decayRateBps = bps;
        emit DecayRateUpdated(bps);
    }

    function setDisputeBondBps(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_DISPUTE_BOND_BPS) revert DisputeBondTooHigh(bps, C.MAX_DISPUTE_BOND_BPS);
        _getStorage().disputeBondBps = bps;
        emit DisputeBondBpsUpdated(bps);
    }

    function setOriginatorStakeRequirement(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getStorage().originatorStakeRequirement = amount;
        emit OriginatorStakeRequirementUpdated(amount);
    }

    function setOriginatorReportBondBps(uint256 bps) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (bps > C.MAX_ORIGINATOR_REPORT_BOND_BPS) revert AdapterFeeTooHigh(bps, C.MAX_ORIGINATOR_REPORT_BOND_BPS);
        _getStorage().originatorReportBondBps = bps;
        emit OriginatorReportBondBpsUpdated(bps);
    }

    function setMinValidationStake(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getStorage().minValidationStake = amount;
        emit MinValidationStakeUpdated(amount);
    }

    function setTreasury(address treasury_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (treasury_ == address(0)) revert ZeroAddress();
        _getStorage().treasury = treasury_;
        emit TreasuryUpdated(treasury_);
    }

    function setMinClaimAmount(uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getStorage().minClaimAmount = amount;
        emit MinClaimAmountUpdated(amount);
    }

    function setClaimCooldown(uint256 cooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getStorage().claimCooldown = cooldown;
        emit ClaimCooldownUpdated(cooldown);
    }

    function setClaimDeadline(uint256 deadline) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (deadline < C.MIN_CLAIM_DEADLINE) revert DeadlineTooShort(deadline, C.MIN_CLAIM_DEADLINE);
        if (deadline > C.MAX_CLAIM_DEADLINE) revert DeadlineTooLong(deadline, C.MAX_CLAIM_DEADLINE);
        _getStorage().claimDeadline = deadline;
        emit ClaimDeadlineUpdated(deadline);
    }

    function setChallengePeriod(uint256 period) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (period < C.MIN_CHALLENGE_PERIOD) revert DeadlineTooShort(period, C.MIN_CHALLENGE_PERIOD);
        if (period > C.MAX_CHALLENGE_PERIOD) revert DeadlineTooLong(period, C.MAX_CHALLENGE_PERIOD);
        _getStorage().challengePeriod = period;
        emit ChallengePeriodUpdated(period);
    }

    function setCommitDeadline(uint256 deadline) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (deadline < C.MIN_COMMIT_DEADLINE) revert DeadlineTooShort(deadline, C.MIN_COMMIT_DEADLINE);
        if (deadline > C.MAX_COMMIT_DEADLINE) revert DeadlineTooLong(deadline, C.MAX_COMMIT_DEADLINE);
        _getStorage().commitDeadline = deadline;
        emit CommitDeadlineUpdated(deadline);
    }

    function setRevealDeadline(uint256 deadline) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (deadline < C.MIN_REVEAL_DEADLINE) revert DeadlineTooShort(deadline, C.MIN_REVEAL_DEADLINE);
        if (deadline > C.MAX_REVEAL_DEADLINE) revert DeadlineTooLong(deadline, C.MAX_REVEAL_DEADLINE);
        _getStorage().revealDeadline = deadline;
        emit RevealDeadlineUpdated(deadline);
    }

    function setForceSettleDelay(uint256 delay) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (delay < C.MIN_FORCE_SETTLE_DELAY) revert DeadlineTooShort(delay, C.MIN_FORCE_SETTLE_DELAY);
        if (delay > C.MAX_FORCE_SETTLE_DELAY) revert DeadlineTooLong(delay, C.MAX_FORCE_SETTLE_DELAY);
        _getStorage().forceSettleDelay = delay;
        emit ForceSettleDelayUpdated(delay);
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

    /// @inheritdoc ISapienCore
    function getProject(bytes32 projectId) external view returns (Project memory) {
        return _getStorage().projects[projectId];
    }

    /// @inheritdoc ISapienCore
    function getClaim(uint256 claimId) external view returns (Claim memory) {
        return _getStorage().claims[claimId];
    }

    /// @inheritdoc ISapienCore
    function getValidationClaim(uint256 claimId) external view returns (ValidationClaim memory) {
        return _getStorage().validationClaims[claimId];
    }

    function getReturnStackTop(bytes32 projectId) external view returns (uint256) {
        return _getStorage().returnStackTop[projectId];
    }

    /// @inheritdoc ISapienCore
    function getContribution(bytes32 projectId, uint256 index) external view returns (Contribution memory) {
        return _getStorage().contributions[projectId][index];
    }

    /// @inheritdoc ISapienCore
    function getReputation(address user, bytes32 role) external view returns (Reputation memory) {
        EngineStorage storage $ = _getStorage();
        Reputation memory rep = $.reputation[user][role];
        if (rep.lastUpdated == 0) {
            rep.score = C.DEFAULT_REPUTATION;
        }
        return rep;
    }

    /// @inheritdoc ISapienCore
    function getPendingRewards(address user, address token) external view returns (uint256) {
        return _getStorage().pendingRewards[user][token];
    }

    /// @inheritdoc ISapienCore
    function getAdapterFees()
        external
        view
        returns (uint256 originationBps, uint256 contributionBps, uint256 validationBps)
    {
        EngineStorage storage $ = _getStorage();
        return ($.originationFeeBps, $.contributionFeeBps, $.validationFeeBps);
    }

    /// @inheritdoc ISapienCore
    function getOriginationAdapter(bytes32 projectId) external view returns (address) {
        return _getStorage().originationAdapter[projectId];
    }

    /// @inheritdoc ISapienCore
    function getContributionAdapter(uint256 claimId) external view returns (address) {
        return _getStorage().contributionAdapter[claimId];
    }

    /// @inheritdoc ISapienCore
    function getValidationAdapter(bytes32 projectId, uint256 index, uint256 nonce, address validator)
        external
        view
        returns (address)
    {
        return _getStorage().validatorCommits[projectId][index][nonce][validator].adapter;
    }

    function getSubmissionNonce(bytes32 projectId, uint256 index) external view returns (uint256) {
        return _getStorage().submissionNonce[projectId][index];
    }

    function getConsensusReport(bytes32 projectId, uint256 index) external view returns (ConsensusReport memory) {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.contributions[projectId][index].consensusNonce;
        return $.consensusReports[projectId][index][nonce];
    }

    function isValidatorOutlier(bytes32 projectId, uint256 index, address validator) external view returns (bool) {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.contributions[projectId][index].consensusNonce;
        return $.validatorConsensus[projectId][index][nonce][validator].isOutlier;
    }

    function isValidatorSettled(bytes32 projectId, uint256 index, uint256 nonce, address validator)
        external
        view
        returns (bool)
    {
        return _getStorage().validatorCommits[projectId][index][nonce][validator].settled;
    }

    function vault() external view returns (address) {
        return address(_getStorage().vault);
    }

    function treasury() external view returns (address) {
        return _getStorage().treasury;
    }

    function getProjectEscrow(bytes32 projectId, address token) external view returns (uint256) {
        return _getStorage().projectEscrow[projectId][token];
    }

    /// @inheritdoc ISapienCore
    function getDispute(bytes32 projectId, uint256 index) external view returns (Dispute memory) {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.contributions[projectId][index].consensusNonce;
        return $.disputes[projectId][index][nonce];
    }

    /// @inheritdoc ISapienCore
    function getOriginatorReport(bytes32 projectId) external view returns (OriginatorReport memory) {
        return _getStorage().originatorReports[projectId];
    }

    function getOriginatorLockedStake(bytes32 projectId) external view returns (uint256) {
        return _getStorage().originatorLockedStake[projectId];
    }

    function getDisputeConfig()
        external
        view
        returns (uint256 disputeBondBps_, uint256 originatorStakeReq_, uint256 originatorReportBondBps_)
    {
        EngineStorage storage $ = _getStorage();
        return ($.disputeBondBps, $.originatorStakeRequirement, $.originatorReportBondBps);
    }

    function getRevealCount(bytes32 projectId, uint256 index) external view returns (uint256) {
        EngineStorage storage $ = _getStorage();
        uint256 nonce = $.submissionNonce[projectId][index];
        return $.validationCounters[projectId][index][nonce].revealCount;
    }

    // Configurable deadline getters
    function claimDeadline() external view returns (uint256) {
        return _getStorage().claimDeadline;
    }

    function challengePeriod() external view returns (uint256) {
        return _getStorage().challengePeriod;
    }

    function commitDeadline() external view returns (uint256) {
        return _getStorage().commitDeadline;
    }

    function revealDeadline() external view returns (uint256) {
        return _getStorage().revealDeadline;
    }

    function forceSettleDelay() external view returns (uint256) {
        return _getStorage().forceSettleDelay;
    }

    function decayRateBps() external view returns (uint256) {
        return _getStorage().decayRateBps;
    }

    // ── UUPS ───────────────────────────────────────────────────────────

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
