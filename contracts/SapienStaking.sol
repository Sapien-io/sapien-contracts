// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";

/**
 * @title SapienStaking
 * @notice This contract enables users to stake Sapien tokens for specific lock-up periods
 *         to potentially earn multipliers. It supports the following features:
 *         - Different lock-up periods (1/3/6/12 months) with corresponding maximum multipliers.
 *         - EIP-712 signature verification for stake actions (STAKE, INITIATE_UNSTAKE, UNSTAKE, INSTANT_UNSTAKE).
 *         - A cooldown period before unstaking, with options for instant unstake (with penalty).
 *         - Contract pausing, upgradeability (UUPS), and reentrancy guard.
 */
contract SapienStaking is
    Initializable,
    PausableUpgradeable,
    Ownable2StepUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable
{
    using ECDSAUpgradeable for bytes32;

    /// @dev Constructor that disables initializers
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    // -------------------------------------------------------------
    // State Variables
    // -------------------------------------------------------------

    /// @notice The Sapien token interface for staking/unstaking (IERC20).
    /// @dev Effectively immutable, but can't use immutable keyword due to upgradeability
    IERC20Upgradeable private _sapienToken;

    /// @notice The authorized Sapien signer address (for verifying signatures).
    /// @dev Effectively immutable, but can't use immutable keyword due to upgradeability
    address private _sapienAddress;
    
    /// @notice Address of the Gnosis Safe that controls administrative functions (effectively immutable, but can't use immutable keyword due to upgradeability)
    address public _gnosisSafe;

    /// @dev Constant for the token's decimal representation (e.g., 10^18 for 18 decimal tokens).
    uint256 private constant TOKEN_DECIMALS = 10 ** 18;

    /**
     * @dev Struct holding staking details for each staker and their specific stake (by orderId).
     * @param amount The amount of tokens staked.
     * @param lockUpPeriod The duration of the lock-up in seconds.
     * @param startTime The timestamp when the stake started.
     * @param multiplier The multiplier applicable to the stake.
     * @param cooldownStart The timestamp when the user initiated unstaking.
     * @param cooldownAmount The amount approved for unstaking during cooldown.
     * @param isActive Indicates if this stake is currently active.
     */
    struct StakingInfo {
        uint256 amount;
        uint256 lockUpPeriod;
        uint256 startTime;
        uint256 multiplier;
        uint256 cooldownStart;
        uint256 cooldownAmount;
        bool isActive;
    }

    /// @notice Mapping of user addresses and their `orderId` to a StakingInfo struct.
    mapping(address => mapping(bytes32 => StakingInfo)) public stakers;

    /// @notice Tracks the total amount of tokens staked in this contract.
    uint256 public totalStaked;

    /// @notice The base stake required for minimum multiplier calculations (e.g., 1000 * 10^18).
    uint256 public constant BASE_STAKE = 1000 * TOKEN_DECIMALS;

    // Maximum multipliers for specific lock-up periods (now with 2 decimal precision)
    uint256 public constant ONE_MONTH_MAX_MULTIPLIER = 10500;      // For 30 days (105.00%)
    uint256 public constant THREE_MONTHS_MAX_MULTIPLIER = 11000;   // For 90 days (110.00%)
    uint256 public constant SIX_MONTHS_MAX_MULTIPLIER = 12500;     // For 180 days (125.00%)
    uint256 public constant TWELVE_MONTHS_MAX_MULTIPLIER = 15000;  // For 365 days (150.00%)

    /// @notice The cooldown period before a user can finalize their unstake.
    uint256 public constant COOLDOWN_PERIOD = 2 days;

    /// @dev Penalty percentage for instant unstake (e.g., 20 means 20%).
    uint256 private constant EARLY_WITHDRAWAL_PENALTY = 20;

    // EIP-712 domain separator constants
    bytes32 private constant EIP712_DOMAIN_TYPEHASH = keccak256(
        "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
    );
    bytes32 private constant STAKE_TYPEHASH = keccak256(
        "Stake(address userWallet,uint256 amount,bytes32 orderId,uint8 actionType)"
    );

    /// @notice EIP-712 domain separator for this contract.
    bytes32 private DOMAIN_SEPARATOR;

    /**
     * @dev Action types for EIP-712 signatures.
     * STAKE: Stake tokens;
     * INITIATE_UNSTAKE: Start the cooldown;
     * UNSTAKE: Finalize after cooldown;
     * INSTANT_UNSTAKE: Immediately unstake with a penalty.
     */
    enum ActionType { STAKE, INITIATE_UNSTAKE, UNSTAKE, INSTANT_UNSTAKE }

    /// @notice Mapping to track used orders to prevent reuse.
    mapping(bytes32 => bool) private usedOrders;

    // -------------------------------------------------------------
    // Events
    // -------------------------------------------------------------

    /**
     * @notice Emitted when a user stakes tokens.
     * @param user The user's address.
     * @param amount The amount staked.
     * @param multiplier The applied multiplier for this stake.
     * @param lockUpPeriod The lock-up duration in seconds.
     * @param orderId The unique identifier for this stake request.
     */
    event Staked(
        address indexed user,
        uint256 amount,
        uint256 multiplier,
        uint256 lockUpPeriod,
        bytes32 orderId
    );

    /**
     * @notice Emitted when a user initiates the unstaking process (starts cooldown).
     * @param user The user's address initiating unstake.
     * @param amount The staked amount associated with the stake.
     * @param orderId The unique identifier for the original stake.
     */
    event UnstakingInitiated(address indexed user, uint256 amount, bytes32 orderId);

    /**
     * @notice Emitted when a user completes unstaking after the cooldown.
     * @param user The user's address.
     * @param amount The amount unstaked.
     * @param orderId The unique identifier for the original stake.
     */
    event Unstaked(address indexed user, uint256 amount, bytes32 orderId);

    /**
     * @notice Emitted when a user performs an instant unstake (penalty applied).
     * @param user The user's address.
     * @param amount The amount actually received by the user (penalty deducted).
     * @param orderId The unique identifier for the original stake.
     */
    event InstantUnstake(address indexed user, uint256 amount, bytes32 orderId);

    // -------------------------------------------------------------
    // Initialization (UUPS)
    // -------------------------------------------------------------

    /**
     * @notice Initializes the SapienStaking contract.
     * @param sapienToken_ The ERC20 token contract for Sapien.
     * @param sapienAddress_ The address authorized to sign stake actions.
     * @param gnosisSafe_ The address of the Gnosis Safe.
     */
    function initialize(
      IERC20Upgradeable sapienToken_,
      address sapienAddress_,
      address gnosisSafe_
    )
        public
        initializer
    {
        require(address(sapienToken_) != address(0), "Zero address not allowed for token");
        require(sapienAddress_ != address(0), "Zero address not allowed for signer");
        require(gnosisSafe_ != address(0), "Zero address not allowed for Gnosis Safe");

        _gnosisSafe = gnosisSafe_;
        
        _sapienToken = sapienToken_;
        _sapienAddress = sapienAddress_;

        __Pausable_init();
        __Ownable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();

        // Initialize the EIP-712 domain separator
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                EIP712_DOMAIN_TYPEHASH,
                keccak256("SapienStaking"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /**
     * @notice Authorizes an upgrade of this contract to a new implementation (UUPS).
     *         Only the contract owner can upgrade.
     * @param newImplementation The address of the new contract implementation.
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlySafe
    {}

    // -------------------------------------------------------------
    // Modifiers
    // -------------------------------------------------------------

    /**
     * @dev Ensures the caller is the Gnosis Safe
     */
    modifier onlySafe() {
        require(msg.sender == _gnosisSafe, "Only the Safe can perform this");
        _;
    }

    // -------------------------------------------------------------
    // Owner-Only Functions
    // -------------------------------------------------------------

    /**
     * @notice Pauses the contract, preventing certain actions (e.g., staking/unstaking).
     *         Only callable by the owner.
     */
    function pause() external onlySafe {
        _pause();
    }

    /**
     * @notice Unpauses the contract, allowing staking/unstaking.
     *         Only callable by the owner.
     */
    function unpause() external onlySafe {
        _unpause();
    }

    // -------------------------------------------------------------
    // Public Functions
    // -------------------------------------------------------------

    /**
     * @notice Stake a specified `amount` of tokens for a given `lockUpPeriod`, 
     *         identified by a unique `orderId` and validated by an EIP-712 signature.
     * @dev Users must approve this contract to spend their tokens before calling `stake`.
     * @param amount The amount of tokens to stake.
     * @param lockUpPeriod The lock-up duration in seconds (30/90/180/365 days).
     * @param orderId A unique identifier for this stake request.
     * @param signature The EIP-712 signature from the authorized signer.
     */
    function stake(
        uint256 amount,
        uint256 lockUpPeriod,
        bytes32 orderId,
        bytes memory signature
    )
        public
        whenNotPaused
        nonReentrant
    {
        require(amount > 0, "Amount must be greater than 0");
        require(
            lockUpPeriod == 30 days ||
                lockUpPeriod == 90 days ||
                lockUpPeriod == 180 days ||
                lockUpPeriod == 365 days,
            "Invalid lock-up period"
        );
        require(!usedOrders[orderId], "Order already used");
        require(
            verifyOrder(msg.sender, amount, orderId, ActionType.STAKE, signature),
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
            cooldownAmount: 0,
            isActive: true
        });

        totalStaked += amount;
        _markOrderAsUsed(orderId);

        require(
            _sapienToken.transferFrom(msg.sender, address(this), amount),
            "Token transfer failed"
        );

        emit Staked(msg.sender, amount, multiplier, lockUpPeriod, orderId);
    }

    /**
     * @notice Initiates the cooldown for unstaking.
     * @param amount The amount intended for unstaking (used for signature validation).
     * @param newOrderId A new unique identifier for this action.
     * @param stakeOrderId The original stake `orderId` that the user wants to unstake from.
     * @param signature The EIP-712 signature from the authorized signer.
     */
    function initiateUnstake(
        uint256 amount,
        bytes32 newOrderId,
        bytes32 stakeOrderId,
        bytes memory signature
    )
        public
        whenNotPaused
        nonReentrant
    {
        StakingInfo storage info = stakers[msg.sender][stakeOrderId];
        require(info.isActive, "Staking position not active");
        require(info.cooldownStart == 0, "Cooldown already initiated");
        require(!usedOrders[newOrderId], "Order already used");
        require(amount <= info.amount, "Amount exceeds staked amount");
        require(
            verifyOrder(msg.sender, amount, newOrderId, ActionType.INITIATE_UNSTAKE, signature),
            "Invalid signature or mismatched parameters"
        );
        // Add check for lock period completion
        require(
            block.timestamp >= info.startTime + info.lockUpPeriod,
            "Lock period not completed"
        );

        info.cooldownStart = block.timestamp;
        info.cooldownAmount = amount; // Store the amount approved for unstaking
        _markOrderAsUsed(newOrderId);

        emit UnstakingInitiated(msg.sender, amount, newOrderId);
    }

    /**
     * @notice Completes the unstaking process after the cooldown period has passed.
     * @param amount The amount to unstake (used for signature validation).
     * @param newOrderId A new unique identifier for this action.
     * @param stakeOrderId The original stake `orderId` the user is unstaking from.
     * @param signature The EIP-712 signature from the authorized signer.
     */
    function unstake(
        uint256 amount,
        bytes32 newOrderId,
        bytes32 stakeOrderId,
        bytes memory signature
    )
        public
        whenNotPaused
        nonReentrant
    {
        require(amount > 0, "Amount must be greater than 0");
        
        StakingInfo storage info = stakers[msg.sender][stakeOrderId];
        require(info.isActive, "Staking position not active");
        require(info.cooldownStart > 0, "Cooldown not initiated");
        require(!usedOrders[newOrderId], "Order already used");
        require(amount <= info.amount, "Amount exceeds staked amount");
        require(amount <= info.cooldownAmount, "Amount exceeds approved unstake amount");
        require(
            verifyOrder(msg.sender, amount, newOrderId, ActionType.UNSTAKE, signature),
            "Invalid signature or mismatched parameters"
        );
        require(
            block.timestamp >= info.cooldownStart + COOLDOWN_PERIOD,
            "Cooldown period not completed"
        );
        
        // Add check for lock period completion
        require(
            block.timestamp >= info.startTime + info.lockUpPeriod,
            "Lock period not completed"
        );

        // Transfer the exact amount (no multiplier bonus applied to tokens)
        require(
            _sapienToken.transfer(msg.sender, amount),
            "Token transfer failed"
        );
        info.amount -= amount;
        info.cooldownAmount -= amount; // Reduce the approved cooldown amount
        
        // If this is a partial unstake, reset cooldown to allow future unstaking
        if (info.amount > 0) {
            info.cooldownStart = 0;
            info.cooldownAmount = 0;
        }
        
        info.isActive = info.amount > 0;
        totalStaked -= amount;
        _markOrderAsUsed(newOrderId);

        emit Unstaked(msg.sender, amount, newOrderId);
    }

    /**
     * @notice Instantly unstakes a specified `amount`, incurring a penalty (20% by default).
     * @param amount The amount to unstake instantly.
     * @param newOrderId A new unique identifier for this action.
     * @param stakeOrderId The original stake `orderId` the user is instantly unstaking from.
     * @param signature The EIP-712 signature from the authorized signer.
     */
    function instantUnstake(
        uint256 amount,
        bytes32 newOrderId,
        bytes32 stakeOrderId,
        bytes memory signature
    )
        public
        whenNotPaused
        nonReentrant
    {
        StakingInfo storage info = stakers[msg.sender][stakeOrderId];
        require(info.isActive, "Staking position not active");
        require(!usedOrders[newOrderId], "Order already used");
        require(
            verifyOrder(msg.sender, amount, newOrderId, ActionType.INSTANT_UNSTAKE, signature),
            "Invalid signature or mismatched parameters"
        );
        // Add check to ensure instant unstake is only possible during lock period
        require(
            block.timestamp < info.startTime + info.lockUpPeriod,
            "Lock period completed, use regular unstake"
        );

        // Calculate penalty
        uint256 penalty = (amount * EARLY_WITHDRAWAL_PENALTY) / 100;
        uint256 payout = amount - penalty;

        // Update staked amount
        info.amount -= amount;
        if (info.amount == 0) {
            info.isActive = false;
        }
        totalStaked -= amount;

        // Transfer net amount to user, penalty to owner
        require(
            _sapienToken.transfer(msg.sender, payout),
            "Token transfer to user failed"
        );
        require(
            _sapienToken.transfer(owner(), penalty),
            "Token transfer of penalty failed"
        );

        _markOrderAsUsed(newOrderId);

        emit InstantUnstake(msg.sender, payout, newOrderId);
    }

    // -------------------------------------------------------------
    // Internal/Private Functions
    // -------------------------------------------------------------

    /**
     * @notice Calculates the multiplier for a given `amount` based on the `maxMultiplier`.
     * @dev If `amount` >= BASE_STAKE, the multiplier is `maxMultiplier`.
     *      Otherwise, it linearly scales from 10000 (100.00%) up to `maxMultiplier`.
     *      Multipliers use 2 decimal places of precision (e.g., 14950 = 149.50%)
     * @param amount The amount staked.
     * @param maxMultiplier The maximum possible multiplier for the given lock-up period.
     * @return The calculated multiplier (clamped at `maxMultiplier` if needed).
     */
    function calculateMultiplier(uint256 amount, uint256 maxMultiplier)
        private
        pure
        returns (uint256)
    {
        // Base multiplier (100%) when no bonus is applied
        uint256 baseMultiplier = 10000;
        
        // Create tiers for more granular multiplier calculation
        // Each tier represents 25% of BASE_STAKE
        uint256 tier1 = BASE_STAKE / 4;     // 250 tokens
        uint256 tier2 = BASE_STAKE / 2;     // 500 tokens
        uint256 tier3 = (BASE_STAKE * 3) / 4; // 750 tokens
        
        // Calculate the bonus range (difference between max and base multiplier)
        uint256 bonusRange = maxMultiplier - baseMultiplier;
        
        if (amount >= BASE_STAKE) {
            return maxMultiplier;
        } else if (amount >= tier3) {
            // 75-100% of bonus range
            return baseMultiplier + (bonusRange * 75 / 100) + 
                   (bonusRange * 25 * (amount - tier3) / (BASE_STAKE - tier3) / 100);
        } else if (amount >= tier2) {
            // 50-75% of bonus range
            return baseMultiplier + (bonusRange * 50 / 100) +
                   (bonusRange * 25 * (amount - tier2) / (tier3 - tier2) / 100);
        } else if (amount >= tier1) {
            // 25-50% of bonus range
            return baseMultiplier + (bonusRange * 25 / 100) +
                   (bonusRange * 25 * (amount - tier1) / (tier2 - tier1) / 100);
        } else {
            // 0-25% of bonus range
            return baseMultiplier +
                   (bonusRange * 25 * amount / tier1 / 100);
        }
    }

    /**
     * @notice Returns the max multiplier based on the lock-up period.
     * @dev Assumes the lockUpPeriod has already been validated.
     * @param lockUpPeriod The duration of lock-up in seconds.
     * @return The maximum multiplier for the specified lock-up period.
     */
    function getMaxMultiplier(uint256 lockUpPeriod)
        private
        pure
        returns (uint256)
    {
        if (lockUpPeriod == 30 days) {
            return ONE_MONTH_MAX_MULTIPLIER;
        }
        if (lockUpPeriod == 90 days) {
            return THREE_MONTHS_MAX_MULTIPLIER;
        }
        if (lockUpPeriod == 180 days) {
            return SIX_MONTHS_MAX_MULTIPLIER;
        }
        if (lockUpPeriod == 365 days) {
            return TWELVE_MONTHS_MAX_MULTIPLIER;
        }
        return 0; // This line should never be reached due to validation in stake()
    }

    /**
     * @notice Verifies the EIP-712 signature for a staking action.
     * @param userWallet The wallet of the user performing the action.
     * @param amount The amount being staked/unstaked (used for signature check).
     * @param orderId A unique identifier for the action.
     * @param actionType The type of action (STAKE, INITIATE_UNSTAKE, UNSTAKE, INSTANT_UNSTAKE).
     * @param signature The EIP-712 signature to validate.
     * @return True if the recovered signer is the authorized `sapienAddress`, otherwise false.
     */
    function verifyOrder(
        address userWallet,
        uint256 amount,
        bytes32 orderId,
        ActionType actionType,
        bytes memory signature
    )
        private
        view
        returns (bool)
    {
        require(!usedOrders[orderId], "Order already used");

        bytes32 structHash = keccak256(
            abi.encode(
                STAKE_TYPEHASH,
                userWallet,
                amount,
                orderId,
                uint8(actionType)
            )
        );

        bytes32 hash = keccak256(
            abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash)
        );

        address signer = hash.recover(signature);
        return (signer == _sapienAddress);
    }

    /**
     * @notice Marks a given `orderId` as used to prevent reuse.
     * @param orderId The unique identifier for the action.
     */
    function _markOrderAsUsed(bytes32 orderId) private {
        usedOrders[orderId] = true;
    }
}
