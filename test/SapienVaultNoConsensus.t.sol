// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Test} from "forge-std/Test.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "lib/openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import {SapienVault} from "src/SapienVault.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";

/// @title Vault does not compute consensus
/// @notice Issue #167: no scoring / quorum / consensus entrypoints on
///         `SapienVault` or `ISapienVault`. Adding one fails this suite.
contract SapienVaultNoConsensusTest is Test {
    SapienVault internal vault;

    function setUp() public {
        MockERC20 token = new MockERC20("Sapien Token", "SAPIEN");
        SapienVault impl = new SapienVault();
        vault = SapienVault(
            address(
                new ERC1967Proxy(
                    address(impl), abi.encodeCall(SapienVault.initialize, (IERC20(address(token)), address(this)))
                )
            )
        );
    }

    /// @notice Source scan: `function <forbidden>` must not appear on the vault
    ///         or its interface. Comments that mention "consensus" are allowed
    ///         (the interface already describes slashing as an engine decision).
    function test_sourceHasNoConsensusEntrypoints() public view {
        _assertNoForbiddenFunctions(vm.readFile("src/SapienVault.sol"));
        _assertNoForbiddenFunctions(vm.readFile("src/interfaces/ISapienVault.sol"));
    }

    /// @notice Selector probe: unrecognized scoring / quorum functions revert
    ///         (no fallback on the implementation; the proxy delegates that revert).
    function test_selectorsHaveNoConsensusEntrypoints() public {
        bytes4[10] memory forbidden = [
            bytes4(keccak256("computeConsensus()")),
            bytes4(keccak256("computeConsensus(uint256)")),
            bytes4(keccak256("computeQuorum()")),
            bytes4(keccak256("quorum()")),
            bytes4(keccak256("score(address)")),
            bytes4(keccak256("getScore(address)")),
            bytes4(keccak256("setScore(address,uint256)")),
            bytes4(keccak256("submitScore(address,uint256)")),
            bytes4(keccak256("getQuorum()")),
            bytes4(keccak256("setQuorum(uint256)"))
        ];
        for (uint256 i; i < forbidden.length; ++i) {
            (bool ok,) = address(vault).staticcall(abi.encodePacked(forbidden[i]));
            assertFalse(ok, "vault answered a consensus/scoring/quorum selector");
        }
    }

    /// @notice Mainnet deployment pins stay exactly the live rewards vault.
    function test_mainnetDeploymentPinsUnchanged() public view {
        string memory json = vm.readFile("deployments/base-mainnet.json");
        assertEq(vm.parseJsonAddress(json, ".vaultAddress"), 0x60Bf63729f688287a450299962b36Cef0aFfaa42);
        assertEq(vm.parseJsonAddress(json, ".sapienAddress"), 0xC729777d0470F30612B1564Fd96E8Dd26f5814E3);
        assertEq(vm.parseJsonAddress(json, ".usdcAddress"), 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913);
        assertEq(vm.parseJsonUint(json, ".chainId"), 8453);
    }

    /// @notice Sepolia wiring targets the live V2 UUPS, not a new proxy.
    function test_sepoliaDeploymentPinsLiveV2() public view {
        string memory json = vm.readFile("deployments/base-sepolia.json");
        assertEq(vm.parseJsonAddress(json, ".vaultAddress"), 0x58E72Fa7fb92B100f2c652377465EEEe2642544C);
        assertEq(vm.parseJsonAddress(json, ".sapienAddress"), 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6);
        assertEq(vm.parseJsonUint(json, ".chainId"), 84532);
    }

    function _assertNoForbiddenFunctions(string memory src) internal pure {
        string[10] memory needles = [
            "function computeConsensus",
            "function computeQuorum",
            "function quorum(",
            "function quorum (",
            "function score(",
            "function score (",
            "function getScore",
            "function setScore",
            "function submitScore",
            "function getQuorum"
        ];
        for (uint256 i; i < needles.length; ++i) {
            require(!_contains(src, needles[i]), "forbidden consensus/scoring/quorum function");
        }
    }

    function _contains(string memory hay, string memory needle) internal pure returns (bool) {
        bytes memory h = bytes(hay);
        bytes memory n = bytes(needle);
        if (n.length == 0 || n.length > h.length) return false;
        uint256 end = h.length - n.length;
        for (uint256 i; i <= end; ++i) {
            bool found = true;
            for (uint256 j; j < n.length; ++j) {
                if (h[i + j] != n[j]) {
                    found = false;
                    break;
                }
            }
            if (found) return true;
        }
        return false;
    }
}
