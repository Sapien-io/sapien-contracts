// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/**
 * @title Constants
 * @notice Library containing common constants used across Sapien contracts
 * @dev Centralizes constants for better maintainability and consistency
 */
library Constants {
    // -------------------------------------------------------------
    // Version Constants
    // -------------------------------------------------------------

    string internal constant QA_VERSION = "0.1.3";
    string internal constant REWARDS_VERSION = "0.1.3";
    string internal constant VAULT_VERSION = "0.1.3";

    // -------------------------------------------------------------
    // Token Constants
    // -------------------------------------------------------------

    /// @notice Token decimals (18 for most ERC20 tokens)
    uint256 internal constant TOKEN_DECIMALS = 10 ** 18;

    /// @notice Total token supply (1 billion SAPIEN tokens with 18 decimals)
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * TOKEN_DECIMALS;

    // -------------------------------------------------------------
    // Role Constants
    // -------------------------------------------------------------

    /// @notice Role for the default admin
    bytes32 internal constant DEFAULT_ADMIN_ROLE = 0x0000000000000000000000000000000000000000000000000000000000000000;

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

    /// @notice Role for signing quality assurance decisions
    bytes32 internal constant QA_SIGNER_ROLE = keccak256("QA_SIGNER_ROLE");

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

    bytes32 internal constant QA_DECISION_TYPEHASH = keccak256(
        "QADecision(address userAddress,uint8 actionType,uint256 penaltyAmount,bytes32 decisionId,bytes32 reason,uint256 expiration)"
    );

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

    /// @notice Amount tier thresholds in tokens (not including decimals)
    uint256 internal constant TIER_1_THRESHOLD = 1000; // 1,000 tokens
    uint256 internal constant TIER_2_THRESHOLD = 2500; // 2,500 tokens
    uint256 internal constant TIER_3_THRESHOLD = 5000; // 5,000 tokens
    uint256 internal constant TIER_4_THRESHOLD = 7500; // 7,500 tokens
    uint256 internal constant TIER_5_THRESHOLD = 10000; // 10,000 tokens

    /// @notice Minimum stake amount (1,000 tokens)
    uint256 internal constant MINIMUM_STAKE_AMOUNT = 250 * TOKEN_DECIMALS;

    /// @notice Maximum stake amount (10,000,000 tokens)
    uint256 internal constant MAXIMUM_STAKE_AMOUNT = 10_000_000 * TOKEN_DECIMALS;

    /// @notice Minimum unstake amount to prevent precision loss in penalty calculations
    /// @dev Set to 500 wei to ensure at least 100 wei penalty (500 * 20 / 100 = 100)
    uint256 internal constant MINIMUM_UNSTAKE_AMOUNT = 500;

    /// @notice Minimum lockup increase period
    uint256 internal constant MINIMUM_LOCKUP_INCREASE = 30 days;

    /// @notice Standard timelock period for critical operations
    uint256 internal constant DEFAULT_TIMELOCK = 48 hours;

    /// @notice Standard cooldown period for unstaking
    uint256 internal constant COOLDOWN_PERIOD = 2 days;

    /// @notice Standard penalty percentage for early withdrawal
    uint256 internal constant EARLY_WITHDRAWAL_PENALTY = 20; // 20%

    // -------------------------------------------------------------
    // Reward Constants
    // -------------------------------------------------------------

    // Add this constant at the contract level
    uint256 internal constant MAX_REWARD_AMOUNT = 1000000 * 10 ** 18;

    // -------------------------------------------------------------
    // QA Constants
    // -------------------------------------------------------------

    /// @notice Validity period for QA signatures (24 hours)
    uint256 internal constant QA_SIGNATURE_VALIDITY_PERIOD = 24 hours;

    string internal constant INSUFFICIENT_STAKE_REASON = "Insufficient stake for full penalty";
    string internal constant UNKNOWN_PENALTY_ERROR = "Unknown error processing penalty";
}
