// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/**
 * @title SapienRewards
 * @notice Sapien AI Rewards Distribution Contract
 * @dev This contract enables secure reward distribution to contributors in the Sapien AI ecosystem.
 *      Contributors earn rewards based on their participation and contributions to the platform.
 *
 * KEY FEATURES:
 * - EIP-712 signature-based reward claims for security and off-chain validation
 * - Order-based tracking system to prevent double claims and replay attacks
 * - Role-based access control for administrators and reward managers
 * - Deposit/withdrawal functionality for reward token management
 * - Emergency pause functionality for security incidents
 * - Balance reconciliation to handle direct token transfers
 *
 * WORKFLOW:
 * 1. Reward administrators deposit reward tokens into the contract
 * 2. Off-chain systems calculate contributor rewards based on participation
 * 3. Authorized reward managers generate EIP-712 signatures for valid claims
 * 4. Contributors use these signatures to claim their earned rewards
 * 5. The contract validates signatures and transfers tokens to claimants
 *
 * SECURITY:
 * - Multi-signature validation ensures only authorized rewards are distributed
 * - Reentrancy protection prevents attack vectors during token transfers
 * - Order ID tracking prevents replay attacks and double spending
 * - Role separation limits access to critical functions
 */
import {
    ECDSA,
    IERC20,
    SafeERC20,
    EIP712Upgradeable,
    PausableUpgradeable,
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
} from "src/utils/Common.sol";

import {ISapienRewards} from "src/interfaces/ISapienRewards.sol";
import {Constants as Const} from "src/utils/Constants.sol";

using ECDSA for bytes32;
using SafeERC20 for IERC20;

/**
 * @title SapienRewards
 * @dev This contract allows users to claim rewards with an EIP-712 offchain signature from the rewards manager.
 */
contract SapienRewards is
    ISapienRewards,
    EIP712Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    /// @dev The reward token.
    IERC20 public rewardToken;

    /// @notice Available reward tokens for claims (tracked locally)
    uint256 private availableRewards;

    /// @notice Mapping of wallet addresses to their redeemed orders.
    mapping(address => mapping(bytes32 => bool)) private redeemedOrders;

    // -------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // -------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------

    /// @notice Returns the version of the contract
    function version() public pure returns (string memory) {
        return Const.REWARDS_VERSION;
    }

    /**
     * @notice Initializes the contract with the provided admin and reward manager.
     * @param admin The address of the role admin. ( default admin )
     * @param rewardAdmin The address of the Rewards admin that manages contributor rewards.
     * @param rewardManager The address of the rewards manager that handles reward claims.
     * @param pauser The address of the pause manager.
     * @param newRewardToken The address of the reward token.
     */
    function initialize(
        address admin,
        address rewardAdmin,
        address rewardManager,
        address pauser,
        address newRewardToken
    ) public initializer {
        if (admin == address(0)) revert ZeroAddress();
        if (rewardManager == address(0)) revert ZeroAddress();
        if (pauser == address(0)) revert ZeroAddress();
        if (rewardAdmin == address(0)) revert ZeroAddress();
        if (newRewardToken == address(0)) revert ZeroAddress();

        __Pausable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        __EIP712_init("SapienRewards", version());

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(Const.PAUSER_ROLE, pauser);
        _grantRole(Const.REWARD_ADMIN_ROLE, rewardAdmin);
        _grantRole(Const.REWARD_MANAGER_ROLE, rewardManager);

        rewardToken = IERC20(newRewardToken);
    }

    // -------------------------------------------------------------
    // Access Control Modifiers
    // -------------------------------------------------------------

    /// @dev Admin Access modifier
    modifier onlyAdmin() {
        if (!hasRole(DEFAULT_ADMIN_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, DEFAULT_ADMIN_ROLE);
        }
        _;
    }

    /// @dev Pauser Access modifier
    modifier onlyPauser() {
        if (!hasRole(Const.PAUSER_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, Const.PAUSER_ROLE);
        }
        _;
    }

    /// @dev Reward Admin Access modifier
    modifier onlyRewardAdmin() {
        if (!hasRole(Const.REWARD_ADMIN_ROLE, msg.sender)) {
            revert AccessControlUnauthorizedAccount(msg.sender, Const.REWARD_ADMIN_ROLE);
        }
        _;
    }

    // -------------------------------------------------------------
    // Role-Based Functions
    // -------------------------------------------------------------

    /**
     * @notice Returns the pauser role identifier
     * @return bytes32 The keccak256 hash of "PAUSER_ROLE"
     */
    function PAUSER_ROLE() external pure returns (bytes32) {
        return Const.PAUSER_ROLE;
    }

    /**
     * @notice Returns the Sapien QA role identifier
     * @return bytes32 The keccak256 hash of "SAPIEN_QA_ROLE"
     */
    function REWARD_ADMIN_ROLE() external pure returns (bytes32) {
        return Const.REWARD_ADMIN_ROLE;
    }

    /**
     * @notice Returns the reward manager role identifier
     * @return bytes32 The keccak256 hash of "REWARD_MANAGER_ROLE"
     */
    function REWARD_MANAGER_ROLE() external pure returns (bytes32) {
        return Const.REWARD_MANAGER_ROLE;
    }

    /**
     * @notice Sets the reward token for the contract.
     * @param newRewardToken The address of the reward token.
     */
    function setRewardToken(address newRewardToken) public onlyAdmin {
        if (newRewardToken == address(0)) {
            revert ZeroAddress();
        }
        rewardToken = IERC20(newRewardToken);

        availableRewards = 0;

        emit RewardTokenSet(newRewardToken);
    }

    /**
     * @notice Allows the safe to pause all critical functions in case of emergency
     * @dev Only callable by the safe
     */
    function pause() external onlyPauser {
        _pause();
    }

    /**
     * @notice Allows the safe to unpause the contract and resume normal operations
     * @dev Only callable by the safe
     */
    function unpause() external onlyPauser {
        _unpause();
    }

    /**
     * @notice Allows for the deposit of reward tokens directly into this contract.
     * @param amount The amount of tokens to deposit.
     */
    function depositRewards(uint256 amount) external onlyRewardAdmin {
        if (amount == 0) revert InvalidAmount();

        rewardToken.safeTransferFrom(msg.sender, address(this), amount);
        availableRewards += amount;

        emit RewardsDeposited(msg.sender, amount, availableRewards);
    }

    /**
     * @notice Allows the contract owners to withdraw tokens from this contract.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawRewards(uint256 amount) external onlyRewardAdmin {
        if (amount == 0) revert InvalidAmount();
        if (amount > availableRewards) revert InsufficientAvailableRewards();

        availableRewards -= amount;
        rewardToken.safeTransfer(msg.sender, amount);

        emit RewardsWithdrawn(msg.sender, amount, availableRewards);
    }

    /**
     * @notice Emergency function to recover tokens sent directly to contract
     * @param amount Amount to recover from untracked balance
     */
    function recoverUnaccountedTokens(uint256 amount) external onlyRewardAdmin {
        uint256 totalBalance = rewardToken.balanceOf(address(this));
        uint256 unaccounted = totalBalance - availableRewards;

        if (amount > unaccounted) revert InsufficientUnaccountedTokens();

        rewardToken.safeTransfer(msg.sender, amount);
        emit UnaccountedTokensRecovered(msg.sender, amount);
    }

    /**
     * @notice Reconciles the balance of the reward token
     * @dev Only callable by the reward safe
     */
    function reconcileBalance() external onlyRewardAdmin {
        _reconcileBalance();
    }

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
        public
        nonReentrant
        whenNotPaused
        returns (bool success)
    {
        _verifyOrder(msg.sender, rewardAmount, orderId, signature);

        _markOrderAsRedeemed(msg.sender, orderId);

        availableRewards -= rewardAmount;
        rewardToken.safeTransfer(msg.sender, rewardAmount);

        emit RewardClaimed(msg.sender, rewardAmount, orderId);
        return true;
    }

    /**
     * @notice Returns the status of an order
     * @param user The user's wallet address
     * @param orderId The order ID to check
     * @return isRedeemed True if the order has been redeemed, false otherwise
     */
    function getOrderRedeemedStatus(address user, bytes32 orderId) public view returns (bool isRedeemed) {
        return redeemedOrders[user][orderId];
    }

    /**
     * @notice Returns the balance of reward tokens held by this contract.
     * @return availableBalance amount of rewards available to claim.
     */
    function getAvailableRewards() public view returns (uint256 availableBalance) {
        return availableRewards;
    }

    /**
     * @notice Returns both available rewards and total contract balance
     * @return availableBalance Amount available for rewards
     * @return totalContractBalance Total tokens in contract (including direct transfers)
     */
    function getRewardTokenBalances() public view returns (uint256 availableBalance, uint256 totalContractBalance) {
        return (availableRewards, rewardToken.balanceOf(address(this)));
    }

    // -------------------------------------------------------------
    // EIP-712 View Functions (for offchain signature generation)
    // -------------------------------------------------------------

    /**
     * @notice Validates input parameters and returns the hash to sign
     *  This is used for server-side generation of the rewards signature to provide the user to claimRewards.
     *  This allows the server to create an attestation for the rewards a user is due based on their contributions.
     * @dev Includes parameter validation for server-side verification
     * @param userWallet The address of the wallet that should receive the reward
     * @param rewardAmount The amount of the reward
     * @param orderId The unique identifier of the order
     * @return hashToSign The EIP-712 hash to be signed (only valid if isValid is true)
     */
    function validateAndGetHashToSign(address userWallet, uint256 rewardAmount, bytes32 orderId)
        public
        view
        returns (bytes32 hashToSign)
    {
        if (rewardAmount == 0) revert InvalidAmount();
        if (orderId == bytes32(0)) revert InvalidOrderId(orderId);

        // Extract and validate expiry
        // orderId is a 256 bit value, we need to extract the last 64 bits which is the expiry timestamp
        uint64 orderTimestamp = uint64(uint256(orderId));

        // Expiry checks - check expiry first
        if (block.timestamp >= orderTimestamp) {
            revert OrderExpired(orderId, orderTimestamp);
        }
        if (orderTimestamp < block.timestamp + Const.MIN_ORDER_EXPIRY_DURATION) {
            revert ExpiryTooSoon(orderId, orderTimestamp);
        }
        if (orderTimestamp > block.timestamp + Const.MAX_ORDER_EXPIRY_DURATION) {
            revert ExpiryTooFar(orderId, orderTimestamp);
        }

        if (rewardAmount > availableRewards) revert InsufficientAvailableRewards();
        if (redeemedOrders[userWallet][orderId]) revert OrderAlreadyUsed();
        if (hasRole(Const.REWARD_MANAGER_ROLE, userWallet)) revert RewardsManagerCannotClaim();
        if (rewardAmount > Const.MAX_REWARD_AMOUNT) {
            revert RewardExceedsMaxAmount(rewardAmount, Const.MAX_REWARD_AMOUNT);
        }

        bytes32 structHash = keccak256(abi.encode(Const.REWARD_CLAIM_TYPEHASH, userWallet, rewardAmount, orderId));

        return _hashTypedDataV4(structHash);
    }

    // -------------------------------------------------------------
    // Internal / Private Functions
    // -------------------------------------------------------------

    /**
     * @dev Verifies the signature using EIP-712 typed data hashing.
     * @param userWallet The address of the wallet that should receive the reward.
     * @param rewardAmount The amount of the reward.
     * @param orderId The unique identifier of the order.
     * @param signature The EIP-712 signature from the authorized signer.
     * @dev Reverts with InvalidRewardParameters if parameters are invalid
     * @dev Reverts with InvalidSignatureOrParameters if signature is malformed
     * @dev Reverts with UnauthorizedSigner if signer lacks REWARD_MANAGER_ROLE
     */
    function _verifyOrder(address userWallet, uint256 rewardAmount, bytes32 orderId, bytes memory signature)
        private
        view
    {
        bytes32 hashToSign = validateAndGetHashToSign(userWallet, rewardAmount, orderId);
        (address signer, ECDSA.RecoverError error,) = hashToSign.tryRecover(signature);

        if (error != ECDSA.RecoverError.NoError) {
            revert InvalidSignatureOrParameters("Signature recovery failed", error);
        }

        if (!hasRole(Const.REWARD_MANAGER_ROLE, signer)) {
            revert UnauthorizedSigner(signer);
        }
    }

    /**
     * @dev Marks an `orderId` as redeemed for the user.
     * @param user The user's wallet address.
     * @param orderId The ID of the order to mark as redeemed.
     */
    function _markOrderAsRedeemed(address user, bytes32 orderId) private {
        redeemedOrders[user][orderId] = true;
    }

    /**
     * @notice Automatically reconciles tracked vs actual balance
     * @dev Adds any untracked tokens to available rewards
     */
    function _reconcileBalance() private {
        uint256 actualBalance = rewardToken.balanceOf(address(this));

        if (actualBalance > availableRewards) {
            uint256 untracked = actualBalance - availableRewards;
            availableRewards = actualBalance;

            emit RewardsReconciled(untracked, availableRewards);
        }
    }
}
