// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract SapienStaking is Initializable, PausableUpgradeable, OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {
    IERC20 public sapienToken;
    address private sapienAddress;

    struct StakingInfo {
        uint256 amount;
        uint256 lockUpPeriod;
        uint256 startTime;
        uint256 multiplier;
        uint256 cooldownStart;
    }

    mapping(address => StakingInfo) public stakers;
    uint256 public totalStaked;

    uint256 public constant BASE_STAKE = 1000 ether; // Minimum tokens for base multiplier
    uint256 public constant ONE_MONTH_MAX_MULTIPLIER = 105; // 1.05x
    uint256 public constant THREE_MONTHS_MAX_MULTIPLIER = 110; // 1.1x
    uint256 public constant SIX_MONTHS_MAX_MULTIPLIER = 125; // 1.25x
    uint256 public constant TWELVE_MONTHS_MAX_MULTIPLIER = 150; // 1.5x

    uint256 public constant COOLDOWN_PERIOD = 2 days;
    uint256 public earlyWithdrawalPenalty = 20;

    event Staked(address indexed user, uint256 amount, uint256 multiplier, uint256 lockUpPeriod);
    event UnstakingInitiated(address indexed user, uint256 amount);
    event Unstaked(address indexed user, uint256 totalPayout);
    event InstantUnstake(address indexed user, uint256 remaining, uint256 penalty);
    event Slashed(address indexed user, uint256 penalty);

    function initialize(IERC20 _sapienToken, address _sapienAddress ) public initializer {
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

    function stake(uint256 amount, uint256 lockUpPeriod) external whenNotPaused nonReentrant {
        require(amount > 0, "Amount must be greater than zero");
        require(lockUpPeriod == 30 days || lockUpPeriod == 90 days || lockUpPeriod == 180 days || lockUpPeriod == 365 days, "Invalid lock-up period");

        uint256 maxMultiplier;
        if (lockUpPeriod == 30 days) maxMultiplier = ONE_MONTH_MAX_MULTIPLIER;
        if (lockUpPeriod == 90 days) maxMultiplier = THREE_MONTHS_MAX_MULTIPLIER;
        if (lockUpPeriod == 180 days) maxMultiplier = SIX_MONTHS_MAX_MULTIPLIER;
        if (lockUpPeriod == 365 days) maxMultiplier = TWELVE_MONTHS_MAX_MULTIPLIER;

        uint256 multiplier = calculateMultiplier(amount, maxMultiplier);

        sapienToken.transferFrom(msg.sender, address(this), amount);

        StakingInfo storage info = stakers[msg.sender];
        info.amount += amount;
        info.lockUpPeriod = lockUpPeriod;
        info.startTime = block.timestamp;
        info.multiplier = multiplier;

        totalStaked += amount;

        emit Staked(msg.sender, amount, multiplier, lockUpPeriod);
    }

    function calculateMultiplier(uint256 amount, uint256 maxMultiplier) public pure returns (uint256) {
        if (amount >= BASE_STAKE) {
            return maxMultiplier; // Full multiplier if staked amount >= BASE_STAKE
        }
        uint256 baseMultiplier = 100; // 1.0x in percentage
        uint256 calculatedMultiplier = baseMultiplier + ((amount * (maxMultiplier - baseMultiplier)) / BASE_STAKE);

        return calculatedMultiplier > maxMultiplier ? maxMultiplier : calculatedMultiplier;
    }

    function initiateUnstake() external whenNotPaused nonReentrant {
        StakingInfo storage info = stakers[msg.sender];
        require(info.amount > 0, "No staked tokens");
        require(block.timestamp >= info.startTime + info.lockUpPeriod, "Lock-up period not complete");

        info.cooldownStart = block.timestamp;

        emit UnstakingInitiated(msg.sender, info.amount);
    }

    function completeUnstake() external whenNotPaused nonReentrant {
        StakingInfo storage info = stakers[msg.sender];
        require(info.amount > 0, "No staked tokens");
        require(info.cooldownStart > 0, "Unstaking not initiated");
        require(block.timestamp >= info.cooldownStart + COOLDOWN_PERIOD, "Cooldown period not complete");

        uint256 baseAmount = info.amount;
        uint256 reward = (baseAmount * info.multiplier) / 100;
        uint256 totalPayout = baseAmount + reward;

        info.amount = 0;
        info.cooldownStart = 0;
        totalStaked -= baseAmount;

        sapienToken.transfer(msg.sender, totalPayout);

        emit Unstaked(msg.sender, totalPayout);
    }

    function instantUnstake() external whenNotPaused nonReentrant {
        StakingInfo storage info = stakers[msg.sender];
        require(info.amount > 0, "No staked tokens");

        uint256 penalty = (info.amount * earlyWithdrawalPenalty) / 100;
        uint256 remaining = info.amount - penalty;

        info.amount = 0;
        totalStaked -= info.amount;

        sapienToken.transfer(msg.sender, remaining);

        emit InstantUnstake(msg.sender, remaining, penalty);
    }

function slash(address[] calldata users, uint256 penalty) external onlySapien nonReentrant {
    for (uint256 i = 0; i < users.length; i++) {
        address user = users[i];
        StakingInfo storage info = stakers[user];
        
        // Check if the user has enough staked amount
        if (info.amount >= penalty && info.amount > 0) {
            info.amount -= penalty; // Deduct the penalty from staked amount
            totalStaked -= penalty; // Update total staked amount
            
            // Transfer penalty tokens to the owner
            sapienToken.transfer(owner(), penalty);

            emit Slashed(user, penalty); // Emit event for the slashed user
        } else {
            // Skip the user if conditions are not met (e.g., insufficient balance or not staking)
            continue;
        }
    }
}


    function stakedBalance(address user) external view returns (uint256) {
        return stakers[user].amount;
    }

    function rewardsMultiplier(address user) external view returns (uint256) {
        return stakers[user].multiplier;
    }

    function calculateReward(address user) public view returns (uint256) {
        StakingInfo storage info = stakers[user];
        if (info.amount == 0) return 0;

        return (info.amount * info.multiplier) / 100;
    }

    function totalStakedTokens() external view returns (uint256) {
        return totalStaked;
    }
}
