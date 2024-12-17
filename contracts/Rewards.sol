// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";


// Define an interface for the rewardToken contract to interact with the releaseTokens function
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

    // Mapping of wallet addresses to their Bloom filter for order IDs
    mapping(address => uint256) private userBloomFilters;

    // Events
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

    // Initialize function for the UUPS upgradeable pattern
    function initialize(address _authorizedSigner) public initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        authorizedSigner = _authorizedSigner;
    }

    // Set the reward token after deployment
    function setRewardToken(address _rewardToken) external onlyOwner {
        require(_rewardToken != address(0), "Invalid reward token address");
        rewardToken = IRewardToken(_rewardToken);
        emit RewardTokenUpdated(_rewardToken);
    }

    // Function to call releaseTokens on the rewardToken contract
    function releaseRewardTokens(string calldata allocationType) external onlyOwner whenNotPaused {
        rewardToken.releaseTokens(allocationType);
        emit TokensReleasedToContract(allocationType);
    }

    // Claim reward function using the preset reward token address
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
        // Check that the signature values match msg.sender, rewardAmount, orderId, and the authorized signer
        require(verifyOrder(msg.sender, rewardAmount, orderId, signature), "Invalid signature or mismatched parameters");

        require(!isOrderRedeemed(msg.sender, orderId), "Order ID already used");

        addOrderToBloomFilter(msg.sender, orderId);

        bool success = rewardToken.transfer(msg.sender, rewardAmount * 10**18);
        string memory reason = success ? "" : "Token transfer failed";

        emit WithdrawalProcessed(msg.sender, orderId, success, reason); // Log withdrawal processing result

        if (!success) revert("Token transfer failed");
        emit RewardClaimed(msg.sender, rewardAmount, orderId); // Log successful reward claim
        return true;
    }

    // Bloom filter implementation to track order IDs (used for duplicate checks)
    uint8 private constant NUM_HASHES = 3;

    function isOrderRedeemed(address user, string calldata orderId) internal view returns (bool) {
        uint256 bloomFilter = userBloomFilters[user];
        for (uint8 i = 0; i < NUM_HASHES; i++) {
            uint8 bitPos = uint8(uint256(keccak256(abi.encodePacked(orderId, i))) % 256);
            if ((bloomFilter & (1 << bitPos)) == 0) {
                return false; // OrderId bit not set in Bloom filter, so it's not redeemed
            }
        }
        return true; // All bits are set, so the orderId is potentially redeemed
    }

    function addOrderToBloomFilter(address user, string calldata orderId) internal {
        uint256 bloomFilter = userBloomFilters[user];
        for (uint8 i = 0; i < NUM_HASHES; i++) {
            uint8 bitPos = uint8(uint256(keccak256(abi.encodePacked(orderId, i))) % 256);
            bloomFilter |= (1 << bitPos); // Set the bit in the Bloom filter
        }
        userBloomFilters[user] = bloomFilter; // Update the user's Bloom filter
    }

    function verifyOrder(
        address userWallet,
        uint256 rewardAmount,
        string calldata orderId,
        bytes memory signature
    ) private view returns (bool) {
        // Step 1: Recompute the hash using the inputs
        bytes32 messageHash = keccak256(abi.encodePacked(userWallet, rewardAmount, orderId));
        
        // Step 2: Apply the Ethereum Signed Message prefix
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            messageHash
        ));

        // Step 3: Recover the signer’s address from the signature
        address signer = ethSignedMessageHash.recover(signature);

        // Step 4: Check if the recovered signer is the authorized signer
        return signer == authorizedSigner;
    }


    function getContractTokenBalance() external view returns (uint256) {
        return rewardToken.balanceOf(address(this));
    }

    // Helper function to get message hash
    function getMessageHash(address userWallet, uint256 rewardAmount, string calldata orderId) 
        private 
        pure 
        returns (bytes32) 
    {
        return keccak256(abi.encodePacked(userWallet, rewardAmount, orderId));
    }

    // Recover the signer from the signature
    function recoverSigner(bytes32 messageHash, bytes memory signature) 
        private 
        pure 
        returns (address) 
    {
        bytes32 ethSignedMessageHash = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash));
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }

    // Split the signature into r, s, v components
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

    // Owner-only function to deposit tokens into the contract
    function depositTokens(uint256 amount) external onlyOwner {
        require(rewardToken.transferFrom(msg.sender, address(this), amount), "Token deposit failed");
    }

    // Owner-only function to withdraw tokens from the contract
    function withdrawTokens(uint256 amount) external onlyOwner {
        require(rewardToken.transfer(owner(), amount), "Token withdrawal failed");
    }

    // Function to authorize contract upgrades
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
