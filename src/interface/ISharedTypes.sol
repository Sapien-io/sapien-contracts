// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";

// ============================================
// CONSTANTS
// ============================================

bytes32 constant CONTRIBUTOR_ROLE = keccak256("CONTRIBUTOR_ROLE");
bytes32 constant VALIDATOR_ROLE = keccak256("VALIDATOR_ROLE");
bytes32 constant ORIGINATOR_ROLE = keccak256("ORIGINATOR_ROLE");
bytes32 constant LOCKER_ROLE = keccak256("LOCKER_ROLE");
bytes32 constant SLASHER_ROLE = keccak256("SLASHER_ROLE");
bytes32 constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
bytes32 constant UPDATER_ROLE = keccak256("UPDATER_ROLE");
bytes32 constant SAPIEN_CORE_ROLE = keccak256("SAPIEN_CORE_ROLE");

// ============================================
// UNAUTHORIZED REASON CONSTANTS
// ============================================

string constant UNAUTHORIZED_MISSING_ORIGINATOR_ROLE = "Missing ORIGINATOR_ROLE";
string constant UNAUTHORIZED_MISSING_CONTRIBUTOR_ROLE = "Missing CONTRIBUTOR_ROLE";
string constant UNAUTHORIZED_MISSING_VALIDATOR_ROLE = "Missing VALIDATOR_ROLE";
string constant UNAUTHORIZED_MISSING_CORE_ROLE = "Missing CORE or ADMIN role";
string constant UNAUTHORIZED_NOT_PROJECT_ORIGINATOR = "Not project originator";
string constant UNAUTHORIZED_ORIGINATOR_CANNOT_CONTRIBUTE = "Originator cannot contribute";
string constant UNAUTHORIZED_NOT_CLAIM_OWNER = "Not claim owner";
string constant UNAUTHORIZED_NOT_INDEX_OWNER = "Not index owner";
string constant UNAUTHORIZED_NO_ASSIGNMENT = "No assignment for index";
string constant UNAUTHORIZED_INSUFFICIENT_STAKE = "Insufficient stake";
string constant UNAUTHORIZED_INSUFFICIENT_AVAILABLE_STAKE = "Insufficient stake to lock";
string constant UNAUTHORIZED_CANNOT_REDUCE_BELOW_INFLIGHT = "Capacity < in-flight stake";
string constant UNAUTHORIZED_ORIGINATOR_CANNOT_VALIDATE = "Originator cannot validate";
string constant UNAUTHORIZED_CONTRIBUTOR_CANNOT_VALIDATE = "Contributor cannot validate";
string constant UNAUTHORIZED_ARRAY_LENGTH_MISMATCH = "Array length mismatch";
string constant UNAUTHORIZED_SKILL_COOLDOWN = "Skill cooldown not elapsed";
string constant UNAUTHORIZED_CLAIM_NOT_EXPIRED = "Claim not expired yet";

/**
 * @title ISharedTypes
 * @author Sapien Team
 * @notice Shared type definitions used across multiple protocol interfaces
 * @dev Centralizes structs and enums to avoid duplication and struct conversion overhead
 */
interface ISharedTypes {
    // ============================================
    // ENUMS
    // ============================================

    // ============================================
    // ERRORS
    // ============================================

    error Unauthorized(string reason);
    error ClaimNotActive(uint256 claimId);
    error ClaimAlreadyExpired(uint256 claimId, uint256 deadline);
    error CapacityReached();
    error InsufficientCapacity();
    error AllValidationsClaimed(bytes32 projectId);
    error RevealDeadlinePassed(uint256 deadline, uint256 current);

    enum ClaimStatus {
        Active,
        Fulfilled,
        Expired,
        Cancelled
    }

    enum ContributionStatus {
        Pending,
        Validated,
        Rewarded,
        Rejected
    }

    // ============================================
    // STRUCTS
    // ============================================

    struct SkillInfo {
        bool validated;
        uint256 completionCount;
    }

    struct UserReputation {
        uint256 score; // 0-10000 (starts at 5000)
        uint256 totalActions; // total validations/contributions/projects
        uint256 successfulActions; // accurate validations/accepted contributions/funded projects
        uint256 lastUpdated;
    }

    struct ProjectConfig {
        uint256 claimDeadlineDays;
        uint256 minStakeToClaim;
        uint256 minStakeToContribute;
        uint256 numberOfValidations;
        uint256 validatorRewardBasisPoints;
        uint256 challengePeriod;
        string requiredSkill;
    }

    struct ProjectState {
        uint256 totalRewardsAvailable;
        uint256 totalQuantityAvailable;
        uint256 nextContributionIndex;
        uint256 activeClaimedQuantity;
        uint256 submittedQuantity;
        uint256 rewardedQuantity;
    }

    struct IndexReservation {
        address claimant;
        uint48 deadline;
    }

    /**
     * @notice Project configuration and funding info
     */
    struct Project {
        bytes32 projectId;
        address originator;
        IERC20 rewardToken;
        ProjectState state;
        ProjectConfig config;
    }

    /**
     * @notice Claim for validation slots
     */
    struct ValidationClaim {
        address validator;
        uint256 quantity;
        uint256 contributionIndex;
        uint256 claimedAt;
        uint256 deadline;
        uint256 committedCount;
        ClaimStatus status;
    }

    /**
     * @notice Claim for contribution slots
     */
    struct Claim {
        address contributor;
        uint256 quantity;
        uint256 claimedAt;
        uint256 deadline;
        uint256 submittedCount;
        uint256 finalizedCount;
        ClaimStatus status;
    }

    /**
     * @notice Contribution submission
     */
    struct Contribution {
        bytes32 projectId;
        address contributor;
        uint256 claimId;
        uint256 contributionIndex;
        bytes32 submissionHash;
        uint256 submittedAt;
        uint256 totalValidations;
        uint256 averageScore;
        uint256 challengeEndsAt;
        ContributionStatus status;
        uint256 rewardRateSnapshot; // F-11: Reward per slot locked at submission time (prevents sandwiching)
    }

    /**
     * @notice Validation commit in commit-reveal scheme
     */
    struct ValidationCommit {
        bytes32 commitHash;
        address validator;
        bool revealed;
        uint64 committedAt;
        uint64 revealDeadlineSnapshot;
        uint64 nonce;
    }

    /**
     * @notice Revealed validation
     */
    struct Validation {
        bytes32 projectId;
        uint256 stakeAmount;
        uint256 contributionIndex;
        address validator;
        uint64 submittedAt;
        uint16 score;
        bool rewarded;
        bool slashed;
    }

    /**
     * @notice Per-project contributor statistics
     */
    struct ContributorStats {
        uint256 totalClaimed;
        uint256 totalSubmitted;
        uint256 totalRewarded;
        uint256 rewardsEarned;
    }

    /**
     * @notice Runtime statistics for a project's contributions
     */
    struct ProjectContributionStats {
        uint256 totalQuantityClaimed;
        uint256 validatedCount;
        uint256 rejectedCount;
        uint256 totalRewardsClaimed;
    }

    /**
     * @notice Final consensus report for a contribution
     */
    struct ConsensusReport {
        uint256 weightedAverage;
        uint256 validatorCount;
        bool isReady;
        address[] validatorsToSlash;
        uint256[] slashAmounts;
        uint256[] validatorWeights; // Weights from the consensus algorithm (M-1 fix)
    }
}
