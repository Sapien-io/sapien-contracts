// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISapienVault} from "src/interfaces/ISapienVault.sol";

/// @custom:storage-location erc7201:sapien.storage.SapienCore
struct EngineStorage {
    ISapienVault vault;
    uint256 protocolFeeBps;
    uint256 originationFeeBps;
    uint256 contributionFeeBps;
    uint256 validationFeeBps;
    uint256 decayRateBps; // reputation decay per day

    uint256 disputeBondBps; // basis points of contribution rewardRate
    uint256 originatorReportBondBps; // basis points of project totalRewards

    address treasury;

    uint256 originatorStakeRequirement; // per-slot stake required from originator
    uint256 minValidationStake; // global minimum stake for validators (H-05)

    uint256 nextClaimId;

    // ── Projects ───────────────────────────────────────────
    mapping(bytes32 => Project) projects;

    // ── Claims ────────────────────────────────────────────
    mapping(uint256 => Claim) claims;

    // ── Index Allocation: Range + Stack hybrid ─────────────
    // Single mapping colocates start+count for one SLOAD (replaces two mappings)
    mapping(bytes32 => IndexRange) indexRange;
    // Return stack for fragmented returns (rejections, expirations)
    mapping(bytes32 => mapping(uint256 => uint256)) returnStack;
    mapping(bytes32 => uint256) returnStackTop;

    // ── Contributions ──────────────────────────────────────
    mapping(bytes32 => mapping(uint256 => Contribution)) contributions;

    // ── Validations (merged into ValidatorCommit) ──────────
    mapping(bytes32 => mapping(uint256 => uint256)) submissionNonce;
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => mapping(address => ValidatorCommit)))) validatorCommits;
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => address[]))) revealedValidators;
    // Single mapping colocates revealCount+claimCount for one SLOAD (replaces two mappings)
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => ValidationCounters))) validationCounters;

    // ── Consensus Reports (keyed by nonce per RISK-006) ──
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => ConsensusReport))) consensusReports;
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => mapping(address => ValidatorConsensusResult))))
        validatorConsensus;

    // ── Reputation ─────────────────────────────────────────
    mapping(address => mapping(bytes32 => Reputation)) reputation;

    // ── Rewards ────────────────────────────────────────────
    mapping(bytes32 => mapping(address => uint256)) projectEscrow; // projectId => token => balance
    mapping(address => mapping(address => uint256)) pendingRewards; // user => token => amount

    // ── Adapter Fees ───────────────────────────────────────
    mapping(bytes32 => address) originationAdapter;
    mapping(uint256 => address) contributionAdapter;

    // ── Disputes (keyed by nonce to prevent cross-nonce poisoning — SEC-C-01) ──
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => Dispute))) disputes;

    // ── Originator Accountability ────────────────────────────
    mapping(bytes32 => uint256) originatorLockedStake;
    mapping(bytes32 => OriginatorReport) originatorReports;

    // ── Pipeline Tracking (SEC-H-01) ─────────────────────────
    mapping(bytes32 => uint256) pendingContributions; // projectId => in-flight contribution count

    // ── Claim Protection ──────────────────────────────────────
    uint256 minClaimAmount; // minimum amount required to claim rewards
    uint256 claimCooldown; // cooldown period between claims (seconds)
    mapping(address => uint256) lastClaimTime; // last claim timestamp per user

    // ── Configurable Deadlines & Periods ──────────────────────────
    uint256 claimDeadline;
    uint256 challengePeriod;
    uint256 commitDeadline;
    uint256 revealDeadline;
    uint256 forceSettleDelay;

    // ── Validation Claims ─────────────────────────────────────────
    uint256 nextValidationClaimId;
    mapping(uint256 => ValidationClaim) validationClaims;
}

// ============================================
// Enums
// ============================================

enum ProjectStatus {
    Created,
    Funded,
    Active,
    Completed,
    Cancelled
}

enum ClaimStatus {
    Active,
    Completed,
    Expired
}

enum ContributionStatus {
    Empty,
    Reserved,
    Pending,
    Accepted,
    Rejected
}

enum DisputeStatus {
    None,
    Open,
    Upheld,
    Rejected
}

enum OriginatorReportStatus {
    None,
    Open,
    Upheld,
    Rejected
}

// ============================================
// Helper Structs
// ============================================

struct IndexRange {
    uint256 start;
    uint256 count;
}

struct ValidationCounters {
    uint256 revealCount;
    uint256 claimCount;
}

// ============================================
// Structs
// ============================================

struct Project {
    address originator;
    address rewardToken;
    uint256 totalRewards;
    uint256 totalQuantity;
    uint256 availableSlots;
    uint256 minStakeToClaim;
    uint256 minValidationStake;
    bytes32 requiredSkill;
    uint256 consensusThreshold; // basis points (e.g., 7000 = 70%)
    uint256 validatorRewardBps; // 0-2500
    uint256 numberOfValidations;
    uint256 minValidatorReputation;
    ProjectStatus status;
    uint256 activatedAt;
    uint256 completedAt;
}

struct Claim {
    address claimant;
    bytes32 projectId;
    uint256 deadline;
    uint256 submittedCount;
    uint256 totalCount;
    ClaimStatus status;
}

struct Contribution {
    address contributor;
    uint256 claimId;
    ContributionStatus status;
    bool rewardReleased;
    bytes32 submissionHash;
    uint256 rewardRate;
    uint256 submittedAt;
    uint256 challengeEndsAt;
    uint256 consensusNonce;
}

struct Reputation {
    uint256 score;
    uint256 totalActions;
    uint256 successfulActions;
    uint256 lastUpdated;
    uint256 dailyGain;
    uint256 dailyGainDate;
}

struct StakeAccount {
    uint256 contributorLock;
    uint256 validatorCapacity;
    uint256 inFlight;
}

struct ValidationClaim {
    address validator;
    bytes32 projectId;
    uint256[] indices;
    uint256 deadline;
    uint256 committedCount;
    uint256 totalCount;
    ValidationClaimStatus status;
}

enum ValidationClaimStatus {
    Active,
    Fulfilled,
    Expired
}

struct Dispute {
    address challenger;
    uint256 openedAt;
    DisputeStatus status;
    uint256 bondAmount;
    uint256 resolvedAt;
    bytes32 evidenceHash;
}

struct OriginatorReport {
    address reporter;
    uint256 reportedAt;
    OriginatorReportStatus status;
    uint256 bondAmount;
    uint256 resolvedAt;
    bytes32 evidenceHash;
}

struct ValidatorCommit {
    bytes32 commitHash;
    uint256 stakedAmount;
    uint256 commitTimestamp;
    uint256 revealedAt;
    uint256 score;
    bool claimed;
    bool settled;
    uint256 validationClaimId;
    address adapter;
}

struct ValidatorConsensusResult {
    bool isOutlier;
    uint256 slashAmount;
    uint256 weight;
}

struct ConsensusReport {
    uint256 weightedAverage;
    uint256 stdDeviation;
    uint256 totalAccurateWeight;
    uint256 nonce;
    bool computed;
}

/// @notice Input to the consensus algorithm
struct ValidationInput {
    address validator;
    uint256 score;
    uint256 stakeAmount;
    uint256 reputation;
}

/// @notice Output from the consensus algorithm
struct ConsensusResult {
    uint256 weightedAverage;
    uint256 stdDeviation;
    address[] validators;
    bool[] isOutlier;
    uint256[] slashAmounts;
    uint256[] weights;
    uint256 totalAccurateWeight;
}
