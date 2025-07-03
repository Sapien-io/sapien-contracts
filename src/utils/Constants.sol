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

    string internal constant QA_VERSION = "1";
    string internal constant REWARDS_VERSION = "1";
    string internal constant VAULT_VERSION = "1";

    // -------------------------------------------------------------
    // Token Constants
    // -------------------------------------------------------------

    /// @notice Token decimals (18 for most ERC20 tokens)
    uint256 internal constant TOKEN_DECIMALS = 10 ** 18;

    /// @notice Total token supply (1 billion SAPIEN tokens with 18 decimals)
    uint256 internal constant TOTAL_SUPPLY = 1_000_000_000 * TOKEN_DECIMALS;

    // -------------------------------------------------------------
    // Role Constants
    // -------------------------------------------------------------

    /// @notice Role for pausing/unpausing the contract
    bytes32 internal constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

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

    bytes32 internal constant REWARD_CLAIM_TYPEHASH =
        keccak256("RewardClaim(address userWallet,uint256 amount,bytes32 orderId)");

    bytes32 internal constant QA_DECISION_TYPEHASH = keccak256(
        "QADecision(address userAddress,uint8 actionType,uint256 penaltyAmount,bytes32 decisionId,bytes32 reason,uint256 expiration)"
    );

    // -------------------------------------------------------------
    // Time Constants
    // -------------------------------------------------------------

    /// @notice Standard lockup periods
    uint256 internal constant LOCKUP_30_DAYS = 30 days;
    uint256 internal constant LOCKUP_90_DAYS = 90 days;
    uint256 internal constant LOCKUP_180_DAYS = 180 days;
    uint256 internal constant LOCKUP_365_DAYS = 365 days;

    uint256 internal constant MIN_ORDER_EXPIRY_DURATION = 60 seconds;
    uint256 internal constant MAX_ORDER_EXPIRY_DURATION = 301 seconds;

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
    uint256 internal constant MIN_MULTIPLIER = 10000; // 1.00x (new multiplicative model)
    uint256 internal constant MAX_MULTIPLIER = 15000; // 1.50x at 365 days

    /// @notice Maximum bonus in basis points, 50%
    uint256 internal constant MAX_BONUS = 5000;

    /// @notice Minimum stake amount (1 token)
    uint256 internal constant MINIMUM_STAKE_AMOUNT = 1 * TOKEN_DECIMALS;

    /// @notice Maximum stake amount (2,500 tokens)
    uint256 public constant MAXIMUM_STAKE_AMOUNT = 2500 * TOKEN_DECIMALS;

    /// @notice Minimum unstake amount to prevent precision loss in penalty calculations
    /// @dev Set to 500 wei to ensure at least 100 wei penalty (500 * 20 / 100 = 100)
    uint256 internal constant MINIMUM_UNSTAKE_AMOUNT = 500;

    /// @notice Minimum lockup increase period
    uint256 internal constant MINIMUM_LOCKUP_INCREASE = 30 days;

    /// @notice Standard timelock period for critical operations
    uint256 internal constant DEFAULT_TIMELOCK = 48 hours;

    /// @notice Standard cooldown period for unstaking
    uint256 internal constant COOLDOWN_PERIOD = 2 days;

    /// @notice Standard penalty for early withdrawal in basis points
    uint256 internal constant EARLY_WITHDRAWAL_PENALTY = 2000; // 20% (2000 basis points)

    // -------------------------------------------------------------
    // Reward Constants
    // -------------------------------------------------------------

    // Add this constant at the contract level
    uint256 internal constant MAX_REWARD_AMOUNT = 10_000 * 10 ** 18;

    // -------------------------------------------------------------
    // QA Constants
    // -------------------------------------------------------------

    /// @notice Validity period for QA signatures (24 hours)
    uint256 internal constant QA_SIGNATURE_VALIDITY_PERIOD = 24 hours;

    string internal constant INSUFFICIENT_STAKE_REASON = "Insufficient stake for full penalty";
}
