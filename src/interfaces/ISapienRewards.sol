// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {ECDSA} from "src/utils/Common.sol";

/**
 * @title ISapienRewards
 * @dev Interface for the SapienRewards contract that manages reward token claims
 *      using EIP-712 signatures for offchain attestation.
 */
interface ISapienRewards {
    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    /// @notice Emitted when a user successfully claims rewards.
    event RewardClaimed(address indexed user, uint256 amount, bytes32 indexed orderId);

    /// @notice Emitted when the reward token address is updated.
    event RewardTokenUpdated(address indexed newRewardToken);

    /// @notice Emitted when rewards are deposited
    event RewardsDeposited(address indexed depositor, uint256 amount, uint256 newBalance);

    /// @notice Emitted when rewards are withdrawn
    event RewardsWithdrawn(address indexed withdrawer, uint256 amount, uint256 newBalance);

    /// @notice Emitted when unaccounted tokens are recovered
    event UnaccountedTokensRecovered(address indexed recipient, uint256 amount);

    /// @notice Emitted when balance reconciliation occurs
    event RewardsReconciled(uint256 untrackedAmount, uint256 newAvailableBalance);

    /// @notice Emitted when the reward token is set
    event RewardTokenSet(address indexed newRewardToken);

    // -------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------

    /// @notice Thrown when an address parameter is the zero address
    error ZeroAddress();

    /// @notice Thrown when there are insufficient rewards available for a claim
    error InsufficientAvailableRewards();

    /// @notice Thrown when attempting to use an order that has already been redeemed
    error OrderAlreadyUsed();

    /// @notice Thrown when a token transfer operation fails
    error TokenTransferFailed();

    /// @notice Thrown when an invalid reward token address is provided
    error InvalidRewardTokenAddress();

    /// @notice Thrown when an amount parameter is zero or invalid
    error InvalidAmount();

    /// @notice Thrown when there are insufficient unaccounted tokens for recovery
    error InsufficientUnaccountedTokens();

    /// @notice Thrown when a rewards manager attempts to claim rewards
    error RewardsManagerCannotClaim();

    /// @notice Thrown when signature verification fails
    /// @param errorMessage Description of the error
    /// @param error The specific ECDSA recovery error
    error InvalidSignatureOrParameters(string errorMessage, ECDSA.RecoverError error);

    /// @notice Thrown when reward parameters are invalid
    /// @param errorMessage Description of the invalid parameters
    error InvalidRewardParameters(string errorMessage);

    /// @notice Thrown when the signer is not authorized
    /// @param signer The address of the unauthorized signer
    error UnauthorizedSigner(address signer);

    /// @notice Thrown when a reward amount exceeds the maximum allowed
    /// @param rewardAmount The attempted reward amount
    /// @param maxAmount The maximum allowed reward amount
    error RewardExceedsMaxAmount(uint256 rewardAmount, uint256 maxAmount);

    /// @notice Thrown when an invalid order ID is provided
    /// @param orderId The invalid order ID
    error InvalidOrderId(bytes32 orderId);

    // -------------------------------------------------------------
    // Initialization Functions
    // -------------------------------------------------------------

    /**
     * @notice Initializes the contract with the provided admin, reward manager, and reward safe addresses.
     *         Sets up the AccessControl, Pausable, UUPS, and ReentrancyGuard functionalities.
     * @param admin The address that will be granted the DEFAULT_ADMIN_ROLE.
     * @param rewardManager The address that will be granted the REWARD_MANAGER_ROLE.
     * @param rewardSafeAddress The address of the reward safe that will hold the reward tokens.
     * @param newRewardToken The address of the new reward token contract.
     */
    function initialize(address admin, address rewardManager, address rewardSafeAddress, address newRewardToken)
        external;

    // -------------------------------------------------------------
    // Administrative Functions
    // -------------------------------------------------------------

    /**
     * @notice Allows the safe to pause all critical functions in case of emergency.
     */
    function pause() external;

    /**
     * @notice Allows the safe to unpause the contract and resume normal operations.
     */
    function unpause() external;

    /**
     * @notice Sets the reward token address after deployment.
     * @param _rewardToken The address of the new reward token contract.
     */
    function setRewardToken(address _rewardToken) external;

    /**
     * @notice Allows the contract owners to deposit tokens directly into this contract.
     * @param amount The amount of tokens to deposit.
     */
    function depositRewards(uint256 amount) external;

    /**
     * @notice Allows the contract owners to withdraw tokens from this contract.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawRewards(uint256 amount) external;

    // -------------------------------------------------------------
    // Public/External Functions
    // -------------------------------------------------------------

    /**
     * @notice Claims a reward using a valid signature from the authorized signer.
     * @dev Uses EIP-712 for message signing and a mapping to track used order IDs.
     * @param rewardAmount The amount of reward tokens to claim.
     * @param orderId The unique identifier of the order.
     * @param signature The EIP-712 signature from the authorized signer.
     * @return success True if the reward transfer is successful.
     */
    function claimReward(uint256 rewardAmount, bytes32 orderId, bytes memory signature)
        external
        returns (bool success);

    /**
     * @notice Returns the balance of reward tokens held by this contract.
     * @return balance The amount of reward tokens available to claim.
     */
    function getAvailableRewards() external view returns (uint256 balance);

    /**
     * @notice Returns both available rewards and total contract balance
     * @return available Amount available for rewards
     * @return total Total tokens in contract (including direct transfers)
     */
    function getRewardTokenBalances() external view returns (uint256 available, uint256 total);

    /**
     * @notice Emergency function to recover tokens sent directly to contract
     * @param amount Amount to recover from untracked balance
     */
    function recoverUnaccountedTokens(uint256 amount) external;

    /**
     * @notice Validates input parameters and returns the hash to sign
     * @dev Used for server-side generation of the rewards signature
     * @param userWallet The address of the wallet that should receive the reward
     * @param rewardAmount The amount of the reward
     * @param orderId The unique identifier of the order
     * @return hashToSign The EIP-712 hash to be signed
     */
    function validateAndGetHashToSign(address userWallet, uint256 rewardAmount, bytes32 orderId)
        external
        view
        returns (bytes32);

    /**
     * @notice Validates the reward parameters
     * @param userWallet The address of the wallet that should receive the reward
     * @param rewardAmount The amount of the reward
     * @param orderId The unique identifier of the order
     */
    function validateRewardParameters(address userWallet, uint256 rewardAmount, bytes32 orderId) external view;

    /**
     * @notice Returns the status of an order
     * @param user The user's wallet address
     * @param orderId The order ID to check
     * @return True if the order has been redeemed, false otherwise
     */
    function getOrderRedeemedStatus(address user, bytes32 orderId) external view returns (bool);

    /**
     * @notice Returns the domain separator for EIP-712 signatures
     * @dev Used to verify signatures are being built for the correct contract/chain
     * @return The current domain separator
     */
    function getDomainSeparator() external view returns (bytes32);

    /**
     * @notice Reconciles the balance of the contract
     */
    function reconcileBalance() external;
}
