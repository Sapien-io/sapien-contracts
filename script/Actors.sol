// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

// Struct definitions for cleaner function returns
struct CoreActors {
    address foundationSafe1;
    address foundationSafe2;
    address securityCouncil;
    address blended;
    address sapienLabs;
}

struct AllActors {
    address rewardsAdmin;
    address rewardsManager;
    address qaManager;
    address qaSigner;
    address pauser;
    address timelockProposer;
    address timelockExecutor;
    address timelockCanceller;
    address timelockAdmin;
    address deployer;
}

library LocalActors {
    address public constant FOUNDATION_SAFE_1 = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;
    address public constant FOUNDATION_SAFE_2 = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8;
    address public constant SECURITY_COUNCIL_SAFE = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC;
    address public constant SAPIEN_LABS = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant BLENDED = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant REWARDS_ADMIN = 0x90F79bf6EB2c4f870365E785982E1f101E93b906;
    address public constant REWARDS_MANAGER = 0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65;
    address public constant QA_MANAGER = 0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc;
    address public constant QA_SIGNER = 0x976EA74026E726554dB657fA54763abd0C3a0aa9;
    address public constant PAUSER = 0xBcd4042DE499D14e55001CcbB24a551F3b954096;
    address public constant TIMELOCK_PROPOSER = 0x14dC79964da2C08b23698B3D3cc7Ca32193d9955;
    address public constant TIMELOCK_EXECUTOR = 0x23618e81E3f5cdF7f54C3d65f7FBc0aBf5B21E8f;
    address public constant TIMELOCK_CANCELLER = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant TIMELOCK_ADMIN = 0xa0Ee7A142d267C1f36714E4a8F75612F20a79720;
    address public constant DEPLOYER = 0x09F4897735f3Ec9Af6C2dda49d97D454B7dD1e59;
}

library SepoliaActors {
    address public constant FOUNDATION_SAFE_1 = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant FOUNDATION_SAFE_2 = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant SECURITY_COUNCIL_SAFE = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant SAPIEN_LABS = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant BLENDED = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant REWARDS_ADMIN = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant REWARDS_MANAGER = 0x2420aaA81708073501609934171ecfeAd818795f;
    address public constant QA_MANAGER = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant QA_SIGNER = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant PAUSER = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant TIMELOCK_PROPOSER = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant TIMELOCK_EXECUTOR = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant TIMELOCK_CANCELLER = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant TIMELOCK_ADMIN = 0x5602be03ecFfBB85D12b7404d4B38AF58277E4cC;
    address public constant DEPLOYER = 0x09F4897735f3Ec9Af6C2dda49d97D454B7dD1e59;
}

library TenderlyActors {
    // The primary Foundation safe that controls the assets / treasury
    address public constant FOUNDATION_SAFE_1 = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant FOUNDATION_SAFE_2 = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant SECURITY_COUNCIL_SAFE = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant SAPIEN_LABS = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant BLENDED = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant REWARDS_ADMIN = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant REWARDS_MANAGER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant QA_MANAGER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant QA_SIGNER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant PAUSER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant TIMELOCK_PROPOSER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant TIMELOCK_EXECUTOR = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant TIMELOCK_CANCELLER = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant TIMELOCK_ADMIN = 0x0C6F86b338417B3b7FCB9B344DECC51d072919c9;
    address public constant DEPLOYER = 0x09F4897735f3Ec9Af6C2dda49d97D454B7dD1e59;
}

library MainnetActors {
    address public constant FOUNDATION_SAFE_1 = 0x0e8b34E70AA583D937e5bF407738f2C8fF4D371C;
    address public constant FOUNDATION_SAFE_2 = 0x5DF0dcEdBE2E2Ae8604425b1913D02E98fC72660;
    address public constant BLENDED = 0xE60E46b8674018fd2Bb2924451dEB2F9e34fD1AC;
    address public constant SECURITY_COUNCIL_SAFE = 0x18D33278be0870A4907922dE65D6FbE27928580a;
    address public constant SAPIEN_LABS = 0x454149F78630A82fDcf5559384042A3BBD358FB2;
    address public constant REWARDS_ADMIN = MainnetActors.SAPIEN_LABS;
    address public constant REWARDS_MANAGER = 0xc0B4A5b6557E32Cf1ae85A875E6f9CeD402688be;
    address public constant QA_MANAGER = 0x1dd0f5712ff9Bd7be4996e5FA6c55a45c5eF4425;
    address public constant QA_SIGNER = 0x84021735702863386646eBCEFa0925B92afD52e1;
    address public constant PAUSER = MainnetActors.SECURITY_COUNCIL_SAFE;
    address public constant TIMELOCK_PROPOSER = MainnetActors.SECURITY_COUNCIL_SAFE;
    address public constant TIMELOCK_EXECUTOR = MainnetActors.SAPIEN_LABS;
    address public constant TIMELOCK_CANCELLER = MainnetActors.SECURITY_COUNCIL_SAFE;
    address public constant TIMELOCK_ADMIN = MainnetActors.BLENDED;
    address public constant DEPLOYER = 0x644B290c29C02A011Ef69DDf01DeEF4eEc8047A3;
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
                blended: LocalActors.BLENDED,
                sapienLabs: LocalActors.SAPIEN_LABS
            });
        } else if (block.chainid == 84532) {
            // Sepolia testnet
            return CoreActors({
                foundationSafe1: SepoliaActors.FOUNDATION_SAFE_1,
                foundationSafe2: SepoliaActors.FOUNDATION_SAFE_2,
                securityCouncil: SepoliaActors.SECURITY_COUNCIL_SAFE,
                blended: SepoliaActors.BLENDED,
                sapienLabs: SepoliaActors.SAPIEN_LABS
            });
        } else if (block.chainid == 8453420) {
            // Tenderly virtual testnet
            return CoreActors({
                foundationSafe1: TenderlyActors.FOUNDATION_SAFE_1,
                foundationSafe2: TenderlyActors.FOUNDATION_SAFE_2,
                securityCouncil: TenderlyActors.SECURITY_COUNCIL_SAFE,
                blended: TenderlyActors.BLENDED,
                sapienLabs: TenderlyActors.SAPIEN_LABS
            });
        } else if (block.chainid == 8453) {
            // Base mainnet
            return CoreActors({
                foundationSafe1: MainnetActors.FOUNDATION_SAFE_1,
                foundationSafe2: MainnetActors.FOUNDATION_SAFE_2,
                securityCouncil: MainnetActors.SECURITY_COUNCIL_SAFE,
                blended: MainnetActors.BLENDED,
                sapienLabs: MainnetActors.SAPIEN_LABS
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
                rewardsAdmin: LocalActors.REWARDS_ADMIN,
                rewardsManager: LocalActors.REWARDS_MANAGER,
                qaManager: LocalActors.QA_MANAGER,
                qaSigner: LocalActors.QA_SIGNER,
                pauser: LocalActors.PAUSER,
                timelockProposer: LocalActors.TIMELOCK_PROPOSER,
                timelockExecutor: LocalActors.TIMELOCK_EXECUTOR,
                timelockCanceller: LocalActors.TIMELOCK_CANCELLER,
                timelockAdmin: LocalActors.TIMELOCK_ADMIN,
                deployer: LocalActors.DEPLOYER
            });
        } else if (block.chainid == 84532) {
            return AllActors({
                rewardsAdmin: SepoliaActors.REWARDS_ADMIN,
                rewardsManager: SepoliaActors.REWARDS_MANAGER,
                qaManager: SepoliaActors.QA_MANAGER,
                qaSigner: SepoliaActors.QA_SIGNER,
                pauser: SepoliaActors.PAUSER,
                timelockProposer: SepoliaActors.TIMELOCK_PROPOSER,
                timelockExecutor: SepoliaActors.TIMELOCK_EXECUTOR,
                timelockCanceller: SepoliaActors.TIMELOCK_CANCELLER,
                timelockAdmin: SepoliaActors.TIMELOCK_ADMIN,
                deployer: SepoliaActors.DEPLOYER
            });
        } else if (block.chainid == 8453420) {
            return AllActors({
                rewardsAdmin: TenderlyActors.REWARDS_ADMIN,
                rewardsManager: TenderlyActors.REWARDS_MANAGER,
                qaManager: TenderlyActors.QA_MANAGER,
                qaSigner: TenderlyActors.QA_SIGNER,
                pauser: TenderlyActors.PAUSER,
                timelockProposer: TenderlyActors.TIMELOCK_PROPOSER,
                timelockExecutor: TenderlyActors.TIMELOCK_EXECUTOR,
                timelockCanceller: TenderlyActors.TIMELOCK_CANCELLER,
                timelockAdmin: TenderlyActors.TIMELOCK_ADMIN,
                deployer: TenderlyActors.DEPLOYER
            });
        } else if (block.chainid == 8453) {
            return AllActors({
                rewardsAdmin: MainnetActors.REWARDS_ADMIN,
                rewardsManager: MainnetActors.REWARDS_MANAGER,
                qaManager: MainnetActors.QA_MANAGER,
                qaSigner: MainnetActors.QA_SIGNER,
                pauser: MainnetActors.PAUSER,
                timelockProposer: MainnetActors.TIMELOCK_PROPOSER,
                timelockExecutor: MainnetActors.TIMELOCK_EXECUTOR,
                timelockCanceller: MainnetActors.TIMELOCK_CANCELLER,
                timelockAdmin: MainnetActors.TIMELOCK_ADMIN,
                deployer: MainnetActors.DEPLOYER
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
                rewardsAdmin: LocalActors.REWARDS_ADMIN,
                rewardsManager: LocalActors.REWARDS_MANAGER,
                qaManager: LocalActors.QA_MANAGER,
                qaSigner: LocalActors.QA_SIGNER,
                pauser: LocalActors.PAUSER,
                timelockProposer: LocalActors.TIMELOCK_PROPOSER,
                timelockExecutor: LocalActors.TIMELOCK_EXECUTOR,
                timelockCanceller: LocalActors.TIMELOCK_CANCELLER,
                timelockAdmin: LocalActors.TIMELOCK_ADMIN,
                deployer: LocalActors.DEPLOYER
            });
        } else if (chainId == 84532) {
            return AllActors({
                rewardsAdmin: SepoliaActors.REWARDS_ADMIN,
                rewardsManager: SepoliaActors.REWARDS_MANAGER,
                qaManager: SepoliaActors.QA_MANAGER,
                qaSigner: SepoliaActors.QA_SIGNER,
                pauser: SepoliaActors.PAUSER,
                timelockProposer: SepoliaActors.TIMELOCK_PROPOSER,
                timelockExecutor: SepoliaActors.TIMELOCK_EXECUTOR,
                timelockCanceller: SepoliaActors.TIMELOCK_CANCELLER,
                timelockAdmin: SepoliaActors.TIMELOCK_ADMIN,
                deployer: SepoliaActors.DEPLOYER
            });
        } else if (chainId == 8453420) {
            return AllActors({
                rewardsAdmin: TenderlyActors.REWARDS_ADMIN,
                rewardsManager: TenderlyActors.REWARDS_MANAGER,
                qaManager: TenderlyActors.QA_MANAGER,
                qaSigner: TenderlyActors.QA_SIGNER,
                pauser: TenderlyActors.PAUSER,
                timelockProposer: TenderlyActors.TIMELOCK_PROPOSER,
                timelockExecutor: TenderlyActors.TIMELOCK_EXECUTOR,
                timelockCanceller: TenderlyActors.TIMELOCK_CANCELLER,
                timelockAdmin: TenderlyActors.TIMELOCK_ADMIN,
                deployer: TenderlyActors.DEPLOYER
            });
        } else if (chainId == 8453) {
            return AllActors({
                rewardsAdmin: MainnetActors.REWARDS_ADMIN,
                rewardsManager: MainnetActors.REWARDS_MANAGER,
                qaManager: MainnetActors.QA_MANAGER,
                qaSigner: MainnetActors.QA_SIGNER,
                pauser: MainnetActors.PAUSER,
                timelockProposer: MainnetActors.TIMELOCK_PROPOSER,
                timelockExecutor: MainnetActors.TIMELOCK_EXECUTOR,
                timelockCanceller: MainnetActors.TIMELOCK_CANCELLER,
                timelockAdmin: MainnetActors.TIMELOCK_ADMIN,
                deployer: MainnetActors.DEPLOYER
            });
        }
        revert("Unsupported chain");
    }
}
