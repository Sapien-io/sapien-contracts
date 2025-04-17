// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../SapienRewards.sol";

contract SapienRewardsV2Mock is SapienRewards {
    function getVersion() external pure returns (string memory) {
        return "2.0";
    }
} 
