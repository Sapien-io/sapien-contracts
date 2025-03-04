// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

/**
 * @title IRewardToken
 * @dev Interface for the reward token that includes a `releaseTokens` function.
 */
interface IRewardToken is IERC20 {
    /**
     * @notice Allows release of tokens based on `allocationType`.
     * @param allocationType The type of allocation to release tokens for.
     */
    function releaseTokens(string calldata allocationType) external;
}

/**
 * @title SapienRewards
 * @dev This contract manages reward token claims using EIP-712 signatures and a Bloom filter
 *      to prevent duplicate claims (by tracking used order IDs). It supports upgrading via UUPS.
 *
 *      - Users can claim rewards if they have a valid signature from an authorized signer.
 *      - Orders (identified by `orderId`) are tracked in a user-specific Bloom filter to prevent reuse.
 *      - Owners can deposit/withdraw tokens, pause the contract, and release tokens from the reward token.
 *      - Contract is upgradeable via UUPS (only owner can authorize an upgrade).
 */
contract SapienRewards is 
    Initializable, 
    OwnableUpgradeable, 
    PausableUpgradeable, 
    UUPSUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    using ECDSA for bytes32;

    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    /// @dev The reward token interface used for transfers and release calls.
    IRewardToken public rewardToken;

    /// @dev The address that is authorized to sign reward claims.
    address private authorizedSigner;

    /// @notice Mapping of wallet addresses to their redeemed order IDs.
    mapping(address => mapping(bytes32 => bool)) private redeemedOrders;

    // EIP-712 domain separator hashes
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant REWARD_CLAIM_TYPEHASH = keccak256(
        "RewardClaim(address userWallet,uint256 amount,string orderId)"
    );

    /// @notice EIP-712 domain separator for this contract.
    bytes32 private DOMAIN_SEPARATOR;

    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    /// @notice Emitted when a user successfully claims rewards.
    event RewardClaimed(address indexed user, uint256 amount, string orderId);

    /// @notice Emitted after processing a withdrawal attempt (whether successful or not).
    event WithdrawalProcessed(address indexed user, string indexed eventOrderId, bool success, string reason);

    /// @notice Emitted when the reward token address is updated.
    event RewardTokenUpdated(address indexed newRewardToken);

    /// @notice Emitted when tokens are released to this contract from the RewardToken contract.
    event TokensReleasedToContract(string allocationType);

    /// @notice Emitted if needed to show successful signature verification steps.
    event SignatureVerified(address user, uint256 amount, string orderId);

    /// @notice Logs the message hash, mainly for debugging or testing.
    event MsgHash(bytes32 msgHash);

    /// @notice Logs the recovered signer, mainly for debugging or testing.
    event RecoveredSigner(address signer);

    // -------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------

    /**
     * @dev Ensures the contract holds enough reward tokens before processing a claim.
     * @param amount The amount of tokens required.
     */
    modifier hasTokenBalance(uint256 amount) {
        require(
            rewardToken.balanceOf(address(this)) >= amount,
            "Insufficient token balance"
        );
        _;
    }

    // -------------------------------------------------------------
    // Initialization (UUPS-related)
    // -------------------------------------------------------------

    /**
     * @notice Initializes the contract with the provided authorized signer address.
     *         Sets up the Ownable, Pausable, UUPS, and ReentrancyGuard functionalities.
     * @param _authorizedSigner The address authorized to sign reward claims.
     */
    function initialize(address _authorizedSigner) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        authorizedSigner = _authorizedSigner;

        // Initialize domain separator for EIP-712
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("SapienRewards"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Authorizes an upgrade to a new implementation (UUPS). 
     *         Only the contract owner can perform this action.
     * @param newImplementation The address of the new implementation.
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    // -------------------------------------------------------------
    // Owner Functions
    // -------------------------------------------------------------

    /**
     * @notice Sets the reward token address after deployment.
     * @param _rewardToken The address of the new reward token contract.
     */
    function setRewardToken(address _rewardToken) external onlyOwner {
        require(_rewardToken != address(0), "Invalid reward token address");
        rewardToken = IRewardToken(_rewardToken);
        emit RewardTokenUpdated(_rewardToken);
    }

    /**
     * @notice Calls the `releaseTokens` function on the reward token contract.
     *         This allows the owner to release tokens into this contract.
     * @param allocationType The type of allocation to release tokens for.
     */
    function releaseRewardTokens(string calldata allocationType) 
        external 
        onlyOwner 
        whenNotPaused 
    {
        rewardToken.releaseTokens(allocationType);
        emit TokensReleasedToContract(allocationType);
    }

    /**
     * @notice Allows the contract owner to deposit tokens directly into this contract.
     * @param amount The amount of tokens to deposit.
     */
    function depositTokens(uint256 amount) external onlyOwner {
        require(
            rewardToken.transferFrom(msg.sender, address(this), amount),
            "Token deposit failed"
        );
    }

    /**
     * @notice Allows the contract owner to withdraw tokens from this contract.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawTokens(uint256 amount) external onlyOwner {
        require(
            rewardToken.transfer(owner(), amount),
            "Token withdrawal failed"
        );
    }

    // -------------------------------------------------------------
    // Public/External Functions
    // -------------------------------------------------------------

    /**
     * @notice Claims a reward using a valid signature from the authorized signer.
     * @dev Uses EIP-712 for message signing and a Bloom filter to track used order IDs.
     * @param rewardAmount The amount of reward tokens to claim.
     * @param orderId The unique identifier of the order.
     * @param signature The EIP-712 signature from the authorized signer.
     * @return success True if the reward transfer is successful.
     */
    function claimReward(
        uint256 rewardAmount,
        string calldata orderId,
        bytes memory signature
    )
        external
        hasTokenBalance(rewardAmount)
        nonReentrant
        whenNotPaused
        returns (bool success)
    {
        require(
            verifyOrder(msg.sender, rewardAmount, orderId, signature),
            "Invalid signature or mismatched parameters"
        );

        require(
            !isOrderRedeemed(msg.sender, orderId),
            "Order ID already used"
        );

        addOrderToBloomFilter(msg.sender, orderId);

        success = rewardToken.transfer(msg.sender, rewardAmount);
        string memory reason = success ? "" : "Token transfer failed";

        emit WithdrawalProcessed(msg.sender, orderId, success, reason);

        if (!success) revert("Token transfer failed");
        
        emit RewardClaimed(msg.sender, rewardAmount, orderId);
        return true;
    }

    /**
     * @notice Returns the balance of reward tokens held by this contract.
     * @return The amount of reward tokens in this contract.
     */
    function getContractTokenBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    // -------------------------------------------------------------
    // Internal Functions (Bloom Filter)
    // -------------------------------------------------------------

    /**
     * @dev Checks if a given `orderId` has been redeemed by the user.
     * @param user The user's wallet address.
     * @param orderId The ID of the order to check.
     * @return True if the `orderId` is already redeemed; otherwise, false.
     */
    function isOrderRedeemed(address user, string calldata orderId) 
        internal 
        view 
        returns (bool) 
    {
        return redeemedOrders[user][keccak256(abi.encodePacked(orderId))];
    }

    /**
     * @dev Marks an `orderId` as redeemed for the user.
     * @param user The user's wallet address.
     * @param orderId The ID of the order to mark as redeemed.
     */
    function addOrderToBloomFilter(address user, string calldata orderId) internal {
        redeemedOrders[user][keccak256(abi.encodePacked(orderId))] = true;
    }

    // -------------------------------------------------------------
    // Internal Functions (EIP-712 Verification)
    // -------------------------------------------------------------

    /**
     * @dev Verifies the signature using EIP-712 typed data hashing.
     * @param userWallet The address of the wallet that should receive the reward.
     * @param rewardAmount The amount of the reward.
     * @param orderId The unique identifier of the order.
     * @param signature The EIP-712 signature from the authorized signer.
     * @return True if the recovered signer matches the `authorizedSigner`.
     */
    function verifyOrder(
        address userWallet,
        uint256 rewardAmount,
        string calldata orderId,
        bytes memory signature
    ) 
        private 
        view 
        returns (bool) 
    {
        bytes32 structHash = keccak256(
            abi.encode(
                REWARD_CLAIM_TYPEHASH,
                userWallet,
                rewardAmount,
                keccak256(bytes(orderId))
            )
        );

        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        address signer = hash.recover(signature);
        return (signer == authorizedSigner);
    }

    // -------------------------------------------------------------
    // (Optional) Helper Functions for Message Hashing & Recovery
    // -------------------------------------------------------------

    /**
     * @notice Calculates a simple message hash of the claim parameters (not EIP-712).
     * @dev This is a helper, not used in the main flow, left for reference.
     * @param userWallet The address of the wallet.
     * @param rewardAmount The amount of the reward.
     * @param orderId The order identifier.
     * @return The keccak256 hash of the concatenated parameters.
     */
    function getMessageHash(
        address userWallet, 
        uint256 rewardAmount, 
        string calldata orderId
    ) 
        private 
        pure 
        returns (bytes32) 
    {
        return keccak256(abi.encodePacked(userWallet, rewardAmount, orderId));
    }

    /**
     * @notice Recovers the signer address from a given signature and a message hash (not EIP-712).
     * @dev This is a helper, not used in the main EIP-712 flow, left for reference.
     * @param messageHash The plain (non-EIP-712) message hash.
     * @param signature The signature to recover the signer from.
     * @return The address that signed the hashed message.
     */
    function recoverSigner(bytes32 messageHash, bytes memory signature) 
        private 
        pure 
        returns (address) 
    {
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }

    /**
     * @notice Splits a signature into (r, s, v) components.
     * @dev This is a helper function for signature splitting, not used in the main EIP-712 flow.
     * @param sig The signature bytes (must be 65 bytes long).
     * @return r The r component of the signature.
     * @return s The s component of the signature.
     * @return v The v component (recovery id) of the signature.
     */
    function splitSignature(bytes memory sig) 
        private 
        pure 
        returns (bytes32 r, bytes32 s, uint8 v) 
    {
        require(sig.length == 65, "Invalid signature length");
        assembly {
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }
}

