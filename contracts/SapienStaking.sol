// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

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

    uint256 private constant TOKEN_DECIMALS = 10 ** 18;

    struct StakingInfo {
        uint256 amount;
        uint256 lockUpPeriod;
        uint256 startTime;
        uint256 multiplier;
        uint256 cooldownStart;
        bool isActive;
    }

    mapping(address => mapping(string => StakingInfo)) public stakers; // Mapping from user to orderId to StakingInfo
    uint256 public totalStaked;

    // BASE_STAKE is used to calculate the multiplier for the staking amount and is not
    // supposed to be blocking if the user wants to stake less than the base amount
    // however, for test-net, the minimum staking amount is set to BASE_STAKE
    uint256 public constant BASE_STAKE = 1000 * TOKEN_DECIMALS;
    uint256 public constant ONE_MONTH_MAX_MULTIPLIER = 105;
    uint256 public constant THREE_MONTHS_MAX_MULTIPLIER = 110;
    uint256 public constant SIX_MONTHS_MAX_MULTIPLIER = 125;
    uint256 public constant TWELVE_MONTHS_MAX_MULTIPLIER = 150;

    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 private constant EARLY_WITHDRAWAL_PENALTY = 20; // 20%

    bytes32 public DOMAIN_SEPARATOR;
    bytes32 public constant STAKING_TYPEHASH = keccak256(
        "Staking(address walletAddress,uint256 rewardAmount,string orderId)"
    );

    mapping(bytes32 => bool) private usedSignatures;

    event Staked(address indexed user, uint256 amount, uint256 multiplier, uint256 lockUpPeriod, string orderId);
    event UnstakingInitiated(address indexed user, uint256 amount, string orderId);
    event Unstaked(address indexed user, uint256 amount, string orderId);
    event InstantUnstake(address indexed user, uint256 amount, string orderId);

    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 _sapienToken, address _sapienAddress) public initializer {
        require(address(_sapienToken) != address(0), "SapienToken address cannot be zero");
        require(_sapienAddress != address(0), "Sapien address cannot be zero");
        sapienToken = _sapienToken;
        sapienAddress = _sapienAddress;
        __Pausable_init();
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("SapienStaking")),      
                keccak256(bytes("1")),                
                block.chainid,                           
                address(this)                            
            )
        );
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
        // this check will be removed in mainnet 
        require(amount >= BASE_STAKE, "Amount must be greater than base stake");
        require(
            lockUpPeriod == 30 days || lockUpPeriod == 90 days || lockUpPeriod == 180 days || lockUpPeriod == 365 days,
            "Invalid lock-up period"
        );
        require(verifyOrder(msg.sender, amount, orderId, signature), "Invalid signature or mismatched parameters");

        uint256 maxMultiplier = getMaxMultiplier(lockUpPeriod);
        uint256 multiplier = calculateMultiplier(amount, maxMultiplier);

        sapienToken.transferFrom(msg.sender, address(this), amount);

        stakers[msg.sender][orderId] = StakingInfo({
            amount: amount,
            lockUpPeriod: lockUpPeriod,
            startTime: block.timestamp,
            multiplier: multiplier,
            cooldownStart: 0,
            isActive: true
        });

        totalStaked += amount;

        emit Staked(msg.sender, amount, multiplier, lockUpPeriod, orderId);
    }

    function calculateMultiplier(uint256 amount, uint256 maxMultiplier) public pure returns (uint256) {
        if (amount >= BASE_STAKE) {
            return maxMultiplier;
        }
        uint256 baseMultiplier = 100;
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
        require(amount > 0, "Unstake amount must be greater than zero");
        StakingInfo storage info = stakers[msg.sender][orderId];
        require(info.isActive, "Staking position not active");
        require(block.timestamp >= info.startTime + info.lockUpPeriod, "Lock-up period not completed");
        require(info.cooldownStart == 0, "Cooldown already initiated");
        require(verifyOrder(msg.sender, amount, orderId, signature), "Invalid signature or mismatched parameters");

        info.cooldownStart = block.timestamp;

        emit UnstakingInitiated(msg.sender, info.amount, orderId);
    }

    function unstake(uint256 amount, string calldata orderId, bytes memory signature) public whenNotPaused nonReentrant {
        require(amount > 0, "Unstake amount must be greater than zero");
        StakingInfo storage info = stakers[msg.sender][orderId];
        require(info.isActive, "Staking position not active");
        require(info.cooldownStart > 0, "Cooldown not initiated");
        require(verifyOrder(msg.sender, amount, orderId, signature), "Invalid signature or mismatched parameters");
        require(block.timestamp >= info.cooldownStart + COOLDOWN_PERIOD, "Cooldown period not completed");
        require(info.amount >= amount, "Insufficient staked amount");

        info.amount -= amount;
        if (info.amount == 0) {
            info.isActive = false;
        }
        totalStaked -= amount;

        sapienToken.transfer(msg.sender, amount);

        emit Unstaked(msg.sender, amount, orderId);
    }

    function instantUnstake(uint256 amount, string calldata orderId, bytes memory signature) public whenNotPaused nonReentrant {
        require(amount > 0, "Unstake amount must be greater than zero");
        StakingInfo storage info = stakers[msg.sender][orderId];
        require(info.isActive, "Staking position not active");
        require(verifyOrder(msg.sender, amount, orderId, signature), "Invalid signature or mismatched parameters");
        require(block.timestamp < info.startTime + info.lockUpPeriod, "Lock-up ended; use regular unstake");

        uint256 penalty = (amount * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 payout = amount - penalty;

        info.amount -= amount;
        if (info.amount == 0) {
            info.isActive = false;
        }
        totalStaked -= amount;

        sapienToken.transfer(msg.sender, payout);
        sapienToken.transfer(owner(), penalty);

        emit InstantUnstake(msg.sender, payout, orderId);
    }

    function verifyOrder(
        address walletAddress,
        uint256 rewardAmount,
        string calldata orderId,
        bytes memory signature
    ) private returns (bool) {
        // Create the struct hash for EIP-712 typed data
        bytes32 structHash = keccak256(
            abi.encode(
                STAKING_TYPEHASH,
                walletAddress,
                rewardAmount,
                keccak256(bytes(orderId)) 
            )
        );

        // EIP-712 domain separation
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                structHash
            )
        );
        require(!usedSignatures[digest], "Signature already used");
        // Recover the signer
        address signer = digest.recover(signature);
        if (signer == sapienAddress) {
            usedSignatures[digest] = true;
            return true;
        }
        return false;
    }
}
