// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    ERC4626Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    AccessControlUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/AccessControlUpgradeable.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {SapienVaultStorage, StakeAccount} from "src/Types.sol";

/// @title SapienVault
/// @notice ERC-4626 vault for SAPIEN token staking with lock and slashing
/// @dev Deployed behind an ERC-1967 proxy. Holds user funds and implements
///      stake locking and share-burn slashing.
contract SapienVault is
    ERC4626Upgradeable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ISapienVault
{
    // ── Roles ──────────────────────────────────────────────────────────

    /// @notice Role permitted to call `unlockStake` and `slashStake`.
    bytes32 public constant ENGINE_ROLE = keccak256("ENGINE_ROLE");

    /// @notice Upper bound (in seconds) on the configurable `minDepositAge` MEV guard.
    uint256 public constant MAX_MIN_DEPOSIT_AGE = 7 days;

    /// @notice Returns the ERC-7201 namespaced storage struct for SapienVault.
    /// @return s Reference to the namespaced `SapienVaultStorage` struct.
    function _getSapienVaultStorage() private pure returns (SapienVaultStorage storage s) {
        assembly {
            s.slot := 0x4d6e6410717d1c28e2e2dce6e8ac53def1f84cd7244221b7a072c02c51460000
        }
    }

    /// @inheritdoc ISapienVault
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

    /// @notice Initialize the vault proxy instance.
    /// @param asset_ ERC-20 asset token accepted by this ERC-4626 vault.
    /// @param admin_ Address granted DEFAULT_ADMIN_ROLE.
    function initialize(IERC20 asset_, address admin_) external initializer {
        if (address(asset_) == address(0)) revert ZeroAddress();
        if (admin_ == address(0)) revert ZeroAddress();
        __ERC4626_init(asset_);
        __ERC20_init("Sapien PoQ Vault", "vSAPIEN");
        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        // SEC-L-04: assert the role grant succeeded; on a fresh initializer this
        // is always true, but we no longer silently discard the return value.
        assert(_grantRole(DEFAULT_ADMIN_ROLE, admin_));
    }

    // ── ERC-4626 inflation attack mitigation ───────────────────────────
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    // ── Deposit timestamp tracking ──────────────────────────────────────

    /// @dev Internal helper to check if the user's latest inbound transfer/deposit
    ///      has satisfied the minimum age. This prevents flash-loans and MEV.
    function _hasMetDepositAge(address user) internal view returns (bool) {
        uint256 minAge = _getSapienVaultStorage().minDepositAge;
        if (minAge == 0) return true;
        uint256 depositTs = _getSapienVaultStorage().lastDepositTimestamp[user];
        if (depositTs == 0) return true;
        return (block.timestamp - depositTs) >= minAge;
    }

    /// @dev Reverts if the user's latest inbound transfer/deposit has not
    ///      satisfied the minimum age requirement.
    function _requireDepositAgeMet(address user) internal view {
        uint256 minAge = _getSapienVaultStorage().minDepositAge;
        if (minAge > 0) {
            uint256 depositTs = _getSapienVaultStorage().lastDepositTimestamp[user];
            if (depositTs > 0) {
                uint256 age = block.timestamp - depositTs;
                if (age < minAge) revert DepositTooRecent(minAge, age);
            }
        }
    }

    /// @dev Tracks the timestamp of a self-deposit, resetting the MEV time-lock.
    ///      Deposits made on behalf of another address (caller != receiver) do
    ///      NOT update the receiver's timestamp — otherwise an attacker could
    ///      grief any user by dust-depositing to their address every
    ///      `minDepositAge` seconds and freezing their lock/transfer/withdraw
    ///      flows (SEC-M-01). Third-party-funded shares still arrive at the
    ///      receiver and remain subject to whatever timer the receiver already
    ///      has from their own prior deposits or inbound transfers.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (caller == receiver) {
            _getSapienVaultStorage().lastDepositTimestamp[receiver] = block.timestamp;
        }
        super._deposit(caller, receiver, assets, shares);
    }

    // ── Stake operations ────────────────────────────────────────────────

    /// @inheritdoc ISapienVault
    function lockStake(uint256 amount) external whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        address user = msg.sender;
        SapienVaultStorage storage $ = _getSapienVaultStorage();

        _requireDepositAgeMet(user);

        uint256 avail = availableBalance(user);
        if (avail < amount) revert InsufficientAvailableBalance(amount, avail);

        $.accounts[user].lockedAmount += amount;
        emit StakeLocked(user, amount);
    }

    /// @inheritdoc ISapienVault
    function unlockStake(address user, uint256 amount) external onlyRole(ENGINE_ROLE) whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        if (acct.lockedAmount < amount) revert InsufficientLockedAmount(amount, acct.lockedAmount);

        acct.lockedAmount -= amount;
        emit StakeUnlocked(user, amount);
    }

    /// @inheritdoc ISapienVault
    function slashStake(address user, uint256 amount) external onlyRole(ENGINE_ROLE) whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        if (acct.lockedAmount < amount) revert InsufficientLockedAmount(amount, acct.lockedAmount);

        acct.lockedAmount -= amount;
        _burnShares(user, amount);
        emit StakeSlashed(user, amount);
    }

    // ── Views ──────────────────────────────────────────────────────────

    /// @inheritdoc ISapienVault
    function getStakeAccount(address user) external view returns (StakeAccount memory) {
        return _getSapienVaultStorage().accounts[user];
    }

    /// @inheritdoc ISapienVault
    function availableBalance(address user) public view returns (uint256) {
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        uint256 totalLocked = acct.lockedAmount;
        uint256 totalAssets_ = convertToAssets(balanceOf(user));
        return totalAssets_ > totalLocked ? totalAssets_ - totalLocked : 0;
    }

    /// @inheritdoc ISapienVault
    function getUserStakeBalance(address user) external view returns (uint256) {
        return convertToAssets(balanceOf(user));
    }

    // ── Withdrawal guard ───────────────────────────────────────────────

    /// @notice Maximum shares that `owner` can redeem at the current block.
    /// @dev Overrides ERC4626Upgradeable to limit redemptions to unlocked balance
    ///      and enforce the MEV-protection time-lock (minDepositAge). Returns 0
    ///      while paused or while the owner is still inside their deposit-age
    ///      window. Uses previewWithdraw (rounds up) to reserve shares for the
    ///      locked amount so that a subsequent withdraw/redeem never
    ///      undercollateralises the lock.
    /// @param owner Address whose redeemable shares are being queried.
    /// @return Maximum number of shares redeemable by `owner`.
    function maxRedeem(address owner) public view override returns (uint256) {
        if (paused() || !_hasMetDepositAge(owner)) return 0;
        uint256 lockedAmt = _getSapienVaultStorage().accounts[owner].lockedAmount;
        uint256 shares = balanceOf(owner);
        uint256 lockedShares = lockedAmt > 0 ? previewWithdraw(lockedAmt) : 0;
        uint256 availShares = shares > lockedShares ? shares - lockedShares : 0;
        uint256 parentMax = super.maxRedeem(owner);
        return availShares < parentMax ? availShares : parentMax;
    }

    /// @notice Maximum assets that `owner` can withdraw at the current block.
    /// @dev Overrides ERC4626Upgradeable; OZ's default does NOT delegate to
    ///      maxRedeem. Computes available shares after reserving enough (rounded
    ///      up via previewWithdraw) for the locked amount, then converts to
    ///      assets. This avoids the rounding mismatch where availableBalance's
    ///      floor asset surplus could cause withdraw() to burn more shares than
    ///      safe. Returns 0 while paused or before the deposit-age timer has
    ///      elapsed.
    /// @param owner Address whose withdrawable assets are being queried.
    /// @return Maximum amount of assets withdrawable by `owner`.
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (paused() || !_hasMetDepositAge(owner)) return 0;
        uint256 lockedAmt = _getSapienVaultStorage().accounts[owner].lockedAmount;
        uint256 shares = balanceOf(owner);
        uint256 lockedShares = lockedAmt > 0 ? previewWithdraw(lockedAmt) : 0;
        uint256 availShares = shares > lockedShares ? shares - lockedShares : 0;
        uint256 maxAssets = convertToAssets(availShares);
        uint256 parentMax = super.maxWithdraw(owner);
        return maxAssets < parentMax ? maxAssets : parentMax;
    }

    /// @notice Maximum assets that may be deposited into the vault.
    /// @dev Returns 0 while paused; otherwise unbounded (subject to caller's
    ///      asset balance and approval). The receiver argument is unused.
    /// @param receiver Account credited with the deposited shares (unused).
    /// @return Maximum depositable asset amount.
    function maxDeposit(address receiver) public view override returns (uint256) {
        receiver;
        return paused() ? 0 : type(uint256).max;
    }

    /// @notice Maximum shares that may be minted from the vault.
    /// @dev Returns 0 while paused; otherwise unbounded (subject to caller's
    ///      asset balance and approval). The receiver argument is unused.
    /// @param receiver Account credited with the minted shares (unused).
    /// @return Maximum mintable share amount.
    function maxMint(address receiver) public view override returns (uint256) {
        receiver;
        return paused() ? 0 : type(uint256).max;
    }

    // ── Transfer guard ─────────────────────────────────────

    /// @dev For wallet-to-wallet transfers, enforce pause state, ensure the
    ///      sender keeps enough shares to cover locked stake, and enforce the
    ///      MEV-protection time-lock (sender must have met minDepositAge).
    ///      Sets the receiver's deposit timestamp on receipt to prevent bypassing
    ///      minDepositAge via share transfers (note: this allows inbound griefing).
    ///      Mints (from == 0) and burns (to == 0) are unrestricted.
    ///      Uses previewWithdraw (rounds up) to reserve shares for the locked
    ///      amount so that transfers never undercollateralise the lock.
    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            _requireNotPaused();

            // MEV / front-running protection: enforce time-lock on all share transfers
            _requireDepositAgeMet(from);

            SapienVaultStorage storage $ = _getSapienVaultStorage();
            StakeAccount storage acct = $.accounts[from];
            uint256 totalLocked = acct.lockedAmount;
            uint256 lockedShares = totalLocked > 0 ? previewWithdraw(totalLocked) : 0;
            if (balanceOf(from) < value + lockedShares) revert TransferExceedsUnlockedShares();

            // Set deposit timestamp for any recipient to prevent bypassing
            // minDepositAge via share transfers. Note this opens a known
            // griefing vector where an attacker can reset a staker's timer,
            // but this is preferred over allowing instant lock bypass.
            if (value > 0) {
                $.lastDepositTimestamp[to] = block.timestamp;
            }
        }
        super._update(from, to, value);
    }

    // ── Internal ───────────────────────────────────────────────────────

    /// @dev Burn shares equivalent to `assetAmount` for slashing.
    ///      Uses previewWithdraw (rounds up) so the penalty is never
    ///      smaller than intended, and reverts when rounding yields 0 shares.
    function _burnShares(address user, uint256 assetAmount) internal {
        uint256 shares = previewWithdraw(assetAmount);
        if (shares == 0) revert ZeroShareSlash();
        _burn(user, shares);
    }

    // ── Admin ──────────────────────────────────────────────────────────

    /// @inheritdoc ISapienVault
    function setMinDepositAge(uint256 age) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (age > MAX_MIN_DEPOSIT_AGE) revert MinDepositAgeTooHigh(age, MAX_MIN_DEPOSIT_AGE);
        _getSapienVaultStorage().minDepositAge = age;
        emit MinDepositAgeUpdated(age);
    }

    /// @inheritdoc ISapienVault
    function minDepositAge() external view returns (uint256) {
        return _getSapienVaultStorage().minDepositAge;
    }

    // ── Pausable hooks ─────────────────────────────────────────────────

    /// @inheritdoc ISapienVault
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /// @inheritdoc ISapienVault
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    // ── ETH rescue ─────────────────────────────────────────────────────

    /// @inheritdoc ISapienVault
    /// @dev Resolves the "locked-ETH" detector: although the vault's asset is ERC-20,
    ///      OZ's `upgradeToAndCall(address,bytes)` is payable, so an admin upgrade
    ///      with non-zero `msg.value` could leave ETH stuck on the proxy. This
    ///      function is the recovery path. Admin-only, full balance, low-level call.
    ///      `nonReentrant` is defense-in-depth — there are no post-call state
    ///      writes, but the recipient is admin-chosen and unconstrained
    ///      (SEC-L-03). The event is emitted before the external call to keep
    ///      strict checks-effects-interactions ordering.
    function rescueETH(address payable to) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        if (to == address(0)) revert ZeroAddress();
        uint256 amount = address(this).balance;
        if (amount == 0) revert ZeroAmount();
        emit EthRescued(to, amount);
        (bool ok,) = to.call{value: amount}("");
        if (!ok) revert EthTransferFailed();
    }

    // ── UUPS ───────────────────────────────────────────────────────────

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
