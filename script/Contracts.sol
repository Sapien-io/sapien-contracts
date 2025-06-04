// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

library LocalContracts {
    address public constant SAPIEN_TOKEN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_VAULT = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_REWARDS = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_QA = 0x0000000000000000000000000000000000000000;
    address public constant MULTIPLIER = 0x0000000000000000000000000000000000000000;
    address public constant TIMELOCK = 0x0000000000000000000000000000000000000000;
}

library TenderlyContracts {
    address public constant SAPIEN_TOKEN = 0xd3a8f3e472efB7246a5C3c604Aa034b6CDbE702F;
    address public constant SAPIEN_VAULT = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_REWARDS = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_QA = 0x5ed9315ab0274B0C546b71ed5a7ABE9982FF1E8D;
    address public constant MULTIPLIER = 0x4Fd7836c7C3Cb0EE140F50EeaEceF1Cbe19D8b55;
    address public constant TIMELOCK = 0xAABc9b2DF2Ed11A3f94b011315Beba0ea7fB7D09;
}

library SepoliaContracts {
    address public constant SAPIEN_TOKEN = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_VAULT = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_REWARDS = 0x0000000000000000000000000000000000000000;
    address public constant SAPIEN_QA = 0x0000000000000000000000000000000000000000;
    address public constant MULTIPLIER = 0x0000000000000000000000000000000000000000;
    address public constant TIMELOCK = 0x0000000000000000000000000000000000000000;
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
    function get()
        internal
        view
        returns (
            address SAPIEN_TOKEN,
            address SAPIEN_VAULT,
            address SAPIEN_REWARDS,
            address SAPIEN_QA,
            address MULTIPLIER,
            address TIMELOCK
        )
    {
        if (block.chainid == 31337) {
            return (
                LocalContracts.SAPIEN_TOKEN,
                LocalContracts.SAPIEN_VAULT,
                LocalContracts.SAPIEN_REWARDS,
                LocalContracts.SAPIEN_QA,
                LocalContracts.MULTIPLIER,
                LocalContracts.TIMELOCK
            );
        } else if (block.chainid == 84532) {
            return (
                SepoliaContracts.SAPIEN_TOKEN,
                SepoliaContracts.SAPIEN_VAULT,
                SepoliaContracts.SAPIEN_REWARDS,
                SepoliaContracts.SAPIEN_QA,
                SepoliaContracts.MULTIPLIER,
                SepoliaContracts.TIMELOCK
            );
        } else if (block.chainid == 8453420) {
            return (
                TenderlyContracts.SAPIEN_TOKEN,
                TenderlyContracts.SAPIEN_VAULT,
                TenderlyContracts.SAPIEN_REWARDS,
                TenderlyContracts.SAPIEN_QA,
                TenderlyContracts.MULTIPLIER,
                TenderlyContracts.TIMELOCK
            );
        } else if (block.chainid == 8453) {
            return (
                MainnetContracts.SAPIEN_TOKEN,
                MainnetContracts.SAPIEN_VAULT,
                MainnetContracts.SAPIEN_REWARDS,
                MainnetContracts.SAPIEN_QA,
                MainnetContracts.MULTIPLIER,
                MainnetContracts.TIMELOCK
            );
        }
        revert("Unsupported chain");
    }
}
