// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";

/// @title SEC-M-06 FIX VERIFICATION: verifyStorageLocation uses correct hash derivation
/// @notice Verifies that SapienVault.verifyStorageLocation() now works correctly after
///         replacing the buggy inline assembly (wrong length: 30 instead of 25) with
///         Solidity-level keccak256.
contract SEC_M_06_WrongHashLength is BaseTest {
    function test_verifyStorageLocationSucceeds() public view {
        // FIX VERIFIED: verifyStorageLocation now computes the correct hash
        // and returns true, instead of reverting with OOG
        assertTrue(vault.verifyStorageLocation(), "verifyStorageLocation should return true");
    }

    function test_correctHashDerivationMatches() public pure {
        bytes32 correctHash = keccak256("sapien.storage.StakeVault");
        bytes32 derived = keccak256(abi.encode(uint256(correctHash) - 1));
        bytes32 expected = derived & ~bytes32(uint256(0xff));

        bytes32 hardcoded = bytes32(uint256(0x0745d816f844b8d3ebe69904ebcd305a06dedec42070def1e397b29c2e74a900));
        assertEq(expected, hardcoded, "off-chain derivation matches hardcoded slot");
    }
}
