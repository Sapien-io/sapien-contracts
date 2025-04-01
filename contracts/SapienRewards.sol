// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
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
    function releaseTokens(uint8 allocationType) external;
}

/**
 * @title SapienRewards
 * @dev This contract manages reward token claims using EIP-712 signatures and a map
 *      to prevent duplicate claims (by tracking used order IDs). It supports upgrading via UUPS.
 *
 *      - Users can claim rewards if they have a valid signature from an authorized signer.
 *      - Orders (identified by `orderId`) are tracked in a user-specific mapping to prevent reuse.
 *      - Owners can deposit/withdraw tokens, pause the contract, and release tokens from the reward token.
 *      - Contract is upgradeable via UUPS (only owner can authorize an upgrade).
 */
contract SapienRewards is 
    Initializable, 
    Ownable2StepUpgradeable,
    PausableUpgradeable, 
    UUPSUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    using ECDSA for bytes32;

    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    /// @dev The address of the Gnosis Safe that controls administrative functions (effectively immutable, but can't use immutable keyword due to upgradeability)
    address public _gnosisSafe;

    /// @dev The reward token interface used for transfers and release calls.
    IRewardToken public rewardToken;

    /// @dev The address that is authorized to sign reward claims.
    /// @dev Effectively immutable, but can't use immutable keyword due to upgradeability
    address private _authorizedSigner;


    /// @notice Mapping of wallet addresses to their redeemed order IDs.
    mapping(address => mapping(bytes32 => bool)) private redeemedOrders;

    // EIP-712 domain separator hashes
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant REWARD_CLAIM_TYPEHASH = keccak256(
        "RewardClaim(address userWallet,uint256 amount,bytes32 orderId)"
    );

    /// @notice EIP-712 domain separator for this contract.
    bytes32 private DOMAIN_SEPARATOR;

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

    /// @notice Mapping of owner addresses to whether they are authorized to upgrade.
    mapping(address => bool) private _upgradeAuthorized;
    event UpgradeAuthorized(address indexed implementation);


    // -------------------------------------------------------------
    // Constructor
    // -------------------------------------------------------------

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // -------------------------------------------------------------
    // Initialization (UUPS-related)
    // -------------------------------------------------------------

    /**
     * @notice Initializes the contract with the provided authorized signer address.
     *         Sets up the Ownable, Pausable, UUPS, and ReentrancyGuard functionalities.
     * @param _authorizedSigner_ The address authorized to sign reward claims.
     */
    function initialize(
      address _authorizedSigner_,
      address gnosisSafe_
    ) public initializer {
        require(_authorizedSigner_ != address(0), "Invalid authorized signer address");
        
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        _authorizedSigner = _authorizedSigner_;
        _gnosisSafe = gnosisSafe_;

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

    function authorizeUpgrade(address newImplementation) public onlySafe {
      _upgradeAuthorized[newImplementation] = true;
      emit UpgradeAuthorized(newImplementation);

    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {
      require(_upgradeAuthorized[newImplementation], "TwoTierAccessControl: upgrade not authorized by safe");
      // Reset authorization after use to prevent re-use
      _upgradeAuthorized[newImplementation] = false;

    }

    // -------------------------------------------------------------
    // Owner Functions
    // -------------------------------------------------------------

    /**
     * @notice Allows the owner to pause all critical functions in case of emergency
     * @dev Only callable by the contract owner
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Allows the owner to unpause the contract and resume normal operations
     * @dev Only callable by the contract owner
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Sets the reward token address after deployment.
     * @param _rewardToken The address of the new reward token contract.
     */
    function setRewardToken(address _rewardToken) external onlySafe {
        require(_rewardToken != address(0), "Invalid reward token address");
        rewardToken = IRewardToken(_rewardToken);
        emit RewardTokenUpdated(_rewardToken);
    }

    /**
     * @notice Allows the contract owners to deposit tokens directly into this contract.
     * @param amount The amount of tokens to deposit.
     */
    function depositTokens(uint256 amount) external onlySafe {
        require(
            rewardToken.transferFrom(_gnosisSafe, address(this), amount),
            "Token deposit failed"
        );
    }

    /**
     * @notice Allows the contract owners to withdraw tokens from this contract.
     * @param amount The amount of tokens to withdraw.
     */
    function withdrawTokens(uint256 amount) external onlySafe {
        require(
            rewardToken.transfer(_gnosisSafe, amount),
            "Token withdrawal failed"
        );
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
    function claimReward(
        uint256 rewardAmount,
        bytes32 orderId,
        bytes memory signature
    )
        external
        nonReentrant
        whenNotPaused
        returns (bool success)
    {
        require(
            rewardToken.balanceOf(address(this)) >= rewardAmount,
            "Insufficient token balance"
        );

        require(
            verifyOrder(msg.sender, rewardAmount, orderId, signature),
            "Invalid signature or mismatched parameters"
        );

        require(
            !isOrderRedeemed(msg.sender, orderId),
            "Order ID already used"
        );

        markOrderAsRedeemed(msg.sender, orderId);

        success = rewardToken.transfer(msg.sender, rewardAmount);
        require(success, "Token transfer failed");
        
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
    // Internal Functions (Order Mapping)
    // -------------------------------------------------------------

    /**
     * @dev Checks if a given `orderId` has been redeemed by the user.
     * @param user The user's wallet address.
     * @param orderId The ID of the order to check.
     * @return True if the `orderId` is already redeemed; otherwise, false.
     */
    function isOrderRedeemed(address user, bytes32 orderId) 
        internal 
        view 
        returns (bool) 
    {
        return redeemedOrders[user][orderId];
    }

    /**
     * @dev Marks an `orderId` as redeemed for the user.
     * @param user The user's wallet address.
     * @param orderId The ID of the order to mark as redeemed.
     */
    function markOrderAsRedeemed(address user, bytes32 orderId) internal {
        redeemedOrders[user][orderId] = true;
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
     * @return True if the recovered signer matches the `_authorizedSigner`.
     */
    function verifyOrder(
        address userWallet,
        uint256 rewardAmount,
        bytes32 orderId,
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
                orderId
            )
        );

        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        address signer = hash.recover(signature);
        return (signer == _authorizedSigner);
    }

    // -------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------

    /**
     * @dev Ensures the caller is the Gnosis Safe
     */
    modifier onlySafe() {
        require(msg.sender == _gnosisSafe, "Only the Safe can perform this");
        _;
    }
    /**
     * @dev overrides ownership Transfer so onlySafe can only change onlyOwner
     */
    function getOwnable2StepStorage() private pure returns (Ownable2StepUpgradeable.Ownable2StepStorage storage $) {
      bytes32 position = 0x237e158222e3e6968b72b9db0d8043aacf074ad9f650f0d1606b4d82ee432c00;
      assembly {
        $.slot := position
      }
    }

    function transferOwnership(
        address newOwner
    ) public override onlySafe {
      Ownable2StepStorage storage $ = getOwnable2StepStorage();
      $._pendingOwner = newOwner;
      emit OwnershipTransferred(_gnosisSafe, newOwner);
    }
}

