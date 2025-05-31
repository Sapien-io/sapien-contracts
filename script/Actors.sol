// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

library LocalActors {
    // The primary Foundation safe that controls the assets / treasury
    address public constant FOUNDATION_SAFE_1 = address(0x01);

    // The secondary Foundation safe
    address public constant FOUNDATION_SAFE_2 = address(0x02);

    // The Blended Safe of the Foundation and operational teams
    address public constant SECURITY_COUNCIL_SAFE = address(0x03);

    // The safe the holds the Contributor Rewards
    address public constant REWARDS_SAFE = address(0x04);

    // The EOA that signs Reward claim attestations
    address public constant REWARDS_MANAGER = address(0x05);
}

library SepoliaActors {
    // The primary Foundation safe that controls the assets / treasury
    address public constant FOUNDATION_SAFE_1 = address(0x01);

    // The secondary Foundation safe
    address public constant FOUNDATION_SAFE_2 = address(0x02);

    // The Blended Safe of the Foundation and operational teams
    address public constant SECURITY_COUNCIL_SAFE = address(0x03);

    // The safe the holds the Contributor Rewards
    address public constant REWARDS_SAFE = address(0x04);

    // The EOA that signs Reward claim attestations
    address public constant REWARDS_MANAGER = address(0x05);
}

library MainnetActors {
    // The primary Foundation safe that controls the assets / treasury
    address public constant FOUNDATION_SAFE_1 = address(0x01);

    // The secondary Foundation safe
    address public constant FOUNDATION_SAFE_2 = address(0x02);

    // The Blended Safe of the Foundation and operational teams
    address public constant SECURITY_COUNCIL_SAFE = address(0x03);

    // The safe the holds the Contributor Rewards
    address public constant REWARDS_SAFE = address(0x04);

    // The EOA that signs Reward claim attestations
    address public constant REWARDS_MANAGER = address(0x05);
}

library Actors {
    function getActors()
        internal
        view
        returns (
            address foundationSafe1,
            address foundationSafe2,
            address securityCouncil,
            address rewardsSafe,
            address rewardsManager
        )
    {
        if (block.chainid == 31337) {
            // Local development chain
            return (
                LocalActors.FOUNDATION_SAFE_1,
                LocalActors.FOUNDATION_SAFE_2,
                LocalActors.SECURITY_COUNCIL_SAFE,
                LocalActors.REWARDS_SAFE,
                LocalActors.REWARDS_MANAGER
            );
        } else if (block.chainid == 84532) {
            // Sepolia testnet
            return (
                SepoliaActors.FOUNDATION_SAFE_1,
                SepoliaActors.FOUNDATION_SAFE_2,
                SepoliaActors.SECURITY_COUNCIL_SAFE,
                SepoliaActors.REWARDS_SAFE,
                SepoliaActors.REWARDS_MANAGER
            );
        } else if (block.chainid == 8453) {
            // Ethereum mainnet
            return (
                MainnetActors.FOUNDATION_SAFE_1,
                MainnetActors.FOUNDATION_SAFE_2,
                MainnetActors.SECURITY_COUNCIL_SAFE,
                MainnetActors.REWARDS_SAFE,
                MainnetActors.REWARDS_MANAGER
            );
        }
        revert("Unsupported chain");
    }
}
