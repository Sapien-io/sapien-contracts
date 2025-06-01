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

    event RewardClaimed(address indexed user, uint256 amount, bytes32 indexed orderId);
    event RewardTokenUpdated(address indexed newRewardToken);
    event RewardsDeposited(address indexed depositor, uint256 amount, uint256 newBalance);
    event RewardsWithdrawn(address indexed withdrawer, uint256 amount, uint256 newBalance);
    event UnaccountedTokensRecovered(address indexed recipient, uint256 amount);
    event RewardsReconciled(uint256 untrackedAmount, uint256 newAvailableBalance);
    event RewardTokenSet(address indexed newRewardToken);

    // -------------------------------------------------------------
    // Errors
    // -------------------------------------------------------------

    error ZeroAddress();
    error InsufficientAvailableRewards();
    error OrderAlreadyUsed();
    error TokenTransferFailed();
    error InvalidRewardTokenAddress();
    error InvalidAmount();
    error InsufficientUnaccountedTokens();
    error RewardsManagerCannotClaim();
    error InvalidSignatureOrParameters(string errorMessage, ECDSA.RecoverError error);
    error InvalidRewardParameters(string errorMessage);
    error UnauthorizedSigner(address signer);
    error RewardExceedsMaxAmount(uint256 rewardAmount, uint256 maxAmount);
    error InvalidOrderId(bytes32 orderId);

    // -------------------------------------------------------------
    //  Functions
    // -------------------------------------------------------------

    function initialize(address admin, address rewardManager, address rewardSafeAddress, address newRewardToken)
        external;

    function pause() external;
    function unpause() external;
    function setRewardToken(address _rewardToken) external;

    function depositRewards(uint256 amount) external;
    function withdrawRewards(uint256 amount) external;
    function reconcileBalance() external;
    function recoverUnaccountedTokens(uint256 amount) external;

    function claimReward(uint256 rewardAmount, bytes32 orderId, bytes memory signature)
        external
        returns (bool success);

    function getAvailableRewards() external view returns (uint256 balance);
    function getRewardTokenBalances() external view returns (uint256 available, uint256 total);
    function getOrderRedeemedStatus(address user, bytes32 orderId) external view returns (bool);
    function getDomainSeparator() external view returns (bytes32);

    function validateAndGetHashToSign(address userWallet, uint256 rewardAmount, bytes32 orderId)
        external
        view
        returns (bytes32);
    function validateRewardParameters(address userWallet, uint256 rewardAmount, bytes32 orderId) external view;
}
