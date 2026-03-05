// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISapienVault} from "src/interfaces/ISapienVault.sol";

/// @custom:storage-location erc7201:sapien.storage.SapienCore
struct EngineStorage {
    // ── Packed Config Slot 0 (32 bytes) ────────────────────
    // vault(20) + protocolFeeBps(2) + originationFeeBps(2) + contributionFeeBps(2)
    // + validationFeeBps(2) + decayRateBps(2) + disputeBondBps(2) = 32
    ISapienVault vault;
    uint16 protocolFeeBps;
    uint16 originationFeeBps;
    uint16 contributionFeeBps;
    uint16 validationFeeBps;
    uint16 decayRateBps;
    uint16 disputeBondBps;

    // ── Packed Config Slot 1 (22 bytes used) ───────────────
    // originatorReportBondBps(2) + treasury(20) = 22
    uint16 originatorReportBondBps;
    address treasury;

    // ── Full-size scalar slots ─────────────────────────────
    uint256 originatorStakeRequirement;
    uint256 minValidationStake;
    uint256 nextClaimId;

    // ── Projects ───────────────────────────────────────────
    mapping(bytes32 => Project) projects;

    // ── Claims ────────────────────────────────────────────
    mapping(uint256 => Claim) claims;

    // ── Index Allocation: Range + Stack hybrid ─────────────
    mapping(bytes32 => IndexRange) indexRange;
    mapping(bytes32 => mapping(uint256 => uint256)) returnStack;
    mapping(bytes32 => uint256) returnStackTop;

    // ── Contributions ──────────────────────────────────────
    mapping(bytes32 => mapping(uint256 => Contribution)) contributions;

    // ── Validations (merged into ValidatorCommit) ──────────
    mapping(bytes32 => mapping(uint256 => uint256)) submissionNonce;
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => mapping(address => ValidatorCommit)))) validatorCommits;
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => address[]))) revealedValidators;
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => ValidationCounters))) validationCounters;

    // ── Consensus Reports (keyed by nonce per RISK-006) ──
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => ConsensusReport))) consensusReports;
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => mapping(address => ValidatorConsensusResult))))
        validatorConsensus;

    // ── Reputation ─────────────────────────────────────────
    mapping(address => mapping(bytes32 => Reputation)) reputation;

    // ── Rewards ────────────────────────────────────────────
    mapping(bytes32 => mapping(address => uint256)) projectEscrow;
    mapping(address => mapping(address => uint256)) pendingRewards;

    // ── Adapter Fees ───────────────────────────────────────
    mapping(bytes32 => address) originationAdapter;
    mapping(uint256 => address) contributionAdapter;

    // ── Disputes (keyed by nonce to prevent cross-nonce poisoning — SEC-C-01) ──
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => Dispute))) disputes;

    // ── Originator Accountability ────────────────────────────
    mapping(bytes32 => uint256) originatorLockedStake;
    mapping(bytes32 => OriginatorReport) originatorReports;

    // ── Pipeline Tracking (SEC-H-01) ─────────────────────────
    mapping(bytes32 => uint256) pendingContributions;

    // ── Claim Protection ──────────────────────────────────────
    uint256 minClaimAmount;
    mapping(address => uint256) lastClaimTime;

    // ── Packed Deadlines Slot (24 bytes in 1 slot) ────────────
    // claimCooldown(4) + claimDeadline(4) + challengePeriod(4)
    // + commitDeadline(4) + revealDeadline(4) + forceSettleDelay(4) = 24
    uint32 claimCooldown;
    uint32 claimDeadline;
    uint32 challengePeriod;
    uint32 commitDeadline;
    uint32 revealDeadline;
    uint32 forceSettleDelay;

    // ── Validation Claims ─────────────────────────────────────────
    uint256 nextValidationClaimId;
    mapping(uint256 => ValidationClaim) validationClaims;

    // ── Pending Contribution Index Set (for random validator assignment) ──
    mapping(bytes32 => uint256[]) pendingIndices;
    mapping(bytes32 => mapping(uint256 => uint256)) pendingIndexPos;

    // ── Skill Registry ──────────────────────────────────────────────────
    mapping(bytes32 => bool) registeredSkills;
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
// Helper Structs (Packed)
// ============================================

/// @notice Packed into 1 slot: start(16) + count(16) = 32 bytes
struct IndexRange {
    uint128 start;
    uint128 count;
}

/// @notice Packed into 1 slot: revealCount(4) + claimCount(4) + commitCount(4) = 12 bytes
struct ValidationCounters {
    uint32 revealCount;
    uint32 claimCount;
    uint32 commitCount;
}

// ============================================
// Structs (Packed)
// ============================================

/// @notice Project — packed from 16 slots → 7 slots
/// Slot 0: originator(20) + status(1) + numberOfValidations(1) + consensusThreshold(2) + validatorRewardBps(2) + minValidatorReputation(2) + totalQuantity(4) = 32
/// Slot 1: rewardToken(20) + activatedAt(6) + completedAt(6) = 32
/// Slot 2: cancelledAt(6) + availableSlots(4) = 10 (partial)
/// Slots 3-6: requiredSkill, totalRewards, minStakeToClaim, minValidationStake
struct Project {
    address originator;
    ProjectStatus status;
    uint8 numberOfValidations;
    uint16 consensusThreshold;
    uint16 validatorRewardBps;
    uint16 minValidatorReputation;
    uint32 totalQuantity;
    address rewardToken;
    uint48 activatedAt;
    uint48 completedAt;
    uint48 cancelledAt;
    uint32 availableSlots;
    bytes32 requiredSkill;
    uint256 totalRewards;
    uint256 minStakeToClaim;
    uint256 minValidationStake;
}

/// @notice Claim — packed from 6 slots → 2 slots
/// Slot 0: claimant(20) + status(1) + deadline(6) + submittedCount(2) + totalCount(2) = 31
/// Slot 1: projectId(32)
struct Claim {
    address claimant;
    ClaimStatus status;
    uint48 deadline;
    uint16 submittedCount;
    uint16 totalCount;
    bytes32 projectId;
}

/// @notice Contribution — packed from 8 slots → 4 slots
/// Slot 0: contributor(20) + status(1) + rewardReleased(1) + submittedAt(6) + claimId(4) = 32
/// Slot 1: submissionHash(32)
/// Slot 2: rewardRate(32)
/// Slot 3: challengeEndsAt(6) + consensusNonce(4) = 10 (partial)
struct Contribution {
    address contributor;
    ContributionStatus status;
    bool rewardReleased;
    uint48 submittedAt;
    uint32 claimId;
    bytes32 submissionHash;
    uint256 rewardRate;
    uint48 challengeEndsAt;
    uint32 consensusNonce;
}

/// @notice Reputation — packed from 6 slots → 1 slot
/// score(2) + totalActions(4) + successfulActions(4) + lastUpdated(6) + dailyGain(2) + dailyGainDate(4) = 22
struct Reputation {
    uint16 score;
    uint32 totalActions;
    uint32 successfulActions;
    uint48 lastUpdated;
    uint16 dailyGain;
    uint32 dailyGainDate;
}

/// @notice ValidationClaim — packed from 7 slots → 3 slots
/// Slot 0: validator(20) + status(1) + deadline(6) + committedCount(2) + totalCount(2) = 31
/// Slot 1: projectId(32)
/// Slot 2: indices array pointer
struct ValidationClaim {
    address validator;
    ValidationClaimStatus status;
    uint48 deadline;
    uint16 committedCount;
    uint16 totalCount;
    bytes32 projectId;
    uint256[] indices;
}

enum ValidationClaimStatus {
    Active,
    Fulfilled,
    Expired
}

/// @notice Dispute — packed from 6 slots → 3 slots
/// Slot 0: challenger(20) + status(1) + openedAt(6) + resolvedAt(5) = 32
/// Slot 1: bondAmount(32)
/// Slot 2: evidenceHash(32)
struct Dispute {
    address challenger;
    DisputeStatus status;
    uint48 openedAt;
    uint40 resolvedAt;
    uint256 bondAmount;
    bytes32 evidenceHash;
}

/// @notice OriginatorReport — packed from 6 slots → 3 slots
/// Slot 0: reporter(20) + status(1) + reportedAt(6) + resolvedAt(5) = 32
/// Slot 1: bondAmount(32)
/// Slot 2: evidenceHash(32)
struct OriginatorReport {
    address reporter;
    OriginatorReportStatus status;
    uint48 reportedAt;
    uint40 resolvedAt;
    uint256 bondAmount;
    bytes32 evidenceHash;
}

/// @notice ValidatorCommit — packed from 8 slots → 4 slots
/// Slot 0: commitHash(32)
/// Slot 1: adapter(20) + claimed(1) + settled(1) + commitTimestamp(6) + validationClaimId(4) = 32
/// Slot 2: revealedAt(6) + score(2) = 8 (partial)
/// Slot 3: stakedAmount(32)
struct ValidatorCommit {
    bytes32 commitHash;
    address adapter;
    bool claimed;
    bool settled;
    uint48 commitTimestamp;
    uint32 validationClaimId;
    uint48 revealedAt;
    uint16 score;
    uint256 stakedAmount;
}

struct ValidatorConsensusResult {
    bool isOutlier;
    uint256 slashAmount;
    uint256 weight;
}

/// @notice ConsensusReport — packed from 5 slots → 3 slots
/// Slot 0: weightedAverage(2) + nonce(4) + computed(1) = 7 (partial)
/// Slot 1: stdDeviation(32)
/// Slot 2: totalAccurateWeight(32)
struct ConsensusReport {
    uint16 weightedAverage;
    uint32 nonce;
    bool computed;
    uint256 stdDeviation;
    uint256 totalAccurateWeight;
}

/// @notice Input to the consensus algorithm (memory-only)
struct ValidationInput {
    address validator;
    uint256 score;
    uint256 stakeAmount;
    uint256 reputation;
}

/// @notice Output from the consensus algorithm (memory-only)
struct ConsensusResult {
    uint256 weightedAverage;
    uint256 stdDeviation;
    address[] validators;
    bool[] isOutlier;
    uint256[] slashAmounts;
    uint256[] weights;
    uint256 totalAccurateWeight;
}

// ── Vault ──────────────────────────────────

struct StakeAccount {
    uint256 contributorLock;
    uint256 validatorCapacity;
    uint256 inFlight;
}

struct SapienVaultStorage {
    mapping(address => StakeAccount) accounts;
    mapping(address => uint256) lastDepositTimestamp;
    uint256 minDepositAge;
}
