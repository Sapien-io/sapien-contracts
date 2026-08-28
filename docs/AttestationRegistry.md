# Sapien Attestation Registry (M4)

Dedicated on-chain hang-point for PoQ proof-report roots. **Not** part of
`SapienVault`, **not** EAS, and **not** a consensus engine. The Sepolia vault
stays at UUPS `0x58E72Fa7fb92B100f2c652377465EEEe2642544C`.

A report root that lives only in a JWS can be rotated away. Issuing a
proof-report now writes a transaction first; `attestation.root` in the signed
payload is the value stored under that `report_id`.

---

## Why a separate contract

The vault is an ERC-4626 asset-lock and slash tool. Overloading it with report
roots would mix collateral accounting with attestation history and force a
vault upgrade for a feature that does not touch user funds. M4 is therefore a
new, non-upgradeable `SapienAttestationRegistry` published next to the vault in
`deployments/base-sepolia.json`.

Mainnet is out of scope. So is copying attestations to EAS — that is a
follow-up after this registry exists.

---

## Roles

| Role | Holder | Capabilities |
|------|--------|--------------|
| `DEFAULT_ADMIN_ROLE` | Same Sepolia Safe as the vault (`0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC`) | Grant / revoke `ISSUER_ROLE`, two-step admin handover, **`revokeKid`** |
| `ISSUER_ROLE` | PoQ engine (or a dedicated report-issuer key) | **`attest`** only |

Admin rules are `AccessControlDefaultAdminRules` (single admin, 3-day
time-locked handover, renounce disabled) — the same S2 posture as the vault,
without sharing storage or a proxy.

`ISSUER_ROLE` is intentionally **not** named `ENGINE_ROLE`. The slash/unlock
key and the report-issuer key may be the same address, but they do not have to
be; the Safe grants the issuer after deploy.

---

## Data model

`attest(reportId, root, scoreRoot, kid, issuedAt)` is write-once per
`reportId`. Zero fields revert. A revoked `kid` cannot be posted.

| On-chain field | Schema source | Encoding |
|----------------|---------------|----------|
| `reportId` | `report_id` (e.g. `PR-2026-0612-ASHLAR-0098`) | `keccak256(bytes(report_id))` |
| `root` | `attestation.root` | Raw 32-byte hash. Strip a `sha256:` prefix off-chain; do not hash again. This is the JWS value. |
| `scoreRoot` | `attestation.score_root` | Same as `root`. |
| `kid` | `attestation.signing_key_id` | `keccak256(bytes(signing_key_id))` |
| `issuedAt` | `issued_at` | Unix seconds (`uint64`). |
| `issuer` | (implicit) | `msg.sender` of the successful `attest` call. |

`hashId(string)` on the contract is the canonical keccak helper for `report_id`
and `signing_key_id`.

---

## Issuance path

The engine (or issuer role) hangs the digest **before** signing the JWS:

1. Finalize the report payload (`report_id`, roots, `signing_key_id`, `issued_at`).
2. `attest(hashId(report_id), root, score_root, hashId(signing_key_id), issued_at_unix)`.
3. Read the transaction hash from the receipt.
4. Set `attestation.root` (and `score_root`) in the JWS to the **same** 32-byte
   values that were posted. A verifier checks
   `registry.attestationRoot(hashId(report_id)) == attestation.root`.
5. Set `attestation.registry` to the structured locator — **not** the string
   `"onchain"`:

```json
"attestation": {
  "root": "0x785e226d8dc36bc7369fed7f7de61ba7a01663beb2e13301e2c7558b2875c37b",
  "score_root": "0x572419963bef2bbe572419963bef2bbe572419963bef2bbe572419963bef2bbe",
  "signing_key_id": "poq-signing-key",
  "registry": {
    "chain": 84532,
    "address": "<attestationRegistryAddress>",
    "tx": "0x<attest transaction hash>"
  }
}
```

`chain` is the EIP-155 chain id (Base Sepolia = `84532`). `address` is this
registry. `tx` is the `attest` transaction hash.

Equivalent names (`chainId` / `registry` / `transactionHash`) are fine as long
as the three values are present. The string `"onchain"` is not a locator.

A Foundry fixture that walks this path (post → root match → `{chain, address, tx}`)
lives in `test/SapienAttestationRegistry.t.sol` and
`test/fixtures/poq-attestation-registry.json`. This environment cannot broadcast
to Sepolia; the unit test is the issuance proof until someone runs
`make deploy-registry-sepolia`.

---

## Revoke-by-kid

`revokeKid(kid)` is `DEFAULT_ADMIN_ROLE` only and is permanent.

- Existing rows stay in storage (the hang is write-once) but `isValid(reportId)`
  becomes `false`.
- Further `attest` calls with that `kid` revert `KidRevoked`.
- Rotate to a new `signing_key_id` and grant it as usual.

This is the on-chain revocation list the schema comment was waiting on
(“absent until the validator/revocation registry exists (M4)”).

---

## Schema follow-up (poq-monorepo)

`proofreport/schema.go` is not in this repository (and the poq-monorepo is not
in the public Sapien-io org). A follow-up there should:

1. Change `attestation.registry` from an optional string to an object
   `{chain, address, tx}` (or equivalent).
2. Delete the comment that omits the field “until the validator/revocation
   registry exists (M4)”.
3. Emit the locator on every issued proof-report after the issuer tx confirms.

---

## Deploy (Base Sepolia only)

Published CREATE2 address (Base Sepolia):
`0xcA73E30aC334cc254672c96dA56A3cc59733F805`.

CREATE2 via Foundry's default factory
(`0x4e59b44847b379578588920cA78FbF26c0B4956C`) and salt
`keccak256("sapien.attestation.registry.m4.base-sepolia")`. Constructor args
are fixed so the address is independent of the broadcasting EOA:

- `admin_` = `0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC` (dev Safe)
- `issuer_` = `address(0)` — Safe grants `ISSUER_ROLE` after deploy

```bash
make deploy-registry-sepolia-dry   # predict / simulate
make deploy-registry-sepolia       # broadcast + write deployments/base-sepolia.json
```

The script refuses to run on any chain other than 84532 and never writes
`vaultAddress`. After a successful broadcast, grant `ISSUER_ROLE` from the Safe.

---

## Out of scope

- Mainnet deploy; the mainnet vault `0x60Bf63729f688287a450299962b36Cef0aFfaa42` is untouched.
- EAS export.
- Vault storage, slashing, or any consensus logic on `SapienVault`.
