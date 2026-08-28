// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

import {
    AccessControlDefaultAdminRules
} from "lib/openzeppelin-contracts/contracts/access/extensions/AccessControlDefaultAdminRules.sol";
import {ISapienAttestationRegistry} from "src/interfaces/ISapienAttestationRegistry.sol";

/// @title SapienAttestationRegistry
/// @notice Dedicated M4 hang-point for PoQ proof-report roots on a single chain.
/// @dev Not a vault extension and not upgradeable. The live `SapienVault` UUPS
///      proxy is unchanged; this contract stores only `(reportId → roots/kid)`.
///      Off-chain `attestation.registry` is the structured locator
///      `{chain, address, tx}` — never the string `"onchain"`.
contract SapienAttestationRegistry is AccessControlDefaultAdminRules, ISapienAttestationRegistry {
    /// @notice Role permitted to call `attest`. Held by the PoQ engine (or a
    ///         dedicated report-issuer key), not by the vault.
    bytes32 public constant ISSUER_ROLE = keccak256("ISSUER_ROLE");

    /// @notice Initial delay between scheduling and accepting a
    ///         `DEFAULT_ADMIN_ROLE` transfer. Matches the vault's S2 default.
    uint48 public constant DEFAULT_ADMIN_TRANSFER_DELAY = 3 days;

    mapping(bytes32 reportId => Attestation) private _attestations;
    mapping(bytes32 kid => bool) private _revokedKids;

    /// @param admin_ Single `DEFAULT_ADMIN_ROLE` holder (governance Safe).
    /// @param issuer_ Optional first `ISSUER_ROLE` holder; `address(0)` skips
    ///        the grant so admin can install the engine later.
    constructor(address admin_, address issuer_) AccessControlDefaultAdminRules(DEFAULT_ADMIN_TRANSFER_DELAY, admin_) {
        if (issuer_ != address(0)) {
            _grantRole(ISSUER_ROLE, issuer_);
        }
    }

    /// @inheritdoc ISapienAttestationRegistry
    function attest(bytes32 reportId, bytes32 root, bytes32 scoreRoot, bytes32 kid, uint64 issuedAt)
        external
        onlyRole(ISSUER_ROLE)
    {
        if (reportId == bytes32(0)) revert ZeroReportId();
        if (root == bytes32(0)) revert ZeroRoot();
        if (scoreRoot == bytes32(0)) revert ZeroScoreRoot();
        if (kid == bytes32(0)) revert ZeroKid();
        if (issuedAt == 0) revert ZeroIssuedAt();
        if (_revokedKids[kid]) revert KidRevoked(kid);
        if (_attestations[reportId].root != bytes32(0)) revert AlreadyAttested(reportId);

        _attestations[reportId] =
            Attestation({root: root, scoreRoot: scoreRoot, kid: kid, issuedAt: issuedAt, issuer: msg.sender});

        emit Attested(reportId, root, kid, scoreRoot, issuedAt, msg.sender);
    }

    /// @inheritdoc ISapienAttestationRegistry
    function revokeKid(bytes32 kid) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (kid == bytes32(0)) revert ZeroKid();
        if (_revokedKids[kid]) revert KidAlreadyRevoked(kid);
        _revokedKids[kid] = true;
        emit SigningKeyRevoked(kid, msg.sender);
    }

    /// @inheritdoc ISapienAttestationRegistry
    function getAttestation(bytes32 reportId) external view returns (Attestation memory) {
        return _attestations[reportId];
    }

    /// @inheritdoc ISapienAttestationRegistry
    function attestationRoot(bytes32 reportId) external view returns (bytes32) {
        return _attestations[reportId].root;
    }

    /// @inheritdoc ISapienAttestationRegistry
    function isKidRevoked(bytes32 kid) external view returns (bool) {
        return _revokedKids[kid];
    }

    /// @inheritdoc ISapienAttestationRegistry
    function isValid(bytes32 reportId) external view returns (bool) {
        Attestation storage row = _attestations[reportId];
        return row.root != bytes32(0) && !_revokedKids[row.kid];
    }

    /// @inheritdoc ISapienAttestationRegistry
    function hashId(string calldata value) external pure returns (bytes32) {
        return keccak256(bytes(value));
    }
}
