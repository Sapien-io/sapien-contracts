// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    Project,
    Claim,
    Contribution,
    Reputation,
    ContributionStatus,
    Dispute,
    OriginatorReport,
    ValidationClaim
} from "src/Types.sol";

/// @title ISapienCore
/// @notice Interface for the SapienCore contract
interface ISapienCore {
    // ── Errors ─────────────────────────────────────────────────────────
    error NotProjectOriginator();
    error OriginatorCannotContribute();
    error NotClaimOwner();
    error IndexNotInClaim();
    error ClaimDeadlinePassed();
    error ClaimDeadlineNotPassed();
    error InsufficientStake(uint256 required, uint256 available);
    error InsufficientReputation(uint256 required, uint256 actual);
    error ConsensusNotReady(uint256 have, uint256 need);
    error ConsensusAlreadyComputed();
    error AlreadySettled();
    error ChallengeNotElapsed();
    error InvalidReveal();
    error AdapterFeeTooHigh(uint256 provided, uint256 max);
    error ProjectNotActive();
    error InvalidProjectConfig(string reason);
    error NoSlotsAvailable();
    error ClaimQuantityTooHigh(uint256 requested, uint256 max);
    error InvalidIndex();
    error IndexNotReserved();
    error IndexNotSubmitted();
    error AlreadyCommitted();
    error NotCommitted();
    error RevealWindowClosed();
    error ContributionNotAccepted();
    error RewardAlreadyReleased();
    error NoRewardToClaim();
    error ClaimAmountTooSmall(uint256 amount, uint256 minClaimAmount);
    error ClaimCooldownActive(uint256 timestamp, uint256 cooldownEnd);
    error ZeroAddress();
    error ZeroAmount();
    error InvalidScore();
    error CannotValidateOwnContribution();
    error AlreadyRevealed();
    error ValidationNotClaimed();
    error InvalidCommitHash();
    error ProjectNotCompleted();
    error ProjectHasActivePipeline();
    error ForceSettleTooEarly();
    error InvalidEvidenceHash();
    error DeadlineTooLong(uint256 provided, uint256 max);

    // Dispute errors
    error DisputeAlreadyOpen();
    error DisputeAlreadyClosed();
    error DisputeNotOpen();
    error DisputeWindowClosed();
    error DisputeInProgress();
    error DisputeResolutionNotExpired();
    error CannotDisputeOwnContribution();
    error ConsensusNotComputed();
    error DisputeBondTooHigh(uint256 provided, uint256 max);

    // Originator report errors
    error OriginatorReportAlreadyOpen();
    error OriginatorReportNotOpen();
    error ProjectNotCancellable();

    // ── Events ─────────────────────────────────────────────────────────
    // Projects
    event ProjectCreated(bytes32 indexed projectId, address indexed originator, string metadataCid);
    event ProjectFunded(bytes32 indexed projectId, uint256 amount, uint256 quantity);
    event ProjectRemoved(bytes32 indexed projectId, address indexed admin);

    // Claims & Contributions
    event ClaimCreated(uint256 indexed claimId, bytes32 indexed projectId, address indexed claimant, uint256[] indices);
    event ClaimExpired(uint256 indexed claimId, uint256 unsubmittedCount);
    event ContributionSubmitted(
        bytes32 indexed projectId, uint256 indexed index, address contributor, bytes32 submissionHash, string dataCid
    );

    // Validation
    event ValidationClaimCreated(
        uint256 indexed claimId, bytes32 indexed projectId, address indexed validator, uint256[] indices
    );
    event ValidationClaimExpired(uint256 indexed claimId, uint256 uncommittedCount);
    event ValidationCommitted(bytes32 indexed projectId, uint256 indexed index, address indexed validator);
    event ValidationRevealed(
        bytes32 indexed projectId, uint256 indexed index, address indexed validator, uint256 score
    );

    // Finalization
    event ConsensusReached(
        bytes32 indexed projectId, uint256 indexed index, uint256 weightedAverage, ContributionStatus status
    );
    event ValidatorSettled(bytes32 indexed projectId, uint256 indexed index, address indexed validator, bool outlier);
    event ContributorRewardReleased(
        bytes32 indexed projectId, uint256 indexed index, address indexed contributor, uint256 amount
    );
    event RewardClaimed(address indexed user, address indexed token, uint256 amount);

    // Reputation
    event ReputationUpdated(address indexed user, bytes32 indexed role, uint256 oldScore, uint256 newScore);

    // Adapter Fees
    event OriginationFeePaid(bytes32 indexed projectId, address indexed adapter, uint256 amount);
    event ContributionAdapterFeePaid(
        bytes32 indexed projectId, uint256 indexed index, address indexed adapter, uint256 amount
    );
    event ValidationAdapterFeePaid(
        bytes32 indexed projectId, uint256 indexed index, address indexed adapter, uint256 amount
    );

    // Disputes
    event DisputeOpened(
        bytes32 indexed projectId, uint256 indexed index, address indexed challenger, uint256 bond, string evidenceCid
    );
    event DisputeResolved(bytes32 indexed projectId, uint256 indexed index, bool upheld);
    event DisputeEscalated(bytes32 indexed projectId, uint256 indexed index);

    // Originator Reports
    event OriginatorReported(bytes32 indexed projectId, address indexed reporter, uint256 bond);
    event OriginatorReportResolved(bytes32 indexed projectId, bool upheld);
    event OriginatorReportEscalated(bytes32 indexed projectId);
    event ProjectCancelled(bytes32 indexed projectId);

    // Admin
    event ProtocolFeeUpdated(uint256 newFeeBps);
    event OriginationFeeUpdated(uint256 newFeeBps);
    event ContributionFeeUpdated(uint256 newFeeBps);
    event ValidationFeeUpdated(uint256 newFeeBps);
    event DecayRateUpdated(uint256 newDecayRate);
    event DisputeBondBpsUpdated(uint256 newBps);
    event OriginatorStakeRequirementUpdated(uint256 newAmount);
    event OriginatorReportBondBpsUpdated(uint256 newBps);
    event MinValidationStakeUpdated(uint256 newAmount);
    event ProjectCompleted(bytes32 indexed projectId);
    event EscrowRefunded(bytes32 indexed projectId, uint256 amount);
    event TreasuryUpdated(address indexed newTreasury);
    event MinClaimAmountUpdated(uint256 newAmount);
    event ClaimCooldownUpdated(uint256 newCooldown);
    event ClaimDeadlineUpdated(uint256 newDeadline);
    event ChallengePeriodUpdated(uint256 newPeriod);
    event CommitDeadlineUpdated(uint256 newDeadline);
    event RevealDeadlineUpdated(uint256 newDeadline);
    event ForceSettleDelayUpdated(uint256 newDelay);

    // ── Origination ─────────────────────────────────────────────
    function createProject(bytes32 projectId, string calldata metadataCid, Project calldata config) external;
    function fundProject(bytes32 projectId, uint256 amount, uint256 quantity, address adapter) external;
    function removeProject(bytes32 projectId) external;

    // ── Contribution ─────────────────────────────────────────────
    function claimToContribute(bytes32 projectId, uint256 quantity, address adapter)
        external
        returns (uint256 claimId, uint256[] memory indices);
    function contribute(uint256 claimId, uint256 index, bytes32 submissionHash, string calldata dataCid) external;
    function batchContribute(
        uint256 claimId,
        uint256[] calldata indices,
        bytes32[] calldata submissionHashes,
        string[] calldata dataCids
    ) external;
    function expireClaim(uint256 claimId, uint256[] calldata indices) external;

    // ── Validation ─────────────────────────────────────────────────────
    function lockValidatorCapacity(uint256 amount) external;
    function unlockValidatorCapacity(uint256 amount) external;
    function claimToValidate(bytes32 projectId, uint256[] calldata indices) external returns (uint256 claimId);
    function commitValidation(
        bytes32 projectId,
        uint256 index,
        bytes32 commitHash,
        uint256 stakeAmount,
        address adapter
    ) external;
    function batchCommitValidations(
        bytes32 projectId,
        uint256[] calldata indices,
        bytes32[] calldata commitHashes,
        uint256[] calldata stakeAmounts,
        address adapter
    ) external;
    function revealValidation(bytes32 projectId, uint256 index, uint256 score, bytes32 salt) external;
    function batchRevealValidations(
        bytes32 projectId,
        uint256[] calldata indices,
        uint256[] calldata scores,
        bytes32[] calldata salts
    ) external;
    function cancelExpiredValidationClaim(uint256 claimId) external;

    // ── Finalization ───────────────────────────────────────────────────
    function computeConsensus(bytes32 projectId, uint256 index) external;
    function settleValidator(bytes32 projectId, uint256 index, uint256 nonce) external;
    function forceSettleValidator(bytes32 projectId, uint256 index, uint256 nonce, address validator) external;
    function releaseContributorReward(bytes32 projectId, uint256 index) external;
    function claimReward(address token) external;

    // ── Disputes ─────────────────────────────────────────────────────────
    function openDispute(bytes32 projectId, uint256 index, bytes32 evidenceHash, string calldata evidenceCid) external;
    function resolveDispute(bytes32 projectId, uint256 index, bool upheld) external;
    function escalateDispute(bytes32 projectId, uint256 index) external;

    // ── Originator Reports ──────────────────────────────────────────────
    function reportOriginator(bytes32 projectId, bytes32 evidenceHash) external;
    function resolveOriginatorReport(bytes32 projectId, bool upheld) external;
    function escalateOriginatorReport(bytes32 projectId) external;

    // ── Project Completion ───────────────────────────────────────────────
    function completeProject(bytes32 projectId) external;
    function refundEscrow(bytes32 projectId) external;

    // ── Views ──────────────────────────────────────────────────────────
    function getProject(bytes32 projectId) external view returns (Project memory);
    function getClaim(uint256 claimId) external view returns (Claim memory);
    function getValidationClaim(uint256 claimId) external view returns (ValidationClaim memory);
    function getContribution(bytes32 projectId, uint256 index) external view returns (Contribution memory);
    function getReputation(address user, bytes32 role) external view returns (Reputation memory);
    function getPendingRewards(address user, address token) external view returns (uint256);
    function getAdapterFees()
        external
        view
        returns (uint256 originationBps, uint256 contributionBps, uint256 validationBps);
    function getOriginationAdapter(bytes32 projectId) external view returns (address);
    function getContributionAdapter(uint256 claimId) external view returns (address);
    function getValidationAdapter(bytes32 projectId, uint256 index, uint256 nonce, address validator)
        external
        view
        returns (address);
    function getDispute(bytes32 projectId, uint256 index) external view returns (Dispute memory);
    function getOriginatorReport(bytes32 projectId) external view returns (OriginatorReport memory);

    // Configurable deadline getters
    function claimDeadline() external view returns (uint256);
    function challengePeriod() external view returns (uint256);
    function commitDeadline() external view returns (uint256);
    function revealDeadline() external view returns (uint256);
    function forceSettleDelay() external view returns (uint256);
}
