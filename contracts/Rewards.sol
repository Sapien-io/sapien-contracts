// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

import "./SapTestToken.sol";

contract SapienRewards is 
    Initializable, 
    Ownable2StepUpgradeable, 
    PausableUpgradeable, 
    UUPSUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    using ECDSA for bytes32;

    bytes32 public constant REWARD_TYPEHASH = keccak256(
        "RewardClaim(address walletAddress,uint256 rewardAmount,string orderId)"
    );

    SapTestToken public rewardToken;
    address private immutable authorizedSigner;
    bytes32 public immutable DOMAIN_SEPARATOR;

    mapping(bytes32 => bool) private usedSignatures;
    mapping(address => mapping(bytes32 => bool)) private redeemedOrders;

    event RewardClaimed(address indexed user, uint256 amount, string orderId);
    event WithdrawalProcessed(address indexed user, string indexed eventOrderId);
    event RewardTokenUpdated(address indexed newRewardToken);
    event TokensReleasedToContract(string allocationType);
    event SignatureVerified(address user, uint256 amount, string orderId);
    event MsgHash(bytes32 msgHash);
    event RecoveredSigner(address signer);

    event TokensDeposited(address indexed from, uint256 amount);
    event TokensWithdrawn(address indexed to, uint256 amount);

    constructor(address _authorizedSigner) {
        require(_authorizedSigner != address(0), "Authorized signer address cannot be zero");

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

        _disableInitializers();
    }

    function initialize() public initializer {
        __Ownable2Step_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function setRewardToken(address _rewardToken) external onlyOwner {
        require(_rewardToken != address(0), "Invalid reward token address");
        rewardToken = SapTestToken(_rewardToken);
        emit RewardTokenUpdated(_rewardToken);
    }

    function depositTokens(uint256 amount) external onlyOwner {
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Token deposit failed");
        emit TokensDeposited(msg.sender, amount);
    }

    function withdrawTokens(uint256 amount) external onlyOwner {
        require(rewardToken.transfer(owner(), amount), "Token withdrawal failed");
        emit TokensWithdrawn(owner(), amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function claimReward(
        uint256 rewardAmount, 
        string calldata orderId, 
        bytes memory signature
    )
        external
        nonReentrant
        whenNotPaused
        returns (bool)
    {
        require(
            verifyOrder(msg.sender, rewardAmount, orderId, signature), 
            "Invalid signature or mismatched parameters"
        );
        require(
            !isOrderRedeemed(msg.sender, orderId), 
            "Order ID already used"
        );
        require(
            rewardToken.balanceOf(address(this)) >= rewardAmount, 
            "Insufficient token balance"
        );

        addOrderToRedeemed(msg.sender, orderId);

        require(
            rewardToken.transfer(msg.sender, rewardAmount), 
            "Token transfer failed"
        );

        emit WithdrawalProcessed(msg.sender, orderId);
        emit RewardClaimed(msg.sender, rewardAmount, orderId);

        return true;
    }

    function getContractTokenBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    function isOrderRedeemed(address user, string calldata orderId) internal view returns (bool) {
        return redeemedOrders[user][keccak256(abi.encodePacked(orderId))];
    }

    function addOrderToRedeemed(address user, string calldata orderId) internal {
        redeemedOrders[user][keccak256(abi.encodePacked(orderId))] = true;
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
}
