// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {IERC4626} from "lib/openzeppelin-contracts/contracts/interfaces/IERC4626.sol";
import {ISapienTrust} from "./interface/ISapienTrust.sol";
import {ISapienVault} from "./interface/ISapienVault.sol";
import {UPDATER_ROLE, UNAUTHORIZED_SKILL_COOLDOWN} from "./interface/ISharedTypes.sol";

/**
 * @title SapienTrust
 * @author Sapien Team
 * @notice Unified identity and reputation layer for Sapien V2
 * @dev Simplified Proof of Quality (PoQ) reputation system with implicit identity via staking.
 */
contract SapienTrust is ISapienTrust, Initializable, AccessControlUpgradeable {
    // ============================================
    // CONSTANTS
    // ============================================

    /// @notice Default reputation score (50%)
    uint256 public constant DEFAULT_REPUTATION = 5000; // 50%

    /// @notice Maximum reputation score (100%)
    uint256 public constant MAX_REPUTATION = 10000; // 100%

    /// @notice Minimum reputation score (5%)
    uint256 public constant MIN_REPUTATION = 500; // 5%

    /// @notice Reputation decrease for slashing (-1%)
    uint256 public constant SLASH_DECREASE = 100; // -1%

    /// @notice Reputation increase for successful actions (+0.1%)
    uint256 public constant SUCCESS_INCREASE = 10; // +0.1%

    /// @notice Reputation decrease for rejected actions (-0.5%)
    uint256 public constant REJECTION_DECREASE = 50; // -0.5%

    // ============================================
    // STATE VARIABLES (ERC-7201 namespaced storage)
    // ============================================

    /// @notice ERC-7201 storage struct for the SapienTrust contract.
    /// @custom:storage-location erc7201:sapien.storage.SapienTrust
    struct SapienTrustStorage {
        /// @notice Reference to the SapienVault contract.
        ISapienVault vault;

        /// @notice Global minimum stake required for participation.
        uint256 minStakeRequired;

        /// @notice Minimum stake required per role.
        mapping(bytes32 => uint256) roleMinStake;

        /// @notice Reputation decay per day in basis points (10000 = 100%).
        uint256 reputationDecayPerDay;

        /// @notice Mapping of user address and role to reputation information.
        mapping(address => mapping(bytes32 => UserReputation)) userReputations;

        /// @notice Mapping of user address and skill name to SkillInfo.
        mapping(address => mapping(string => SkillInfo)) userSkills;

        /// @notice Mapping of user address to the last timestamp their skill was validated.
        mapping(address => uint256) lastSkillValidatedAt;

        /// @notice Mapping of user address to daily accumulated reputation gain.
        mapping(address => uint256) dailyReputationGain;

        /// @notice Mapping of user address to the day their daily gain was last updated.
        mapping(address => uint256) lastGainUpdateDay;

        /// @notice True if protocol roles have been configured, false otherwise.
        bool protocolRolesConfigured;
    }

    /**
     * @notice Retrieves the storage pointer for the SapienTrust contract using ERC-7201 slot calculation.
     * @dev Uses a unique storage slot derived from the contract name for upgradeable storage layout safety.
     * @return $ Storage pointer to the SapienTrustStorage struct.
     */
    function _getSapienTrustStorage() private pure returns (SapienTrustStorage storage $) {
        bytes32 slot =
            keccak256(abi.encode(uint256(keccak256("sapien.storage.SapienTrust")) - 1)) & ~bytes32(uint256(0xff));
        assembly {
            $.slot := slot
        }
    }

    /// @notice Maximum daily reputation gain (1%)
    uint256 public constant MAX_DAILY_GAIN = 100; // 1%

    /// @notice Cooldown period between skill validations (1 day)
    uint256 public constant SKILL_VALIDATION_COOLDOWN = 1 days;

    // ============================================
    // INITIALIZER
    // ============================================

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the SapienTrust contract
     * @dev Sets up the vault reference and initial configuration
     * @param _vault Address of the SapienVault contract
     * @param _minStake Global minimum stake required
     * @param _decayRate Reputation decay rate per day in basis points
     * @param _admin Address to grant DEFAULT_ADMIN_ROLE
     */
    function initialize(address _vault, uint256 _minStake, uint256 _decayRate, address _admin) public initializer {
        if (_vault == address(0) || _admin == address(0)) revert InvalidAddress();

        __AccessControl_init();
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);

        SapienTrustStorage storage $ = _getSapienTrustStorage();
        $.vault = ISapienVault(_vault);
        $.minStakeRequired = _minStake;
        $.reputationDecayPerDay = _decayRate;
    }

    // ============================================
    // IDENTITY FUNCTIONS (IMPLICIT)
    // ============================================

    /**
     * @notice Check if a user is eligible for a role based on their stake.
     * @dev Reverts with InsufficientStake if requirements not met
     * @param user The address to check.
     * @param role The role to check eligibility for.
     */
    function hasEnoughStakeForRole(address user, bytes32 role) public view {
        SapienTrustStorage storage $ = _getSapienTrustStorage();
        uint256 required = $.roleMinStake[role];
        if (required == 0) required = $.minStakeRequired;

        uint256 actual = _getUserStake(user);
        if (actual < required) {
            revert InsufficientStake(role, required, actual);
        }
    }

    /**
     * @notice Check if a user has a validated skill
     * @param user Address of the user
     * @param skill Name of the skill to check
     * @return True if the skill is validated for the user
     */
    function hasValidatedSkill(address user, string calldata skill) external view returns (bool) {
        return _getSapienTrustStorage().userSkills[user][skill].validated;
    }

    /**
     * @notice Mark a skill as validated for a user.
     * @dev Only callable by protocol contracts (SapienCore) after proven quality work.
     * @param user Address of the user
     * @param skill Name of the skill to validate
     */
    function validateSkill(address user, string calldata skill) external onlyRole(UPDATER_ROLE) {
        SapienTrustStorage storage $ = _getSapienTrustStorage();
        if (
            $.lastSkillValidatedAt[user] != 0
                && block.timestamp < $.lastSkillValidatedAt[user] + SKILL_VALIDATION_COOLDOWN
        ) {
            revert Unauthorized(UNAUTHORIZED_SKILL_COOLDOWN);
        }

        $.userSkills[user][skill].validated = true;
        ++$.userSkills[user][skill].completionCount;
        $.lastSkillValidatedAt[user] = block.timestamp;
        emit SkillValidated(user, skill, $.userSkills[user][skill].completionCount);
    }

    // ============================================
    // REPUTATION FUNCTIONS (WITH LAZY DECAY)
    // ============================================

    /**
     * @notice Get the trust score (reputation) of a user for a specific role
     * @dev Applies decay if reputation hasn't been updated recently
     * @param user Address of the user
     * @param role Role identifier
     * @return Reputation score (0-10000, where 5000 is default)
     */
    function getTrustScore(address user, bytes32 role) public view returns (uint256) {
        UserReputation memory rep = _getSapienTrustStorage().userReputations[user][role];
        if (rep.lastUpdated == 0) return DEFAULT_REPUTATION;

        return _applyDecay(rep.score, rep.lastUpdated);
    }

    /**
     * @notice Update a user's reputation based on their performance
     * @dev Applies decay before updating and enforces daily gain limits
     * @param user Address of the user
     * @param role Role identifier
     * @param success True if the action was successful/accurate
     * @param qualityScore Score of the specific action (0-10000, used for bonus calculation)
     */
    function updateReputation(address user, bytes32 role, bool success, uint256 qualityScore)
        external
        onlyRole(UPDATER_ROLE)
    {
        SapienTrustStorage storage $ = _getSapienTrustStorage();
        UserReputation storage rep = $.userReputations[user][role];

        // 1. Initialize if needed
        if (rep.lastUpdated == 0) {
            rep.score = DEFAULT_REPUTATION;
        } else {
            // 2. Apply decay before updating
            rep.score = _applyDecay(rep.score, rep.lastUpdated);
        }

        uint256 oldScore = rep.score;
        ++rep.totalActions;
        rep.lastUpdated = block.timestamp;

        if (success) {
            ++rep.successfulActions;
            // Basic increase + quality bonus
            uint256 bonus = SUCCESS_INCREASE;
            if (qualityScore > 5000) {
                bonus += ((qualityScore - 5000) * 10) / 5000; // Up to +10 bps bonus for high quality
            }

            // Apply daily gain limit
            uint256 currentDay = block.timestamp / 1 days;
            if (currentDay > $.lastGainUpdateDay[user]) {
                $.dailyReputationGain[user] = bonus;
                $.lastGainUpdateDay[user] = currentDay;
            } else {
                if ($.dailyReputationGain[user] + bonus > MAX_DAILY_GAIN) {
                    bonus =
                        MAX_DAILY_GAIN > $.dailyReputationGain[user] ? MAX_DAILY_GAIN - $.dailyReputationGain[user] : 0;
                }
                $.dailyReputationGain[user] += bonus;
            }

            rep.score = _min(rep.score + bonus, MAX_REPUTATION);
        } else {
            // Rejection or Slash
            uint256 penalty = qualityScore == 0 ? SLASH_DECREASE : REJECTION_DECREASE;
            rep.score = _max(rep.score > penalty ? rep.score - penalty : 0, MIN_REPUTATION);
        }

        emit ReputationUpdated(user, role, oldScore, rep.score);
    }

    // ============================================
    // STAKING & SYBIL PROTECTION
    // ============================================

    /**
     * @notice Check if a user meets the global minimum staking requirement
     * @param user Address of the user to check
     * @return True if user meets global minimum requirement
     */
    function hasRequiredStake(address user) public view returns (bool) {
        uint256 minStake = _getSapienTrustStorage().minStakeRequired;
        if (minStake == 0) return true;
        return _getUserStake(user) >= minStake;
    }

    /**
     * @notice Internal helper to get a user's staked amount from the vault
     * @dev Get a user's staked amount from the vault
     * @param user Address of the user
     * @return Amount of assets staked by the user
     */
    function _getUserStake(address user) internal view returns (uint256) {
        ISapienVault v = _getSapienTrustStorage().vault;
        uint256 userShares = IERC20(address(v)).balanceOf(user);
        return IERC4626(address(v)).convertToAssets(userShares);
    }

    // ============================================
    // INTERNAL HELPERS
    // ============================================

    /**
     * @notice Internal helper to apply reputation decay based on time passed
     * @dev Apply reputation decay based on time passed since last update
     * @param currentScore Current reputation score
     * @param lastUpdate Timestamp of last reputation update
     * @return Reputation score after applying decay
     */
    function _applyDecay(uint256 currentScore, uint256 lastUpdate) internal view returns (uint256) {
        uint256 decayRate = _getSapienTrustStorage().reputationDecayPerDay;
        if (decayRate == 0 || lastUpdate == 0) return currentScore;

        uint256 timePassed = block.timestamp - lastUpdate;
        if (timePassed < 1 days) return currentScore;

        // Linear approximation of decay: score * (1 - (decayRate * time) / (10000 * 1 days))
        // If timePassed is large enough that decay >= 100%, return MIN_REPUTATION
        // Check: (timePassed * reputationDecayPerDay) >= (10000 * 1 days)
        if (timePassed * decayRate >= 10000 * 1 days) return MIN_REPUTATION;

        // Multiply before divide to avoid precision loss
        uint256 totalDecay = (currentScore * decayRate * timePassed) / (10000 * 1 days);

        if (totalDecay >= currentScore - MIN_REPUTATION) return MIN_REPUTATION;
        return currentScore - totalDecay;
    }

    /**
     * @notice Return the minimum of two values
     * @dev Return the minimum of two values
     * @param a First value
     * @param b Second value
     * @return Minimum value
     */
    function _min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @notice Return the maximum of two values
     * @dev Return the maximum of two values
     * @param a First value
     * @param b Second value
     * @return Maximum value
     */
    function _max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /**
     * @notice Set the reputation decay rate per day
     * @param _decayRate New decay rate in basis points
     */
    function setReputationDecay(uint256 _decayRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (_decayRate > 10000) revert DecayRateOutOfRange(_decayRate, 10000);
        _getSapienTrustStorage().reputationDecayPerDay = _decayRate;
        emit ReputationDecayUpdated(_decayRate);
    }

    /**
     * @notice Set the global minimum stake required
     * @param _minStake New minimum stake amount
     */
    function setMinStakeRequired(uint256 _minStake) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getSapienTrustStorage().minStakeRequired = _minStake;
        emit MinStakeRequiredUpdated(_minStake);
    }

    /**
     * @notice Set the minimum stake required for a specific role
     * @param role Role identifier
     * @param _minStake New minimum stake amount
     */
    function setRoleMinStake(bytes32 role, uint256 _minStake) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getSapienTrustStorage().roleMinStake[role] = _minStake;
        emit RoleMinStakeUpdated(role, _minStake);
    }

    /**
     * @notice Grant UPDATER_ROLE to the SapienCore and ValidationOracle contracts (F-03 fix)
     * @dev Must be called by admin after all contracts are deployed. Can only be called once.
     *      This ensures that updateReputation() and validateSkill() can be called by protocol contracts.
     * @param _core Address of the SapienCore contract
     * @param _oracle Address of the ValidationOracle contract
     */
    function setupProtocolRoles(address _core, address _oracle) external onlyRole(DEFAULT_ADMIN_ROLE) {
        SapienTrustStorage storage $ = _getSapienTrustStorage();
        if ($.protocolRolesConfigured) revert ProtocolRolesAlreadyConfigured();
        if (_core == address(0) || _oracle == address(0)) revert InvalidAddress();

        _grantRole(UPDATER_ROLE, _core);
        _grantRole(UPDATER_ROLE, _oracle);
        $.protocolRolesConfigured = true;

        emit ProtocolRolesConfigured(_core, _oracle);
    }

    // ============================================
    // VIEW GETTERS (match ISapienTrust interface)
    // ============================================

    function vault() external view returns (ISapienVault) {
        return _getSapienTrustStorage().vault;
    }

    function minStakeRequired() external view returns (uint256) {
        return _getSapienTrustStorage().minStakeRequired;
    }

    function reputationDecayPerDay() external view returns (uint256) {
        return _getSapienTrustStorage().reputationDecayPerDay;
    }

    function roleMinStake(bytes32 role) external view returns (uint256) {
        return _getSapienTrustStorage().roleMinStake[role];
    }
}
