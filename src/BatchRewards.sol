// SPDX-License-Identifier: BSD-3-Clause
pragma solidity 0.8.30;

import {ISapienRewards} from "src/interfaces/ISapienRewards.sol";
import {ReentrancyGuard} from "lib/openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";

contract BatchRewards is ReentrancyGuard {

    error ZeroAddress();

    ISapienRewards public immutable sapienRewards;
    ISapienRewards public immutable usdcRewards;

    constructor(ISapienRewards _sapienRewards, ISapienRewards _usdcRewards) {
        if (address(_sapienRewards) == address(0) || address(_usdcRewards) == address(0)) revert ZeroAddress();
        sapienRewards = _sapienRewards;
        usdcRewards = _usdcRewards;
    }

    /**
     * @notice Claims rewards from both the Sapien and USDC rewards contracts in a single transaction.
     * @dev Calls `claimRewardFor` on both the `sapienRewards` and `usdcRewards` contracts.
     *      Tokens are sent directly to the caller (msg.sender).
     * @param sapienRewardAmount The amount of Sapien rewards to claim.
     * @param sapienOrderId The unique order ID for the Sapien reward claim.
     * @param sapienSignature The signature authorizing the Sapien reward claim.
     * @param usdcRewardAmount The amount of USDC rewards to claim.
     * @param usdcOrderId The unique order ID for the USDC reward claim.
     * @param usdcSignature The signature authorizing the USDC reward claim.
     */
    function batchClaimRewards(
        uint256 sapienRewardAmount,
        bytes32 sapienOrderId,
        bytes memory sapienSignature,
        uint256 usdcRewardAmount,
        bytes32 usdcOrderId,
        bytes memory usdcSignature
    ) public nonReentrant {
        // Claim rewards - tokens go directly to msg.sender
        if (sapienRewardAmount > 0) {
            sapienRewards.claimRewardFor(msg.sender, sapienRewardAmount, sapienOrderId, sapienSignature);
        }
        if (usdcRewardAmount > 0) {
            usdcRewards.claimRewardFor(msg.sender, usdcRewardAmount, usdcOrderId, usdcSignature);
        }
    }
}