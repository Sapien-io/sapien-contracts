// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

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
    function get()
        internal
        view
        returns (
            address FOUNDATION_SAFE_1,
            address FOUNDATION_SAFE_2,
            address SECURITY_COUNCIL_SAFE,
            address REWARDS_SAFE,
            address REWARDS_MANAGER,
            address QA_MANAGER,
            address QA_ADMIN,
            address TIMELOCK_PROPOSER,
            address TIMELOCK_EXECUTOR,
            address TIMELOCK_ADMIN
        )
    {
        if (block.chainid == 31337) {
            return (
                LocalActors.FOUNDATION_SAFE_1,
                LocalActors.FOUNDATION_SAFE_2,
                LocalActors.SECURITY_COUNCIL_SAFE,
                LocalActors.REWARDS_SAFE,
                LocalActors.REWARDS_MANAGER,
                LocalActors.QA_MANAGER,
                LocalActors.QA_ADMIN,
                LocalActors.TIMELOCK_PROPOSER,
                LocalActors.TIMELOCK_EXECUTOR,
                LocalActors.TIMELOCK_ADMIN
            );
        } else if (block.chainid == 84532) {
            return (
                SepoliaActors.FOUNDATION_SAFE_1,
                SepoliaActors.FOUNDATION_SAFE_2,
                SepoliaActors.SECURITY_COUNCIL_SAFE,
                SepoliaActors.REWARDS_SAFE,
                SepoliaActors.REWARDS_MANAGER,
                SepoliaActors.QA_MANAGER,
                SepoliaActors.QA_ADMIN,
                SepoliaActors.TIMELOCK_PROPOSER,
                SepoliaActors.TIMELOCK_EXECUTOR,
                SepoliaActors.TIMELOCK_ADMIN
            );
        } else if (block.chainid == 8453420) {
            return (
                TenderlyActors.FOUNDATION_SAFE_1,
                TenderlyActors.FOUNDATION_SAFE_2,
                TenderlyActors.SECURITY_COUNCIL_SAFE,
                TenderlyActors.REWARDS_SAFE,
                TenderlyActors.REWARDS_MANAGER,
                TenderlyActors.QA_MANAGER,
                TenderlyActors.QA_ADMIN,
                TenderlyActors.TIMELOCK_PROPOSER,
                TenderlyActors.TIMELOCK_EXECUTOR,
                TenderlyActors.TIMELOCK_ADMIN
            );
        } else if (block.chainid == 8453) {
            return (
                MainnetActors.FOUNDATION_SAFE_1,
                MainnetActors.FOUNDATION_SAFE_2,
                MainnetActors.SECURITY_COUNCIL_SAFE,
                MainnetActors.REWARDS_SAFE,
                MainnetActors.REWARDS_MANAGER,
                MainnetActors.QA_MANAGER,
                MainnetActors.QA_ADMIN,
                MainnetActors.TIMELOCK_PROPOSER,
                MainnetActors.TIMELOCK_EXECUTOR,
                TenderlyActors.TIMELOCK_ADMIN
            );
        }
        revert("Unsupported chain");
    }
}
