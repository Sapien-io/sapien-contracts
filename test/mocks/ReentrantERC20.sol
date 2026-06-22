// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/// @notice Malicious ERC20 that re-enters a target contract during token transfers.
/// @dev Used to verify the vault's nonReentrant guard blocks reentrancy via the staked token.
contract ReentrantERC20 is ERC20 {
    uint8 private _decimals;
    address public attackTarget;
    bytes public attackCalldata;
    bool public attackEnabled;

    constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
        _decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Arm the token to re-enter `target` with `data` on the next transfer.
    function armAttack(address target, bytes calldata data) external {
        attackTarget = target;
        attackCalldata = data;
        attackEnabled = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        super._update(from, to, value);

        if (attackEnabled && attackTarget != address(0)) {
            // Single-shot: disable before re-entering so we attempt the reentrant call exactly once.
            attackEnabled = false;
            (bool ok, bytes memory ret) = attackTarget.call(attackCalldata);
            if (!ok) {
                // Bubble up the revert (e.g. ReentrancyGuardReentrantCall) so the outer tx reverts with it.
                assembly {
                    revert(add(ret, 0x20), mload(ret))
                }
            }
        }
    }
}
