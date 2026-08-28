// SPDX-License-Identifier: MIT
pragma solidity ^0.8.36;

import {Vm} from "forge-std/Vm.sol";

/// @notice Off-chain `report.stake` fields the engine (poq-monorepo #1760) will
///         write after a Sepolia review. The vault never computes these; tests
///         and observers use them to check Basescan against the signed report.
library CollateralReport {
    /// @dev Foundry VM address (same as `Test.vm`).
    Vm internal constant VM = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    struct Stake {
        /// @dev `stake.slashed_wei` — `"0"` on unlock; the `slashStake` asset
        ///      amount (also `StakeSlashed.amount`) on slash.
        uint256 slashedWei;
        /// @dev `stake.stake_at_risk_wei` — `getStakeAccount(user).lockedAmount`
        ///      at review time, before unlock or slash.
        uint256 stakeAtRiskWei;
    }

    /// @notice Accepted review: engine calls `unlockStake`; nothing is burned.
    function accepted(uint256 lockedAtReview) internal pure returns (Stake memory) {
        return Stake({slashedWei: 0, stakeAtRiskWei: lockedAtReview});
    }

    /// @notice Forced review: engine calls `slashStake`; `slashedWei` is the
    ///         intended net asset damage (the `amount` argument / `StakeSlashed`).
    function slashed(uint256 burnedAssets, uint256 lockedAtReview) internal pure returns (Stake memory) {
        return Stake({slashedWei: burnedAssets, stakeAtRiskWei: lockedAtReview});
    }

    /// @notice Basescan Sepolia URL an HTML report can use for the slash tx.
    function sepoliaTxUrl(bytes32 txHash) internal pure returns (string memory) {
        return string.concat("https://sepolia.basescan.org/tx/", VM.toString(txHash));
    }
}
