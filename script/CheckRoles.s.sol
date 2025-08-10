// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {Script, console} from "lib/forge-std/src/Script.sol";

import {SapienVault} from "src/SapienVault.sol";
import {SapienRewards} from "src/SapienRewards.sol";
import {SapienQA} from "src/SapienQA.sol";
import {BatchRewards} from "src/BatchRewards.sol";
import {TimelockController} from "src/utils/Common.sol";
import {ProxyAdmin} from "src/utils/Common.sol";

import {Actors, AllActors} from "script/Actors.sol";
import {Contracts, DeployedContracts} from "script/Contracts.sol";

interface IAccessControlView {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

contract CheckRoles is Script {
    bytes32 DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 PAUSER_ROLE = keccak256("PAUSER_ROLE");

    // vault
    bytes32 SAPIEN_QA_ROLE;
    // rewards
    bytes32 REWARDS_PAUSER;
    bytes32 REWARDS_ADMIN_ROLE;
    bytes32 REWARDS_MANAGER_ROLE;
    bytes32 BATCH_CLAIMER_ROLE;
    //timelock
    bytes32 PROPOSER_ROLE;
    bytes32 EXECUTOR_ROLE;
    bytes32 CANCELLER_ROLE;
    // sapien qa
    bytes32 QA_MANAGER_ROLE;
    bytes32 QA_SIGNER_ROLE;

    SapienVault vault;
    SapienRewards sapienRewards;
    TimelockController timelock;

    SapienQA sapienQA;
    SapienRewards usdcRewards;
    BatchRewards batchRewards;
    ProxyAdmin sapienVaultProxyAdmin;
    ProxyAdmin sapienRewardsProxyAdmin;
    ProxyAdmin sapienQaProxyAdmin;
    ProxyAdmin usdcRewardsProxyAdmin;

    function run() external {
        DeployedContracts memory contracts = Contracts.get();
        AllActors memory actors = Actors.getAllActors();

        console.log("Chain ID:", block.chainid);
        console.log("SapienToken:", contracts.sapienToken);
        console.log("USDC:", contracts.usdcToken);
        console.log("SapienVault (proxy):", contracts.sapienVault);
        console.log("SapienRewards (proxy):", contracts.sapienRewards);
        console.log("SapienQA (proxy):", contracts.sapienQA);
        console.log("USDCRewards (proxy):", contracts.usdcRewards);
        console.log("BatchRewards:", contracts.batchRewards);
        console.log("Timelock:", contracts.timelock);
        console.log("VaultProxyAdmin:", contracts.sapienVaultProxyAdmin);
        console.log("SapienRewardsProxyAdmin:", contracts.sapienRewardsProxyAdmin);
        console.log("SapienQAProxyAdmin:", contracts.sapienQaProxyAdmin);
        console.log("USDCRewardsProxyAdmin:", contracts.usdcRewardsProxyAdmin);
        console.log("");

        // Only proceed for non-zero targets
        bool hasVault = contracts.sapienVault != address(0);
        bool hasSapienRewards = contracts.sapienRewards != address(0);
        bool hasSapienQA = contracts.sapienQA != address(0);
        bool hasBatchRewards = contracts.batchRewards != address(0);
        bool hasUsdcRewards = contracts.usdcRewards != address(0);
        bool hasTimelock = contracts.timelock != address(0);
        bool hasSapienToken = contracts.sapienToken != address(0);
        bool hasUsdcToken = contracts.usdcToken != address(0);
        bool hasProxyAdmin = contracts.sapienVaultProxyAdmin != address(0)
            || contracts.sapienRewardsProxyAdmin != address(0) || contracts.sapienQaProxyAdmin != address(0)
            || contracts.usdcRewardsProxyAdmin != address(0);

        if (
            !hasVault && !hasSapienRewards && !hasBatchRewards && !hasUsdcRewards && !hasTimelock && !hasSapienToken
                && !hasUsdcToken && !hasProxyAdmin
        ) {
            console.log("No contract addresses configured for this chain.");
            return;
        }

        vault = SapienVault(payable(contracts.sapienVault));
        sapienRewards = SapienRewards(payable(contracts.sapienRewards));
        timelock = TimelockController(payable(contracts.timelock));

        sapienQA = SapienQA(payable(contracts.sapienQA));
        usdcRewards = SapienRewards(payable(contracts.usdcRewards));
        batchRewards = BatchRewards(payable(contracts.batchRewards));
        sapienVaultProxyAdmin = ProxyAdmin(payable(contracts.sapienVaultProxyAdmin));
        sapienRewardsProxyAdmin = ProxyAdmin(payable(contracts.sapienRewardsProxyAdmin));
        sapienQaProxyAdmin = ProxyAdmin(payable(contracts.sapienQaProxyAdmin));
        usdcRewardsProxyAdmin = ProxyAdmin(payable(contracts.usdcRewardsProxyAdmin));

        if (hasVault) {
            SAPIEN_QA_ROLE = vault.SAPIEN_QA_ROLE();
        }

        if (hasSapienRewards) {
            REWARDS_ADMIN_ROLE = sapienRewards.REWARD_ADMIN_ROLE();
            REWARDS_MANAGER_ROLE = sapienRewards.REWARD_MANAGER_ROLE();
            BATCH_CLAIMER_ROLE = sapienRewards.BATCH_CLAIMER_ROLE();
        }

        if (hasTimelock) {
            PROPOSER_ROLE = timelock.PROPOSER_ROLE();
            EXECUTOR_ROLE = timelock.EXECUTOR_ROLE();
            CANCELLER_ROLE = timelock.CANCELLER_ROLE();
        }

        if (hasSapienQA) {
            QA_MANAGER_ROLE = sapienQA.QA_MANAGER_ROLE();
            QA_SIGNER_ROLE = sapienQA.QA_SIGNER_ROLE();
        }

        // Addresses to sanity-check across roles
        address[12] memory addrs = [
            actors.securityCouncil,
            contracts.timelock,
            actors.pauser,
            actors.rewardsAdmin,
            actors.rewardsManager,
            actors.qaManager,
            actors.qaSigner,
            contracts.sapienQA,
            actors.deployer,
            contracts.batchRewards,
            actors.blended,
            actors.sapienLabs
        ];
        string[12] memory names = [
            "securityCouncil",
            "timelock",
            "pauser",
            "rewardsAdmin",
            "rewardsManager",
            "qaManager",
            "qaSigner",
            "sapienQA",
            "deployer",
            "batchRewards",
            "blended",
            "sapienLabs"
        ];

        // Vault role checks
        if (hasVault) {
            console.log("==== SapienVault Roles ====");
            _printRole("DEFAULT_ADMIN_ROLE", address(vault), DEFAULT_ADMIN_ROLE, addrs, names);
            _printRole("PAUSER_ROLE", address(vault), PAUSER_ROLE, addrs, names);
            _printRole("SAPIEN_QA_ROLE", address(vault), SAPIEN_QA_ROLE, addrs, names);
            console.log("");
        }

        // Rewards role checks
        if (hasSapienRewards) {
            console.log("==== SapienRewards Roles ====");
            _printRole("DEFAULT_ADMIN_ROLE", address(sapienRewards), DEFAULT_ADMIN_ROLE, addrs, names);
            _printRole("PAUSER_ROLE", address(sapienRewards), PAUSER_ROLE, addrs, names);
            _printRole("REWARD_ADMIN_ROLE", address(sapienRewards), REWARDS_ADMIN_ROLE, addrs, names);
            _printRole("REWARD_MANAGER_ROLE", address(sapienRewards), REWARDS_MANAGER_ROLE, addrs, names);
            _printRole("BATCH_CLAIMER_ROLE", address(sapienRewards), BATCH_CLAIMER_ROLE, addrs, names);
        }

        // SapienQA role checks
        if (hasSapienQA) {
            console.log("==== SapienQA Roles ====");
            _printRole("QA_MANAGER_ROLE", address(sapienQA), QA_MANAGER_ROLE, addrs, names);
            _printRole("QA_SIGNER_ROLE", address(sapienQA), QA_SIGNER_ROLE, addrs, names);
        }

        if (hasUsdcRewards) {
            console.log("==== USDCRewards Roles ====");
            _printRole("DEFAULT_ADMIN_ROLE", address(usdcRewards), DEFAULT_ADMIN_ROLE, addrs, names);
            _printRole("PAUSER_ROLE", address(usdcRewards), PAUSER_ROLE, addrs, names);
            _printRole("REWARD_ADMIN_ROLE", address(usdcRewards), REWARDS_ADMIN_ROLE, addrs, names);
            _printRole("REWARD_MANAGER_ROLE", address(usdcRewards), REWARDS_MANAGER_ROLE, addrs, names);
        }

        // ProxyAdmin role checks
        if (hasProxyAdmin) {
            console.log("==== ProxyAdmin Roles ====");
            console.log("VaultProxyAdmin owner:", sapienVaultProxyAdmin.owner());
            console.log("SapienRewardsProxyAdmin owner:", sapienRewardsProxyAdmin.owner());
            console.log("SapienQAProxyAdmin owner:", sapienQaProxyAdmin.owner());
            console.log("USDCRewardsProxyAdmin owner:", usdcRewardsProxyAdmin.owner());
            console.log("");
        }

        // Timelock role checks
        if (hasTimelock) {
            console.log("==== Timelock Roles ====");
            _printRole("DEFAULT_ADMIN_ROLE", address(timelock), DEFAULT_ADMIN_ROLE, addrs, names);
            _printRole("PROPOSER_ROLE", address(timelock), PROPOSER_ROLE, addrs, names);
            _printRole("EXECUTOR_ROLE", address(timelock), EXECUTOR_ROLE, addrs, names);
            _printRole("CANCELLER_ROLE", address(timelock), CANCELLER_ROLE, addrs, names);
        }
    }

    function _printRole(
        string memory roleName,
        address target,
        bytes32 role,
        address[12] memory addrs,
        string[12] memory names
    ) private view {
        IAccessControlView targetLike = IAccessControlView(target);
        console.log("Role:", roleName);
        for (uint256 i = 0; i < addrs.length; i++) {
            bool has = targetLike.hasRole(role, addrs[i]);
            if (!has) continue;

            console.log("    name:", names[i]);
            console.log("    addr:", addrs[i]);
            console.log("    hasRole:", has);
            console.log("");
        }
    }
}
