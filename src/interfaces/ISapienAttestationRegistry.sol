// SPDX-License-Identifier: MIT
pragma solidity 0.8.36;

/// @title ISapienAttestationRegistry
/// @notice On-chain hang-point for PoQ proof-report roots (M4). Independent of
///         `SapienVault` — the vault never stores report roots or consensus.
/// @dev `reportId` and `kid` are `keccak256` of the UTF-8 schema strings
///      (`report_id`, `attestation.signing_key_id`). `root` / `scoreRoot` are
///      the raw 32-byte hashes from `attestation.root` / `attestation.score_root`
///      (strip a `sha256:` prefix off-chain; do not hash again).
interface ISapienAttestationRegistry {
    // ── Errors ─────────────────────────────────────────────────────────

    error ZeroReportId();
    error ZeroRoot();
    error ZeroScoreRoot();
    error ZeroKid();
    error ZeroIssuedAt();
    /// @notice `reportId` already has a write-once attestation.
    error AlreadyAttested(bytes32 reportId);
    /// @notice The signing-key id has been revoked; new posts are rejected and
    ///         existing attestations with this `kid` are no longer valid.
    error KidRevoked(bytes32 kid);
    error KidAlreadyRevoked(bytes32 kid);

    // ── Types ──────────────────────────────────────────────────────────

    /// @notice One proof-report attestation. Packed into four storage slots.
    /// @dev `issuedAt` is the report's `issued_at` as a Unix timestamp, not
    ///      `block.timestamp`. `issuer` is the `ISSUER_ROLE` account that posted.
    struct Attestation {
        bytes32 root;
        bytes32 scoreRoot;
        bytes32 kid;
        uint64 issuedAt;
        address issuer;
    }

    // ── Events ─────────────────────────────────────────────────────────

    /// @notice A proof-report root was hung on-chain. The posting transaction
    ///         hash is the `tx` field of off-chain `attestation.registry`.
    /// @param reportId `keccak256(bytes(report_id))`.
    /// @param root Raw 32-byte `attestation.root` (must equal the JWS value).
    /// @param kid `keccak256(bytes(signing_key_id))`.
    /// @param scoreRoot Raw 32-byte `attestation.score_root`.
    /// @param issuedAt Report `issued_at` as Unix seconds.
    /// @param issuer `ISSUER_ROLE` account that posted.
    event Attested(
        bytes32 indexed reportId,
        bytes32 indexed root,
        bytes32 indexed kid,
        bytes32 scoreRoot,
        uint64 issuedAt,
        address issuer
    );

    /// @notice Admin revoked a signing-key id. Every attestation posted under
    ///         that `kid` becomes invalid; further `attest` calls with it revert.
    event SigningKeyRevoked(bytes32 indexed kid, address indexed account);

    // ── Writes ─────────────────────────────────────────────────────────

    /// @notice Post a write-once attestation for `reportId`.
    /// @dev Reverts if any field is zero, `reportId` is already attested, or
    ///      `kid` has been revoked. `ISSUER_ROLE` only.
    function attest(bytes32 reportId, bytes32 root, bytes32 scoreRoot, bytes32 kid, uint64 issuedAt) external;

    /// @notice Permanently revoke a signing-key id. `DEFAULT_ADMIN_ROLE` only.
    function revokeKid(bytes32 kid) external;

    // ── Views ──────────────────────────────────────────────────────────

    /// @notice Full attestation row, or a zero struct if `reportId` was never posted.
    function getAttestation(bytes32 reportId) external view returns (Attestation memory);

    /// @notice `attestation.root` for `reportId`, or `bytes32(0)` if unknown.
    function attestationRoot(bytes32 reportId) external view returns (bytes32);

    /// @notice Whether admin has revoked this signing-key id.
    function isKidRevoked(bytes32 kid) external view returns (bool);

    /// @notice True when `reportId` has been posted and its `kid` is not revoked.
    function isValid(bytes32 reportId) external view returns (bool);

    /// @notice `keccak256` of a schema string (`report_id` or `signing_key_id`).
    function hashId(string calldata value) external pure returns (bytes32);
}
