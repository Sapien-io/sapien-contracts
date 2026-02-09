// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SapienTrust} from "../src/SapienTrust.sol";
import {ValidationOracle} from "../src/ValidationOracle.sol";
import {SapienCore} from "../src/SapienCore.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {LinearStakeConsensus} from "../src/consensus/LinearStakeConsensus.sol";
import {CappedLinearConsensus} from "../src/consensus/CappedLinearConsensus.sol";
import {SqrtStakeConsensus} from "../src/consensus/SqrtStakeConsensus.sol";
import {HybridConsensus} from "../src/consensus/HybridConsensus.sol";
import {UPDATER_ROLE, LOCKER_ROLE} from "../src/interface/ISharedTypes.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployProtocol
 * @notice Deployment script for the consolidated 3-pillar architecture
 */
contract DeployProtocol is Script {
    address public vault;
    address public rewards;
    address public admin;

    SapienTrust public trust;
    ValidationOracle public oracle;
    SapienCore public core;

    function run() external {
        vault = vm.envAddress("SAPIEN_VAULT_ADDRESS");
        rewards = vm.envAddress("REWARDS_ADDRESS");
        admin = vm.envAddress("ADMIN_ADDRESS");

        vm.startBroadcast();

        // 1. Deploy SapienTrust (Pillar 3)
        console.log("Deploying SapienTrust...");
        SapienTrust trustImpl = new SapienTrust();
        bytes memory trustInit = abi.encodeWithSelector(
            SapienTrust.initialize.selector,
            vault,
            100 ether, // minStake
            10, // decayRate (0.1%)
            admin
        );
        trust = SapienTrust(address(new ERC1967Proxy(address(trustImpl), trustInit)));
        console.log("SapienTrust deployed at:", address(trust));

        // 2. Deploy ValidationOracle (Pillar 2)
        console.log("Deploying ValidationOracle...");
        ValidationOracle oracleImpl = new ValidationOracle();
        bytes memory oracleInit =
            abi.encodeWithSelector(ValidationOracle.initialize.selector, address(trust), vault, "SqrtStake", admin);
        oracle = ValidationOracle(address(new ERC1967Proxy(address(oracleImpl), oracleInit)));
        console.log("ValidationOracle deployed at:", address(oracle));

        // 3. Deploy SapienCore (Pillar 1)
        console.log("Deploying SapienCore...");
        SapienCore coreImpl = new SapienCore();
        bytes memory coreInit = abi.encodeWithSelector(
            SapienCore.initialize.selector, vault, rewards, address(trust), address(oracle), admin
        );
        core = SapienCore(address(new ERC1967Proxy(address(coreImpl), coreInit)));
        console.log("SapienCore deployed at:", address(core));

        // 4. Register Algorithms in Oracle
        console.log("Registering Algorithms...");
        oracle.registerAlgorithm("LinearStake", address(new LinearStakeConsensus()));
        oracle.registerAlgorithm("CappedLinear", address(new CappedLinearConsensus()));
        oracle.registerAlgorithm("SqrtStake", address(new SqrtStakeConsensus()));
        oracle.registerAlgorithm("Hybrid", address(new HybridConsensus()));

        // 5. Setup Permissions
        console.log("Setting up permissions...");
        trust.grantRole(UPDATER_ROLE, address(oracle));
        trust.grantRole(UPDATER_ROLE, address(core));

        SapienVault(vault).grantRole(LOCKER_ROLE, address(oracle));
        SapienVault(vault).grantRole(LOCKER_ROLE, address(core));

        vm.stopBroadcast();

        console.log("\n=== UNIFIED ARCHITECTURE DEPLOYED ===");
        console.log("SapienCore:       ", address(core));
        console.log("ValidationOracle: ", address(oracle));
        console.log("SapienTrust:      ", address(trust));
    }
}
