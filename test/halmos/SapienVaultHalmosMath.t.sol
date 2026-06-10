// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Math} from "lib/openzeppelin-contracts/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";

/// @notice Pure-math Halmos checks for the dilution-compensated slash burn formula.
/// @dev Fully symbolic end-to-end SAP-2 (deposit → lock → slash → convertToAssets)
///      times out in Halmos; this isolates `_slashShareAmount` mulDiv reasoning.
contract SapienVaultHalmosMathTest is Test {
    uint256 internal constant DECIMALS_OFFSET = 0; // SapienVault uses offset 0

    function _slashBurnShares(uint256 naiveShares, uint256 userBalance, uint256 totalSupply)
        internal
        pure
        returns (uint256)
    {
        uint256 s = totalSupply + 10 ** DECIMALS_OFFSET;
        uint256 x = Math.mulDiv(naiveShares, s, s + naiveShares - userBalance, Math.Rounding.Floor);
        return x > userBalance ? userBalance : x;
    }

    /// @dev Burn >= naive shares — concrete grid (symbolic version times out).
    function check_slashBurnGteNaiveShares_concrete() external pure {
        assert(_slashBurnShares(400e18, 1000e18, 1000e18) >= 400e18);
        assert(_slashBurnShares(3e18, 10e18, 10e18) >= 3e18);
    }

    /// @dev Burn never exceeds the user's balance.
    function check_slashBurnLteBalance(uint256 naiveShares, uint256 userBalance, uint256 totalSupply) external pure {
        vm.assume(naiveShares > 0 && naiveShares <= 1e24);
        vm.assume(userBalance > 0 && userBalance <= 1e24);
        vm.assume(totalSupply >= userBalance && totalSupply <= 1e24);

        uint256 burn = _slashBurnShares(naiveShares, userBalance, totalSupply);
        assert(burn <= userBalance);
    }
}
