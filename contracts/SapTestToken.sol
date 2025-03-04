// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

/**
 * @title SapTestToken
 * @dev An upgradeable ERC20 token with vesting schedules for different allocation types.
 *      Supports UUPS upgrades and includes pause functionality.
 *
 *      - Implements vesting schedules for different token allocations (investors, team, rewards, etc.)
 *      - Only the Gnosis Safe can perform administrative actions
 *      - Supports pausing and upgrading via UUPS pattern
 *      - Includes reentrancy protection for token releases
 */
contract SapTestToken is
    Initializable,
    ERC20Upgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    // -------------------------------------------------------------
    // Structs
    // -------------------------------------------------------------

    /**
     * @dev Structure defining a vesting schedule for token allocations
     */
    struct VestingSchedule {
        uint256 cliff;      // Duration before tokens start vesting
        uint256 start;      // Timestamp when vesting begins
        uint256 duration;   // Total duration of vesting period
        uint256 amount;     // Total amount of tokens to vest
        uint256 released;   // Amount of tokens already released
        bool revoked;       // Whether the schedule has been revoked
        address safe;       // Address receiving the vested tokens
    }

    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    /// @notice Emitted when tokens are released from a vesting schedule
    event TokensReleased(string destination, uint256 amount);

    /// @notice Emitted when the contract is initialized
    event InitializedEvent(address safe, uint256 amount);

    /// @notice Emitted when a vesting schedule is updated
    event VestingScheduleUpdated(string allocationType, uint256 amount);

    // -------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------

    /// @notice Total allocation for investors
    uint256 public constant INVESTORS_ALLOCATION = 300000000 * 10 ** 18;

    /// @notice Total allocation for team and advisors
    uint256 public constant TEAM_ADVISORS_ALLOCATION = 200000000 * 10 ** 18;

    /// @notice Total allocation for labeling rewards
    uint256 public constant LABELING_REWARDS_ALLOCATION = 150000000 * 10 ** 18;

    /// @notice Total allocation for airdrops
    uint256 public constant AIRDROPS_ALLOCATION = 150000000 * 10 ** 18;

    /// @notice Total allocation for community treasury
    uint256 public constant COMMUNITY_TREASURY_ALLOCATION = 100000000 * 10 ** 18;

    /// @notice Total allocation for staking incentives
    uint256 public constant STAKING_INCENTIVES_ALLOCATION = 50000000 * 10 ** 18;

    /// @notice Total allocation for liquidity incentives
    uint256 public constant LIQUIDITY_INCENTIVES_ALLOCATION = 50000000 * 10 ** 18;

    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    /// @dev Timestamp when vesting starts
    uint256 private vestingStartTimestamp;

    /// @notice Mapping of allocation types to their vesting schedules
    mapping(string => VestingSchedule) public vestingSchedules;

    /// @notice Address of the Gnosis Safe that controls administrative functions
    address public gnosisSafe;

    // -------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------

    /**
     * @dev Ensures the caller is the Gnosis Safe
     */
    modifier onlySafe() {
        require(msg.sender == gnosisSafe, "Only the Safe can perform this");
        _;
    }

    // -------------------------------------------------------------
    // Initialization
    // -------------------------------------------------------------

    /**
     * @notice Initializes the token contract with initial supply and Gnosis Safe address
     * @param _gnosisSafe Address of the Gnosis Safe that will control the contract
     * @param _totalSupply Initial total supply of tokens
     */
    function initialize(address _gnosisSafe, uint256 _totalSupply) public initializer {
        emit InitializedEvent(_gnosisSafe, _totalSupply);
        require(_gnosisSafe != address(0), "Invalid Gnosis Safe address");
        require(_totalSupply > 0, "Total supply must be greater than zero");
        
        gnosisSafe = _gnosisSafe;
        __ERC20_init("SapTestToken", "PTSPN");
        __Ownable_init(gnosisSafe);
        __Pausable_init();
        __UUPSUpgradeable_init();
        vestingStartTimestamp = block.timestamp;

        _mint(_gnosisSafe, _totalSupply);
        _createHardcodedVestingSchedules();
        
        emit InitializedEvent(_gnosisSafe, _totalSupply);
    }

    // -------------------------------------------------------------
    // Internal Functions
    // -------------------------------------------------------------

    /**
     * @dev Creates the initial vesting schedules for all allocation types
     */
    function _createHardcodedVestingSchedules() internal {
        uint256 cliff = 365 days; // 1 year cliff
        vestingSchedules["investors"] = VestingSchedule({
            cliff: cliff,
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: INVESTORS_ALLOCATION,
            released: 0,
            revoked: false,
            safe: gnosisSafe
        });
        vestingSchedules["team"] = VestingSchedule({
            cliff: cliff,
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: TEAM_ADVISORS_ALLOCATION,
            released: 0,
            revoked: false,
            safe: gnosisSafe
        });
        vestingSchedules["rewards"] = VestingSchedule({
            cliff: 0, // No cliff for rewards
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: LABELING_REWARDS_ALLOCATION,
            released: 0,
            revoked: false,
            safe: gnosisSafe
        });
        vestingSchedules["airdrop"] = VestingSchedule({
            cliff: 0, // No cliff for airdrops
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: AIRDROPS_ALLOCATION,
            released: 0,
            revoked: false,
            safe: gnosisSafe
        });
        vestingSchedules["communityTreasury"] = VestingSchedule({
            cliff: 0, // No cliff for community treasury
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: COMMUNITY_TREASURY_ALLOCATION,
            released: 0,
            revoked: false,
            safe: gnosisSafe
        });
        vestingSchedules["stakingIncentives"] = VestingSchedule({
            cliff: 0, // No cliff for staking incentives
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: STAKING_INCENTIVES_ALLOCATION,
            released: 0,
            revoked: false,
            safe: gnosisSafe
        });
        vestingSchedules["liquidityIncentives"] = VestingSchedule({
            cliff: 0, // No cliff for liquidity incentives
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: LIQUIDITY_INCENTIVES_ALLOCATION,
            released: 0,
            revoked: false,
            safe: gnosisSafe
        });
    }

    /**
     * @dev Authorizes an upgrade to a new implementation (UUPS)
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlySafe {}

    // -------------------------------------------------------------
    // External Functions
    // -------------------------------------------------------------

    /**
     * @notice Updates a vesting schedule for a specific allocation type
     * @param allocationType The type of allocation to update
     * @param cliff Duration before tokens start vesting
     * @param start Timestamp when vesting begins
     * @param duration Total duration of vesting period
     * @param amount Total amount of tokens to vest
     * @param safe Address that will receive the vested tokens
     */
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
            released: vestingSchedules[allocationType].released,
            revoked: false,
            safe: safe
        });
        emit VestingScheduleUpdated(allocationType, amount);
    }

    /**
     * @notice Releases available tokens for a specific allocation type
     * @param allocationType The type of allocation to release tokens from
     */
    function releaseTokens(string calldata allocationType) 
        external 
        nonReentrant 
        whenNotPaused 
    {
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

    /**
     * @notice Pauses all token transfers and releases
     */
    function pause() external onlySafe {
        _pause();
    }

    /**
     * @notice Unpauses all token transfers and releases
     */
    function unpause() external onlySafe {
        _unpause();
    }
}
