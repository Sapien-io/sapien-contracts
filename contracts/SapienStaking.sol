// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract SapienStaking is Initializable, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using ECDSA for bytes32;

    IERC20 public sapienToken;
    address private sapienAddress;

    uint256 private constant TOKEN_DECIMALS = 10 ** 18; // 18 decimals (standard for ERC-20 tokens)

    struct StakingInfo {
        uint256 amount; // Stored in wei
        uint256 lockUpPeriod;
        uint256 startTime;
        uint256 multiplier; // Stored in percentage (e.g., 105 for 1.05x)
        uint256 cooldownStart;
    }

    mapping(address => StakingInfo) public stakers;
    uint256 public totalStaked; // Stored in wei

    uint256 public constant BASE_STAKE = 1000; // Minimum tokens for base multiplier
    uint256 public constant ONE_MONTH_MAX_MULTIPLIER = 105; // 1.05x
    uint256 public constant THREE_MONTHS_MAX_MULTIPLIER = 110; // 1.1x
    uint256 public constant SIX_MONTHS_MAX_MULTIPLIER = 125; // 1.25x
    uint256 public constant TWELVE_MONTHS_MAX_MULTIPLIER = 150; // 1.5x

    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 private constant EARLY_WITHDRAWAL_PENALTY = 20; // 20% penalty for instant unstake

    event Staked(address indexed user, uint256 amount, uint256 multiplier, uint256 lockUpPeriod, string orderId);
    event UnstakingInitiated(address indexed user, uint256 amount, string orderId);
    event Unstaked(address indexed user, uint256 totalPayout, string orderId);
    event InstantUnstake(address indexed user, uint256 totalPayout, string orderId);
    event Slashed(address indexed user, uint256 penalty);
    event DebugMessageHash(bytes32 rawHash, bytes32 prefixedHash);

    function initialize(IERC20 _sapienToken, address _sapienAddress) public initializer {
        sapienToken = _sapienToken;
        sapienAddress = _sapienAddress;
        __Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
    }

    modifier onlySapien() {
        require(msg.sender == sapienAddress, "Caller is not Sapien");
        _;
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    function stake(uint256 amount, uint256 lockUpPeriod, string calldata orderId, bytes memory signature) public whenNotPaused nonReentrant {
        require(amount >= BASE_STAKE, "Amount must be greater than base stake");
        require(lockUpPeriod == 30 days || lockUpPeriod == 90 days || lockUpPeriod == 180 days || lockUpPeriod == 365 days, "Invalid lock-up period");

        require(verifyOrder(msg.sender, amount, orderId, signature), "Invalid signature or mismatched parameters");

        uint256 maxMultiplier = getMaxMultiplier(lockUpPeriod);
        uint256 multiplier = calculateMultiplier(amount, maxMultiplier);


        // Transfer tokens
        sapienToken.transferFrom(msg.sender, address(this), amount);

        StakingInfo storage info = stakers[msg.sender];
        info.amount += amount;
        info.lockUpPeriod = lockUpPeriod;
        info.startTime = block.timestamp;
        info.multiplier = multiplier;

        totalStaked += amount;

        emit Staked(msg.sender, amount, multiplier, lockUpPeriod, orderId);
    }

    function calculateMultiplier(uint256 amount, uint256 maxMultiplier) public pure returns (uint256) {
        if (amount >= BASE_STAKE) {
            return maxMultiplier; // Full multiplier if staked amount >= BASE_STAKE
        }
        uint256 baseMultiplier = 100; // 1.0x in percentage
        uint256 calculatedMultiplier = baseMultiplier + ((amount * (maxMultiplier - baseMultiplier)) / BASE_STAKE);

        return calculatedMultiplier > maxMultiplier ? maxMultiplier : calculatedMultiplier;
    }

    function getMaxMultiplier(uint256 lockUpPeriod) private pure returns (uint256) {
        if (lockUpPeriod == 30 days) return ONE_MONTH_MAX_MULTIPLIER;
        if (lockUpPeriod == 90 days) return THREE_MONTHS_MAX_MULTIPLIER;
        if (lockUpPeriod == 180 days) return SIX_MONTHS_MAX_MULTIPLIER;
        if (lockUpPeriod == 365 days) return TWELVE_MONTHS_MAX_MULTIPLIER;
        revert("Invalid lock-up period");
    }


    function initiateUnstake(uint256 amount, string calldata orderId, bytes memory signature) public whenNotPaused nonReentrant {
        StakingInfo storage info = stakers[msg.sender];
        require(info.amount >= amount, "Insufficient staked amount");
        require(verifyOrder(msg.sender, amount, orderId, signature), "Invalid signature or mismatched parameters");
        require(info.cooldownStart == 0, "Cooldown already initiated");

        info.cooldownStart = block.timestamp;

        emit UnstakingInitiated(msg.sender, amount, orderId);
    }

    function unstake(uint256 amount, string calldata orderId, bytes memory signature) public whenNotPaused nonReentrant {
        StakingInfo storage info = stakers[msg.sender];
        require(info.amount >= amount, "Insufficient staked amount");
        require(verifyOrder(msg.sender, amount, orderId, signature), "Invalid signature or mismatched parameters");
        require(info.cooldownStart > 0, "Cooldown not initiated");
        require(block.timestamp >= info.cooldownStart + COOLDOWN_PERIOD, "Cooldown period not completed");

        uint256 baseAmount = amount;
        uint256 reward = (baseAmount * info.multiplier) / 100;
        uint256 totalPayout = baseAmount + reward;

        info.amount -= baseAmount;
        totalStaked -= baseAmount;
        info.cooldownStart = 0; // Reset cooldown

        sapienToken.transfer(msg.sender, totalPayout);

        emit Unstaked(msg.sender, totalPayout, orderId);
    }

    function instantUnstake(uint256 amount, string calldata orderId, bytes memory signature) public whenNotPaused nonReentrant {
        StakingInfo storage info = stakers[msg.sender];
        require(info.amount >= amount, "Insufficient staked amount");
        require(verifyOrder(msg.sender, amount, orderId, signature), "Invalid signature or mismatched parameters");

        uint256 penalty = (amount * 20) / 100; // 20% penalty
        uint256 payout = amount - penalty; 

        info.amount -= amount; 
        totalStaked -= amount;

        sapienToken.transfer(msg.sender, payout); 
        sapienToken.transfer(owner(), penalty); 
        emit InstantUnstake(msg.sender, payout, orderId);

    }


    function verifyOrder(
        address userWallet,
        uint256 rewardAmount,
        string calldata orderId,
        bytes memory signature
    )  private view returns (bool) {
        bytes32 messageHash = keccak256(abi.encodePacked(userWallet, rewardAmount, orderId));
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );


        address signer = ethSignedMessageHash.recover(signature);
        return signer == sapienAddress;
    }
}
