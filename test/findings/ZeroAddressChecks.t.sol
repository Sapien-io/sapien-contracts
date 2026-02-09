// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "../BaseTest.t.sol";
import {console} from "forge-std/console.sol";
import {ORIGINATOR_ROLE} from "../../src/interface/ISharedTypes.sol";
import {SapienCore} from "../../src/SapienCore.sol";
import {ValidationOracle} from "../../src/ValidationOracle.sol";
import {SapienTrust} from "../../src/SapienTrust.sol";
import {SapienVault} from "../../src/SapienVault.sol";
import {Rewards} from "../../src/Rewards.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title ZeroAddressChecksTest
 * @notice Comprehensive tests for zero address validation
 * @dev Issue #14 from security review: Missing Zero-Address Checks - MEDIUM
 */
contract ZeroAddressChecksTest is BaseTest {
    bytes32 public constant PROJECT_ID = keccak256("test-project");

    function setUp() public override {
        super.setUp();
    }

    // ============================================
    // SAPIEN CORE TESTS
    // ============================================

    /**
     * @notice Test SapienCore.initialize with zero addresses
     * @dev Should revert with InvalidAddress for all zero address inputs
     */
    function test_SapienCore_Initialize_ZeroVault() public {
        address coreImpl = address(new SapienCore());
        bytes memory initData = abi.encodeWithSelector(
            SapienCore.initialize.selector,
            address(0), // vault - ZERO ADDRESS
            address(rewards),
            address(trust),
            address(oracle),
            admin
        );

        vm.expectRevert();
        new ERC1967Proxy(coreImpl, initData);
    }

    function test_SapienCore_Initialize_ZeroRewards() public {
        address coreImpl = address(new SapienCore());
        bytes memory initData = abi.encodeWithSelector(
            SapienCore.initialize.selector,
            address(vault),
            address(0), // rewards - ZERO ADDRESS
            address(trust),
            address(oracle),
            admin
        );

        vm.expectRevert();
        new ERC1967Proxy(coreImpl, initData);
    }

    function test_SapienCore_Initialize_ZeroTrust() public {
        address coreImpl = address(new SapienCore());
        bytes memory initData = abi.encodeWithSelector(
            SapienCore.initialize.selector,
            address(vault),
            address(rewards),
            address(0), // trust - ZERO ADDRESS
            address(oracle),
            admin
        );

        vm.expectRevert();
        new ERC1967Proxy(coreImpl, initData);
    }

    function test_SapienCore_Initialize_ZeroOracle() public {
        address coreImpl = address(new SapienCore());
        bytes memory initData = abi.encodeWithSelector(
            SapienCore.initialize.selector,
            address(vault),
            address(rewards),
            address(trust),
            address(0), // oracle - ZERO ADDRESS
            admin
        );

        vm.expectRevert();
        new ERC1967Proxy(coreImpl, initData);
    }

    function test_SapienCore_Initialize_ZeroAdmin() public {
        address coreImpl = address(new SapienCore());
        bytes memory initData = abi.encodeWithSelector(
            SapienCore.initialize.selector,
            address(vault),
            address(rewards),
            address(trust),
            address(oracle),
            address(0) // admin - ZERO ADDRESS
        );

        vm.expectRevert();
        new ERC1967Proxy(coreImpl, initData);
    }

    function test_SapienCore_CreateProject_ZeroRewardToken() public {
        // Setup originator role
        vm.startPrank(admin);
        trust.grantRole(ORIGINATOR_ROLE, originator);
        vm.stopPrank();

        // Note: createProject does NOT check for zero address
        // This test documents that zero address is accepted (potential issue)
        vm.startPrank(originator);
        core.createProject(PROJECT_ID, address(0), "test-project", 0, 0, 3, 1000, "");
        vm.stopPrank();

        // Project is created (this documents the missing check)
        assertEq(core.getProject(PROJECT_ID).originator, originator, "Project should be created");

        console.log("=== Missing Zero Address Check ===");
        console.log("createProject accepts address(0) for rewardToken");
        console.log("This may cause issues when trying to fund the project");
    }

    // ============================================
    // VALIDATION ORACLE TESTS
    // ============================================

    /**
     * @notice Test ValidationOracle.initialize with zero addresses
     */
    function test_ValidationOracle_Initialize_ZeroTrust() public {
        address oracleImpl = address(new ValidationOracle());
        bytes memory initData = abi.encodeWithSelector(
            ValidationOracle.initialize.selector,
            address(0), // trust - ZERO ADDRESS
            address(vault),
            "LinearStake",
            admin
        );

        vm.expectRevert();
        new ERC1967Proxy(oracleImpl, initData);
    }

    function test_ValidationOracle_Initialize_ZeroVault() public {
        address oracleImpl = address(new ValidationOracle());
        bytes memory initData = abi.encodeWithSelector(
            ValidationOracle.initialize.selector,
            address(trust),
            address(0), // vault - ZERO ADDRESS
            "LinearStake",
            admin
        );

        vm.expectRevert();
        new ERC1967Proxy(oracleImpl, initData);
    }

    function test_ValidationOracle_Initialize_ZeroAdmin() public {
        address oracleImpl = address(new ValidationOracle());
        bytes memory initData = abi.encodeWithSelector(
            ValidationOracle.initialize.selector,
            address(trust),
            address(vault),
            "LinearStake",
            address(0) // admin - ZERO ADDRESS
        );

        vm.expectRevert();
        new ERC1967Proxy(oracleImpl, initData);
    }

    // ============================================
    // SAPIEN TRUST TESTS
    // ============================================

    /**
     * @notice Test SapienTrust.initialize with zero addresses
     */
    function test_SapienTrust_Initialize_ZeroVault() public {
        address trustImpl = address(new SapienTrust());
        bytes memory initData = abi.encodeWithSelector(
            SapienTrust.initialize.selector,
            address(0), // vault - ZERO ADDRESS
            100 ether,
            10,
            admin
        );

        vm.expectRevert();
        new ERC1967Proxy(trustImpl, initData);
    }

    function test_SapienTrust_Initialize_ZeroAdmin() public {
        address trustImpl = address(new SapienTrust());
        bytes memory initData = abi.encodeWithSelector(
            SapienTrust.initialize.selector,
            address(vault),
            100 ether,
            10,
            address(0) // admin - ZERO ADDRESS
        );

        vm.expectRevert();
        new ERC1967Proxy(trustImpl, initData);
    }

    // ============================================
    // SAPIEN VAULT TESTS
    // ============================================

    /**
     * @notice Test SapienVault.initialize with zero addresses
     */
    function test_SapienVault_Initialize_ZeroAsset() public {
        address vaultImpl = address(new SapienVault());
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector,
            address(0), // asset - ZERO ADDRESS
            admin
        );

        vm.expectRevert();
        new ERC1967Proxy(vaultImpl, initData);
    }

    function test_SapienVault_Initialize_ZeroAdmin() public {
        address vaultImpl = address(new SapienVault());
        bytes memory initData = abi.encodeWithSelector(
            SapienVault.initialize.selector,
            address(stakeToken),
            address(0) // admin - ZERO ADDRESS
        );

        vm.expectRevert();
        new ERC1967Proxy(vaultImpl, initData);
    }

    // ============================================
    // REWARDS TESTS
    // ============================================

    /**
     * @notice Test Rewards.initialize with zero admin
     */
    function test_Rewards_Initialize_ZeroAdmin() public {
        address rewardsImpl = address(new Rewards());
        bytes memory initData = abi.encodeWithSelector(
            Rewards.initialize.selector,
            address(0) // admin - ZERO ADDRESS
        );

        vm.expectRevert();
        new ERC1967Proxy(rewardsImpl, initData);
    }

    /**
     * @notice Test Rewards.setCore with zero address
     * @dev Already tested in Rewards.t.sol, but included for completeness
     */
    function test_Rewards_SetCore_ZeroAddress() public {
        vm.startPrank(admin);
        vm.expectRevert();
        rewards.setCore(address(0));
        vm.stopPrank();
    }

    /**
     * @notice Test Rewards.emergencyWithdraw with zero address
     * @dev Already tested in Rewards.t.sol, but included for completeness
     */
    function test_Rewards_EmergencyWithdraw_ZeroTo() public {
        vm.startPrank(admin);
        rewards.pause();
        vm.expectRevert();
        rewards.emergencyWithdraw(address(rewardToken), address(0), 10 ether);
        vm.stopPrank();
    }

    // ============================================
    // COMPREHENSIVE AUDIT
    // ============================================

    /**
     * @notice Document all functions that should check for zero addresses
     */
    function test_DocumentZeroAddressChecks() public pure {
        console.log("=== Zero Address Checks Audit ===");
        console.log("\n[OK] Functions WITH zero address checks:");
        console.log("1. SapienCore.initialize() - Checks all addresses");
        console.log("2. ValidationOracle.initialize() - Checks trust, vault, admin");
        console.log("3. SapienTrust.initialize() - Checks vault, admin");
        console.log("4. SapienVault.initialize() - Checks asset, admin");
        console.log("5. Rewards.initialize() - Checks admin");
        console.log("6. Rewards.setCore() - Checks core address");
        console.log("7. Rewards.emergencyWithdraw() - Checks 'to' address");

        console.log("\n[WARN] Functions that MAY need zero address checks:");
        console.log("1. SapienCore.createProject() - rewardToken parameter");
        console.log("   - Currently: No explicit check found");
        console.log("   - Recommendation: Add check if zero address is invalid");

        console.log("\n2. ValidationOracle.registerProject() - originator parameter");
        console.log("   - Currently: No explicit check found");
        console.log("   - Recommendation: Add check if zero address is invalid");

        console.log("\n3. Any function accepting address parameters");
        console.log("   - Should validate if zero address would cause issues");

        console.log("\n=== Summary ===");
        console.log("Most critical functions (initializers) have proper checks");
        console.log("Some public functions may benefit from additional validation");
    }

    /**
     * @notice Test that valid addresses work correctly
     */
    function test_ValidAddresses_WorkCorrectly() public view {
        // All initializers should work with valid addresses
        // This is already tested in BaseTest.setUp()
        assertTrue(address(core) != address(0), "Core should be deployed");
        assertTrue(address(oracle) != address(0), "Oracle should be deployed");
        assertTrue(address(trust) != address(0), "Trust should be deployed");
        assertTrue(address(vault) != address(0), "Vault should be deployed");
        assertTrue(address(rewards) != address(0), "Rewards should be deployed");
    }
}
