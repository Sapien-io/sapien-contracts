// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
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
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

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
        address safe;       // Address receiving the vested tokens
    }

    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    /// @notice Emitted when tokens are released from a vesting schedule
    event TokensReleased(AllocationType indexed destination, uint256 amount);

    /// @notice Emitted when the contract is initialized
    event InitializedEvent(address safe, uint256 amount);

    /// @notice Emitted when a vesting schedule is updated
    event VestingScheduleUpdated(AllocationType indexed allocationType, uint256 amount);

    /// @notice Emitted when a new rewards contract is proposed
    event RewardsContractChangeProposed(address indexed newRewardsContract);

    /// @notice Emitted when a new rewards contract is accepted
    event RewardsContractChangeAccepted(address indexed newRewardsContract);

    // -------------------------------------------------------------
    // Constants
    // -------------------------------------------------------------

    /// @notice Number of decimals for token amounts
    uint8 public constant DECIMALS = 18;

    /// @notice Total allocation for investors
    uint256 public constant INVESTORS_ALLOCATION = 300000000 * 10 ** DECIMALS;

    /// @notice Total allocation for team and advisors
    uint256 public constant TEAM_ADVISORS_ALLOCATION = 200000000 * 10 ** DECIMALS;

    /// @notice Total allocation for labeling rewards
    uint256 public constant LABELING_REWARDS_ALLOCATION = 150000000 * 10 ** DECIMALS;

    /// @notice Total allocation for airdrops
    uint256 public constant AIRDROPS_ALLOCATION = 150000000 * 10 ** DECIMALS;

    /// @notice Total allocation for community treasury
    uint256 public constant COMMUNITY_TREASURY_ALLOCATION = 100000000 * 10 ** DECIMALS;

    /// @notice Total allocation for staking incentives
    uint256 public constant STAKING_INCENTIVES_ALLOCATION = 50000000 * 10 ** DECIMALS;

    /// @notice Total allocation for liquidity incentives
    uint256 public constant LIQUIDITY_INCENTIVES_ALLOCATION = 50000000 * 10 ** DECIMALS;

    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    /// @dev Timestamp when vesting starts
    uint256 private vestingStartTimestamp;

    // Add enum definition
    enum AllocationType {
        INVESTORS,
        TEAM,
        REWARDS,
        AIRDROP,
        COMMUNITY_TREASURY,
        STAKING_INCENTIVES,
        LIQUIDITY_INCENTIVES
    }

    /// @notice Mapping of allocation types to their vesting schedules
    mapping(AllocationType => VestingSchedule) public vestingSchedules;

    /// @notice Address of the Gnosis Safe that controls administrative functions
    address public gnosisSafe;

    /// @notice Address of the authorized rewards contract
    address public rewardsContract;

    // Add new state variables
    address public pendingRewardsContract;

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
        
        // Calculate total expected supply from all allocations
        uint256 expectedSupply = INVESTORS_ALLOCATION +
            TEAM_ADVISORS_ALLOCATION +
            LABELING_REWARDS_ALLOCATION +
            AIRDROPS_ALLOCATION +
            COMMUNITY_TREASURY_ALLOCATION +
            STAKING_INCENTIVES_ALLOCATION +
            LIQUIDITY_INCENTIVES_ALLOCATION;
        
        require(_totalSupply == expectedSupply, "Total supply must match sum of allocations");
        
        gnosisSafe = _gnosisSafe;
        __ERC20_init("SapTestToken", "PTSPN");
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
        vestingSchedules[AllocationType.INVESTORS] = VestingSchedule({
            cliff: cliff,
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: INVESTORS_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules[AllocationType.TEAM] = VestingSchedule({
            cliff: cliff,
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: TEAM_ADVISORS_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules[AllocationType.REWARDS] = VestingSchedule({
            cliff: 0, // No cliff for rewards
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: LABELING_REWARDS_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules[AllocationType.AIRDROP] = VestingSchedule({
            cliff: 0, // No cliff for airdrops
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: AIRDROPS_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules[AllocationType.COMMUNITY_TREASURY] = VestingSchedule({
            cliff: 0, // No cliff for community treasury
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: COMMUNITY_TREASURY_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules[AllocationType.STAKING_INCENTIVES] = VestingSchedule({
            cliff: 0, // No cliff for staking incentives
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: STAKING_INCENTIVES_ALLOCATION,
            released: 0,
            safe: gnosisSafe
        });
        vestingSchedules[AllocationType.LIQUIDITY_INCENTIVES] = VestingSchedule({
            cliff: 0, // No cliff for liquidity incentives
            start: vestingStartTimestamp,
            duration: 48 * 30 days, // 48 months
            amount: LIQUIDITY_INCENTIVES_ALLOCATION,
            released: 0,
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
        AllocationType allocationType,
        uint256 cliff,
        uint256 start,
        uint256 duration,
        uint256 amount,
        address safe
    ) external onlySafe {
        // Validate allocation type exists by checking its amount
        require(vestingSchedules[allocationType].amount > 0, "Invalid allocation type");
        
        VestingSchedule storage existingSchedule = vestingSchedules[allocationType];
        
        if (block.timestamp > existingSchedule.start && existingSchedule.amount > 0) {
            require(start <= existingSchedule.start, "Cannot delay start time after vesting begins");
            require(amount >= existingSchedule.released, "Cannot reduce amount below released tokens");
            require(safe == existingSchedule.safe, "Cannot change safe address after vesting begins");
        }

        // Validate new parameters
        require(safe != address(0), "Invalid safe address");
        require(duration >= cliff, "Duration must be greater than or equal to cliff");
        require(amount > 0, "Amount must be greater than 0");
        require(start > block.timestamp, "Start time must be in the future");

        vestingSchedules[allocationType] = VestingSchedule({
            cliff: cliff,
            start: start,
            duration: duration,
            amount: amount,
            released: existingSchedule.released,
            safe: safe
        });
        emit VestingScheduleUpdated(allocationType, amount);
    }

    /**
     * @notice Proposes a new rewards contract address (step 1 of 2)
     * @param _newRewardsContract Address of the proposed rewards contract
     */
    function proposeRewardsContract(address _newRewardsContract) external onlySafe {
        require(_newRewardsContract != address(0), "Invalid rewards contract address");
        pendingRewardsContract = _newRewardsContract;
        emit RewardsContractChangeProposed(_newRewardsContract);
    }

    /**
     * @notice Accepts the proposed rewards contract change (step 2 of 2)
     */
    function acceptRewardsContract() external onlySafe {
        require(pendingRewardsContract != address(0), "No pending rewards contract");
        rewardsContract = pendingRewardsContract;
        pendingRewardsContract = address(0);
        emit RewardsContractChangeAccepted(rewardsContract);
    }

    /**
     * @notice Releases available tokens for a specific allocation type
     * @param allocationType The type of allocation to release tokens from
     */
    function releaseTokens(AllocationType allocationType) 
        external 
        nonReentrant 
        whenNotPaused 
    {
        require(
            msg.sender == rewardsContract || msg.sender == gnosisSafe,
            "Caller is not authorized"
        );
        
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
