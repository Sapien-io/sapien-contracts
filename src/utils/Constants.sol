// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/**
 * @title Constants
 * @notice Library containing common constants used across Sapien contracts
 * @dev Centralizes constants for better maintainability and consistency
 */
library Constants {
    // -------------------------------------------------------------
    // Token Constants
    // -------------------------------------------------------------

    /// @notice Token decimals (18 for most ERC20 tokens)
    uint256 internal constant TOKEN_DECIMALS = 10 ** 18;

    /// @notice Token Supply 1B
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * TOKEN_DECIMALS;

    // -------------------------------------------------------------
    // Role Constants
    // -------------------------------------------------------------

    /// @notice Role for the default admin
    bytes32 internal constant DEFAULT_ADMIN_ROLE = keccak256("DEFAULT_ADMIN_ROLE");

    /// @notice Role for pausing/unpausing the contract
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role for upgrading the contract
    bytes32 internal constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");

    /// @notice Role for managing the reward token
    bytes32 internal constant REWARD_MANAGER_ROLE = keccak256("REWARD_MANAGER_ROLE");

    /// @notice Role for managing the reward admin / safe
    bytes32 internal constant REWARD_ADMIN_ROLE = keccak256("REWARD_ADMIN_ROLE");

    /// @notice Role for managing quality assurance decisions
    bytes32 internal constant QA_MANAGER_ROLE = keccak256("QA_MANAGER_ROLE");

    /// @notice Role for managing quality assurance decisions
    bytes32 internal constant QA_ADMIN_ROLE = keccak256("QA_ADMIN_ROLE");

    /// @notice Role for managing quality assurance decisions
    bytes32 internal constant SAPIEN_QA_ROLE = keccak256("SAPIEN_QA_ROLE");

    // -------------------------------------------------------------
    // EIP-712 Constants
    // -------------------------------------------------------------

    /// @notice EIP-712 domain separator hashes
    bytes32 internal constant EIP712_DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 internal constant REWARD_CLAIM_TYPEHASH =
        keccak256("RewardClaim(address userWallet,uint256 amount,bytes32 orderId)");

    // -------------------------------------------------------------
    // Time Constants
    // -------------------------------------------------------------

    /// @notice Standard time periods in seconds
    uint256 internal constant SECONDS_PER_MINUTE = 60;
    uint256 internal constant SECONDS_PER_HOUR = 3600;
    uint256 internal constant SECONDS_PER_DAY = 86400;
    uint256 internal constant SECONDS_PER_WEEK = 604800;
    uint256 internal constant SECONDS_PER_YEAR = 31536000; // 365 days

    /// @notice Standard lockup periods
    uint256 internal constant LOCKUP_30_DAYS = 30 days;
    uint256 internal constant LOCKUP_90_DAYS = 90 days;
    uint256 internal constant LOCKUP_180_DAYS = 180 days;
    uint256 internal constant LOCKUP_365_DAYS = 365 days;

    // -------------------------------------------------------------
    // Basis Points and Precision
    // -------------------------------------------------------------

    /// @notice Basis points precision (10000 = 100%)
    uint256 internal constant BASIS_POINTS = 10000;

    /// @notice High precision for calculations (1e18)
    uint256 internal constant PRECISION = 1e18;

    // -------------------------------------------------------------
    // Staking Constants
    // -------------------------------------------------------------

    /// @notice Multiplier constants in basis points
    uint256 internal constant BASE_MULTIPLIER = 10000; // 1.00x
    uint256 internal constant MIN_MULTIPLIER = 10500; // 1.05x at 30 days
    uint256 internal constant MULTIPLIER_90_DAYS = 11000; // 1.10x at 90 days
    uint256 internal constant MULTIPLIER_180_DAYS = 12500; // 1.25x at 180 days
    uint256 internal constant MAX_MULTIPLIER = 15000; // 1.50x at 365 days

    /// @notice Validation tier amount factors (in basis points)
    uint256 internal constant T1_FACTOR = 1000; // 0%
    uint256 internal constant T2_FACTOR = 2500; // 25%
    uint256 internal constant T3_FACTOR = 5000; // 50%
    uint256 internal constant T4_FACTOR = 7500; // 75%
    uint256 internal constant T5_FACTOR = 10000; // 100%

    // -------------------------------------------------------------
    // Reward Constants
    // -------------------------------------------------------------

    // Add this constant at the contract level
    uint256 internal constant MAX_REWARD_AMOUNT = 1000000 * 10 ** 18;

    // -------------------------------------------------------------
    // Default Timelock and Security Constants
    // -------------------------------------------------------------

    /// @notice Standard timelock period for critical operations
    uint256 internal constant DEFAULT_TIMELOCK = 48 hours;

    /// @notice Standard cooldown period for unstaking
    uint256 internal constant COOLDOWN_PERIOD = 2 days;

    /// @notice Standard penalty percentage for early withdrawal
    uint256 internal constant EARLY_WITHDRAWAL_PENALTY = 20; // 20%

    // -------------------------------------------------------------
    // Minimum Values
    // -------------------------------------------------------------

    /// @notice Minimum stake amount (1,000 tokens)
    uint256 internal constant MINIMUM_STAKE_AMOUNT = 1000 * TOKEN_DECIMALS;

    /// @notice Minimum lockup increase period
    uint256 internal constant MINIMUM_LOCKUP_INCREASE = 7 days;

    // -------------------------------------------------------------
    // QA Constants
    // -------------------------------------------------------------

    string internal constant INSUFFICIENT_STAKE_REASON = "Insufficient stake for full penalty";
    string internal constant UNKNOWN_PENALTY_ERROR = "Unknown error processing penalty";
}
