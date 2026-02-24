// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// ── V2 mock implementations ───────────────────────────────────────────────────
//
// These are minimal "next version" implementations used to verify upgrade
// mechanics. They add a version() identifier and a reinitializer(2) so that
// migration-calldata paths can be exercised without touching production code.

/// @custom:oz-upgrades-unsafe-allow constructor
contract SapienCoreV2 is SapienCore {
    constructor() {
        _disableInitializers();
    }

    function version() external pure returns (string memory) {
        return "v2";
    }

    /// @dev Simulates migration logic run via upgradeToAndCall.
    function initializeV2() external reinitializer(2) {}
}

/// @custom:oz-upgrades-unsafe-allow constructor
contract SapienVaultV2 is SapienVault {
    constructor() {
        _disableInitializers();
    }

    function version() external pure returns (string memory) {
        return "v2";
    }

    /// @dev Simulates migration logic run via upgradeToAndCall.
    function initializeV2() external reinitializer(2) {}
}

// ─────────────────────────────────────────────────────────────────────────────
//
// How UUPS upgrades work in this system
// ──────────────────────────────────────
// Both SapienCore and SapienVault are deployed behind ERC-1967 proxies.
// The UUPS pattern stores the implementation address in a well-known EIP-1967
// slot and delegates all calls to it. The implementation contract itself holds
// the upgradeToAndCall() entry-point, gated by _authorizeUpgrade() which
// requires DEFAULT_ADMIN_ROLE.
//
// Storage is held entirely in the PROXY. ERC-7201 namespaced structs mean
// there is no risk of collisions between the protocol storage and the OZ
// upgradeable base contracts, and no __gap arrays are needed.
//
// Initializer versioning (OZ Initializable):
//   - constructor() → _disableInitializers() sets _initialized = max on the
//     bare implementation so it can never be initialised directly.
//   - initialize()  → marked `initializer`, sets proxy _initialized = 1.
//   - initializeV2() → marked `reinitializer(2)`, requires _initialized < 2.
//
// ─────────────────────────────────────────────────────────────────────────────

/// @title Upgrade Tests — SapienCore & SapienVault
contract UpgradeTest is BaseTest {
    // ERC-1967 implementation slot
    // keccak256("eip1967.proxy.implementation") - 1
    bytes32 private constant _IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    // Mirror the ERC-1967 Upgraded event so vm.expectEmit can reference it
    event Upgraded(address indexed implementation);

    function _getImpl(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, _IMPL_SLOT))));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienCore — access control
    // ══════════════════════════════════════════════════════════════════════════

    function test_core_adminCanUpgrade() public {
        SapienCoreV2 newImpl = new SapienCoreV2();

        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        assertEq(_getImpl(address(engine)), address(newImpl));
    }

    function test_core_nonAdminCannotUpgrade() public {
        SapienCoreV2 newImpl = new SapienCoreV2();

        vm.prank(contributor1);
        vm.expectRevert();
        engine.upgradeToAndCall(address(newImpl), "");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienCore — re-initialisation guards
    // ══════════════════════════════════════════════════════════════════════════

    // initialize() uses the `initializer` modifier which requires _initialized == 0.
    // After setUp the proxy has _initialized = 1, so a second initialize() must revert.
    function test_core_reinitializeBlockedAfterUpgrade() public {
        SapienCoreV2 newImpl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        vm.expectRevert();
        engine.initialize(admin, address(vault), treasury);
    }

    // reinitializer(2) requires _initialized < 2. After setUp _initialized = 1, so it passes.
    function test_core_reinitializerRunsAfterUpgrade() public {
        SapienCoreV2 newImpl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        SapienCoreV2(address(engine)).initializeV2();
    }

    // Direct calls to the implementation are blocked because the constructor ran
    // _disableInitializers() which sets _initialized = type(uint64).max.
    function test_core_reinitializerBlockedOnDirectImpl() public {
        SapienCoreV2 impl = new SapienCoreV2();

        vm.expectRevert();
        impl.initializeV2();
    }

    // Once reinitializer(2) has run it cannot run again (_initialized is now 2).
    function test_core_reinitializerIdempotentAfterRun() public {
        SapienCoreV2 newImpl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        SapienCoreV2(address(engine)).initializeV2();

        vm.expectRevert();
        SapienCoreV2(address(engine)).initializeV2();
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienCore — migration calldata via upgradeToAndCall
    // ══════════════════════════════════════════════════════════════════════════

    // upgradeToAndCall atomically upgrades the implementation and calls the
    // migration function in the same transaction.
    function test_core_upgradeWithMigrationCalldata() public {
        SapienCoreV2 newImpl = new SapienCoreV2();
        bytes memory data = abi.encodeCall(SapienCoreV2.initializeV2, ());

        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), data);

        // Migration already ran — a second call must revert
        vm.expectRevert();
        SapienCoreV2(address(engine)).initializeV2();
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienCore — implementation slot & Upgraded event
    // ══════════════════════════════════════════════════════════════════════════

    function test_core_implementationChangesAfterUpgrade() public {
        address implBefore = _getImpl(address(engine));

        SapienCoreV2 newImpl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        address implAfter = _getImpl(address(engine));
        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(newImpl));
    }

    function test_core_upgradeEmitsUpgradedEvent() public {
        SapienCoreV2 newImpl = new SapienCoreV2();

        vm.expectEmit(true, false, false, false, address(engine));
        emit Upgraded(address(newImpl));

        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienCore — new functionality available post-upgrade
    // ══════════════════════════════════════════════════════════════════════════

    function test_core_upgradeExposesNewFunction() public {
        SapienCoreV2 newImpl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        assertEq(SapienCoreV2(address(engine)).version(), "v2");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienCore — storage preservation
    // ══════════════════════════════════════════════════════════════════════════

    // Protocol configuration written during initialize() must survive an upgrade.
    function test_core_upgradePreservesProtocolConfig() public {
        address treasuryBefore = engine.treasury();
        uint256 challengePeriodBefore = engine.challengePeriod();
        uint256 claimDeadlineBefore = engine.claimDeadline();
        uint256 commitDeadlineBefore = engine.commitDeadline();
        uint256 revealDeadlineBefore = engine.revealDeadline();
        (uint256 origFee, uint256 contribFee, uint256 valFee) = engine.getAdapterFees();

        SapienCoreV2 newImpl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        assertEq(engine.treasury(), treasuryBefore);
        assertEq(engine.challengePeriod(), challengePeriodBefore);
        assertEq(engine.claimDeadline(), claimDeadlineBefore);
        assertEq(engine.commitDeadline(), commitDeadlineBefore);
        assertEq(engine.revealDeadline(), revealDeadlineBefore);
        (uint256 o, uint256 c, uint256 v) = engine.getAdapterFees();
        assertEq(o, origFee);
        assertEq(c, contribFee);
        assertEq(v, valFee);
    }

    // Vault reference written during initialize() must survive.
    function test_core_upgradePreservesVaultReference() public {
        address vaultBefore = engine.vault();

        SapienCoreV2 newImpl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        assertEq(engine.vault(), vaultBefore);
    }

    // Access-control roles granted during initialize() must survive.
    function test_core_upgradePreservesRoles() public {
        assertTrue(engine.hasRole(engine.DEFAULT_ADMIN_ROLE(), admin));

        SapienCoreV2 newImpl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        assertTrue(engine.hasRole(engine.DEFAULT_ADMIN_ROLE(), admin));
    }

    // Active project data and escrow balances must survive.
    function test_core_upgradePreservesProjectState() public {
        bytes32 projectId = _createAndFundProject();

        address origBefore = engine.getProject(projectId).originator;
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));
        assertGt(escrowBefore, 0, "precondition: escrow funded");

        SapienCoreV2 newImpl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        assertEq(engine.getProject(projectId).originator, origBefore);
        assertEq(engine.getProjectEscrow(projectId, address(token)), escrowBefore);
    }

    // Contribution claim data must survive.
    function test_core_upgradePreservesClaimData() public {
        bytes32 projectId = _createAndFundProject();
        _claimAndContribute(contributor1, projectId, 1);

        // Claim IDs start at 1 (nextClaimId = 1 set in initialize)
        address claimantBefore = engine.getClaim(1).claimant;
        assertEq(claimantBefore, contributor1, "precondition: claim recorded");

        SapienCoreV2 newImpl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(newImpl), "");

        assertEq(engine.getClaim(1).claimant, claimantBefore);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienCore — multiple sequential upgrades
    // ══════════════════════════════════════════════════════════════════════════

    function test_core_multipleSequentialUpgrades() public {
        bytes32 projectId = _createAndFundProject();
        uint256 escrowBefore = engine.getProjectEscrow(projectId, address(token));

        SapienCoreV2 v2Impl = new SapienCoreV2();
        vm.prank(admin);
        engine.upgradeToAndCall(address(v2Impl), "");

        // Upgrade back to the original implementation
        SapienCore v1Impl = new SapienCore();
        vm.prank(admin);
        engine.upgradeToAndCall(address(v1Impl), "");

        assertEq(engine.getProjectEscrow(projectId, address(token)), escrowBefore);
        assertEq(engine.treasury(), treasury);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienVault — access control
    // ══════════════════════════════════════════════════════════════════════════

    function test_vault_adminCanUpgrade() public {
        SapienVaultV2 newImpl = new SapienVaultV2();

        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        assertEq(_getImpl(address(vault)), address(newImpl));
    }

    function test_vault_nonAdminCannotUpgrade() public {
        SapienVaultV2 newImpl = new SapienVaultV2();

        vm.prank(contributor1);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newImpl), "");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienVault — re-initialisation guards
    // ══════════════════════════════════════════════════════════════════════════

    function test_vault_reinitializeBlockedAfterUpgrade() public {
        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        vm.expectRevert();
        vault.initialize(IERC20(address(token)), admin);
    }

    function test_vault_reinitializerRunsAfterUpgrade() public {
        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        SapienVaultV2(address(vault)).initializeV2();
    }

    function test_vault_reinitializerBlockedOnDirectImpl() public {
        SapienVaultV2 impl = new SapienVaultV2();

        vm.expectRevert();
        impl.initializeV2();
    }

    function test_vault_reinitializerIdempotentAfterRun() public {
        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        SapienVaultV2(address(vault)).initializeV2();

        vm.expectRevert();
        SapienVaultV2(address(vault)).initializeV2();
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienVault — migration calldata via upgradeToAndCall
    // ══════════════════════════════════════════════════════════════════════════

    function test_vault_upgradeWithMigrationCalldata() public {
        SapienVaultV2 newImpl = new SapienVaultV2();
        bytes memory data = abi.encodeCall(SapienVaultV2.initializeV2, ());

        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), data);

        vm.expectRevert();
        SapienVaultV2(address(vault)).initializeV2();
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienVault — implementation slot & Upgraded event
    // ══════════════════════════════════════════════════════════════════════════

    function test_vault_implementationChangesAfterUpgrade() public {
        address implBefore = _getImpl(address(vault));

        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        address implAfter = _getImpl(address(vault));
        assertNotEq(implBefore, implAfter);
        assertEq(implAfter, address(newImpl));
    }

    function test_vault_upgradeEmitsUpgradedEvent() public {
        SapienVaultV2 newImpl = new SapienVaultV2();

        vm.expectEmit(true, false, false, false, address(vault));
        emit Upgraded(address(newImpl));

        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienVault — new functionality available post-upgrade
    // ══════════════════════════════════════════════════════════════════════════

    function test_vault_upgradeExposesNewFunction() public {
        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        assertEq(SapienVaultV2(address(vault)).version(), "v2");
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienVault — storage preservation
    // ══════════════════════════════════════════════════════════════════════════

    // ERC-4626 state (total assets & supply) must survive — these are stored in
    // OZ's ERC20Upgradeable and ERC4626Upgradeable namespaced slots.
    function test_vault_upgradePreservesERC4626State() public {
        uint256 totalAssetsBefore = vault.totalAssets();
        uint256 totalSupplyBefore = vault.totalSupply();
        assertGt(totalAssetsBefore, 0, "precondition: assets deposited");

        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        assertEq(vault.totalAssets(), totalAssetsBefore);
        assertEq(vault.totalSupply(), totalSupplyBefore);
    }

    // Underlying asset address must survive.
    function test_vault_upgradePreservesAssetAddress() public {
        address assetBefore = vault.asset();

        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        assertEq(vault.asset(), assetBefore);
    }

    // Share balances (ERC-20 balanceOf) for depositors must survive.
    function test_vault_upgradePreservesShareBalances() public {
        uint256 sharesBefore = vault.balanceOf(contributor1);
        assertGt(sharesBefore, 0, "precondition: contributor1 has shares");

        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        assertEq(vault.balanceOf(contributor1), sharesBefore);
    }

    // Available (unlocked) balance must survive.
    function test_vault_upgradePreservesAvailableBalance() public {
        uint256 availBefore = vault.availableBalance(contributor1);
        assertGt(availBefore, 0, "precondition: contributor1 has free balance");

        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        assertEq(vault.availableBalance(contributor1), availBefore);
    }

    // Locked stake in SapienVaultStorage (ERC-7201 namespace) must survive.
    // Trigger a lock by claiming a contribution slot, then upgrade, then verify
    // the available balance (which reflects the locked amount) is unchanged.
    function test_vault_upgradePreservesStakeAccount() public {
        bytes32 projectId = _createAndFundProject();
        _claimAndContribute(contributor1, projectId, 1);

        uint256 availAfterLock = vault.availableBalance(contributor1);

        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        assertEq(vault.availableBalance(contributor1), availAfterLock);
    }

    // ACCESS_CONTROL roles (ENGINE_ROLE, DEFAULT_ADMIN_ROLE) must survive.
    function test_vault_upgradePreservesRoles() public {
        bytes32 engineRole = vault.ENGINE_ROLE();
        assertTrue(vault.hasRole(engineRole, address(engine)));
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));

        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        assertTrue(vault.hasRole(engineRole, address(engine)));
        assertTrue(vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), admin));
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienVault — functional continuity after upgrade
    // ══════════════════════════════════════════════════════════════════════════

    // Deposits and withdrawals must work normally after an upgrade.
    function test_vault_depositsWorkAfterUpgrade() public {
        SapienVaultV2 newImpl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(newImpl), "");

        address newUser = makeAddr("newUser");
        uint256 amount = 100e18;
        token.mint(newUser, amount);

        vm.startPrank(newUser);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, newUser);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(vault.balanceOf(newUser), shares);
    }

    // ══════════════════════════════════════════════════════════════════════════
    // SapienVault — multiple sequential upgrades
    // ══════════════════════════════════════════════════════════════════════════

    function test_vault_multipleSequentialUpgrades() public {
        uint256 totalAssetsBefore = vault.totalAssets();

        SapienVaultV2 v2Impl = new SapienVaultV2();
        vm.prank(admin);
        vault.upgradeToAndCall(address(v2Impl), "");

        SapienVault v1Impl = new SapienVault();
        vm.prank(admin);
        vault.upgradeToAndCall(address(v1Impl), "");

        assertEq(vault.totalAssets(), totalAssetsBefore);
        assertEq(vault.asset(), address(token));
    }
}
