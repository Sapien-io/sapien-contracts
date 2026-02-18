// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployableERC20} from "./mocks/DeployableERC20.sol";
import {QualityEngine} from "src/QualityEngine.sol";
import {StakeVault} from "src/StakeVault.sol";

/// @notice Deploys tokens (SAPIEN, USDC), StakeVault, QualityEngine to Anvil, writes local.json.
contract DeployAnvil is Script {
    function run() external {
        uint256 deployerPrivateKey =
            vm.envOr("PRIVATE_KEY", uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80));
        address deployer = vm.addr(deployerPrivateKey);

        vm.startBroadcast(deployerPrivateKey);

        // Tokens
        DeployableERC20 sapien = new DeployableERC20("Sapien", "SAPIEN", 18);
        DeployableERC20 usdc = new DeployableERC20("USD Coin", "USDC", 6);

        // StakeVault (staking token = SAPIEN)
        StakeVault vaultImpl = new StakeVault();
        bytes memory vaultInit = abi.encodeCall(StakeVault.initialize, (IERC20(address(sapien)), deployer));
        StakeVault vault = StakeVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));

        QualityEngine engineImpl = new QualityEngine();
        bytes memory engineInit =
            abi.encodeCall(QualityEngine.initialize, (deployer, address(vault), deployer, address(0)));
        QualityEngine engine = QualityEngine(address(new ERC1967Proxy(address(engineImpl), engineInit)));

        // Grant ENGINE_ROLE to QualityEngine on the vault
        vault.grantRole(vault.ENGINE_ROLE(), address(engine));

        vm.stopBroadcast();

        // Write deployed addresses to local.json
        string memory obj = "contracts";
        vm.serializeAddress(obj, "SAPIEN", address(sapien));
        vm.serializeAddress(obj, "USDC", address(usdc));
        vm.serializeAddress(obj, "StakeVault", address(vault));
        string memory json = vm.serializeAddress(obj, "QualityEngine", address(engine));
        vm.writeJson(json, "deployments/local.json");
    }
}
