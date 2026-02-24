// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {BaseTest} from "test/BaseTest.sol";
import {ISapienCore} from "src/interfaces/ISapienCore.sol";

/// @title SEC-L-02: Redundant zero-check after zero-revert
/// @notice Proves that the `if (stakeAmount > 0)` guard in commitValidation is dead code
///         because stakeAmount == 0 already reverts earlier with InsufficientStake.
contract SEC_L_02_RedundantZeroCheck is BaseTest {
    function test_zeroStakeRevertsBeforeRedundantGuard() public {
        bytes32 projectId = _createAndFundProject();

        (, uint256[] memory indices) = _claimAndContribute(contributor1, projectId, 1);
        uint256 idx = indices[0];

        bytes32 salt = keccak256(abi.encodePacked("salt", validator1, idx));
        bytes32 commitHash = keccak256(abi.encodePacked(uint256(8000), salt));

        vm.startPrank(validator1);
        {
            uint256[] memory _indices = new uint256[](1);
            _indices[0] = idx;
            engine.claimToValidate(projectId, _indices);
        }
        engine.lockValidatorCapacity(VALIDATOR_STAKE);

        // stakeAmount = 0 reverts with InsufficientStake(1, 0)
        // The later `if (stakeAmount > 0) { vault.commitStake(...) }` is never reached
        vm.expectRevert(abi.encodeWithSelector(ISapienCore.InsufficientStake.selector, 1, 0));
        engine.commitValidation(projectId, idx, commitHash, 0, address(0));
        vm.stopPrank();
    }
}
