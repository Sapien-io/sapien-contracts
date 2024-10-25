// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract SapienRewards is 
    Initializable, 
    OwnableUpgradeable, 
    PausableUpgradeable, 
    UUPSUpgradeable, 
    ReentrancyGuardUpgradeable 
{
    IERC20 public rewardToken;
    address public authorizedSigner;

    // Mapping of wallet addresses to their Bloom filter for order IDs
    mapping(address => uint256) private userBloomFilters;

    // Event for claiming rewards
    event RewardClaimed(address indexed user, uint256 amount, bytes32 orderId);
    // Event for withdrawal processing
    event WithdrawalProcessed(address indexed user, bytes32 indexed eventOrderId, bool success, string reason);

    modifier hasTokenBalance(uint256 amount) {
        require(rewardToken.balanceOf(address(this)) >= amount, "Insufficient token balance");
        _;
    }

    function initialize(address _rewardToken, address _authorizedSigner) public initializer {
        __Ownable_init(_rewardToken);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        rewardToken = IERC20(_rewardToken);
        authorizedSigner = _authorizedSigner;
    }

    // Bloom filter parameters
    uint8 private constant NUM_HASHES = 3; // Number of hash functions

    function claimReward(uint256 rewardAmount, bytes32 orderId, bytes memory signature)
        external 
        hasTokenBalance(rewardAmount) 
        nonReentrant 
    {
        require(verifyOrder(msg.sender, rewardAmount, orderId, signature), "Invalid order or signature");

        // Check if the orderId is possibly already redeemed using the user’s Bloom filter
        require(!isOrderRedeemed(msg.sender, orderId), "Order ID already used");

        // Mark the orderId in the user’s Bloom filter
        addOrderToBloomFilter(msg.sender, orderId);

        bool success = rewardToken.transfer(msg.sender, rewardAmount);
        string memory reason = success ? "" : "Token transfer failed";

        emit WithdrawalProcessed(msg.sender, orderId, success, reason);

        if (!success) revert("Token transfer failed");

        emit RewardClaimed(msg.sender, rewardAmount, orderId);
    }

    function isOrderRedeemed(address user, bytes32 orderId) internal view returns (bool) {
        uint256 bloomFilter = userBloomFilters[user];
        for (uint8 i = 0; i < NUM_HASHES; i++) {
            uint8 bitPos = uint8(uint256(keccak256(abi.encodePacked(orderId, i))) % 256);
            if ((bloomFilter & (1 << bitPos)) == 0) {
                return false; // OrderId bit not set in Bloom filter, so it's not redeemed
            }
        }
        return true; // All bits are set, so the orderId is potentially redeemed
    }

    function addOrderToBloomFilter(address user, bytes32 orderId) internal {
        uint256 bloomFilter = userBloomFilters[user];
        for (uint8 i = 0; i < NUM_HASHES; i++) {
            uint8 bitPos = uint8(uint256(keccak256(abi.encodePacked(orderId, i))) % 256);
            bloomFilter |= (1 << bitPos); // Set the bit in the Bloom filter
        }
        userBloomFilters[user] = bloomFilter; // Update the user's Bloom filter
    }

    function verifyOrder(address user, uint256 rewardAmount, bytes32 orderId, bytes memory signature) 
        internal 
        view 
        returns (bool) 
    {
        bytes32 messageHash = getMessageHash(user, rewardAmount, orderId, user);
        return recoverSigner(messageHash, signature) == authorizedSigner;
    }

    function getMessageHash(address user, uint256 rewardAmount, bytes32 orderId, address userWallet) 
        public 
        pure 
        returns (bytes32) 
    {
        bytes32 userHash = keccak256(abi.encodePacked(user));
        bytes32 rewardAmountHex = bytes32(rewardAmount);
        bytes32 orderIdHash = keccak256(abi.encodePacked(orderId));
        bytes32 walletHash = keccak256(abi.encodePacked(userWallet));
        
        return keccak256(abi.encodePacked(userHash, rewardAmountHex, orderIdHash, walletHash));
    }

    function recoverSigner(bytes32 messageHash, bytes memory signature) 
        public 
        pure 
        returns (address) 
    {
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }

    function splitSignature(bytes memory sig) 
        public 
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

    // Owner-only function to deposit tokens into the contract
    function depositTokens(uint256 amount) external onlyOwner {
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Token deposit failed");
    }

    // Owner-only function to withdraw tokens from the contract
    function withdrawTokens(uint256 amount) external onlyOwner {
        require(rewardToken.transfer(owner(), amount), "Token withdrawal failed");
    }

    // Function to pause the contract (only owner)
    function pause() external onlyOwner {
        _pause();
    }

    // Function to unpause the contract (only owner)
    function unpause() external onlyOwner {
        _unpause();
    }

    // Function to authorize contract upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
