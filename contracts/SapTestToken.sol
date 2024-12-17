// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

contract SapTestToken is
    Initializable,
    ERC20Upgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    struct VestingSchedule {
        uint256 cliff;
        uint256 start;
        uint256 duration;
        uint256 amount;
        uint256 released;
        bool revoked;
        address safe;
    }

    event TokensReleased(string destination, uint256 amount);
    event InitializedEvent(address safe, uint256 amount);
    event VestingScheduleUpdated(string allocationType, uint256 amount);

    uint256 public constant INVESTORS_ALLOCATION = 300000000 * 10 ** 18;
    uint256 public constant TEAM_ADVISORS_ALLOCATION = 200000000 * 10 ** 18;
    uint256 public constant LABELING_REWARDS_ALLOCATION = 150000000 * 10 ** 18;
    uint256 public constant AIRDROPS_ALLOCATION = 150000000 * 10 ** 18;
    uint256 public constant COMMUNITY_TREASURY_ALLOCATION = 100000000 * 10 ** 18;
    uint256 public constant STAKING_INCENTIVES_ALLOCATION = 50000000 * 10 ** 18;
    uint256 public constant LIQUIDITY_INCENTIVES_ALLOCATION = 50000000 * 10 ** 18;

    uint256 private vestingStartTimestamp;
    mapping(string => VestingSchedule) public vestingSchedules;
    address public gnosisSafe;

    modifier onlySafe() {
        require(msg.sender == gnosisSafe, "Only the Safe can perform this");
        _;
    }

    function initialize(address _gnosisSafe, uint256 _totalSupply) public initializer {
        emit InitializedEvent(_gnosisSafe, _totalSupply);
        require(_gnosisSafe != address(0), "Invalid Gnosis Safe address");
        require(_totalSupply > 0, "Total supply must be greater than zero");
        gnosisSafe = _gnosisSafe;
        __ERC20_init("SapTestToken", "SAPTEST");
        __Ownable_init(gnosisSafe);
        __Pausable_init();
        __UUPSUpgradeable_init();
        vestingStartTimestamp = block.timestamp;

        _mint(_gnosisSafe, _totalSupply);
        _createHardcodedVestingSchedules();
    }

    function _createHardcodedVestingSchedules() internal {
        uint256 cliff = 0 days;
        vestingSchedules["investors"] = VestingSchedule({
            cliff: cliff,
            start: vestingStartTimestamp,
            duration: 2 * 1 days,
            amount: INVESTORS_ALLOCATION,
            released: 0,
            revoked: false,
            safe: gnosisSafe
        });
        vestingSchedules["team"] = VestingSchedule({
            cliff: cliff,
            start: vestingStartTimestamp,
            duration: 2 * 1 days,
            amount: TEAM_ADVISORS_ALLOCATION,
            released: 0,
            revoked: false,
            safe: gnosisSafe
        });
        vestingSchedules["rewards"] = VestingSchedule({
            cliff: cliff,
            start: vestingStartTimestamp,
            duration: 2 * 1 days,
            amount: LABELING_REWARDS_ALLOCATION,
            released: 0,
            revoked: false,
            safe: 0x6957342b8b28A0252ef9EeB5dadCEfaB31283c77
        });
        vestingSchedules["airdrop"] = VestingSchedule({
            cliff: cliff,
            start: vestingStartTimestamp,
            duration: 2 * 1 days,
            amount: AIRDROPS_ALLOCATION,
            released: 0,
            revoked: false,
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
        vestingSchedules[allocationType] = VestingSchedule({
            cliff: cliff,
            start: start,
            duration: duration,
            amount: amount,
            released: vestingSchedules[allocationType].released, // Preserve the released amount
            revoked: false,
            safe: safe
        });
        emit VestingScheduleUpdated(allocationType, amount);
    }
	// Removed only safe. Add it back and whitelist the contracts
    function releaseTokens(string calldata allocationType) external nonReentrant whenNotPaused {
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
