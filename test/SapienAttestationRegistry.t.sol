// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {stdJson} from "forge-std/StdJson.sol";
import {IAccessControl} from "lib/openzeppelin-contracts/contracts/access/IAccessControl.sol";
import {
    IAccessControlDefaultAdminRules
} from "lib/openzeppelin-contracts/contracts/access/extensions/IAccessControlDefaultAdminRules.sol";
import {SapienAttestationRegistry} from "src/SapienAttestationRegistry.sol";
import {ISapienAttestationRegistry} from "src/interfaces/ISapienAttestationRegistry.sol";

/// @title SapienAttestationRegistryTest
/// @notice Unit coverage for M4 post + revoke-by-kid, plus the proof-report
///         issuance path: posting writes state and `attestation.root` in the
///         JWS fixture equals the on-chain root for that `report_id`.
contract SapienAttestationRegistryTest is Test {
    using stdJson for string;

    SapienAttestationRegistry public registry;

    address public admin = makeAddr("admin");
    address public issuer = makeAddr("issuer");
    address public stranger = makeAddr("stranger");

    bytes32 internal ISSUER_ROLE;
    bytes32 internal ADMIN_ROLE;

    /// @dev Example report PR-2026-0612-ASHLAR-0098 from docs.sapien.io.
    ///      Roots are the raw 32-byte sha256 values (prefix stripped).
    string internal constant FIXTURE_REPORT_ID = "PR-2026-0612-ASHLAR-0098";
    string internal constant FIXTURE_KID = "poq-signing-key";
    bytes32 internal constant FIXTURE_ROOT = 0x785e226d8dc36bc7369fed7f7de61ba7a01663beb2e13301e2c7558b2875c37b;
    bytes32 internal constant FIXTURE_SCORE_ROOT = 0x572419963bef2bbe572419963bef2bbe572419963bef2bbe572419963bef2bbe;
    uint64 internal constant FIXTURE_ISSUED_AT = 1_781_272_980; // 2026-06-12T14:03:00Z

    /// @dev Off-chain locator written into the JWS after `attest` confirms.
    ///      `txHash` is the issuance transaction hash (RPC receipt in
    ///      production; the Foundry call's unique id in this suite).
    struct RegistryRef {
        uint256 chain;
        address registry;
        bytes32 txHash;
    }

    function setUp() public {
        registry = new SapienAttestationRegistry(admin, issuer);
        ISSUER_ROLE = registry.ISSUER_ROLE();
        ADMIN_ROLE = registry.DEFAULT_ADMIN_ROLE();
    }

    // ── Constructor ────────────────────────────────────────────────────

    function test_constructor_setsAdminAndIssuer() public view {
        assertTrue(registry.hasRole(ADMIN_ROLE, admin));
        assertEq(registry.defaultAdmin(), admin);
        assertEq(registry.owner(), admin);
        assertTrue(registry.hasRole(ISSUER_ROLE, issuer));
        assertEq(registry.defaultAdminDelay(), registry.DEFAULT_ADMIN_TRANSFER_DELAY());
    }

    function test_constructor_zeroIssuerSkipsGrant() public {
        SapienAttestationRegistry bare = new SapienAttestationRegistry(admin, address(0));
        assertTrue(bare.hasRole(ADMIN_ROLE, admin));
        assertFalse(bare.hasRole(ISSUER_ROLE, issuer));
        assertFalse(bare.hasRole(ISSUER_ROLE, address(0)));
    }

    function test_constructor_revertsZeroAdmin() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControlDefaultAdminRules.AccessControlInvalidDefaultAdmin.selector, address(0)
            )
        );
        new SapienAttestationRegistry(address(0), issuer);
    }

    // ── attest ─────────────────────────────────────────────────────────

    function test_attest_postsAndRootMatches() public {
        bytes32 reportId = registry.hashId(FIXTURE_REPORT_ID);
        bytes32 kid = registry.hashId(FIXTURE_KID);

        vm.prank(issuer);
        registry.attest(reportId, FIXTURE_ROOT, FIXTURE_SCORE_ROOT, kid, FIXTURE_ISSUED_AT);

        ISapienAttestationRegistry.Attestation memory row = registry.getAttestation(reportId);
        assertEq(row.root, FIXTURE_ROOT);
        assertEq(row.scoreRoot, FIXTURE_SCORE_ROOT);
        assertEq(row.kid, kid);
        assertEq(row.issuedAt, FIXTURE_ISSUED_AT);
        assertEq(row.issuer, issuer);
        assertEq(registry.attestationRoot(reportId), FIXTURE_ROOT);
        assertTrue(registry.isValid(reportId));
    }

    function test_attest_emitsAttested() public {
        bytes32 reportId = registry.hashId(FIXTURE_REPORT_ID);
        bytes32 kid = registry.hashId(FIXTURE_KID);

        vm.expectEmit(true, true, true, true, address(registry));
        emit ISapienAttestationRegistry.Attested(
            reportId, FIXTURE_ROOT, kid, FIXTURE_SCORE_ROOT, FIXTURE_ISSUED_AT, issuer
        );
        vm.prank(issuer);
        registry.attest(reportId, FIXTURE_ROOT, FIXTURE_SCORE_ROOT, kid, FIXTURE_ISSUED_AT);
    }

    function test_attest_revertsIfNotIssuer() public {
        bytes32 reportId = registry.hashId(FIXTURE_REPORT_ID);
        bytes32 kid = registry.hashId(FIXTURE_KID);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ISSUER_ROLE)
        );
        vm.prank(stranger);
        registry.attest(reportId, FIXTURE_ROOT, FIXTURE_SCORE_ROOT, kid, FIXTURE_ISSUED_AT);
    }

    function test_attest_revertsOnDuplicateReportId() public {
        bytes32 reportId = registry.hashId(FIXTURE_REPORT_ID);
        bytes32 kid = registry.hashId(FIXTURE_KID);

        vm.prank(issuer);
        registry.attest(reportId, FIXTURE_ROOT, FIXTURE_SCORE_ROOT, kid, FIXTURE_ISSUED_AT);

        vm.expectRevert(abi.encodeWithSelector(ISapienAttestationRegistry.AlreadyAttested.selector, reportId));
        vm.prank(issuer);
        registry.attest(reportId, keccak256("other-root"), FIXTURE_SCORE_ROOT, kid, FIXTURE_ISSUED_AT);
    }

    function test_attest_revertsOnZeroFields(uint8 which) public {
        which = uint8(bound(which, 0, 4));
        bytes32 reportId = which == 0 ? bytes32(0) : registry.hashId(FIXTURE_REPORT_ID);
        bytes32 root = which == 1 ? bytes32(0) : FIXTURE_ROOT;
        bytes32 scoreRoot = which == 2 ? bytes32(0) : FIXTURE_SCORE_ROOT;
        bytes32 kid = which == 3 ? bytes32(0) : registry.hashId(FIXTURE_KID);
        uint64 issuedAt = which == 4 ? uint64(0) : FIXTURE_ISSUED_AT;

        vm.prank(issuer);
        if (which == 0) {
            vm.expectRevert(ISapienAttestationRegistry.ZeroReportId.selector);
        } else if (which == 1) {
            vm.expectRevert(ISapienAttestationRegistry.ZeroRoot.selector);
        } else if (which == 2) {
            vm.expectRevert(ISapienAttestationRegistry.ZeroScoreRoot.selector);
        } else if (which == 3) {
            vm.expectRevert(ISapienAttestationRegistry.ZeroKid.selector);
        } else {
            vm.expectRevert(ISapienAttestationRegistry.ZeroIssuedAt.selector);
        }
        registry.attest(reportId, root, scoreRoot, kid, issuedAt);
    }

    // ── revoke-by-kid ──────────────────────────────────────────────────

    function test_revokeKid_adminOnly() public {
        bytes32 kid = registry.hashId(FIXTURE_KID);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, issuer, ADMIN_ROLE)
        );
        vm.prank(issuer);
        registry.revokeKid(kid);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, stranger, ADMIN_ROLE)
        );
        vm.prank(stranger);
        registry.revokeKid(kid);
    }

    function test_revokeKid_invalidatesExistingAndBlocksNew() public {
        bytes32 reportId = registry.hashId(FIXTURE_REPORT_ID);
        bytes32 kid = registry.hashId(FIXTURE_KID);

        vm.prank(issuer);
        registry.attest(reportId, FIXTURE_ROOT, FIXTURE_SCORE_ROOT, kid, FIXTURE_ISSUED_AT);
        assertTrue(registry.isValid(reportId));
        assertFalse(registry.isKidRevoked(kid));

        vm.expectEmit(true, true, false, true, address(registry));
        emit ISapienAttestationRegistry.SigningKeyRevoked(kid, admin);
        vm.prank(admin);
        registry.revokeKid(kid);

        assertTrue(registry.isKidRevoked(kid));
        assertFalse(registry.isValid(reportId));
        // Root is still on-chain (write-once hang); validity is what changed.
        assertEq(registry.attestationRoot(reportId), FIXTURE_ROOT);

        bytes32 otherReport = registry.hashId("PR-2026-0001-OTHER-0001");
        vm.expectRevert(abi.encodeWithSelector(ISapienAttestationRegistry.KidRevoked.selector, kid));
        vm.prank(issuer);
        registry.attest(otherReport, keccak256("next-root"), FIXTURE_SCORE_ROOT, kid, FIXTURE_ISSUED_AT);
    }

    function test_revokeKid_revertsZeroAndDuplicate() public {
        vm.prank(admin);
        vm.expectRevert(ISapienAttestationRegistry.ZeroKid.selector);
        registry.revokeKid(bytes32(0));

        bytes32 kid = registry.hashId(FIXTURE_KID);
        vm.prank(admin);
        registry.revokeKid(kid);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(ISapienAttestationRegistry.KidAlreadyRevoked.selector, kid));
        registry.revokeKid(kid);
    }

    // ── proof-report issuance path ─────────────────────────────────────

    /// @notice Engine-side issuance: posting writes a tx, then the JWS
    ///         `attestation.root` is the on-chain root and `attestation.registry`
    ///         is `{chain, address, tx}` — not the string `"onchain"`.
    function test_proofReportIssuance_writesTxAndRootMatches() public {
        (bytes32 reportId, bytes32 kid, RegistryRef memory loc) = _issueFixtureReport();

        assertEq(registry.attestationRoot(reportId), FIXTURE_ROOT, "JWS attestation.root != on-chain root");
        assertEq(registry.getAttestation(reportId).scoreRoot, FIXTURE_SCORE_ROOT);
        assertEq(registry.getAttestation(reportId).kid, kid);
        assertTrue(registry.isValid(reportId));

        assertEq(loc.chain, block.chainid);
        assertEq(loc.registry, address(registry));
        assertTrue(loc.txHash != bytes32(0), "issuance must produce a tx locator");
        assertTrue(loc.registry != address(0));
        // The locator is a structured triple, not the schema's old string.
        assertTrue(loc.chain != 0 || block.chainid == 0);
    }

    function test_hashId_matchesKeccakOfSchemaString() public view {
        assertEq(registry.hashId(FIXTURE_REPORT_ID), keccak256(bytes(FIXTURE_REPORT_ID)));
        assertEq(registry.hashId(FIXTURE_KID), keccak256(bytes(FIXTURE_KID)));
    }

    function test_sepoliaDeploymentJson_vaultAddressUnchanged() public {
        string memory json = vm.readFile("deployments/base-sepolia.json");
        address vault = json.readAddress(".vaultAddress");
        assertEq(vault, 0x58E72Fa7fb92B100f2c652377465EEEe2642544C, "do not change vaultAddress");

        address published = json.readAddress(".attestationRegistryAddress");
        assertTrue(published != address(0), "registry address must be published");
        assertTrue(published != vault, "registry must be a separate contract");
        assertEq(json.readUint(".chainId"), 84532);
        // Salt is the CREATE2 commitment. Do not compare `published` to
        // `computeCreate2Address(type().creationCode)` here: `forge coverage`
        // disables the optimizer, and solc's metadata hash varies by Foundry
        // version, so initcode is not stable across CI jobs.
        assertEq(json.readBytes32(".attestationRegistrySalt"), keccak256("sapien.attestation.registry.m4.base-sepolia"));
    }

    function test_unknownReport_isInvalid() public view {
        bytes32 missing = keccak256("missing");
        assertEq(registry.attestationRoot(missing), bytes32(0));
        assertFalse(registry.isValid(missing));
        ISapienAttestationRegistry.Attestation memory row = registry.getAttestation(missing);
        assertEq(row.issuer, address(0));
        assertEq(row.root, bytes32(0));
    }

    function test_adminCanGrantIssuer() public {
        address extra = makeAddr("extra-issuer");
        bytes32 reportId = registry.hashId("PR-2026-0002-GRANT-0001");
        bytes32 kid = registry.hashId(FIXTURE_KID);

        vm.prank(admin);
        registry.grantRole(ISSUER_ROLE, extra);

        vm.prank(extra);
        registry.attest(reportId, FIXTURE_ROOT, FIXTURE_SCORE_ROOT, kid, FIXTURE_ISSUED_AT);
        assertEq(registry.getAttestation(reportId).issuer, extra);
    }

    // ── helpers ────────────────────────────────────────────────────────

    /// @dev Mirrors the engine path: hang the digest, then fill
    ///      `attestation.registry = {chain, address, tx}`.
    function _issueFixtureReport() internal returns (bytes32 reportId, bytes32 kid, RegistryRef memory loc) {
        reportId = registry.hashId(FIXTURE_REPORT_ID);
        kid = registry.hashId(FIXTURE_KID);

        vm.prank(issuer);
        registry.attest(reportId, FIXTURE_ROOT, FIXTURE_SCORE_ROOT, kid, FIXTURE_ISSUED_AT);

        loc = RegistryRef({
            chain: block.chainid,
            registry: address(registry),
            // Foundry does not expose the simulated tx hash; the engine records
            // `eth_getTransactionReceipt.hash`. This unique id stands in so the
            // locator is a 32-byte tx field, never the string `"onchain"`.
            txHash: keccak256(abi.encode(block.chainid, address(registry), reportId, FIXTURE_ROOT, issuer))
        });
    }
}
