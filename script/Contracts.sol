// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

// Struct definition for cleaner function returns
struct DeployedContracts {
    address sapienToken;
    address sapienVault;
    address sapienRewards;
    address sapienQA;
    address multiplier;
    address timelock;
}

library LocalContracts {
    address public constant SAPIEN_TOKEN = 0x5FbDB2315678afecb367f032d93F642f64180aa3;
    address public constant SAPIEN_VAULT = 0x0165878A594ca255338adfa4d48449f69242Eb8F;
    address public constant SAPIEN_REWARDS = 0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9;
    address public constant SAPIEN_QA = 0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0;
    address public constant MULTIPLIER = 0x1111111111111111111111111111111111111111;
    address public constant TIMELOCK = 0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512;
}

library TenderlyContracts {
    address public constant SAPIEN_TOKEN = 0xd3a8f3e472efB7246a5C3c604Aa034b6CDbE702F;
    address public constant SAPIEN_VAULT = 0x35977d540799db1e8910c00F476a879E2c0e1a24;
    address public constant SAPIEN_REWARDS = 0xcCa75eFc3161CF18276f84C3924FC8dC9a63E28C;
    address public constant SAPIEN_QA = 0x5ed9315ab0274B0C546b71ed5a7ABE9982FF1E8D;
    address public constant MULTIPLIER = 0x4Fd7836c7C3Cb0EE140F50EeaEceF1Cbe19D8b55;
    address public constant TIMELOCK = 0xAABc9b2DF2Ed11A3f94b011315Beba0ea7fB7D09;
}

library SepoliaContracts {
    address public constant SAPIEN_TOKEN = 0x7F54613f339d15424E9AdE87967BAE40b23Fa7F6;
    address public constant SAPIEN_VAULT = 0x63962218ea90237d79E7833811E920BB7CE78311;
    address public constant SAPIEN_REWARDS = 0xFfC83AF7b215a026A9A8BBE9c3E8835fB29f479B;
    address public constant SAPIEN_QA = 0x93263cB5AfC26Aa8910D5038aC01a12e4881B478;
    address public constant MULTIPLIER = 0x8816D0CC618E4Ca88Fb67d97586B691b0Dae3E2b;
    address public constant TIMELOCK = 0x2a5F9e1Be3A78C73EA1aB256D3Eb0C5A475742cC;
}

library MainnetContracts {
    address public constant SAPIEN_TOKEN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_VAULT = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_REWARDS = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_QA = 0x0000000000000000000000000000000000000000;
    address public constant MULTIPLIER = 0x0000000000000000000000000000000000000000;
    address public constant TIMELOCK = 0x0000000000000000000000000000000000000000;
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
                sapienVault: LocalContracts.SAPIEN_VAULT,
                sapienRewards: LocalContracts.SAPIEN_REWARDS,
                sapienQA: LocalContracts.SAPIEN_QA,
                multiplier: LocalContracts.MULTIPLIER,
                timelock: LocalContracts.TIMELOCK
            });
        } else if (block.chainid == 84532) {
            return DeployedContracts({
                sapienToken: SepoliaContracts.SAPIEN_TOKEN,
                sapienVault: SepoliaContracts.SAPIEN_VAULT,
                sapienRewards: SepoliaContracts.SAPIEN_REWARDS,
                sapienQA: SepoliaContracts.SAPIEN_QA,
                multiplier: SepoliaContracts.MULTIPLIER,
                timelock: SepoliaContracts.TIMELOCK
            });
        } else if (block.chainid == 8453420) {
            return DeployedContracts({
                sapienToken: TenderlyContracts.SAPIEN_TOKEN,
                sapienVault: TenderlyContracts.SAPIEN_VAULT,
                sapienRewards: TenderlyContracts.SAPIEN_REWARDS,
                sapienQA: TenderlyContracts.SAPIEN_QA,
                multiplier: TenderlyContracts.MULTIPLIER,
                timelock: TenderlyContracts.TIMELOCK
            });
        } else if (block.chainid == 8453) {
            return DeployedContracts({
                sapienToken: MainnetContracts.SAPIEN_TOKEN,
                sapienVault: MainnetContracts.SAPIEN_VAULT,
                sapienRewards: MainnetContracts.SAPIEN_REWARDS,
                sapienQA: MainnetContracts.SAPIEN_QA,
                multiplier: MainnetContracts.MULTIPLIER,
                timelock: MainnetContracts.TIMELOCK
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
                sapienVault: LocalContracts.SAPIEN_VAULT,
                sapienRewards: LocalContracts.SAPIEN_REWARDS,
                sapienQA: LocalContracts.SAPIEN_QA,
                multiplier: LocalContracts.MULTIPLIER,
                timelock: LocalContracts.TIMELOCK
            });
        } else if (chainId == 84532) {
            return DeployedContracts({
                sapienToken: SepoliaContracts.SAPIEN_TOKEN,
                sapienVault: SepoliaContracts.SAPIEN_VAULT,
                sapienRewards: SepoliaContracts.SAPIEN_REWARDS,
                sapienQA: SepoliaContracts.SAPIEN_QA,
                multiplier: SepoliaContracts.MULTIPLIER,
                timelock: SepoliaContracts.TIMELOCK
            });
        } else if (chainId == 8453420) {
            return DeployedContracts({
                sapienToken: TenderlyContracts.SAPIEN_TOKEN,
                sapienVault: TenderlyContracts.SAPIEN_VAULT,
                sapienRewards: TenderlyContracts.SAPIEN_REWARDS,
                sapienQA: TenderlyContracts.SAPIEN_QA,
                multiplier: TenderlyContracts.MULTIPLIER,
                timelock: TenderlyContracts.TIMELOCK
            });
        } else if (chainId == 8453) {
            return DeployedContracts({
                sapienToken: MainnetContracts.SAPIEN_TOKEN,
                sapienVault: MainnetContracts.SAPIEN_VAULT,
                sapienRewards: MainnetContracts.SAPIEN_REWARDS,
                sapienQA: MainnetContracts.SAPIEN_QA,
                multiplier: MainnetContracts.MULTIPLIER,
                timelock: MainnetContracts.TIMELOCK
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
            && contracts.multiplier != address(0) && contracts.timelock != address(0);
    }
}
