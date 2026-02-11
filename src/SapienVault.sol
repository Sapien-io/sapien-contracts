// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    ERC4626Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/ERC20Upgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/interfaces/IERC20.sol";
import {SafeERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {
    ReentrancyGuardUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {Initializable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ISapienVault} from "./interface/ISapienVault.sol";
import {LOCKER_ROLE, SLASHER_ROLE, PAUSER_ROLE} from "./interface/ISharedTypes.sol";

/**
 * @title SapienVault
 * @notice ERC-4626 compliant vault for staking with slashing capability (Upgradeable)
 * @dev Users deposit staking tokens and receive vault shares.
 *      Slashing burns shares from penalized users, reducing their position.
 *      Uses transparent proxy pattern for upgradeability.
 */
contract SapienVault is
    ISapienVault,
    Initializable,
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;

    /// @notice Amount of stake locked for each user (prevents withdrawal/transfer)
    /// @dev user => locked amount in assets
    mapping(address => uint256) public lockedStake;

    // Storage gap for future upgrades (49 slots reserved)
    // forge-lint: disable-next-line(mixed-case-variable)
    // __gap follows OpenZeppelin upgradeable contract pattern
    uint256[49] private __gap;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize the vault (replaces constructor for upgradeable pattern)
     * @param _stakingToken The underlying token to be staked
     * @param _defaultAdmin The address to grant DEFAULT_ADMIN_ROLE
     */
    function initialize(address _stakingToken, address _defaultAdmin) public initializer {
        if (_stakingToken == address(0)) revert InvalidAddress();
        if (_defaultAdmin == address(0)) revert InvalidAddress();

        __ERC4626_init(IERC20(_stakingToken));
        __ERC20_init("Sapien Vault Shares", "vSAPIEN");
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();

        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);
        _grantRole(PAUSER_ROLE, _defaultAdmin);

        // Inflation attack protection: mint small amount of shares to dead address
        // This anchors the share price even if assets are small.
        // Note: This requires the first depositor to provide assets to back these shares,
        // or for the admin to fund the vault.
        _mint(address(0xdead), 1000);
    }

    /**
     * @dev Inflation attack protection (standard for ERC4626)
     */
    function _decimalsOffset() internal pure virtual override returns (uint8) {
        return 3;
    }

    // ============================================
    // STAKE LOCKING FUNCTIONS
    // ============================================

    /**
     * @notice Lock a user's stake to prevent withdrawals/transfers
     * @dev Can only be called by addresses with LOCKER_ROLE (e.g., ProjectRegistry)
     * @param user The user whose stake to lock
     * @param amount The amount to lock
     * @param reason The reason for locking (for event tracking)
     */
    function lockStake(address user, uint256 amount, string calldata reason)
        external
        onlyRole(LOCKER_ROLE)
        whenNotPaused
    {
        if (amount == 0) revert ZeroAmount();

        uint256 currentStake = convertToAssets(balanceOf(user));
        uint256 availableStake = currentStake - lockedStake[user];

        if (amount > availableStake) {
            revert InsufficientUnlockedStake(user, amount, availableStake);
        }

        lockedStake[user] += amount;
        emit StakeLocked(user, amount, msg.sender, reason);
    }

    /**
     * @notice Unlock a user's stake
     * @dev Can only be called by addresses with LOCKER_ROLE
     * @param user The user whose stake to unlock
     * @param amount The amount to unlock
     * @param reason The reason for unlocking (for event tracking)
     */
    function unlockStake(address user, uint256 amount, string calldata reason) external onlyRole(LOCKER_ROLE) {
        if (amount == 0) revert ZeroAmount();

        if (lockedStake[user] < amount) {
            revert InsufficientLockedStake(user, amount, lockedStake[user]);
        }

        lockedStake[user] -= amount;
        emit StakeUnlocked(user, amount, msg.sender, reason);
    }

    /**
     * @notice Get the amount of stake available for withdrawal/transfer
     * @param user The user to check
     * @return The available (unlocked) stake amount
     */
    function getAvailableStake(address user) external view returns (uint256) {
        uint256 totalStake = convertToAssets(balanceOf(user));
        return totalStake > lockedStake[user] ? totalStake - lockedStake[user] : 0;
    }

    /**
     * @notice Get the amount of locked stake for a user
     * @param user The user to check
     * @return The locked stake amount
     */
    function getLockedStake(address user) external view returns (uint256) {
        return lockedStake[user];
    }

    // ============================================
    // PAUSE FUNCTIONS
    // ============================================

    /**
     * @notice Pause the vault (emergency use)
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the vault
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    // ============================================
    // SLASHING FUNCTIONS
    // ============================================

    /**
     * @notice Slash a user's position by burning their shares
     * @dev The underlying assets remain in vault, increasing share value for remaining holders
     *      This redistributes the slashed value to all other stakers proportionally
     * @param user The user to slash
     * @param assetAmount The amount of assets to slash (will be converted to shares)
     * @param projectId The project identifier (bytes32 hash of IPFS CID) for tracking purposes
     * @return actualAssetsSlashed The actual amount of assets slashed (capped at user's balance)
     */
    function slash(address user, uint256 assetAmount, bytes32 projectId)
        external
        onlyRole(SLASHER_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint256 actualAssetsSlashed)
    {
        uint256 userShares = balanceOf(user);
        if (userShares == 0) return 0; // No-op if user has no shares to slash

        uint256 userAssets = convertToAssets(userShares);
        actualAssetsSlashed = assetAmount > userAssets ? userAssets : assetAmount;

        if (actualAssetsSlashed == 0) return 0;

        uint256 sharesToSlash = convertToShares(actualAssetsSlashed);
        if (sharesToSlash > userShares) {
            sharesToSlash = userShares;
        }

        _burn(user, sharesToSlash);

        // Adjust locked stake if it exceeds new balance after slashing
        uint256 newBalance = convertToAssets(balanceOf(user));
        if (lockedStake[user] > newBalance) {
            lockedStake[user] = newBalance;
        }

        emit Slashed(user, sharesToSlash, actualAssetsSlashed, msg.sender, projectId);
    }

    // ============================================
    // INTERNAL HELPER FUNCTIONS
    // ============================================

    /**
     * @notice Internal function to check if user has sufficient unlocked stake
     * @dev Reverts if user is trying to move more than their available (unlocked) stake
     * @param user The user address to check
     * @param amount The amount being transferred/withdrawn
     */
    function _checkUnlockedStake(address user, uint256 amount) internal view {
        uint256 totalStake = convertToAssets(balanceOf(user));
        uint256 availableStake = totalStake > lockedStake[user] ? totalStake - lockedStake[user] : 0;

        if (amount > availableStake) {
            revert InsufficientUnlockedStake(user, amount, availableStake);
        }
    }

    /**
     * @notice Get the staked balance of a user in terms of underlying assets
     * @param user The user address
     * @return The amount of underlying assets the user can redeem
     */
    function getStake(address user) external view returns (uint256) {
        return convertToAssets(balanceOf(user));
    }

    /**
     * @notice Returns the total staked amount
     * @dev Includes slashed tokens that increase share value for remaining holders
     * @return Total staked assets in the vault
     */
    function totalStaked() external view returns (uint256) {
        return totalAssets();
    }

    /**
     * @notice Override totalAssets to return actual vault balance
     * @dev Slashed tokens remain in vault and increase share value for remaining holders
     * @return Total assets held by the vault (including value from slashed shares)
     */
    function totalAssets() public view virtual override returns (uint256) {
        return IERC20(asset()).balanceOf(address(this));
    }

    // ============================================
    // OVERRIDE ERC-4626 FUNCTIONS WITH RESTRICTIONS
    // ============================================

    /**
     * @notice Override deposit to prevent deposits during emergency pause
     * @dev Opus 4.6 L-4 fix: Without this, users can deposit during pause but cannot
     *      withdraw, trapping their tokens until the vault is unpaused.
     */
    function deposit(uint256 assets, address receiver) public virtual override whenNotPaused returns (uint256) {
        return super.deposit(assets, receiver);
    }

    /**
     * @notice Override mint to prevent mints during emergency pause
     * @dev Opus 4.6 L-4 fix: Share-denominated counterpart to deposit().
     */
    function mint(uint256 shares, address receiver) public virtual override whenNotPaused returns (uint256) {
        return super.mint(shares, receiver);
    }

    /**
     * @notice Override transfer to prevent transfers beyond unlocked stake
     * @dev Reverts if sender is trying to transfer locked stake
     */
    function transfer(address to, uint256 amount)
        public
        virtual
        override(ERC20Upgradeable, IERC20)
        whenNotPaused
        returns (bool)
    {
        uint256 assetAmount = _convertToAssets(amount, Math.Rounding.Ceil);
        _checkUnlockedStake(msg.sender, assetAmount);
        return super.transfer(to, amount);
    }

    /**
     * @notice Override transferFrom to prevent transfers beyond unlocked stake
     * @dev Reverts if from address is trying to transfer locked stake
     */
    function transferFrom(address from, address to, uint256 amount)
        public
        virtual
        override(ERC20Upgradeable, IERC20)
        whenNotPaused
        returns (bool)
    {
        uint256 assetAmount = _convertToAssets(amount, Math.Rounding.Ceil);
        _checkUnlockedStake(from, assetAmount);
        return super.transferFrom(from, to, amount);
    }

    /**
     * @notice Override withdraw to prevent withdrawals beyond unlocked stake
     * @dev Reverts if owner is trying to withdraw locked stake
     * @param owner The account owner
     */
    function withdraw(uint256 assets, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        _checkUnlockedStake(owner, assets);
        return super.withdraw(assets, receiver, owner);
    }

    /**
     * @notice Override redeem to prevent redemptions beyond unlocked stake
     * @dev Reverts if owner is trying to redeem locked stake
     * @param owner The account owner
     */
    function redeem(uint256 shares, address receiver, address owner)
        public
        virtual
        override
        whenNotPaused
        returns (uint256)
    {
        uint256 assets = _convertToAssets(shares, Math.Rounding.Ceil);
        _checkUnlockedStake(owner, assets);
        return super.redeem(shares, receiver, owner);
    }

    /**
     * @notice Returns the staking token address
     * @return The underlying asset address
     */
    function stakingToken() external view returns (IERC20) {
        return IERC20(asset());
    }
}
