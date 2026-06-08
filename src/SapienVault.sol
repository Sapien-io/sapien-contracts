// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    ERC4626Upgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {
    AccessControlDefaultAdminRulesUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/access/extensions/AccessControlDefaultAdminRulesUpgradeable.sol";
import {PausableUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/PausableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "lib/openzeppelin-contracts-upgradeable/contracts/utils/ReentrancyGuardUpgradeable.sol";
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {SafeCast} from "lib/openzeppelin-contracts/contracts/utils/math/SafeCast.sol";
import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {ISapienVault} from "src/interfaces/ISapienVault.sol";
import {SapienVaultStorage, StakeAccount, Tranche} from "src/Types.sol";

/// @title SapienVault
/// @notice ERC-4626 vault for SAPIEN token staking with lock and slashing
/// @dev Deployed behind an ERC-1967 proxy. Holds user funds and implements
///      stake locking and share-burn slashing.
contract SapienVault is
    ERC4626Upgradeable,
    AccessControlDefaultAdminRulesUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable,
    ISapienVault
{
    using SafeCast for uint256;

    // ── Roles ──────────────────────────────────────────────────────────

    /// @notice Role permitted to call `unlockStake` and `slashStake`.
    bytes32 public constant ENGINE_ROLE = keccak256("ENGINE_ROLE");

    /// @notice Upper bound (in seconds) on the configurable `minDepositAge` MEV guard.
    uint256 public constant MAX_MIN_DEPOSIT_AGE = 7 days;

    /// @notice Initial mandatory delay between scheduling and accepting a
    ///         `DEFAULT_ADMIN_ROLE` transfer (S2). The admin can retune this via
    ///         the inherited `changeDefaultAdminDelay` (itself time-locked).
    uint48 public constant DEFAULT_ADMIN_TRANSFER_DELAY = 3 days;

    /// @notice Default `minDepositAge` seeded at initialization so the flash-deposit
    ///         MEV guard is active out of the box rather than disabled until an
    ///         admin intervenes (SEC/SAP-5). Admin can retune within
    ///         `[0, MAX_MIN_DEPOSIT_AGE]` via `setMinDepositAge`.
    uint256 public constant DEFAULT_MIN_DEPOSIT_AGE = 1 days;

    /// @notice Maximum number of concurrent immature tranches tracked per user.
    /// @dev Bounds the gas of `_settle` so an attacker cannot grief a user by
    ///      spamming dust deposits to their address. When the cap is reached a
    ///      new inflow coalesces into the newest cohort (its clock resets to
    ///      `block.timestamp`), so a griefing deposit can only delay the
    ///      freshest cohort and never the user's older, near-mature shares.
    uint256 internal constant MAX_IMMATURE_TRANCHES = 32;

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
        // S2: install `admin_` as the single `DEFAULT_ADMIN_ROLE` holder under the
        // two-step, time-locked transfer rules. This also records `admin_` as the
        // current default admin (`defaultAdmin()` / `owner()`).
        __AccessControlDefaultAdminRules_init(DEFAULT_ADMIN_TRANSFER_DELAY, admin_);
        __Pausable_init();
        __ReentrancyGuard_init();
        // SAP-5: seed the MEV guard so it is enabled at deployment instead of
        // defaulting to 0 (disabled). Admin can still retune via setMinDepositAge.
        _getSapienVaultStorage().minDepositAge = DEFAULT_MIN_DEPOSIT_AGE;
        emit MinDepositAgeUpdated(0, DEFAULT_MIN_DEPOSIT_AGE);
    }

    /// @notice Reinitializer for the SAP-1 tranche-accounting + S2 role-management
    ///         upgrade from the live (V1, global-timer) implementation.
    /// @dev SAP-1 needs no global seeding: each user's pre-upgrade balance and age
    ///      migrate lazily on their first post-upgrade interaction (`_lazyMigrate`).
    ///
    ///      S2: the live vault granted `DEFAULT_ADMIN_ROLE` through plain
    ///      `AccessControlUpgradeable`, so the `AccessControlDefaultAdminRules`
    ///      storage (`_currentDefaultAdmin`, `_currentDelay`) is unset. Seed it to
    ///      the *existing* admin so `defaultAdmin()` / `owner()` and the single-admin
    ///      invariant are consistent post-upgrade. `currentAdmin_` must already hold
    ///      the role, so this can only bless the incumbent — never grant the role to
    ///      a fresh address via the upgrade calldata.
    /// @param currentAdmin_ The address that currently holds `DEFAULT_ADMIN_ROLE`.
    function initializeV2(address currentAdmin_) external reinitializer(2) {
        if (!hasRole(DEFAULT_ADMIN_ROLE, currentAdmin_)) revert ZeroAddress();
        // Seeds `_currentDelay` and records `currentAdmin_` as the default admin.
        // `defaultAdmin()` is still 0 here (never set under V1), so the inherited
        // `_grantRole` guard passes; the role mapping already has it, so no
        // duplicate `RoleGranted` is emitted.
        __AccessControlDefaultAdminRules_init(DEFAULT_ADMIN_TRANSFER_DELAY, currentAdmin_);

        // SAP-5: enable the MEV guard on upgrade if it was never configured on
        // the live (pre-upgrade) vault. Guarded on `== 0` so an admin value set
        // before the upgrade is preserved rather than clobbered.
        SapienVaultStorage storage $ = _getSapienVaultStorage();
        if ($.minDepositAge == 0) {
            $.minDepositAge = DEFAULT_MIN_DEPOSIT_AGE;
            emit MinDepositAgeUpdated(0, DEFAULT_MIN_DEPOSIT_AGE);
        }
    }

    // ── ERC-4626 inflation attack mitigation ───────────────────────────
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    // ── Tranche age accounting (SAP-1) ──────────────────────────────────

    /// @dev Seed a user's tranche state from their pre-upgrade balance the
    ///      first time they are touched after the upgrade. Existing balances
    ///      keep their original age via `lastDepositTimestamp`; a `0` timestamp
    ///      meant "exempt" under the old logic, so it migrates as fully mature.
    ///      Idempotent — runs at most once per address.
    function _lazyMigrate(SapienVaultStorage storage $, address user) private {
        if ($.migrated[user]) return;
        $.migrated[user] = true;
        uint256 bal = balanceOf(user);
        if (bal == 0) return;
        uint256 ts = $.lastDepositTimestamp[user];
        if (ts == 0) {
            $.matureShares[user] = bal;
        } else {
            $.immature[user][0] = Tranche({shares: bal.toUint128(), startTime: uint64(ts)});
            $.immatureTail[user] = 1;
        }
    }

    /// @dev Promote every head cohort that has cleared `minDepositAge` into the
    ///      aggregated `matureShares` bucket and return the resulting mature
    ///      total. Cohorts are pushed in time order, so FIFO popping is correct
    ///      and iteration is bounded by `MAX_IMMATURE_TRANCHES`.
    function _settle(SapienVaultStorage storage $, address user) private returns (uint256) {
        _lazyMigrate($, user);
        uint256 minAge = $.minDepositAge;
        uint256 head = $.immatureHead[user];
        uint256 tail = $.immatureTail[user];
        uint256 mature = $.matureShares[user];
        while (head < tail) {
            Tranche storage t = $.immature[user][head];
            if (minAge != 0 && block.timestamp - t.startTime < minAge) break;
            mature += t.shares;
            delete $.immature[user][head];
            unchecked {
                ++head;
            }
        }
        if (head == tail) {
            // Fully drained: reset pointers so indices stay small.
            head = 0;
            $.immatureTail[user] = 0;
        }
        $.immatureHead[user] = head;
        $.matureShares[user] = mature;
        return mature;
    }

    /// @dev Reverts when an immature cohort would be recorded below `minTrancheSize`.
    ///      Checked on the deposited asset amount so integrators see a stable floor.
    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        SapienVaultStorage storage $ = _getSapienVaultStorage();
        if ($.minDepositAge > 0 && $.minTrancheSize > 0 && assets < $.minTrancheSize) {
            revert BelowMinTrancheSize(assets, $.minTrancheSize);
        }
        super._deposit(caller, receiver, assets, shares);
    }

    /// @dev Record `value` freshly-arrived shares for `user` as a new immature
    ///      cohort. When `minDepositAge` is zero the shares are immediately
    ///      mature. When the per-user tranche cap is reached the shares coalesce
    ///      into the newest cohort and reset its clock (conservative: they can
    ///      only mature later, never earlier), bounding `_settle` gas.
    function _pushImmature(SapienVaultStorage storage $, address user, uint256 value) private {
        if (value == 0) return;
        if ($.minDepositAge == 0) {
            _lazyMigrate($, user);
            $.matureShares[user] += value;
            return;
        }
        _settle($, user);
        uint256 head = $.immatureHead[user];
        uint256 tail = $.immatureTail[user];
        if (tail - head >= MAX_IMMATURE_TRANCHES) {
            Tranche storage newest = $.immature[user][tail - 1];
            newest.shares += value.toUint128();
            newest.startTime = uint64(block.timestamp);
        } else {
            $.immature[user][tail] = Tranche({shares: value.toUint128(), startTime: uint64(block.timestamp)});
            $.immatureTail[user] = tail + 1;
        }
    }

    /// @dev Write-free mirror of migrate+settle for view functions: returns the
    ///      shares that are (or migrate as) mature at the current block.
    function _matureSharesView(address user) internal view returns (uint256) {
        SapienVaultStorage storage $ = _getSapienVaultStorage();
        uint256 minAge = $.minDepositAge;
        if (!$.migrated[user]) {
            uint256 bal = balanceOf(user);
            if (bal == 0) return 0;
            uint256 ts = $.lastDepositTimestamp[user];
            if (ts == 0) return bal;
            return (minAge == 0 || block.timestamp - ts >= minAge) ? bal : 0;
        }
        uint256 head = $.immatureHead[user];
        uint256 tail = $.immatureTail[user];
        uint256 mature = $.matureShares[user];
        while (head < tail) {
            Tranche storage t = $.immature[user][head];
            if (minAge != 0 && block.timestamp - t.startTime < minAge) break;
            mature += t.shares;
            unchecked {
                ++head;
            }
        }
        return mature;
    }

    // ── Stake operations ────────────────────────────────────────────────

    /// @inheritdoc ISapienVault
    function lockStake(uint256 amount) external whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        address user = msg.sender;
        SapienVaultStorage storage $ = _getSapienVaultStorage();

        uint256 mature = _settle($, user);
        uint256 locked = $.accounts[user].lockedAmount;
        uint256 lockedShares = locked > 0 ? previewWithdraw(locked) : 0;
        uint256 availShares = mature > lockedShares ? mature - lockedShares : 0;
        uint256 avail = convertToAssets(availShares);
        if (avail < amount) revert InsufficientAvailableBalance(amount, avail);

        $.accounts[user].lockedAmount = locked + amount;
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
    /// @dev SAP-2: `amount` is the *intended net damage* in asset terms, gated by
    ///      the user's locked stake. Because slashing burns shares without moving
    ///      assets out, the surviving shares (including the user's own) would
    ///      otherwise recapture part of the penalty via the exchange-rate bump.
    ///      `_slashShareAmount` sizes the burn to compensate for that dilution so
    ///      the user's value drops by exactly `amount` (capped at their whole
    ///      stake), and the recaptured value accrues to the *other* stakers.
    function slashStake(address user, uint256 amount) external onlyRole(ENGINE_ROLE) whenNotPaused {
        if (amount == 0) revert ZeroAmount();
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        if (acct.lockedAmount < amount) revert InsufficientLockedAmount(amount, acct.lockedAmount);

        uint256 shares = _slashShareAmount(user, amount);
        if (shares == 0) revert ZeroShareSlash();

        acct.lockedAmount -= amount;
        _burn(user, shares);
        emit StakeSlashed(user, amount);
        emit SharesSlashed(user, shares);
    }

    // ── Views ──────────────────────────────────────────────────────────

    /// @inheritdoc ISapienVault
    function getStakeAccount(address user) external view returns (StakeAccount memory) {
        return _getSapienVaultStorage().accounts[user];
    }

    /// @dev S3: matured shares free of the locked-stake reservation, shared by
    ///      `availableBalance`, `maxWithdraw`, and `maxRedeem` so the
    ///      mature-minus-locked computation lives in one place. Reserves shares
    ///      for the lock with `previewWithdraw` (rounds up) so a subsequent
    ///      withdraw/redeem can never undercollateralise the lock.
    function _availableMatureShares(address owner) internal view returns (uint256) {
        uint256 lockedAmt = _getSapienVaultStorage().accounts[owner].lockedAmount;
        uint256 mature = _matureSharesView(owner);
        uint256 lockedShares = lockedAmt > 0 ? previewWithdraw(lockedAmt) : 0;
        return mature > lockedShares ? mature - lockedShares : 0;
    }

    /// @inheritdoc ISapienVault
    function availableBalance(address user) public view returns (uint256) {
        return convertToAssets(_availableMatureShares(user));
    }

    /// @inheritdoc ISapienVault
    function assetsOf(address user) external view returns (uint256) {
        return convertToAssets(balanceOf(user));
    }

    /// @inheritdoc ISapienVault
    function maturedShares(address user) external view returns (uint256) {
        return _matureSharesView(user);
    }

    /// @inheritdoc ISapienVault
    function pendingShares(address user) external view returns (uint256) {
        SapienVaultStorage storage $ = _getSapienVaultStorage();
        uint256 minAge = $.minDepositAge;
        if (!$.migrated[user]) {
            uint256 ts = $.lastDepositTimestamp[user];
            if (ts == 0) return 0;
            return (minAge == 0 || block.timestamp - ts >= minAge) ? 0 : balanceOf(user);
        }
        uint256 head = $.immatureHead[user];
        uint256 tail = $.immatureTail[user];
        uint256 sum;
        for (uint256 i = head; i < tail; ++i) {
            Tranche storage t = $.immature[user][i];
            if (minAge != 0 && block.timestamp - t.startTime < minAge) {
                sum += t.shares;
            }
        }
        return sum;
    }

    /// @inheritdoc ISapienVault
    function depositAgeStatus(address user)
        external
        view
        returns (uint256 matured, uint256 pending, uint256 minAge, uint256 nextMaturityRemaining)
    {
        SapienVaultStorage storage $ = _getSapienVaultStorage();
        minAge = $.minDepositAge;
        matured = _matureSharesView(user);
        uint256 bal = balanceOf(user);
        pending = bal > matured ? bal - matured : 0;
        if (pending == 0 || minAge == 0) return (matured, pending, minAge, 0);

        // Earliest start time among the still-immature shares. Tranches are pushed
        // in time order, so the first immature cohort is the soonest to mature.
        uint256 earliestStart;
        if (!$.migrated[user]) {
            // Unmigrated holder with pending shares: the legacy timer is non-zero
            // (a `0` timestamp migrates as fully mature, contributing no pending).
            earliestStart = $.lastDepositTimestamp[user];
        } else {
            uint256 head = $.immatureHead[user];
            uint256 tail = $.immatureTail[user];
            for (uint256 i = head; i < tail; ++i) {
                Tranche storage t = $.immature[user][i];
                if (block.timestamp - t.startTime < minAge) {
                    earliestStart = t.startTime;
                    break;
                }
            }
        }
        uint256 maturesAt = earliestStart + minAge;
        nextMaturityRemaining = maturesAt > block.timestamp ? maturesAt - block.timestamp : 0;
    }

    // ── Withdrawal guard ───────────────────────────────────────────────

    /// @notice Maximum shares that `owner` can redeem at the current block.
    /// @dev Overrides ERC4626Upgradeable to limit redemptions to matured,
    ///      unlocked shares. Only shares that have cleared `minDepositAge`
    ///      count, so recently-deposited shares are excluded while already-aged
    ///      shares stay redeemable (SAP-6). Returns 0 while paused. Uses
    ///      previewWithdraw (rounds up) to reserve shares for the locked amount
    ///      so that a subsequent withdraw/redeem never undercollateralises the
    ///      lock.
    /// @param owner Address whose redeemable shares are being queried.
    /// @return Maximum number of shares redeemable by `owner`.
    function maxRedeem(address owner) public view override returns (uint256) {
        if (paused()) return 0;
        uint256 availShares = _availableMatureShares(owner);
        uint256 parentMax = super.maxRedeem(owner);
        return availShares < parentMax ? availShares : parentMax;
    }

    /// @notice Maximum assets that `owner` can withdraw at the current block.
    /// @dev Overrides ERC4626Upgradeable; OZ's default does NOT delegate to
    ///      maxRedeem. Computes available shares from the owner's matured
    ///      balance after reserving enough (rounded up via previewWithdraw) for
    ///      the locked amount, then converts to assets. This avoids the rounding
    ///      mismatch where availableBalance's floor asset surplus could cause
    ///      withdraw() to burn more shares than safe. Returns 0 while paused;
    ///      recently-deposited (immature) shares are not yet withdrawable.
    /// @param owner Address whose withdrawable assets are being queried.
    /// @return Maximum amount of assets withdrawable by `owner`.
    function maxWithdraw(address owner) public view override returns (uint256) {
        if (paused()) return 0;
        uint256 maxAssets = convertToAssets(_availableMatureShares(owner));
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

    // ── Transfer / mint / burn hook ────────────────────────────────────

    /// @dev Routes every balance change through tranche accounting:
    ///      - Mints (`from == 0`, deposit/mint by any caller) record the new
    ///        shares as an immature cohort for the receiver, so freshly-minted
    ///        shares must age before they can be locked/withdrawn/transferred.
    ///        Applying this uniformly closes the delegate-deposit bypass (SAP-3).
    ///      - Burns (`to == 0`, withdraw/redeem/slash) draw from matured shares;
    ///        `maxWithdraw`/`maxRedeem` and the lock reservation guarantee the
    ///        burned amount never exceeds the sender's matured balance.
    ///      - Transfers move only matured, unlocked shares and credit them to
    ///        the recipient as matured ("age travels with the shares"), so a
    ///        dust transfer can no longer reset a victim's global timer (SAP-1).
    ///      Uses previewWithdraw (rounds up) to reserve shares for the locked
    ///      amount so that transfers never undercollateralise the lock.
    function _update(address from, address to, uint256 value) internal override {
        SapienVaultStorage storage $ = _getSapienVaultStorage();
        if (from == address(0)) {
            _pushImmature($, to, value);
        } else if (to == address(0)) {
            uint256 mature = _settle($, from);
            if (value <= mature) {
                $.matureShares[from] = mature - value;
            } else {
                // A slash can burn more than the matured balance (SAP-2 sizes the
                // burn above the matured/locked-equivalent to defeat dilution
                // recapture). Drain matured first, then spill the remainder from
                // the user's immature cohorts FIFO. Normal withdraw/redeem never
                // reach this branch because maxWithdraw/maxRedeem cap at matured.
                $.matureShares[from] = 0;
                uint256 remaining = value - mature;
                uint256 head = $.immatureHead[from];
                uint256 tail = $.immatureTail[from];
                while (remaining > 0 && head < tail) {
                    Tranche storage t = $.immature[from][head];
                    uint256 ts = t.shares;
                    if (ts > remaining) {
                        t.shares = uint128(ts - remaining);
                        remaining = 0;
                    } else {
                        remaining -= ts;
                        delete $.immature[from][head];
                        unchecked {
                            ++head;
                        }
                    }
                }
                if (head == tail) {
                    head = 0;
                    $.immatureTail[from] = 0;
                }
                $.immatureHead[from] = head;
            }
        } else {
            _requireNotPaused();

            uint256 mature = _settle($, from);
            uint256 totalLocked = $.accounts[from].lockedAmount;
            uint256 lockedShares = totalLocked > 0 ? previewWithdraw(totalLocked) : 0;
            uint256 availMature = mature > lockedShares ? mature - lockedShares : 0;
            if (value > availMature) revert TransferExceedsUnlockedShares();

            $.matureShares[from] = mature - value;
            _settle($, to);
            $.matureShares[to] += value;
        }
        super._update(from, to, value);
    }

    // ── Internal ───────────────────────────────────────────────────────

    /// @dev Shares to burn so a slash inflicts exactly `assetDamage` of net value
    ///      loss on `user`, compensating for the exchange-rate dilution that
    ///      would otherwise return part of the penalty to the user's own shares.
    ///
    ///      With virtual pool totals A = totalAssets()+1 and S = totalSupply()+
    ///      10^offset, user balance b, and s_D = convertToShares(assetDamage)
    ///      (shares for the damage at the current rate), the burn is:
    ///
    ///          x = s_D * S / (S + s_D - b)
    ///
    ///      derived from holding assets constant and requiring the user's value
    ///      convertToAssets(b) - convertToAssets(b - x) to equal `assetDamage`.
    ///      The denominator is always positive (the inflation-mitigation virtual
    ///      shares guarantee S > totalSupply() >= b). All rounding is *down* so
    ///      the realized net damage never exceeds `assetDamage`; this keeps the
    ///      post-slash invariant convertToAssets(balanceOf) >= lockedAmount
    ///      intact (the user can never be left under-collateralised by rounding).
    ///      Caps at the user's full balance ("up to that amount of shares, if
    ///      available").
    function _slashShareAmount(address user, uint256 assetDamage) internal view returns (uint256) {
        uint256 sD = convertToShares(assetDamage);
        if (sD == 0) return 0;
        uint256 b = balanceOf(user);
        if (b == 0) return 0;
        uint256 s = totalSupply() + 10 ** _decimalsOffset();
        // denom > 0: s includes the virtual share offset, so s > totalSupply() >= b.
        uint256 x = Math.mulDiv(sD, s, s + sD - b, Math.Rounding.Floor);
        return x > b ? b : x;
    }

    // ── Access control (S2) ────────────────────────────────────────────

    /// @notice Renounce a role held by `account`.
    /// @dev S2: renouncing `DEFAULT_ADMIN_ROLE` is hard-disabled — leaving the
    ///      vault with no admin would permanently freeze pausing, upgrades, role
    ///      management, `minDepositAge`, and ETH rescue. Admin handover must go
    ///      through the two-step, time-locked `beginDefaultAdminTransfer` /
    ///      `acceptDefaultAdminTransfer` flow instead. All other roles renounce
    ///      normally.
    /// @param role The role being renounced.
    /// @param account The account renouncing the role (must be the caller).
    function renounceRole(bytes32 role, address account) public override(AccessControlDefaultAdminRulesUpgradeable) {
        if (role == DEFAULT_ADMIN_ROLE) revert DefaultAdminRenounceDisabled();
        super.renounceRole(role, account);
    }

    // ── Admin ──────────────────────────────────────────────────────────

    /// @inheritdoc ISapienVault
    /// @dev S3: no-op writes are skipped so a redundant set neither bumps storage
    ///      nor emits a spurious `MinDepositAgeUpdated`.
    function setMinDepositAge(uint256 age) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (age > MAX_MIN_DEPOSIT_AGE) revert MinDepositAgeTooHigh(age, MAX_MIN_DEPOSIT_AGE);
        SapienVaultStorage storage $ = _getSapienVaultStorage();
        uint256 oldAge = $.minDepositAge;
        if (age == oldAge) return;
        $.minDepositAge = age;
        emit MinDepositAgeUpdated(oldAge, age);
    }

    /// @inheritdoc ISapienVault
    function minDepositAge() external view returns (uint256) {
        return _getSapienVaultStorage().minDepositAge;
    }

    /// @inheritdoc ISapienVault
    function setMinTrancheSize(uint256 size) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getSapienVaultStorage().minTrancheSize = size;
        emit MinTrancheSizeUpdated(size);
    }

    /// @inheritdoc ISapienVault
    function minTrancheSize() external view returns (uint256) {
        return _getSapienVaultStorage().minTrancheSize;
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
