// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";

/**
 * @title ISapienStaking
 * @dev Interface for the SapienStaking contract that enables users to stake tokens
 *      for specific lock-up periods with multipliers and EIP-712 signature verification.
 */
interface ISapienStaking {
    // -------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------

    /**
     * @dev Struct holding staking details for each staker and their specific stake (by orderId).
     * @param amount The amount of tokens staked.
     * @param lockUpPeriod The duration of the lock-up in seconds.
     * @param startTime The timestamp when the stake started.
     * @param multiplier The multiplier applicable to the stake.
     * @param cooldownStart The timestamp when the user initiated unstaking.
     * @param cooldownAmount The amount approved for unstaking during cooldown.
     * @param isActive Indicates if this stake is currently active.
     */
    struct StakingInfo {
        uint256 amount;
        uint256 lockUpPeriod;
        uint256 startTime;
        uint256 multiplier;
        uint256 cooldownStart;
        uint256 cooldownAmount;
        bool isActive;
    }

    /**
     * @dev Action types for EIP-712 signatures.
     * STAKE: Stake tokens;
     * INITIATE_UNSTAKE: Start the cooldown;
     * UNSTAKE: Finalize after cooldown;
     * INSTANT_UNSTAKE: Immediately unstake with a penalty.
     */
    enum ActionType {
        STAKE,
        INITIATE_UNSTAKE,
        UNSTAKE,
        INSTANT_UNSTAKE
    }

    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    /**
     * @notice Emitted when a user stakes tokens.
     * @param user The user's address.
     * @param amount The amount staked.
     * @param multiplier The applied multiplier for this stake.
     * @param lockUpPeriod The lock-up duration in seconds.
     * @param orderId The unique identifier for this stake request.
     */
    event Staked(address indexed user, uint256 amount, uint256 multiplier, uint256 lockUpPeriod, bytes32 orderId);

    /**
     * @notice Emitted when a user initiates the unstaking process (starts cooldown).
     * @param user The user's address initiating unstake.
     * @param amount The staked amount associated with the stake.
     * @param orderId The unique identifier for the original stake.
     */
    event UnstakingInitiated(address indexed user, uint256 amount, bytes32 orderId);

    /**
     * @notice Emitted when a user completes unstaking after the cooldown.
     * @param user The user's address.
     * @param amount The amount unstaked.
     * @param orderId The unique identifier for the original stake.
     */
    event Unstaked(address indexed user, uint256 amount, bytes32 orderId);

    /**
     * @notice Emitted when a user performs an instant unstake (penalty applied).
     * @param user The user's address.
     * @param amount The amount actually received by the user (penalty deducted).
     * @param orderId The unique identifier for the original stake.
     */
    event InstantUnstake(address indexed user, uint256 amount, bytes32 orderId);

    /// @notice Emitted when an upgrade is authorized.
    event UpgradeAuthorized(address indexed implementation);

    // -------------------------------------------------------------
    // Initialization Functions
    // -------------------------------------------------------------

    /**
     * @notice Initializes the SapienStaking contract.
     * @param sapienToken_ The ERC20 token contract for Sapien.
     * @param sapienAddress_ The address authorized to sign stake actions.
     * @param gnosisSafe_ The address of the Gnosis Safe.
     */
    function initialize(ERC20Upgradeable sapienToken_, address sapienAddress_, address gnosisSafe_) external;

    /**
     * @notice Authorizes an upgrade of this contract to a new implementation (UUPS).
     * @param newImplementation The address of the new contract implementation.
     */
    function authorizeUpgrade(address newImplementation) external;

    // -------------------------------------------------------------
    // Administrative Functions
    // -------------------------------------------------------------

    /**
     * @notice Pauses the contract, preventing certain actions (e.g., staking/unstaking).
     */
    function pause() external;

    /**
     * @notice Unpauses the contract, allowing staking/unstaking.
     */
    function unpause() external;

    // -------------------------------------------------------------
    // Staking Functions
    // -------------------------------------------------------------

    /**
     * @notice Stake a specified `amount` of tokens for a given `lockUpPeriod`,
     *         identified by a unique `orderId` and validated by an EIP-712 signature.
     * @param amount The amount of tokens to stake.
     * @param lockUpPeriod The lock-up duration in seconds (30/90/180/365 days).
     * @param orderId A unique identifier for this stake request.
     * @param signature The EIP-712 signature from the authorized signer.
     */
    function stake(uint256 amount, uint256 lockUpPeriod, bytes32 orderId, bytes memory signature) external;

    /**
     * @notice Initiates the cooldown for unstaking.
     * @param amount The amount intended for unstaking (used for signature validation).
     * @param newOrderId A new unique identifier for this action.
     * @param stakeOrderId The original stake `orderId` that the user wants to unstake from.
     * @param signature The EIP-712 signature from the authorized signer.
     */
    function initiateUnstake(uint256 amount, bytes32 newOrderId, bytes32 stakeOrderId, bytes memory signature)
        external;

    /**
     * @notice Completes the unstaking process after the cooldown period has passed.
     * @param amount The amount to unstake (used for signature validation).
     * @param newOrderId A new unique identifier for this action.
     * @param stakeOrderId The original stake `orderId` the user is unstaking from.
     * @param signature The EIP-712 signature from the authorized signer.
     */
    function unstake(uint256 amount, bytes32 newOrderId, bytes32 stakeOrderId, bytes memory signature) external;

    /**
     * @notice Instantly unstakes a specified `amount`, incurring a penalty (20% by default).
     * @param amount The amount to unstake instantly.
     * @param newOrderId A new unique identifier for this action.
     * @param stakeOrderId The original stake `orderId` the user is instantly unstaking from.
     * @param signature The EIP-712 signature from the authorized signer.
     */
    function instantUnstake(uint256 amount, bytes32 newOrderId, bytes32 stakeOrderId, bytes memory signature)
        external;

    // -------------------------------------------------------------
    // View Functions
    // -------------------------------------------------------------

    /**
     * @notice Returns the total amount of tokens staked in this contract.
     * @return The total staked amount.
     */
    function totalStaked() external view returns (uint256);

    /**
     * @notice Returns the address of the Gnosis Safe.
     * @return The address of the Gnosis Safe.
     */
    function _gnosisSafe() external view returns (address);

    // -------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------

    /**
     * @notice Returns the minimum stake amount (1,000 SAPIEN).
     * @return The minimum stake amount.
     */
    function MINIMUM_STAKE() external pure returns (uint256);

    /**
     * @notice Returns the maximum multiplier for 1 month lock-up (105.00%).
     * @return The multiplier value.
     */
    function ONE_MONTH_MAX_MULTIPLIER() external pure returns (uint256);

    /**
     * @notice Returns the maximum multiplier for 3 months lock-up (110.00%).
     * @return The multiplier value.
     */
    function THREE_MONTHS_MAX_MULTIPLIER() external pure returns (uint256);

    /**
     * @notice Returns the maximum multiplier for 6 months lock-up (125.00%).
     * @return The multiplier value.
     */
    function SIX_MONTHS_MAX_MULTIPLIER() external pure returns (uint256);

    /**
     * @notice Returns the maximum multiplier for 12 months lock-up (150.00%).
     * @return The multiplier value.
     */
    function TWELVE_MONTHS_MAX_MULTIPLIER() external pure returns (uint256);

    /**
     * @notice Returns the cooldown period before unstaking (2 days).
     * @return The cooldown period in seconds.
     */
    function COOLDOWN_PERIOD() external pure returns (uint256);
}
