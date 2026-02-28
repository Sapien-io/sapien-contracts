// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console} from "forge-std/Script.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DeployableERC20} from "./mocks/DeployableERC20.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";

/// @notice Deploys SapienVault and SapienCore to Base Sepolia behind ERC-1967 proxies.
/// @dev    Uses `--account` keystore auth. Set SAPIEN_TOKEN env var to skip mock token deploy.
///         Output is written to deployments/base-sepolia.json.
contract DeployBaseSepolia is Script {

    address public constant SAPIEN_TOKEN = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6;
    address public constant TREASURY = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant DEFAULT_ADMIN = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant DEPLOYER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;

    function run() external {
        console.log("Deployer:", DEPLOYER);

        vm.startBroadcast();
        console.log("Using existing SAPIEN token:", SAPIEN_TOKEN);
        

        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInit = abi.encodeCall(SapienVault.initialize, (IERC20(SAPIEN_TOKEN), DEPLOYER));
        SapienVault vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), vaultInit)));
        console.log("SapienVault proxy:", address(vault));

        SapienCore coreImpl = new SapienCore();
        bytes memory coreInit = abi.encodeCall(SapienCore.initialize, (DEPLOYER, address(vault), TREASURY));
        SapienCore core = SapienCore(address(new ERC1967Proxy(address(coreImpl), coreInit)));
        console.log("SapienCore proxy:", address(core));

        vault.grantRole(vault.ENGINE_ROLE(), address(core));
        // set default admin on vault to DEFAULT_ADMIN
        vault.grantRole(vault.DEFAULT_ADMIN_ROLE(), DEFAULT_ADMIN);
        console.log("DEFAULT_ADMIN_ROLE granted to SapienVault");

        core.grantRole(core.DEFAULT_ADMIN_ROLE(), DEFAULT_ADMIN);
        console.log("DEFAULT_ADMIN_ROLE granted to SapienCore");

        vault.revokeRole(vault.DEFAULT_ADMIN_ROLE(), DEPLOYER);
        console.log("DEFAULT_ADMIN_ROLE revoked from SapienVault");
        
        core.revokeRole(core.DEFAULT_ADMIN_ROLE(), DEPLOYER);
        console.log("DEFAULT_ADMIN_ROLE revoked from SapienCore");


        console.log("ENGINE_ROLE granted to SapienCore");


        vm.stopBroadcast();

        string memory obj = "deployment";
        vm.serializeAddress(obj, "DEPLOYER", DEPLOYER);
        vm.serializeAddress(obj, "DEFAULT_ADMIN", DEFAULT_ADMIN);
        vm.serializeAddress(obj, "TREASURY", TREASURY);
        vm.serializeAddress(obj, "SAPIEN", SAPIEN_TOKEN);
        vm.serializeAddress(obj, "SapienVault_Implementation", address(vaultImpl));
        vm.serializeAddress(obj, "SapienVault", address(vault));
        vm.serializeAddress(obj, "SapienCore_Implementation", address(coreImpl));
        string memory json = vm.serializeAddress(obj, "SapienCore", address(core));
        vm.writeJson(json, "deployments/base-sepolia.json");
        console.log("Deployment addresses written to deployments/base-sepolia.json");
    }
}
