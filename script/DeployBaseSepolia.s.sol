// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SapienTrust} from "../src/SapienTrust.sol";
import {ValidationOracle} from "../src/ValidationOracle.sol";
import {SapienCore} from "../src/SapienCore.sol";
import {SapienVault} from "../src/SapienVault.sol";
import {Rewards} from "../src/Rewards.sol";
import {LinearStakeConsensus} from "../src/consensus/LinearStakeConsensus.sol";
import {CappedLinearConsensus} from "../src/consensus/CappedLinearConsensus.sol";
import {SqrtStakeConsensus} from "../src/consensus/SqrtStakeConsensus.sol";
import {HybridConsensus} from "../src/consensus/HybridConsensus.sol";
import {
    UPDATER_ROLE,
    LOCKER_ROLE,
    SLASHER_ROLE,
    PAUSER_ROLE,
    SAPIEN_CORE_ROLE
} from "../src/interface/ISharedTypes.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployBaseSepolia
 * @notice Deployment script for Base Sepolia testnet
 * @dev Deploys all Sapien Protocol contracts and configures roles/permissions
 *
 * Required environment variables:
 * - STAKING_TOKEN=0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6 (Address of the ERC20 token to use for staking
 * - ADMIN_ADDRESS=0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC (Address that will have admin roles on all contracts
 *
 * Optional environment variables:
 * - MIN_STAKE: Minimum stake amount (default: 100 ether)
 * - DECAY_RATE: Reputation decay rate in basis points (default: 10 = 0.1%)
 * - DEFAULT_ALGORITHM: Default consensus algorithm name (default: "SqrtStake")
 */
contract DeployBaseSepolia is Script {
    // Contract instances
    SapienVault public vault;
    Rewards public rewards;
    SapienTrust public trust;
    ValidationOracle public oracle;
    SapienCore public core;

    // Deployment parameters
    address public stakingToken;
    address public admin;
    uint256 public minStake;
    uint256 public decayRate;
    string public defaultAlgorithm;

    function run() external {
        console.log("===========================================");
        console.log("Sapien Protocol Deployment");
        console.log("===========================================");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", msg.sender);
        console.log("\nNetwork: Base Sepolia (Testnet)");
        console.log("-------------------------------------------");

        // Load configuration from environment
        _loadConfiguration();

        // Start broadcast (uses private key from environment)
        vm.startBroadcast();

        // Deploy all contracts
        _deployContracts();

        // Configure roles and permissions
        _setupRoles();

        // Register consensus algorithms
        _registerAlgorithms();

        vm.stopBroadcast();

        // Output deployment summary
        _outputDeploymentSummary();
    }

    /**
     * @notice Load configuration from environment variables
     */
    function _loadConfiguration() internal {
        // Required: Staking token address
        stakingToken = vm.envAddress("STAKING_TOKEN");
        console.log("Staking Token:", stakingToken);

        // Required: Admin address
        admin = vm.envAddress("ADMIN_ADDRESS");
        console.log("Admin Address:", admin);

        // Optional: Configuration parameters
        minStake = vm.envOr("MIN_STAKE", uint256(100 ether));
        decayRate = vm.envOr("DECAY_RATE", uint256(10)); // 10 = 0.1%
        defaultAlgorithm = vm.envOr("DEFAULT_ALGORITHM", string("SqrtStake"));

        console.log("Min Stake:", minStake);
        console.log("Decay Rate:", decayRate, "(basis points)");
        console.log("Default Algorithm:", defaultAlgorithm);
        console.log("\nDeploying core contracts...");
    }

    /**
     * @notice Deploy all protocol contracts
     */
    function _deployContracts() internal {
        // 1. Deploy SapienVault
        console.log("\n[1] Deploying SapienVault...");
        SapienVault vaultImpl = new SapienVault();
        bytes memory vaultInitData = abi.encodeWithSelector(SapienVault.initialize.selector, stakingToken, admin);
        vault = SapienVault(address(new ERC1967Proxy(address(vaultImpl), vaultInitData)));
        console.log("    SapienVault Proxy:", address(vault));
        console.log("    SapienVault Impl: ", address(vaultImpl));

        // 2. Deploy Rewards
        console.log("\n[2] Deploying Rewards...");
        Rewards rewardsImpl = new Rewards();
        bytes memory rewardsInitData = abi.encodeWithSelector(Rewards.initialize.selector, admin);
        rewards = Rewards(address(new ERC1967Proxy(address(rewardsImpl), rewardsInitData)));
        console.log("    Rewards Proxy:", address(rewards));
        console.log("    Rewards Impl: ", address(rewardsImpl));

        // 3. Deploy SapienTrust
        console.log("\n[3] Deploying SapienTrust...");
        SapienTrust trustImpl = new SapienTrust();
        bytes memory trustInitData =
            abi.encodeWithSelector(SapienTrust.initialize.selector, address(vault), minStake, decayRate, admin);
        trust = SapienTrust(address(new ERC1967Proxy(address(trustImpl), trustInitData)));
        console.log("    SapienTrust Proxy:", address(trust));
        console.log("    SapienTrust Impl: ", address(trustImpl));

        // 4. Deploy ValidationOracle
        console.log("\n[4] Deploying ValidationOracle...");
        ValidationOracle oracleImpl = new ValidationOracle();
        bytes memory oracleInitData = abi.encodeWithSelector(
            ValidationOracle.initialize.selector, address(trust), address(vault), defaultAlgorithm, admin
        );
        oracle = ValidationOracle(address(new ERC1967Proxy(address(oracleImpl), oracleInitData)));
        console.log("    ValidationOracle Proxy:", address(oracle));
        console.log("    ValidationOracle Impl: ", address(oracleImpl));

        // 5. Deploy SapienCore
        console.log("\n[5] Deploying SapienCore...");
        SapienCore coreImpl = new SapienCore();
        bytes memory coreInitData = abi.encodeWithSelector(
            SapienCore.initialize.selector, address(vault), address(rewards), address(trust), address(oracle), admin
        );
        core = SapienCore(address(new ERC1967Proxy(address(coreImpl), coreInitData)));
        console.log("    SapienCore Proxy:", address(core));
        console.log("    SapienCore Impl: ", address(coreImpl));
    }

    /**
     * @notice Configure roles and permissions
     */
    function _setupRoles() internal {
        console.log("\n[6] Setting up roles and permissions...");

        // Link Rewards to Core
        rewards.setCore(address(core));
        console.log("    Rewards linked to SapienCore");

        // Grant UPDATER_ROLE on SapienTrust
        trust.grantRole(UPDATER_ROLE, address(oracle));
        trust.grantRole(UPDATER_ROLE, address(core));
        trust.grantRole(UPDATER_ROLE, admin);
        console.log("    UPDATER_ROLE granted on SapienTrust");

        // Grant roles on SapienVault
        vault.grantRole(LOCKER_ROLE, admin);
        vault.grantRole(SLASHER_ROLE, admin);
        vault.grantRole(PAUSER_ROLE, admin);
        vault.grantRole(LOCKER_ROLE, address(oracle));
        vault.grantRole(LOCKER_ROLE, address(core));
        vault.grantRole(SLASHER_ROLE, address(oracle));
        vault.grantRole(SLASHER_ROLE, address(core));
        vault.grantRole(SLASHER_ROLE, address(vault)); // Self-slashing capability
        console.log("    Roles granted on SapienVault");

        // Grant SAPIEN_CORE_ROLE on ValidationOracle
        oracle.grantRole(SAPIEN_CORE_ROLE, address(core));
        oracle.grantRole(SAPIEN_CORE_ROLE, admin);
        console.log("    SAPIEN_CORE_ROLE granted on ValidationOracle");
    }

    /**
     * @notice Register consensus algorithms
     */
    function _registerAlgorithms() internal {
        console.log("\n[7] Registering consensus algorithms...");

        oracle.registerAlgorithm("LinearStake", address(new LinearStakeConsensus()));
        console.log("    LinearStake registered");

        oracle.registerAlgorithm("CappedLinear", address(new CappedLinearConsensus()));
        console.log("    CappedLinear registered");

        oracle.registerAlgorithm("SqrtStake", address(new SqrtStakeConsensus()));
        console.log("    SqrtStake registered");

        oracle.registerAlgorithm("Hybrid", address(new HybridConsensus()));
        console.log("    Hybrid registered");
    }

    /**
     * @notice Output deployment summary and addresses
     */
    function _outputDeploymentSummary() internal view {
        console.log("\n===========================================");
        console.log("DEPLOYMENT COMPLETE");
        console.log("===========================================");
        console.log("\nContract Addresses:");
        console.log("  SapienCore:       ", address(core));
        console.log("  ValidationOracle: ", address(oracle));
        console.log("  SapienTrust:      ", address(trust));
        console.log("  SapienVault:      ", address(vault));
        console.log("  Rewards:          ", address(rewards));
        console.log("  Staking Token:    ", stakingToken);
        console.log("  Admin:            ", admin);

        console.log("\n===========================================");
        console.log("\nEnvironment variables");
        console.log("-------------------------------------------");
        console.log("SAPIEN_CORE_ADDRESS=", address(core));
        console.log("VALIDATION_ORACLE_ADDRESS=", address(oracle));
        console.log("SAPIEN_TRUST_ADDRESS=", address(trust));
        console.log("SAPIEN_VAULT_ADDRESS=", address(vault));
        console.log("REWARDS_ADDRESS=", address(rewards));
        console.log("STAKING_TOKEN_ADDRESS=", stakingToken);
        console.log("ADMIN_ADDRESS=", admin);
        console.log("MIN_STAKE=", minStake);
        console.log("DECAY_RATE=", decayRate);
        console.log("DEFAULT_ALGORITHM=", defaultAlgorithm);
    }
}
