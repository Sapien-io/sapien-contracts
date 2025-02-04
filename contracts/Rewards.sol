// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

// Interface for the rewardToken
interface IRewardToken is IERC20 {
    function releaseTokens(string calldata allocationType) external;
}

contract SapienRewards is 
    Initializable, 
    OwnableUpgradeable, 
    PausableUpgradeable, 
    UUPSUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    using ECDSA for bytes32;

    IRewardToken public rewardToken;
    address private authorizedSigner;

    // ------------------ ADDED FOR EIP-712 ------------------
    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant REWARD_TYPEHASH = keccak256(
        "RewardClaim(address walletAddress,uint256 rewardAmount,string orderId)"
    );

    mapping(bytes32 => bool) private usedSignatures;
    mapping(address => uint256) private userBloomFilters;

    event RewardClaimed(address indexed user, uint256 amount, string orderId);
    event WithdrawalProcessed(address indexed user, string indexed eventOrderId, bool success, string reason);
    event RewardTokenUpdated(address indexed newRewardToken);
    event TokensReleasedToContract(string allocationType);
    event SignatureVerified(address user, uint256 amount, string orderId);
    event MsgHash(bytes32 msgHash);
    event RecoveredSigner(address signer);

    modifier hasTokenBalance(uint256 amount) {
        require(rewardToken.balanceOf(address(this)) >= amount, "Insufficient token balance");
        _;
    }

    function initialize(address _authorizedSigner) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        authorizedSigner = _authorizedSigner;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("SapienRewards")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setRewardToken(address _rewardToken) external onlyOwner {
        require(_rewardToken != address(0), "Invalid reward token address");
        rewardToken = IRewardToken(_rewardToken);
        emit RewardTokenUpdated(_rewardToken);
    }

    function releaseRewardTokens(string calldata allocationType) external onlyOwner whenNotPaused {
        rewardToken.releaseTokens(allocationType);
        emit TokensReleasedToContract(allocationType);
    }

    function claimReward(
        uint256 rewardAmount, 
        string calldata orderId, 
        bytes memory signature
    )
        external
        hasTokenBalance(rewardAmount)
        nonReentrant
        whenNotPaused
        returns (bool)
    {
        require(verifyOrder(msg.sender, rewardAmount, orderId, signature), "Invalid signature or mismatched parameters");
        require(!isOrderRedeemed(msg.sender, orderId), "Order ID already used");

        addOrderToBloomFilter(msg.sender, orderId);

        bool success = rewardToken.transfer(msg.sender, rewardAmount);
        string memory reason = success ? "" : "Token transfer failed";

        emit WithdrawalProcessed(msg.sender, orderId, success, reason);

        if (!success) revert("Token transfer failed");
        emit RewardClaimed(msg.sender, rewardAmount, orderId);
        return true;
    }

    uint8 private constant NUM_HASHES = 3;

    function isOrderRedeemed(address user, string calldata orderId) internal view returns (bool) {
        uint256 bloomFilter = userBloomFilters[user];
        for (uint8 i = 0; i < NUM_HASHES; i++) {
            uint8 bitPos = uint8(uint256(keccak256(abi.encodePacked(orderId, i))) % 256);
            if ((bloomFilter & (1 << bitPos)) == 0) {
                return false;
            }
        }
        return true;
    }

    function addOrderToBloomFilter(address user, string calldata orderId) internal {
        uint256 bloomFilter = userBloomFilters[user];
        for (uint8 i = 0; i < NUM_HASHES; i++) {
            uint8 bitPos = uint8(uint256(keccak256(abi.encodePacked(orderId, i))) % 256);
            bloomFilter |= (1 << bitPos);
        }
        userBloomFilters[user] = bloomFilter;
    }

    function verifyOrder(
        address walletAddress,
        uint256 rewardAmount,
        string calldata orderId,
        bytes memory signature
    ) private returns (bool) 
    {
        bytes32 structHash = keccak256(
            abi.encode(
                REWARD_TYPEHASH,
                walletAddress,
                rewardAmount,
                keccak256(bytes(orderId))
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                structHash
            )
        );

        require(!usedSignatures[digest], "Signature already used");

        address signer = ECDSA.recover(digest, signature);
        if (signer == authorizedSigner) {
            usedSignatures[digest] = true;
            return true;
        }
        return false;
    }


    function getContractTokenBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    function depositTokens(uint256 amount) external onlyOwner {
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Token deposit failed");
    }

    function withdrawTokens(uint256 amount) external onlyOwner {
        require(rewardToken.transfer(owner(), amount), "Token withdrawal failed");
    }

}
