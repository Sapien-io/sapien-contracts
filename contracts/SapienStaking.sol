// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./SapTestToken.sol";

contract SapienStaking is Initializable, PausableUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    using ECDSA for bytes32;

    SapTestToken public immutable sapienToken;
    address private immutable sapienAddress;
    bytes32 public immutable DOMAIN_SEPARATOR;

    uint8 public constant DECIMALS = 18;

    struct StakingInfo {
        uint256 amount;
        uint256 lockUpPeriod;
        uint256 startTime;
        uint256 multiplier;
        uint256 cooldownStart;
        bool isActive;
    }

    mapping(address => mapping(string => StakingInfo)) public stakers;
    uint256 public totalStaked;

    uint256 public constant BASE_STAKE = 1000 * (10 ** DECIMALS);
    uint256 public constant ONE_MONTH_MAX_MULTIPLIER = 105;
    uint256 public constant THREE_MONTHS_MAX_MULTIPLIER = 110;
    uint256 public constant SIX_MONTHS_MAX_MULTIPLIER = 125;
    uint256 public constant TWELVE_MONTHS_MAX_MULTIPLIER = 150;

    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 private constant EARLY_WITHDRAWAL_PENALTY = 20;

    bytes32 public constant STAKING_TYPEHASH = keccak256(
        "Staking(address walletAddress,uint256 rewardAmount,string orderId)"
    );

    mapping(bytes32 => bool) private usedSignatures;

    event Staked(address indexed user, uint256 amount, uint256 multiplier, uint256 lockUpPeriod, string orderId);
    event UnstakingInitiated(address indexed user, uint256 amount, string orderId);
    event Unstaked(address indexed user, uint256 amount, string orderId);
    event InstantUnstake(address indexed user, uint256 amount, string orderId);

    constructor(SapTestToken _sapienToken, address _sapienAddress) {
        require(address(_sapienToken) != address(0), "SapienToken address cannot be zero");
        require(_sapienAddress != address(0), "Sapien address cannot be zero");

        sapienToken = _sapienToken;
        sapienAddress = _sapienAddress;

        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("SapienStaking")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );

        _disableInitializers();
    }

    function initialize() public initializer {
        __Pausable_init();
        __Ownable2Step_init();
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

    function stake(
        uint256 amount, 
        uint256 lockUpPeriod, 
        string calldata orderId, 
        bytes memory signature
    ) 
        public 
        whenNotPaused 
        nonReentrant 
    {
        require(amount >= BASE_STAKE, "Amount must be greater than base stake");
        require(
            verifyOrder(msg.sender, amount, orderId, signature), 
            "Invalid signature or mismatched parameters"
        );

        uint256 maxMultiplier = getMaxMultiplier(lockUpPeriod);
        uint256 multiplier = calculateMultiplier(amount, maxMultiplier);

        stakers[msg.sender][orderId] = StakingInfo({
            amount: amount,
            lockUpPeriod: lockUpPeriod,
            startTime: block.timestamp,
            multiplier: multiplier,
            cooldownStart: 0,
            isActive: true
        });

        totalStaked += amount;

        require(
            sapienToken.transferFrom(msg.sender, address(this), amount), 
            "TransferFrom failed"
        );

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

    function verifyOrder(
        address walletAddress,
        uint256 rewardAmount,
        string calldata orderId,
        bytes memory signature
    ) private returns (bool) {
        bytes32 structHash = keccak256(
            abi.encode(
                STAKING_TYPEHASH,
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

        address signer = digest.recover(signature);
        if (signer == sapienAddress) {
            usedSignatures[digest] = true;
            return true;
        }
        return false;
    }
}
