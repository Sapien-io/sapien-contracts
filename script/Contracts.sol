// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

// Struct definition for cleaner function returns
struct DeployedContracts {
    address sapienToken;
    address usdcToken;
    address sapienVault;
    address sapienRewards;
    address usdcRewards;
    address sapienQA;
    address timelock;
    address batchRewards;
    address sapienVaultProxyAdmin;
    address sapienRewardsProxyAdmin;
    address usdcRewardsProxyAdmin;
    address sapienQaProxyAdmin;
}

// These are the proxies
library LocalContracts {
    address public constant SAPIEN_TOKEN = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address public constant USDC_TOKEN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_VAULT = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    address public constant SAPIEN_REWARDS = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;
    address public constant USDC_REWARDS = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_QA = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    address public constant TIMELOCK = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
    address public constant BATCH_REWARDS = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address public constant USDC_REWARDS_PROXY_ADMIN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_VAULT_PROXY_ADMIN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_REWARDS_PROXY_ADMIN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_QA_PROXY_ADMIN = 0x0000000000000000000000000000000000000000;
}

library TenderlyContracts {
    address public constant SAPIEN_TOKEN = 0xd3a8f3e472efB7246a5C3c604Aa034b6CDbE702F;
    address public constant USDC_TOKEN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_VAULT = 0x35977d540799db1e8910c00F476a879E2c0e1a24;
    address public constant SAPIEN_REWARDS = 0xcCa75eFc3161CF18276f84C3924FC8dC9a63E28C;
    address public constant USDC_REWARDS = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_QA = 0x5ed9315ab0274B0C546b71ed5a7ABE9982FF1E8D;
    address public constant TIMELOCK = 0xAABc9b2DF2Ed11A3f94b011315Beba0ea7fB7D09;
    address public constant BATCH_REWARDS = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address public constant USDC_REWARDS_PROXY_ADMIN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_VAULT_PROXY_ADMIN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_REWARDS_PROXY_ADMIN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_QA_PROXY_ADMIN = 0x0000000000000000000000000000000000000000;
}

library SepoliaContracts {
    address public constant SAPIEN_TOKEN = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6;
    address public constant USDC_TOKEN = 0x4d4394119CF096FbdbbD3Efb00d204c891C6Cd05;
    address public constant SAPIEN_VAULT = 0x3a92bF12A5ece7959C47D1aF32E10d71d868bF90;
    address public constant SAPIEN_REWARDS = 0xFF443d92F80A12Fb7343bb16d44df60204c6eB08;
    address public constant USDC_REWARDS = 0x798Fc8E87AfD496b8a16b436120cc6A456d3AC48;
    address public constant SAPIEN_QA = 0x575C1F6FBa0cA77AbAd28d8ca8b6f93727b36bbF;
    address public constant TIMELOCK = 0x2a5F9e1Be3A78C73EA1aB256D3Eb0C5A475742cC;
    address public constant BATCH_REWARDS = 0xae064cF985da8Cd842753D65B307E27A3853838e;
    address public constant SAPIEN_VAULT_PROXY_ADMIN = 0xa36323825c62AC6CFF43f346fE722692647B2D41;
    address public constant SAPIEN_REWARDS_PROXY_ADMIN = 0xb2c78dDa5A17210F5d07Bc7BdDbe94a11C5b2dca;
    address public constant USDC_REWARDS_PROXY_ADMIN = 0x5779A31ac0988Df319A7BC1EEdc51b2bb7D504eB;
    address public constant SAPIEN_QA_PROXY_ADMIN = 0xa4188b8d12fb96df519bCdA88a6502Ab8aEd4261;
}

library MainnetContracts {
    address public constant SAPIEN_TOKEN = 0xC729777d0470F30612B1564Fd96E8Dd26f5814E3;
    address public constant USDC_TOKEN = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address public constant SAPIEN_VAULT = 0x74b21FAdf654543B142De0bDC7a6A4a0c631e397;
    address public constant SAPIEN_REWARDS = 0xB70C2BA5Aa45b052C2aC59D310bA8E93Ee65B3C9;
    address public constant USDC_REWARDS = 0x9E866C93Fc53baA53B7D00927094de0C18320AA2;
    address public constant SAPIEN_QA = 0x962F190C6DDf58547fe2Ac4696187694a715A2eA;
    address public constant TIMELOCK = 0x20304CbD5D4674b430CdC360f9F7B19790D98257;
    address public constant BATCH_REWARDS = 0x0000000000000000000000000000000000000000;
    address public constant USDC_REWARDS_PROXY_ADMIN = 0x17199aa37bEf6bff8813a70B89F64AC8B4c3E5B4;
    address public constant SAPIEN_VAULT_PROXY_ADMIN = 0x253053553e7105C5Bb39b38000EaA2aCdA95509E;
    address public constant SAPIEN_REWARDS_PROXY_ADMIN = 0x679C3986dEA1c281fB3e2D5853E0d2Df199ACaD7;
    address public constant SAPIEN_QA_PROXY_ADMIN = 0x0000000000000000000000000000000000000000;
}

library Contracts {
    /**
     * @notice Returns deployed contract addresses for the current chain
     * @return DeployedContracts struct with all 6 contract addresses
     */
    function get() internal view returns (DeployedContracts memory) {
        if (block.chainid == 31337) {
            return DeployedContracts({
                sapienToken: LocalContracts.SAPIEN_TOKEN,
                usdcToken: LocalContracts.USDC_TOKEN,
                sapienVault: LocalContracts.SAPIEN_VAULT,
                sapienRewards: LocalContracts.SAPIEN_REWARDS,
                usdcRewards: LocalContracts.USDC_REWARDS,
                sapienQA: LocalContracts.SAPIEN_QA,
                timelock: LocalContracts.TIMELOCK,
                batchRewards: LocalContracts.BATCH_REWARDS,
                sapienVaultProxyAdmin: LocalContracts.SAPIEN_VAULT_PROXY_ADMIN,
                sapienRewardsProxyAdmin: LocalContracts.SAPIEN_REWARDS_PROXY_ADMIN,
                usdcRewardsProxyAdmin: LocalContracts.USDC_REWARDS_PROXY_ADMIN,
                sapienQaProxyAdmin: LocalContracts.SAPIEN_QA_PROXY_ADMIN
            });
        } else if (block.chainid == 84532) {
            return DeployedContracts({
                sapienToken: SepoliaContracts.SAPIEN_TOKEN,
                usdcToken: SepoliaContracts.USDC_TOKEN,
                sapienVault: SepoliaContracts.SAPIEN_VAULT,
                sapienRewards: SepoliaContracts.SAPIEN_REWARDS,
                usdcRewards: SepoliaContracts.USDC_REWARDS,
                sapienQA: SepoliaContracts.SAPIEN_QA,
                timelock: SepoliaContracts.TIMELOCK,
                batchRewards: SepoliaContracts.BATCH_REWARDS,
                sapienVaultProxyAdmin: SepoliaContracts.SAPIEN_VAULT_PROXY_ADMIN,
                sapienRewardsProxyAdmin: SepoliaContracts.SAPIEN_REWARDS_PROXY_ADMIN,
                usdcRewardsProxyAdmin: SepoliaContracts.USDC_REWARDS_PROXY_ADMIN,
                sapienQaProxyAdmin: SepoliaContracts.SAPIEN_QA_PROXY_ADMIN
            });
        } else if (block.chainid == 8453420) {
            return DeployedContracts({
                sapienToken: TenderlyContracts.SAPIEN_TOKEN,
                usdcToken: TenderlyContracts.USDC_TOKEN,
                sapienVault: TenderlyContracts.SAPIEN_VAULT,
                sapienRewards: TenderlyContracts.SAPIEN_REWARDS,
                usdcRewards: TenderlyContracts.USDC_REWARDS,
                sapienQA: TenderlyContracts.SAPIEN_QA,
                timelock: TenderlyContracts.TIMELOCK,
                batchRewards: TenderlyContracts.BATCH_REWARDS,
                sapienVaultProxyAdmin: TenderlyContracts.SAPIEN_VAULT_PROXY_ADMIN,
                sapienRewardsProxyAdmin: TenderlyContracts.SAPIEN_REWARDS_PROXY_ADMIN,
                usdcRewardsProxyAdmin: TenderlyContracts.USDC_REWARDS_PROXY_ADMIN,
                sapienQaProxyAdmin: TenderlyContracts.SAPIEN_QA_PROXY_ADMIN
            });
        } else if (block.chainid == 8453) {
            return DeployedContracts({
                sapienToken: MainnetContracts.SAPIEN_TOKEN,
                usdcToken: MainnetContracts.USDC_TOKEN,
                sapienVault: MainnetContracts.SAPIEN_VAULT,
                sapienRewards: MainnetContracts.SAPIEN_REWARDS,
                usdcRewards: MainnetContracts.USDC_REWARDS,
                sapienQA: MainnetContracts.SAPIEN_QA,
                timelock: MainnetContracts.TIMELOCK,
                batchRewards: MainnetContracts.BATCH_REWARDS,
                sapienVaultProxyAdmin: MainnetContracts.SAPIEN_VAULT_PROXY_ADMIN,
                sapienRewardsProxyAdmin: MainnetContracts.SAPIEN_REWARDS_PROXY_ADMIN,
                usdcRewardsProxyAdmin: MainnetContracts.USDC_REWARDS_PROXY_ADMIN,
                sapienQaProxyAdmin: MainnetContracts.SAPIEN_QA_PROXY_ADMIN
            });
        }
        revert("Unsupported chain");
    }

    /**
     * @notice Check if a chain ID is supported
     * @param chainId The chain ID to check
     * @return bool True if supported, false otherwise
     */
    function isChainSupported(uint256 chainId) internal pure returns (bool) {
        return chainId == 31337 || chainId == 84532 || chainId == 8453420 || chainId == 8453;
    }

    /**
     * @notice Get contracts for a specific chain ID
     * @param chainId The chain ID to get contracts for
     * @return DeployedContracts struct with all addresses populated
     */
    function getContractsForChain(uint256 chainId) internal pure returns (DeployedContracts memory) {
        if (chainId == 31337) {
            return DeployedContracts({
                sapienToken: LocalContracts.SAPIEN_TOKEN,
                usdcToken: LocalContracts.USDC_TOKEN,
                sapienVault: LocalContracts.SAPIEN_VAULT,
                sapienRewards: LocalContracts.SAPIEN_REWARDS,
                usdcRewards: LocalContracts.USDC_REWARDS,
                sapienQA: LocalContracts.SAPIEN_QA,
                timelock: LocalContracts.TIMELOCK,
                batchRewards: LocalContracts.BATCH_REWARDS,
                sapienVaultProxyAdmin: LocalContracts.SAPIEN_VAULT_PROXY_ADMIN,
                sapienRewardsProxyAdmin: LocalContracts.SAPIEN_REWARDS_PROXY_ADMIN,
                usdcRewardsProxyAdmin: LocalContracts.USDC_REWARDS_PROXY_ADMIN,
                sapienQaProxyAdmin: LocalContracts.SAPIEN_QA_PROXY_ADMIN
            });
        } else if (chainId == 84532) {
            return DeployedContracts({
                sapienToken: SepoliaContracts.SAPIEN_TOKEN,
                usdcToken: SepoliaContracts.USDC_TOKEN,
                sapienVault: SepoliaContracts.SAPIEN_VAULT,
                sapienRewards: SepoliaContracts.SAPIEN_REWARDS,
                usdcRewards: SepoliaContracts.USDC_REWARDS,
                sapienQA: SepoliaContracts.SAPIEN_QA,
                timelock: SepoliaContracts.TIMELOCK,
                batchRewards: SepoliaContracts.BATCH_REWARDS,
                sapienVaultProxyAdmin: SepoliaContracts.SAPIEN_VAULT_PROXY_ADMIN,
                sapienRewardsProxyAdmin: SepoliaContracts.SAPIEN_REWARDS_PROXY_ADMIN,
                usdcRewardsProxyAdmin: SepoliaContracts.USDC_REWARDS_PROXY_ADMIN,
                sapienQaProxyAdmin: SepoliaContracts.SAPIEN_QA_PROXY_ADMIN
            });
        } else if (chainId == 8453420) {
            return DeployedContracts({
                sapienToken: TenderlyContracts.SAPIEN_TOKEN,
                usdcToken: TenderlyContracts.USDC_TOKEN,
                sapienVault: TenderlyContracts.SAPIEN_VAULT,
                sapienRewards: TenderlyContracts.SAPIEN_REWARDS,
                usdcRewards: TenderlyContracts.USDC_REWARDS,
                sapienQA: TenderlyContracts.SAPIEN_QA,
                timelock: TenderlyContracts.TIMELOCK,
                batchRewards: TenderlyContracts.BATCH_REWARDS,
                sapienVaultProxyAdmin: TenderlyContracts.SAPIEN_VAULT_PROXY_ADMIN,
                sapienRewardsProxyAdmin: TenderlyContracts.SAPIEN_REWARDS_PROXY_ADMIN,
                usdcRewardsProxyAdmin: TenderlyContracts.USDC_REWARDS_PROXY_ADMIN,
                sapienQaProxyAdmin: TenderlyContracts.SAPIEN_QA_PROXY_ADMIN
            });
        } else if (chainId == 8453) {
            return DeployedContracts({
                sapienToken: MainnetContracts.SAPIEN_TOKEN,
                usdcToken: MainnetContracts.USDC_TOKEN,
                sapienVault: MainnetContracts.SAPIEN_VAULT,
                sapienRewards: MainnetContracts.SAPIEN_REWARDS,
                usdcRewards: MainnetContracts.USDC_REWARDS,
                sapienQA: MainnetContracts.SAPIEN_QA,
                timelock: MainnetContracts.TIMELOCK,
                batchRewards: MainnetContracts.BATCH_REWARDS,
                sapienVaultProxyAdmin: MainnetContracts.SAPIEN_VAULT_PROXY_ADMIN,
                sapienRewardsProxyAdmin: MainnetContracts.SAPIEN_REWARDS_PROXY_ADMIN,
                usdcRewardsProxyAdmin: MainnetContracts.USDC_REWARDS_PROXY_ADMIN,
                sapienQaProxyAdmin: MainnetContracts.SAPIEN_QA_PROXY_ADMIN
            });
        }
        revert("Unsupported chain");
    }

    /**
     * @notice Check if all contracts are deployed (non-zero addresses)
     * @param contracts The contracts struct to check
     * @return bool True if all contracts are deployed, false otherwise
     */
    function areAllContractsDeployed(DeployedContracts memory contracts) internal pure returns (bool) {
        return contracts.sapienToken != address(0) && contracts.sapienVault != address(0)
            && contracts.sapienRewards != address(0) && contracts.sapienQA != address(0)
            && contracts.timelock != address(0) && contracts.sapienVaultProxyAdmin != address(0)
            && contracts.sapienRewardsProxyAdmin != address(0) && contracts.sapienQaProxyAdmin != address(0)
            && contracts.batchRewards != address(0);
    }
}
