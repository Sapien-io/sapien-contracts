// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {MockERC20} from "../mocks/MockERC20.sol";

/// @title AuditBase
/// @notice Shared fixture for the per-finding Quantstamp audit test files.
/// @dev One test contract per finding (SAP-1 … SAP-7) inherits this base so the
///      deploy/setup boilerplate lives in a single place. Each finding file
///      contains the test(s) that prove that finding is valid.
abstract contract AuditBase is Test {
    SapienVault public vault;
    MockERC20 public token;

    address public admin = makeAddr("admin");
    address public engine = makeAddr("engine");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint256 public constant DEPOSIT_AMOUNT = 1000e18;

    bytes32 internal ENGINE_ROLE;
    bytes32 internal ADMIN_ROLE;

    function setUp() public virtual {
        token = new MockERC20("Sapien Token", "SAPIEN");

        SapienVault vaultImpl = new SapienVault();
        bytes memory initData = abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), admin));
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), initData)));

        ENGINE_ROLE = vault.ENGINE_ROLE();
        ADMIN_ROLE = vault.DEFAULT_ADMIN_ROLE();

        vm.startPrank(admin);
        vault.grantRole(ENGINE_ROLE, engine);
        // initialize() now seeds DEFAULT_MIN_DEPOSIT_AGE (SAP-5). Findings that
        // depend on a specific cooldown set their own age; the rest exercise
        // guard-independent mechanics, so disable it here for a clean baseline.
        vault.setMinDepositAge(0);
        vm.stopPrank();

        token.mint(user1, DEPOSIT_AMOUNT * 10);
        token.mint(user2, DEPOSIT_AMOUNT * 10);

        vm.prank(user1);
        token.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        token.approve(address(vault), type(uint256).max);
    }
}
