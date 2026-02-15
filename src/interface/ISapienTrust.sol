// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ISharedTypes} from "src/interface/ISharedTypes.sol";
import {ISapienVault} from "src/interface/ISapienVault.sol";

/**
 * @title ISapienTrust
 * @author Sapien Team
 * @notice Unified identity and reputation layer for Sapien V2
 * @dev Manages simplified user skills and Proof of Quality (PoQ) reputation.
 *      Identity is implicit: anyone with sufficient stake can participate.
 */
interface ISapienTrust is ISharedTypes {
    // ============================================
    // EVENTS
    // ============================================

    /**
     * @notice Emitted when a user's reputation score is updated
     * @param user Address of the user
     * @param role Role identifier
     * @param oldScore Previous reputation score
     * @param newScore New reputation score
     */
    event ReputationUpdated(address indexed user, bytes32 indexed role, uint256 oldScore, uint256 indexed newScore);

    /**
     * @notice Emitted when a user's skill is validated
     * @param user Address of the user
     * @param skill Name of the skill
     * @param completionCount Number of successful completions
     */
    event SkillValidated(address indexed user, string skill, uint256 indexed completionCount);

    /**
     * @notice Emitted when the reputation decay rate is updated
     * @param decayRate New decay rate in basis points
     */
    event ReputationDecayUpdated(uint256 indexed decayRate);

    /**
     * @notice Emitted when the global minimum stake requirement is updated
     * @param minStake New minimum stake amount
     */
    event MinStakeRequiredUpdated(uint256 indexed minStake);

    /**
     * @notice Emitted when the minimum stake for a specific role is updated
     * @param role Role identifier
     * @param minStake New minimum stake amount
     */
    event RoleMinStakeUpdated(bytes32 indexed role, uint256 indexed minStake);

    /**
     * @notice Emitted when protocol roles are configured
     * @param core Address of the SapienCore contract
     * @param oracle Address of the ValidationOracle contract
     */
    event ProtocolRolesConfigured(address indexed core, address indexed oracle);

    // ============================================
    // ERRORS
    // ============================================

    error InvalidAddress();
    error InsufficientStake(bytes32 role, uint256 required, uint256 actual);
    error ProtocolRolesAlreadyConfigured();
    error DecayRateOutOfRange(uint256 provided, uint256 max);

    // ============================================
    // IDENTITY FUNCTIONS
    // ============================================

    /**
     * @notice Check if a user is eligible for a role based on their stake
     * @dev Reverts with InsufficientStake if requirements not met
     * @param user Address of the user
     * @param role Role identifier (e.g. CONTRIBUTOR_ROLE)
     */
    function hasEnoughStakeForRole(address user, bytes32 role) external view;

    /**
     * @notice Check if a user has a validated skill
     * @param user Address of the user
     * @param skill Name of the skill
     * @return True if the skill is validated
     */
    function hasValidatedSkill(address user, string calldata skill) external view returns (bool);

    /**
     * @notice Mark a skill as validated for a user
     * @param user Address of the user
     * @param skill Name of the skill to validate
     */
    function validateSkill(address user, string calldata skill) external;

    /**
     * @notice Get the minimum stake required for a specific role
     * @param role Role identifier
     * @return Minimum amount of staking tokens required
     */
    function roleMinStake(bytes32 role) external view returns (uint256);

    // ============================================
    // REPUTATION FUNCTIONS
    // ============================================

    /**
     * @notice Get the trust score (reputation) of a user for a specific role
     * @param user Address of the user
     * @param role Role identifier
     * @return Reputation score (0-10000, where 5000 is default)
     */
    function getTrustScore(address user, bytes32 role) external view returns (uint256);

    /**
     * @notice Update a user's reputation based on their performance
     * @param user Address of the user
     * @param role Role identifier
     * @param success True if the action was successful/accurate
     * @param qualityScore Score of the specific action (if applicable)
     */
    function updateReputation(address user, bytes32 role, bool success, uint256 qualityScore) external;

    // ============================================
    // STAKING & SYBIL PROTECTION
    // ============================================

    /**
     * @notice Check if a user meets the global minimum staking requirement
     * @param user Address of the user
     * @return True if user has sufficient stake
     */
    function hasRequiredStake(address user) external view returns (bool);

    /**
     * @notice Get the global minimum staking requirement
     * @return Minimum amount of staking tokens required
     */
    function minStakeRequired() external view returns (uint256);

    /**
     * @notice Get the reputation decay rate per day
     * @return Decay rate in basis points (e.g., 10 = 0.1%)
     */
    function reputationDecayPerDay() external view returns (uint256);

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Set the reputation decay rate per day
     * @param _decayRate Decay rate in basis points (e.g., 10 = 0.1%)
     */
    function setReputationDecay(uint256 _decayRate) external;

    /**
     * @notice Set the global minimum stake required
     * @param _minStake Minimum amount of staking tokens required
     */
    function setMinStakeRequired(uint256 _minStake) external;

    /**
     * @notice Set the minimum stake required for a specific role
     * @param role Role identifier
     * @param _minStake Minimum amount of staking tokens required
     */
    function setRoleMinStake(bytes32 role, uint256 _minStake) external;

    /**
     * @notice Grant UPDATER_ROLE to the SapienCore and ValidationOracle contracts (F-03 fix)
     * @dev Must be called by admin after all contracts are deployed. Can only be called once.
     * @param _core Address of the SapienCore contract
     * @param _oracle Address of the ValidationOracle contract
     */
    function setupProtocolRoles(address _core, address _oracle) external;
}
