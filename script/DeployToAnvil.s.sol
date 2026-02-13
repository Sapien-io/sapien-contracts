// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "lib/forge-std/src/Script.sol";
import {console} from "lib/forge-std/src/console.sol";
import {SapienTrust} from "src/SapienTrust.sol";
import {ValidationOracle} from "src/ValidationOracle.sol";
import {SapienCore} from "src/SapienCore.sol";
import {SapienVault} from "src/SapienVault.sol";
import {Rewards} from "src/Rewards.sol";
import {SqrtStakeConsensus} from "src/consensus/SqrtStakeConsensus.sol";
import {MockERC20} from "test/mocks/MockERC20.sol";
import {
    UPDATER_ROLE,
    LOCKER_ROLE,
    SLASHER_ROLE,
    PAUSER_ROLE,
    SAPIEN_CORE_ROLE
} from "src/interface/ISharedTypes.sol";
import {ERC1967Proxy} from "lib/openzeppelin-contracts/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeployToAnvil
 * @notice Deployment script for local Anvil instance - deploys all contracts and sets up test environment
 */
contract DeployToAnvil is Script {
    // Contract instances
    SapienVault public vault;
    Rewards public rewards;
    SapienTrust public trust;
    ValidationOracle public oracle;
    SapienCore public core;
    MockERC20 public stakeToken;
    MockERC20 public rewardToken;

    // Test accounts (Anvil default accounts)
    address public admin = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public originator = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address public contributor = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address public validator1 = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address public validator2 = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
    address public validator3 = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;

    function run() external {
        console.log("=== Deploying Sapien Protocol to Anvil ===\n");

        // Start broadcast with admin account for all admin operations
        vm.startBroadcast(admin);

        // 1. Deploy Mock Tokens
        console.log("[1] Deploying Mock ERC20 tokens...");
        stakeToken = new MockERC20("Stake Token", "SAPIEN", 18);
        rewardToken = new MockERC20("Reward Token", "USDC", 6);
        console.log("    Stake Token:", address(stakeToken));
        console.log("    Reward Token:", address(rewardToken));

        // 2. Deploy SapienVault
        console.log("\n[2] Deploying SapienVault...");
        address vaultImpl = address(new SapienVault());
        bytes memory vaultInitData = abi.encodeWithSelector(SapienVault.initialize.selector, address(stakeToken), admin);
        vault = SapienVault(address(new ERC1967Proxy(vaultImpl, vaultInitData)));
        console.log("    SapienVault:", address(vault));

        // 3. Deploy Rewards
        console.log("\n[3] Deploying Rewards...");
        address rewardsImpl = address(new Rewards());
        bytes memory rewardsInitData = abi.encodeWithSelector(Rewards.initialize.selector, admin);
        rewards = Rewards(address(new ERC1967Proxy(rewardsImpl, rewardsInitData)));
        console.log("    Rewards:", address(rewards));

        // 4. Deploy SapienTrust
        console.log("\n[4] Deploying SapienTrust...");
        address trustImpl = address(new SapienTrust());
        bytes memory trustInitData =
            abi.encodeWithSelector(SapienTrust.initialize.selector, address(vault), 100 ether, 10, admin);
        trust = SapienTrust(address(new ERC1967Proxy(trustImpl, trustInitData)));
        console.log("    SapienTrust:", address(trust));

        // 5. Deploy ValidationOracle
        console.log("\n[5] Deploying ValidationOracle...");
        address oracleImpl = address(new ValidationOracle());
        bytes memory oracleInitData = abi.encodeWithSelector(
            ValidationOracle.initialize.selector, address(trust), address(vault), "SqrtStake", admin
        );
        oracle = ValidationOracle(address(new ERC1967Proxy(oracleImpl, oracleInitData)));
        console.log("    ValidationOracle:", address(oracle));

        // 6. Deploy SapienCore
        console.log("\n[6] Deploying SapienCore...");
        address coreImpl = address(new SapienCore());
        bytes memory coreInitData = abi.encodeWithSelector(
            SapienCore.initialize.selector, address(vault), address(rewards), address(trust), address(oracle), admin
        );
        core = SapienCore(address(new ERC1967Proxy(coreImpl, coreInitData)));
        console.log("    SapienCore:", address(core));

        // 7. Register Consensus Algorithm
        // Must use admin account for registerAlgorithm (requires DEFAULT_ADMIN_ROLE)
        console.log("\n[7] Registering consensus algorithm...");
        oracle.registerAlgorithm("SqrtStake", address(new SqrtStakeConsensus()));
        console.log("    Algorithm registered");

        // 8. Setup Roles and Permissions
        // All role grants require admin account (DEFAULT_ADMIN_ROLE)
        console.log("\n[8] Setting up roles and permissions...");
        rewards.setCore(address(core));

        trust.grantRole(UPDATER_ROLE, address(oracle));
        trust.grantRole(UPDATER_ROLE, address(core));
        trust.grantRole(UPDATER_ROLE, admin);

        vault.grantRole(LOCKER_ROLE, admin);
        vault.grantRole(SLASHER_ROLE, admin);
        vault.grantRole(PAUSER_ROLE, admin);
        vault.grantRole(LOCKER_ROLE, address(oracle));
        vault.grantRole(LOCKER_ROLE, address(core));
        vault.grantRole(SLASHER_ROLE, address(oracle));
        vault.grantRole(SLASHER_ROLE, address(core));
        vault.grantRole(SLASHER_ROLE, address(vault));

        oracle.grantRole(SAPIEN_CORE_ROLE, address(core));
        oracle.grantRole(SAPIEN_CORE_ROLE, admin);
        console.log("    Roles configured");

        // 9. Mint tokens to test accounts
        console.log("\n[9] Minting tokens to test accounts...");
        stakeToken.mint(originator, 1000 ether);
        stakeToken.mint(contributor, 1000 ether);
        stakeToken.mint(validator1, 1000 ether);
        stakeToken.mint(validator2, 1000 ether);
        stakeToken.mint(validator3, 1000 ether);
        rewardToken.mint(originator, 10000 ether);
        console.log("    Tokens minted");

        // Stop admin broadcast before switching to user accounts
        vm.stopBroadcast();

        // 10. Setup initial vault deposits
        // Note: These deposits require --unlocked flag to use Anvil's default accounts
        console.log("\n[10] Setting up initial vault deposits...");

        // Deposit for originator
        vm.startBroadcast(originator);
        stakeToken.approve(address(vault), 1000 ether);
        vault.deposit(1000 ether, originator);
        vm.stopBroadcast();

        // Deposit for contributor
        vm.startBroadcast(contributor);
        stakeToken.approve(address(vault), 1000 ether);
        vault.deposit(1000 ether, contributor);
        vm.stopBroadcast();

        // Deposit for validator1
        vm.startBroadcast(validator1);
        stakeToken.approve(address(vault), 1000 ether);
        vault.deposit(1000 ether, validator1);
        vm.stopBroadcast();

        // Deposit for validator2
        vm.startBroadcast(validator2);
        stakeToken.approve(address(vault), 1000 ether);
        vault.deposit(1000 ether, validator2);
        vm.stopBroadcast();

        // Deposit for validator3
        vm.startBroadcast(validator3);
        stakeToken.approve(address(vault), 1000 ether);
        vault.deposit(1000 ether, validator3);
        vm.stopBroadcast();

        console.log("    Vault deposits completed");

        // Output deployment addresses
        console.log("\n=== DEPLOYMENT COMPLETE ===");
        console.log("SapienCore:       ", address(core));
        console.log("ValidationOracle: ", address(oracle));
        console.log("SapienTrust:      ", address(trust));
        console.log("SapienVault:      ", address(vault));
        console.log("Rewards:           ", address(rewards));
        console.log("Stake Token:      ", address(stakeToken));
        console.log("Reward Token:     ", address(rewardToken));
        console.log("\n=== TEST ACCOUNTS ===");
        console.log("Admin:             ", admin);
        console.log("Originator:        ", originator);
        console.log("Contributor:       ", contributor);
        console.log("Validator1:        ", validator1);
        console.log("Validator2:        ", validator2);
        console.log("Validator3:        ", validator3);
    }
}
