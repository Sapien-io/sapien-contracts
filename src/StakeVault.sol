// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IStakeVault} from "src/interfaces/IStakeVault.sol";
import {StakeAccount} from "src/Types.sol";

/// @title StakeVault
/// @notice ERC-4626 vault for SAPIEN token staking with typed lock categories
/// @dev Deployed behind an ERC-1967 proxy. Holds user funds and implements contributor locks,
///      validator capacity, in-flight stake tracking, and share-burn slashing.
contract StakeVault is ERC4626Upgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable, IStakeVault {
    using SafeERC20 for IERC20;

    // ── Roles ──────────────────────────────────────────────────────────
    bytes32 public constant ENGINE_ROLE = keccak256("ENGINE_ROLE");

    // ── Errors ─────────────────────────────────────────────────────────
    error InsufficientAvailableBalance(uint256 required, uint256 available);
    error InsufficientContributorLock(uint256 required, uint256 locked);
    error InsufficientValidatorCapacity(uint256 required, uint256 capacity);
    error InsufficientInFlight(uint256 required, uint256 inFlight);
    error TransferExceedsUnlockedShares();
    error ZeroAmount();
    error ZeroAddress();

    // ── Events ─────────────────────────────────────────────────────────
    event ContributorLocked(address indexed user, uint256 amount);
    event ContributorUnlocked(address indexed user, uint256 amount);
    event ContributorSlashed(address indexed user, uint256 amount);
    event ValidatorCapacityLocked(address indexed user, uint256 amount);
    event ValidatorCapacityUnlocked(address indexed user, uint256 amount);
    event StakeCommitted(address indexed user, uint256 amount);
    event CommitReleased(address indexed user, uint256 amount);
    event ValidatorSlashed(address indexed user, uint256 amount);

    // ── Storage (ERC-7201 namespaced) ──────────────────────────────────
    /// @custom:storage-location erc7201:sapien.storage.StakeVault
    struct StakeVaultStorage {
        mapping(address => StakeAccount) accounts;
    }

    // keccak256(abi.encode(uint256(keccak256("sapien.storage.StakeVault")) - 1)) & ~bytes32(uint256(0xff))
    function _getStakeVaultStorage() private pure returns (StakeVaultStorage storage $) {
        assembly {
            $.slot := 0x0745d816f844b8d3ebe69904ebcd305a06dedec42070def1e397b29c2e74a900
        }
    }

    /// @notice Verify ERC-7201 storage location derivation
    function verifyStorageLocation() external pure returns (bool) {
        bytes32 expected;
        assembly {
            // Compute keccak256("sapien.storage.StakeVault")
            let namespaceHash := keccak256("sapien.storage.StakeVault", 30)
            // Compute keccak256(abi.encode(uint256(namespaceHash) - 1))
            mstore(0x00, sub(namespaceHash, 1))
            expected := keccak256(0x00, 32)
            // Apply & ~bytes32(uint256(0xff))
            expected := and(expected, not(0xff))
        }
        return expected == bytes32(uint256(0x0745d816f844b8d3ebe69904ebcd305a06dedec42070def1e397b29c2e74a900));
    }

    // ── Initializer ────────────────────────────────────────────────────
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 asset_, address admin_) external initializer {
        if (admin_ == address(0)) revert ZeroAddress();
        __ERC4626_init(asset_);
        __ERC20_init("Sapien Vault Token", "vSAPIEN");
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    // ── ERC-4626 inflation attack mitigation ───────────────────────────
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    // ── Contributor stake operations ───────────────────────────────────

    /// @inheritdoc IStakeVault
    function lockContributor(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        uint256 avail = availableBalance(user);
        if (avail < amount) revert InsufficientAvailableBalance(amount, avail);

        _getStakeVaultStorage().accounts[user].contributorLock += amount;
        emit ContributorLocked(user, amount);
    }

    /// @inheritdoc IStakeVault
    function unlockContributor(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getStakeVaultStorage().accounts[user];
        if (acct.contributorLock < amount) revert InsufficientContributorLock(amount, acct.contributorLock);

        acct.contributorLock -= amount;
        emit ContributorUnlocked(user, amount);
    }

    /// @inheritdoc IStakeVault
    function slashContributor(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getStakeVaultStorage().accounts[user];
        if (acct.contributorLock < amount) revert InsufficientContributorLock(amount, acct.contributorLock);

        acct.contributorLock -= amount;
        _burnShares(user, amount);
        emit ContributorSlashed(user, amount);
    }

    // ── Validator capacity operations ──────────────────────────────────

    /// @inheritdoc IStakeVault
    function lockValidatorCapacity(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        uint256 avail = availableBalance(user);
        if (avail < amount) revert InsufficientAvailableBalance(amount, avail);

        _getStakeVaultStorage().accounts[user].validatorCapacity += amount;
        emit ValidatorCapacityLocked(user, amount);
    }

    /// @inheritdoc IStakeVault
    function unlockValidatorCapacity(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getStakeVaultStorage().accounts[user];
        if (acct.validatorCapacity < amount) revert InsufficientValidatorCapacity(amount, acct.validatorCapacity);

        acct.validatorCapacity -= amount;
        emit ValidatorCapacityUnlocked(user, amount);
    }

    // ── Validator in-flight operations ─────────────────────────────────

    /// @inheritdoc IStakeVault
    function commitStake(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getStakeVaultStorage().accounts[user];
        if (acct.validatorCapacity < amount) revert InsufficientValidatorCapacity(amount, acct.validatorCapacity);

        acct.validatorCapacity -= amount;
        acct.inFlight += amount;
        emit StakeCommitted(user, amount);
    }

    /// @inheritdoc IStakeVault
    function releaseCommit(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getStakeVaultStorage().accounts[user];
        if (acct.inFlight < amount) revert InsufficientInFlight(amount, acct.inFlight);

        acct.inFlight -= amount;
        acct.validatorCapacity += amount;
        emit CommitReleased(user, amount);
    }

    /// @inheritdoc IStakeVault
    function slashValidator(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getStakeVaultStorage().accounts[user];
        if (acct.inFlight < amount) revert InsufficientInFlight(amount, acct.inFlight);

        acct.inFlight -= amount;
        _burnShares(user, amount);
        emit ValidatorSlashed(user, amount);
    }

    // ── Batch operations ──────────────────────────────────────────────

    /// @inheritdoc IStakeVault
    function slashAndUnlockContributor(address user, uint256 slashAmount, uint256 unlockAmount)
        external
        onlyRole(ENGINE_ROLE)
    {
        StakeAccount storage acct = _getStakeVaultStorage().accounts[user];
        uint256 totalDeduction = slashAmount + unlockAmount;
        if (acct.contributorLock < totalDeduction) {
            revert InsufficientContributorLock(totalDeduction, acct.contributorLock);
        }
        acct.contributorLock -= totalDeduction;
        if (slashAmount > 0) {
            _burnShares(user, slashAmount);
            emit ContributorSlashed(user, slashAmount);
        }
        if (unlockAmount > 0) {
            emit ContributorUnlocked(user, unlockAmount);
        }
    }

    // ── Views ──────────────────────────────────────────────────────────

    /// @inheritdoc IStakeVault
    function getStakeAccount(address user) external view returns (StakeAccount memory) {
        return _getStakeVaultStorage().accounts[user];
    }

    /// @inheritdoc IStakeVault
    function availableBalance(address user) public view returns (uint256) {
        StakeAccount storage acct = _getStakeVaultStorage().accounts[user];
        uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
        uint256 totalAssets_ = convertToAssets(balanceOf(user));
        return totalAssets_ > totalLocked ? totalAssets_ - totalLocked : 0;
    }

    /// @inheritdoc IStakeVault
    function totalStaked(address user) external view returns (uint256) {
        return convertToAssets(balanceOf(user));
    }

    // ── Withdrawal guard ───────────────────────────────────────────────
    /// @dev Override maxRedeem to limit withdrawals to unlocked balance.
    ///      OZ's maxWithdraw calls maxRedeem, so we only need to override maxRedeem.
    function maxRedeem(address owner) public view override returns (uint256) {
        uint256 avail = availableBalance(owner);
        uint256 availShares = convertToShares(avail);
        uint256 parentMax = super.maxRedeem(owner); // balanceOf(owner)
        return availShares < parentMax ? availShares : parentMax;
    }

    // ── Transfer guard ─────────────────────────────────────

    /// @dev Prevent share transfers that would leave sender below their locked amount.
    ///      Mints (from == 0) and burns (to == 0) are unrestricted.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            StakeAccount storage acct = _getStakeVaultStorage().accounts[from];
            uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
            uint256 lockedShares = convertToShares(totalLocked);
            if (balanceOf(from) - value < lockedShares) revert TransferExceedsUnlockedShares();
        }
        super._update(from, to, value);
    }

    // ── Internal ───────────────────────────────────────────────────────

    /// @dev Burn shares equivalent to `assetAmount` for slashing
    function _burnShares(address user, uint256 assetAmount) internal {
        uint256 shares = convertToShares(assetAmount);
        if (shares > 0) {
            _burn(user, shares);
        }
    }

    // ── Pausable hooks ─────────────────────────────────────────────────

    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ── UUPS ───────────────────────────────────────────────────────────

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
