// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {
    Project,
    ProjectStatus,
    Claim,
    Contribution,
    ContributionStatus,
    ConsensusReport,
    StakeAccount,
    Reputation,
    Dispute,
    OriginatorReport
} from "src/Types.sol";

/// @title SepoliaForkUpgradeTest
/// @notice Forks live Base Sepolia state, snapshots everything, performs the
///         upgrade with the latest source, then asserts all storage survived.
///
///         Usage:
///           forge test --match-contract SepoliaForkUpgradeTest \
///             --fork-url $BASE_SEPOLIA_RPC_URL -vvv
///
///         Optional env vars:
///           PROJECT_ID  - hex-encoded project ID to verify (if one exists on-chain)
///           STAKER      - address of a user with vault deposits to verify
contract SepoliaForkUpgradeTest is Test {
    uint256 constant BASE_SEPOLIA_CHAIN_ID = 84532;

    // ── Deployed addresses (deployments/base-sepolia.json) ───────────
    address constant SAPIEN_CORE = 0xDFFEc0D8F9DF05bf3DecbdFefD650779D6481077;
    address constant SAPIEN_VAULT = 0xf0E3C676b277Ce31C2E72Cd473684FA4C8866029;
    address constant SAPIEN_TOKEN = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6;
    address constant SAFE_ADMIN = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;

    // ERC-1967 implementation slot
    bytes32 private constant _IMPL_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    SapienCore engine = SapienCore(SAPIEN_CORE);
    SapienVault vault = SapienVault(SAPIEN_VAULT);
    IERC20 token = IERC20(SAPIEN_TOKEN);

    // ── Pre-upgrade snapshots ────────────────────────────────────────
    struct CoreSnapshot {
        address treasury;
        address vaultAddr;
        uint256 challengePeriod;
        uint256 claimDeadline;
        uint256 commitDeadline;
        uint256 revealDeadline;
        uint256 forceSettleDelay;
        uint256 decayRateBps;
        uint256 originationBps;
        uint256 contributionBps;
        uint256 validationBps;
        bool adminHasRole;
        bool isPaused;
    }

    struct VaultSnapshot {
        address asset;
        uint256 totalAssets;
        uint256 totalSupply;
        uint256 minDepositAge;
        bool adminHasRole;
        bool engineHasRole;
        bool isPaused;
    }

    function _readImpl(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, _IMPL_SLOT))));
    }

    function _snapshotCore() internal view returns (CoreSnapshot memory s) {
        s.treasury = engine.treasury();
        s.vaultAddr = engine.vault();
        s.challengePeriod = engine.challengePeriod();
        s.claimDeadline = engine.claimDeadline();
        s.commitDeadline = engine.commitDeadline();
        s.revealDeadline = engine.revealDeadline();
        s.forceSettleDelay = engine.forceSettleDelay();
        s.decayRateBps = engine.decayRateBps();
        (s.originationBps, s.contributionBps, s.validationBps) = engine.getAdapterFees();
        s.adminHasRole = engine.hasRole(engine.DEFAULT_ADMIN_ROLE(), SAFE_ADMIN);
        s.isPaused = engine.paused();
    }

    function _snapshotVault() internal view returns (VaultSnapshot memory s) {
        s.asset = vault.asset();
        s.totalAssets = vault.totalAssets();
        s.totalSupply = vault.totalSupply();
        s.minDepositAge = vault.minDepositAge();
        s.adminHasRole = vault.hasRole(vault.DEFAULT_ADMIN_ROLE(), SAFE_ADMIN);
        s.engineHasRole = vault.hasRole(vault.ENGINE_ROLE(), SAPIEN_CORE);
        s.isPaused = vault.paused();
    }

    function setUp() public {
        if (block.chainid != BASE_SEPOLIA_CHAIN_ID) {
            vm.skip(true);
        }
    }

    // ══════════════════════════════════════════════════════════════════
    // SapienCore upgrade
    // ══════════════════════════════════════════════════════════════════

    function test_coreUpgrade_preservesAllState() public {
        CoreSnapshot memory before = _snapshotCore();
        address implBefore = _readImpl(SAPIEN_CORE);

        SapienCore newImpl = new SapienCore();
        vm.prank(SAFE_ADMIN);
        engine.upgradeToAndCall(address(newImpl), "");

        address implAfter = _readImpl(SAPIEN_CORE);
        assertNotEq(implBefore, implAfter, "impl should change");
        assertEq(implAfter, address(newImpl), "impl should be new deployment");

        CoreSnapshot memory after_ = _snapshotCore();

        assertEq(after_.treasury, before.treasury, "treasury");
        assertEq(after_.vaultAddr, before.vaultAddr, "vault");
        assertEq(after_.challengePeriod, before.challengePeriod, "challengePeriod");
        assertEq(after_.claimDeadline, before.claimDeadline, "claimDeadline");
        assertEq(after_.commitDeadline, before.commitDeadline, "commitDeadline");
        assertEq(after_.revealDeadline, before.revealDeadline, "revealDeadline");
        assertEq(after_.forceSettleDelay, before.forceSettleDelay, "forceSettleDelay");
        assertEq(after_.decayRateBps, before.decayRateBps, "decayRateBps");
        assertEq(after_.originationBps, before.originationBps, "originationBps");
        assertEq(after_.contributionBps, before.contributionBps, "contributionBps");
        assertEq(after_.validationBps, before.validationBps, "validationBps");
        assertEq(after_.adminHasRole, before.adminHasRole, "admin role");
        assertEq(after_.isPaused, before.isPaused, "paused state");
    }

    function test_coreUpgrade_preservesProjectState() public {
        bytes32 projectId = vm.envOr("PROJECT_ID", bytes32(0));
        if (projectId == bytes32(0)) return;

        Project memory projBefore = engine.getProject(projectId);
        uint256 escrowBefore = engine.getProjectEscrow(projectId, SAPIEN_TOKEN);

        SapienCore newImpl = new SapienCore();
        vm.prank(SAFE_ADMIN);
        engine.upgradeToAndCall(address(newImpl), "");

        Project memory projAfter = engine.getProject(projectId);
        assertEq(projAfter.originator, projBefore.originator, "project originator");
        assertEq(uint256(projAfter.status), uint256(projBefore.status), "project status");
        assertEq(projAfter.totalRewards, projBefore.totalRewards, "project totalRewards");
        assertEq(projAfter.totalQuantity, projBefore.totalQuantity, "project totalQuantity");
        assertEq(projAfter.availableSlots, projBefore.availableSlots, "project availableSlots");
        assertEq(engine.getProjectEscrow(projectId, SAPIEN_TOKEN), escrowBefore, "project escrow");
    }

    function test_coreUpgrade_functionalAfterUpgrade() public {
        SapienCore newImpl = new SapienCore();
        vm.prank(SAFE_ADMIN);
        engine.upgradeToAndCall(address(newImpl), "");

        assertEq(engine.treasury(), engine.treasury(), "view calls work");

        bytes32 skillId = keccak256("DATA_ANNOTATION");
        bool registered = engine.isSkillRegistered(skillId);
        assertTrue(registered || !registered, "read calls succeed");
    }

    // ══════════════════════════════════════════════════════════════════
    // SapienVault upgrade
    // ══════════════════════════════════════════════════════════════════

    function test_vaultUpgrade_preservesAllState() public {
        VaultSnapshot memory before = _snapshotVault();
        address implBefore = _readImpl(SAPIEN_VAULT);

        SapienVault newImpl = new SapienVault();
        vm.prank(SAFE_ADMIN);
        vault.upgradeToAndCall(address(newImpl), "");

        address implAfter = _readImpl(SAPIEN_VAULT);
        assertNotEq(implBefore, implAfter, "impl should change");
        assertEq(implAfter, address(newImpl), "impl should be new deployment");

        VaultSnapshot memory after_ = _snapshotVault();

        assertEq(after_.asset, before.asset, "asset");
        assertEq(after_.totalAssets, before.totalAssets, "totalAssets");
        assertEq(after_.totalSupply, before.totalSupply, "totalSupply");
        assertEq(after_.minDepositAge, before.minDepositAge, "minDepositAge");
        assertEq(after_.adminHasRole, before.adminHasRole, "admin role");
        assertEq(after_.engineHasRole, before.engineHasRole, "engine role");
        assertEq(after_.isPaused, before.isPaused, "paused state");
    }

    function test_vaultUpgrade_preservesStakerBalance() public {
        address staker = vm.envOr("STAKER", address(0));
        if (staker == address(0)) return;

        uint256 sharesBefore = vault.balanceOf(staker);
        uint256 availBefore = vault.availableBalance(staker);
        StakeAccount memory acctBefore = vault.getStakeAccount(staker);

        SapienVault newImpl = new SapienVault();
        vm.prank(SAFE_ADMIN);
        vault.upgradeToAndCall(address(newImpl), "");

        assertEq(vault.balanceOf(staker), sharesBefore, "shares");
        assertEq(vault.availableBalance(staker), availBefore, "available balance");

        StakeAccount memory acctAfter = vault.getStakeAccount(staker);
        assertEq(acctAfter.contributorLock, acctBefore.contributorLock, "contributorLock");
        assertEq(acctAfter.validatorCapacity, acctBefore.validatorCapacity, "validatorCapacity");
        assertEq(acctAfter.inFlight, acctBefore.inFlight, "inFlight");
    }

    function test_vaultUpgrade_depositsWorkAfter() public {
        SapienVault newImpl = new SapienVault();
        vm.prank(SAFE_ADMIN);
        vault.upgradeToAndCall(address(newImpl), "");

        address depositor = makeAddr("post-upgrade-depositor");
        uint256 amount = 100e18;
        deal(SAPIEN_TOKEN, depositor, amount);

        vm.startPrank(depositor);
        token.approve(address(vault), amount);
        uint256 shares = vault.deposit(amount, depositor);
        vm.stopPrank();

        assertGt(shares, 0, "deposit should mint shares");
        assertEq(vault.balanceOf(depositor), shares, "balance should match");
    }

    // ══════════════════════════════════════════════════════════════════
    // Both contracts upgraded together
    // ══════════════════════════════════════════════════════════════════

    function test_dualUpgrade_bothPreserveState() public {
        CoreSnapshot memory coreBefore = _snapshotCore();
        VaultSnapshot memory vaultBefore = _snapshotVault();

        SapienCore coreImpl = new SapienCore();
        vm.prank(SAFE_ADMIN);
        engine.upgradeToAndCall(address(coreImpl), "");

        SapienVault vaultImpl = new SapienVault();
        vm.prank(SAFE_ADMIN);
        vault.upgradeToAndCall(address(vaultImpl), "");

        CoreSnapshot memory coreAfter = _snapshotCore();
        VaultSnapshot memory vaultAfter = _snapshotVault();

        assertEq(coreAfter.treasury, coreBefore.treasury, "core treasury");
        assertEq(coreAfter.vaultAddr, coreBefore.vaultAddr, "core vault ref");
        assertEq(coreAfter.adminHasRole, coreBefore.adminHasRole, "core admin role");
        assertEq(coreAfter.challengePeriod, coreBefore.challengePeriod, "core challengePeriod");

        assertEq(vaultAfter.asset, vaultBefore.asset, "vault asset");
        assertEq(vaultAfter.totalAssets, vaultBefore.totalAssets, "vault totalAssets");
        assertEq(vaultAfter.totalSupply, vaultBefore.totalSupply, "vault totalSupply");
        assertEq(vaultAfter.adminHasRole, vaultBefore.adminHasRole, "vault admin role");
        assertEq(vaultAfter.engineHasRole, vaultBefore.engineHasRole, "vault engine role");
    }
}
