// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployableERC20} from "./mocks/DeployableERC20.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";

/// @notice Deploys tokens (SAPIEN, USDC), SapienVault, SapienCore to Anvil, writes local.json.
contract DeployAnvil is Script {
    function run() external {
        uint256 deployerPrivateKey =
            vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        DeployableERC20 sapien = new DeployableERC20("Sapien", "SAPIEN", 18);
        DeployableERC20 usdc = new DeployableERC20("USD Coin", "USDC", 6);

        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInit = abi.encodeCall(SapienVault.initialize, (IERC20(address(sapien)), deployer));
        SapienVault vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));

        SapienCore engineImpl = new SapienCore();
        bytes memory engineInit = abi.encodeCall(SapienCore.initialize, (deployer, address(vault), deployer));
        SapienCore engine = SapienCore(address(new ERC1967Proxy(address(engineImpl), engineInit)));

        vault.grantRole(vault.ENGINE_ROLE(), address(engine));

        vm.stopBroadcast();

        string memory obj = "contracts";
        vm.serializeAddress(obj, "SAPIEN", address(sapien));
        vm.serializeAddress(obj, "USDC", address(usdc));
        vm.serializeAddress(obj, "SapienVault", address(vault));
        string memory json = vm.serializeAddress(obj, "SapienCore", address(engine));
        vm.writeJson(json, "deployments/local.json");
    }
}
