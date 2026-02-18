// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    Project,
    Claim,
    IndexState,
    Contribution,
    Reputation,
    ContributionStatus,
    Dispute,
    OriginatorReport
} from "src/Types.sol";

/// @title IQualityEngine
/// @notice Interface for the QualityEngine contract
interface IQualityEngine {
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
    error NonceMismatch();
    error AdapterFeeTooHigh(uint256 provided, uint256 max);
    error ProjectNotFunded();
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
    event ProjectCreated(bytes32 indexed projectId, address indexed originator);
    event ProjectFunded(bytes32 indexed projectId, uint256 amount, uint256 quantity);

    // Claims & Contributions
    event ClaimCreated(uint256 indexed claimId, bytes32 indexed projectId, address indexed claimant, uint256[] indices);
    event ClaimExpired(uint256 indexed claimId, uint256 unsubmittedCount);
    event ContributionSubmitted(
        bytes32 indexed projectId, uint256 indexed index, address contributor, bytes32 submissionHash
    );

    // Validation
    event ValidationClaimed(bytes32 indexed projectId, uint256 indexed index, address indexed validator);
    event ValidationCommitted(bytes32 indexed projectId, uint256 indexed index, address indexed validator);
    event ValidationRevealed(bytes32 indexed projectId, uint256 indexed index, address indexed validator, uint16 score);

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
    event DisputeOpened(bytes32 indexed projectId, uint256 indexed index, address indexed challenger, uint256 bond);
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
    event MinContributorStakeUpdated(uint256 newAmount);
    event MaxDecayRateBpsExceeded(uint256 provided, uint256 max);
    event ProjectCompleted(bytes32 indexed projectId);
    event EscrowRefunded(bytes32 indexed projectId, uint256 amount);
    event ConsensusAlgorithmUpdated(address indexed newAlgorithm);
    event TreasuryUpdated(address indexed newTreasury);
    event MinClaimAmountUpdated(uint64 newAmount);
    event ClaimCooldownUpdated(uint64 newCooldown);

    // ── Project Management ─────────────────────────────────────────────
    function createProject(bytes32 projectId, Project calldata config) external;
    function fundProject(bytes32 projectId, uint256 amount, uint256 quantity, address adapter) external;

    // ── Claim & Contribute ─────────────────────────────────────────────
    function claimToContribute(bytes32 projectId, uint256 quantity, address adapter)
        external
        returns (uint256 claimId, uint256[] memory indices);
    function contribute(uint256 claimId, uint256 index, bytes32 submissionHash) external;
    function expireClaim(uint256 claimId, uint256[] calldata indices) external;

    // ── Validation ─────────────────────────────────────────────────────
    function setValidatorCapacity(uint256 amount) external;
    function reduceValidatorCapacity(uint256 amount) external;
    function commitValidation(bytes32 projectId, uint256 index, bytes32 commitHash, uint128 stakeAmount) external;
    function revealValidation(bytes32 projectId, uint256 index, uint16 score, bytes32 salt) external;

    // ── Finalization ───────────────────────────────────────────────────
    function computeConsensus(bytes32 projectId, uint256 index) external;
    function settleValidator(bytes32 projectId, uint256 index, uint256 nonce) external;
    function forceSettleValidator(bytes32 projectId, uint256 index, uint256 nonce, address validator) external;
    function releaseContributorReward(bytes32 projectId, uint256 index) external;
    function claimReward(address token) external;

    // ── Disputes ─────────────────────────────────────────────────────────
    function openDispute(bytes32 projectId, uint256 index, bytes32 evidenceHash) external;
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
    function getIndexState(bytes32 projectId, uint256 index) external view returns (IndexState memory);
    function getContribution(bytes32 projectId, uint256 index) external view returns (Contribution memory);
    function getReputation(address user, bytes32 role) external view returns (Reputation memory);
    function getPendingRewards(address user, address token) external view returns (uint256);
    function getAdapterFees()
        external
        view
        returns (uint256 originationBps, uint256 contributionBps, uint256 validationBps);
    function getOriginationAdapter(bytes32 projectId) external view returns (address);
    function getContributionAdapter(uint256 claimId) external view returns (address);
    function getDispute(bytes32 projectId, uint256 index) external view returns (Dispute memory);
    function getOriginatorReport(bytes32 projectId) external view returns (OriginatorReport memory);
}
