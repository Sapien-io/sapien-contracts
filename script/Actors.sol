// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

// Struct definitions for cleaner function returns
struct CoreActors {
    address foundationSafe1;
    address foundationSafe2;
    address securityCouncil;
    address rewardsSafe;
    address rewardsManager;
}

struct AllActors {
    address foundationSafe1;
    address foundationSafe2;
    address securityCouncil;
    address rewardsSafe;
    address rewardsManager;
    address qaManager;
    address qaAdmin;
    address timelockProposer;
    address timelockExecutor;
    address timelockAdmin;
}

library LocalActors {
    address public constant FOUNDATION_SAFE_1 = address(0x01);
    address public constant FOUNDATION_SAFE_2 = address(0x02);
    address public constant SECURITY_COUNCIL_SAFE = address(0x03);
    address public constant REWARDS_SAFE = address(0x04);
    address public constant REWARDS_MANAGER = address(0x05);
    address public constant QA_MANAGER = address(0x06);
    address public constant QA_ADMIN = address(0x07);
    address public constant TIMELOCK_PROPOSER = address(0x08);
    address public constant TIMELOCK_EXECUTOR = address(0x09);
    address public constant TIMELOCK_ADMIN = address(0x0A);
}

library SepoliaActors {
    address public constant FOUNDATION_SAFE_1 = address(0x01);
    address public constant FOUNDATION_SAFE_2 = address(0x02);
    address public constant SECURITY_COUNCIL_SAFE = address(0x03);
    address public constant REWARDS_SAFE = address(0x04);
    address public constant REWARDS_MANAGER = address(0x05);
    address public constant QA_MANAGER = address(0x06);
    address public constant QA_ADMIN = address(0x07);
    address public constant TIMELOCK_PROPOSER = address(0x08);
    address public constant TIMELOCK_EXECUTOR = address(0x09);
    address public constant TIMELOCK_ADMIN = address(0x0A);
}

library TenderlyActors {
    // The primary Foundation safe that controls the assets / treasury
    address public constant FOUNDATION_SAFE_1 = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant FOUNDATION_SAFE_2 = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant SECURITY_COUNCIL_SAFE = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant REWARDS_SAFE = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant REWARDS_MANAGER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant QA_MANAGER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant QA_ADMIN = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant TIMELOCK_PROPOSER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant TIMELOCK_EXECUTOR = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant TIMELOCK_ADMIN = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
}

library MainnetActors {
    address public constant FOUNDATION_SAFE_1 = address(0x01);
    address public constant FOUNDATION_SAFE_2 = address(0x02);
    address public constant SECURITY_COUNCIL_SAFE = address(0x03);
    address public constant REWARDS_SAFE = address(0x04);
    address public constant REWARDS_MANAGER = address(0x05);
    address public constant QA_MANAGER = address(0x06);
    address public constant QA_ADMIN = address(0x07);
    address public constant TIMELOCK_PROPOSER = address(0x08);
    address public constant TIMELOCK_EXECUTOR = address(0x09);
    address public constant TIMELOCK_ADMIN = address(0x0A);
}

library Actors {
    /**
     * @notice Returns core actor addresses for the current chain
     * @return CoreActors struct with the 5 main actor addresses
     */
    function getActors() internal view returns (CoreActors memory) {
        if (block.chainid == 31337) {
            // Local development chain
            return CoreActors({
                foundationSafe1: LocalActors.FOUNDATION_SAFE_1,
                foundationSafe2: LocalActors.FOUNDATION_SAFE_2,
                securityCouncil: LocalActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: LocalActors.REWARDS_SAFE,
                rewardsManager: LocalActors.REWARDS_MANAGER
            });
        } else if (block.chainid == 84532) {
            // Sepolia testnet
            return CoreActors({
                foundationSafe1: SepoliaActors.FOUNDATION_SAFE_1,
                foundationSafe2: SepoliaActors.FOUNDATION_SAFE_2,
                securityCouncil: SepoliaActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: SepoliaActors.REWARDS_SAFE,
                rewardsManager: SepoliaActors.REWARDS_MANAGER
            });
        } else if (block.chainid == 8453420) {
            // Tenderly virtual testnet
            return CoreActors({
                foundationSafe1: TenderlyActors.FOUNDATION_SAFE_1,
                foundationSafe2: TenderlyActors.FOUNDATION_SAFE_2,
                securityCouncil: TenderlyActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: TenderlyActors.REWARDS_SAFE,
                rewardsManager: TenderlyActors.REWARDS_MANAGER
            });
        } else if (block.chainid == 8453) {
            // Base mainnet
            return CoreActors({
                foundationSafe1: MainnetActors.FOUNDATION_SAFE_1,
                foundationSafe2: MainnetActors.FOUNDATION_SAFE_2,
                securityCouncil: MainnetActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: MainnetActors.REWARDS_SAFE,
                rewardsManager: MainnetActors.REWARDS_MANAGER
            });
        }
        revert("Unsupported chain");
    }

    /**
     * @notice Returns all actor addresses for the current chain
     * @return AllActors struct with all 10 actor addresses
     */
    function getAllActors() internal view returns (AllActors memory) {
        if (block.chainid == 31337) {
            return AllActors({
                foundationSafe1: LocalActors.FOUNDATION_SAFE_1,
                foundationSafe2: LocalActors.FOUNDATION_SAFE_2,
                securityCouncil: LocalActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: LocalActors.REWARDS_SAFE,
                rewardsManager: LocalActors.REWARDS_MANAGER,
                qaManager: LocalActors.QA_MANAGER,
                qaAdmin: LocalActors.QA_ADMIN,
                timelockProposer: LocalActors.TIMELOCK_PROPOSER,
                timelockExecutor: LocalActors.TIMELOCK_EXECUTOR,
                timelockAdmin: LocalActors.TIMELOCK_ADMIN
            });
        } else if (block.chainid == 84532) {
            return AllActors({
                foundationSafe1: SepoliaActors.FOUNDATION_SAFE_1,
                foundationSafe2: SepoliaActors.FOUNDATION_SAFE_2,
                securityCouncil: SepoliaActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: SepoliaActors.REWARDS_SAFE,
                rewardsManager: SepoliaActors.REWARDS_MANAGER,
                qaManager: SepoliaActors.QA_MANAGER,
                qaAdmin: SepoliaActors.QA_ADMIN,
                timelockProposer: SepoliaActors.TIMELOCK_PROPOSER,
                timelockExecutor: SepoliaActors.TIMELOCK_EXECUTOR,
                timelockAdmin: SepoliaActors.TIMELOCK_ADMIN
            });
        } else if (block.chainid == 8453420) {
            return AllActors({
                foundationSafe1: TenderlyActors.FOUNDATION_SAFE_1,
                foundationSafe2: TenderlyActors.FOUNDATION_SAFE_2,
                securityCouncil: TenderlyActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: TenderlyActors.REWARDS_SAFE,
                rewardsManager: TenderlyActors.REWARDS_MANAGER,
                qaManager: TenderlyActors.QA_MANAGER,
                qaAdmin: TenderlyActors.QA_ADMIN,
                timelockProposer: TenderlyActors.TIMELOCK_PROPOSER,
                timelockExecutor: TenderlyActors.TIMELOCK_EXECUTOR,
                timelockAdmin: TenderlyActors.TIMELOCK_ADMIN
            });
        } else if (block.chainid == 8453) {
            return AllActors({
                foundationSafe1: MainnetActors.FOUNDATION_SAFE_1,
                foundationSafe2: MainnetActors.FOUNDATION_SAFE_2,
                securityCouncil: MainnetActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: MainnetActors.REWARDS_SAFE,
                rewardsManager: MainnetActors.REWARDS_MANAGER,
                qaManager: MainnetActors.QA_MANAGER,
                qaAdmin: MainnetActors.QA_ADMIN,
                timelockProposer: MainnetActors.TIMELOCK_PROPOSER,
                timelockExecutor: MainnetActors.TIMELOCK_EXECUTOR,
                timelockAdmin: MainnetActors.TIMELOCK_ADMIN
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
     * @notice Get actors for a specific chain ID
     * @param chainId The chain ID to get actors for
     * @return AllActors struct with all addresses populated
     */
    function getActorsForChain(uint256 chainId) internal pure returns (AllActors memory) {
        if (chainId == 31337) {
            return AllActors({
                foundationSafe1: LocalActors.FOUNDATION_SAFE_1,
                foundationSafe2: LocalActors.FOUNDATION_SAFE_2,
                securityCouncil: LocalActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: LocalActors.REWARDS_SAFE,
                rewardsManager: LocalActors.REWARDS_MANAGER,
                qaManager: LocalActors.QA_MANAGER,
                qaAdmin: LocalActors.QA_ADMIN,
                timelockProposer: LocalActors.TIMELOCK_PROPOSER,
                timelockExecutor: LocalActors.TIMELOCK_EXECUTOR,
                timelockAdmin: LocalActors.TIMELOCK_ADMIN
            });
        } else if (chainId == 84532) {
            return AllActors({
                foundationSafe1: SepoliaActors.FOUNDATION_SAFE_1,
                foundationSafe2: SepoliaActors.FOUNDATION_SAFE_2,
                securityCouncil: SepoliaActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: SepoliaActors.REWARDS_SAFE,
                rewardsManager: SepoliaActors.REWARDS_MANAGER,
                qaManager: SepoliaActors.QA_MANAGER,
                qaAdmin: SepoliaActors.QA_ADMIN,
                timelockProposer: SepoliaActors.TIMELOCK_PROPOSER,
                timelockExecutor: SepoliaActors.TIMELOCK_EXECUTOR,
                timelockAdmin: SepoliaActors.TIMELOCK_ADMIN
            });
        } else if (chainId == 8453420) {
            return AllActors({
                foundationSafe1: TenderlyActors.FOUNDATION_SAFE_1,
                foundationSafe2: TenderlyActors.FOUNDATION_SAFE_2,
                securityCouncil: TenderlyActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: TenderlyActors.REWARDS_SAFE,
                rewardsManager: TenderlyActors.REWARDS_MANAGER,
                qaManager: TenderlyActors.QA_MANAGER,
                qaAdmin: TenderlyActors.QA_ADMIN,
                timelockProposer: TenderlyActors.TIMELOCK_PROPOSER,
                timelockExecutor: TenderlyActors.TIMELOCK_EXECUTOR,
                timelockAdmin: TenderlyActors.TIMELOCK_ADMIN
            });
        } else if (chainId == 8453) {
            return AllActors({
                foundationSafe1: MainnetActors.FOUNDATION_SAFE_1,
                foundationSafe2: MainnetActors.FOUNDATION_SAFE_2,
                securityCouncil: MainnetActors.SECURITY_COUNCIL_SAFE,
                rewardsSafe: MainnetActors.REWARDS_SAFE,
                rewardsManager: MainnetActors.REWARDS_MANAGER,
                qaManager: MainnetActors.QA_MANAGER,
                qaAdmin: MainnetActors.QA_ADMIN,
                timelockProposer: MainnetActors.TIMELOCK_PROPOSER,
                timelockExecutor: MainnetActors.TIMELOCK_EXECUTOR,
                timelockAdmin: MainnetActors.TIMELOCK_ADMIN
            });
        }
        revert("Unsupported chain");
    }
}
