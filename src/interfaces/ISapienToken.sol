// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

/**
 * @title ISapienToken
 * @dev Interface for the Sapien Token contract
 */
interface ISapienToken is IERC20 {
    /// @dev Custom errors
    error ZeroAddress();

    /// @dev Returns the maximum supply of tokens
    function maxSupply() external view returns (uint256);
}
