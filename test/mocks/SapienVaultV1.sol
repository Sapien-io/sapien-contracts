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
import {UUPSUpgradeable} from "lib/openzeppelin-contracts-upgradeable/contracts/proxy/utils/UUPSUpgradeable.sol";
import {SapienVaultStorage, StakeAccount} from "src/Types.sol";

/// @title SapienVaultV1
/// @notice Frozen pre-SAP-1 implementation used ONLY by migration tests to
///         reproduce the legacy global-timer storage state (it writes
///         `lastDepositTimestamp`). It shares the ERC-7201 storage slot and the
///         first three struct fields with the production contract, so an
///         `upgradeToAndCall` to the new implementation exercises the real lazy
///         migration path. Not deployed in production.
contract SapienVaultV1 is ERC4626Upgradeable, AccessControlUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    bytes32 public constant ENGINE_ROLE = keccak256("ENGINE_ROLE");

    error DepositTooRecent(uint256 required, uint256 actual);
    error InsufficientAvailableBalance(uint256 required, uint256 available);

    function _getSapienVaultStorage() private pure returns (SapienVaultStorage storage s) {
        assembly {
            s.slot := 0x4d6e6410717d1c28e2e2dce6e8ac53def1f84cd7244221b7a072c02c51460000
        }
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(IERC20 asset_, address admin_) external initializer {
        __ERC4626_init(asset_);
        __ERC20_init("Sapien PoQ Vault", "vSAPIEN");
        __AccessControl_init();
        __Pausable_init();
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    function _hasMetDepositAge(address user) internal view returns (bool) {
        uint256 minAge = _getSapienVaultStorage().minDepositAge;
        if (minAge == 0) return true;
        uint256 depositTs = _getSapienVaultStorage().lastDepositTimestamp[user];
        if (depositTs == 0) return true;
        return (block.timestamp - depositTs) >= minAge;
    }

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

    function _deposit(address caller, address receiver, uint256 assets, uint256 shares) internal override {
        if (caller == receiver) {
            _getSapienVaultStorage().lastDepositTimestamp[receiver] = block.timestamp;
        }
        super._deposit(caller, receiver, assets, shares);
    }

    function lockStake(uint256 amount) external whenNotPaused {
        address user = msg.sender;
        SapienVaultStorage storage $ = _getSapienVaultStorage();
        _requireDepositAgeMet(user);
        uint256 avail = availableBalance(user);
        if (avail < amount) revert InsufficientAvailableBalance(amount, avail);
        $.accounts[user].lockedAmount += amount;
    }

    function availableBalance(address user) public view returns (uint256) {
        StakeAccount storage acct = _getSapienVaultStorage().accounts[user];
        uint256 totalLocked = acct.lockedAmount;
        uint256 totalAssets_ = convertToAssets(balanceOf(user));
        return totalAssets_ > totalLocked ? totalAssets_ - totalLocked : 0;
    }

    function maxRedeem(address owner) public view override returns (uint256) {
        if (paused() || !_hasMetDepositAge(owner)) return 0;
        uint256 lockedAmt = _getSapienVaultStorage().accounts[owner].lockedAmount;
        uint256 shares = balanceOf(owner);
        uint256 lockedShares = lockedAmt > 0 ? previewWithdraw(lockedAmt) : 0;
        uint256 availShares = shares > lockedShares ? shares - lockedShares : 0;
        uint256 parentMax = super.maxRedeem(owner);
        return availShares < parentMax ? availShares : parentMax;
    }

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

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            _requireNotPaused();
            _requireDepositAgeMet(from);
            SapienVaultStorage storage $ = _getSapienVaultStorage();
            if (value > 0) {
                $.lastDepositTimestamp[to] = block.timestamp;
            }
        }
        super._update(from, to, value);
    }

    function setMinDepositAge(uint256 age) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _getSapienVaultStorage().minDepositAge = age;
    }

    function lastDepositTimestamp(address user) external view returns (uint256) {
        return _getSapienVaultStorage().lastDepositTimestamp[user];
    }

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}
}
