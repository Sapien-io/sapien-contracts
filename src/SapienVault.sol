// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {SapienVaultStorage, StakeAccount} from "src/Types.sol";

/// @title SapienVault
/// @notice ERC-4626 vault for SAPIEN token staking with typed lock categories
/// @dev Deployed behind an ERC-1967 proxy. Holds user funds and implements contributor locks,
///      validator capacity, in-flight stake tracking, and share-burn slashing.
contract SapienVault is
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ISapienVault
{
    using SafeERC20 for IERC20;

    // ── Roles ──────────────────────────────────────────────────────────
    bytes32 public constant ENGINE_ROLE = keccak256("ENGINE_ROLE");

    uint256 public constant MAX_MIN_DEPOSIT_AGE = 7 days;

    function _getSapienVaultStorage() private pure returns (SapienVaultStorage storage $) {
        assembly {
            $.slot := 0x4d6e6410717d1c28e2e2dce6e8ac53def1f84cd7244221b7a072c02c51460000
        }
    }

    /// @notice Verify ERC-7201 storage location derivation
    function verifyStorageLocation() external pure returns (bool) {
        // SEC-M-06: Use Solidity-level keccak256 instead of inline assembly
        // to avoid incorrect string length issues (was 30 instead of 25)
        // keccak256(abi.encode(uint256(keccak256("sapien.storage.SapienCore")) - 1)) & ~bytes32(uint256(0xff))
        // solhint-disable-next-line solidity-formatting
        bytes32 namespaceHash = keccak256("sapien.storage.SapienVault");
        bytes32 derived = keccak256(abi.encode(uint256(namespaceHash) - 1));
        bytes32 expected = derived & ~bytes32(uint256(0xff));
        return expected == bytes32(uint256(0x4d6e6410717d1c28e2e2dce6e8ac53def1f84cd7244221b7a072c02c51460000));
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

    // ── Deposit timestamp tracking ──────────────────────────────────────

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        _getSapienVaultStorage().lastDepositTimestamp[receiver] = block.timestamp;
        super._deposit(caller, receiver, assets, shares);
    }

    // ── Contributor stake operations ───────────────────────────────────

    /// @inheritdoc ISapienVault
    function lockContributor(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        uint256 avail = availableBalance(user);
        if (avail < amount) revert InsufficientAvailableBalance(amount, avail);

        _getSapienVaultStorage().accounts[user].contributorLock += amount;
        emit ContributorLocked(user, amount);
    }

    /// @inheritdoc ISapienVault
    function unlockContributor(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        if (acct.contributorLock < amount) revert InsufficientContributorLock(amount, acct.contributorLock);

        acct.contributorLock -= amount;
        emit ContributorUnlocked(user, amount);
    }

    /// @inheritdoc ISapienVault
    function slashContributor(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        if (acct.contributorLock < amount) revert InsufficientContributorLock(amount, acct.contributorLock);

        acct.contributorLock -= amount;
        _burnShares(user, amount);
        emit ContributorSlashed(user, amount);
    }

    // ── Validator capacity operations ──────────────────────────────────

    /// @inheritdoc ISapienVault
    function lockValidatorCapacity(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        SapienVaultStorage storage $ = _getSapienVaultStorage();
        uint256 minAge = $.minDepositAge;
        if (minAge > 0) {
            uint256 depositTs = $.lastDepositTimestamp[user];
            if (depositTs > 0) {
                uint256 age = block.timestamp - depositTs;
                if (age < minAge) revert DepositTooRecent(minAge, age);
            }
        }
        uint256 avail = availableBalance(user);
        if (avail < amount) revert InsufficientAvailableBalance(amount, avail);

        $.accounts[user].validatorCapacity += amount;
        emit ValidatorCapacityLocked(user, amount);
    }

    /// @inheritdoc ISapienVault
    function unlockValidatorCapacity(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        if (acct.validatorCapacity < amount) revert InsufficientValidatorCapacity(amount, acct.validatorCapacity);

        acct.validatorCapacity -= amount;
        emit ValidatorCapacityUnlocked(user, amount);
    }

    // ── Validator in-flight operations ─────────────────────────────────

    /// @inheritdoc ISapienVault
    function commitStake(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        if (acct.validatorCapacity < amount) revert InsufficientValidatorCapacity(amount, acct.validatorCapacity);

        acct.validatorCapacity -= amount;
        acct.inFlight += amount;
        emit StakeCommitted(user, amount);
    }

    /// @inheritdoc ISapienVault
    function releaseCommit(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        if (acct.inFlight < amount) revert InsufficientInFlight(amount, acct.inFlight);

        acct.inFlight -= amount;
        acct.validatorCapacity += amount;
        emit CommitReleased(user, amount);
    }

    /// @inheritdoc ISapienVault
    function slashValidator(address user, uint256 amount) external onlyRole(ENGINE_ROLE) {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        if (acct.inFlight < amount) revert InsufficientInFlight(amount, acct.inFlight);

        acct.inFlight -= amount;
        _burnShares(user, amount);
        emit ValidatorSlashed(user, amount);
    }

    // ── Batch operations ──────────────────────────────────────────────

    /// @inheritdoc ISapienVault
    function slashAndUnlockContributor(address user, uint256 slashAmount, uint256 unlockAmount)
        external
        onlyRole(ENGINE_ROLE)
    {
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
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

    /// @inheritdoc ISapienVault
    function getStakeAccount(address user) external view returns (StakeAccount memory) {
        return _getSapienVaultStorage().accounts[user];
    }

    /// @inheritdoc ISapienVault
    function availableBalance(address user) public view returns (uint256) {
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
        uint256 totalAssets_ = convertToAssets(balanceOf(user));
        return totalAssets_ > totalLocked ? totalAssets_ - totalLocked : 0;
    }

    /// @inheritdoc ISapienVault
    function totalStaked(address user) external view returns (uint256) {
        return convertToAssets(balanceOf(user));
    }

    // ── Withdrawal guard ───────────────────────────────────────────────
    /// @dev Override maxRedeem to limit withdrawals to unlocked balance.
    function maxRedeem(address owner) public view override returns (uint256) {
        if (paused()) return 0; // SEC-M-01: block redemptions when paused
        uint256 avail = availableBalance(owner);
        uint256 availShares = convertToShares(avail);
        uint256 parentMax = super.maxRedeem(owner); // balanceOf(owner)
        return availShares < parentMax ? availShares : parentMax;
    }

    /// @dev Override maxWithdraw — OZ's default does NOT delegate to maxRedeem.
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (paused()) return 0; // SEC-M-01: block withdrawals when paused
        uint256 avail = availableBalance(owner);
        uint256 parentMax = super.maxWithdraw(owner);
        return avail < parentMax ? avail : parentMax;
    }

    // SEC-M-01: Block ERC4626 deposits/mints when paused
    function maxDeposit(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    function maxMint(address) public view override returns (uint256) {
        return paused() ? 0 : type(uint256).max;
    }

    // ── Transfer guard ─────────────────────────────────────

    /// @dev Prevent share transfers that would leave sender below their locked amount.
    ///      Mints (from == 0) and burns (to == 0) are unrestricted.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            StakeAccount storage acct = _getSapienVaultStorage().accounts[from];
            uint256 totalLocked = acct.contributorLock + acct.validatorCapacity + acct.inFlight;
            uint256 lockedShares = convertToShares(totalLocked);
            if (balanceOf(from) - value < lockedShares) revert TransferExceedsUnlockedShares();
        }
        super._update(from, to, value);
    }

    // ── Internal ───────────────────────────────────────────────────────

    /// @dev Burn shares equivalent to `assetAmount` for slashing.
    ///      Uses previewWithdraw (rounds up) so the slash always covers the full asset penalty.
    function _burnShares(address user, uint256 assetAmount) internal {
        uint256 shares = previewWithdraw(assetAmount);
        if (shares == 0) revert ZeroShareSlash();
        _burn(user, shares);
    }

    // ── Admin ──────────────────────────────────────────────────────────

    function setMinDepositAge(uint256 age) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (age > MAX_MIN_DEPOSIT_AGE) revert MinDepositAgeTooHigh(age, MAX_MIN_DEPOSIT_AGE);
        _getSapienVaultStorage().minDepositAge = age;
        emit MinDepositAgeUpdated(age);
    }

    function minDepositAge() external view returns (uint256) {
        return _getSapienVaultStorage().minDepositAge;
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
