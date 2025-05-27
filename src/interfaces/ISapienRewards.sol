// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

/**
 * @title IRewardToken
 * @dev Interface for the reward token that includes a `releaseTokens` function.
 */
interface IRewardToken is IERC20 {
    /**
     * @notice Allows release of tokens based on `allocationType`.
     * @param allocationType The type of allocation to release tokens for.
     */
    function releaseTokens(uint8 allocationType) external;
}

/**
 * @title ISapienRewards
 * @dev Interface for the SapienRewards contract that manages reward token claims
 *      using EIP-712 signatures and prevents duplicate claims.
 */
interface ISapienRewards {
    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    /// @notice Emitted when a user successfully claims rewards.
    event RewardClaimed(address indexed user, uint256 amount, bytes32 orderId);

    /// @notice Emitted after processing a withdrawal attempt (whether successful or not).
    event WithdrawalProcessed(address indexed user, bytes32 indexed eventOrderId, bool success, string reason);

    /// @notice Emitted when the reward token address is updated.
    event RewardTokenUpdated(address indexed newRewardToken);

    /// @notice Logs the message hash, mainly for debugging or testing.
    event MsgHash(bytes32 msgHash);

    /// @notice Emitted when an upgrade is authorized.
    event UpgradeAuthorized(address indexed implementation);

    // -------------------------------------------------------------
    // Initialization Functions
    // -------------------------------------------------------------

    /**
     * @notice Initializes the contract with the provided authorized signer address.
     *         Sets up the Ownable, Pausable, UUPS, and ReentrancyGuard functionalities.
     * @param _authorizedSigner_ The address authorized to sign reward claims.
     * @param gnosisSafe_ The address of the Gnosis Safe that controls administrative functions.
     */
    function initialize(address _authorizedSigner_, address gnosisSafe_) external;

    /**
     * @notice Authorizes an upgrade to a new implementation.
     * @param newImplementation The address of the new implementation contract.
     */
    function authorizeUpgrade(address newImplementation) external;

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
    function depositTokens(uint256 amount) external;

    /**
     * @notice Allows the contract owners to withdraw tokens from this contract.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawTokens(uint256 amount) external;

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
     * @return The amount of reward tokens in this contract.
     */
    function getContractTokenBalance() external view returns (uint256);

    // -------------------------------------------------------------
    // State Variable Getters
    // -------------------------------------------------------------

    /**
     * @notice Returns the reward token interface.
     * @return The IRewardToken interface instance.
     */
    function rewardToken() external view returns (IRewardToken);

    /**
     * @notice Returns the address of the Gnosis Safe.
     * @return The address of the Gnosis Safe.
     */
    function _gnosisSafe() external view returns (address);
}
