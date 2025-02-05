// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract SapTestToken is
    Initializable,
    ERC20Upgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    struct VestingSchedule {
        uint256 cliff;
        uint256 start;
        uint256 duration;
        uint256 amount;
        uint256 released;
        address safe;
    }

    enum AllocationType { INVESTORS, TEAM_ADVISORS, LABELING_REWARDS, AIRDROPS, COMMUNITY_TREASURY, STAKING_INCENTIVES, LIQUIDITY_INCENTIVES }

    uint8 public constant DECIMALS = 18;

    event TokensReleased(AllocationType allocationType, uint256 amount);
    event InitializedEvent(address safe, uint256 amount, address sapienRewardsContract);
    event VestingScheduleUpdated(AllocationType allocationType, uint256 amount);
    event SafeTransferInitiated(address indexed newSafe);
    event SafeTransferCompleted(address indexed newSafe);

    uint256 public constant INVESTORS_ALLOCATION = 300000000 * 10 ** DECIMALS;
    uint256 public constant TEAM_ADVISORS_ALLOCATION = 200000000 * 10 ** DECIMALS;
    uint256 public constant LABELING_REWARDS_ALLOCATION = 150000000 * 10 ** DECIMALS;
    uint256 public constant AIRDROPS_ALLOCATION = 150000000 * 10 ** DECIMALS;
    uint256 public constant COMMUNITY_TREASURY_ALLOCATION = 100000000 * 10 ** DECIMALS;
    uint256 public constant STAKING_INCENTIVES_ALLOCATION = 50000000 * 10 ** DECIMALS;
    uint256 public constant LIQUIDITY_INCENTIVES_ALLOCATION = 50000000 * 10 ** DECIMALS;

    uint256 public vestingStartTimestamp;
    address public sapienRewardsContract;
    address public gnosisSafe;
    address private pendingSafe;

    mapping(AllocationType => VestingSchedule) public vestingSchedules;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _gnosisSafe, uint256 _totalSupply, address _sapienRewardsContract) public initializer {
        require(_gnosisSafe != address(0), "Invalid Gnosis Safe address");
        require(_sapienRewardsContract != address(0), "Invalid SapienRewards address");
        require(_gnosisSafe != address(0), "Invalid Gnosis Safe address");
        require(_totalSupply > 0, "Total supply must be greater than zero");

        uint256 totalAllocations = INVESTORS_ALLOCATION +
                                   TEAM_ADVISORS_ALLOCATION +
                                   LABELING_REWARDS_ALLOCATION +
                                   AIRDROPS_ALLOCATION +
                                   COMMUNITY_TREASURY_ALLOCATION +
                                   STAKING_INCENTIVES_ALLOCATION +
                                   LIQUIDITY_INCENTIVES_ALLOCATION;

        require(_totalSupply == totalAllocations, "Total supply must match allocations");


        gnosisSafe = _gnosisSafe;
        sapienRewardsContract = _sapienRewardsContract;

        __ERC20_init("SapTestToken", "PTSPN");
        __Pausable_init();
        __UUPSUpgradeable_init();
        vestingStartTimestamp = block.timestamp;

        _mint(_gnosisSafe, _totalSupply);
        _createHardcodedVestingSchedules();
        emit InitializedEvent(_gnosisSafe, _totalSupply, _sapienRewardsContract);
    }


    modifier onlySafe() {
        require(msg.sender == gnosisSafe, "Only the Safe can perform this");
        _;
    }

    modifier onlyPendingSafe() {
        require(msg.sender == pendingSafe, "Only the pending Safe can accept ownership");
        _;
    }

    function transferSafe(address newSafe) external onlySafe {
        require(newSafe != address(0), "Invalid address");
        pendingSafe = newSafe;
        emit SafeTransferInitiated(newSafe);
    }

    function acceptSafe() external {
        require(msg.sender == pendingSafe, "Only the pending Safe can accept ownership");
        gnosisSafe = pendingSafe;
        pendingSafe = address(0);
        emit SafeTransferCompleted(gnosisSafe);
    }

    function _createHardcodedVestingSchedules() internal {
        uint256 cliff = 365 days;
        vestingSchedules[AllocationType.INVESTORS] = VestingSchedule(cliff, vestingStartTimestamp, 48 * 30 days, INVESTORS_ALLOCATION, 0, gnosisSafe);
        vestingSchedules[AllocationType.TEAM_ADVISORS] = VestingSchedule(cliff, vestingStartTimestamp, 48 * 30 days, TEAM_ADVISORS_ALLOCATION, 0, gnosisSafe);
        vestingSchedules[AllocationType.LABELING_REWARDS] = VestingSchedule(0, vestingStartTimestamp, 48 * 30 days, LABELING_REWARDS_ALLOCATION, 0, sapienRewardsContract);
        vestingSchedules[AllocationType.AIRDROPS] = VestingSchedule(0, vestingStartTimestamp, 48 * 30 days, AIRDROPS_ALLOCATION, 0, gnosisSafe);
        vestingSchedules[AllocationType.COMMUNITY_TREASURY] = VestingSchedule(0, vestingStartTimestamp, 48 * 30 days, COMMUNITY_TREASURY_ALLOCATION, 0, gnosisSafe);
        vestingSchedules[AllocationType.STAKING_INCENTIVES] = VestingSchedule(0, vestingStartTimestamp, 48 * 30 days, STAKING_INCENTIVES_ALLOCATION, 0, gnosisSafe);
        vestingSchedules[AllocationType.LIQUIDITY_INCENTIVES] = VestingSchedule(0, vestingStartTimestamp, 48 * 30 days, LIQUIDITY_INCENTIVES_ALLOCATION, 0, gnosisSafe);
    }

    function releaseTokens(AllocationType allocationType) external nonReentrant whenNotPaused onlySafe {
        VestingSchedule storage schedule = vestingSchedules[allocationType];
        require(schedule.amount > 0, "No tokens to release");

        uint256 currentTime = block.timestamp;
        uint256 elapsedTime = currentTime - schedule.start;
        require(elapsedTime >= schedule.cliff, "Cliff not reached");

        uint256 releasableAmount;
        if (schedule.duration == 0) {
            releasableAmount = schedule.amount - schedule.released;
        } else {
            uint256 vestingPeriod = elapsedTime > schedule.duration ? schedule.duration : elapsedTime;
            uint256 vestedAmount = (schedule.amount * vestingPeriod) / schedule.duration;
            releasableAmount = vestedAmount - schedule.released;
        }

        require(releasableAmount > 0, "No tokens releasable");

        schedule.released += releasableAmount;
        _transfer(gnosisSafe, schedule.safe, releasableAmount);
        emit TokensReleased(allocationType, releasableAmount);
    }

    function pause() external onlySafe {
        _pause();
    }

    function unpause() external onlySafe {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlySafe {}
}
