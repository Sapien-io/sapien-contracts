// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IStakeVault} from "src/interfaces/IStakeVault.sol";

/// @custom:storage-location erc7201:sapien.storage.QualityEngine
struct EngineStorage {
    // ── Slot 0: vault (20) + 5 fee bps (10) = 30 bytes ──
    IStakeVault vault;
    uint16 protocolFeeBps;
    uint16 originationFeeBps;
    uint16 contributionFeeBps;
    uint16 validationFeeBps;
    uint16 decayRateBps; // reputation decay per day

    // ── Slot 1: consensusAlgorithm (20) + 2 bps (4) = 24 bytes ──
    address consensusAlgorithm; // IConsensusAlgorithm (staticcall target)
    uint16 disputeBondBps; // basis points of contribution rewardRate
    uint16 originatorReportBondBps; // basis points of project totalRewards

    // ── Slot 2: treasury (20 bytes) ──
    address treasury;

    // ── Slot 3: packed stake configs (16 + 16 = 32 bytes) ──
    uint128 originatorStakeRequirement; // per-slot stake required from originator
    uint128 minValidationStake; // global minimum stake for validators (H-05)

    // ── Slot 4: counter ──
    uint256 nextClaimId;

    // ── Projects ───────────────────────────────────────────
    mapping(bytes32 => Project) projects;

    // ── Claims & Indices ───────────────────────────────────
    mapping(uint256 => Claim) claims;
    mapping(bytes32 => mapping(uint256 => IndexState)) indexStates;

    // ── Index Allocation: Range + Stack hybrid ─────────────
    // Packed range (1 mapping replaces 2; colocates start+count for 1 SLOAD)
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
    // Packed counters (1 mapping replaces 2; colocates revealCount+claimCount)
    mapping(bytes32 => mapping(uint256 => mapping(uint256 => ValidationCounters))) validationCounters;

    // ── Consensus Reports (packed into 2-slot struct; keyed by nonce per RISK-006) ──
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
    uint64 minClaimAmount; // minimum amount required to claim rewards
    uint64 claimCooldown; // cooldown period between claims (seconds)
    mapping(address => uint64) lastClaimTime; // last claim timestamp per user
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

enum SubmissionStatus {
    Empty,
    Reserved,
    Submitted,
    Accepted,
    Rejected
}

enum ContributionStatus {
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
// Packed Helper Structs
// ============================================

/// @dev 1 slot. Packed index allocation range (replaces 2 separate mappings).
struct IndexRange {
    uint128 start; // first available index in range
    uint128 count; // how many sequential indices remain
}

/// @dev 1 slot. Packed validation counters (replaces 2 separate mappings).
struct ValidationCounters {
    uint128 revealCount;
    uint128 claimCount;
}

// ============================================
// Structs
// ============================================

/// @dev 9 slots (down from 13). Config fields packed into final slot.
struct Project {
    address originator; // 20 bytes → slot 0
    address rewardToken; // 20 bytes → slot 1
    uint256 totalRewards; // slot 2
    uint256 totalQuantity; // slot 3
    uint256 availableSlots; // slot 4
    uint256 minStakeToClaim; // slot 5
    uint256 minValidationStake; // slot 6
    bytes32 requiredSkill; // slot 7
    // ── packed config (25 bytes → slot 8) ──
    uint16 consensusThreshold; // basis points (e.g., 7000 = 70%)
    uint16 validatorRewardBps; // 0-2500
    uint16 numberOfValidations;
    uint16 minValidatorReputation;
    ProjectStatus status;
    uint64 activatedAt; // when project went Funded → Active
    uint64 completedAt;
}

/// @dev 3 slots. indices removed (passed via calldata on expiry).
struct Claim {
    address claimant; // 20 bytes → slot 0
    bytes32 projectId; // 32 bytes → slot 1
    uint64 deadline; // 8 bytes
    uint8 submittedCount; // 1 byte
    uint8 totalCount; // 1 byte
    ClaimStatus status; // 1 byte
    // 11 bytes → slot 2
}

/// @dev 1 slot (down from 2). deadline removed (never read; use Claim.deadline instead).
struct IndexState {
    address reservedBy; // 20 bytes
    uint64 claimId; // 8 bytes
    SubmissionStatus status; // 1 byte
    // 29 bytes → slot 0
}

/// @dev 5 slots. consensusNonce stores nonce at computeConsensus (RISK-006).
struct Contribution {
    address contributor; // 20 bytes → slot 0
    bytes32 submissionHash; // slot 1
    uint256 rewardRate; // slot 2
    uint64 submittedAt; // 8 bytes
    uint64 challengeEndsAt; // 8 bytes
    uint64 claimId; // 8 bytes
    ContributionStatus status; // 1 byte
    bool rewardReleased; // 1 byte
    uint64 consensusNonce; // nonce at computeConsensus (for dispute/settlement lookups)
    // 34 bytes → slot 3-4
}

/// @dev 1 slot (down from 6). All fields fit in 30 bytes.
struct Reputation {
    uint64 score;
    uint32 totalActions;
    uint32 successfulActions;
    uint64 lastUpdated;
    uint16 dailyGain;
    uint32 dailyGainDate;
}

struct StakeAccount {
    uint256 contributorLock;
    uint256 validatorCapacity;
    uint256 inFlight;
}

/// @dev 3 slots (down from 4). bondAmount downsized to uint128, fields reordered for packing.
struct Dispute {
    address challenger; // 20 bytes ─┐
    uint64 openedAt; //  8 bytes  ├─ slot 0 (29 bytes)
    DisputeStatus status; //  1 byte  ─┘
    uint128 bondAmount; // 16 bytes ─┐
    uint64 resolvedAt; //  8 bytes  ├─ slot 1 (24 bytes)
    bytes32 evidenceHash; // 32 bytes ─── slot 2
}

/// @dev 3 slots (down from 4). bondAmount downsized to uint128, fields reordered for packing.
struct OriginatorReport {
    address reporter; // 20 bytes ─┐
    uint64 reportedAt; //  8 bytes  ├─ slot 0 (29 bytes)
    OriginatorReportStatus status; //  1 byte  ─┘
    uint128 bondAmount; // 16 bytes ─┐
    uint64 resolvedAt; //  8 bytes  ├─ slot 1 (24 bytes)
    bytes32 evidenceHash; // 32 bytes ─── slot 2
}

/// @dev Merged per-validator commit/reveal data. Replaces 6 separate 4-level mappings.
///      3 slots: commitHash (32) | stakedAmount+timestamps (32) | score+flags (4)
struct ValidatorCommit {
    bytes32 commitHash; // slot 0
    uint128 stakedAmount; // 16 bytes
    uint64 commitTimestamp; // 8 bytes
    uint64 revealedAt; // 8 bytes
    // 32 bytes → slot 1
    uint16 score; // 2 bytes
    bool claimed; // 1 byte
    bool settled; // 1 byte
    // 4 bytes → slot 2
}

/// @dev 1 slot (down from 2). Downsized to uint120 for single-slot packing.
struct ValidatorConsensusResult {
    bool isOutlier; //  1 byte ─┐
    uint120 slashAmount; // 15 bytes  ├─ 31 bytes → 1 slot
    uint120 weight; // 15 bytes ─┘
}

/// @dev 2 slots (down from 5 separate mappings). Packed consensus report per contribution index.
struct ConsensusReport {
    uint128 weightedAverage; // 16 bytes
    uint128 stdDeviation; // 16 bytes → slot 0
    uint128 totalAccurateWeight; // 16 bytes
    uint64 nonce; // 8 bytes
    bool computed; // 1 byte → slot 1 (25 bytes)
}

/// @notice Input to the consensus algorithm
struct ValidationInput {
    address validator;
    uint16 score;
    uint128 stakeAmount;
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
