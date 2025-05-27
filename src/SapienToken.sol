// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {ISapienToken} from "src/interfaces/ISapienToken.sol";
import {AccessControl} from "lib/openzeppelin-contracts/contracts/access/AccessControl.sol";
import {ERC20Permit, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {Pausable} from "lib/openzeppelin-contracts/contracts/utils/Pausable.sol";

/**
 * @title SapienToken
 * @dev Implementation of the Sapien Token (ERC20) with ERC20Permit
 */
contract SapienToken is ISapienToken, AccessControl, ERC20Permit, Pausable {
    /// @dev Maximum supply of tokens (1 Billion tokens with 18 decimals)
    uint256 private immutable _MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev Role for pausing/unpausing the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /**
     * @dev Constructor that sets up the token with initial parameters
     * @param admin The address that will have admin roles (should be a multisig)
     */
    constructor(address admin) ERC20("Sapien Token", "SAPIEN") ERC20Permit("Sapien Token") {
        if (admin == address(0)) revert ZeroAddressOwner();

        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(PAUSER_ROLE, admin);

        _mint(admin, _MAX_SUPPLY);
    }

    /// @inheritdoc ISapienToken
    function maxSupply() external pure returns (uint256) {
        return _MAX_SUPPLY;
    }

    /// @inheritdoc ISapienToken
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /// @inheritdoc ISapienToken
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /// @dev Override supportsInterface to handle multiple inheritance
    function supportsInterface(bytes4 interfaceId) public view virtual override(AccessControl) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    ///@dev Override _update to add pausable functionality
    function _update(address from, address to, uint256 value) internal override whenNotPaused {
        super._update(from, to, value);
    }
}
