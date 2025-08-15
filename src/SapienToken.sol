// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

/**
 * @title SapienToken
 * @notice Sapien AI Platform Utility Token
 * @dev This is the native utility token for the Sapien AI ecosystem.
 */
import {ISapienToken} from "src/interfaces/ISapienToken.sol";
import {ERC20Permit, ERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title SapienToken
contract SapienToken is ISapienToken, ERC20Permit {
    /// @dev Maximum supply of tokens (1 Billion tokens with 18 decimals)
    uint256 private immutable MAX_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @dev Constructor
    /// @param treasury The foundation treasury multisig
    constructor(address treasury) ERC20("Sapien", "SAPIEN") ERC20Permit("Sapien") {
        if (treasury == address(0)) revert ZeroAddress();

        _mint(treasury, MAX_SUPPLY);
    }

    /// @inheritdoc ISapienToken
    function maxSupply() external pure returns (uint256) {
        return MAX_SUPPLY;
    }
}
