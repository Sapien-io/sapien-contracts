// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

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
		uint256 cliff; // The time period after which vesting starts
		uint256 start; // When vesting begins
		uint256 duration; // The total vesting period
		uint256 amount; // The total amount to be vested
		uint256 released; // The amount already released
		bool revoked; // Whether the vesting has been revoked
		address safe; // Safe address
	}
	event TokensReleased(string destination, uint256 amount);
	event InitializedEvent(address safe, uint256 amount);

	// Allocation constants
	uint256 public constant INVESTORS_ALLOCATION = 300000000 * 10 ** 18;
	uint256 public constant TEAM_ADVISORS_ALLOCATION = 200000000 * 10 ** 18;
	uint256 public constant LABELING_REWARDS_ALLOCATION = 150000000 * 10 ** 18;
	uint256 public constant AIRDROPS_ALLOCATION = 150000000 * 10 ** 18;
	uint256 public constant COMMUNITY_TREASURY_ALLOCATION =
		100000000 * 10 ** 18;
	uint256 public constant STAKING_INCENTIVES_ALLOCATION = 50000000 * 10 ** 18;
	uint256 public constant LIQUIDITY_INCENTIVES_ALLOCATION =
		50000000 * 10 ** 18;

	// Vesting related variables
	uint256 private vestingStartTimestamp;

	uint256 lastReleasedAt;

	// TODO bytes32
	mapping(string => VestingSchedule) public vestingSchedules;

	address public gnosisSafe;


	// Modifier to restrict access to only the Gnosis Safe
	modifier onlySafe() {
		require(
			msg.sender == gnosisSafe,
			"Only the Safe can perform this"
		);
		_;
	}


// TODO The initialize function mints _totalSupply to the Gnosis Safe but does not ensure that 
// the total supply matches the sum of all vesting schedules. Consider adding checks to 
// ensure consistency between the total supply minted and the sum of all allocated 
// tokens (investors, team, etc.).
	function initialize(
		address _gnosisSafe,
		uint256 _totalSupply
	) public initializer() {
		emit InitializedEvent(_gnosisSafe, _totalSupply);
		require(_gnosisSafe != address(0), "Invalid Gnosis Safe address");
		require(_totalSupply > 0, "Total supply must be greater than zero");
		gnosisSafe = _gnosisSafe;
		__ERC20_init("SapTestToken", "SAPTEST");
		__Ownable_init(gnosisSafe);
		__Pausable_init();
		__UUPSUpgradeable_init();
		vestingStartTimestamp = block.timestamp;

		// Mint total supply to Gnosis Safe
		_mint(_gnosisSafe, _totalSupply);

		// Hardcoded vesting schedules for different allocations
		_createHardcodedVestingSchedules();
	}

	function _createHardcodedVestingSchedules() internal {
		uint256 cliff = 0 days;
		VestingSchedule memory investorsSchedule = VestingSchedule({
		cliff: 0,
		start: vestingStartTimestamp,
		duration: 2 * 1 days,
		amount: TEAM_ADVISORS_ALLOCATION,
		released: 0,
		revoked: false,
		safe: gnosisSafe
		});
		vestingSchedules["investors"] = investorsSchedule;
		vestingSchedules["team"] = VestingSchedule({
			cliff: cliff,
			start: vestingStartTimestamp,
			duration: 2 * 1 days, // 2 days vesting duration
			amount: TEAM_ADVISORS_ALLOCATION,
			released: 0,
			revoked: false,
			safe: gnosisSafe
		});
		vestingSchedules["rewards"] = VestingSchedule({
			cliff: cliff,
			start: vestingStartTimestamp,
			duration: 2 * 1 days, // 2 days vesting duration
			amount: LABELING_REWARDS_ALLOCATION,
			released: 0,
			revoked: false,
			safe: gnosisSafe
		});
		vestingSchedules["airdrop"] = VestingSchedule({
			cliff: cliff,
			start: vestingStartTimestamp,
			duration: 2 * 1 days, // 2 days vesting duration
			amount: AIRDROPS_ALLOCATION,
			released: 0,
			revoked: false,
			safe: gnosisSafe
		});
		vestingSchedules["community"] = VestingSchedule({
			cliff: cliff,
			start: vestingStartTimestamp,
			duration: 2 * 1 days, // 2 days vesting duration
			amount: COMMUNITY_TREASURY_ALLOCATION,
			released: 0,
			revoked: false,
			safe: gnosisSafe
		});
		vestingSchedules["staking"] = VestingSchedule({
			cliff: cliff,
			start: vestingStartTimestamp,
			duration: 2 * 1 days, // 2 days vesting duration
			amount: STAKING_INCENTIVES_ALLOCATION,
			released: 0,
			revoked: false,
			safe: gnosisSafe
		});
		vestingSchedules["liquidity"] = VestingSchedule({
			cliff: cliff,
			start: vestingStartTimestamp,
			duration: 2 * 1 days, // 2 days vesting duration
			amount: LIQUIDITY_INCENTIVES_ALLOCATION,
			released: 0,
			revoked: false,
			safe: gnosisSafe
		});
	}

   function releaseTokens(string calldata allocationType) external onlySafe nonReentrant whenNotPaused()  {
		VestingSchedule storage schedule = vestingSchedules[allocationType];
		require(schedule.amount > 0, "No tokens to release");

		uint256 currentTime = block.timestamp;
		uint256 elapsedTime = currentTime - schedule.start;
		require(elapsedTime >= schedule.cliff, "Cliff not reached");

		uint256 vestingPeriod = elapsedTime > schedule.duration ? schedule.duration : elapsedTime;
		uint256 vestedAmount = (schedule.amount * vestingPeriod) / schedule.duration;
		uint256 releasableAmount = vestedAmount - schedule.released;
		require(releasableAmount > 0, "No tokens releasable");

		schedule.released += releasableAmount;
		_transfer(gnosisSafe, msg.sender, releasableAmount);
		emit TokensReleased(allocationType, releasableAmount);
	}

	// Pause token transfers, only Gnosis Safe can call this function
	function pause() external onlySafe {
		_pause();
	}

	// Resume token transfers, only Gnosis Safe can call this function
	function unpause() external onlySafe {
		_unpause();
	}

	// Override ERC20 transfer functions to respect pause functionality
	function _update(
		address from,
		address to,
		uint256 amount
	) internal virtual override(ERC20Upgradeable) whenNotPaused {
		super._update(from, to, amount);
	}

	function _msgSender()
		internal
		view
		virtual
		override(ContextUpgradeable)
		returns (address)
	{
		return super._msgSender();
	}

	function _msgData()
		internal
		view
		virtual
		override(ContextUpgradeable)
		returns (bytes calldata)
	{
		return super._msgData();
	}

	// Override _contextSuffixLength to avoid conflicts
	function _contextSuffixLength()
		internal
		view
		virtual
		override(ContextUpgradeable)
		returns (uint256)
	{
		return super._contextSuffixLength();
	}

	 // UUPS authorize upgrade function - must be implemented
	function _authorizeUpgrade(address newImplementation) internal override onlySafe {}
}
