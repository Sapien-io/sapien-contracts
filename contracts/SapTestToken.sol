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

    uint8 public constant DECIMALS = 18;


    event TokensReleased(string destination, uint256 amount);
    event InitializedEvent(address safe, uint256 amount, address sapienRewardsContract);
    event VestingScheduleUpdated(string allocationType, uint256 amount);

    uint256 public constant INVESTORS_ALLOCATION = 300000000 * 10 * DECIMALS;
    uint256 public constant TEAM_ADVISORS_ALLOCATION = 200000000 * 10 ** DECIMALS;
    uint256 public constant LABELING_REWARDS_ALLOCATION = 150000000 * 10 ** DECIMALS;
    uint256 public constant AIRDROPS_ALLOCATION = 150000000 * 10 ** DECIMALS;
    uint256 public constant COMMUNITY_TREASURY_ALLOCATION = 100000000 * 10 ** DECIMALS;
    uint256 public constant STAKING_INCENTIVES_ALLOCATION = 50000000 * 10 ** DECIMALS;
    uint256 public constant LIQUIDITY_INCENTIVES_ALLOCATION = 50000000 * 10 ** DECIMALS;

    uint256 private vestingStartTimestamp;
    address public sapienRewardsContract;
    mapping(string => VestingSchedule) public vestingSchedules;
    address public gnosisSafe;

    constructor() {
        _disableInitializers();
    }

    modifier onlySafe() {
        require(msg.sender == gnosisSafe, "Only the Safe can perform this");
        _;
    }

    modifier onlySapienRewards() {
    require(msg.sender == sapienRewardsContract, "Caller is not SapienRewards contract");
    _;
    }


    function initialize(address _gnosisSafe, uint256 _totalSupply, address _sapienRewardsContract) public initializer {
        emit InitializedEvent(_gnosisSafe, _totalSupply,_sapienRewardsContract );
        uint256 totalAllocations = INVESTORS_ALLOCATION +
                               TEAM_ADVISORS_ALLOCATION +
                               LABELING_REWARDS_ALLOCATION +
                               AIRDROPS_ALLOCATION +
                               COMMUNITY_TREASURY_ALLOCATION +
                               STAKING_INCENTIVES_ALLOCATION +
                               LIQUIDITY_INCENTIVES_ALLOCATION;


        require(_gnosisSafe != address(0), "Invalid Gnosis Safe address");
        require(_totalSupply == totalAllocations, "Total supply must match the sum of all allocations");
        require(_sapienRewardsContract != address(0), "Invalid SapienRewards address");
        sapienRewardsContract = _sapienRewardsContract;
        gnosisSafe = _gnosisSafe;
        __ERC20_init("SapTestToken", "PTSPN");
        __Pausable_init();
        __UUPSUpgradeable_init();
        vestingStartTimestamp = block.timestamp;

        _mint(_gnosisSafe, _totalSupply);
        _createHardcodedVestingSchedules();
    }

    function _createHardcodedVestingSchedules() internal {
        uint256 cliff = 365 days; // 1 year cliff
        vestingSchedules["investors"] = VestingSchedule({
            cliff: cliff,
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: INVESTORS_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules["team"] = VestingSchedule({
            cliff: cliff,
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: TEAM_ADVISORS_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules["rewards"] = VestingSchedule({
            cliff: 0, // No cliff for rewards
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: LABELING_REWARDS_ALLOCATION,
            released: 0,
            safe: sapienRewardsContract
        });
        vestingSchedules["airdrop"] = VestingSchedule({
            cliff: 0, // No cliff for airdrops
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: AIRDROPS_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules["communityTreasury"] = VestingSchedule({
            cliff: 0, // No cliff for community treasury
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: COMMUNITY_TREASURY_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules["stakingIncentives"] = VestingSchedule({
            cliff: 0, // No cliff for staking incentives
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: STAKING_INCENTIVES_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules["liquidityIncentives"] = VestingSchedule({
            cliff: 0, // No cliff for liquidity incentives
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: LIQUIDITY_INCENTIVES_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
    }

    function updateVestingSchedule(
        string calldata allocationType,
        uint256 cliff,
        uint256 start,
        uint256 duration,
        uint256 amount,
        address safe
    ) external onlySafe {
        require(vestingSchedules[allocationType].amount > 0, "Invalid allocation type");
        require(cliff < duration, "Cliff must be less than duration");
        require(start >= block.timestamp, "Start time must be in the future");
        require(safe != address(0), "Invalid safe address");

        vestingSchedules[allocationType] = VestingSchedule({
            cliff: cliff,
            start: start,
            duration: duration,
            amount: amount,
            released: vestingSchedules[allocationType].released, // Preserve the released amount
            safe: safe
        });
        emit VestingScheduleUpdated(allocationType, amount);
    }

    function releaseTokens(string calldata allocationType) external nonReentrant whenNotPaused onlySafe {
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
