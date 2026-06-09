// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @dev Shared deployment helpers for Halmos test contracts.
abstract contract SapienVaultHalmosBase is Test {
    SapienVault internal vault;
    MockERC20 internal token;

    address internal constant ADMIN = address(0xA11CE);
    address internal constant ENGINE = address(0xE0611E);
    address internal constant USER = address(0xBEEF);
    address internal constant USER2 = address(0xCAFE);

    function _deployVault() internal {
        token = new MockERC20("Sapien Token", "SAPIEN");

        SapienVault impl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), ADMIN));
        vault = SapienVault(address(new ERC1967Proxy(address(impl), initData)));

        vm.startPrank(ADMIN);
        vault.grantRole(vault.ENGINE_ROLE(), ENGINE);
        vm.stopPrank();
    }

    function _fund(address account, uint256 amount) internal {
        token.mint(account, amount);
        vm.prank(account);
        token.approve(address(vault), type(uint256).max);
    }

    function _assumeReasonableAssets(uint256 assets) internal {
        vm.assume(assets > 0);
        // Tighter bound keeps ERC-4626 mulDiv paths tractable for the SMT solver.
        vm.assume(assets <= type(uint64).max);
    }
}
