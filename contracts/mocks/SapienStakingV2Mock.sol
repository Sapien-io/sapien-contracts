// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "../SapienStaking.sol";

contract SapienStakingV2Mock is SapienStaking {
  function getVersion() external pure returns (string memory) {
    return "2.0"; 
  }
}


